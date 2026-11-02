import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { afterAll, describe, expect, it, vi } from "vitest";

vi.setConfig({ testTimeout: 120_000 });
import { BACKEND_ROOT } from "../src/persistence/paths.ts";

// E6.4: validador de conteudo (tools/validate_content.mjs). Conteudo REAL = sem erros; conteudo CORROMPIDO sintetico (copia em
// backend/.data/test-tmp, ignorada pelo Git) = cada defeito detectado, com a mensagem certa.
const REPO = fileURLToPath(new URL("../..", import.meta.url));
const TOOL = join(REPO, "tools", "validate_content.mjs");
const mod: any = await import(pathToFileURL(TOOL).href);
const TMP_ROOT = join(BACKEND_ROOT, ".data", "test-tmp");
mkdirSync(TMP_ROOT, { recursive: true });
const made: string[] = [];
afterAll(() => { for (const d of made) { try { rmSync(d, { recursive: true, force: true }); } catch { /* rm pode ser bloqueado no ambiente */ } } });

/** Copia UMA vez data/ + shared/content_schemas para uma pasta temporaria; cada mutacao e desfeita ao final (copiar e lento no disco do projeto). */
let SHARED_ROOT = "";
function clone(): string {
  if (SHARED_ROOT) return SHARED_ROOT;
  const root = mkdtempSync(join(TMP_ROOT, "cv-"));
  made.push(root);
  cpSync(join(REPO, "data"), join(root, "data"), { recursive: true });
  cpSync(join(REPO, "shared", "content_schemas"), join(root, "shared", "content_schemas"), { recursive: true });
  SHARED_ROOT = root;
  return root;
}
const originals = new Map<string, string>();
const editText = (root: string, rel: string, fn: (t: string) => string) => {
  const p = join(root, rel);
  const before = readFileSync(p, "utf8");
  if (!originals.has(p)) originals.set(p, before);
  const after = fn(before);
  expect(after, `mutacao sem efeito em ${rel}`).not.toBe(before);
  writeFileSync(p, after);
};
const editJson = (root: string, rel: string, fn: (d: any) => void) => editText(root, rel, (t) => { const d = JSON.parse(t); fn(d); return JSON.stringify(d, null, 2) + "\n"; });
/** Aplica a mutacao, valida e DESFAZ; devolve os erros do validador. */
function errorsAfter(mutate: (root: string) => void, opts: { noGenerated?: boolean } = { noGenerated: true }): string[] {
  const root = clone();
  try {
    mutate(root);
    return mod.validateContent(root, opts).errors as string[];
  } finally {
    for (const [p, txt] of originals) writeFileSync(p, txt);
    originals.clear();
  }
}
const has = (errs: string[], re: RegExp) => errs.some((e) => re.test(e));

describe("validate_content: conteudo real", () => {
  // (a copia compartilhada leva alguns segundos no disco do projeto)
  it("nao tem erros, cobre quests/exploracao e os catalogos gerados estao em dia", () => {
    const r = mod.validateContent(REPO);
    expect(r.errors).toEqual([]);
    expect(r.stats.quests).toBeGreaterThanOrEqual(10);
    expect(r.stats.quests).toBeLessThanOrEqual(15);
    expect(r.stats.quests_alcancaveis).toBe(r.stats.quests);
    expect(r.stats.pontos_de_exploracao).toBeGreaterThanOrEqual(6);
    for (const k of ["itens", "tabelas_de_loot", "inimigos", "classes", "talentos", "receitas", "npcs", "dialogos", "zonas", "areas"]) expect(r.stats[k]).toBeGreaterThan(0);
  });
  it("CLI: saida 0 no conteudo real, 1 em conteudo corrompido, 2 em uso invalido", () => {
    const ok = spawnSync(process.execPath, [TOOL], { cwd: REPO, encoding: "utf8" });
    expect(ok.status).toBe(0);
    expect(ok.stdout).toMatch(/RESULTADO: OK/);
    const root = clone();
    editJson(root, "data/quests/gw_welcome.json", (q) => { q.giver_npc = "npc_fantasma"; });
    const bad = spawnSync(process.execPath, [TOOL, "--root", root, "--no-generated"], { cwd: REPO, encoding: "utf8" });
    for (const [p, txt] of originals) writeFileSync(p, txt);
    originals.clear();
    expect(bad.status).toBe(1);
    expect(bad.stdout).toMatch(/npc_fantasma/);
    expect(bad.stdout).toMatch(/RESULTADO: FALHOU/);
    const usage = spawnSync(process.execPath, [TOOL, "--root", join(root, "nao_existe")], { cwd: REPO, encoding: "utf8" });
    expect(usage.status).toBe(2);
    const js = spawnSync(process.execPath, [TOOL, "--json"], { cwd: REPO, encoding: "utf8" });
    expect(JSON.parse(js.stdout).ok).toBe(true);
  });
});

describe("validate_content: conteudo corrompido e detectado", () => {
  it("quest -> NPC, item de recompensa, item coletado, inimigo, area, ponto e dialogo inexistentes", () => {
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.turn_in_npc = "npc_fantasma"; })), /turn_in_npc.*npc_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.rewards.items[0].item_id = "item_fantasma"; })), /item_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_scrap_for_orla.json", (q) => { q.objectives[0].target = "item_fantasma"; })), /item 'item_fantasma' inexistente/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_clear_clearing.json", (q) => { q.objectives[0].target = "inimigo_fantasma"; })), /inimigo 'inimigo_fantasma'/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_ruins_expedition.json", (q) => { q.objectives[0].target = "area_fantasma"; })), /area 'area_fantasma'/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_wild_survey.json", (q) => { q.objectives[0].target = "poi_fantasma"; })), /poi_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_bench_lessons.json", (q) => { q.objectives[0].target = "item_fantasma"; })), /item_fantasma/)).toBe(true);
  });
  it("ciclo de pre-requisitos e pre-requisito inexistente", () => {
    const cyc = errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.prerequisites.quests = ["gw_rootsong"]; }));
    expect(has(cyc, /ciclo de prerequisitos/)).toBe(true);
    expect(has(cyc, /inalcancavel/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_whispers.json", (q) => { q.prerequisites.quests = ["quest_fantasma"]; })), /quest_fantasma/)).toBe(true);
  });
  it("quest inalcancavel: nivel, objetivo sem fonte, NPC fora do mundo, dialogo que nao oferece", () => {
    const lv = errorsAfter((r) => editJson(r, "data/quests/gw_rootsong.json", (q) => { q.prerequisites.min_level = 99; }));
    expect(has(lv, /gw_rootsong/)).toBe(true);
    const nospawn = errorsAfter((r) => editJson(r, "data/quests/gw_clear_clearing.json", (q) => { q.objectives[0].target = "root_sprout"; }));
    expect(has(nospawn, /quest 'gw_clear_clearing' inalcancavel.*root_sprout.*nao nasce/)).toBe(true);
    expect(has(nospawn, /quest 'gw_thorn_hunt' inalcancavel.*pre-requisito 'gw_clear_clearing'/)).toBe(true); // propaga pela cadeia
    const nonpc = errorsAfter((r) => editJson(r, "data/areas/world/greenwood_world.json", (w) => { w.zones[0].npcs = w.zones[0].npcs.filter((n: string) => n !== "npc_mapper_pell"); }));
    expect(has(nonpc, /npc_mapper_pell.*nenhuma zona/)).toBe(true);
    expect(has(nonpc, /gw_wild_survey' inalcancavel/)).toBe(true);
    const nooffer = errorsAfter((r) => editJson(r, "data/dialogues/dlg_mapper_pell.json", (d) => { for (const n of Object.values<any>(d.nodes)) for (const c of n.choices ?? []) c.effects = (c.effects ?? []).filter((e: any) => e.quest_id !== "gw_wild_survey"); }));
    expect(has(nooffer, /gw_wild_survey' inalcancavel.*nao oferece|nao entrega/)).toBe(true);
    const iso = errorsAfter((r) => editJson(r, "data/areas/world/greenwood_world.json", (w) => { w.zones[0].portals = []; }));
    expect(has(iso, /zona 'zone_wild': inalcancavel/)).toBe(true);
    expect(has(iso, /quest 'gw_wild_survey' inalcancavel/)).toBe(true);
  });
  it("ids duplicados, nome de arquivo != id, id fora do padrao e campos obrigatorios/faixas", () => {
    const dup = errorsAfter((r) => editJson(r, "data/quests/gw_whispers.json", (q) => { q.id = "gw_welcome"; }));
    expect(has(dup, /nome do arquivo difere do id/)).toBe(true);
    expect(has(dup, /id duplicado/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { delete q.title; })), /title/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.rewards.xp = 99999999; })), /rewards\.xp/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.rewards = { xp: 0, items: [] }; })), /recompensa vazia/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.objectives[0].type = "pvp_duel"; })), /type invalido/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.objectives[0].required = 0; })), /required/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/quests/gw_wild_survey.json", (q) => { q.objectives[0].required = 3; })), /discover exige required = 1/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/npcs/npc_elder_orla.json", (n) => { n.interact_radius = 0; })), /interact_radius/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/npcs/npc_smith_dorran.json", (n) => { n.id = "Mau-Id"; })), /Mau-Id/)).toBe(true);
  });
  it("loot -> item, inimigo -> loot, receita -> item/estacao, talento -> habilidade, unico -> loot/modificador", () => {
    expect(has(errorsAfter((r) => editText(r, "data/loot/loot_melee_grunt.tres", (t) => t.replace(/item_id = &"potion_minor"/, 'item_id = &"item_fantasma"'))), /loot 'loot_melee_grunt': item 'item_fantasma'/)).toBe(true);
    expect(has(errorsAfter((r) => editText(r, "data/loot/loot_melee_grunt.tres", (t) => t.replace(/weight = [\d.]+/, "weight = 0.0"))), /peso/)).toBe(true);
    expect(has(errorsAfter((r) => editText(r, "data/enemies/melee_grunt.tres", (t) => t.replace("loot_melee_grunt.tres", "loot_sumiu.tres"))), /inimigo 'melee_grunt': tabela de loot/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/recipes/rcp_potion_minor.json", (x) => { x.results[0].item_id = "item_fantasma"; })), /item_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/recipes/rcp_potion_minor.json", (x) => { x.station = "station_fantasma"; })), /station_fantasma/)).toBe(true);
    const tal = errorsAfter((r) => editJson(r, "data/talents/mage.json", (t) => { const n = t.nodes.find((x: any) => x.effects.some((e: any) => e.type === "skill_mod")); n.effects.find((e: any) => e.type === "skill_mod").skill = "skill_fantasma"; }));
    expect(has(tal, /skill_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/items/_uniques.json", (u) => { u.uniques[0].obtain.sources[0].loot_table = "loot_fantasma"; })), /loot_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/items/_uniques.json", (u) => { u.uniques[0].effects[0].mod = "mod_fantasma"; })), /mod/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/classes/mage.json", (c) => { c.skills.skill_1 = "skill_fantasma"; })), /skill_fantasma/)).toBe(true);
  });
  it("dialogos: quest, no e NPC inexistentes; ultima entrada precisa ser fallback", () => {
    expect(has(errorsAfter((r) => editJson(r, "data/dialogues/dlg_elder_orla.json", (d) => { d.entries[0].if.quest = "quest_fantasma"; })), /quest inexistente 'quest_fantasma'/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/dialogues/dlg_elder_orla.json", (d) => { d.nodes.welcome_offer.choices[0].next = "no_fantasma"; })), /no inexistente 'no_fantasma'/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/dialogues/dlg_elder_orla.json", (d) => { d.npc_id = "npc_fantasma"; })), /npc_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/dialogues/dlg_elder_orla.json", (d) => { d.entries.pop(); })), /fallback/)).toBe(true);
  });
  it("mundo, areas e exploracao: referencias e geometria", () => {
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[1].center = [9000, 0, 9000]; })), /fora da zona/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[1].zone = "zone_fantasma"; })), /zone_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[1].id = d.points[0].id; })), /duplicado/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[0].rewards = { xp: 0, items: [] }; })), /recompensa vazia/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[0].rewards.items = [{ item_id: "item_fantasma", qty: 1 }]; })), /item_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[3].requires_quests = ["quest_fantasma"]; })), /quest_fantasma|requires_quests/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/areas/greenwood.json", (a) => { a.areas[0].center = [9000, 0, 9000]; })), /fora de qualquer zona/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/areas/world/greenwood_world.json", (w) => { w.zones[1].enemies[0].type = "inimigo_fantasma"; })), /inimigo_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/areas/world/greenwood_world.json", (w) => { w.zones[0].portals[0].to_spawn = "spawn_fantasma"; })), /spawn_fantasma/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/areas/world/greenwood_world.json", (w) => { w.zones[0].npcs.push("npc_fantasma"); })), /npc_fantasma/)).toBe(true);
  });
  it("E8.4 icones e creditos: formato, cobertura e aviso de atribuicao (CC BY)", () => {
    expect(has(errorsAfter((r) => editJson(r, "data/ui/icons.json", (d) => { d.skills.fireball = "Lorc/Fogo Grande"; })), /fireball: referencia/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/ui/icons.json", (d) => { delete d.items.potion_minor; })), /item 'potion_minor' sem icone/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/ui/icons.json", (d) => { delete d.skills.dodge; })), /habilidade 'dodge' sem icone/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/ui/icons.json", (d) => { delete d.item_types.weapon; })), /tipo de item 'weapon' sem icone/)).toBe(true);
    expect(has(errorsAfter((r) => editJson(r, "data/ui/icons.json", (d) => { delete d.attributes; })), /secao 'attributes'/)).toBe(true);
  });
  it("catalogo gerado desatualizado e detectado (sem --no-generated)", () => {
    const errs = errorsAfter((r) => editJson(r, "data/quests/gw_welcome.json", (q) => { q.rewards.xp = 61; }), {});
    expect(has(errs, /quests\.json: desatualizado/)).toBe(true);
    const errs2 = errorsAfter((r) => editJson(r, "data/exploration/greenwood_exploration.json", (d) => { d.points[0].rewards.xp = 26; }), {});
    expect(has(errs2, /exploration\.json: desatualizado/)).toBe(true);
    expect(existsSync(join(REPO, "tools", "validate_content.mjs"))).toBe(true);
  });
});
