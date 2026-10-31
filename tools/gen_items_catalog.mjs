#!/usr/bin/env node
// Gera shared/content_schemas/items.json a partir de data/items/*.tres (ItemData do Godot).
// Uso (na raiz do repo):
//   node tools/gen_items_catalog.mjs          # escreve o arquivo
//   node tools/gen_items_catalog.mjs --check  # sai com 1 se o arquivo difere do que seria gerado
// Regenere SEMPRE que um item em data/items mudar (id, slot, stackable, max_stack, rarity).
import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ITEMS_DIR = join(ROOT, "data", "items");
const OUT = join(ROOT, "shared", "content_schemas", "items.json");
// Espelha enums de scripts/data/item_data.gd
const SLOTS = ["none", "weapon", "armor", "trinket"];
const RARITIES = ["common", "uncommon", "rare", "epic", "legendary"];

function field(body, name) {
  const m = new RegExp(`^${name}\\s*=\\s*(.+?)\\s*$`, "m").exec(body);
  return m ? m[1] : undefined;
}

export function parseTres(text, file) {
  const idx = text.indexOf("\n[resource]");
  if (idx < 0) throw new Error(`${file}: sem secao [resource]`);
  const body = text.slice(idx);
  const idRaw = field(body, "id");
  const m = idRaw && /^&?"([a-z][a-z0-9_]*)"$/.exec(idRaw);
  if (!m) throw new Error(`${file}: id ausente/invalido`);
  const slot = Number(field(body, "slot") ?? "0");
  const rarity = Number(field(body, "rarity") ?? "0");
  const stackable = (field(body, "stackable") ?? "false") === "true";
  const maxStackRaw = Number(field(body, "max_stack") ?? "1");
  if (!SLOTS[slot]) throw new Error(`${file}: slot invalido ${slot}`);
  if (!RARITIES[rarity]) throw new Error(`${file}: rarity invalida ${rarity}`);
  if (!Number.isInteger(maxStackRaw)) throw new Error(`${file}: max_stack invalido`);
  return {
    id: m[1],
    slot: SLOTS[slot],
    stackable,
    // Igual a ItemData.effective_max_stack(): nao empilhaveis valem 1.
    max_stack: stackable ? Math.max(maxStackRaw, 1) : 1,
    rarity: RARITIES[rarity],
  };
}

export function buildCatalog() {
  const items = readdirSync(ITEMS_DIR)
    .filter((f) => f.endsWith(".tres"))
    .sort()
    .map((f) => parseTres(readFileSync(join(ITEMS_DIR, f), "utf8"), f));
  const ids = new Set();
  for (const it of items) {
    if (ids.has(it.id)) throw new Error(`id duplicado: ${it.id}`);
    ids.add(it.id);
  }
  items.sort((a, b) => (a.id < b.id ? -1 : 1));
  return { schema_version: 1, source: "data/items/*.tres (gerado por tools/gen_items_catalog.mjs)", items };
}

const text = JSON.stringify(buildCatalog(), null, 2) + "\n";
if (process.argv.includes("--check")) {
  const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
  if (cur !== text) {
    console.error("shared/content_schemas/items.json desatualizado: rode node tools/gen_items_catalog.mjs");
    process.exit(1);
  }
  console.log("items.json em dia");
} else {
  writeFileSync(OUT, text);
  console.log(`escrito ${OUT}`);
}
