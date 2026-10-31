#!/usr/bin/env node
// Gera shared/content_schemas/quests.json (catalogo que o BACKEND usa para validar o estado de quests e as
// recompensas) a partir de data/quests/*.json (fonte de verdade, tambem lida pelo Godot).
// Valida a estrutura e as referencias cruzadas (itens, inimigos, NPCs, areas, prerequisitos, ciclos).
// Uso (na raiz do repo):
//   node tools/gen_quests_catalog.mjs          # escreve o arquivo
//   node tools/gen_quests_catalog.mjs --check  # sai com 1 se o arquivo difere do que seria gerado ou se ha erro
// Regenere SEMPRE que uma quest em data/quests mudar. Espelha scripts/quests/quest_def.gd.
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "shared", "content_schemas", "quests.json");
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const TYPES = ["main", "side", "exploration", "hunt", "gather", "dungeon", "story", "coop", "hidden"];
const OBJ_TYPES = ["kill", "collect", "reach_area", "talk"];
const MAX_OBJECTIVES = 6, MAX_REQUIRED = 999, MAX_XP = 100000, MAX_REWARD_ITEMS = 8, MAX_QTY = 99, MAX_LEVEL = 50;

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));
const jsonFiles = (dir) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("_")).sort() : []);
const isInt = (v) => Number.isSafeInteger(v);

/** Ids de inimigos existentes (data/enemies/*.tres, linha `id = &"..."`). */
function enemyIds(root) {
  const dir = join(root, "data", "enemies");
  const ids = new Set();
  if (!existsSync(dir)) return ids;
  for (const f of readdirSync(dir).filter((x) => x.endsWith(".tres"))) {
    const m = /^id\s*=\s*&?"([a-z][a-z0-9_]*)"\s*$/m.exec(readFileSync(join(dir, f), "utf8"));
    if (m) ids.add(m[1]);
  }
  return ids;
}

/** Valida UMA quest; devolve lista de erros. */
export function validateQuest(q, file = "?") {
  const e = [];
  const w = `quest '${q?.id}' (${file})`;
  const s = (k, max = 400) => {
    if (typeof q[k] !== "string" || q[k].trim() === "" || q[k].length > max) e.push(`${w}: '${k}' ausente/vazio/longo demais`);
  };
  if (typeof q !== "object" || q === null || Array.isArray(q)) return [`${file}: raiz deve ser objeto`];
  if (typeof q.id !== "string" || !ID_RE.test(q.id)) e.push(`${file}: id invalido`);
  if (q.schema_version !== 1) e.push(`${w}: schema_version deve ser 1`);
  if (!TYPES.includes(q.type)) e.push(`${w}: type invalido`);
  for (const k of ["region", "giver_npc", "turn_in_npc"]) if (typeof q[k] !== "string" || !ID_RE.test(q[k])) e.push(`${w}: '${k}' invalido`);
  s("title", 80); s("title_key", 96); s("description"); s("description_key", 96);
  if (q.abandonable !== undefined && typeof q.abandonable !== "boolean") e.push(`${w}: abandonable deve ser bool`);
  const pre = q.prerequisites ?? {};
  if (typeof pre !== "object" || Array.isArray(pre)) e.push(`${w}: prerequisites invalido`);
  else {
    const pq = pre.quests ?? [];
    if (!Array.isArray(pq) || pq.some((x) => typeof x !== "string" || !ID_RE.test(x)) || new Set(pq).size !== pq.length) e.push(`${w}: prerequisites.quests invalido`);
    const ml = pre.min_level ?? 1;
    if (!isInt(ml) || ml < 1 || ml > MAX_LEVEL) e.push(`${w}: prerequisites.min_level fora de 1..${MAX_LEVEL}`);
  }
  if (!Array.isArray(q.objectives) || q.objectives.length < 1 || q.objectives.length > MAX_OBJECTIVES) e.push(`${w}: objectives deve ter 1..${MAX_OBJECTIVES}`);
  else {
    const seen = new Set();
    for (const o of q.objectives) {
      const ow = `${w} objetivo '${o?.id}'`;
      if (typeof o?.id !== "string" || !ID_RE.test(o.id)) e.push(`${ow}: id invalido`);
      else if (seen.has(o.id)) e.push(`${ow}: id duplicado`);
      else seen.add(o.id);
      if (!OBJ_TYPES.includes(o?.type)) e.push(`${ow}: type invalido`);
      if (typeof o?.target !== "string" || !ID_RE.test(o.target)) e.push(`${ow}: target invalido`);
      if (!isInt(o?.required) || o.required < 1 || o.required > MAX_REQUIRED) e.push(`${ow}: required fora de 1..${MAX_REQUIRED}`);
      if ((o?.type === "reach_area" || o?.type === "talk") && o.required !== 1) e.push(`${ow}: ${o.type} exige required = 1`);
      if (typeof o?.text !== "string" || !o.text || typeof o?.text_key !== "string" || !o.text_key) e.push(`${ow}: text/text_key ausentes`);
    }
  }
  const rw = q.rewards;
  if (typeof rw !== "object" || rw === null) e.push(`${w}: rewards invalido`);
  else {
    const xp = rw.xp ?? 0;
    if (!isInt(xp) || xp < 0 || xp > MAX_XP) e.push(`${w}: rewards.xp fora de 0..${MAX_XP}`);
    const items = rw.items ?? [];
    if (!Array.isArray(items) || items.length > MAX_REWARD_ITEMS) e.push(`${w}: rewards.items invalido`);
    else {
      const ids = new Set();
      for (const it of items) {
        if (typeof it?.item_id !== "string" || !ID_RE.test(it.item_id) || !isInt(it?.qty) || it.qty < 1 || it.qty > MAX_QTY) e.push(`${w}: item de recompensa invalido`);
        else if (ids.has(it.item_id)) e.push(`${w}: item de recompensa repetido`);
        else ids.add(it.item_id);
      }
    }
    if (xp === 0 && items.length === 0) e.push(`${w}: recompensa vazia`);
  }
  return e;
}

/** Le data/**, valida tudo e devolve {catalog, errors}. */
export function buildQuestCatalog(root = ROOT) {
  const errors = [];
  const qdir = join(root, "data", "quests");
  const quests = [];
  for (const f of jsonFiles(qdir)) {
    let q;
    try { q = readJson(join(qdir, f)); } catch (err) { errors.push(`${f}: JSON invalido`); continue; }
    errors.push(...validateQuest(q, f));
    if (typeof q?.id === "string" && f !== `${q.id}.json`) errors.push(`${f}: nome do arquivo difere do id`);
    quests.push(q);
  }
  const ids = new Set();
  for (const q of quests) { if (ids.has(q.id)) errors.push(`id duplicado: ${q.id}`); ids.add(q.id); }

  const itemsPath = join(root, "shared", "content_schemas", "items.json");
  const items = new Set(existsSync(itemsPath) ? readJson(itemsPath).items.map((i) => i.id) : []);
  const npcs = new Set(jsonFiles(join(root, "data", "npcs")).map((f) => readJson(join(root, "data", "npcs", f)).id));
  const areas = new Set();
  for (const f of jsonFiles(join(root, "data", "areas"))) for (const a of readJson(join(root, "data", "areas", f)).areas ?? []) areas.add(a.id);
  const pendingPath = join(qdir, "_pending_refs.json");
  const pending = existsSync(pendingPath) ? readJson(pendingPath) : {};
  const enemies = new Set([...enemyIds(root), ...(pending.enemies ?? [])]);
  const pendingItems = new Set(pending.items ?? []);

  for (const q of quests) {
    if (typeof q?.id !== "string") continue;
    const w = `quest '${q.id}'`;
    if (npcs.size > 0) for (const k of ["giver_npc", "turn_in_npc"]) if (!npcs.has(q[k])) errors.push(`${w}: ${k} '${q[k]}' inexistente`);
    for (const p of q.prerequisites?.quests ?? []) if (!ids.has(p) || p === q.id) errors.push(`${w}: prerequisito '${p}' invalido`);
    for (const o of q.objectives ?? []) {
      if (o.type === "kill" && enemies.size > 0 && !enemies.has(o.target)) errors.push(`${w}: inimigo '${o.target}' inexistente e nao pendente`);
      if (o.type === "collect" && items.size > 0 && !items.has(o.target) && !pendingItems.has(o.target)) errors.push(`${w}: item '${o.target}' inexistente`);
      if (o.type === "reach_area" && areas.size > 0 && !areas.has(o.target)) errors.push(`${w}: area '${o.target}' inexistente`);
      if (o.type === "talk" && npcs.size > 0 && !npcs.has(o.target)) errors.push(`${w}: npc '${o.target}' inexistente`);
    }
    for (const it of q.rewards?.items ?? []) if (items.size > 0 && !items.has(it.item_id)) errors.push(`${w}: item de recompensa '${it.item_id}' inexistente no catalogo de itens (backend o recusaria)`);
  }
  // ciclos de prerequisitos
  const byId = new Map(quests.map((q) => [q.id, q]));
  for (const q of quests) {
    const seen = new Set(); const stack = [...(q.prerequisites?.quests ?? [])];
    while (stack.length) {
      const c = stack.pop();
      if (c === q.id) { errors.push(`quest '${q.id}': ciclo de prerequisitos`); break; }
      if (seen.has(c)) continue;
      seen.add(c);
      stack.push(...(byId.get(c)?.prerequisites?.quests ?? []));
    }
  }
  const out = quests
    .filter((q) => typeof q?.id === "string")
    .sort((a, b) => (a.id < b.id ? -1 : 1))
    .map((q) => ({
      id: q.id,
      prerequisites: { quests: [...(q.prerequisites?.quests ?? [])].sort(), min_level: q.prerequisites?.min_level ?? 1 },
      objectives: q.objectives.map((o) => ({ id: o.id, type: o.type, target: o.target, required: o.required })),
      rewards: {
        xp: q.rewards.xp ?? 0,
        items: [...(q.rewards.items ?? [])].map((i) => ({ item_id: i.item_id, qty: i.qty })).sort((a, b) => (a.item_id < b.item_id ? -1 : 1)),
      },
    }));
  return { catalog: { schema_version: 1, source: "data/quests/*.json (gerado por tools/gen_quests_catalog.mjs)", quests: out }, errors };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { catalog, errors } = buildQuestCatalog();
  if (errors.length) {
    console.error("quests invalidas:\n - " + errors.join("\n - "));
    process.exit(1);
  }
  const text = JSON.stringify(catalog, null, 2) + "\n";
  if (process.argv.includes("--check")) {
    const cur = existsSync(OUT) ? readFileSync(OUT, "utf8") : "";
    if (cur !== text) {
      console.error("shared/content_schemas/quests.json desatualizado: rode node tools/gen_quests_catalog.mjs");
      process.exit(1);
    }
    console.log("quests.json em dia");
  } else {
    writeFileSync(OUT, text);
    console.log(`escrito ${OUT}`);
  }
}
