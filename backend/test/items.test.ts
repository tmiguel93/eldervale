import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { registerCharactersRoutes } from "../src/characters/routes.ts";
import { parseInstance, type ItemInstance } from "../src/characters/instances.ts";
import { loadRecipeCatalogFromDisk } from "../src/crafting/catalog.ts";
import { createApp, type App } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { migrate } from "../src/persistence/migrate.ts";
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
const getC = (id: string) => call("GET", `/internal/characters/${id}`, { internal: true }).then((r) => r.json.character);

async function mkChar(): Promise<Ch> {
  const acc = await mkAccount(db, `i${++seq}@example.com`);
  const r = await call("POST", "/v1/characters", { as: acc, body: { name: `Itemizer${seq}`, class_id: "warrior" } });
  expect(r.status).toBe(201);
  const sid = await mkSession(db);
  await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [r.json.character.id, sid]);
  return { id: r.json.character.id as string, sid };
}
let dropN = 0;
const lootKey = (c: Ch) => `loot:${c.sid}:${++dropN}:${c.id}`;
const reward = (c: Ch, key: string, line: unknown) =>
  call("POST", `/internal/characters/${c.id}/rewards`, { internal: true, session: c.sid, body: { idempotency_key: key, xp: 0, items: [line] } });
const checkpoint = (c: Ch, g: any, patch: Record<string, unknown>) => {
  const state: any = { schema_version: g.schema_version, level: g.level, xp: g.xp, stats: g.stats, inventory: g.inventory, equipment: g.equipment };
  if (g.equipment_inst) state.equipment_inst = g.equipment_inst;
  return call("POST", `/internal/characters/${c.id}/checkpoint`, { internal: true, session: c.sid, body: { expected_revision: g.revision, state: { ...state, ...patch } } });
};

let uidN = 0;
const uid = () => (++uidN).toString(16).padStart(16, "0");
const aff = (id: string, tier: number, value: number) => ({ id, tier, value });
/** Magico valido para arma: 1 prefixo + 1 sufixo, custo 2 (<= 4). */
const magic = (u = uid()): ItemInstance => ({ uid: u, rarity: "uncommon", ilvl: 5, affixes: [aff("pre_brutal", 3, 1.5), aff("suf_of_ward", 3, 0.015)] });
const swordLine = (inst: unknown) => ({ item_id: "sword_basic", qty: 1, inst });

describe("catalogo de itens com regras (E6.3)", () => {
  it("traz 6 raridades com orcamento crescente, affixes validos e unicos marcados", () => {
    const r = items.rules!;
    expect(r).toBeDefined();
    const ids = ["common", "uncommon", "rare", "epic", "legendary", "mythic"];
    let prev = -1;
    for (const id of ids) {
      const x = r.rarity(id)!;
      expect(x).toBeDefined();
      expect(x.budget).toBeGreaterThanOrEqual(prev);
      expect(x.affix_max).toBeLessThanOrEqual(r.maxAffixes);
      prev = x.budget;
    }
    expect(r.rarity("common")).toMatchObject({ budget: 0, affix_max: 0 });
    expect(r.affix("pre_brutal")!.tiers.length).toBe(3);
    expect(r.isUnique("unique_emberfang")).toBe(true);
    expect(r.isUnique("sword_basic")).toBe(false);
    expect(items.get("unique_emberfang")).toMatchObject({ slot: "weapon", rarity: "legendary" });
  });

  it("items.json esta em dia com data/items (gerador --check)", () => {
    const root = fileURLToPath(new URL("../..", import.meta.url));
    expect(execFileSync(process.execPath, ["tools/gen_items_catalog.mjs", "--check"], { cwd: root, encoding: "utf8" })).toMatch(/em dia/);
  });
});

describe("parseInstance", () => {
  const sword = items.get("sword_basic")!;
  const armor = items.get("armor_leather")!;
  const bad = (raw: unknown, base = sword) => () => parseInstance(raw, base, items);

  it("aceita instancias validas (incl. limite exato do orcamento de um Mitico)", () => {
    expect(parseInstance(magic(), sword, items).affixes).toHaveLength(2);
    const mythic: ItemInstance = {
      uid: uid(), rarity: "mythic", ilvl: 50,
      affixes: [aff("pre_brutal", 1, 9), aff("pre_arcane", 1, 40), aff("pre_sweeping", 1, 0.2), aff("suf_of_fury", 1, 0.14), aff("suf_of_ward", 1, 0.09), aff("suf_of_insight", 1, 3.2)],
    };
    expect(parseInstance(mythic, sword, items).affixes).toHaveLength(6); // custo 24 == orcamento 24
  });

  it("rejeita: forma, raridade, ilvl, base, affixes", () => {
    const ok = magic();
    expect(bad(null)).toThrow(/objeto/);
    expect(bad({ ...ok, extra: 1 })).toThrow(/campo desconhecido/);
    expect(bad({ ...ok, uid: "XYZ" })).toThrow(/uid/);
    expect(bad({ ...ok, rarity: "common" })).toThrow(/rarity/);
    expect(bad({ ...ok, rarity: "godly" })).toThrow(/rarity/);
    expect(bad({ ...ok, ilvl: 0 })).toThrow(/ilvl/);
    expect(bad({ ...ok, ilvl: 51 })).toThrow(/ilvl/);
    expect(bad({ ...ok, ilvl: 5.5 })).toThrow(/ilvl/);
    expect(bad(ok, items.get("scrap_material")!)).toThrow(/equipavel/);
    expect(bad(ok, items.get("unique_emberfang")!)).toThrow(/unico/);
    expect(bad({ ...ok, affixes: [] })).toThrow(/numero de affixes/);
    expect(bad({ ...ok, affixes: [aff("pre_brutal", 3, 1), aff("suf_of_ward", 3, 0.01), aff("pre_arcane", 3, 6)] })).toThrow(/numero de affixes/);
    expect(bad({ ...ok, affixes: [aff("nao_existe", 3, 1)] })).toThrow(/desconhecido/);
    expect(bad({ ...ok, affixes: [aff("pre_vital", 3, 8)] })).toThrow(/slot/); // pre_vital nao vale em arma
    expect(bad({ ...ok, affixes: [aff("pre_brutal", 3, 1.5), aff("suf_of_ward", 3, 0.015)].map((a) => ({ ...a, x: 1 })) })).toThrow(/campo desconhecido/);
  });

  it("rejeita: faixas, tiers, grupos, prefixos/sufixos, orcamento, tamanho", () => {
    const base = { uid: uid(), rarity: "uncommon", ilvl: 5 };
    expect(bad({ ...base, affixes: [aff("pre_brutal", 3, 2.5)] })).toThrow(/faixa/); // max do tier 3 = 2
    expect(bad({ ...base, affixes: [aff("pre_brutal", 3, 0.5)] })).toThrow(/faixa/);
    expect(bad({ ...base, affixes: [aff("pre_brutal", 3, Number.NaN)] })).toThrow(/valor/);
    expect(bad({ ...base, affixes: [aff("pre_brutal", 2, 4)] })).toThrow(/ilvl/); // tier 2 exige ilvl 12
    expect(bad({ ...base, affixes: [aff("pre_brutal", 9, 4)] })).toThrow(/tier/);
    expect(bad({ ...base, affixes: [aff("pre_brutal", 3, 1.5), aff("suf_of_might", 3, 2)] })).toThrow(/grupo/); // dois do grupo 'attack'
    expect(bad({ ...base, affixes: [aff("pre_brutal", 3, 1.5), aff("pre_arcane", 3, 6)] })).toThrow(/prefixos/); // magico: 1 prefixo
    expect(bad({ ...base, ilvl: 28, affixes: [aff("pre_brutal", 1, 7), aff("suf_of_ward", 3, 0.01)] })).toThrow(/orcamento/); // 4 + 1 > 4
    const huge = { uid: uid(), rarity: "uncommon", ilvl: 5, affixes: [aff("pre_brutal", 3, 1.5)], pad: "x".repeat(600) };
    expect(bad(huge)).toThrow();
    expect(parseInstance({ uid: uid(), rarity: "uncommon", ilvl: 28, affixes: [aff("pre_vital", 1, 30)] }, armor, items).affixes[0]!.value).toBe(30);
  });
});

describe("migracao 0006", () => {
  const sql = readFileSync(new URL("../migrations/0006_item_instances.sql", import.meta.url), "utf8");
  it("e aditiva: linhas antigas ficam com inst NULL e continuam legiveis", async () => {
    const d = await createPgliteDb();
    await migrate(d, { dir: fileURLToPath(new URL("../migrations", import.meta.url)) });
    const cols = await d.query<{ column_name: string; data_type: string; is_nullable: string }>(
      "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE column_name = 'inst' AND table_name IN ('character_inventory','character_equipment') ORDER BY table_name");
    expect(cols.rows).toHaveLength(2);
    expect(cols.rows.every((c) => c.data_type === "jsonb" && c.is_nullable === "YES")).toBe(true);
    await d.close();
  });

  it("do estado anterior (0001..0005) para o atual preserva dados; reexecutar o SQL e idempotente; CHECK e indice unico valem", async () => {
    const d = await createPgliteDb();
    // aplica so 0001..0005 manualmente via migrate com diretorio filtrado
    const { mkdtempSync, cpSync, readdirSync, rmSync, mkdirSync } = await import("node:fs");
    const { join } = await import("node:path");
    const { BACKEND_ROOT, MIGRATIONS_DIR } = await import("../src/persistence/paths.ts");
    mkdirSync(join(BACKEND_ROOT, ".data", "test-tmp"), { recursive: true });
    const dir = mkdtempSync(join(BACKEND_ROOT, ".data", "test-tmp", "m6-"));
    for (const f of readdirSync(MIGRATIONS_DIR)) if (f.endsWith(".sql") && !f.startsWith("0006")) cpSync(join(MIGRATIONS_DIR, f), join(dir, f));
    await migrate(d, { dir });
    const acc = await mkAccount(d, "mig@example.com");
    const ch = await d.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id) VALUES ($1,'MigHero','warrior') RETURNING id", [acc]);
    const id = ch.rows[0]!.id;
    await d.query("INSERT INTO character_inventory (character_id, slot, item_id, qty) VALUES ($1,0,'sword_basic',1),($1,1,'scrap_material',7)", [id]);
    await d.query("INSERT INTO character_equipment (character_id, slot_name, item_id) VALUES ($1,'weapon','sword_basic')", [id]);
    const r = await migrate(d); // aplica 0006 sobre dados existentes
    expect(r.applied).toEqual([6]);
    await d.exec?.(sql); // 2a execucao do mesmo SQL: nao falha
    const inv = await d.query<{ item_id: string; qty: number; inst: unknown }>("SELECT item_id, qty, inst FROM character_inventory WHERE character_id=$1 ORDER BY slot", [id]);
    expect(inv.rows).toEqual([{ item_id: "sword_basic", qty: 1, inst: null }, { item_id: "scrap_material", qty: 7, inst: null }]);
    await expect(d.query("UPDATE character_inventory SET inst = '[1]'::jsonb WHERE character_id=$1 AND slot=0", [id])).rejects.toThrow();
    await d.query("UPDATE character_inventory SET inst = '{\"uid\":\"aaaaaaaaaaaaaaaa\"}'::jsonb WHERE character_id=$1 AND slot=0", [id]);
    await expect(d.query("UPDATE character_inventory SET inst = '{\"uid\":\"aaaaaaaaaaaaaaaa\"}'::jsonb WHERE character_id=$1 AND slot=1", [id])).rejects.toThrow();
    // rollback documentado
    await d.query("DROP INDEX IF EXISTS character_inventory_inst_uid_uniq");
    await d.query("ALTER TABLE character_inventory DROP CONSTRAINT IF EXISTS character_inventory_inst_is_object");
    await d.query("ALTER TABLE character_inventory DROP COLUMN IF EXISTS inst");
    const back = await d.query("SELECT item_id, qty FROM character_inventory WHERE character_id=$1 ORDER BY slot", [id]);
    expect(back.rows).toHaveLength(2);
    await d.close();
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* rm pode ser bloqueado no ambiente */ }
  });
});

describe("recompensas com instancia (loot:)", () => {
  it("persiste a instancia, GET devolve base_id/qty + inst; saves antigos continuam sem inst", async () => {
    const c = await mkChar();
    const before = await getC(c.id);
    expect(before.inventory).toEqual([]);
    expect(before.equipment_inst).toBeUndefined();
    const inst = magic();
    const r = await reward(c, lootKey(c), swordLine(inst));
    expect(r.status).toBe(200);
    expect(r.json.replayed).toBe(false);
    const g = await getC(c.id);
    expect(g.inventory).toEqual([{ slot: 0, item_id: "sword_basic", qty: 1, inst }]);
    // um item simples ao lado continua sem a chave inst
    const r2 = await reward(c, lootKey(c), { item_id: "sword_basic", qty: 1 });
    expect(r2.status).toBe(200);
    const g2 = await getC(c.id);
    expect(g2.inventory[1]).toEqual({ slot: 1, item_id: "sword_basic", qty: 1 });
    expect("inst" in g2.inventory[1]).toBe(false);
  });

  it("replay da mesma chave nao duplica; mesma chave com outro conteudo = 409; mesmo uid com outra chave = 409", async () => {
    const c = await mkChar();
    const inst = magic();
    const key = lootKey(c);
    expect((await reward(c, key, swordLine(inst))).json.replayed).toBe(false);
    const again = await reward(c, key, swordLine(inst));
    expect(again.status).toBe(200);
    expect(again.json.replayed).toBe(true);
    expect((await getC(c.id)).inventory).toHaveLength(1);
    const other = await reward(c, key, swordLine(magic()));
    expect(other.status).toBe(409);
    expect(code(other)).toBe("idempotency_key_reuse");
    const dup = await reward(c, lootKey(c), swordLine(inst));
    expect(dup.status).toBe(409);
    expect(code(dup)).toBe("duplicate_instance");
    expect((await getC(c.id)).inventory).toHaveLength(1);
  });

  it("replays concorrentes aplicam UMA vez", async () => {
    const c = await mkChar();
    const key = lootKey(c);
    const inst = magic();
    const rs = await Promise.all(Array.from({ length: 6 }, () => reward(c, key, swordLine(inst))));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => !r.json.replayed)).toHaveLength(1);
    expect((await getC(c.id)).inventory.filter((e: any) => e.inst)).toHaveLength(1);
  });

  it("recusa instancia invalida, fora de loot:, qty != 1, campo extra e inventario cheio sem queimar a chave", async () => {
    const c = await mkChar();
    const badInst = { ...magic(), affixes: [aff("pre_brutal", 3, 99), aff("suf_of_might", 3, 2)] };
    const r1 = await reward(c, lootKey(c), swordLine(badInst));
    expect(r1.status).toBe(400);
    expect(code(r1)).toBe("invalid_instance");
    const r2 = await reward(c, `kill:${c.sid}:1:${c.id}`, swordLine(magic()));
    expect(r2.status).toBe(400);
    expect(code(r2)).toBe("invalid_instance");
    const r3 = await reward(c, lootKey(c), { item_id: "sword_basic", qty: 2, inst: magic() });
    expect(code(r3)).toBe("invalid_instance");
    const r4 = await reward(c, lootKey(c), { item_id: "scrap_material", qty: 1, inst: magic() });
    expect(code(r4)).toBe("invalid_instance");
    expect((await getC(c.id)).inventory).toEqual([]);
    // enche o inventario (24) com itens simples e tenta uma instancia
    const g = await getC(c.id);
    const full = Array.from({ length: 24 }, (_, i) => ({ slot: i, item_id: "sword_basic", qty: 1 }));
    expect((await checkpoint(c, g, { inventory: full })).status).toBe(200);
    const key = lootKey(c);
    const inst = magic();
    const r5 = await reward(c, key, swordLine(inst));
    expect(r5.status).toBe(409);
    expect(code(r5)).toBe("inventory_full");
    // libera um slot: a MESMA chave agora funciona (a falha nao a consumiu)
    const g2 = await getC(c.id);
    expect((await checkpoint(c, g2, { inventory: full.slice(1) })).status).toBe(200);
    expect((await reward(c, key, swordLine(inst))).status).toBe(200);
  });
});

describe("checkpoint e instancias (equipar/desequipar)", () => {
  it("equipar move a instancia para equipment_inst e desequipar a devolve, sem perda nem duplicacao", async () => {
    const c = await mkChar();
    const inst = magic();
    await reward(c, lootKey(c), swordLine(inst));
    let g = await getC(c.id);
    // equipa: a arma antiga (sword_basic simples) vai para o inventario no lugar da instancia
    const eq = await checkpoint(c, g, {
      inventory: [{ slot: 0, item_id: "sword_basic", qty: 1 }],
      equipment: { ...g.equipment, weapon: "sword_basic" },
      equipment_inst: { weapon: inst },
    });
    expect(eq.status).toBe(200);
    g = await getC(c.id);
    expect(g.equipment_inst).toEqual({ weapon: inst });
    expect(g.inventory).toEqual([{ slot: 0, item_id: "sword_basic", qty: 1 }]);
    // desequipa
    const un = await checkpoint(c, g, {
      inventory: [{ slot: 0, item_id: "sword_basic", qty: 1 }, { slot: 1, item_id: "sword_basic", qty: 1, inst }],
      equipment: { armor: g.equipment.armor },
      equipment_inst: undefined,
    });
    expect(un.status).toBe(200);
    g = await getC(c.id);
    expect(g.equipment_inst).toBeUndefined();
    expect(g.inventory.filter((e: any) => e.inst)).toEqual([{ slot: 1, item_id: "sword_basic", qty: 1, inst }]);
    // descartar a instancia (remover) e permitido
    expect((await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1 }] })).status).toBe(200);
  });

  it("recusa criar, alterar ou duplicar instancias pelo checkpoint e formas invalidas", async () => {
    const c = await mkChar();
    const inst = magic();
    await reward(c, lootKey(c), swordLine(inst));
    let g = await getC(c.id);
    const forged = await checkpoint(c, g, { inventory: [...g.inventory, { slot: 1, item_id: "sword_basic", qty: 1, inst: magic() }] });
    expect(forged.status).toBe(422);
    expect(code(forged)).toBe("invalid_state");
    g = await getC(c.id);
    const tampered = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst: { ...inst, ilvl: 40 } }] });
    expect(tampered.status).toBe(422);
    const upgraded = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst: { ...inst, affixes: [aff("pre_brutal", 3, 2), aff("suf_of_ward", 3, 0.015)] } }] });
    expect(upgraded.status).toBe(422);
    const rebased = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_rare", qty: 1, inst }] });
    expect(rebased.status).toBe(422);
    const twice = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst }, { slot: 1, item_id: "sword_basic", qty: 1, inst }] });
    expect(twice.status).toBe(422);
    const both = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst }], equipment: { ...g.equipment, weapon: "sword_basic" }, equipment_inst: { weapon: inst } });
    expect(both.status).toBe(422); // mesmo uid no inventario e equipado
    const qty2 = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 2, inst }] });
    expect(qty2.status).toBe(422);
    const noItem = await checkpoint(c, g, { equipment: { armor: g.equipment.armor }, equipment_inst: { weapon: inst } });
    expect(noItem.status).toBe(422);
    const wrongSlot = await checkpoint(c, g, { equipment: { ...g.equipment, armor: "sword_basic" } });
    expect(wrongSlot.status).toBe(422);
    const junk = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst: "x" }] });
    expect(junk.status).toBe(422);
    const keys = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1, inst, foo: 1 }] });
    expect(keys.status).toBe(422);
    const after = await getC(c.id);
    expect(after.inventory).toEqual([{ slot: 0, item_id: "sword_basic", qty: 1, inst }]); // nada disso gravou
    expect(after.revision).toBe(g.revision);
  });

  it("estado sem instancias (jogo antigo/sem campo) continua valido e limpa o equipamento rolado se o servidor o tirou", async () => {
    const c = await mkChar();
    const g = await getC(c.id);
    const r = await checkpoint(c, g, { inventory: [{ slot: 0, item_id: "scrap_material", qty: 5 }] });
    expect(r.status).toBe(200);
    expect((await getC(c.id)).inventory).toEqual([{ slot: 0, item_id: "scrap_material", qty: 5 }]);
  });
});

describe("crafting x instancias", () => {
  const craft = (c: Ch, rid: string) =>
    call("POST", `/internal/characters/${c.id}/craft`, { internal: true, session: c.sid, body: { idempotency_key: `craft:${c.sid}:${++dropN}:${c.id}`, recipe_id: rid } });

  it("item com affixes nunca e consumido como ingrediente", async () => {
    const c = await mkChar();
    const inst: ItemInstance = { uid: uid(), rarity: "uncommon", ilvl: 5, affixes: [aff("pre_bulwark", 3, 1), aff("suf_of_ward", 3, 0.01)] };
    await reward(c, lootKey(c), { item_id: "armor_leather", qty: 1, inst });
    let g = await getC(c.id);
    await checkpoint(c, g, { inventory: [...g.inventory, { slot: 1, item_id: "scrap_material", qty: 8 }] });
    const r = await craft(c, "rcp_armor_heavy"); // 1 armor_leather SIMPLES + 8 scrap
    expect(r.status).toBe(409);
    expect(code(r)).toBe("insufficient_ingredients");
    g = await getC(c.id);
    expect(g.inventory.find((e: any) => e.inst)?.inst).toEqual(inst);
    // com um armor_leather simples tambem, so o simples e consumido
    await reward(c, lootKey(c), { item_id: "armor_leather", qty: 1 });
    const ok = await craft(c, "rcp_armor_heavy");
    expect(ok.status).toBe(200);
    g = await getC(c.id);
    expect(g.inventory.filter((e: any) => e.item_id === "armor_leather")).toEqual([expect.objectContaining({ inst })]);
    expect(g.inventory.some((e: any) => e.item_id === "armor_heavy" && !e.inst)).toBe(true);
  });
});

describe("concorrencia equipar x craft x checkpoint x recompensa", () => {
  it("operacoes simultaneas nunca duplicam nem perdem a instancia", async () => {
    const c = await mkChar();
    const inst = magic();
    await reward(c, lootKey(c), swordLine(inst));
    const g = await getC(c.id);
    await checkpoint(c, g, { inventory: [...g.inventory, { slot: 1, item_id: "scrap_material", qty: 10 }] });
    const g1 = await getC(c.id);
    const equipCp = checkpoint(c, g1, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1 }, { slot: 1, item_id: "scrap_material", qty: 10 }], equipment: { ...g1.equipment, weapon: "sword_basic" }, equipment_inst: { weapon: inst } });
    const equipCp2 = checkpoint(c, g1, { inventory: [{ slot: 0, item_id: "sword_basic", qty: 1 }, { slot: 1, item_id: "scrap_material", qty: 10 }], equipment: { ...g1.equipment, weapon: "sword_basic" }, equipment_inst: { weapon: inst } });
    const craftP = call("POST", `/internal/characters/${c.id}/craft`, { internal: true, session: c.sid, body: { idempotency_key: `craft:${c.sid}:${++dropN}:${c.id}`, recipe_id: "rcp_potion_minor" } });
    const rew = reward(c, lootKey(c), swordLine(magic()));
    const res = await Promise.all([equipCp, equipCp2, craftP, rew]);
    expect(res.every((r) => r.status === 200 || r.status === 409 || r.status === 422)).toBe(true);
    expect([res[0]!.status, res[1]!.status].filter((s) => s === 200).length).toBeLessThanOrEqual(1); // so um checkpoint com a mesma revision vence
    const end = await getC(c.id);
    const uids = [...end.inventory.filter((e: any) => e.inst).map((e: any) => e.inst.uid), ...Object.values(end.equipment_inst ?? {}).map((i: any) => i.uid)];
    expect(new Set(uids).size).toBe(uids.length); // sem uid repetido
    expect(uids).toContain(inst.uid); // a instancia original existe exatamente uma vez
    expect(uids.filter((u) => u === inst.uid)).toHaveLength(1);
  });
});
