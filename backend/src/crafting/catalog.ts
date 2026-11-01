import { readFileSync } from "node:fs";
import type { Catalog } from "../characters/catalog.ts";

export interface RecipeStack {
  item_id: string;
  qty: number;
}
export interface Recipe {
  id: string;
  /** Id da estacao (data/areas/world/*_world.json). O backend nao conhece posicoes: a proximidade e checada pelo servidor de sessao. */
  station: string;
  ingredients: readonly RecipeStack[];
  results: readonly RecipeStack[];
}
export interface RecipeCatalog {
  get(id: string): Recipe | undefined;
  has(id: string): boolean;
  ids(): string[];
}

const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);
const MAX_INGREDIENTS = 4;
const MAX_RESULTS = 2;
const MAX_QTY = 99;

export const EMPTY_RECIPES: RecipeCatalog = Object.freeze({ get: () => undefined, has: () => false, ids: () => [] });

function stacks(raw: unknown, label: string, max: number, id: string, items: Catalog): RecipeStack[] {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > max) throw new Error(`receitas: ${label} de ${id} deve ter 1..${max} entradas`);
  const seen = new Set<string>();
  const out: RecipeStack[] = [];
  for (const s of raw as unknown[]) {
    const r = s as Record<string, unknown> | null;
    if (typeof r !== "object" || r === null) throw new Error(`receitas: ${label} invalido em ${id}`);
    if (typeof r.item_id !== "string" || !items.has(r.item_id)) throw new Error(`receitas: item desconhecido em ${label} de ${id}`);
    if (seen.has(r.item_id)) throw new Error(`receitas: item repetido em ${label} de ${id}`);
    seen.add(r.item_id);
    if (!isInt(r.qty) || r.qty < 1 || r.qty > MAX_QTY) throw new Error(`receitas: qty invalida em ${label} de ${id}`);
    out.push(Object.freeze({ item_id: r.item_id, qty: r.qty }));
  }
  return out.sort((a, b) => (a.item_id < b.item_id ? -1 : 1));
}

/**
 * Valida shared/content_schemas/recipes.json (gerado por tools/gen_recipes_catalog.mjs) e cruza com o catalogo
 * de itens. Lanca Error em qualquer inconsistencia (falha na inicializacao).
 */
export function createRecipeCatalog(raw: unknown, items: Catalog): RecipeCatalog {
  if (typeof raw !== "object" || raw === null) throw new Error("receitas: raiz invalida");
  const obj = raw as { schema_version?: unknown; recipes?: unknown };
  if (obj.schema_version !== 1) throw new Error("receitas: schema_version nao suportada");
  if (!Array.isArray(obj.recipes)) throw new Error("receitas: lista invalida");
  const map = new Map<string, Recipe>();
  for (const r of obj.recipes as unknown[]) {
    const rec = r as Record<string, unknown> | null;
    if (typeof rec !== "object" || rec === null) throw new Error("receitas: entrada invalida");
    const id = rec.id;
    if (typeof id !== "string" || !ID_RE.test(id)) throw new Error(`receitas: id invalido ${String(id)}`);
    if (map.has(id)) throw new Error(`receitas: id duplicado ${id}`);
    if (typeof rec.station !== "string" || !ID_RE.test(rec.station)) throw new Error(`receitas: estacao invalida em ${id}`);
    const ingredients = stacks(rec.ingredients, "ingredients", MAX_INGREDIENTS, id, items);
    const results = stacks(rec.results, "results", MAX_RESULTS, id, items);
    const ing = new Set(ingredients.map((s) => s.item_id));
    if (results.some((s) => ing.has(s.item_id))) throw new Error(`receitas: ${id} tem resultado que tambem e ingrediente`);
    map.set(id, Object.freeze({ id, station: rec.station, ingredients, results }));
  }
  return { get: (id) => map.get(id), has: (id) => map.has(id), ids: () => [...map.keys()] };
}

export const RECIPES_JSON_URL = new URL("../../../shared/content_schemas/recipes.json", import.meta.url);

export function loadRecipeCatalogFromDisk(items: Catalog, url: URL = RECIPES_JSON_URL): RecipeCatalog {
  return createRecipeCatalog(JSON.parse(readFileSync(url, "utf8")), items);
}
