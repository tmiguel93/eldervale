import { readFileSync } from "node:fs";

export type ItemSlot = "none" | "weapon" | "armor" | "trinket";
export interface CatalogItem {
  id: string;
  slot: ItemSlot;
  stackable: boolean;
  /** Tamanho efetivo de pilha (1 para nao empilhaveis). */
  max_stack: number;
  rarity: string;
}

/** E6.3: tier de um affix (faixa liberada por ilvl, custo no orcamento da raridade). */
export interface AffixTier { tier: number; ilvl_min: number; min: number; max: number; cost: number; weight: number }
export interface AffixDef { id: string; kind: "prefix" | "suffix"; group: string; slots: readonly string[]; tiers: readonly AffixTier[] }
export interface RarityDef { id: string; rank: number; budget: number; affix_min: number; affix_max: number; prefix_max: number; suffix_max: number }
/** E6.3: regras de raridade/affixes/unicos (shared/content_schemas/items.json, gerado de data/items/_*.json). */
export interface ItemRules {
  ilvlMax: number;
  maxAffixes: number;
  rarity(id: string): RarityDef | undefined;
  affix(id: string): AffixDef | undefined;
  isUnique(itemId: string): boolean;
}

export interface Catalog {
  get(id: string): CatalogItem | undefined;
  has(id: string): boolean;
  ids(): string[];
  /** E6.3: ausente quando o JSON do catalogo nao traz as regras (entao instancias sao recusadas). */
  rules?: ItemRules;
}

const SLOTS = new Set<string>(["none", "weapon", "armor", "trinket"]);
const ID_RE = /^[a-z][a-z0-9_]{0,63}$/;

/**
 * Valida o JSON do catalogo (gerado por tools/gen_items_catalog.mjs a partir de data/items/*.tres)
 * e devolve um catalogo imutavel. Lanca Error em qualquer inconsistencia (falha na inicializacao).
 */
export function createCatalog(raw: unknown): Catalog {
  if (typeof raw !== "object" || raw === null) throw new Error("catalogo: raiz invalida");
  const obj = raw as { schema_version?: unknown; items?: unknown };
  if (obj.schema_version !== 1) throw new Error("catalogo: schema_version nao suportada");
  if (!Array.isArray(obj.items) || obj.items.length === 0) throw new Error("catalogo: items vazio");
  const map = new Map<string, CatalogItem>();
  for (const it of obj.items as unknown[]) {
    if (typeof it !== "object" || it === null) throw new Error("catalogo: item invalido");
    const r = it as Record<string, unknown>;
    const id = r.id;
    if (typeof id !== "string" || !ID_RE.test(id)) throw new Error(`catalogo: id invalido ${String(id)}`);
    if (map.has(id)) throw new Error(`catalogo: id duplicado ${id}`);
    if (typeof r.slot !== "string" || !SLOTS.has(r.slot)) throw new Error(`catalogo: slot invalido em ${id}`);
    if (typeof r.stackable !== "boolean") throw new Error(`catalogo: stackable invalido em ${id}`);
    const ms = r.max_stack;
    if (typeof ms !== "number" || !Number.isInteger(ms) || ms < 1 || ms > 999) throw new Error(`catalogo: max_stack invalido em ${id}`);
    if (!r.stackable && ms !== 1) throw new Error(`catalogo: item nao empilhavel ${id} com max_stack ${ms}`);
    if (r.stackable && r.slot !== "none") throw new Error(`catalogo: item equipavel ${id} nao pode ser empilhavel`);
    map.set(id, Object.freeze({ id, slot: r.slot as ItemSlot, stackable: r.stackable, max_stack: ms, rarity: String(r.rarity ?? "common") }));
  }
  return { get: (id) => map.get(id), has: (id) => map.has(id), ids: () => [...map.keys()], rules: parseRules(raw as Record<string, unknown>) };
}

const AFFIX_ID_RE = /^[a-z][a-z0-9_]{0,47}$/;

/** E6.3: le rarities/affixes/uniques do JSON (se houver). Lanca Error em inconsistencia estrutural (o gerador ja validou o conteudo). */
function parseRules(raw: Record<string, unknown>): ItemRules | undefined {
  if (raw.rarities === undefined && raw.affixes === undefined) return undefined;
  const num = (v: unknown, w: string): number => {
    if (typeof v !== "number" || !Number.isFinite(v)) throw new Error(`catalogo: ${w} invalido`);
    return v;
  };
  if (!Array.isArray(raw.rarities) || !Array.isArray(raw.affixes) || !Array.isArray(raw.uniques)) throw new Error("catalogo: rarities/affixes/uniques invalidos");
  const rarities = new Map<string, RarityDef>();
  for (const r of raw.rarities as Record<string, unknown>[]) {
    const id = String(r.id);
    rarities.set(id, Object.freeze({
      id, rank: num(r.rank, "rank"), budget: num(r.budget, "budget"), affix_min: num(r.affix_min, "affix_min"), affix_max: num(r.affix_max, "affix_max"),
      prefix_max: num(r.prefix_max, "prefix_max"), suffix_max: num(r.suffix_max, "suffix_max"),
    }));
  }
  const affixes = new Map<string, AffixDef>();
  for (const a of raw.affixes as Record<string, unknown>[]) {
    const id = a.id;
    if (typeof id !== "string" || !AFFIX_ID_RE.test(id) || affixes.has(id)) throw new Error(`catalogo: affix invalido ${String(id)}`);
    if (a.kind !== "prefix" && a.kind !== "suffix") throw new Error(`catalogo: kind invalido em ${id}`);
    if (!Array.isArray(a.slots) || !Array.isArray(a.tiers) || a.tiers.length === 0) throw new Error(`catalogo: affix ${id} sem slots/tiers`);
    const tiers = (a.tiers as Record<string, unknown>[]).map((t) => Object.freeze({
      tier: num(t.tier, "tier"), ilvl_min: num(t.ilvl_min, "ilvl_min"), min: num(t.min, "min"), max: num(t.max, "max"), cost: num(t.cost, "cost"), weight: num(t.weight, "weight"),
    }));
    affixes.set(id, Object.freeze({ id, kind: a.kind, group: String(a.group), slots: Object.freeze([...(a.slots as string[])]), tiers: Object.freeze(tiers) }));
  }
  const uniques = new Set((raw.uniques as Record<string, unknown>[]).map((u) => String(u.id)));
  return {
    ilvlMax: num(raw.ilvl_max, "ilvl_max"),
    maxAffixes: num(raw.max_affixes, "max_affixes"),
    rarity: (id) => rarities.get(id),
    affix: (id) => affixes.get(id),
    isUnique: (itemId) => uniques.has(itemId),
  };
}

export const ITEMS_JSON_URL = new URL("../../../shared/content_schemas/items.json", import.meta.url);

/** Le shared/content_schemas/items.json (relativo a este arquivo). */
export function loadCatalogFromDisk(url: URL = ITEMS_JSON_URL): Catalog {
  return createCatalog(JSON.parse(readFileSync(url, "utf8")));
}
