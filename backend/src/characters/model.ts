import { ApiError, Errors } from "../http/errors.ts";
import type { Catalog } from "./catalog.ts";
import type { CharacterLimits } from "./limits.ts";
import { EMPTY_QUESTS, type QuestCatalog } from "../quests/catalog.ts";
import { validateQuestsState, type QuestsState } from "../quests/state.ts";
import type { ClassCatalog } from "./classes.ts";
import { levelForXp, MAX_LEVEL, MAX_TOTAL_XP } from "./progression.ts";

export const SCHEMA_VERSION = 1;
export const EQUIP_SLOTS = ["weapon", "armor", "trinket"] as const;
export type EquipSlot = (typeof EQUIP_SLOTS)[number];

/** Stats BASE do personagem (nivel/equipamento sao aplicados em runtime pelo jogo; ver StatBlock). */
export const STAT_KEYS = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"] as const;
export type Stats = Record<(typeof STAT_KEYS)[number], number>;
export const BASE_STATS: Readonly<Stats> = Object.freeze({
  max_health: 100,
  max_resource: 50,
  resource_regen: 5,
  attack_power: 10,
  defense: 0,
  resistance: 0,
  move_speed: 5,
});
/** Kit inicial: mesmo do jogo (scripts/arena/test_arena.gd STARTING_ITEMS), ja equipado. */
export const STARTING_EQUIPMENT: Readonly<Record<string, string>> = Object.freeze({ weapon: "sword_basic", armor: "armor_leather" });

export interface InventoryEntry {
  slot: number;
  item_id: string;
  qty: number;
}
export type Equipment = Partial<Record<EquipSlot, string>>;
export interface CharacterState {
  schema_version: number;
  level: number;
  xp: number;
  stats: Stats;
  inventory: InventoryEntry[];
  equipment: Equipment;
  /** E5.1. Opcional na ENTRADA do checkpoint (ausente = manter o do banco); sempre presente no que e lido/gravado. */
  quests?: QuestsState;
}

export function invalidState(message: string): ApiError {
  return new ApiError(422, "invalid_state", message);
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);

function exactKeys(o: Record<string, unknown>, allowed: readonly string[], where: string): void {
  for (const k of Object.keys(o)) if (!allowed.includes(k)) throw invalidState(`${where}: campo desconhecido "${k.slice(0, 40)}"`);
}

/**
 * Valida e normaliza um estado de personagem vindo do servidor de sessao.
 * Lanca ApiError 422 invalid_state. Nao toca em banco.
 */
export function validateState(input: unknown, catalog: Catalog, limits: CharacterLimits, quests: QuestCatalog = EMPTY_QUESTS): CharacterState {
  if (!isObj(input)) throw invalidState("state deve ser um objeto");
  exactKeys(input, ["schema_version", "level", "xp", "stats", "inventory", "equipment", "quests"], "state");
  if (input.schema_version !== SCHEMA_VERSION) throw invalidState(`schema_version deve ser ${SCHEMA_VERSION}`);

  const { level, xp } = input;
  if (!isInt(level) || level < 1 || level > MAX_LEVEL) throw invalidState(`level deve ser inteiro 1..${MAX_LEVEL}`);
  if (!isInt(xp) || xp < 0 || xp > MAX_TOTAL_XP) throw invalidState(`xp deve ser inteiro 0..${MAX_TOTAL_XP}`);
  if (levelForXp(xp) !== level) throw invalidState(`level ${level} incoerente com xp ${xp} (esperado ${levelForXp(xp)})`);

  if (!isObj(input.stats)) throw invalidState("stats deve ser um objeto");
  exactKeys(input.stats, STAT_KEYS, "stats");
  const stats = {} as Stats;
  for (const k of STAT_KEYS) {
    const v = input.stats[k];
    const max = k === "resistance" ? 0.75 : k === "move_speed" ? 100 : 100_000;
    if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > max) throw invalidState(`stats.${k} deve ser numero 0..${max}`);
    stats[k] = v;
  }

  if (!Array.isArray(input.inventory)) throw invalidState("inventory deve ser uma lista");
  if (input.inventory.length > limits.inventoryCapacity) throw invalidState(`inventory excede a capacidade (${limits.inventoryCapacity})`);
  const seen = new Set<number>();
  const inventory: InventoryEntry[] = [];
  for (const e of input.inventory as unknown[]) {
    if (!isObj(e)) throw invalidState("entrada de inventory invalida");
    exactKeys(e, ["slot", "item_id", "qty"], "inventory");
    if (!isInt(e.slot) || e.slot < 0 || e.slot >= limits.inventoryCapacity) throw invalidState(`inventory.slot deve ser inteiro 0..${limits.inventoryCapacity - 1}`);
    if (seen.has(e.slot)) throw invalidState(`inventory.slot ${e.slot} duplicado`);
    seen.add(e.slot);
    if (typeof e.item_id !== "string") throw invalidState("inventory.item_id deve ser string");
    const item = catalog.get(e.item_id);
    if (!item) throw invalidState(`item desconhecido "${e.item_id.slice(0, 40)}"`);
    if (!isInt(e.qty) || e.qty < 1) throw invalidState("inventory.qty deve ser inteiro >= 1");
    if (e.qty > item.max_stack) throw invalidState(`${item.id}: qty ${e.qty} acima do max_stack ${item.max_stack}`);
    inventory.push({ slot: e.slot, item_id: item.id, qty: e.qty });
  }
  inventory.sort((a, b) => a.slot - b.slot);

  if (!isObj(input.equipment)) throw invalidState("equipment deve ser um objeto");
  exactKeys(input.equipment, EQUIP_SLOTS, "equipment");
  const equipment: Equipment = {};
  for (const s of EQUIP_SLOTS) {
    const v = input.equipment[s];
    if (v === undefined || v === null) continue;
    if (typeof v !== "string") throw invalidState(`equipment.${s} deve ser string`);
    const item = catalog.get(v);
    if (!item) throw invalidState(`item desconhecido "${v.slice(0, 40)}"`);
    if (item.slot !== s) throw invalidState(`item ${item.id} (slot ${item.slot}) nao cabe em ${s}`);
    equipment[s] = item.id;
  }
  const out: CharacterState = { schema_version: SCHEMA_VERSION, level, xp, stats, inventory, equipment };
  if (input.quests !== undefined) out.quests = validateQuestsState(input.quests, quests, limits.maxActiveQuests);
  return out;
}

/** Quantidade total por item (inventario + equipado). Itens nao tem identidade de instancia: a conservacao e por contagem. */
export function itemTotals(state: Pick<CharacterState, "inventory" | "equipment">): Map<string, number> {
  const m = new Map<string, number>();
  for (const e of state.inventory) m.set(e.item_id, (m.get(e.item_id) ?? 0) + e.qty);
  for (const id of Object.values(state.equipment)) if (id) m.set(id, (m.get(id) ?? 0) + 1);
  return m;
}

export type AddResult =
  | { ok: true; inventory: InventoryEntry[] }
  | { ok: false; missing: { item_id: string; qty: number }[] };

/**
 * Adiciona itens ao inventario (puro, tudo-ou-nada). Como Inventory.add do jogo: completa pilhas existentes
 * por ordem de slot e abre novos slots no menor indice livre < capacity.
 */
export function addItems(inventory: readonly InventoryEntry[], items: readonly { item_id: string; qty: number }[], catalog: Catalog, capacity: number): AddResult {
  const slots = new Map<number, InventoryEntry>();
  for (const e of inventory) slots.set(e.slot, { ...e });
  const missing: { item_id: string; qty: number }[] = [];
  for (const { item_id, qty } of items) {
    const item = catalog.get(item_id);
    if (!item) throw new Error(`item fora do catalogo: ${item_id}`); // chamadores validam antes
    let left = qty;
    if (item.stackable) {
      for (const e of [...slots.values()].sort((a, b) => a.slot - b.slot)) {
        if (left === 0) break;
        if (e.item_id !== item_id || e.qty >= item.max_stack) continue;
        const put = Math.min(left, item.max_stack - e.qty);
        e.qty += put;
        left -= put;
      }
    }
    for (let s = 0; s < capacity && left > 0; s++) {
      if (slots.has(s)) continue;
      const put = Math.min(left, item.max_stack);
      slots.set(s, { slot: s, item_id, qty: put });
      left -= put;
    }
    if (left > 0) missing.push({ item_id, qty: left });
  }
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true, inventory: [...slots.values()].sort((a, b) => a.slot - b.slot) };
}

// ---------------------------------------------------------------- entrada publica
export function validateCharacterName(raw: unknown): string {
  if (typeof raw !== "string") throw Errors.badRequest("name deve ser string", "invalid_name");
  const name = raw.normalize("NFC").trim();
  const len = [...name].length;
  if (len < 2 || len > 24) throw Errors.badRequest("name deve ter 2 a 24 caracteres", "invalid_name");
  if (!/^[\p{L}\p{N}][\p{L}\p{N} '_-]*$/u.test(name) || name.includes("  ")) {
    throw Errors.badRequest("name aceita letras, numeros, espaco simples, apostrofo, hifen e underscore", "invalid_name");
  }
  return name;
}

/** E6.1: o class_id tem de existir no catalogo de classes (shared/content_schemas/classes.json); a classe e imutavel apos a criacao. */
export function validateClassId(raw: unknown, classes: ClassCatalog): string {
  if (typeof raw !== "string" || !classes.has(raw)) throw Errors.badRequest("class_id invalido", "invalid_class");
  return raw;
}

const REWARD_KEY_RE = /^[A-Za-z0-9._:-]{8,128}$/;

export interface RewardRequest {
  idempotency_key: string;
  /** E5.1: recompensa de quest (chave estavel `quest:<quest_id>:<character_id>`, xp/itens iguais ao catalogo). */
  quest_id?: string;
  xp: number;
  items: { item_id: string; qty: number }[];
}

export function validateRewardRequest(body: unknown, catalog: Catalog, limits: CharacterLimits, quests: QuestCatalog = EMPTY_QUESTS, characterId = ""): RewardRequest {
  const bad = (m: string, code = "invalid_reward") => Errors.badRequest(m, code);
  if (!isObj(body)) throw bad("corpo deve ser um objeto");
  for (const k of Object.keys(body)) if (!["idempotency_key", "xp", "items", "quest_id"].includes(k)) throw bad(`campo desconhecido "${k.slice(0, 40)}"`);
  const key = body.idempotency_key;
  if (typeof key !== "string" || !REWARD_KEY_RE.test(key)) throw bad("idempotency_key deve ter 8..128 chars [A-Za-z0-9._:-]", "invalid_idempotency_key");
  let xp = 0;
  if (body.xp !== undefined) {
    if (!isInt(body.xp) || body.xp < 0 || body.xp > limits.rewardMaxXp) throw bad(`xp deve ser inteiro 0..${limits.rewardMaxXp}`);
    xp = body.xp;
  }
  const merged = new Map<string, number>();
  if (body.items !== undefined) {
    if (!Array.isArray(body.items) || body.items.length > limits.rewardMaxItems) throw bad(`items deve ser lista de ate ${limits.rewardMaxItems}`);
    for (const e of body.items as unknown[]) {
      if (!isObj(e)) throw bad("item invalido");
      for (const k of Object.keys(e)) if (k !== "item_id" && k !== "qty") throw bad(`campo desconhecido "${k.slice(0, 40)}" em item`);
      if (typeof e.item_id !== "string" || !catalog.has(e.item_id)) throw bad("item_id desconhecido", "unknown_item");
      if (!isInt(e.qty) || e.qty < 1 || e.qty > limits.rewardMaxQty) throw bad(`qty deve ser inteiro 1..${limits.rewardMaxQty}`);
      merged.set(e.item_id, (merged.get(e.item_id) ?? 0) + e.qty);
    }
  }
  const items = [...merged.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([item_id, qty]) => ({ item_id, qty }));
  if (body.quest_id !== undefined) {
    const qid = body.quest_id;
    if (typeof qid !== "string" || !/^[a-z][a-z0-9_]{0,47}$/.test(qid)) throw bad("quest_id invalido", "invalid_reward");
    const def = quests.get(qid);
    if (!def) throw bad("quest desconhecida", "unknown_quest");
    if (key !== `quest:${qid}:${characterId}`) throw bad("idempotency_key de quest deve ser quest:<quest_id>:<character_id>", "invalid_idempotency_key");
    // O servidor de sessao nao escolhe o valor: tem de ser exatamente a recompensa do catalogo.
    if (xp !== def.rewards.xp || JSON.stringify(items) !== JSON.stringify(def.rewards.items)) {
      throw bad("recompensa diverge do catalogo da quest", "quest_reward_mismatch");
    }
    return { idempotency_key: key, quest_id: qid, xp, items };
  }
  if (xp === 0 && merged.size === 0) throw bad("recompensa vazia");
  return { idempotency_key: key, xp, items };
}
