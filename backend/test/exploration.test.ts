import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { validateRewardRequest, validateState } from "../src/characters/model.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { createQuestCatalog, loadQuestCatalogFromDisk } from "../src/quests/catalog.ts";
import { discoverPoi, emptyQuests, mergeCheckpointQuests, normalizeStoredQuests, validateQuestsState } from "../src/quests/state.ts";
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
  const acc = await mkAccount(db, `x${++seq}@example.com`);
  const r = await call("POST", "/v1/characters", { as: acc, body: { name: `Explorer${seq}`, class_id: "warrior" } });
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


const prew = (c: { id: string }, poi: string) => {
  const d = qcat.poi(poi)!;
  return { idempotency_key: `explore:${poi}:${c.id}`, poi_id: poi, xp: d.rewards.xp, items: d.rewards.items };
};

describe("exploracao: catalogo", () => {
  it("carrega >= 6 pontos validos e quests `discover` apontam para pontos existentes", () => {
    expect(qcat.poiIds().length).toBeGreaterThanOrEqual(6);
    for (const id of qcat.ids()) for (const o of qcat.get(id)!.objectives) if (o.type === "discover") expect(qcat.hasPoi(o.target)).toBe(true);
  });
  it("rejeita exploracao invalida (item desconhecido, quest exigida inexistente, id duplicado, recompensa vazia)", () => {
    const qraw = { schema_version: 1, quests: [] };
    const p = { id: "poi_t", zone: "zone_hub", min_level: 1, requires_quests: [], rewards: { xp: 5, items: [] } };
    const mk = (pt: unknown[]) => () => createQuestCatalog(qraw, items, { schema_version: 1, points: pt });
    expect(mk([p])).not.toThrow();
    expect(mk([{ ...p, rewards: { xp: 0, items: [{ item_id: "nao_existe", qty: 1 }] } }])).toThrow(/item/);
    expect(mk([{ ...p, requires_quests: ["fantasma"] }])).toThrow(/requires_quests/);
    expect(mk([p, p])).toThrow(/duplicado/);
    expect(mk([{ ...p, rewards: { xp: 0, items: [] } }])).toThrow(/sem recompensa/);
    expect(mk([{ ...p, id: "Bad-Id" }])).toThrow(/invalido/);
    expect(() => createQuestCatalog({ schema_version: 1, quests: [{ id: "q", prerequisites: {}, objectives: [{ id: "o", type: "discover", target: "poi_x", required: 1 }], rewards: { xp: 1, items: [] } }] }, items, { schema_version: 1, points: [] })).toThrow(/ponto de exploracao desconhecido/);
  });
  it("estado: discovered validado (forma, ponto conhecido, sem duplicata) e canonico", () => {
    const ok = validateQuestsState({ active: {}, completed: [], discovered: ["poi_wild_oak".replace("oak", "fallen_oak"), "poi_hub_hollow_stump"] }, qcat);
    expect(ok.discovered).toEqual(["poi_hub_hollow_stump", "poi_wild_fallen_oak"]);
    expect(validateQuestsState({ active: {}, completed: [] }, qcat)).toEqual({ active: {}, completed: [] });
    expect(() => validateQuestsState({ active: {}, completed: [], discovered: ["poi_fantasma"] }, qcat)).toThrow();
    expect(() => validateQuestsState({ active: {}, completed: [], discovered: ["poi_hub_hollow_stump", "poi_hub_hollow_stump"] }, qcat)).toThrow();
    expect(() => validateQuestsState({ active: {}, completed: [], discovered: "x" }, qcat)).toThrow();
    expect(normalizeStoredQuests({ discovered: ["b", "a", 3] }).discovered).toEqual(["a", "b"]);
    expect(normalizeStoredQuests({}).discovered).toBeUndefined();
    expect(mergeCheckpointQuests({ ...emptyQuests(), discovered: ["a"] }, { ...emptyQuests(), discovered: ["b"] }).discovered).toEqual(["a"]);
    expect(discoverPoi(emptyQuests(), "poi_x").discovered).toEqual(["poi_x"]);
  });
  it("validateRewardRequest com poi_id: chave estavel, ponto conhecido, valores do catalogo, prefixo reservado", () => {
    const cid = "11111111-1111-4111-8111-111111111111";
    const good = { idempotency_key: `explore:poi_hub_hollow_stump:${cid}`, poi_id: "poi_hub_hollow_stump", ...qcat.poi("poi_hub_hollow_stump")!.rewards };
    expect(validateRewardRequest(good, items, DEFAULT_LIMITS, qcat, cid).poi_id).toBe("poi_hub_hollow_stump");
    const bad = (b: object, code: string) => expect(() => validateRewardRequest({ ...good, ...b }, items, DEFAULT_LIMITS, qcat, cid)).toThrow(expect.objectContaining({ code }));
    bad({ xp: good.xp + 1 }, "poi_reward_mismatch");
    bad({ items: [] }, "poi_reward_mismatch");
    bad({ poi_id: "poi_fantasma" }, "unknown_poi");
    bad({ idempotency_key: `explore:poi_hub_hollow_stump:${cid.replace("1", "2")}` }, "invalid_idempotency_key");
    bad({ quest_id: "gw_welcome" }, "invalid_reward");
    expect(() => validateRewardRequest({ idempotency_key: `explore:poi_x:${cid}`, xp: 5, items: [] }, items, DEFAULT_LIMITS, qcat, cid)).toThrow(expect.objectContaining({ code: "invalid_idempotency_key" }));
  });
});

describe("exploracao: recompensa unica, idempotente e persistida", () => {
  it("paga xp+itens, marca descoberto na mesma transacao; replay nao duplica", async () => {
    const c = await mkChar();
    const before = await getC(c.id);
    const body = prew(c, "poi_hub_hollow_stump");
    const r1 = await rw(c, body);
    expect(r1.status).toBe(200);
    expect(r1.json.replayed).toBe(false);
    const after = await getC(c.id);
    expect(after.quests.discovered).toEqual(["poi_hub_hollow_stump"]);
    expect(after.xp).toBe(before.xp + qcat.poi("poi_hub_hollow_stump")!.rewards.xp);
    const scrap = (ch: any) => ch.inventory.filter((e: any) => e.item_id === "scrap_material").reduce((a: number, e: any) => a + e.qty, 0);
    expect(scrap(after)).toBe(scrap(before) + 2);
    const r2 = await rw(c, body);
    expect(r2.status).toBe(200);
    expect(r2.json.replayed).toBe(true);
    const again = await getC(c.id);
    expect(again.xp).toBe(after.xp);
    expect(scrap(again)).toBe(scrap(after));
    expect(again.revision).toBe(after.revision);
  });
  it("outra chave para o mesmo ponto => 409 poi_already_discovered (sem duplicar)", async () => {
    const c = await mkChar();
    await rw(c, prew(c, "poi_hub_hollow_stump"));
    const snap = await getC(c.id);
    const r = await rw(c, { ...prew(c, "poi_hub_hollow_stump"), idempotency_key: `explore:poi_hub_hollow_stump:${c.id}`.replace("explore:", "explore:") + "" });
    expect(r.status).toBe(200); // mesma chave = replay
    // a chave e estavel por contrato; a protecao extra vale quando o claim some: apaga o claim e tenta de novo
    await db.query("DELETE FROM reward_claims WHERE character_id = $1", [c.id]);
    const r3 = await rw(c, prew(c, "poi_hub_hollow_stump"));
    expect(r3.status).toBe(409);
    expect(r3.json.error?.code ?? r3.json.code).toBe("poi_already_discovered");
    const fin = await getC(c.id);
    expect(fin.xp).toBe(snap.xp);
    expect(fin.quests.discovered).toEqual(["poi_hub_hollow_stump"]);
  });
  it("nivel insuficiente e quest exigida => 409, nada aplicado", async () => {
    const c = await mkChar();
    const lv = await rw(c, prew(c, "poi_wild_thorn_relic"));
    expect(lv.status).toBe(409);
    expect(lv.json.error?.code ?? lv.json.code).toBe("poi_level_too_low");
    const rq = await rw(c, prew(c, "poi_wild_hunter_cache"));
    expect(rq.status).toBe(409);
    expect(rq.json.error?.code ?? rq.json.code).toBe("poi_prereq_missing");
    const ch = await getC(c.id);
    expect(ch.quests.discovered).toBeUndefined();
    expect(ch.xp).toBe(0);
  });
  it("divergencia do catalogo => 400; sem fencing => recusado", async () => {
    const c = await mkChar();
    expect((await rw(c, { ...prew(c, "poi_hub_hollow_stump"), xp: 999 })).status).toBe(400);
    const r = await call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, body: prew(c, "poi_hub_hollow_stump") });
    expect([400, 401, 403, 409]).toContain(r.status);
    expect((await getC(c.id)).quests.discovered).toBeUndefined();
  });
  it("concorrencia: 5 requests simultaneos da mesma chave pagam uma vez", async () => {
    const c = await mkChar();
    const body = prew(c, "poi_wild_fallen_oak");
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => rw(c, body)));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => r.json.replayed === false).length).toBe(1);
    expect((await getC(c.id)).xp).toBe(qcat.poi("poi_wild_fallen_oak")!.rewards.xp);
  });
  it("checkpoint nao cria nem desfaz descobertas (somente-servidor) e preserva ao omitir quests", async () => {
    const c = await mkChar();
    let ch = await getC(c.id);
    const forged = await cp(c, ch.revision, stateOf(ch, { active: {}, completed: [], discovered: ["poi_wild_fallen_oak"] }));
    expect(forged.status).toBe(200);
    ch = await getC(c.id);
    expect(ch.quests.discovered).toBeUndefined();
    await rw(c, prew(c, "poi_hub_hollow_stump"));
    ch = await getC(c.id);
    const wipe = await cp(c, ch.revision, stateOf(ch, { active: {}, completed: [] }));
    expect(wipe.status).toBe(200);
    expect((await getC(c.id)).quests.discovered).toEqual(["poi_hub_hollow_stump"]);
    ch = await getC(c.id);
    const unk = await cp(c, ch.revision, stateOf(ch, { active: {}, completed: [], discovered: ["poi_fantasma"] }));
    expect(unk.status).toBe(422);
  });
  it("quest com objetivo discover aceita progresso 0..1 no checkpoint", async () => {
    const c = await mkChar();
    const ch = await getC(c.id);
    const ok = await cp(c, ch.revision, stateOf(ch, { active: { gw_wild_survey: { objectives: { find_oak: 1, find_milestone: 0 } } }, completed: [] }));
    expect(ok.status).toBe(200);
    const ch2 = await getC(c.id);
    const over = await cp(c, ch2.revision, stateOf(ch2, { active: { gw_wild_survey: { objectives: { find_oak: 2 } } }, completed: [] }));
    expect(over.status).toBe(422);
  });
});
