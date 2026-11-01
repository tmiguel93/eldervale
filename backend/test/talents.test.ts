import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { loadClassCatalogFromDisk } from "../src/characters/classes.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { loadRecipeCatalogFromDisk } from "../src/crafting/catalog.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { loadQuestCatalogFromDisk } from "../src/quests/catalog.ts";
import { createTalentCatalog, loadTalentCatalogFromDisk, TALENTS_JSON_URL } from "../src/talents/catalog.ts";
import { checkAllocate, normalizeStoredTalents, pointsSpent } from "../src/talents/rules.ts";
import { totalXpForLevel } from "../src/characters/progression.ts";
import { PgErrorCode } from "../src/persistence/db.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const items = loadCatalogFromDisk();
const classes = loadClassCatalogFromDisk();
const cat = loadTalentCatalogFromDisk(items, classes);
const cfg = testConfig({ GAME_SESSION_INTERNAL_SECRET: "internal-secret-for-tests-0123456789abcdef" });

let db: Db;
let app: App;
let seq = 0;
beforeAll(async () => {
  db = await freshDb();
  app = createApp({
    config: cfg, db, log: createLogger({ level: "error" }),
    authVerifier: async (t) => (t.startsWith("tok-") ? { accountId: t.slice(4) } : null),
    register: (r, d) => registerCharactersRoutes(r, d, { catalog: items, limits: DEFAULT_LIMITS, quests: loadQuestCatalogFromDisk(items), recipes: loadRecipeCatalogFromDisk(items), classes, talents: cat }),
  });
});
afterAll(async () => { await db.close(); });

async function call(method: string, path: string, o: { as?: string; internal?: boolean; body?: unknown; session?: string } = {}) {
  const headers: Record<string, string> = {};
  if (o.as) headers.authorization = `Bearer tok-${o.as}`;
  if (o.internal) headers.authorization = `Bearer ${cfg.gameSessionInternalSecret}`;
  if (o.body !== undefined) headers["content-type"] = "application/json";
  if (o.session) headers["x-session-id"] = o.session;
  const res = await app.handle(new Request(`http://t${path}`, { method, headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }));
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}
const code = (r: { json: any }): string => r.json?.error?.code ?? r.json?.code;

type Ch = { id: string; sid: string; acc: string };
async function mkChar(level: number, class_id = "warrior"): Promise<Ch> {
  const acc = await mkAccount(db, `t${++seq}@example.com`);
  const r = await call("POST", "/v1/characters", { as: acc, body: { name: `Talent${seq}`, class_id } });
  expect(r.status).toBe(201);
  const id = r.json.character.id as string;
  const sid = await mkSession(db);
  await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [id, sid]);
  await db.query("UPDATE characters SET level = $2, xp = $3 WHERE id = $1", [id, level, totalXpForLevel(level)]);
  return { id, sid, acc };
}
const getC = (id: string) => call("GET", `/internal/characters/${id}`, { internal: true }).then((r) => r.json.character);
let keyN = 0;
const tkey = (c: Ch) => `talent:${c.sid}:${++keyN}:${c.id}`;
const cmd = (c: Ch, op: string, arg?: string, extra: Record<string, unknown> = {}, key = tkey(c)) =>
  call("POST", `/internal/characters/${c.id}/talents`, { internal: true, session: c.sid, body: { idempotency_key: key, op, ...(arg !== undefined ? { arg } : {}), ...extra } });

describe("catalogo de talentos", () => {
  it("carrega do disco, bate com as classes e esta em dia com data/talents", () => {
    expect(cat.classIds().sort()).toEqual(["mage", "ranger", "warrior"]);
    expect(cat.tree("warrior")!.specs).toEqual(["berserker"]);
    expect(cat.pointsForLevel(1)).toBe(0);
    expect(cat.pointsForLevel(2)).toBe(1);
    expect(cat.pointsForLevel(10)).toBe(9);
    expect(cat.pointsForLevel(500)).toBe(cat.points.max_points);
    const root = fileURLToPath(new URL("../..", import.meta.url));
    expect(execFileSync(process.execPath, ["tools/gen_talents_catalog.mjs", "--check"], { cwd: root, encoding: "utf8" })).toMatch(/em dia/);
  });

  it("rejeita catalogo invalido (ciclo, requisito inexistente, spec, item do respec)", () => {
    const raw = JSON.parse(readFileSync(TALENTS_JSON_URL, "utf8"));
    const mut = (f: (r: any) => void) => () => { const c = structuredClone(raw); f(c); createTalentCatalog(c, items, classes); };
    expect(mut(() => {})).not.toThrow();
    expect(mut((r) => { r.schema_version = 2; })).toThrow(/schema_version/);
    expect(mut((r) => { r.trees[0].nodes[0].requires = [r.trees[0].nodes[0].id]; })).toThrow(/requisito/);
    expect(mut((r) => { r.trees[0].nodes[0].requires = ["nao_existe"]; })).toThrow(/requisito/);
    expect(mut((r) => { const n = r.trees[0].nodes; n[0].requires = [n[1].id]; n[1].requires = [n[0].id]; })).toThrow(/ciclo/);
    expect(mut((r) => { r.trees[0].nodes[0].spec = "outra"; })).toThrow(/spec/);
    expect(mut((r) => { r.trees[0].nodes[0].max_rank = 99; })).toThrow(/max_rank/);
    expect(mut((r) => { r.respec.cost_items = [{ item_id: "ouro_fake", qty: 1 }]; })).toThrow(/desconhecido/);
    expect(mut((r) => { r.trees[0].class_id = "paladin"; })).toThrow(/classe/);
    expect(mut((r) => { r.trees.pop(); })).toThrow(/sem arvore/);
  });

  it("normalizeStoredTalents e leniente; checkAllocate segue a ordem de erros", () => {
    const tree = cat.tree("warrior")!;
    expect(normalizeStoredTalents(null)).toEqual({ spec: "", ranks: {}, respecs: 0 });
    expect(normalizeStoredTalents({ spec: "berserker", ranks: { w_vigor: 4, ghost: 1, b_rage: 1 }, respecs: -1 }, tree))
      .toEqual({ spec: "berserker", ranks: { w_vigor: 3, b_rage: 1 }, respecs: 0 });
    expect(normalizeStoredTalents({ spec: "x", ranks: { b_rage: 1 } }, tree)).toEqual({ spec: "", ranks: {}, respecs: 0 });
    const st = { spec: "", ranks: {}, respecs: 0 };
    expect(checkAllocate(tree, st, 5, "nope", cat)).toBe("unknown_node");
    expect(checkAllocate(tree, st, 5, "b_bloodlust", cat)).toBe("spec_not_chosen");
    expect(checkAllocate(tree, { ...st, ranks: { w_vigor: 3 } }, 5, "w_vigor", cat)).toBe("max_rank");
    expect(checkAllocate(tree, st, 5, "w_iron_skin", cat)).toBe("prerequisite");
    expect(checkAllocate(tree, st, 1, "w_vigor", cat)).toBe("no_points");
    expect(pointsSpent(tree, { spec: "", ranks: { w_vigor: 2, w_heavy_focus: 1 }, respecs: 0 })).toBe(4);
  });
});

describe("migracao 0005", () => {
  it("coluna talents default {} e CHECK de objeto; reexecutar o SQL e idempotente", async () => {
    const c = await mkChar(1);
    const g = await getC(c.id);
    expect(g.talents).toEqual({ spec: "", ranks: {}, respecs: 0 });
    const raw = await db.query<{ talents: unknown }>("SELECT talents FROM characters WHERE id = $1", [c.id]);
    expect(raw.rows[0]!.talents).toEqual({});
    let pg: string | undefined;
    try { await db.query("UPDATE characters SET talents = '[1]'::jsonb WHERE id = $1", [c.id]); } catch (e) { pg = (e as { code?: string }).code; }
    expect(pg).toBe(PgErrorCode.checkViolation);
    const sql = readFileSync(new URL("../migrations/0005_character_talents.sql", import.meta.url), "utf8");
    await db.exec(sql); await db.exec(sql);
    expect((await getC(c.id)).talents.spec).toBe("");
  });
});

describe("POST /internal/characters/:id/talents", () => {
  it("escolhe spec, aloca respeitando pontos/prerequisitos/max_rank; erro nao grava nem consome chave", async () => {
    const c = await mkChar(5); // 4 pontos
    expect(code(await cmd(c, "allocate", "w_vigor"))).toBeUndefined();
    const r0 = await getC(c.id);
    expect(r0.talents.ranks).toEqual({ w_vigor: 1 });
    expect(code(await cmd(c, "allocate", "b_bloodlust"))).toBe("spec_not_chosen");
    expect(code(await cmd(c, "choose_spec", "mage_spec"))).toBe("unknown_spec");
    expect((await cmd(c, "choose_spec", "berserker")).status).toBe(200);
    expect(code(await cmd(c, "choose_spec", "berserker"))).toBe("spec_already_chosen");
    expect(code(await cmd(c, "allocate", "w_iron_skin"))).toBeUndefined();
    expect((await cmd(c, "allocate", "w_quick_roll")).status).toBe(200); // custo 2 -> 4 de 4 gastos
    expect(code(await cmd(c, "allocate", "w_might"))).toBe("no_points");
    const g = await getC(c.id);
    expect(g.talents).toEqual({ spec: "berserker", ranks: { w_vigor: 1, w_iron_skin: 1, w_quick_roll: 1 }, respecs: 0 });
    expect(code(await cmd(c, "allocate", "w_stamina", {}, "talent:bad"))).toBe("invalid_idempotency_key");
  });

  it("pre-requisito, max_rank, nivel e classe errada", async () => {
    const c = await mkChar(12);
    expect(code(await cmd(c, "allocate", "w_iron_skin"))).toBe("prerequisite");
    for (let i = 0; i < 3; i++) expect((await cmd(c, "allocate", "w_vigor")).status).toBe(200);
    expect(code(await cmd(c, "allocate", "w_vigor"))).toBe("max_rank");
    expect(code(await cmd(c, "allocate", "m_intellect"))).toBe("unknown_node"); // no de mago em guerreiro
    const mage = await mkChar(3, "mage");
    expect(code(await cmd(mage, "allocate", "w_vigor"))).toBe("unknown_node");
    expect((await cmd(mage, "allocate", "m_intellect")).status).toBe(200);
  });

  it("min_points_spent do no mestre", async () => {
    const c = await mkChar(30);
    await cmd(c, "choose_spec", "berserker");
    for (const n of ["w_might", "b_frenzy", "b_rage", "w_stamina", "w_wide_swing", "b_bloodlust", "b_cyclone"]) {
      expect((await cmd(c, "allocate", n)).status, n).toBe(200);
    }
    // gastos: 1+1+2+1+2+1+2 = 10 (< 12): requisitos de no ok, mas min_points_spent falha
    expect(code(await cmd(c, "allocate", "b_warlord"))).toBe("prerequisite");
    expect((await cmd(c, "allocate", "b_rage")).status).toBe(200); // 12
    expect((await cmd(c, "allocate", "b_warlord")).status).toBe(200);
  });

  it("idempotencia: replay devolve o mesmo resultado sem repetir; chave com outro conteudo = 409", async () => {
    const c = await mkChar(5);
    const k = tkey(c);
    const a = await cmd(c, "allocate", "w_vigor", {}, k);
    const b = await cmd(c, "allocate", "w_vigor", {}, k);
    expect(a.status).toBe(200);
    expect(b.json.replayed).toBe(true);
    expect(b.json.result).toEqual(a.json.result);
    expect((await getC(c.id)).talents.ranks).toEqual({ w_vigor: 1 });
    expect(code(await cmd(c, "allocate", "w_might", {}, k))).toBe("idempotency_key_reuse");
  });

  it("validacao de corpo, fencing de sessao e prefixo reservado", async () => {
    const c = await mkChar(5);
    const post = (body: unknown, session: string | undefined = c.sid) => call("POST", `/internal/characters/${c.id}/talents`, { internal: true, session, body });
    expect(code(await post({ idempotency_key: tkey(c), op: "nuke", arg: "x" }))).toBe("invalid_op");
    expect(code(await post({ idempotency_key: tkey(c), op: "allocate" }))).toBe("invalid_arg");
    expect(code(await post({ idempotency_key: tkey(c), op: "allocate", arg: "W VIGOR" }))).toBe("invalid_arg");
    expect(code(await post({ idempotency_key: tkey(c), op: "respec", arg: "x" }))).toBe("invalid_arg");
    expect((await post({ idempotency_key: tkey(c), op: "allocate", arg: "w_vigor", extra: 1 })).status).toBe(400);
    expect(code(await post({ idempotency_key: `talent:${c.sid}:1:${(await mkChar(1)).id}`, op: "allocate", arg: "w_vigor" }))).toBeDefined();
    const other = await mkSession(db);
    expect((await post({ idempotency_key: `talent:${other}:1:${c.id}`, op: "allocate", arg: "w_vigor" }, other)).status).toBeGreaterThanOrEqual(400);
    expect((await call("POST", `/internal/characters/${c.id}/talents`, { as: c.acc, body: { idempotency_key: tkey(c), op: "allocate", arg: "w_vigor" } })).status).toBeGreaterThanOrEqual(401);
    const rw = await call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, session: c.sid, body: { idempotency_key: `talent:${c.sid}:1:${c.id}`, xp: 1 } });
    expect(rw.status).toBe(400);
    expect((await getC(c.id)).talents.ranks).toEqual({});
  });

  it("revision: expected_revision divergente = 409 revision_conflict; correto passa", async () => {
    const c = await mkChar(5);
    const g = await getC(c.id);
    expect(code(await cmd(c, "allocate", "w_vigor", { expected_revision: g.revision + 5 }))).toBe("revision_conflict");
    const ok = await cmd(c, "allocate", "w_vigor", { expected_revision: g.revision });
    expect(ok.status).toBe(200);
    expect(ok.json.result.revision).toBe(g.revision + 1);
  });

  it("concorrencia: N comandos simultaneos nunca estouram os pontos", async () => {
    const c = await mkChar(3); // 2 pontos
    const rs = await Promise.all(["w_vigor", "w_might", "w_stamina", "w_vigor", "w_might"].map((n) => cmd(c, "allocate", n)));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(2);
    const g = await getC(c.id);
    expect(Object.values(g.talents.ranks as Record<string, number>).reduce((a, b) => a + b, 0)).toBe(2);
  });

  it("respec: consome o custo em itens, zera tudo, conta respecs; sem itens = 409 e nada muda", async () => {
    const c = await mkChar(5);
    await cmd(c, "choose_spec", "berserker");
    await cmd(c, "allocate", "w_vigor");
    expect(code(await cmd(c, "respec"))).toBe("insufficient_items");
    expect((await getC(c.id)).talents.ranks).toEqual({ w_vigor: 1 });
    const g = await getC(c.id);
    await db.query("UPDATE characters SET stats = stats WHERE id = $1", [c.id]);
    const state = { schema_version: g.schema_version, level: g.level, xp: g.xp, stats: g.stats, inventory: [{ slot: 0, item_id: "scrap_material", qty: 4 }], equipment: g.equipment };
    const cp = await call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, session: c.sid, body: { expected_revision: g.revision, state } });
    expect(cp.status).toBe(200);
    const r = await cmd(c, "respec");
    expect(r.status).toBe(200);
    const after = await getC(c.id);
    expect(after.talents).toEqual({ spec: "", ranks: {}, respecs: 1 });
    expect(after.inventory).toEqual([{ slot: 0, item_id: "scrap_material", qty: 1 }]);
    expect(code(await cmd(c, "respec"))).toBe("nothing_to_reset");
    expect((await cmd(c, "choose_spec", "berserker")).status).toBe(200);
  });

  it("checkpoint do servidor preserva talentos (nao os grava nem os apaga)", async () => {
    const c = await mkChar(5);
    await cmd(c, "allocate", "w_vigor");
    const g = await getC(c.id);
    const state = { schema_version: g.schema_version, level: g.level, xp: g.xp, stats: g.stats, inventory: [], equipment: g.equipment };
    const cp = await call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, session: c.sid, body: { expected_revision: g.revision, state } });
    expect(cp.status).toBe(200);
    const bad = await call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, session: c.sid, body: { expected_revision: g.revision + 1, state: { ...state, talents: { spec: "berserker", ranks: { b_warlord: 1 } } } } });
    expect(bad.status).toBe(422);
    expect((await getC(c.id)).talents.ranks).toEqual({ w_vigor: 1 });
    const pub = await call("GET", `/v1/characters/${c.id}`, { as: c.acc });
    expect(pub.json.character.talents.ranks).toEqual({ w_vigor: 1 });
  });
});
