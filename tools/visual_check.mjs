// E8.1 - Validacao dos campos visual_* (visual_scene, visual_height, visual_tint, visual_yaw_offset, visual_clips,
// visual_equip, visual_placeholder) de inimigos (.tres), classes e NPCs (.json). Usada por tools/validate_content.mjs.
// Confere: formato da referencia, alias/id no assets/ASSET_MANIFEST.json, arquivo existente em assets/, faixas numericas,
// estados validos em visual_clips e (lendo o JSON do proprio .glb) se os clips e os acessorios citados EXISTEM no modelo.
// Espelha scripts/visual/visual_spec.gd e scripts/visual/clip_table.gd. Documentacao: docs/E8_MODELS.md.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const STATES = ["idle", "move", "attack", "skill", "dodge", "hit", "death", "spawn"];
export const MIN_HEIGHT = 0.1, MAX_HEIGHT = 12, MAX_EQUIP = 16, MAX_NAME = 64;
const ALIAS_RE = /^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$/;
const ASSET_PREFIX = "res://assets/third_party/";
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

const manifests = new Map();
function manifestOf(root) {
  if (manifests.has(root)) return manifests.get(root);
  const p = join(root, "assets", "ASSET_MANIFEST.json");
  let m = null;
  if (existsSync(p)) { try { m = JSON.parse(readFileSync(p, "utf8")); } catch { m = null; } }
  manifests.set(root, m);
  return m;
}

/** alias | id de asset | res://... -> caminho relativo a raiz do projeto (ou null). */
export function resolveRef(ref, root) {
  if (typeof ref !== "string") return null;
  if (ref.startsWith("res://")) return ref.slice("res://".length);
  const m = manifestOf(root);
  if (!m) return null;
  const id = m.aliases?.[ref] ?? ref;
  return m.assets?.[id]?.path ?? null;
}

const glbs = new Map();
/** Le o chunk JSON do .glb: nomes de animacao (sem prefixo `Armature|`, minusculos) e de nos (como o Godot nomeia). */
export function glbInfo(abs) {
  if (glbs.has(abs)) return glbs.get(abs);
  let info = null;
  try {
    const buf = readFileSync(abs);
    if (buf.readUInt32LE(0) === 0x46546c67 && buf.toString("ascii", 16, 20) === "JSON") {
      const len = buf.readUInt32LE(12);
      const j = JSON.parse(buf.toString("utf8", 20, 20 + len));
      const strip = (n) => String(n).slice(String(n).lastIndexOf("|") + 1).toLowerCase();
      info = {
        anims: new Set((j.animations ?? []).map((a) => strip(a.name ?? ""))),
        nodes: new Set((j.nodes ?? []).map((n) => String(n.name ?? "").replace(/[.:/@%" ]/g, "_"))),
      };
    }
  } catch { info = null; }
  glbs.set(abs, info);
  return info;
}

/** v: {scene, height, tint:[r,g,b]|null, yaw, clips:{}, equip:[]}; adiciona mensagens a `err`. */
export function checkVisual(v, where, root, err) {
  const w = `${where}: visual`;
  if (typeof v.scene !== "string" || !(v.scene.startsWith("res://") ? v.scene.startsWith(ASSET_PREFIX) && /\.(glb|gltf)$/.test(v.scene) && !v.scene.includes("..") : ALIAS_RE.test(v.scene))) {
    err(`${w}_scene '${String(v.scene).slice(0, 60)}' invalido (alias, id de asset ou res://assets/third_party/...glb)`);
    return;
  }
  const rel = resolveRef(v.scene, root);
  if (!rel) { err(`${w}_scene '${v.scene}': alias/id inexistente em assets/ASSET_MANIFEST.json`); return; }
  const abs = join(root, rel);
  if (!existsSync(abs)) { err(`${w}_scene '${v.scene}': arquivo '${rel}' nao existe em assets/`); return; }
  if (!isNum(v.height) || v.height < MIN_HEIGHT || v.height > MAX_HEIGHT) err(`${w}_height fora de ${MIN_HEIGHT}..${MAX_HEIGHT}`);
  if (v.tint != null && (!Array.isArray(v.tint) || v.tint.length !== 3 || !v.tint.every((c) => isNum(c) && c >= 0 && c <= 4))) err(`${w}_tint deve ser [r, g, b] em 0..4`);
  if (v.yaw != null && (!isNum(v.yaw) || Math.abs(v.yaw) > 360)) err(`${w}_yaw_offset fora de -360..360`);
  const info = /\.glb$/.test(abs) ? glbInfo(abs) : null;
  for (const [k, c] of Object.entries(v.clips ?? {})) {
    if (!STATES.includes(k)) { err(`${w}_clips: estado desconhecido '${k.slice(0, 24)}'`); continue; }
    if (typeof c !== "string" || c === "" || c.length > MAX_NAME) { err(`${w}_clips.${k}: nome de clip invalido`); continue; }
    if (info && !info.anims.has(c.slice(c.lastIndexOf("|") + 1).toLowerCase())) err(`${w}_clips.${k}: clip '${c}' nao existe em ${rel}`);
  }
  if (!Array.isArray(v.equip ?? [])) { err(`${w}_equip deve ser lista`); return; }
  if ((v.equip ?? []).length > MAX_EQUIP) err(`${w}_equip: no maximo ${MAX_EQUIP} nomes`);
  for (const n of v.equip ?? []) {
    if (typeof n !== "string" || n === "" || n.length > MAX_NAME) err(`${w}_equip: nome invalido`);
    else if (info && !info.nodes.has(n)) err(`${w}_equip: acessorio '${n}' nao existe em ${rel}`);
  }
}

/** Do dicionario de um JSON (classe/NPC). Sem visual_scene: so acusa chaves visual_* orfas. */
export function checkVisualJson(d, where, root, err, keys) {
  if (d?.visual_scene === undefined) {
    for (const k of keys) if (d?.[k] !== undefined) err(`${where}: ${k} sem visual_scene`);
    return;
  }
  const bad = (m) => err(`${where}: ${m}`);
  if (d.visual_height !== undefined && !isNum(d.visual_height)) return bad("visual_height deve ser numero");
  if (d.visual_yaw_offset !== undefined && !isNum(d.visual_yaw_offset)) return bad("visual_yaw_offset deve ser numero (graus)");
  if (d.visual_clips !== undefined && (typeof d.visual_clips !== "object" || d.visual_clips === null || Array.isArray(d.visual_clips))) return bad("visual_clips deve ser objeto");
  if (d.visual_equip !== undefined && !Array.isArray(d.visual_equip)) return bad("visual_equip deve ser lista");
  if (d.visual_placeholder !== undefined && typeof d.visual_placeholder !== "boolean") bad("visual_placeholder deve ser bool");
  checkVisual({ scene: d.visual_scene, height: d.visual_height ?? 1.8, tint: d.visual_tint ?? null, yaw: d.visual_yaw_offset ?? 0, clips: d.visual_clips ?? {}, equip: d.visual_equip ?? [] }, where, root, err);
}

/** Do texto de um inimigo .tres. */
export function checkVisualTres(text, where, root, err) {
  const body = text.slice(Math.max(0, text.lastIndexOf("[resource]")));
  const f = (n) => new RegExp(`^${n}\\s*=\\s*([^\\n]*)$`, "m").exec(body)?.[1];
  const scene = /^"(.*)"$/.exec(f("visual_scene") ?? "")?.[1];
  if (scene === undefined || scene === "") {
    for (const k of ["visual_height", "visual_tint", "visual_yaw_offset", "visual_clips", "visual_equip", "visual_placeholder"]) if (f(k) !== undefined) err(`${where}: ${k} sem visual_scene`);
    return;
  }
  const tintM = /^Color\(\s*([-\d.eE]+),\s*([-\d.eE]+),\s*([-\d.eE]+),\s*([-\d.eE]+)\s*\)$/.exec(f("visual_tint") ?? "");
  const clipsRaw = /^visual_clips\s*=\s*\{([^}]*)\}/m.exec(body)?.[1] ?? "";
  const clips = {};
  for (const m of clipsRaw.matchAll(/"([^"]*)"\s*:\s*"([^"]*)"/g)) clips[m[1]] = m[2];
  const equipRaw = /^visual_equip\s*=\s*PackedStringArray\(([^)]*)\)/m.exec(body)?.[1] ?? "";
  const equip = [...equipRaw.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
  checkVisual({
    scene, height: Number(f("visual_height") ?? "1.8"),
    tint: tintM && Number(tintM[4]) > 0 ? [Number(tintM[1]), Number(tintM[2]), Number(tintM[3])] : null,
    yaw: Number(f("visual_yaw_offset") ?? "0"), clips, equip,
  }, where, root, err);
}
