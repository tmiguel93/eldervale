import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { createCatalog, loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS, loadCharacterLimits, type CharacterLimits } from "../src/characters/limits.ts";
import { validateCharacterName } from "../src/characters/model.ts";
import { applyXp, levelForXp, MAX_LEVEL, MAX_TOTAL_XP, totalXpForLevel, xpToNext } from "../src/characters/progression.ts";
import { checkpoint, grantReward, type ServiceCtx } from "../src/characters/service.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const catalog = loadCatalogFromDisk();
const cfg = testConfig({ GAME_SESSION_INTERNAL_SECRET: "internal-secret-for-tests-0123456789abcdef" });
const SECRET = cfg.gameSessionInternalSecret;

let db: Db;
let seq = 0;
let app: App;
beforeAll(async () => { db = await freshDb(); app = mkApp(); });
afterAll(async () => { await db.close(); });

function mkApp(limits: CharacterLimits = DEFAULT_LIMITS, database: Db = db): App {
  return createApp({
    config: cfg,
    db: database,
    log: createLogger({ level: "error" }),
    authVerifier: async (t) => (t.startsWith("tok-") ? { accountId: t.slice(4) } : null),
    register: (r, d) => registerCharactersRoutes(r, d, { catalog, limits }),
  });
}

interface CallOpts { as?: string; internal?: boolean | string; body?: unknown; session?: string | null }
const lockCache = new Map<string, Promise<string>>();
/** Cria (uma vez por personagem; seguro sob concorrencia) sessao + lock para o fencing do M4. */
function sessionFor(characterId: string): Promise<string> {
  let p = lockCache.get(characterId);
  if (!p) {
    p = (async () => {
      const sid = await mkSession(db);
      await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [characterId, sid]);
      return sid;
    })();
    lockCache.set(characterId, p);
  }
  return p;
}
async function call(app: App, method: string, path: string, o: CallOpts = {}) {
  const headers: Record<string, string> = {};
  if (o.as) headers.authorization = `Bearer tok-${o.as}`;
  if (o.internal) headers.authorization = `Bearer ${o.internal === true ? SECRET : o.internal}`;
  if (o.body !== undefined) headers["content-type"] = "application/json";
  const m = /^\/internal\/characters\/([0-9a-f-]{36})\/(checkpoint|rewards)$/i.exec(path);
  if (m && o.internal && o.session !== null) headers["x-session-id"] = o.session ?? (await sessionFor(m[1]!.toLowerCase()));
  const res = await app.handle(new Request(`http://t${path}`, { method, headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }));
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}

const uname = () => `Hero${++seq}`;
const newAccount = () => mkAccount(db, `u${++seq}@example.com`);
async function newChar(accountId: string, a: App = app) {
  const r = await call(a, "POST", "/v1/characters", { as: accountId, body: { name: uname(), class_id: "warrior" } });
  expect(r.status).toBe(201);
  return r.json.character as { id: string; revision: number; level: number; xp: number; inventory: any[]; equipment: any; stats: any };
}
const get = (id: string) => call(app, "GET", `/internal/characters/${id}`, { internal: true }).then((r) => r.json.character);
const stateOf = (c: any) => ({ schema_version: c.schema_version, level: c.level, xp: c.xp, stats: c.stats, inventory: c.inventory, equipment: c.equipment });
const cp = (id: string, expected_revision: number, state: unknown, session?: string | null) =>
  call(app, "POST", `/internal/characters/${id}/checkpoint`, { internal: true, body: { expected_revision, state }, session });
const FAKE_SESSION = "11111111-1111-4111-8111-111111111111";
const reward = (id: string, body: unknown, session?: string | null) => call(app, "POST", `/internal/characters/${id}/rewards`, { internal: true, body, session });

describe("catalogo", () => {
  it("carrega do disco com os 12 itens do jogo (7 base + 5 unicos E6.3) e dados corretos", () => {
    expect(catalog.ids().sort()).toEqual([
      "amulet_vigor", "armor_heavy", "armor_leather", "potion_minor", "scrap_material", "sword_basic", "sword_rare",
      "unique_emberfang", "unique_featherknot", "unique_frostbrand", "unique_gravitas_plate", "unique_twin_quiver",
    ]);
    expect(catalog.get("potion_minor")).toMatchObject({ slot: "none", stackable: true, max_stack: 20 });
    expect(catalog.get("scrap_material")).toMatchObject({ stackable: true, max_stack: 50 });
    expect(catalog.get("sword_basic")).toMatchObject({ slot: "weapon", stackable: false, max_stack: 1 });
    expect(catalog.get("armor_leather")?.slot).toBe("armor");
    expect(catalog.get("amulet_vigor")?.slot).toBe("trinket");
    expect(catalog.has("nao_existe")).toBe(false);
  });
  it("rejeita catalogo invalido", () => {
    const item = { id: "a", slot: "none", stackable: false, max_stack: 1, rarity: "common" };
    expect(() => createCatalog({ schema_version: 2, items: [item] })).toThrow();
    expect(() => createCatalog({ schema_version: 1, items: [] })).toThrow();
    expect(() => createCatalog({ schema_version: 1, items: [item, item] })).toThrow(/duplicado/);
    expect(() => createCatalog({ schema_version: 1, items: [{ ...item, slot: "head" }] })).toThrow(/slot/);
    expect(() => createCatalog({ schema_version: 1, items: [{ ...item, max_stack: 5 }] })).toThrow(/max_stack/);
    expect(() => createCatalog({ schema_version: 1, items: [{ ...item, id: "Bad Id" }] })).toThrow(/id/);
  });
  const root = fileURLToPath(new URL("../../", import.meta.url));
  it.skipIf(!existsSync(`${root}data/items`))("items.json esta em dia com data/items/*.tres", () => {
    expect(() => execFileSync(process.execPath, [`${root}tools/gen_items_catalog.mjs`, "--check"], { stdio: "pipe" })).not.toThrow();
  });
});

describe("progressao", () => {
  it("curva round(100 * L^1.5) e nivel maximo", () => {
    expect([1, 2, 3, 4].map(xpToNext)).toEqual([100, 283, 520, 800]);
    expect(xpToNext(MAX_LEVEL)).toBe(0);
    expect(levelForXp(0)).toBe(1);
    expect(levelForXp(99)).toBe(1);
    expect(levelForXp(100)).toBe(2);
    expect(levelForXp(totalXpForLevel(10) - 1)).toBe(9);
    expect(levelForXp(totalXpForLevel(10))).toBe(10);
    expect(levelForXp(MAX_TOTAL_XP)).toBe(MAX_LEVEL);
    expect(applyXp(0, 10 ** 12)).toEqual({ xp: MAX_TOTAL_XP, level: MAX_LEVEL });
    expect(applyXp(5, -10)).toEqual({ xp: 5, level: 1 });
  });
  it("limites carregam de env e rejeitam valor invalido", () => {
    expect(loadCharacterLimits({ CHARACTER_MAX_PER_ACCOUNT: "3" }).maxCharactersPerAccount).toBe(3);
    expect(() => loadCharacterLimits({ CHARACTER_INVENTORY_CAPACITY: "0" })).toThrow();
    expect(() => loadCharacterLimits({ CHARACTER_MAX_PER_ACCOUNT: "abc" })).toThrow();
  });
});

describe("criar/listar/ler personagens", () => {
  it("cria com kit inicial equipado, nivel 1, revision 0, stats base", async () => {
    const acc = await newAccount();
    const c = await newChar(acc);
    expect(c).toMatchObject({ level: 1, xp: 0, revision: 0, class_id: "warrior", inventory_capacity: 24, inventory: [], equipment: { weapon: "sword_basic", armor: "armor_leather" } });
    expect(c.stats).toMatchObject({ max_health: 100, attack_power: 10 });
    const list = await call(app, "GET", "/v1/characters", { as: acc });
    expect(list.json.characters).toHaveLength(1);
    expect(list.json.characters[0].id).toBe(c.id);
  });

  it.each([
    ["curto", "a"], ["longo", "x".repeat(25)], ["espacos nas pontas so (trim) curto", " a "], ["caractere inseguro", "Bob<script>"],
    ["espaco duplo", "Bob  Lee"], ["comeca com hifen", "-Bob"], ["emoji", "Bob\u{1F600}"], ["nao string", 123],
  ])("recusa nome invalido: %s", async (_n, name) => {
    const acc = await newAccount();
    const r = await call(app, "POST", "/v1/characters", { as: acc, body: { name, class_id: "warrior" } });
    expect(r.status).toBe(400);
    expect(r.json.error.code).toBe("invalid_name");
  });

  it("aceita nomes validos (acentos, hifen, apostrofo) e normaliza trim", () => {
    expect(validateCharacterName("  João D'Arc-2  ")).toBe("João D'Arc-2");
    expect(validateCharacterName("ab")).toBe("ab");
    expect(validateCharacterName("x".repeat(24))).toHaveLength(24);
  });

  it("class_id so da lista permitida; campos extras e corpo invalido => 400", async () => {
    const acc = await newAccount();
    expect((await call(app, "POST", "/v1/characters", { as: acc, body: { name: uname(), class_id: "necromancer" } })).json.error.code).toBe("invalid_class");
    expect((await call(app, "POST", "/v1/characters", { as: acc, body: { name: uname(), class_id: "warrior", level: 50 } })).status).toBe(400);
    expect((await call(app, "POST", "/v1/characters", { as: acc, body: [] })).status).toBe(400);
  });

  it("nome unico case-insensitive => 409; reutilizavel apos soft delete", async () => {
    const a = await newAccount();
    const b = await newAccount();
    const name = `Zed${++seq}`;
    const c = await call(app, "POST", "/v1/characters", { as: a, body: { name, class_id: "warrior" } });
    expect(c.status).toBe(201);
    const dup = await call(app, "POST", "/v1/characters", { as: b, body: { name: name.toUpperCase(), class_id: "warrior" } });
    expect(dup.status).toBe(409);
    expect(dup.json.error.code).toBe("name_taken");
    expect((await call(app, "DELETE", `/v1/characters/${c.json.character.id}`, { as: a })).status).toBe(204);
    expect((await call(app, "POST", "/v1/characters", { as: b, body: { name: name.toLowerCase(), class_id: "warrior" } })).status).toBe(201);
  });

  it("limite por conta (409) e exato sob concorrencia", async () => {
    const small = mkApp({ ...DEFAULT_LIMITS, maxCharactersPerAccount: 2 });
    const acc = await newAccount();
    await newChar(acc, small);
    await newChar(acc, small);
    const over = await call(small, "POST", "/v1/characters", { as: acc, body: { name: uname(), class_id: "warrior" } });
    expect(over.status).toBe(409);
    expect(over.json.error.code).toBe("character_limit");

    const acc2 = await newAccount();
    const rs = await Promise.all(Array.from({ length: 6 }, () => call(small, "POST", "/v1/characters", { as: acc2, body: { name: uname(), class_id: "warrior" } })));
    expect(rs.filter((r) => r.status === 201)).toHaveLength(2);
    expect(rs.filter((r) => r.status === 409)).toHaveLength(4);
    expect((await call(small, "GET", "/v1/characters", { as: acc2 })).json.characters).toHaveLength(2);
  });

  it("exige autenticacao", async () => {
    expect((await call(app, "GET", "/v1/characters")).status).toBe(401);
    expect((await call(app, "POST", "/v1/characters", { body: { name: "Abc", class_id: "warrior" } })).status).toBe(401);
  });
});

describe("ownership e isolamento", () => {
  it("outra conta recebe 404 em GET/DELETE e nao ve o personagem na lista", async () => {
    const a = await newAccount();
    const b = await newAccount();
    const c = await newChar(a);
    expect((await call(app, "GET", `/v1/characters/${c.id}`, { as: b })).status).toBe(404);
    expect((await call(app, "DELETE", `/v1/characters/${c.id}`, { as: b })).status).toBe(404);
    expect((await call(app, "GET", "/v1/characters", { as: b })).json.characters).toEqual([]);
    expect((await call(app, "GET", `/v1/characters/${c.id}`, { as: a })).status).toBe(200);
    // inexistente tem a MESMA resposta que alheio
    const ghost = await call(app, "GET", "/v1/characters/00000000-0000-4000-8000-000000000000", { as: b });
    const foreign = await call(app, "GET", `/v1/characters/${c.id}`, { as: b });
    expect(ghost).toEqual(foreign);
    expect((await call(app, "GET", `/v1/characters/${c.id}`, { as: a })).json.character.id).toBe(c.id);
  });
  it("id malformado => 400", async () => {
    const a = await newAccount();
    expect((await call(app, "GET", "/v1/characters/abc", { as: a })).status).toBe(400);
    expect((await call(app, "GET", "/internal/characters/abc", { internal: true })).status).toBe(400);
  });
});

describe("soft delete e lock de sessao", () => {
  it("recusa com lock ativo, apaga sem lock e some das leituras", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const sid = await mkSession(db);
    await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1, $2)", [c.id, sid]);
    const blocked = await call(app, "DELETE", `/v1/characters/${c.id}`, { as: a });
    expect(blocked.status).toBe(409);
    expect(blocked.json.error.code).toBe("character_in_session");
    expect((await call(app, "GET", `/v1/characters/${c.id}`, { as: a })).status).toBe(200);

    await db.query("DELETE FROM character_locks WHERE character_id = $1", [c.id]);
    expect((await call(app, "DELETE", `/v1/characters/${c.id}`, { as: a })).status).toBe(204);
    expect((await call(app, "GET", `/v1/characters/${c.id}`, { as: a })).status).toBe(404);
    expect((await call(app, "GET", `/internal/characters/${c.id}`, { internal: true })).status).toBe(404);
    expect((await call(app, "GET", "/v1/characters", { as: a })).json.characters).toEqual([]);
    expect((await call(app, "DELETE", `/v1/characters/${c.id}`, { as: a })).status).toBe(404);
    const row = await db.query<{ deleted_at: Date | null }>("SELECT deleted_at FROM characters WHERE id = $1", [c.id]);
    expect(row.rows[0]!.deleted_at).not.toBeNull(); // linha preservada
  });
});

describe("/internal exige segredo de servico", () => {
  it("sem header, token de usuario e segredo errado => 401; certo => 200", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const paths: [string, string][] = [["GET", `/internal/characters/${c.id}`], ["POST", `/internal/characters/${c.id}/checkpoint`], ["POST", `/internal/characters/${c.id}/rewards`]];
    for (const [m, p] of paths) {
      const body = m === "POST" ? {} : undefined;
      expect((await call(app, m, p, { body })).status).toBe(401);
      expect((await call(app, m, p, { as: a, body })).status).toBe(401);
      expect((await call(app, m, p, { internal: "wrong-secret", body })).status).toBe(401);
    }
    expect((await call(app, "GET", `/internal/characters/${c.id}`, { internal: true })).status).toBe(200);
  });
  it("buildApp real registra as rotas: /internal sem segredo => 401, /v1 sem token => 401", async () => {
    const real = buildApp({ config: cfg, db });
    expect((await call(real, "GET", "/internal/characters/00000000-0000-4000-8000-000000000000")).status).toBe(401);
    expect((await call(real, "GET", "/v1/characters")).status).toBe(401);
    expect((await call(real, "GET", "/internal/characters/00000000-0000-4000-8000-000000000000", { internal: true })).status).toBe(404);
  });
  it("GET interno devolve estado completo + revision", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const g = await get(c.id);
    expect(g).toMatchObject({ id: c.id, account_id: a, revision: 0, level: 1, schema_version: 1, equipment: { weapon: "sword_basic" } });
  });
});

describe("checkpoint", () => {
  it("estado valido persiste, incrementa revision e e relido igual", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const st = { ...stateOf(c), level: 3, xp: 400, inventory: [{ slot: 5, item_id: "potion_minor", qty: 20 }, { slot: 0, item_id: "sword_rare", qty: 1 }], equipment: { weapon: "sword_basic", trinket: "amulet_vigor" } };
    const r = await cp(c.id, 0, st);
    expect(r.status).toBe(200);
    expect(r.json.character.revision).toBe(1);
    const g = await get(c.id);
    expect(g).toMatchObject({ revision: 1, level: 3, xp: 400, equipment: { weapon: "sword_basic", trinket: "amulet_vigor" } });
    expect(g.equipment.armor).toBeUndefined();
    expect(g.inventory).toEqual([{ slot: 0, item_id: "sword_rare", qty: 1 }, { slot: 5, item_id: "potion_minor", qty: 20 }]);
  });

  it("revision antiga => 409 sem alterar nada", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    expect((await cp(c.id, 0, { ...stateOf(c), xp: 10 })).status).toBe(200);
    const stale = await cp(c.id, 0, { ...stateOf(c), xp: 99, inventory: [{ slot: 0, item_id: "scrap_material", qty: 5 }] });
    expect(stale.status).toBe(409);
    expect(stale.json.error.code).toBe("revision_conflict");
    const g = await get(c.id);
    expect(g).toMatchObject({ revision: 1, xp: 10, inventory: [] });
    expect((await cp(c.id, 7, stateOf(g))).status).toBe(409); // revision futura
  });

  it("checkpoint sem lock (personagem inexistente/apagado/sem sessao) => 409 fencing; sem cabecalho => 400; estado vazio => 422", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const st = stateOf(c);
    const fake = "11111111-1111-4111-8111-111111111111";
    expect((await cp("00000000-0000-4000-8000-000000000000", 0, st, fake)).status).toBe(409);
    expect((await cp(c.id, 0, st, null)).status).toBe(400);
    expect((await cp(c.id, 0, {})).status).toBe(422);
    const d = await newChar(a);
    await call(app, "DELETE", `/v1/characters/${d.id}`, { as: a });
    expect((await cp(d.id, 0, st, fake)).status).toBe(409);
  });

  const bad: [string, (s: any) => void][] = [
    ["item desconhecido", (s) => { s.inventory = [{ slot: 0, item_id: "espada_do_hax", qty: 1 }]; }],
    ["stack acima do max (potion 21)", (s) => { s.inventory = [{ slot: 0, item_id: "potion_minor", qty: 21 }]; }],
    ["nao empilhavel com qty 2", (s) => { s.inventory = [{ slot: 0, item_id: "sword_rare", qty: 2 }]; }],
    ["qty 0", (s) => { s.inventory = [{ slot: 0, item_id: "potion_minor", qty: 0 }]; }],
    ["slot >= capacidade", (s) => { s.inventory = [{ slot: 24, item_id: "potion_minor", qty: 1 }]; }],
    ["slot negativo", (s) => { s.inventory = [{ slot: -1, item_id: "potion_minor", qty: 1 }]; }],
    ["slot duplicado", (s) => { s.inventory = [{ slot: 1, item_id: "potion_minor", qty: 1 }, { slot: 1, item_id: "scrap_material", qty: 1 }]; }],
    ["acima da capacidade (25 entradas)", (s) => { s.inventory = Array.from({ length: 25 }, (_, i) => ({ slot: i, item_id: "potion_minor", qty: 1 })); }],
    ["equipamento no slot errado", (s) => { s.equipment = { weapon: "armor_leather" }; }],
    ["slot de equipamento inexistente", (s) => { s.equipment = { head: "sword_basic" }; }],
    ["equipar item sem slot", (s) => { s.equipment = { trinket: "potion_minor" }; }],
    ["equipar item desconhecido", (s) => { s.equipment = { weapon: "x_sword" }; }],
    ["nivel incoerente com xp", (s) => { s.level = 5; s.xp = 10; }],
    ["nivel acima do maximo", (s) => { s.level = 51; }],
    ["xp acima do maximo", (s) => { s.xp = MAX_TOTAL_XP + 1; s.level = 50; }],
    ["xp fracionario", (s) => { s.xp = 1.5; }],
    ["xp negativo", (s) => { s.xp = -1; }],
    ["stat fora do intervalo", (s) => { s.stats.resistance = 0.9; }],
    ["stat NaN-like (string)", (s) => { s.stats.max_health = "100"; }],
    ["stat desconhecido", (s) => { s.stats.god_mode = 1; }],
    ["campo extra no estado", (s) => { s.gold = 999999; }],
    ["schema_version errada", (s) => { s.schema_version = 2; }],
  ];
  it.each(bad)("estado invalido => 422 e nada muda: %s", async (_n, mut) => {
    const a = await newAccount();
    const c = await newChar(a);
    const s: any = structuredClone(stateOf(c));
    mut(s);
    const r = await cp(c.id, 0, s);
    expect(r.status).toBe(422);
    expect(r.json.error.code).toBe("invalid_state");
    expect(await get(c.id)).toMatchObject({ revision: 0, level: 1, xp: 0, inventory: [] });
  });

  it("corpo malformado => 400", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    expect((await call(app, "POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, body: { state: stateOf(c) } })).status).toBe(400);
    expect((await call(app, "POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, body: { expected_revision: -1, state: stateOf(c) } })).status).toBe(400);
    expect((await call(app, "POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, body: { expected_revision: 0, state: stateOf(c), extra: 1 } })).status).toBe(400);
  });

  it("limites de sanidade: xp nao diminui, ganho de xp e de item por checkpoint limitados", async () => {
    const tight = mkApp({ ...DEFAULT_LIMITS, checkpointMaxXpGain: 1000, checkpointMaxItemGain: 3 });
    const a = await newAccount();
    const c = await newChar(a, tight);
    const tcp = (rev: number, s: unknown) => call(tight, "POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, body: { expected_revision: rev, state: s } });
    const base = stateOf(c);
    const tooMuchXp = await tcp(0, { ...base, xp: 1001, level: levelForXp(1001) });
    expect(tooMuchXp.status).toBe(422);
    expect(tooMuchXp.json.error.message).toMatch(/xp/);
    const tooManyItems = await tcp(0, { ...base, inventory: [{ slot: 0, item_id: "scrap_material", qty: 4 }] });
    expect(tooManyItems.status).toBe(422);
    expect((await tcp(0, { ...base, xp: 1000, level: levelForXp(1000), inventory: [{ slot: 0, item_id: "scrap_material", qty: 3 }] })).status).toBe(200);
    const down = await tcp(1, { ...base, xp: 10, level: 1 });
    expect(down.status).toBe(422);
    // equipar sword_basic extra (equip + inventario) conta como ganho: total 2 > 1+... limite 3, ok; 5 nao
    expect(await get(c.id)).toMatchObject({ revision: 1, xp: 1000 });
  });

  it("checkpoints concorrentes com a mesma revision: so um vence", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const rs = await Promise.all(Array.from({ length: 6 }, (_, i) => cp(c.id, 0, { ...stateOf(c), xp: 10 + i, level: 1 })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.status === 409)).toHaveLength(5);
    const winner = rs.find((r) => r.status === 200)!;
    const g = await get(c.id);
    expect(g.revision).toBe(1);
    expect(g.xp).toBe(winner.json.character.xp);
  });

  it("falha no meio do checkpoint => rollback total (nada persistido)", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const ctx = svcCtx();
    const failing = failOn(db, /INSERT INTO character_equipment/);
    const st = { ...stateOf(c), xp: 50, inventory: [{ slot: 0, item_id: "scrap_material", qty: 9 }], equipment: { weapon: "sword_rare" } } as any;
    await expect(checkpoint(failing, ctx, c.id, 0, st)).rejects.toThrow(/falha injetada/);
    const g = await get(c.id);
    expect(g).toMatchObject({ revision: 0, xp: 0, inventory: [], equipment: { weapon: "sword_basic", armor: "armor_leather" } });
  });
});

function svcCtx(): ServiceCtx {
  return { catalog, limits: DEFAULT_LIMITS, now: Date.now, log: createLogger({ level: "error" }) };
}
/** Db que lanca ao executar SQL que casa `re` dentro de uma transacao. */
function failOn(real: Db, re: RegExp): Db {
  const wrap = (d: Db): Db => ({
    query: async (sql, p) => { if (re.test(sql)) throw new Error("falha injetada"); return d.query(sql, p); },
    exec: (sql) => d.exec(sql),
    tx: (fn) => d.tx((inner) => fn(wrap(inner))),
    close: () => d.close(),
  });
  return wrap(real);
}

describe("recompensas", () => {
  const key = () => `key-${++seq}-abcdefgh`;

  it("aplica xp e itens, incrementa revision, devolve resultado", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const r = await reward(c.id, { idempotency_key: key(), xp: 50, items: [{ item_id: "potion_minor", qty: 5 }, { item_id: "sword_rare", qty: 1 }] });
    expect(r.status).toBe(200);
    expect(r.json.replayed).toBe(false);
    expect(r.json.result).toMatchObject({ xp_granted: 50, level_before: 1, level_after: 1, levels_gained: 0, revision: 1 });
    expect(await get(c.id)).toMatchObject({ revision: 1, xp: 50, inventory: [{ slot: 0, item_id: "potion_minor", qty: 5 }, { slot: 1, item_id: "sword_rare", qty: 1 }] });
  });

  it("idempotente: mesma chave repetida devolve o original sem reaplicar", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const body = { idempotency_key: key(), xp: 120, items: [{ item_id: "scrap_material", qty: 7 }] };
    const first = await reward(c.id, body);
    const again = await reward(c.id, body);
    const third = await reward(c.id, body);
    expect(again.status).toBe(200);
    expect(again.json.replayed).toBe(true);
    expect(again.json.result).toEqual(first.json.result);
    expect(third.json.result).toEqual(first.json.result);
    expect(await get(c.id)).toMatchObject({ revision: 1, xp: 120, level: 2, inventory: [{ slot: 0, item_id: "scrap_material", qty: 7 }] });
    const n = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM reward_claims WHERE character_id = $1", [c.id]);
    expect(n.rows[0]!.n).toBe(1);
  });

  it("mesma chave com conteudo diferente => 409 e nada aplicado", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const k = key();
    await reward(c.id, { idempotency_key: k, xp: 10 });
    const r = await reward(c.id, { idempotency_key: k, xp: 999 });
    expect(r.status).toBe(409);
    expect(r.json.error.code).toBe("idempotency_key_reuse");
    expect((await get(c.id)).xp).toBe(10);
  });

  it("a mesma chave em personagens diferentes e independente", async () => {
    const a = await newAccount();
    const c1 = await newChar(a);
    const c2 = await newChar(a);
    const k = key();
    expect((await reward(c1.id, { idempotency_key: k, xp: 5 })).json.replayed).toBe(false);
    expect((await reward(c2.id, { idempotency_key: k, xp: 5 })).json.replayed).toBe(false);
  });

  it("concorrente: 8 requisicoes simultaneas com a MESMA chave aplicam uma vez", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const body = { idempotency_key: key(), xp: 30, items: [{ item_id: "potion_minor", qty: 4 }] };
    const rs = await Promise.all(Array.from({ length: 8 }, () => reward(c.id, body)));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => !r.json.replayed)).toHaveLength(1);
    for (const r of rs) expect(r.json.result).toEqual(rs[0]!.json.result); // jsonb reordena chaves: compara estruturalmente
    expect(await get(c.id)).toMatchObject({ revision: 1, xp: 30, inventory: [{ slot: 0, item_id: "potion_minor", qty: 4 }] });
  });

  it("concorrente: chaves diferentes todas aplicam; itens e xp conservados", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const rs = await Promise.all(Array.from({ length: 10 }, () => reward(c.id, { idempotency_key: key(), xp: 7, items: [{ item_id: "scrap_material", qty: 13 }] })));
    expect(rs.every((r) => r.status === 200 && r.json.replayed === false)).toBe(true);
    const g = await get(c.id);
    expect(g.xp).toBe(70);
    expect(g.revision).toBe(10);
    const total = g.inventory.reduce((s: number, e: any) => s + e.qty, 0);
    expect(total).toBe(130); // 10 * 13, conservacao
    expect(g.inventory.every((e: any) => e.qty <= 50)).toBe(true);
    expect(new Set(rs.map((r) => r.json.result.revision)).size).toBe(10); // revisions distintas
  });

  it("level-up multiplo pela curva", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const need = totalXpForLevel(5) + 10;
    const r = await reward(c.id, { idempotency_key: key(), xp: need });
    expect(r.json.result).toMatchObject({ level_before: 1, level_after: 5, levels_gained: 4, xp_total: need });
    expect(await get(c.id)).toMatchObject({ level: 5, xp: need });
  });

  it("nivel maximo: satura o xp e nao passa de 50", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    let last: any;
    for (let i = 0; i < 2; i++) last = await reward(c.id, { idempotency_key: key(), xp: 1_000_000 });
    expect(last.json.result.level_after).toBe(MAX_LEVEL);
    expect(last.json.result.xp_total).toBe(MAX_TOTAL_XP);
    const again = await reward(c.id, { idempotency_key: key(), xp: 500 });
    expect(again.json.result).toMatchObject({ xp_granted: 0, levels_gained: 0, level_after: MAX_LEVEL });
    expect(await get(c.id)).toMatchObject({ level: 50, xp: MAX_TOTAL_XP });
  });

  it("empilha ate max_stack e transborda para novos slots", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    await reward(c.id, { idempotency_key: key(), items: [{ item_id: "potion_minor", qty: 15 }] });
    await reward(c.id, { idempotency_key: key(), items: [{ item_id: "potion_minor", qty: 30 }, { item_id: "sword_rare", qty: 2 }] });
    const g = await get(c.id);
    expect(g.inventory).toEqual([
      { slot: 0, item_id: "potion_minor", qty: 20 },
      { slot: 1, item_id: "potion_minor", qty: 20 },
      { slot: 2, item_id: "potion_minor", qty: 5 },
      { slot: 3, item_id: "sword_rare", qty: 1 },
      { slot: 4, item_id: "sword_rare", qty: 1 },
    ]);
  });

  it("sem espaco => 409 atomico: nem xp nem itens, chave nao consumida", async () => {
    const tiny = mkApp({ ...DEFAULT_LIMITS, inventoryCapacity: 2 });
    const a = await newAccount();
    const c = await newChar(a, tiny);
    const rw = (b: unknown) => call(tiny, "POST", `/internal/characters/${c.id}/rewards`, { internal: true, body: b });
    await rw({ idempotency_key: key(), items: [{ item_id: "sword_rare", qty: 1 }] });
    const k = key();
    const full = await rw({ idempotency_key: k, xp: 500, items: [{ item_id: "potion_minor", qty: 1 }, { item_id: "scrap_material", qty: 1 }] });
    expect(full.status).toBe(409);
    expect(full.json.error.code).toBe("inventory_full");
    const g = await call(tiny, "GET", `/internal/characters/${c.id}`, { internal: true });
    expect(g.json.character).toMatchObject({ revision: 1, xp: 0, level: 1, inventory: [{ slot: 0, item_id: "sword_rare", qty: 1 }] });
    const claims = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM reward_claims WHERE character_id = $1 AND idempotency_key = $2", [c.id, k]);
    expect(claims.rows[0]!.n).toBe(0);
    // so xp (sem itens) com inventario cheio funciona
    expect((await rw({ idempotency_key: key(), xp: 5 })).status).toBe(200);
  });

  it("falha no meio da recompensa => rollback total (xp, itens, claim)", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const k = key();
    const failing = failOn(db, /INSERT INTO reward_claims/);
    const req = { idempotency_key: k, xp: 200, items: [{ item_id: "potion_minor" as const, qty: 3 }] };
    await expect(grantReward(failing, svcCtx(), c.id, req)).rejects.toThrow(/falha injetada/);
    expect(await get(c.id)).toMatchObject({ revision: 0, xp: 0, level: 1, inventory: [] });
    const claims = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM reward_claims WHERE character_id = $1", [c.id]);
    expect(claims.rows[0]!.n).toBe(0);
    // e a mesma chave ainda pode ser usada depois
    expect((await reward(c.id, req)).json.replayed).toBe(false);
  });

  it("recompensa e checkpoint disputam a mesma revision: ou um ou outro vence", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const [r, k] = await Promise.all([
      reward(c.id, { idempotency_key: key(), xp: 20 }),
      cp(c.id, 0, { ...stateOf(c), xp: 5 }),
    ]);
    expect(r.status).toBe(200); // recompensa nao usa expected_revision
    expect([200, 409]).toContain(k.status);
    const g = await get(c.id);
    expect(g.revision).toBe(k.status === 200 ? 2 : 1);
  });

  it("validacao de entrada", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    const ok1 = key();
    const cases: [string, unknown][] = [
      ["sem chave", { xp: 1 }],
      ["chave curta", { idempotency_key: "short", xp: 1 }],
      ["chave com caractere invalido", { idempotency_key: "bad key with spaces", xp: 1 }],
      ["vazia", { idempotency_key: ok1 }],
      ["xp negativo", { idempotency_key: ok1, xp: -1 }],
      ["xp fracionario", { idempotency_key: ok1, xp: 1.5 }],
      ["xp enorme", { idempotency_key: ok1, xp: 1_000_001 }],
      ["xp zero sem itens", { idempotency_key: ok1, xp: 0 }],
      ["item desconhecido", { idempotency_key: ok1, items: [{ item_id: "ouro", qty: 1 }] }],
      ["qty 0", { idempotency_key: ok1, items: [{ item_id: "potion_minor", qty: 0 }] }],
      ["qty 1000", { idempotency_key: ok1, items: [{ item_id: "potion_minor", qty: 1000 }] }],
      ["21 itens", { idempotency_key: ok1, items: Array.from({ length: 21 }, () => ({ item_id: "potion_minor", qty: 1 })) }],
      ["campo extra", { idempotency_key: ok1, xp: 1, gold: 5 }],
      ["campo extra no item", { idempotency_key: ok1, items: [{ item_id: "potion_minor", qty: 1, price: 0 }] }],
      ["items nao lista", { idempotency_key: ok1, items: "x" }],
    ];
    for (const [name, body] of cases) {
      const r = await reward(c.id, body);
      expect(r.status, name).toBe(400);
    }
    expect((await reward(c.id, { idempotency_key: ok1, items: Array.from({ length: 20 }, () => ({ item_id: "scrap_material", qty: 1 })) })).status).toBe(200);
    expect((await reward("00000000-0000-4000-8000-000000000000", { idempotency_key: key(), xp: 1 }, FAKE_SESSION)).status).toBe(409); // sem lock: fencing
    expect((await get(c.id)).inventory).toEqual([{ slot: 0, item_id: "scrap_material", qty: 20 }]); // 20 linhas mescladas
  });

  it("recompensa em personagem apagado (sem lock) => 409 fencing", async () => {
    const a = await newAccount();
    const c = await newChar(a);
    await call(app, "DELETE", `/v1/characters/${c.id}`, { as: a });
    expect((await reward(c.id, { idempotency_key: key(), xp: 1 }, FAKE_SESSION)).status).toBe(409);
  });
});
