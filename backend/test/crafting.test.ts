import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { createRecipeCatalog, loadRecipeCatalogFromDisk } from "../src/crafting/catalog.ts";
import { removeItems } from "../src/crafting/service.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { loadQuestCatalogFromDisk } from "../src/quests/catalog.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const items = loadCatalogFromDisk();
const qcat = loadQuestCatalogFromDisk(items);
const recipes = loadRecipeCatalogFromDisk(items);
const cfg = testConfig({ GAME_SESSION_INTERNAL_SECRET: "internal-secret-for-tests-0123456789abcdef" });

let db: Db;
let app: App;
let seq = 0;
beforeAll(async () => {
  db = await freshDb();
  app = createApp({
    config: cfg, db, log: createLogger({ level: "error" }),
    authVerifier: async (t) => (t.startsWith("tok-") ? { accountId: t.slice(4) } : null),
    register: (r, d) => registerCharactersRoutes(r, d, { catalog: items, limits: DEFAULT_LIMITS, quests: qcat, recipes }),
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

type Ch = { id: string; sid: string };
/** Cria personagem + sessao com lock e (opcional) inventario inicial via checkpoint. */
async function mkChar(inv: { item_id: string; qty: number }[] = [], equipment?: Record<string, string>): Promise<Ch> {
  const acc = await mkAccount(db, `c${++seq}@example.com`);
  const r = await call("POST", "/v1/characters", { as: acc, body: { name: `Crafter${seq}`, class_id: "warrior" } });
  expect(r.status).toBe(201);
  const id = r.json.character.id as string;
  const sid = await mkSession(db);
  await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [id, sid]);
  const c = { id, sid };
  if (inv.length > 0 || equipment) {
    const g = await getC(id);
    const inventory = inv.map((e, i) => ({ slot: i, ...e }));
    const state = { schema_version: g.schema_version, level: g.level, xp: g.xp, stats: g.stats, inventory, equipment: equipment ?? g.equipment };
    const cp = await call("POST", `/internal/characters/${id}/checkpoint`, { internal: true, session: sid, body: { expected_revision: g.revision, state } });
    expect(cp.status).toBe(200);
  }
  return c;
}
const getC = (id: string) => call("GET", `/internal/characters/${id}`, { internal: true }).then((r) => r.json.character);
const qty = (c: any, item: string): number => c.inventory.filter((e: any) => e.item_id === item).reduce((n: number, e: any) => n + e.qty, 0);
let keyN = 0;
const ckey = (c: Ch) => `craft:${c.sid}:${++keyN}:${c.id}`;
const doCraft = (c: Ch, recipe_id: string, key = ckey(c), session: string | null = c.sid) =>
  call("POST", `/internal/characters/${c.id}/craft`, { internal: true, session: session ?? undefined, body: { idempotency_key: key, recipe_id } });

describe("catalogo de receitas", () => {
  it("carrega do disco (5 receitas, so itens existentes) e esta em dia com data/recipes", () => {
    expect(recipes.ids().sort()).toEqual(["rcp_amulet_vigor", "rcp_armor_heavy", "rcp_armor_leather", "rcp_potion_minor", "rcp_sword_basic"]);
    expect(recipes.get("rcp_potion_minor")).toMatchObject({ station: "station_greenwood_workbench", ingredients: [{ item_id: "scrap_material", qty: 3 }], results: [{ item_id: "potion_minor", qty: 1 }] });
    for (const id of recipes.ids()) {
      for (const s of [...recipes.get(id)!.ingredients, ...recipes.get(id)!.results]) expect(items.has(s.item_id)).toBe(true);
    }
    const root = fileURLToPath(new URL("../..", import.meta.url));
    const out = execFileSync(process.execPath, ["tools/gen_recipes_catalog.mjs", "--check"], { cwd: root, encoding: "utf8" });
    expect(out).toMatch(/em dia/);
  });

  it("rejeita catalogo invalido", () => {
    const base = { id: "r1", station: "st", ingredients: [{ item_id: "scrap_material", qty: 2 }], results: [{ item_id: "potion_minor", qty: 1 }] };
    const mk = (r: unknown, v = 1) => () => createRecipeCatalog({ schema_version: v, recipes: [r] }, items);
    expect(mk(base)).not.toThrow();
    expect(mk(base, 2)).toThrow(/schema_version/);
    expect(mk({ ...base, id: "R!" })).toThrow(/id invalido/);
    expect(mk({ ...base, station: "" })).toThrow(/estacao/);
    expect(mk({ ...base, ingredients: [] })).toThrow(/ingredients/);
    expect(mk({ ...base, ingredients: [{ item_id: "ouro", qty: 1 }] })).toThrow(/desconhecido/);
    expect(mk({ ...base, ingredients: [{ item_id: "scrap_material", qty: 0 }] })).toThrow(/qty/);
    expect(mk({ ...base, ingredients: [{ item_id: "scrap_material", qty: 1 }, { item_id: "scrap_material", qty: 1 }] })).toThrow(/repetido/);
    expect(mk({ ...base, results: [{ item_id: "scrap_material", qty: 1 }] })).toThrow(/tambem e ingrediente/);
    expect(() => createRecipeCatalog({ schema_version: 1, recipes: [base, base] }, items)).toThrow(/duplicado/);
  });

  it("removeItems: tudo-ou-nada, maior slot primeiro, equipados nao contam", () => {
    const inv = [{ slot: 0, item_id: "scrap_material", qty: 2 }, { slot: 3, item_id: "scrap_material", qty: 3 }, { slot: 5, item_id: "potion_minor", qty: 1 }];
    const r = removeItems(inv, [{ item_id: "scrap_material", qty: 4 }]);
    expect(r).toEqual({ ok: true, inventory: [{ slot: 0, item_id: "scrap_material", qty: 1 }, { slot: 5, item_id: "potion_minor", qty: 1 }] });
    expect(removeItems(inv, [{ item_id: "scrap_material", qty: 6 }])).toMatchObject({ ok: false, missing: [{ item_id: "scrap_material", qty: 1 }] });
    expect(removeItems(inv, [{ item_id: "scrap_material", qty: 1 }, { item_id: "potion_minor", qty: 2 }])).toMatchObject({ ok: false });
    expect(inv[0]!.qty).toBe(2); // entrada nao foi mutada
  });
});

describe("POST /internal/characters/:id/craft", () => {
  it("consome ingredientes e entrega o resultado atomicamente; revision sobe", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 7 }]);
    const before = await getC(c.id);
    const r = await doCraft(c, "rcp_potion_minor");
    expect(r.status).toBe(200);
    expect(r.json.replayed).toBe(false);
    expect(r.json.result).toMatchObject({ recipe_id: "rcp_potion_minor", consumed: [{ item_id: "scrap_material", qty: 3 }], produced: [{ item_id: "potion_minor", qty: 1 }] });
    const after = await getC(c.id);
    expect(qty(after, "scrap_material")).toBe(4);
    expect(qty(after, "potion_minor")).toBe(1);
    expect(after.revision).toBe(before.revision + 1);
    expect(r.json.character.revision).toBe(after.revision);
  });

  it("receita com dois ingredientes (armor_heavy = armor_leather + 8 sucata)", async () => {
    const c = await mkChar([{ item_id: "armor_leather", qty: 1 }, { item_id: "scrap_material", qty: 8 }]);
    expect((await doCraft(c, "rcp_armor_heavy")).status).toBe(200);
    const after = await getC(c.id);
    expect(after.inventory).toEqual([{ slot: 0, item_id: "armor_heavy", qty: 1 }]);
  });

  it("replay com a MESMA chave devolve o original sem consumir de novo", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 6 }]);
    const key = ckey(c);
    const a = await doCraft(c, "rcp_potion_minor", key);
    const b = await doCraft(c, "rcp_potion_minor", key);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(b.json.replayed).toBe(true);
    expect(b.json.result).toEqual(a.json.result);
    const after = await getC(c.id);
    expect(qty(after, "scrap_material")).toBe(3);
    expect(qty(after, "potion_minor")).toBe(1);
    expect(after.revision).toBe(a.json.result.revision);
  });

  it("mesma chave com receita diferente => 409 idempotency_key_reuse e nada muda", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 20 }]);
    const key = ckey(c);
    expect((await doCraft(c, "rcp_potion_minor", key)).status).toBe(200);
    const r = await doCraft(c, "rcp_sword_basic", key);
    expect(r.status).toBe(409);
    expect(code(r)).toBe("idempotency_key_reuse");
    expect(qty(await getC(c.id), "scrap_material")).toBe(17);
  });

  it("requests concorrentes com a mesma chave aplicam UMA vez", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 9 }]);
    const key = ckey(c);
    const rs = await Promise.all([1, 2, 3, 4].map(() => doCraft(c, "rcp_potion_minor", key)));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => !r.json.replayed)).toHaveLength(1);
    const after = await getC(c.id);
    expect(qty(after, "scrap_material")).toBe(6);
    expect(qty(after, "potion_minor")).toBe(1);
  });

  it("crafts concorrentes com chaves diferentes serializam e nunca gastam ingredientes que nao existem", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 7 }]); // da para 2 pocoes (6 sucatas), nao 3
    const rs = await Promise.all([1, 2, 3].map(() => doCraft(c, "rcp_potion_minor")));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(2);
    expect(rs.filter((r) => r.status === 409).map(code)).toEqual(["insufficient_ingredients"]);
    const after = await getC(c.id);
    expect(qty(after, "scrap_material")).toBe(1);
    expect(qty(after, "potion_minor")).toBe(2);
  });

  it("ingredientes insuficientes => 409, nada muda e a chave NAO e consumida", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 2 }]);
    const before = await getC(c.id);
    const key = ckey(c);
    const r = await doCraft(c, "rcp_potion_minor", key);
    expect(r.status).toBe(409);
    expect(code(r)).toBe("insufficient_ingredients");
    const mid = await getC(c.id);
    expect(mid.revision).toBe(before.revision);
    expect(qty(mid, "scrap_material")).toBe(2);
    // ganha sucata e repete com a mesma chave: agora funciona (a falha nao queimou a chave)
    await db.query("UPDATE character_inventory SET qty = 3 WHERE character_id = $1", [c.id]);
    expect((await doCraft(c, "rcp_potion_minor", key)).status).toBe(200);
    expect(qty(await getC(c.id), "potion_minor")).toBe(1);
  });

  it("item equipado nao conta como ingrediente", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 8 }], { weapon: "sword_basic", armor: "armor_leather" });
    const r = await doCraft(c, "rcp_armor_heavy");
    expect(r.status).toBe(409);
    expect(code(r)).toBe("insufficient_ingredients");
  });

  it("inventario cheio => 409 inventory_full, tudo-ou-nada, chave nao consumida", async () => {
    // 22 espadas + sucata(12) + pocoes(5) = 24 slots; o amuleto (nao empilhavel) precisaria de um 25o.
    const inv = [
      ...Array.from({ length: 22 }, () => ({ item_id: "sword_basic", qty: 1 })),
      { item_id: "scrap_material", qty: 12 }, { item_id: "potion_minor", qty: 5 },
    ];
    const c = await mkChar(inv);
    const before = await getC(c.id);
    expect(before.inventory).toHaveLength(24);
    const key = ckey(c);
    const r = await doCraft(c, "rcp_amulet_vigor", key);
    expect(r.status).toBe(409);
    expect(code(r)).toBe("inventory_full");
    const after = await getC(c.id);
    expect(after.revision).toBe(before.revision);
    expect(qty(after, "scrap_material")).toBe(12);
    expect(qty(after, "potion_minor")).toBe(5);
    expect(qty(after, "amulet_vigor")).toBe(0);
    // abre espaco e repete com a MESMA chave
    await db.query("DELETE FROM character_inventory WHERE character_id = $1 AND slot = 0", [c.id]);
    expect((await doCraft(c, "rcp_amulet_vigor", key)).status).toBe(200);
    expect(qty(await getC(c.id), "amulet_vigor")).toBe(1);
  });

  it("o resultado pode usar o slot liberado pelos ingredientes (inventario lotado, mas a conta fecha)", async () => {
    const inv = [...Array.from({ length: 23 }, () => ({ item_id: "sword_basic", qty: 1 })), { item_id: "scrap_material", qty: 5 }];
    const c = await mkChar(inv);
    expect((await doCraft(c, "rcp_sword_basic")).status).toBe(200); // 5 sucatas somem, a espada ocupa o slot
    const after = await getC(c.id);
    expect(after.inventory).toHaveLength(24);
    expect(qty(after, "sword_basic")).toBe(24);
    expect(qty(after, "scrap_material")).toBe(0);
  });

  it("receita desconhecida / malformada => 400", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 9 }]);
    expect(code(await doCraft(c, "rcp_nao_existe"))).toBe("unknown_recipe");
    expect(code(await doCraft(c, "Bad Id!"))).toBe("invalid_recipe");
    const r = await call("POST", `/internal/characters/${c.id}/craft`, { internal: true, session: c.sid, body: { idempotency_key: ckey(c), recipe_id: 5 } });
    expect(r.status).toBe(400);
    expect(qty(await getC(c.id), "scrap_material")).toBe(9);
  });

  it("corpo com campo extra / chave fora do formato / chave de outra sessao ou personagem => 400", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 9 }]);
    const other = await mkChar([{ item_id: "scrap_material", qty: 9 }]);
    const post = (body: unknown) => call("POST", `/internal/characters/${c.id}/craft`, { internal: true, session: c.sid, body });
    expect((await post({ idempotency_key: ckey(c), recipe_id: "rcp_potion_minor", xp: 100 })).status).toBe(400);
    expect(code(await post({ idempotency_key: "craft-qualquer-coisa", recipe_id: "rcp_potion_minor" }))).toBe("invalid_idempotency_key");
    expect(code(await post({ idempotency_key: `craft:${other.sid}:1:${c.id}`, recipe_id: "rcp_potion_minor" }))).toBe("invalid_idempotency_key"); // sessao alheia
    expect(code(await post({ idempotency_key: `craft:${c.sid}:1:${other.id}`, recipe_id: "rcp_potion_minor" }))).toBe("invalid_idempotency_key"); // personagem alheio
    expect(code(await post({ idempotency_key: `loot:${c.sid}:1:${c.id}`, recipe_id: "rcp_potion_minor" }))).toBe("invalid_idempotency_key");
    expect(code(await post({ recipe_id: "rcp_potion_minor" }))).toBe("invalid_idempotency_key");
    expect(qty(await getC(c.id), "scrap_material")).toBe(9);
  });

  it("fencing: sem X-Session-Id => 400; sessao sem o lock => 409; sessao encerrada => 409; sem credencial interna => 401", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 9 }]);
    expect((await doCraft(c, "rcp_potion_minor", ckey(c), null)).status).toBe(400);
    const stranger = await mkSession(db);
    const r = await doCraft(c, "rcp_potion_minor", `craft:${stranger}:1:${c.id}`, stranger);
    expect(r.status).toBe(409);
    expect(code(r)).toBe("session_fenced");
    await db.query("UPDATE game_sessions SET closed_at = now(), status = 'closed' WHERE id = $1", [c.sid]);
    expect(code(await doCraft(c, "rcp_potion_minor"))).toBe("session_fenced");
    const anon = await call("POST", `/internal/characters/${c.id}/craft`, { session: c.sid, body: { idempotency_key: ckey(c), recipe_id: "rcp_potion_minor" } });
    expect(anon.status).toBe(401);
    expect(qty(await getC(c.id), "scrap_material")).toBe(9);
  });

  it("personagem inexistente => 404", async () => {
    const c = await mkChar();
    const ghost = "99999999-9999-4999-8999-999999999999";
    await db.query("INSERT INTO character_locks (character_id, session_id) SELECT $1, $2 WHERE false", [ghost, c.sid]);
    const r = await call("POST", `/internal/characters/${ghost}/craft`, { internal: true, session: c.sid, body: { idempotency_key: `craft:${c.sid}:1:${ghost}`, recipe_id: "rcp_potion_minor" } });
    expect([404, 409]).toContain(r.status); // sem lock => fencing; o importante e nao criar nada
  });
});

describe("chaves reservadas em /rewards (loot:, craft:)", () => {
  const rw = (c: Ch, body: unknown, session: string | undefined = c.sid) =>
    call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, session, body });

  it("loot:<sessao>:<drop>:<personagem> paga exatamente um item; replay nao duplica", async () => {
    const c = await mkChar();
    const body = { idempotency_key: `loot:${c.sid}:42:${c.id}`, items: [{ item_id: "potion_minor", qty: 2 }] };
    const a = await rw(c, body);
    expect(a.status).toBe(200);
    expect(a.json.replayed).toBe(false);
    const b = await rw(c, body);
    expect(b.json.replayed).toBe(true);
    expect(qty(await getC(c.id), "potion_minor")).toBe(2);
    // mesma chave, outro conteudo => 409
    expect(code(await rw(c, { ...body, items: [{ item_id: "potion_minor", qty: 9 }] }))).toBe("idempotency_key_reuse");
    expect(qty(await getC(c.id), "potion_minor")).toBe(2);
  });

  it("loot: com xp, varios itens, sessao/personagem alheios ou formato errado => 400", async () => {
    const c = await mkChar();
    const o = await mkChar();
    const it1 = [{ item_id: "scrap_material", qty: 1 }];
    expect((await rw(c, { idempotency_key: `loot:${c.sid}:1:${c.id}`, xp: 10, items: it1 })).status).toBe(400);
    expect((await rw(c, { idempotency_key: `loot:${c.sid}:2:${c.id}`, items: [...it1, { item_id: "potion_minor", qty: 1 }] })).status).toBe(400);
    expect(code(await rw(c, { idempotency_key: `loot:${o.sid}:3:${c.id}`, items: it1 }))).toBe("invalid_idempotency_key");
    expect(code(await rw(c, { idempotency_key: `loot:${c.sid}:3:${o.id}`, items: it1 }))).toBe("invalid_idempotency_key");
    expect(code(await rw(c, { idempotency_key: `loot:${c.sid}:abc:${c.id}`, items: it1 }))).toBe("invalid_idempotency_key");
    expect(code(await rw(c, { idempotency_key: `craft:${c.sid}:1:${c.id}`, items: it1 }))).toBe("invalid_idempotency_key");
    expect(qty(await getC(c.id), "scrap_material")).toBe(0);
  });

  it("loot com inventario cheio => 409 inventory_full, nada aplicado e chave livre", async () => {
    const c = await mkChar(Array.from({ length: 24 }, () => ({ item_id: "sword_basic", qty: 1 })));
    const body = { idempotency_key: `loot:${c.sid}:7:${c.id}`, items: [{ item_id: "amulet_vigor", qty: 1 }] };
    const r = await rw(c, body);
    expect(r.status).toBe(409);
    expect(code(r)).toBe("inventory_full");
    await db.query("DELETE FROM character_inventory WHERE character_id = $1 AND slot = 0", [c.id]);
    expect((await rw(c, body)).status).toBe(200);
  });

  it("claims de craft e de loot convivem na mesma tabela sem colidir", async () => {
    const c = await mkChar([{ item_id: "scrap_material", qty: 3 }]);
    expect((await doCraft(c, "rcp_potion_minor")).status).toBe(200);
    expect((await rw(c, { idempotency_key: `loot:${c.sid}:1:${c.id}`, items: [{ item_id: "scrap_material", qty: 4 }] })).status).toBe(200);
    const n = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM reward_claims WHERE character_id = $1", [c.id]);
    expect(n.rows[0]!.n).toBe(2);
  });
});
