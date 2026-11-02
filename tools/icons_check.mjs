// E8.4 - Validador do mapeamento de icones da UI (data/ui/icons.json, game-icons.net CC BY 3.0) e dos creditos (data/ui/credits.json).
// Confere: formato "autor/nome", arquivo existente (quando assets/ esta presente), COBERTURA (toda habilidade, item, classe, tipo de
// item, slot de equipamento, atributo e recurso tem icone) e que os avisos de atribuicao apontam para pacotes reais do ASSET_MANIFEST.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const rj = (p) => JSON.parse(readFileSync(p, "utf8"));
const REF_RE = /^[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*$/;
const SECTIONS = ["skills", "items", "item_types", "equip_slots", "attributes", "classes", "resources", "enemies", "ui", "talent_tiers"];
const ITEM_TYPES = ["weapon", "armor", "trinket", "consumable", "material", "misc"];
const EQUIP_SLOTS = ["weapon", "armor", "trinket"];
const ATTRIBUTES = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"];
const RESOURCES = ["stamina", "mana", "xp", "health"];
const UI_KEYS = ["quests", "inventory", "map", "talents", "craft", "dialogue", "options", "credits", "menu", "boss_left", "boss_right", "death", "loading_rune"];

const ids = (dir, ext) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(ext) && !f.startsWith("_")).map((f) => f.slice(0, -ext.length)).sort() : []);

/** `err(msg)` acumula erros; devolve estatisticas. */
export function checkIcons(root, err) {
  const stats = { icones_referenciados: 0, credito_pacotes: 0 };
  const path = join(root, "data", "ui", "icons.json");
  if (!existsSync(path)) return stats;
  let doc;
  try { doc = rj(path); } catch (e) { err(`ui/icons.json: JSON invalido (${e.message})`); return stats; }
  const iconsDir = join(root, "assets", "third_party", "game_icons");
  const haveFiles = existsSync(iconsDir);
  const used = new Set();
  for (const sec of SECTIONS) {
    if (typeof doc[sec] !== "object" || doc[sec] === null || Array.isArray(doc[sec])) { err(`ui/icons.json: secao '${sec}' ausente ou invalida`); continue; }
    for (const [k, ref] of Object.entries(doc[sec])) {
      if (typeof ref !== "string" || !REF_RE.test(ref)) { err(`ui/icons.json ${sec}.${k}: referencia '${ref}' invalida (use autor/nome)`); continue; }
      used.add(ref);
      if (haveFiles && !existsSync(join(iconsDir, `${ref}.svg`))) err(`ui/icons.json ${sec}.${k}: arquivo assets/third_party/game_icons/${ref}.svg inexistente`);
    }
  }
  stats.icones_referenciados = used.size;
  const need = (sec, list, label) => { for (const id of list) if (!doc[sec]?.[id]) err(`ui/icons.json ${sec}: ${label} '${id}' sem icone`); };
  need("skills", ids(join(root, "data", "skills"), ".tres"), "habilidade");
  need("items", ids(join(root, "data", "items"), ".tres"), "item");
  need("classes", ids(join(root, "data", "classes"), ".json"), "classe");
  need("item_types", ITEM_TYPES, "tipo de item");
  need("equip_slots", EQUIP_SLOTS, "slot de equipamento");
  need("attributes", ATTRIBUTES, "atributo");
  need("resources", RESOURCES, "recurso");
  need("ui", UI_KEYS, "icone de interface");

  // creditos
  const cpath = join(root, "data", "ui", "credits.json");
  if (!existsSync(cpath)) return stats;
  let credits;
  try { credits = rj(cpath); } catch (e) { err(`ui/credits.json: JSON invalido (${e.message})`); return stats; }
  const mpath = join(root, "assets", "ASSET_MANIFEST.json");
  const pkgs = existsSync(mpath) ? (rj(mpath).packages ?? {}) : null;
  for (const [id, n] of Object.entries(credits.notices ?? {})) {
    stats.credito_pacotes++;
    if (typeof n !== "string" || n.length < 20) err(`ui/credits.json notices.${id}: texto de atribuicao vazio`);
    if (pkgs && !pkgs[id]) err(`ui/credits.json notices.${id}: pacote inexistente no ASSET_MANIFEST`);
  }
  if (pkgs) {
    for (const [id, p] of Object.entries(pkgs)) {
      if (/^CC-BY/.test(String(p.license ?? "")) && !credits.notices?.[id]) err(`ui/credits.json: pacote CC BY '${id}' sem aviso de atribuicao`);
    }
  }
  return stats;
}
