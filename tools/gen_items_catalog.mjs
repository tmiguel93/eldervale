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
const RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"];
const LOOT_DIR = join(ROOT, "data", "loot");
const STAT_FIELDS = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"];
const SKILL_MOD_PARAMS = { damage: ["damage_pct"], cost: ["cost_pct", "cooldown_pct"], area: ["radius_pct"] };
const ELEMENTS = ["physical", "fire", "ice", "lightning"];
const EQUIP_SLOTS = ["weapon", "armor", "trinket"];
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;

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

function readJson(name) {
  return JSON.parse(readFileSync(join(ITEMS_DIR, name), "utf8"));
}

const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/** Valida _rarity.json (E6.3). Lanca Error com TODOS os problemas. */
export function validateRarities(r) {
  const e = [];
  if (r.schema_version !== 1) e.push("_rarity.json: schema_version deve ser 1");
  if (!Number.isInteger(r.ilvl_max) || r.ilvl_max < 1 || r.ilvl_max > 100) e.push("_rarity.json: ilvl_max 1..100");
  if (!Number.isInteger(r.max_affixes) || r.max_affixes < 1 || r.max_affixes > 8) e.push("_rarity.json: max_affixes 1..8");
  const ids = (r.rarities ?? []).map((x) => x.id);
  if (JSON.stringify(ids) !== JSON.stringify(RARITIES)) e.push(`_rarity.json: rarities deve ser exatamente ${RARITIES.join(",")} (nessa ordem)`);
  (r.rarities ?? []).forEach((x, i) => {
    const w = `_rarity.json:${x.id}`;
    if (x.rank !== i) e.push(`${w}: rank deve ser ${i}`);
    if (typeof x.name !== "string" || !x.name) e.push(`${w}: name vazio`);
    if (!/^#[0-9a-fA-F]{6}$/.test(x.color ?? "")) e.push(`${w}: color #rrggbb`);
    for (const k of ["budget", "affix_min", "affix_max", "prefix_max", "suffix_max", "drop_weight"]) {
      if (!Number.isInteger(x[k]) || x[k] < 0) e.push(`${w}: ${k} inteiro >= 0`);
    }
    if (x.affix_min > x.affix_max) e.push(`${w}: affix_min > affix_max`);
    if (x.affix_max > r.max_affixes) e.push(`${w}: affix_max acima de max_affixes`);
    if (x.prefix_max + x.suffix_max < x.affix_max) e.push(`${w}: prefix_max + suffix_max < affix_max`);
    if (x.budget < x.affix_min) e.push(`${w}: budget menor que affix_min (custo minimo de um tier e 1)`);
    if (i > 0 && x.budget < r.rarities[i - 1].budget) e.push(`${w}: budget deve crescer com a raridade`);
    if (i > 0 && x.affix_max < r.rarities[i - 1].affix_max) e.push(`${w}: affix_max nao pode diminuir`);
  });
  const total = (r.rarities ?? []).reduce((n, x) => n + (x.drop_weight || 0), 0);
  if (!(total > 0)) e.push("_rarity.json: soma de drop_weight deve ser > 0");
  for (const tier of ["normal", "mini_boss", "boss"]) {
    const m = r.tier_weight_mult?.[tier];
    if (!m) { e.push(`_rarity.json: tier_weight_mult.${tier} ausente`); continue; }
    for (const id of RARITIES) if (!isNum(m[id]) || m[id] < 0 || m[id] > 100) e.push(`_rarity.json: tier_weight_mult.${tier}.${id} 0..100`);
    if (RARITIES.every((id) => !(m[id] > 0))) e.push(`_rarity.json: tier_weight_mult.${tier} so zeros`);
  }
  if (e.length) throw new Error(e.join("\n"));
}

/** Valida um efeito (mesmos tipos de skill_mod dos talentos + wildcard "*"). */
function effectErrors(fx, w) {
  const e = [];
  if (fx.type === "stat") {
    if (!STAT_FIELDS.includes(fx.stat)) e.push(`${w}: stat invalido`);
    if (!isNum(fx.amount)) e.push(`${w}: amount numerico`);
    return e;
  }
  if (fx.type !== "skill_mod") return [`${w}: type deve ser stat|skill_mod`];
  if (fx.skill !== "*" && !ID_RE.test(fx.skill ?? "")) e.push(`${w}: skill invalida`);
  const need = { damage: ["damage_pct"], extra_projectiles: ["count", "spread_deg", "damage_scale"], area: ["radius_pct"], cost: [], convert: ["to"],
    condition: ["when", "threshold", "damage_pct"], synergy: ["after_skill", "window", "damage_pct"] }[fx.mod];
  if (!need) return [...e, `${w}: mod invalido`];
  for (const k of need) if (fx[k] === undefined) e.push(`${w}: ${fx.mod} exige ${k}`);
  if (fx.mod === "convert" && !ELEMENTS.includes(fx.to)) e.push(`${w}: convert.to ${ELEMENTS.join("|")}`);
  if (fx.mod === "condition" && !["self_hp_below", "self_hp_above", "resource_above"].includes(fx.when)) e.push(`${w}: when invalido`);
  if (fx.mod === "extra_projectiles" && !(fx.count >= 1 && fx.count <= 3)) e.push(`${w}: count 1..3`);
  return e;
}

export function validateAffixes(a, rar) {
  const e = [];
  if (a.schema_version !== 1) e.push("_affixes.json: schema_version deve ser 1");
  const seen = new Set();
  for (const x of a.affixes ?? []) {
    const w = `_affixes.json:${x.id}`;
    if (!ID_RE.test(x.id ?? "")) { e.push(`${w}: id invalido`); continue; }
    if (seen.has(x.id)) e.push(`${w}: id duplicado`);
    seen.add(x.id);
    if (!["prefix", "suffix"].includes(x.kind)) e.push(`${w}: kind prefix|suffix`);
    if (!ID_RE.test(x.group ?? "")) e.push(`${w}: group invalido`);
    if (typeof x.name !== "string" || !x.name) e.push(`${w}: name vazio`);
    if (!Array.isArray(x.slots) || x.slots.length < 1 || x.slots.some((s) => !EQUIP_SLOTS.includes(s)) || new Set(x.slots).size !== x.slots.length) e.push(`${w}: slots deve ser subconjunto de ${EQUIP_SLOTS.join(",")}`);
    const fx = x.effect ?? {};
    if (fx.type === "stat") { if (!STAT_FIELDS.includes(fx.stat)) e.push(`${w}: effect.stat invalido`); }
    else if (fx.type === "skill_mod") {
      if (fx.skill !== "*") e.push(`${w}: affix de skill_mod usa skill "*"`);
      if (!SKILL_MOD_PARAMS[fx.mod]?.includes(fx.param)) e.push(`${w}: mod/param invalidos (${fx.mod}/${fx.param})`);
      if (fx.sign !== 1 && fx.sign !== -1) e.push(`${w}: sign 1|-1`);
    } else e.push(`${w}: effect.type stat|skill_mod`);
    const ts = x.tiers ?? [];
    if (ts.length < 1 || ts.length > 5) e.push(`${w}: 1..5 tiers`);
    let prevTier = Infinity, prevIlvl = 0, prevMax = -Infinity;
    for (const t of ts) {
      const tw = `${w}.tier${t.tier}`;
      if (!Number.isInteger(t.tier) || t.tier < 1 || t.tier >= prevTier) e.push(`${tw}: tiers em ordem decrescente (3,2,1) e unicos`);
      if (!Number.isInteger(t.ilvl_min) || t.ilvl_min < 1 || t.ilvl_min > rar.ilvl_max || t.ilvl_min < prevIlvl) e.push(`${tw}: ilvl_min 1..${rar.ilvl_max} crescente`);
      if (!isNum(t.min) || !isNum(t.max) || t.min <= 0 || t.max < t.min) e.push(`${tw}: faixa 0 < min <= max`);
      if (t.min < prevMax) e.push(`${tw}: faixa nao pode regredir`);
      if (!Number.isInteger(t.cost) || t.cost < 1 || t.cost > 8) e.push(`${tw}: cost 1..8`);
      if (!Number.isInteger(t.weight) || t.weight < 1) e.push(`${tw}: weight inteiro >= 1`);
      if (fx.type === "stat" && fx.stat === "resistance" && t.max > 0.3) e.push(`${tw}: resistencia por affix <= 0.30`);
      prevTier = t.tier; prevIlvl = t.ilvl_min; prevMax = t.max;
    }
    if (ts.length && ts[0].ilvl_min !== 1) e.push(`${w}: o tier mais baixo deve liberar no ilvl 1`);
  }
  // Cada slot precisa ter affixes suficientes (grupos distintos, prefixos e sufixos) para as raridades altas.
  for (const slot of EQUIP_SLOTS) {
    const list = (a.affixes ?? []).filter((x) => x.slots?.includes(slot));
    const groups = new Set(list.map((x) => x.group));
    const maxR = rar.rarities[rar.rarities.length - 1];
    if (groups.size < maxR.affix_min) e.push(`slot ${slot}: so ${groups.size} grupos de affix (< affix_min ${maxR.affix_min} da maior raridade)`);
    if (!list.some((x) => x.kind === "prefix") || !list.some((x) => x.kind === "suffix")) e.push(`slot ${slot}: precisa de ao menos um prefixo e um sufixo`);
  }
  if (e.length) throw new Error(e.join("\n"));
}

export function validateUniques(u, items, lootIds) {
  const e = [];
  if (u.schema_version !== 1) e.push("_uniques.json: schema_version deve ser 1");
  const seen = new Set();
  for (const x of u.uniques ?? []) {
    const w = `_uniques.json:${x.id}`;
    if (seen.has(x.id)) e.push(`${w}: id duplicado`);
    seen.add(x.id);
    const it = items.find((i) => i.id === x.id);
    if (!it) { e.push(`${w}: sem data/items/${x.id}.tres`); continue; }
    if (it.slot === "none") e.push(`${w}: item base precisa ser equipavel`);
    if (it.rarity === "common" || it.rarity === "uncommon") e.push(`${w}: raridade do item base deve ser >= rare`);
    if (typeof x.name !== "string" || !x.name || typeof x.description !== "string" || x.description.length < 10) e.push(`${w}: name/description obrigatorios`);
    if (!Array.isArray(x.effects) || x.effects.length < 1 || x.effects.length > 3) e.push(`${w}: 1..3 effects`);
    (x.effects ?? []).forEach((fx, i) => {
      e.push(...effectErrors(fx, `${w}.effects[${i}]`));
      // o jogo so aplica efeitos de habilidade dos unicos (stats fixos ficam no .tres); `stat` aqui seria um no-op silencioso
      if (fx && fx.type !== "skill_mod") e.push(`${w}.effects[${i}]: unicos usam apenas type skill_mod (stats fixos vao no .tres)`);
    });
    const o = x.obtain ?? {};
    if (!Number.isInteger(o.min_level) || o.min_level < 1 || o.min_level > 50) e.push(`${w}: obtain.min_level 1..50`);
    if (!Array.isArray(o.sources) || o.sources.length < 1) e.push(`${w}: obtain.sources vazio`);
    for (const s of o.sources ?? []) {
      if (!lootIds.has(s.loot_table)) e.push(`${w}: loot_table '${s.loot_table}' inexistente`);
      if (!isNum(s.chance) || s.chance <= 0 || s.chance > 1) e.push(`${w}: chance (0,1]`);
    }
  }
  if ((u.uniques ?? []).length < 3) e.push("_uniques.json: o roadmap pede 3-5 itens unicos de teste");
  if (e.length) throw new Error(e.join("\n"));
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
  // E6.3: raridades, affixes e unicos (dados). Aditivo: schema_version continua 1; leitores antigos ignoram as chaves novas.
  const rar = readJson("_rarity.json");
  const aff = readJson("_affixes.json");
  const uni = readJson("_uniques.json");
  validateRarities(rar);
  validateAffixes(aff, rar);
  const lootIds = new Set(readdirSync(LOOT_DIR).filter((f) => f.endsWith(".tres")).map((f) => /^id = &"([a-z0-9_]+)"/m.exec(readFileSync(join(LOOT_DIR, f), "utf8"))?.[1]));
  validateUniques(uni, items, lootIds);
  const uniqueIds = new Set(uni.uniques.map((x) => x.id));
  for (const it of items) if (uniqueIds.has(it.id)) it.unique = true;
  return {
    schema_version: 1,
    source: "data/items/*.tres + _rarity.json + _affixes.json + _uniques.json (gerado por tools/gen_items_catalog.mjs)",
    items,
    ilvl_max: rar.ilvl_max,
    max_affixes: rar.max_affixes,
    rarities: rar.rarities.map(({ id, name, rank, budget, affix_min, affix_max, prefix_max, suffix_max }) => ({ id, name, rank, budget, affix_min, affix_max, prefix_max, suffix_max })),
    affixes: aff.affixes,
    uniques: uni.uniques.map(({ id, effects, obtain }) => ({ id, effects, obtain })),
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
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
}
