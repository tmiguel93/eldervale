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

export interface Catalog {
  get(id: string): CatalogItem | undefined;
  has(id: string): boolean;
  ids(): string[];
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
  return {
    get: (id) => map.get(id),
    has: (id) => map.has(id),
    ids: () => [...map.keys()],
  };
}

export const ITEMS_JSON_URL = new URL("../../../shared/content_schemas/items.json", import.meta.url);

/** Le shared/content_schemas/items.json (relativo a este arquivo). */
export function loadCatalogFromDisk(url: URL = ITEMS_JSON_URL): Catalog {
  return createCatalog(JSON.parse(readFileSync(url, "utf8")));
}
