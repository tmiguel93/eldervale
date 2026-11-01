#!/usr/bin/env node
// Gera shared/content_schemas/classes.json (catalogo que o BACKEND usa para validar `class_id` e obter os stats base
// de criacao) a partir de data/classes/*.json (fonte de verdade, tambem lida pelo Godot: scripts/classes/class_def.gd).
// Valida a estrutura e as referencias cruzadas (habilidades em data/skills/*.tres, slots por tipo, especializacoes unicas).
// Uso (na raiz do repo):
//   node tools/gen_classes_catalog.mjs          # escreve o arquivo
//   node tools/gen_classes_catalog.mjs --check  # sai com 1 se o arquivo difere do que seria gerado ou se ha erro
// Regenere SEMPRE que uma classe ou habilidade em data/ mudar. Espelha scripts/classes/class_def.gd.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "shared", "content_schemas", "classes.json");
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const SLOTS = ["attack", "skill_1", "skill_2", "dodge"];
const RESOURCE_KINDS = ["stamina", "mana"];
const STAT_KEYS = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"];
const STAT_MAX = { resistance: 0.75, move_speed: 100 };
const STAT_DEFAULT_MAX = 100000, MAX_GROWTH = 1000, MAX_TAGS = 8, MAX_SPECS = 6;
const DEFAULT_CLASS = "warrior";

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const jsonFiles = (dir) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("_")).sort() : []);
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/** Habilidades de data/skills/*.tres: id -> { kind (0 ataque, 1 esquiva), cost }. */
export function skillIndex(root = ROOT) {
  const dir = join(root, "data", "skills");
  const out = new Map();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir).filter((x) => x.endsWith(".tres"))) {
    const t = readFileSync(join(dir, f), "utf8");
    const id = /^id\s*=\s*&"([a-z][a-z0-9_]*)"\s*$/m.exec(t)?.[1];
    const kind = Number(/^kind\s*=\s*(\d+)\s*$/m.exec(t)?.[1] ?? 0);
    const cost = Number(/^resource_cost\s*=\s*([0-9.]+)\s*$/m.exec(t)?.[1] ?? 0);
    if (id) out.set(id, { kind, cost, file: f });
  }
  return out;
}

/** Valida UMA classe; devolve lista de erros. */
export function validateClass(c, file = "?") {
  const e = [];
  const w = `classe '${c?.id}' (${file})`;
  if (typeof c !== "object" || c === null || Array.isArray(c)) return [`${file}: raiz deve ser objeto`];
  const allowed = ["schema_version", "id", "display_name", "description", "resource", "base_stats", "growth_per_level", "skills", "specializations"];
  for (const k of Object.keys(c)) if (!allowed.includes(k)) e.push(`${w}: campo desconhecido '${k.slice(0, 40)}'`);
  if (c.schema_version !== 1) e.push(`${w}: schema_version deve ser 1`);
  if (typeof c.id !== "string" || !ID_RE.test(c.id)) e.push(`${file}: id invalido`);
  else if (file !== "?" && file !== `${c.id}.json`) e.push(`${w}: nome do arquivo difere do id`);
  if (typeof c.display_name !== "string" || c.display_name.trim() === "") e.push(`${w}: display_name ausente`);
  if (c.description !== undefined && (typeof c.description !== "string" || c.description.length > 400)) e.push(`${w}: description invalida`);
  if (!RESOURCE_KINDS.includes(c.resource?.kind)) e.push(`${w}: resource.kind deve ser ${RESOURCE_KINDS.join("|")}`);
  const block = (v, label, isBase) => {
    if (typeof v !== "object" || v === null || Array.isArray(v)) { e.push(`${w}: ${label} deve ser objeto`); return; }
    for (const k of Object.keys(v)) if (!STAT_KEYS.includes(k)) e.push(`${w}: ${label}.${k} desconhecido`);
    for (const k of STAT_KEYS) {
      if (v[k] === undefined) { if (isBase) e.push(`${w}: ${label}.${k} ausente`); continue; }
      const max = STAT_MAX[k] ?? (isBase ? STAT_DEFAULT_MAX : MAX_GROWTH);
      if (!isNum(v[k]) || v[k] < 0 || v[k] > max) e.push(`${w}: ${label}.${k} fora de 0..${max}`);
    }
    if (isBase) for (const k of ["max_health", "max_resource", "attack_power", "move_speed"]) if (!(v[k] > 0)) e.push(`${w}: ${label}.${k} deve ser > 0`);
  };
  block(c.base_stats, "base_stats", true);
  block(c.growth_per_level, "growth_per_level", false);
  if (typeof c.skills !== "object" || c.skills === null) e.push(`${w}: skills deve ser objeto`);
  else {
    for (const k of Object.keys(c.skills)) if (!SLOTS.includes(k)) e.push(`${w}: slot '${k.slice(0, 40)}' desconhecido`);
    const seen = new Set();
    for (const s of SLOTS) {
      const sid = c.skills[s];
      if (typeof sid !== "string" || !ID_RE.test(sid)) e.push(`${w}: skills.${s} ausente/invalido`);
      else if (seen.has(sid)) e.push(`${w}: habilidade '${sid}' repetida em slots`);
      else seen.add(sid);
    }
  }
  if (!Array.isArray(c.specializations) || c.specializations.length < 1 || c.specializations.length > MAX_SPECS) e.push(`${w}: specializations deve ter 1..${MAX_SPECS}`);
  else {
    const seen = new Set();
    for (const s of c.specializations) {
      const sw = `${w} especializacao '${s?.id}'`;
      for (const k of Object.keys(s ?? {})) if (!["id", "display_name", "tags", "description", "planned"].includes(k)) e.push(`${sw}: campo desconhecido '${k.slice(0, 40)}'`);
      if (typeof s?.id !== "string" || !ID_RE.test(s.id)) e.push(`${sw}: id invalido`);
      else if (seen.has(s.id)) e.push(`${sw}: id duplicado`);
      else seen.add(s.id);
      if (typeof s?.display_name !== "string" || s.display_name.trim() === "") e.push(`${sw}: display_name ausente`);
      if (typeof s?.planned !== "boolean") e.push(`${sw}: planned deve ser bool`);
      if (!Array.isArray(s?.tags) || s.tags.length < 1 || s.tags.length > MAX_TAGS || s.tags.some((t) => typeof t !== "string" || !ID_RE.test(t))) e.push(`${sw}: tags invalidas`);
    }
    if (!c.specializations.some((s) => s?.planned === false)) e.push(`${w}: precisa de ao menos 1 especializacao inicial (planned = false)`);
  }
  return e;
}

export function buildClassCatalog(root = ROOT) {
  const errors = [];
  const dir = join(root, "data", "classes");
  const classes = [];
  for (const f of jsonFiles(dir)) {
    let c;
    try { c = readJson(join(dir, f)); } catch (err) { errors.push(`${f}: JSON invalido (${err.message})`); continue; }
    errors.push(...validateClass(c, f));
    classes.push(c);
  }
  const ids = new Set();
  for (const c of classes) { if (ids.has(c.id)) errors.push(`id duplicado: ${c.id}`); ids.add(c.id); }
  if (!ids.has(DEFAULT_CLASS)) errors.push(`classe padrao '${DEFAULT_CLASS}' ausente`);

  const skills = skillIndex(root);
  const owner = new Map(), specs = new Map();
  for (const c of classes) {
    if (typeof c?.id !== "string") continue;
    for (const s of SLOTS) {
      const sid = c.skills?.[s];
      if (typeof sid !== "string") continue;
      const sk = skills.get(sid);
      if (!sk) { errors.push(`classe '${c.id}': habilidade '${sid}' (slot ${s}) inexistente em data/skills`); continue; }
      if ((sk.kind === 1) !== (s === "dodge")) errors.push(`classe '${c.id}': slot ${s} exige habilidade ${s === "dodge" ? "de esquiva" : "de ataque"}`);
      if (s === "attack" && sk.cost > 0) errors.push(`classe '${c.id}': o ataque basico nao pode custar recurso`);
      if (owner.has(sid) && owner.get(sid) !== c.id) errors.push(`habilidade '${sid}' usada pelas classes ${owner.get(sid)} e ${c.id}`);
      owner.set(sid, c.id);
    }
    for (const sp of c.specializations ?? []) {
      if (specs.has(sp?.id)) errors.push(`especializacao '${sp.id}' duplicada (${specs.get(sp.id)} e ${c.id})`);
      specs.set(sp?.id, c.id);
    }
  }
  const out = classes
    .filter((c) => typeof c?.id === "string")
    .sort((a, b) => (a.id < b.id ? -1 : 1))
    .map((c) => ({
      id: c.id,
      resource_kind: c.resource?.kind,
      base_stats: Object.fromEntries(STAT_KEYS.map((k) => [k, c.base_stats?.[k]])),
      skills: Object.fromEntries(SLOTS.map((s) => [s, c.skills?.[s]])),
      specializations: (c.specializations ?? []).map((s) => ({ id: s.id, planned: s.planned })),
    }));
  return { catalog: { schema_version: 1, source: "data/classes/*.json (gerado por tools/gen_classes_catalog.mjs)", default_class: DEFAULT_CLASS, classes: out }, errors };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { catalog, errors } = buildClassCatalog();
  if (errors.length) {
    console.error("classes invalidas:\n - " + errors.join("\n - "));
    process.exit(1);
  }
  const text = JSON.stringify(catalog, null, 2) + "\n";
  if (process.argv.includes("--check")) {
    const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
    if (cur !== text) {
      console.error("shared/content_schemas/classes.json desatualizado: rode node tools/gen_classes_catalog.mjs");
      process.exit(1);
    }
    console.log("classes.json em dia");
  } else {
    writeFileSync(OUT, text);
    console.log(`escrito ${OUT}`);
  }
}
