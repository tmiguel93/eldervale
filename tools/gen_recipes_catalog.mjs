#!/usr/bin/env node
// Gera shared/content_schemas/recipes.json (catalogo que o BACKEND usa para validar e executar o crafting)
// a partir de data/recipes/*.json (fonte de verdade, tambem lida pelo Godot). Valida estrutura e referencias
// cruzadas (itens do catalogo, estacao declarada no mundo, ingredientes x resultados).
// Uso (na raiz do repo):
//   node tools/gen_recipes_catalog.mjs          # escreve o arquivo
//   node tools/gen_recipes_catalog.mjs --check  # sai com 1 se o arquivo difere do que seria gerado ou se ha erro
// Regenere SEMPRE que uma receita em data/recipes mudar. Espelha scripts/crafting/recipe_def.gd.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "shared", "content_schemas", "recipes.json");
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const ITEM_RE = /^[a-z][a-z0-9_]{0,63}$/;
const MAX_INGREDIENTS = 4, MAX_RESULTS = 2, MAX_QTY = 99, MAX_RECIPES = 64;

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const jsonFiles = (dir) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("_")).sort() : []);
const isInt = (v) => Number.isSafeInteger(v);

function checkStacks(list, label, max, w, e) {
  if (!Array.isArray(list) || list.length < 1 || list.length > max) { e.push(`${w}: ${label} deve ter 1..${max} entradas`); return; }
  const seen = new Set();
  for (const s of list) {
    if (typeof s !== "object" || s === null || Object.keys(s).some((k) => k !== "item_id" && k !== "qty")) { e.push(`${w}: ${label} com entrada invalida`); continue; }
    if (typeof s.item_id !== "string" || !ITEM_RE.test(s.item_id)) e.push(`${w}: ${label}.item_id invalido`);
    else if (seen.has(s.item_id)) e.push(`${w}: ${label} repete '${s.item_id}'`);
    else seen.add(s.item_id);
    if (!isInt(s.qty) || s.qty < 1 || s.qty > MAX_QTY) e.push(`${w}: ${label}.qty fora de 1..${MAX_QTY}`);
  }
}

/** Valida UMA receita; devolve lista de erros. */
export function validateRecipe(r, file = "?") {
  const e = [];
  if (typeof r !== "object" || r === null || Array.isArray(r)) return [`${file}: raiz deve ser objeto`];
  const w = `receita '${r.id}' (${file})`;
  if (typeof r.id !== "string" || !ID_RE.test(r.id)) e.push(`${file}: id invalido`);
  if (r.schema_version !== 1) e.push(`${w}: schema_version deve ser 1`);
  if (typeof r.station !== "string" || !ID_RE.test(r.station)) e.push(`${w}: station invalida`);
  for (const [k, max] of [["name", 80], ["name_key", 96]]) if (typeof r[k] !== "string" || r[k].trim() === "" || r[k].length > max) e.push(`${w}: '${k}' ausente/vazio/longo demais`);
  checkStacks(r.ingredients, "ingredients", MAX_INGREDIENTS, w, e);
  checkStacks(r.results, "results", MAX_RESULTS, w, e);
  const ing = new Set((Array.isArray(r.ingredients) ? r.ingredients : []).map((s) => s?.item_id));
  for (const s of Array.isArray(r.results) ? r.results : []) if (ing.has(s?.item_id)) e.push(`${w}: resultado '${s.item_id}' tambem e ingrediente (receita circular)`);
  return e;
}

/** Ids de estacoes declaradas em data/areas/world/*_world.json. */
function stationIds(root) {
  const dir = join(root, "data", "areas", "world");
  const ids = new Set();
  for (const f of jsonFiles(dir)) for (const z of readJson(join(dir, f)).zones ?? []) for (const s of z.stations ?? []) ids.add(s.id);
  return ids;
}

/** Le data/**, valida tudo e devolve {catalog, errors}. */
export function buildRecipeCatalog(root = ROOT) {
  const errors = [];
  const rdir = join(root, "data", "recipes");
  const recipes = [];
  for (const f of jsonFiles(rdir)) {
    let r;
    try { r = readJson(join(rdir, f)); } catch { errors.push(`${f}: JSON invalido`); continue; }
    errors.push(...validateRecipe(r, f));
    if (typeof r?.id === "string" && f !== `${r.id}.json`) errors.push(`${f}: nome do arquivo difere do id`);
    recipes.push(r);
  }
  if (recipes.length > MAX_RECIPES) errors.push(`mais de ${MAX_RECIPES} receitas`);
  const ids = new Set();
  for (const r of recipes) { if (ids.has(r?.id)) errors.push(`id duplicado: ${r.id}`); ids.add(r?.id); }
  const itemsPath = join(root, "shared", "content_schemas", "items.json");
  const items = new Set(existsSync(itemsPath) ? readJson(itemsPath).items.map((i) => i.id) : []);
  const stations = stationIds(root);
  for (const r of recipes) {
    if (typeof r?.id !== "string") continue;
    const w = `receita '${r.id}'`;
    if (stations.size > 0 && !stations.has(r.station)) errors.push(`${w}: estacao '${r.station}' nao declarada no mundo`);
    for (const s of [...(r.ingredients ?? []), ...(r.results ?? [])]) if (items.size > 0 && !items.has(s?.item_id)) errors.push(`${w}: item '${s?.item_id}' fora do catalogo de itens`);
  }
  const sorted = (l) => [...l].map((s) => ({ item_id: s.item_id, qty: s.qty })).sort((a, b) => (a.item_id < b.item_id ? -1 : 1));
  const out = recipes
    .filter((r) => typeof r?.id === "string")
    .sort((a, b) => (a.id < b.id ? -1 : 1))
    .map((r) => ({ id: r.id, station: r.station, ingredients: sorted(r.ingredients ?? []), results: sorted(r.results ?? []) }));
  return { catalog: { schema_version: 1, source: "data/recipes/*.json (gerado por tools/gen_recipes_catalog.mjs)", recipes: out }, errors };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { catalog, errors } = buildRecipeCatalog();
  if (errors.length) {
    console.error("receitas invalidas:\n - " + errors.join("\n - "));
    process.exit(1);
  }
  const text = JSON.stringify(catalog, null, 2) + "\n";
  if (process.argv.includes("--check")) {
    const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
    if (cur !== text) {
      console.error("shared/content_schemas/recipes.json desatualizado: rode node tools/gen_recipes_catalog.mjs");
      process.exit(1);
    }
    console.log("recipes.json em dia");
  } else {
    writeFileSync(OUT, text);
    console.log(`escrito ${OUT}`);
  }
}
