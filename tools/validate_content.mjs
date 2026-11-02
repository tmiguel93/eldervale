#!/usr/bin/env node
// E6.4 - Validador de conteudo do Eldervale (Node, sem dependencias). Carrega TODO o conteudo de data/ e confere:
//  - ids unicos, estaveis ([a-z][a-z0-9_]*) e iguais ao nome do arquivo;
//  - estrutura/faixas de classes, talentos, itens (raridades, affixes, unicos), receitas, quests, exploracao (reaproveita os
//    validadores dos geradores tools/gen_*_catalog.mjs);
//  - referencias cruzadas: quest -> NPC/dialogo/item/inimigo/area/ponto/zona, loot -> item, inimigo -> loot, receita -> item/estacao,
//    talento -> habilidade, unico -> tabela de loot/modificador, dialogo -> quest/no, NPC/area/ponto -> zona do mundo;
//  - ciclos de pre-requisitos de quest e quests INALCANCAVEIS (pre-requisito, nivel, NPC fora do mundo, objetivo sem fonte, zona isolada);
//  - catalogos gerados em shared/content_schemas/*.json em dia com data/.
// Uso (na raiz do repo):   node tools/validate_content.mjs [--root <pasta>] [--json] [--no-generated]
// Saida: relatorio no stdout; codigo 0 = sem erros, 1 = ha erros, 2 = uso invalido. `validateContent(root)` e exportada para testes.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildClassCatalog } from "./gen_classes_catalog.mjs";
import { buildTalentCatalog } from "./gen_talents_catalog.mjs";
import { buildRecipeCatalog } from "./gen_recipes_catalog.mjs";
import { buildQuestCatalog } from "./gen_quests_catalog.mjs";
import { checkVisualJson, checkVisualTres } from "./visual_check.mjs";
import { checkVfx } from "./vfx_check.mjs";
import { VISUAL_KEYS } from "./gen_classes_catalog.mjs";
import { parseTres, validateAffixes, validateRarities, validateUniques } from "./gen_items_catalog.mjs";

const DEFAULT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const MAX_LEVEL = 50;

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const listDir = (d, ext) => (existsSync(d) ? readdirSync(d).filter((f) => f.endsWith(ext)).sort() : []);
const jsonFiles = (d) => listDir(d, ".json").filter((f) => !f.startsWith("_"));
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/** Le o `[resource]` de um .tres: id, campos simples e o mapa ext_resource id -> caminho. */
function parseTresLoose(text) {
  const ext = {};
  for (const m of text.matchAll(/^\[ext_resource [^\]]*path="([^"]+)"[^\]]*id="([^"]+)"/gm)) ext[m[2]] = m[1];
  const idx = text.lastIndexOf("[resource]");
  const body = idx >= 0 ? text.slice(idx) : "";
  const f = (n) => new RegExp(`^${n}\\s*=\\s*(.+?)\\s*$`, "m").exec(body)?.[1];
  return { ext, body, id: /^&?"([^"]*)"$/.exec(f("id") ?? "")?.[1], field: f };
}

export function validateContent(root = DEFAULT_ROOT, opts = {}) {
  const errors = [];
  const err = (m) => errors.push(m);
  const stats = {};
  const D = (...p) => join(root, "data", ...p);
  const checkId = (id, where) => { if (typeof id !== "string" || !ID_RE.test(id)) err(`${where}: id '${String(id)}' fora do padrao [a-z][a-z0-9_]{0,47}`); };
  const uniq = (list, where) => { const s = new Set(); for (const x of list) { if (s.has(x)) err(`${where}: id duplicado '${x}'`); s.add(x); } return s; };

  // ---------------- itens (.tres) + raridades/affixes/unicos
  const itemList = [];
  for (const f of listDir(D("items"), ".tres")) {
    try {
      const it = parseTres(readFileSync(D("items", f), "utf8"), f);
      if (f !== `${it.id}.tres`) err(`items/${f}: nome do arquivo difere do id '${it.id}'`);
      checkId(it.id, `items/${f}`);
      itemList.push(it);
    } catch (e) { err(String(e.message)); }
  }
  const itemIds = uniq(itemList.map((i) => i.id), "itens");
  stats.itens = itemIds.size;

  // ---------------- loot e inimigos (.tres)
  const loot = new Map(); // id -> {items:[..]}
  for (const f of listDir(D("loot"), ".tres")) {
    const t = readFileSync(D("loot", f), "utf8");
    const p = parseTresLoose(t);
    if (!p.id) { err(`loot/${f}: id ausente`); continue; }
    if (f !== `${p.id}.tres`) err(`loot/${f}: nome do arquivo difere do id '${p.id}'`);
    checkId(p.id, `loot/${f}`);
    if (loot.has(p.id)) err(`loot: id duplicado '${p.id}'`);
    const entries = [...t.matchAll(/^item_id = &"([^"]+)"\s*$/gm)].map((m) => m[1]);
    const weights = [...t.matchAll(/^weight = ([-\d.]+)\s*$/gm)].map((m) => Number(m[1]));
    for (const it of entries) if (!itemIds.has(it)) err(`loot '${p.id}': item '${it}' inexistente em data/items`);
    if (weights.some((w) => !(w > 0))) err(`loot '${p.id}': peso de entrada deve ser > 0`);
    if (entries.length === 0) err(`loot '${p.id}': sem entradas`);
    const rolls = Number(p.field("rolls") ?? "1");
    if (!Number.isInteger(rolls) || rolls < 1 || rolls > 10) err(`loot '${p.id}': rolls fora de 1..10`);
    loot.set(p.id, { items: entries });
  }
  stats.tabelas_de_loot = loot.size;
  const enemies = new Map(); // id -> {loot}
  for (const f of listDir(D("enemies"), ".tres")) {
    const tresText = readFileSync(D("enemies", f), "utf8");
    const p = parseTresLoose(tresText);
    if (!p.id) { err(`enemies/${f}: id ausente`); continue; }
    checkVisualTres(tresText, `enemies/${f}`, root, err); // E8.1: visual_* (alias/arquivo/clips/acessorios existem)
    if (f !== `${p.id}.tres`) err(`enemies/${f}: nome do arquivo difere do id '${p.id}'`);
    checkId(p.id, `enemies/${f}`);
    if (enemies.has(p.id)) err(`inimigos: id duplicado '${p.id}'`);
    const xp = Number(p.field("xp_reward") ?? "0");
    if (!Number.isFinite(xp) || xp < 0) err(`inimigo '${p.id}': xp_reward invalido`);
    const lref = /ExtResource\("([^"]+)"\)/.exec(p.field("loot_table") ?? "")?.[1];
    let lootId = null;
    if (lref) {
      const path = p.ext[lref];
      lootId = path ? /([^/]+)\.tres$/.exec(path)?.[1] ?? null : null;
      if (!lootId || !loot.has(lootId)) err(`inimigo '${p.id}': tabela de loot '${path ?? lref}' inexistente`);
    }
    enemies.set(p.id, { loot: lootId });
  }
  stats.inimigos = enemies.size;

  // raridades, affixes, unicos
  try {
    const rar = readJson(D("items", "_rarity.json"));
    const aff = readJson(D("items", "_affixes.json"));
    const uni = readJson(D("items", "_uniques.json"));
    for (const [fn, a] of [[validateRarities, [rar]], [validateAffixes, [aff, rar]], [validateUniques, [uni, itemList, new Set(loot.keys())]]]) {
      try { fn(...a); } catch (e) { for (const line of String(e.message).split("\n")) err(line); }
    }
    stats.affixes = (aff.affixes ?? []).length;
    stats.unicos = (uni.uniques ?? []).length;
    uniq((aff.affixes ?? []).map((a) => a.id), "affixes");
    for (const u of uni.uniques ?? []) if (!itemIds.has(u.id)) err(`unico '${u.id}': sem item base`);
  } catch (e) { err(`items/_rarity|_affixes|_uniques: ${e.message}`); }

  // ---------------- habilidades, classes, talentos, receitas (validadores dos geradores)
  const { catalog: classCat, errors: classErr } = buildClassCatalog(root);
  classErr.forEach(err);
  stats.classes = classCat.classes.length;
  for (const f of jsonFiles(D("classes"))) { try { const c = readJson(D("classes", f)); if (f !== `${c.id}.json`) err(`classes/${f}: nome do arquivo difere do id`); checkId(c.id, `classes/${f}`); checkVisualJson(c, `classes/${f}`, root, err, VISUAL_KEYS); } catch { /* ja reportado */ } }
  const talents = buildTalentCatalog(root);
  talents.errors.forEach(err);
  stats.talentos = talents.catalog.trees.reduce((n, t) => n + t.nodes.length, 0);
  const recipes = buildRecipeCatalog(root);
  recipes.errors.forEach(err);
  stats.receitas = recipes.catalog.recipes.length;
  const recipeList = [];
  for (const f of jsonFiles(D("recipes"))) {
    try {
      const r = readJson(D("recipes", f));
      recipeList.push(r);
      for (const s of [...(r.ingredients ?? []), ...(r.results ?? [])]) if (!itemIds.has(s?.item_id)) err(`receita '${r.id}': item '${s?.item_id}' inexistente em data/items`);
    } catch { /* ja reportado */ }
  }

  // ---------------- mundo: zonas, NPCs, areas
  const zones = new Map();
  let world = null;
  const wdir = D("areas", "world");
  for (const f of jsonFiles(wdir)) {
    try { world = readJson(join(wdir, f)); } catch (e) { err(`areas/world/${f}: JSON invalido`); continue; }
    uniq((world.zones ?? []).map((z) => z.id), `mundo ${f}`);
    for (const z of world.zones ?? []) { checkId(z.id, `zona (${f})`); zones.set(z.id, z); }
    if (!zones.has(world.start_zone)) err(`mundo ${f}: start_zone '${world.start_zone}' inexistente`);
  }
  stats.zonas = zones.size;
  const inZone = (z, pos, margin = 0) => Array.isArray(pos) && pos.length >= 3 && Math.abs(pos[0] - z.center[0]) <= z.size[0] / 2 + margin && Math.abs(pos[2] - z.center[2]) <= z.size[1] / 2 + margin;
  const zoneAt = (pos) => [...zones.values()].find((z) => inZone(z, pos));
  const npcs = new Map();
  for (const f of jsonFiles(D("npcs"))) {
    try {
      const n = readJson(D("npcs", f));
      if (f !== `${n.id}.json`) err(`npcs/${f}: nome do arquivo difere do id`);
      checkId(n.id, `npcs/${f}`);
      if (npcs.has(n.id)) err(`npcs: id duplicado '${n.id}'`);
      if (typeof n.display_name !== "string" || !n.display_name) err(`npc '${n.id}': display_name ausente`);
      if (!isNum(n.interact_radius) || n.interact_radius <= 0 || n.interact_radius > 20) err(`npc '${n.id}': interact_radius fora de (0, 20]`);
      if (!Array.isArray(n.position) || n.position.length !== 3 || !n.position.every(isNum)) err(`npc '${n.id}': position invalida`);
      checkVisualJson(n, `npcs/${f}`, root, err, VISUAL_KEYS);
      npcs.set(n.id, n);
    } catch (e) { err(`npcs/${f}: JSON invalido`); }
  }
  stats.npcs = npcs.size;
  const npcZone = new Map();
  for (const z of zones.values()) {
    for (const n of z.npcs ?? []) {
      if (!npcs.has(n)) { err(`zona '${z.id}': NPC '${n}' inexistente`); continue; }
      if (!inZone(z, npcs.get(n).position, -1)) err(`zona '${z.id}': NPC '${n}' fora da zona`);
      npcZone.set(n, z.id);
    }
  }
  for (const id of npcs.keys()) if (zones.size > 0 && !npcZone.has(id)) err(`npc '${id}': nao esta listado em nenhuma zona do mundo`);
  const areas = new Map();
  for (const f of jsonFiles(D("areas"))) {
    try {
      for (const a of readJson(D("areas", f)).areas ?? []) {
        checkId(a.id, `areas/${f}`);
        if (areas.has(a.id)) err(`areas: id duplicado '${a.id}'`);
        if (!Array.isArray(a.center) || a.center.length !== 3 || !a.center.every(isNum) || !isNum(a.radius) || a.radius <= 0) err(`area '${a.id}': center/radius invalidos`);
        else if (zones.size > 0 && !zoneAt(a.center)) err(`area '${a.id}': fora de qualquer zona`);
        areas.set(a.id, a);
      }
    } catch { err(`areas/${f}: JSON invalido`); }
  }
  stats.areas = areas.size;
  // portais, spawns, inimigos, estacoes
  const edges = new Map();
  const stationZone = new Map();
  for (const z of zones.values()) {
    edges.set(z.id, []);
    for (const p of z.portals ?? []) {
      const dest = zones.get(p.to_zone);
      if (!dest) { err(`zona '${z.id}': portal '${p.id}' aponta para zona inexistente '${p.to_zone}'`); continue; }
      if (!dest.spawns?.[p.to_spawn]) err(`zona '${z.id}': portal '${p.id}': spawn '${p.to_spawn}' inexistente em '${dest.id}'`);
      edges.get(z.id).push(dest.id);
    }
    for (const e of z.enemies ?? []) {
      if (!enemies.has(e.type)) err(`zona '${z.id}': inimigo '${e.type}' inexistente em data/enemies`);
      if (!inZone(z, e.pos, -1)) err(`zona '${z.id}': inimigo '${e.type}' fora da zona`);
    }
    if (z.encounter?.boss && !enemies.has(z.encounter.boss)) err(`zona '${z.id}': chefe '${z.encounter.boss}' inexistente`);
    if (z.checkpoint && !z.spawns?.[z.checkpoint]) err(`zona '${z.id}': checkpoint '${z.checkpoint}' inexistente`);
    for (const s of z.stations ?? []) stationZone.set(s.id, z.id);
  }
  const reachZones = new Set();
  if (zones.has(world?.start_zone)) {
    const stack = [world.start_zone];
    while (stack.length) { const c = stack.pop(); if (reachZones.has(c)) continue; reachZones.add(c); stack.push(...(edges.get(c) ?? [])); }
    for (const id of zones.keys()) if (!reachZones.has(id)) err(`zona '${id}': inalcancavel a partir de '${world.start_zone}'`);
  }
  for (const r of recipeList) if (zones.size > 0 && !stationZone.has(r.station)) err(`receita '${r.id}': estacao '${r.station}' nao declarada no mundo`);

  // fontes de itens e inimigos alcancaveis
  const spawned = new Set(); // inimigos que existem em zona alcancavel
  for (const z of zones.values()) if (reachZones.has(z.id)) { for (const e of z.enemies ?? []) spawned.add(e.type); if (z.encounter?.boss) spawned.add(z.encounter.boss); }
  const obtainable = new Set();
  for (const e of spawned) for (const it of loot.get(enemies.get(e)?.loot)?.items ?? []) obtainable.add(it);
  const craftable = new Set();
  for (const r of recipeList) if (reachZones.has(stationZone.get(r.station))) for (const s of r.results ?? []) craftable.add(s.item_id);

  // ---------------- exploracao
  const qb = buildQuestCatalog(root); // inclui exploracao
  const poiList = [];
  for (const f of jsonFiles(D("exploration"))) {
    try {
      for (const p of readJson(D("exploration", f)).points ?? []) {
        poiList.push(p);
        const z = zones.get(p.zone);
        if (!z) err(`ponto '${p.id}': zona '${p.zone}' inexistente`);
        else if (!inZone(z, p.center, -1)) err(`ponto '${p.id}': fora da zona '${p.zone}'`);
        else if (!reachZones.has(z.id) && zones.size > 0) err(`ponto '${p.id}': zona '${p.zone}' inalcancavel`);
        for (const it of p.rewards?.items ?? []) if (!itemIds.has(it.item_id)) err(`ponto '${p.id}': item '${it.item_id}' inexistente`);
      }
    } catch { err(`exploration/${f}: JSON invalido`); }
  }
  stats.pontos_de_exploracao = poiList.length;
  const poiMap = new Map(poiList.map((p) => [p.id, p]));

  // ---------------- quests e dialogos
  const quests = new Map();
  for (const f of jsonFiles(D("quests"))) { try { const q = readJson(D("quests", f)); quests.set(q.id, q); checkId(q.id, `quests/${f}`); } catch { /* ja reportado pelo gerador */ } }
  stats.quests = quests.size;
  qb.errors.forEach(err);
  const dialogues = new Map();
  for (const f of jsonFiles(D("dialogues"))) {
    try {
      const d = readJson(D("dialogues", f));
      if (f !== `${d.id}.json`) err(`dialogues/${f}: nome do arquivo difere do id`);
      checkId(d.id, `dialogues/${f}`);
      if (dialogues.has(d.id)) err(`dialogos: id duplicado '${d.id}'`);
      dialogues.set(d.id, d);
    } catch { err(`dialogues/${f}: JSON invalido`); }
  }
  stats.dialogos = dialogues.size;
  const dlgOfNpc = new Map();
  for (const n of npcs.values()) {
    if (n.dialogue_id) {
      const d = dialogues.get(n.dialogue_id);
      if (!d) err(`npc '${n.id}': dialogo '${n.dialogue_id}' inexistente`);
      else if (d.npc_id !== n.id) err(`npc '${n.id}': dialogo '${d.id}' pertence a '${d.npc_id}'`);
      else dlgOfNpc.set(n.id, d);
    }
  }
  const effects = new Map(); // npc -> {accept:Set, turn_in:Set}
  const condQuests = (c, out) => { if (!c || typeof c !== "object") return; if (c.quest) out.push(c.quest); for (const k of ["all", "any"]) for (const x of c[k] ?? []) condQuests(x, out); if (c.not) condQuests(c.not, out); };
  for (const d of dialogues.values()) {
    const w = `dialogo '${d.id}'`;
    if (!npcs.has(d.npc_id)) err(`${w}: npc '${d.npc_id}' inexistente`);
    const nodes = d.nodes ?? {};
    for (const e of d.entries ?? []) {
      if (!nodes[e.node]) err(`${w}: entrada aponta para no inexistente '${e.node}'`);
      const qs = []; condQuests(e.if, qs);
      for (const q of qs) if (!quests.has(q)) err(`${w}: condicao referencia quest inexistente '${q}'`);
    }
    if (!(d.entries ?? []).length || (d.entries[d.entries.length - 1].if !== undefined)) err(`${w}: a ultima entrada deve ser o fallback (sem 'if')`);
    const eff = effects.get(d.npc_id) ?? { accept: new Set(), turn_in: new Set() };
    effects.set(d.npc_id, eff);
    for (const [nid, n] of Object.entries(nodes)) {
      const chs = n.choices ?? [];
      for (const c of chs) {
        if (c.next != null && !nodes[c.next]) err(`${w}: no '${nid}' aponta para no inexistente '${c.next}'`);
        for (const x of c.effects ?? []) {
          if (!quests.has(x.quest_id)) err(`${w}: efeito referencia quest inexistente '${x.quest_id}'`);
          (x.type === "accept_quest" ? eff.accept : eff.turn_in).add(x.quest_id);
        }
      }
      for (const x of n.on_enter ?? []) {
        if (!quests.has(x.quest_id)) err(`${w}: efeito referencia quest inexistente '${x.quest_id}'`);
        (x.type === "accept_quest" ? eff.accept : eff.turn_in).add(x.quest_id);
      }
    }
  }

  // alcancabilidade de quests: ponto fixo sobre os pre-requisitos
  const recipeResults = craftable;
  const whyNot = new Map();
  const reach = new Set();
  const objProblem = (q, o) => {
    switch (o.type) {
      case "kill": return spawned.has(o.target) ? null : `inimigo '${o.target}' nao nasce em nenhuma zona alcancavel`;
      case "collect": return obtainable.has(o.target) || recipeResults.has(o.target) || [...quests.values()].some((x) => x.rewards?.items?.some((i) => i.item_id === o.target)) || poiList.some((p) => p.rewards?.items?.some((i) => i.item_id === o.target)) ? null : `item '${o.target}' sem fonte (loot/receita/recompensa)`;
      case "reach_area": { const a = areas.get(o.target); return a && reachZones.has(zoneAt(a.center)?.id) ? null : `area '${o.target}' fora de zona alcancavel`; }
      case "talk": return reachZones.has(npcZone.get(o.target)) ? null : `NPC '${o.target}' fora de zona alcancavel`;
      case "craft": return recipeResults.has(o.target) ? null : `nenhuma receita alcancavel produz '${o.target}'`;
      case "discover": { const p = poiMap.get(o.target); if (!p) return `ponto '${o.target}' inexistente`; return reachZones.has(p.zone) ? null : `ponto '${o.target}' em zona inalcancavel`; }
      default: return `tipo de objetivo '${o.type}' desconhecido`;
    }
  };
  let changed = true;
  while (changed) {
    changed = false;
    for (const q of quests.values()) {
      if (reach.has(q.id)) continue;
      const why = [];
      for (const p of q.prerequisites?.quests ?? []) if (!reach.has(p)) why.push(`pre-requisito '${p}' inalcancavel`);
      if ((q.prerequisites?.min_level ?? 1) > MAX_LEVEL) why.push("min_level acima do nivel maximo");
      for (const k of ["giver_npc", "turn_in_npc"]) if (zones.size > 0 && !reachZones.has(npcZone.get(q[k]))) why.push(`${k} '${q[k]}' fora de zona alcancavel`);
      if (!effects.get(q.giver_npc)?.accept.has(q.id)) why.push(`dialogo de '${q.giver_npc}' nao oferece a quest`);
      if (!effects.get(q.turn_in_npc)?.turn_in.has(q.id)) why.push(`dialogo de '${q.turn_in_npc}' nao entrega a quest`);
      for (const o of q.objectives ?? []) { const m = zones.size > 0 ? objProblem(q, o) : null; if (m) why.push(`objetivo '${o.id}': ${m}`); }
      if (why.length === 0) { reach.add(q.id); changed = true; } else whyNot.set(q.id, why);
    }
  }
  if (zones.size > 0) for (const q of quests.values()) if (!reach.has(q.id)) err(`quest '${q.id}' inalcancavel: ${(whyNot.get(q.id) ?? []).join("; ")}`);
  stats.quests_alcancaveis = reach.size;
  // pontos com exigencias impossiveis
  for (const p of poiList) {
    for (const q of p.requires_quests ?? []) if (quests.has(q) && !reach.has(q) && zones.size > 0) err(`ponto '${p.id}': exige quest inalcancavel '${q}'`);
    if ((p.min_level ?? 1) > MAX_LEVEL) err(`ponto '${p.id}': min_level acima do maximo`);
  }

  // ---------------- catalogos gerados em dia (shared/content_schemas)
  if (!opts.noGenerated) {
    const fresh = (rel, obj) => {
      const p = join(root, "shared", "content_schemas", rel);
      if (!existsSync(p)) { err(`shared/content_schemas/${rel}: ausente (rode o gerador)`); return; }
      if (readFileSync(p, "utf8") !== JSON.stringify(obj, null, 2) + "\n") err(`shared/content_schemas/${rel}: desatualizado em relacao a data/ (rode o gerador correspondente)`);
    };
    if (qb.errors.length === 0) { fresh("quests.json", qb.catalog); fresh("exploration.json", qb.exploration); }
    if (classErr.length === 0) fresh("classes.json", classCat);
    if (talents.errors.length === 0) fresh("talents.json", talents.catalog);
    if (recipes.errors.length === 0) fresh("recipes.json", recipes.catalog);
  }
  Object.assign(stats, Object.fromEntries(Object.entries(checkVfx(root, err)).map(([k, v]) => [`vfx_${k}`, v]))); // E8.3
  return { errors: [...new Set(errors)], stats };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const argv = process.argv.slice(2);
  const ri = argv.indexOf("--root");
  const root = ri >= 0 ? resolve(argv[ri + 1] ?? "") : DEFAULT_ROOT;
  if (ri >= 0 && (!argv[ri + 1] || !existsSync(root))) { console.error("uso: node tools/validate_content.mjs [--root <pasta>] [--json] [--no-generated]"); process.exit(2); }
  const { errors, stats } = validateContent(root, { noGenerated: argv.includes("--no-generated") });
  if (argv.includes("--json")) console.log(JSON.stringify({ ok: errors.length === 0, stats, errors }, null, 2));
  else {
    console.log("== Validacao de conteudo do Eldervale ==");
    for (const [k, v] of Object.entries(stats)) console.log(`  ${k.replace(/_/g, " ")}: ${v}`);
    if (errors.length) { console.log(`\nERROS (${errors.length}):`); for (const e of errors) console.log(`  - ${e}`); }
    console.log(errors.length ? `\nRESULTADO: FALHOU (${errors.length} erro(s))` : "\nRESULTADO: OK (0 erros)");
  }
  process.exit(errors.length ? 1 : 0);
}
