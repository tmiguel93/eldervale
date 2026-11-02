import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { createClassCatalog, loadClassCatalogFromDisk } from "../src/characters/classes.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { BASE_STATS } from "../src/characters/model.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { PgErrorCode } from "../src/persistence/db.ts";
import { loadMigrations, migrate } from "../src/persistence/migrate.ts";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { loadQuestCatalogFromDisk } from "../src/quests/catalog.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const items = loadCatalogFromDisk();
const classes = loadClassCatalogFromDisk();
const cfg = testConfig({ GAME_SESSION_INTERNAL_SECRET: "internal-secret-for-tests-0123456789abcdef" });
const ROOT = fileURLToPath(new URL("../..", import.meta.url));

let db: Db;
let app: App;
let seq = 0;
beforeAll(async () => {
  db = await freshDb();
  app = createApp({
    config: cfg, db, log: createLogger({ level: "error" }),
    authVerifier: async (t) => (t.startsWith("tok-") ? { accountId: t.slice(4) } : null),
    register: (r, d) => registerCharactersRoutes(r, d, { catalog: items, limits: DEFAULT_LIMITS, quests: loadQuestCatalogFromDisk(items), classes }),
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
async function mk(classId: unknown) {
  const acc = await mkAccount(db, `c${++seq}@example.com`);
  const body: Record<string, unknown> = { name: `Classy${seq}` };
  if (classId !== undefined) body.class_id = classId;
  const r = await call("POST", "/v1/characters", { as: acc, body });
  return { acc, r };
}

describe("catalogo de classes", () => {
  it("carrega do disco: 3 classes jogaveis, warrior padrao, 1 especializacao inicial cada", () => {
    expect(classes.ids().sort()).toEqual(["mage", "ranger", "warrior"]);
    expect(classes.defaultId).toBe("warrior");
    for (const id of classes.ids()) {
      const c = classes.get(id)!;
      expect(c.specializations.filter((s) => !s.planned)).toHaveLength(1);
      expect(c.specializations).toHaveLength(3);
      expect(Object.keys(c.skills)).toEqual(["attack", "skill_1", "skill_2", "dodge"]);
    }
    expect(classes.get("mage")!.resource_kind).toBe("mana");
    expect(classes.get("warrior")!.resource_kind).toBe("stamina");
  });

  it("guerreiro = stats base historicos (saves existentes nao mudam)", () => {
    expect({ ...classes.get("warrior")!.base_stats }).toEqual({ ...BASE_STATS });
  });

  it("esta em dia com data/classes (gerador --check) e referencias de data/skills validas", () => {
    const out = execFileSync("node", ["tools/gen_classes_catalog.mjs", "--check"], { cwd: ROOT, encoding: "utf8" });
    expect(out).toContain("em dia");
  });

  it("gerador recusa classe quebrada (habilidade inexistente)", async () => {
    const mod = await import(`${ROOT}/tools/gen_classes_catalog.mjs`);
    const good = JSON.parse(readFileSync(`${ROOT}/data/classes/mage.json`, "utf8"));
    expect(mod.validateClass(good, "mage.json")).toEqual([]);
    expect(mod.validateClass({ ...good, id: "Mage" }, "mage.json").length).toBeGreaterThan(0);
    expect(mod.validateClass({ ...good, resource: { kind: "rage" } }, "mage.json").length).toBeGreaterThan(0);
    expect(mod.validateClass({ ...good, skills: { ...good.skills, dodge: undefined } }, "mage.json").length).toBeGreaterThan(0);
    expect(mod.validateClass({ ...good, specializations: good.specializations.map((s: any) => ({ ...s, planned: true })) }, "mage.json").length).toBeGreaterThan(0);
    expect(mod.validateClass({ ...good, base_stats: { ...good.base_stats, resistance: 0.9 } }, "mage.json").length).toBeGreaterThan(0);
    expect(mod.validateClass({ ...good, extra: 1 }, "mage.json").length).toBeGreaterThan(0);
    const idx = mod.skillIndex(ROOT);
    expect(idx.has("fireball") && idx.has("heavy_strike") && !idx.has("meteor_swarm")).toBe(true);
    const { errors } = mod.buildClassCatalog(ROOT);
    expect(errors).toEqual([]);
  });

  it("createClassCatalog rejeita JSON malformado", () => {
    const raw = JSON.parse(readFileSync(`${ROOT}/shared/content_schemas/classes.json`, "utf8"));
    expect(() => createClassCatalog(raw)).not.toThrow();
    const clone = () => JSON.parse(JSON.stringify(raw));
    const bad: Array<[string, (r: any) => void]> = [
      ["schema", (r) => { r.schema_version = 2; }],
      ["vazio", (r) => { r.classes = []; }],
      ["id", (r) => { r.classes[0].id = "Bad Id"; }],
      ["duplicado", (r) => { r.classes[1].id = r.classes[0].id; }],
      ["recurso", (r) => { r.classes[0].resource_kind = "rage"; }],
      ["stat", (r) => { r.classes[0].base_stats.max_health = -1; }],
      ["resistance", (r) => { r.classes[0].base_stats.resistance = 0.9; }],
      ["stat desconhecido", (r) => { r.classes[0].base_stats.luck = 1; }],
      ["skill", (r) => { delete r.classes[0].skills.dodge; }],
      ["skill repetida", (r) => { r.classes[0].skills.skill_1 = r.classes[0].skills.attack; }],
      ["spec", (r) => { r.classes[0].specializations = []; }],
      ["sem inicial", (r) => { r.classes[0].specializations.forEach((s: any) => { s.planned = true; }); }],
      ["sem padrao", (r) => { r.classes = r.classes.filter((c: any) => c.id !== "warrior"); }],
    ];
    for (const [name, mut] of bad) {
      const r = clone();
      mut(r);
      expect(() => createClassCatalog(r), name).toThrow();
    }
    expect(() => createClassCatalog(null)).toThrow();
    expect(() => createClassCatalog([])).toThrow();
  });
});

describe("migracao 0004 (class_id)", () => {
  it("do zero: default warrior, CHECK de formato, sem tocar linhas validas", async () => {
    const d = await createPgliteDb();
    const r = await migrate(d);
    expect(r.applied).toEqual([1, 2, 3, 4, 5, 6]);
    const acc = await mkAccount(d, "m0@example.com");
    const ins = await d.query<{ class_id: string }>("INSERT INTO characters (account_id, name) VALUES ($1, 'SemClasse') RETURNING class_id", [acc]);
    expect(ins.rows[0]!.class_id).toBe("warrior");
    for (const ok of ["mage", "ranger", "w", "arcane_knight2"]) {
      await d.query("INSERT INTO characters (account_id, name, class_id) VALUES ($1, $2, $3)", [acc, `ok_${ok}`, ok]);
    }
    for (const bad of ["Mage", "mage!", "", "1mage", "a".repeat(49), "has space"]) {
      let code: string | undefined;
      try { await d.query("INSERT INTO characters (account_id, name, class_id) VALUES ($1, $2, $3)", [acc, `bad_${bad.length}`, bad]); } catch (e) { code = (e as { code?: string }).code; }
      expect(code, bad).toBe(PgErrorCode.checkViolation);
    }
    await d.close();
  });

  it("a partir da versao anterior (0001-0003): preserva dados, normaliza so o malformado", async () => {
    const d = await createPgliteDb();
    const all = loadMigrations();
    expect(all).toHaveLength(6);
    const upto3 = await migrate(d, { migrations: all.slice(0, 3) });
    expect(upto3.applied).toEqual([1, 2, 3]);
    const acc = await mkAccount(d, "m3@example.com");
    const ids: Record<string, string> = {};
    for (const [name, cls] of [["Velho", "warrior"], ["Curto", "w"], ["Futuro", "paladin"], ["Torto", "Bad Class!"], ["Vazio", ""]] as const) {
      const r = await d.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id, level, xp, stats) VALUES ($1,$2,$3, 7, 1234, '{\"max_health\":100}'::jsonb) RETURNING id", [acc, name, cls]);
      ids[name] = r.rows[0]!.id;
    }
    const before = await d.query("SELECT id, level, xp, stats, revision, quests FROM characters ORDER BY name");
    const up = await migrate(d);
    expect(up.applied).toEqual([4, 5, 6]);
    const cls = async (n: string) => (await d.query<{ class_id: string }>("SELECT class_id FROM characters WHERE id = $1", [ids[n]!])).rows[0]!.class_id;
    expect(await cls("Velho")).toBe("warrior");
    expect(await cls("Curto")).toBe("w");
    expect(await cls("Futuro")).toBe("paladin");
    expect(await cls("Torto")).toBe("warrior");
    expect(await cls("Vazio")).toBe("warrior");
    const after = await d.query("SELECT id, level, xp, stats, revision, quests FROM characters ORDER BY name");
    expect(after.rows).toEqual(before.rows);
    await d.close();
  });

  it("idempotente: reexecutar o SQL nao falha nem altera dados", async () => {
    const d = await createPgliteDb();
    await migrate(d);
    const acc = await mkAccount(d, "idem@example.com");
    await d.query("INSERT INTO characters (account_id, name, class_id) VALUES ($1, 'Mago1', 'mage')", [acc]);
    const sql = loadMigrations().find((m) => m.version === 4)!.sql;
    await d.exec(sql);
    await d.exec(sql);
    const n = await d.query<{ n: number }>("SELECT count(*)::int AS n FROM pg_constraint WHERE conname = 'characters_class_id_format'");
    expect(n.rows[0]!.n).toBe(1);
    expect((await d.query<{ class_id: string }>("SELECT class_id FROM characters WHERE name = 'Mago1'")).rows[0]!.class_id).toBe("mage");
    expect((await migrate(d)).applied).toEqual([]);
    await d.close();
  });

  it("rollback documentado funciona e a migracao reaplica", async () => {
    const d = await createPgliteDb();
    await migrate(d);
    const acc = await mkAccount(d, "rb@example.com");
    await d.query("INSERT INTO characters (account_id, name, class_id) VALUES ($1, 'Rb', 'ranger')", [acc]);
    // mesmo SQL de backend/migrations/README.md (secao 0004)
    await d.exec(`BEGIN;
ALTER TABLE characters DROP CONSTRAINT IF EXISTS characters_class_id_format;
ALTER TABLE characters ALTER COLUMN class_id DROP DEFAULT;
DELETE FROM schema_migrations WHERE version = 4;
COMMIT;`);
    let code: string | undefined;
    try { await d.query("INSERT INTO characters (account_id, name) VALUES ($1, 'SemDefault')", [acc]); } catch (e) { code = (e as { code?: string }).code; }
    expect(code).toBe(PgErrorCode.notNullViolation);
    expect((await d.query<{ class_id: string }>("SELECT class_id FROM characters WHERE name = 'Rb'")).rows[0]!.class_id).toBe("ranger");
    expect((await migrate(d)).applied).toEqual([4]);
    await d.close();
  });

  it("README de migracoes documenta o plano de rollback da 0004", () => {
    const readme = readFileSync(`${ROOT}/backend/migrations/README.md`, "utf8");
    expect(readme).toContain("### 0004_character_class_default");
    expect(readme).toContain("DROP CONSTRAINT");
  });
});

describe("API de personagens com class_id", () => {
  it.each(["warrior", "mage", "ranger"])("cria %s: 201, class_id persistido e stats base da classe", async (cid) => {
    const { acc, r } = await mk(cid);
    expect(r.status).toBe(201);
    expect(r.json.character.class_id).toBe(cid);
    expect(r.json.character.stats).toEqual({ ...classes.get(cid)!.base_stats });
    expect(r.json.character.level).toBe(1);
    const id = r.json.character.id as string;
    const got = await call("GET", `/v1/characters/${id}`, { as: acc });
    expect(got.json.character.class_id).toBe(cid);
    const list = await call("GET", "/v1/characters", { as: acc });
    expect(list.json.characters[0]).toMatchObject({ id, class_id: cid });
    const internal = await call("GET", `/internal/characters/${id}`, { internal: true });
    expect(internal.json.character.class_id).toBe(cid);
    const row = await db.query<{ class_id: string }>("SELECT class_id FROM characters WHERE id = $1", [id]);
    expect(row.rows[0]!.class_id).toBe(cid);
  });

  it("class_id invalido/ausente => 400 invalid_class e nada e criado", async () => {
    for (const bad of ["necromancer", "Mage", "", "mage ", "../mage", 5, null, ["mage"], { id: "mage" }, undefined, "a".repeat(200)]) {
      const { acc, r } = await mk(bad);
      expect(r.status, JSON.stringify(bad)).toBe(400);
      expect(r.json.error.code).toBe("invalid_class");
      const n = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM characters WHERE account_id = $1", [acc]);
      expect(n.rows[0]!.n).toBe(0);
    }
  });

  it("checkpoint e recompensa preservam class_id; class_id no estado e recusado", async () => {
    const { acc, r } = await mk("mage");
    const id = r.json.character.id as string;
    const sid = await mkSession(db);
    await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [id, sid]);
    const c0 = (await call("GET", `/internal/characters/${id}`, { internal: true })).json.character;
    const state = { schema_version: c0.schema_version, level: c0.level, xp: c0.xp, stats: c0.stats, inventory: c0.inventory, equipment: c0.equipment };
    const cp = (st: unknown, rev: number, extra: Record<string, unknown> = {}) =>
      call("POST", `/internal/characters/${id}/checkpoint`, { internal: true, session: sid, body: { expected_revision: rev, state: st, ...extra } });
    const ok = await cp({ ...state, xp: 50 }, c0.revision);
    expect(ok.status).toBe(200);
    expect(ok.json.character.class_id).toBe("mage");
    expect(ok.json.character.xp).toBe(50);
    const rev = ok.json.character.revision as number;
    const smuggle = await cp({ ...state, class_id: "warrior" }, rev);
    expect(smuggle.status).toBe(422);
    expect(smuggle.json.error.code).toBe("invalid_state");
    const smuggle2 = await cp(state, rev, { class_id: "warrior" });
    expect(smuggle2.status).toBe(400);
    const rw = await call("POST", `/internal/characters/${id}/rewards`, { internal: true, session: sid, body: { idempotency_key: `reward:${id}:one`, xp: 10, class_id: "warrior" } });
    expect(rw.status).toBe(400);
    const rw2 = await call("POST", `/internal/characters/${id}/rewards`, { internal: true, session: sid, body: { idempotency_key: `reward:${id}:one`, xp: 10 } });
    expect(rw2.status).toBe(200);
    expect(rw2.json.character.class_id).toBe("mage");
    const final = (await call("GET", `/v1/characters/${id}`, { as: acc })).json.character;
    expect(final.class_id).toBe("mage");
    const row = await db.query<{ class_id: string }>("SELECT class_id FROM characters WHERE id = $1", [id]);
    expect(row.rows[0]!.class_id).toBe("mage");
  });

  it("personagem ja existente sem coluna preenchida pelo cliente continua legivel (guerreiro antigo)", async () => {
    const acc = await mkAccount(db, `legacy${++seq}@example.com`);
    const ins = await db.query<{ id: string }>("INSERT INTO characters (account_id, name, stats) VALUES ($1, $2, $3::jsonb) RETURNING id", [acc, `Legacy${seq}`, JSON.stringify(BASE_STATS)]);
    const got = await call("GET", `/v1/characters/${ins.rows[0]!.id}`, { as: acc });
    expect(got.status).toBe(200);
    expect(got.json.character.class_id).toBe("warrior");
    expect(got.json.character.stats).toEqual({ ...BASE_STATS });
  });
});
