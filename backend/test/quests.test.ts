import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createCatalog, loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS, loadCharacterLimits } from "../src/characters/limits.ts";
import { validateRewardRequest, validateState } from "../src/characters/model.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { createQuestCatalog, loadQuestCatalogFromDisk } from "../src/quests/catalog.ts";
import { completeQuest, emptyQuests, mergeCheckpointQuests, normalizeStoredQuests, validateQuestsState } from "../src/quests/state.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const items = loadCatalogFromDisk();
const qcat = loadQuestCatalogFromDisk(items);
const cfg = testConfig({ GAME_SESSION_INTERNAL_SECRET: "internal-secret-for-tests-0123456789abcdef" });

let db: Db;
let app: App;
let seq = 0;
beforeAll(async () => {
  db = await freshDb();
  app = createApp({
    config: cfg, db, log: createLogger({ level: "error" }),
    authVerifier: async (t) => (t.startsWith("tok-") ? { accountId: t.slice(4) } : null),
    register: (r, d) => registerCharactersRoutes(r, d, { catalog: items, limits: DEFAULT_LIMITS, quests: qcat }),
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
/** Cria personagem + sessao com lock (fencing M4). */
async function mkChar() {
  const acc = await mkAccount(db, `q${++seq}@example.com`);
  const r = await call("POST", "/v1/characters", { as: acc, body: { name: `Quester${seq}`, class_id: "warrior" } });
  expect(r.status).toBe(201);
  const id = r.json.character.id as string;
  const sid = await mkSession(db);
  await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [id, sid]);
  return { id, sid };
}
const getC = (id: string) => call("GET", `/internal/characters/${id}`, { internal: true }).then((r) => r.json.character);
const stateOf = (c: any, quests?: unknown) => ({
  schema_version: c.schema_version, level: c.level, xp: c.xp, stats: c.stats, inventory: c.inventory, equipment: c.equipment,
  ...(quests === undefined ? {} : { quests }),
});
const cp = (c: { id: string; sid: string }, rev: number, state: unknown) =>
  call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, session: c.sid, body: { expected_revision: rev, state } });
const rw = (c: { id: string; sid: string }, body: unknown) =>
  call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, session: c.sid, body });
const qrew = (c: { id: string }, qid: string) => {
  const d = qcat.get(qid)!;
  return { idempotency_key: `quest:${qid}:${c.id}`, quest_id: qid, xp: d.rewards.xp, items: d.rewards.items };
};

describe("catalogo de quests", () => {
  it("carrega do disco, valida referencias e esta em dia com data/quests", () => {
    expect(qcat.ids().sort()).toEqual(["gw_clear_clearing", "gw_ruin_guardian", "gw_ruins_expedition", "gw_scrap_for_orla", "gw_welcome"]);
    expect(qcat.get("gw_welcome")!.rewards).toEqual({ xp: 60, items: [{ item_id: "potion_minor", qty: 2 }] });
    const root = fileURLToPath(new URL("../..", import.meta.url));
    const out = execFileSync(process.execPath, ["tools/gen_quests_catalog.mjs", "--check"], { cwd: root, encoding: "utf8" });
    expect(out).toMatch(/em dia/);
  });

  it("rejeita catalogo invalido", () => {
    const base = { id: "q", prerequisites: {}, objectives: [{ id: "o", type: "kill", target: "x", required: 1 }], rewards: { xp: 1, items: [] } };
    const mk = (q: unknown, v = 1) => () => createQuestCatalog({ schema_version: v, quests: [q] }, items);
    expect(mk(base)).not.toThrow();
    expect(mk(base, 2)).toThrow(/schema_version/);
    expect(mk({ ...base, id: "Q!" })).toThrow(/id invalido/);
    expect(mk({ ...base, objectives: [] })).toThrow(/sem objetivos/);
    expect(mk({ ...base, objectives: [{ ...base.objectives[0], type: "dance" }] })).toThrow(/invalido/);
    expect(mk({ ...base, rewards: { xp: 0, items: [] } })).toThrow(/sem recompensa/);
    expect(mk({ ...base, rewards: { xp: 0, items: [{ item_id: "nope", qty: 1 }] } })).toThrow(/desconhecido/);
    expect(mk({ ...base, prerequisites: { quests: ["ghost"] } })).toThrow(/prerequisito desconhecido/);
    expect(() => createQuestCatalog({ schema_version: 1, quests: [base, base] }, items)).toThrow(/duplicado/);
  });
});

describe("validacao do estado de quests", () => {
  it("normaliza '{}' do banco e aceita estado valido (forma canonica ordenada)", () => {
    expect(normalizeStoredQuests({})).toEqual(emptyQuests());
    expect(normalizeStoredQuests(null)).toEqual(emptyQuests());
    const ok = validateQuestsState({ active: { gw_clear_clearing: { objectives: { kill_grunts: 3 } } }, completed: ["gw_welcome"] }, qcat);
    expect(ok).toEqual({ active: { gw_clear_clearing: { objectives: { kill_grunts: 3 } } }, completed: ["gw_welcome"] });
  });

  it("rejeita formas invalidas, ids/objetivos desconhecidos, progresso fora da faixa e conflitos", () => {
    const v = (x: unknown, max = 10) => () => validateQuestsState(x, qcat, max);
    expect(v([])).toThrow(/objeto/);
    expect(v({ extra: 1 })).toThrow(/campo desconhecido/);
    expect(v({ active: [] })).toThrow(/active/);
    expect(v({ completed: "x" })).toThrow(/completed/);
    expect(v({ completed: ["ghost"] })).toThrow(/desconhecida/);
    expect(v({ completed: ["gw_welcome", "gw_welcome"] })).toThrow(/duplicado/);
    expect(v({ completed: ["Bad Id"] })).toThrow(/invalido/);
    expect(v({ active: { ghost: { objectives: {} } } })).toThrow(/desconhecida/);
    expect(v({ active: { gw_welcome: { objectives: { nope: 1 } } } })).toThrow(/objetivo desconhecido/);
    expect(v({ active: { gw_clear_clearing: { objectives: { kill_grunts: 6 } } } })).toThrow(/progresso/);
    expect(v({ active: { gw_clear_clearing: { objectives: { kill_grunts: -1 } } } })).toThrow(/progresso/);
    expect(v({ active: { gw_clear_clearing: { objectives: { kill_grunts: 1.5 } } } })).toThrow(/progresso/);
    expect(v({ active: { gw_clear_clearing: { objectives: { kill_grunts: "3" } } } })).toThrow(/progresso/);
    expect(v({ active: { gw_welcome: { objectives: {} } }, completed: ["gw_welcome"] })).toThrow(/ja concluida/);
    expect(v({ active: { gw_welcome: { objectives: {} }, gw_scrap_for_orla: { objectives: {} } } }, 1)).toThrow(/limite/);
  });

  it("merge do checkpoint: completed e somente-servidor; ativa ja concluida no banco e descartada", () => {
    const stored = { active: {}, completed: ["gw_welcome"] };
    const merged = mergeCheckpointQuests(stored, { active: { gw_welcome: { objectives: { talk_brannoch: 1 } }, gw_scrap_for_orla: { objectives: {} } }, completed: ["gw_welcome", "gw_clear_clearing"] });
    expect(merged).toEqual({ active: { gw_scrap_for_orla: { objectives: {} } }, completed: ["gw_welcome"] });
    expect(completeQuest({ active: { a: { objectives: {} } }, completed: ["z"] }, "a")).toEqual({ active: {}, completed: ["a", "z"] });
  });

  it("validateState: quests opcional; limite configuravel por env", () => {
    const c = { schema_version: 1, level: 1, xp: 0, stats: { max_health: 100, max_resource: 50, resource_regen: 5, attack_power: 10, defense: 0, resistance: 0, move_speed: 5 }, inventory: [], equipment: {} };
    expect(validateState(c, items, DEFAULT_LIMITS, qcat).quests).toBeUndefined();
    expect(validateState({ ...c, quests: { active: {}, completed: [] } }, items, DEFAULT_LIMITS, qcat).quests).toEqual(emptyQuests());
    expect(() => validateState({ ...c, quests: { active: {}, completed: ["ghost"] } }, items, DEFAULT_LIMITS, qcat)).toThrow(/desconhecida/);
    expect(loadCharacterLimits({ CHARACTER_MAX_ACTIVE_QUESTS: "3" }).maxActiveQuests).toBe(3);
    expect(() => loadCharacterLimits({ CHARACTER_MAX_ACTIVE_QUESTS: "0" })).toThrow();
  });

  it("validateRewardRequest com quest_id: chave estavel, quest conhecida, valores do catalogo", () => {
    const cid = "11111111-1111-4111-8111-111111111111";
    const good = { idempotency_key: `quest:gw_welcome:${cid}`, quest_id: "gw_welcome", xp: 60, items: [{ item_id: "potion_minor", qty: 2 }] };
    expect(validateRewardRequest(good, items, DEFAULT_LIMITS, qcat, cid)).toMatchObject({ quest_id: "gw_welcome", xp: 60 });
    const code = (b: unknown) => { try { validateRewardRequest(b, items, DEFAULT_LIMITS, qcat, cid); return "ok"; } catch (e: any) { return e.code; } };
    expect(code({ ...good, quest_id: "ghost" })).toBe("unknown_quest");
    expect(code({ ...good, idempotency_key: "quest:gw_welcome:outro-personagem" })).toBe("invalid_idempotency_key");
    expect(code({ ...good, idempotency_key: `reward-${cid}-xxxxxxxx` })).toBe("invalid_idempotency_key");
    expect(code({ ...good, xp: 61 })).toBe("quest_reward_mismatch");
    expect(code({ ...good, items: [] })).toBe("quest_reward_mismatch");
    expect(code({ ...good, quest_id: 5 })).toBe("invalid_reward");
  });
});

describe("persistencia de quests (checkpoint)", () => {
  it("personagem novo tem quests vazias; checkpoint persiste active e a releitura devolve igual", async () => {
    const c = await mkChar();
    const g = await getC(c.id);
    expect(g.quests).toEqual({ active: {}, completed: [] });
    const q = { active: { gw_welcome: { objectives: { talk_brannoch: 0 } }, gw_scrap_for_orla: { objectives: { collect_scrap: 4 } } }, completed: [] };
    const r = await cp(c, g.revision, stateOf(g, q));
    expect(r.status).toBe(200);
    expect(r.json.character.revision).toBe(g.revision + 1);
    const again = await getC(c.id);
    expect(again.quests.active.gw_scrap_for_orla.objectives.collect_scrap).toBe(4);
    expect(Object.keys(again.quests.active).sort()).toEqual(["gw_scrap_for_orla", "gw_welcome"]);
  });

  it("checkpoint sem `quests` preserva o estado do banco", async () => {
    const c = await mkChar();
    let g = await getC(c.id);
    await cp(c, g.revision, stateOf(g, { active: { gw_welcome: { objectives: {} } }, completed: [] }));
    g = await getC(c.id);
    const r = await cp(c, g.revision, stateOf(g));
    expect(r.status).toBe(200);
    expect((await getC(c.id)).quests.active).toHaveProperty("gw_welcome");
  });

  it("estado invalido => 422 e nada muda; revision antiga => 409", async () => {
    const c = await mkChar();
    const g = await getC(c.id);
    const bad = await cp(c, g.revision, stateOf(g, { active: { ghost: { objectives: {} } }, completed: [] }));
    expect(bad.status).toBe(422);
    expect(bad.json.error.code ?? bad.json.code).toBe("invalid_state");
    const over = await cp(c, g.revision, stateOf(g, { active: { gw_clear_clearing: { objectives: { kill_grunts: 99 } } }, completed: [] }));
    expect(over.status).toBe(422);
    expect((await getC(c.id)).revision).toBe(g.revision);
    expect((await cp(c, g.revision + 5, stateOf(g, emptyQuests()))).status).toBe(409);
  });

  it("checkpoint exige X-Session-Id do lock (fencing preservado)", async () => {
    const c = await mkChar();
    const g = await getC(c.id);
    const r = await call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, body: { expected_revision: g.revision, state: stateOf(g, emptyQuests()) } });
    expect(r.status).toBe(400);
    const other = await mkSession(db);
    const r2 = await cp({ id: c.id, sid: other }, g.revision, stateOf(g, emptyQuests()));
    expect(r2.status).toBe(409);
  });

  it("checkpoint nao conclui nem desfaz conclusao (completed somente-servidor)", async () => {
    const c = await mkChar();
    let g = await getC(c.id);
    // tentar concluir via checkpoint: completed do cliente e ignorado
    const r = await cp(c, g.revision, stateOf(g, { active: {}, completed: ["gw_welcome"] }));
    expect(r.status).toBe(200);
    expect((await getC(c.id)).quests.completed).toEqual([]);
    // a recompensa ainda paga (nao foi bloqueada por checkpoint anterior)
    const pay = await rw(c, qrew(c, "gw_welcome"));
    expect(pay.status).toBe(200);
    g = await getC(c.id);
    expect(g.quests.completed).toEqual(["gw_welcome"]);
    // tentar desfazer: continua concluida; ativa conflitante e descartada
    const r2 = await cp(c, g.revision, stateOf(g, { active: { gw_scrap_for_orla: { objectives: {} } }, completed: [] }));
    expect(r2.status).toBe(200);
    const g2 = await getC(c.id);
    expect(g2.quests.completed).toEqual(["gw_welcome"]);
    expect(Object.keys(g2.quests.active)).toEqual(["gw_scrap_for_orla"]);
  });
});

describe("recompensa de quest", () => {
  it("paga xp+itens, conclui a quest na mesma transacao e remove de ativas", async () => {
    const c = await mkChar();
    let g = await getC(c.id);
    await cp(c, g.revision, stateOf(g, { active: { gw_welcome: { objectives: { talk_brannoch: 1 } } }, completed: [] }));
    const r = await rw(c, qrew(c, "gw_welcome"));
    expect(r.status).toBe(200);
    expect(r.json.replayed).toBe(false);
    expect(r.json.result).toMatchObject({ xp_granted: 60, items_added: [{ item_id: "potion_minor", qty: 2 }] });
    g = await getC(c.id);
    expect(g.xp).toBe(60);
    expect(g.inventory).toEqual([{ slot: 0, item_id: "potion_minor", qty: 2 }]);
    expect(g.quests).toEqual({ active: {}, completed: ["gw_welcome"] });
  });

  it("replay (retry da mesma chave) devolve o original sem duplicar", async () => {
    const c = await mkChar();
    const body = qrew(c, "gw_welcome");
    const first = await rw(c, body);
    const again = await rw(c, body);
    const third = await rw(c, body);
    expect(again.status).toBe(200);
    expect(again.json.replayed).toBe(true);
    expect(third.json.result).toEqual(first.json.result);
    const g = await getC(c.id);
    expect(g.xp).toBe(60);
    expect(g.inventory[0].qty).toBe(2);
    expect(g.revision).toBe(first.json.result.revision);
  });

  it("outra chave para quest ja concluida => 409 quest_already_completed (sem duplicar)", async () => {
    const c = await mkChar();
    await rw(c, qrew(c, "gw_welcome"));
    // a chave estavel e obrigatoria, entao so um replay legitimo e aceito; sem a claim (linha apagada) o estado concluido barra
    await db.query("DELETE FROM reward_claims WHERE character_id = $1", [c.id]);
    const r = await rw(c, qrew(c, "gw_welcome"));
    expect(r.status).toBe(409);
    expect(JSON.stringify(r.json)).toContain("quest_already_completed");
    expect((await getC(c.id)).xp).toBe(60);
  });

  it("valores divergentes do catalogo, quest desconhecida e chave errada => 400", async () => {
    const c = await mkChar();
    const ok = qrew(c, "gw_welcome");
    const t = async (b: unknown) => (await rw(c, b));
    expect((await t({ ...ok, xp: 6000 })).status).toBe(400);
    expect((await t({ ...ok, quest_id: "ghost" })).status).toBe(400);
    expect((await t({ ...ok, idempotency_key: "quest:gw_welcome:outro-id" })).status).toBe(400);
    expect((await t({ ...ok, items: [{ item_id: "sword_rare", qty: 1 }] })).status).toBe(400);
    const g = await getC(c.id);
    expect(g.xp).toBe(0);
    expect(g.quests.completed).toEqual([]);
  });

  it("inventario cheio => 409 inventory_full, nada aplicado e a quest continua nao concluida (retry possivel)", async () => {
    const c = await mkChar();
    let g = await getC(c.id);
    const full = Array.from({ length: 24 }, (_, i) => ({ slot: i, item_id: "sword_rare", qty: 1 }));
    expect((await cp(c, g.revision, stateOf({ ...g, inventory: full }))).status).toBe(200);
    const r = await rw(c, qrew(c, "gw_welcome"));
    expect(r.status).toBe(409);
    expect(JSON.stringify(r.json)).toContain("inventory_full");
    g = await getC(c.id);
    expect(g.xp).toBe(0);
    expect(g.quests.completed).toEqual([]);
    // libera espaco: a mesma chave agora paga (a falha nao consumiu a chave)
    expect((await cp(c, g.revision, stateOf({ ...g, inventory: [] }))).status).toBe(200);
    const retry = await rw(c, qrew(c, "gw_welcome"));
    expect(retry.status).toBe(200);
    expect(retry.json.replayed).toBe(false);
  });

  it("concorrencia: 5 requests simultaneos da mesma chave pagam uma vez", async () => {
    const c = await mkChar();
    const rs = await Promise.all(Array.from({ length: 5 }, () => rw(c, qrew(c, "gw_clear_clearing"))));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => !r.json.replayed)).toHaveLength(1);
    const g = await getC(c.id);
    expect(g.xp).toBe(150);
    expect(g.quests.completed).toEqual(["gw_clear_clearing"]);
  });

  it("recompensa de quest exige o fencing de sessao", async () => {
    const c = await mkChar();
    const r = await call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, body: qrew(c, "gw_welcome") });
    expect(r.status).toBe(400);
    expect((await rw({ id: c.id, sid: await mkSession(db) }, qrew(c, "gw_welcome"))).status).toBe(409);
    expect((await getC(c.id)).xp).toBe(0);
  });

  it("recompensa generica (sem quest_id) continua igual e nao toca em quests", async () => {
    const c = await mkChar();
    const r = await rw(c, { idempotency_key: `generic-${c.id}`, xp: 10 });
    expect(r.status).toBe(200);
    expect((await getC(c.id)).quests).toEqual({ active: {}, completed: [] });
  });
});
