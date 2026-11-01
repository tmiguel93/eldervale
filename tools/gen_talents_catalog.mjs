#!/usr/bin/env node
// Gera shared/content_schemas/talents.json (catalogo que o BACKEND usa para validar alocacao de talentos: pontos, pre-requisitos,
// max_rank, especializacao, custo de respec) a partir de data/talents/*.json (fonte de verdade, tambem lida pelo Godot:
// scripts/talents/talent_tree.gd / talent_catalog.gd). Valida a estrutura, o GRAFO (aciclico, requisitos existentes, nos genericos
// nao dependem de nos de especializacao) e as referencias (classe, especializacao inicial, habilidades da classe, item do respec).
// Os `effects` (stats e modificadores de habilidade) sao validados aqui, mas NAO vao para o catalogo do backend (so o Godot os aplica).
// Uso (na raiz do repo):
//   node tools/gen_talents_catalog.mjs          # escreve o arquivo
//   node tools/gen_talents_catalog.mjs --check  # sai com 1 se o arquivo difere do que seria gerado ou se ha erro
// Regenere SEMPRE que data/talents, data/classes ou data/skills mudarem. Espelha scripts/talents/talent_tree.gd.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { skillIndex } from "./gen_classes_catalog.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "shared", "content_schemas", "talents.json");
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const TIERS = ["small", "notable", "mastery"];
const STATS = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"];
const ELEMENTS = ["physical", "fire", "ice", "lightning"];
const WHEN = ["self_hp_below", "self_hp_above", "resource_above"];
const MOD_KEYS = {
  damage: ["damage_pct"],
  extra_projectiles: ["count", "spread_deg", "damage_scale"],
  area: ["radius_pct"],
  duration: ["i_frames_add"],
  cost: ["cost_pct", "cooldown_pct"],
  convert: ["to", "damage_pct"],
  condition: ["when", "threshold", "damage_pct"],
  synergy: ["after_skill", "window", "damage_pct"],
};
const MAX_NODES = 40, MAX_RANK = 5, MAX_COST = 10, MAX_EFFECTS = 6, MAX_REQUIRES = 4;

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const isNum = (v) => typeof v === "number" && Number.isFinite(v);
const isInt = (v) => Number.isSafeInteger(v);
const inRange = (v, lo, hi) => isNum(v) && v >= lo && v <= hi;

/** Ids de data/items/*.tres. */
function itemIds(root) {
  const dir = join(root, "data", "items");
  const out = new Set();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir).filter((x) => x.endsWith(".tres"))) {
    const id = /^id\s*=\s*&"([a-z][a-z0-9_]*)"\s*$/m.exec(readFileSync(join(dir, f), "utf8"))?.[1];
    if (id) out.add(id);
  }
  return out;
}

export function validateProgression(p) {
  const e = [];
  if (typeof p !== "object" || p === null || Array.isArray(p)) return ["_progression.json: raiz deve ser objeto"];
  for (const k of Object.keys(p)) if (!["schema_version", "points", "respec"].includes(k)) e.push(`_progression.json: campo desconhecido '${k.slice(0, 40)}'`);
  if (p.schema_version !== 1) e.push("_progression.json: schema_version deve ser 1");
  const pt = p.points ?? {};
  if (!isInt(pt.first_point_level) || pt.first_point_level < 2 || pt.first_point_level > 50) e.push("_progression.json: points.first_point_level deve ser inteiro 2..50");
  if (!isInt(pt.points_per_level) || pt.points_per_level < 1 || pt.points_per_level > 5) e.push("_progression.json: points.points_per_level deve ser inteiro 1..5");
  if (!isInt(pt.max_points) || pt.max_points < 1 || pt.max_points > 500) e.push("_progression.json: points.max_points deve ser inteiro 1..500");
  for (const k of Object.keys(pt)) if (!["first_point_level", "points_per_level", "max_points"].includes(k)) e.push(`_progression.json: points.${k.slice(0, 40)} desconhecido`);
  const rs = p.respec ?? {};
  for (const k of Object.keys(rs)) if (!["cost_items", "require_safe_zone"].includes(k)) e.push(`_progression.json: respec.${k.slice(0, 40)} desconhecido`);
  if (typeof rs.require_safe_zone !== "boolean") e.push("_progression.json: respec.require_safe_zone deve ser bool");
  if (!Array.isArray(rs.cost_items) || rs.cost_items.length > 3) e.push("_progression.json: respec.cost_items deve ser lista de ate 3");
  else {
    const seen = new Set();
    for (const c of rs.cost_items) {
      if (typeof c?.item_id !== "string" || !ID_RE.test(c.item_id) || seen.has(c.item_id)) e.push("_progression.json: respec.cost_items: item_id invalido/repetido");
      else seen.add(c.item_id);
      if (!isInt(c?.qty) || c.qty < 1 || c.qty > 99) e.push("_progression.json: respec.cost_items: qty deve ser inteiro 1..99");
      for (const k of Object.keys(c ?? {})) if (!["item_id", "qty"].includes(k)) e.push(`_progression.json: respec.cost_items: campo '${k.slice(0, 40)}' desconhecido`);
    }
  }
  return e;
}

/** Valida UM efeito; `ctx` = { skills (Map id->info), classSkills (Set), where }. */
export function validateEffect(fx, ctx) {
  const e = [];
  const w = ctx.where;
  if (typeof fx !== "object" || fx === null || Array.isArray(fx)) return [`${w}: efeito deve ser objeto`];
  if (fx.type === "stat") {
    for (const k of Object.keys(fx)) if (!["type", "stat", "amount"].includes(k)) e.push(`${w}: campo '${k.slice(0, 40)}' desconhecido no efeito stat`);
    if (!STATS.includes(fx.stat)) e.push(`${w}: stat desconhecido`);
    else if (!inRange(fx.amount, 0.0001, fx.stat === "resistance" ? 0.1 : 1000)) e.push(`${w}: stat.amount fora de faixa`);
    return e;
  }
  if (fx.type !== "skill_mod") return [`${w}: type de efeito deve ser stat|skill_mod`];
  const allowed = ["type", "skill", "mod", ...(MOD_KEYS[fx.mod] ?? [])];
  for (const k of Object.keys(fx)) if (!allowed.includes(k)) e.push(`${w}: campo '${k.slice(0, 40)}' desconhecido no modificador`);
  if (typeof fx.skill !== "string" || !ctx.classSkills.has(fx.skill)) e.push(`${w}: habilidade alvo '${String(fx.skill).slice(0, 40)}' nao pertence a classe`);
  const sk = ctx.skills.get(fx.skill);
  switch (fx.mod) {
    case "damage":
      if (!inRange(fx.damage_pct, 0.01, 2)) e.push(`${w}: damage_pct deve estar em 0.01..2`);
      break;
    case "extra_projectiles":
      if (!isInt(fx.count) || fx.count < 1 || fx.count > 2) e.push(`${w}: count deve ser inteiro 1..2`);
      if (!inRange(fx.spread_deg, 1, 45)) e.push(`${w}: spread_deg deve estar em 1..45`);
      if (!inRange(fx.damage_scale, 0.1, 1)) e.push(`${w}: damage_scale deve estar em 0.1..1`);
      if (sk && !sk.projectile) e.push(`${w}: extra_projectiles exige habilidade que dispara projetil`);
      break;
    case "area":
      if (!inRange(fx.radius_pct, 0.01, 1)) e.push(`${w}: radius_pct deve estar em 0.01..1`);
      if (sk && sk.kind === 1) e.push(`${w}: area nao se aplica a esquiva`);
      break;
    case "duration":
      if (!inRange(fx.i_frames_add, 0.01, 0.5)) e.push(`${w}: i_frames_add deve estar em 0.01..0.5`);
      if (sk && sk.kind !== 1) e.push(`${w}: duration exige habilidade de esquiva`);
      break;
    case "cost": {
      const has = fx.cost_pct !== undefined || fx.cooldown_pct !== undefined;
      if (!has) e.push(`${w}: cost exige cost_pct e/ou cooldown_pct`);
      for (const k of ["cost_pct", "cooldown_pct"]) if (fx[k] !== undefined && !inRange(fx[k], -0.9, 0)) e.push(`${w}: ${k} deve estar em -0.9..0`);
      break;
    }
    case "convert":
      if (!ELEMENTS.includes(fx.to)) e.push(`${w}: convert.to deve ser ${ELEMENTS.join("|")}`);
      if (fx.damage_pct !== undefined && !inRange(fx.damage_pct, 0, 1)) e.push(`${w}: damage_pct deve estar em 0..1`);
      if (sk && sk.kind === 1) e.push(`${w}: convert nao se aplica a esquiva`);
      break;
    case "condition":
      if (!WHEN.includes(fx.when)) e.push(`${w}: condition.when deve ser ${WHEN.join("|")}`);
      if (!inRange(fx.threshold, 0.05, 0.95)) e.push(`${w}: threshold deve estar em 0.05..0.95`);
      if (!inRange(fx.damage_pct, 0.01, 2)) e.push(`${w}: damage_pct deve estar em 0.01..2`);
      if (sk && sk.kind === 1) e.push(`${w}: condition nao se aplica a esquiva`);
      break;
    case "synergy":
      if (typeof fx.after_skill !== "string" || !ctx.classSkills.has(fx.after_skill)) e.push(`${w}: after_skill nao pertence a classe`);
      else if (fx.after_skill === fx.skill) e.push(`${w}: after_skill deve ser outra habilidade`);
      if (!inRange(fx.window, 0.5, 10)) e.push(`${w}: window deve estar em 0.5..10`);
      if (!inRange(fx.damage_pct, 0.01, 2)) e.push(`${w}: damage_pct deve estar em 0.01..2`);
      if (sk && sk.kind === 1) e.push(`${w}: synergy nao se aplica a esquiva`);
      break;
    default:
      e.push(`${w}: mod desconhecido '${String(fx.mod).slice(0, 40)}'`);
  }
  return e;
}

/** Valida UMA arvore. `cls` = classe de data/classes (ou undefined). Devolve erros. */
export function validateTree(t, file, cls, skills) {
  const e = [];
  const w = `talentos '${t?.class_id}' (${file})`;
  if (typeof t !== "object" || t === null || Array.isArray(t)) return [`${file}: raiz deve ser objeto`];
  for (const k of Object.keys(t)) if (!["schema_version", "class_id", "nodes"].includes(k)) e.push(`${w}: campo desconhecido '${k.slice(0, 40)}'`);
  if (t.schema_version !== 1) e.push(`${w}: schema_version deve ser 1`);
  if (typeof t.class_id !== "string" || !ID_RE.test(t.class_id)) e.push(`${file}: class_id invalido`);
  else if (file !== `${t.class_id}.json`) e.push(`${w}: nome do arquivo difere do class_id`);
  if (!cls) { e.push(`${w}: classe inexistente em data/classes`); return e; }
  const activeSpecs = new Set((cls.specializations ?? []).filter((s) => s.planned === false).map((s) => s.id));
  const classSkills = new Set(Object.values(cls.skills ?? {}));
  if (!Array.isArray(t.nodes) || t.nodes.length < 1 || t.nodes.length > MAX_NODES) return [...e, `${w}: nodes deve ter 1..${MAX_NODES}`];
  const byId = new Map();
  for (const n of t.nodes) {
    const nw = `${w} no '${n?.id}'`;
    if (typeof n !== "object" || n === null || Array.isArray(n)) { e.push(`${w}: no invalido`); continue; }
    for (const k of Object.keys(n)) if (!["id", "name", "description", "tier", "spec", "requires", "min_points_spent", "min_level", "cost", "max_rank", "effects"].includes(k)) e.push(`${nw}: campo desconhecido '${k.slice(0, 40)}'`);
    if (typeof n.id !== "string" || !ID_RE.test(n.id)) { e.push(`${nw}: id invalido`); continue; }
    if (byId.has(n.id)) { e.push(`${nw}: id duplicado`); continue; }
    byId.set(n.id, n);
    if (typeof n.name !== "string" || n.name.trim() === "" || n.name.length > 60) e.push(`${nw}: name invalido`);
    if (typeof n.description !== "string" || n.description.length > 300) e.push(`${nw}: description invalida`);
    if (!TIERS.includes(n.tier)) e.push(`${nw}: tier deve ser ${TIERS.join("|")}`);
    if (typeof n.spec !== "string" || (n.spec !== "" && !activeSpecs.has(n.spec))) e.push(`${nw}: spec deve ser vazio ou uma especializacao inicial da classe`);
    if (!isInt(n.cost) || n.cost < 1 || n.cost > MAX_COST) e.push(`${nw}: cost deve ser inteiro 1..${MAX_COST}`);
    if (!isInt(n.max_rank) || n.max_rank < 1 || n.max_rank > MAX_RANK) e.push(`${nw}: max_rank deve ser inteiro 1..${MAX_RANK}`);
    if (!isInt(n.min_points_spent) || n.min_points_spent < 0 || n.min_points_spent > 100) e.push(`${nw}: min_points_spent deve ser inteiro 0..100`);
    if (!isInt(n.min_level) || n.min_level < 1 || n.min_level > 50) e.push(`${nw}: min_level deve ser inteiro 1..50`);
    if (!Array.isArray(n.requires) || n.requires.length > MAX_REQUIRES || n.requires.some((r) => typeof r !== "string" || !ID_RE.test(r)) || new Set(n.requires).size !== n.requires.length) e.push(`${nw}: requires invalido (lista de ate ${MAX_REQUIRES} ids unicos)`);
    if (!Array.isArray(n.effects) || n.effects.length < 1 || n.effects.length > MAX_EFFECTS) e.push(`${nw}: effects deve ter 1..${MAX_EFFECTS}`);
    else n.effects.forEach((fx, i) => e.push(...validateEffect(fx, { skills, classSkills, where: `${nw} efeito ${i}` })));
  }
  // referencias + grafo
  for (const n of byId.values()) {
    for (const r of Array.isArray(n.requires) ? n.requires : []) {
      const rn = byId.get(r);
      if (!rn) e.push(`${w} no '${n.id}': requisito '${r}' inexistente`);
      else if (r === n.id) e.push(`${w} no '${n.id}': requisito de si mesmo`);
      else if (n.spec === "" && rn.spec !== "") e.push(`${w} no '${n.id}': no generico nao pode exigir no de especializacao ('${r}')`);
      else if (n.spec !== "" && rn.spec !== "" && rn.spec !== n.spec) e.push(`${w} no '${n.id}': requisito de outra especializacao ('${r}')`);
    }
  }
  const state = new Map(); // 1 visitando, 2 pronto
  const dfs = (id, path) => {
    if (state.get(id) === 2) return;
    if (state.get(id) === 1) { e.push(`${w}: ciclo de requisitos (${[...path, id].join(" -> ")})`); return; }
    state.set(id, 1);
    for (const r of byId.get(id)?.requires ?? []) if (byId.has(r)) dfs(r, [...path, id]);
    state.set(id, 2);
  };
  for (const id of byId.keys()) dfs(id, []);
  const masteries = [...byId.values()].filter((n) => n.tier === "mastery");
  if (masteries.length !== 1) e.push(`${w}: a arvore deve ter exatamente 1 maestria (tem ${masteries.length})`);
  return e;
}

export function buildTalentCatalog(root = ROOT) {
  const errors = [];
  const dir = join(root, "data", "talents");
  let progression = null;
  try { progression = readJson(join(dir, "_progression.json")); errors.push(...validateProgression(progression)); }
  catch (err) { errors.push(`_progression.json: ${err.message}`); }
  const items = itemIds(root);
  for (const c of progression?.respec?.cost_items ?? []) if (!items.has(c?.item_id)) errors.push(`_progression.json: item de custo do respec '${c?.item_id}' inexistente em data/items`);

  const skills = skillIndex(root);
  const trees = [];
  const seen = new Set();
  const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("_")).sort() : [];
  for (const f of files) {
    let t;
    try { t = readJson(join(dir, f)); } catch (err) { errors.push(`${f}: JSON invalido (${err.message})`); continue; }
    let cls;
    try { cls = readJson(join(root, "data", "classes", `${t?.class_id}.json`)); } catch { cls = undefined; }
    errors.push(...validateTree(t, f, cls, skills));
    if (typeof t?.class_id === "string") { if (seen.has(t.class_id)) errors.push(`class_id duplicado: ${t.class_id}`); seen.add(t.class_id); }
    trees.push({ t, cls });
  }
  // toda classe do catalogo precisa de arvore
  const classDir = join(root, "data", "classes");
  for (const f of existsSync(classDir) ? readdirSync(classDir).filter((x) => x.endsWith(".json") && !x.startsWith("_")) : []) {
    const id = f.replace(/\.json$/, "");
    if (!seen.has(id)) errors.push(`classe '${id}' sem arvore de talentos em data/talents`);
  }
  const out = trees
    .filter(({ t }) => typeof t?.class_id === "string" && Array.isArray(t.nodes))
    .sort((a, b) => (a.t.class_id < b.t.class_id ? -1 : 1))
    .map(({ t, cls }) => ({
      class_id: t.class_id,
      specs: (cls?.specializations ?? []).filter((s) => s.planned === false).map((s) => s.id),
      nodes: t.nodes.map((n) => ({
        id: n.id, spec: n.spec, requires: n.requires, min_points_spent: n.min_points_spent, min_level: n.min_level, cost: n.cost, max_rank: n.max_rank,
      })),
    }));
  return {
    catalog: {
      schema_version: 1,
      source: "data/talents/*.json (gerado por tools/gen_talents_catalog.mjs)",
      points: progression?.points,
      respec: progression?.respec,
      trees: out,
    },
    errors,
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { catalog, errors } = buildTalentCatalog();
  if (errors.length) {
    console.error("talentos invalidos:\n - " + errors.join("\n - "));
    process.exit(1);
  }
  const text = JSON.stringify(catalog, null, 2) + "\n";
  if (process.argv.includes("--check")) {
    const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
    if (cur !== text) {
      console.error("shared/content_schemas/talents.json desatualizado: rode node tools/gen_talents_catalog.mjs");
      process.exit(1);
    }
    console.log("talents.json em dia");
  } else {
    writeFileSync(OUT, text);
    console.log(`escrito ${OUT}`);
  }
}
