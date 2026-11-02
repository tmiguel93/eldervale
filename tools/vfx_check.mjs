// E8.3 - Validador do catalogo de VFX (data/vfx). Mesmo esquema do Godot (data/vfx/_layer_schema.json).
// Confere: tipos de camada e campos (faixas), sprites/blends, referencias de bindings -> efeitos, habilidades existentes em data/skills
// e COBERTURA: toda habilidade de data/skills tem binding; todo tipo de ataque de inimigo tem efeito.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const rj = (p) => JSON.parse(readFileSync(p, "utf8"));
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const ENEMY_KINDS = ["melee", "aoe", "projectile", "charge", "summon"];

function checkField(spec, v, where, err) {
  const t = spec.t;
  if (t === "num" || t === "int") {
    if (typeof v !== "number" || !Number.isFinite(v)) return err(`${where}: esperado numero`);
    if (t === "int" && !Number.isInteger(v)) err(`${where}: esperado inteiro`);
    if (spec.min !== undefined && v < spec.min) err(`${where}: ${v} < min ${spec.min}`);
    if (spec.max !== undefined && v > spec.max) err(`${where}: ${v} > max ${spec.max}`);
  } else if (t === "bool") { if (typeof v !== "boolean") err(`${where}: esperado bool`); }
  else if (t === "str") { if (typeof v !== "string") err(`${where}: esperado texto`); }
  else if (t === "enum") { if (!spec.values.includes(v)) err(`${where}: '${v}' fora de ${spec.values.join("|")}`); }
  else if (t === "color") { if (!Array.isArray(v) || (v.length !== 3 && v.length !== 4) || v.some((c) => typeof c !== "number" || c < 0 || c > 8)) err(`${where}: cor invalida`); }
  else if (t === "vec3") { if (!Array.isArray(v) || v.length !== 3 || v.some((c) => typeof c !== "number")) err(`${where}: vec3 invalido`); }
  else if (t === "range") { if (!Array.isArray(v) || v.length !== 2 || v.some((c) => typeof c !== "number") || v[0] > v[1]) err(`${where}: faixa invalida`); }
}

/** Retorna {errors, stats}. `skillIds` = ids em data/skills (para cobertura). */
export function checkVfx(root, err) {
  const dir = join(root, "data", "vfx");
  const stats = { efeitos: 0, camadas: 0, habilidades_ligadas: 0 };
  if (!existsSync(dir)) return stats;
  let schema, bind;
  try { schema = rj(join(dir, "_layer_schema.json")); bind = rj(join(dir, "bindings.json")); } catch (e) { err(`vfx: JSON invalido (${e.message})`); return stats; }
  const effects = new Map();
  for (const f of readdirSync(dir).filter((x) => /^effects_.*\.json$/.test(x)).sort()) {
    let doc; try { doc = rj(join(dir, f)); } catch (e) { err(`vfx/${f}: JSON invalido`); continue; }
    for (const [id, e] of Object.entries(doc.effects ?? doc)) {
      if (id.startsWith("_")) continue;
      if (!ID_RE.test(id)) err(`vfx/${f}: id '${id}' invalido`);
      if (effects.has(id)) err(`vfx: efeito duplicado '${id}'`);
      effects.set(id, e);
      for (const [k, v] of Object.entries(e)) { if (k === "layers") continue; const s = schema.effect_keys[k]; if (!s) err(`vfx '${id}': chave '${k}' desconhecida`); else checkField(s, v, `vfx '${id}'.${k}`, err); }
      if (!Array.isArray(e.layers) || e.layers.length === 0) { err(`vfx '${id}': sem camadas`); continue; }
      e.layers.forEach((l, i) => {
        const w = `vfx '${id}'[${i}]`; stats.camadas++;
        const spec = schema.layer_types[l.type];
        if (!spec) return err(`${w}: tipo '${l.type}' desconhecido`);
        for (const [k, v] of Object.entries(l)) {
          if (k === "type") continue;
          if (k === "sprite") { if (!schema.sprites.includes(v)) err(`${w}: sprite '${v}' desconhecido`); continue; }
          if (k === "blend") { if (!schema.blends.includes(v)) err(`${w}: blend '${v}' invalido`); continue; }
          const s = spec[k] ?? schema.common[k]; if (!s) err(`${w}: campo '${k}' desconhecido para ${l.type}`); else checkField(s, v, `${w}.${k}`, err);
        }
        for (const [k, s] of Object.entries({ ...schema.common, ...spec })) if (s.req && l[k] === undefined) err(`${w}: campo obrigatorio '${k}'`);
      });
    }
  }
  stats.efeitos = effects.size;
  const need = (ref, where) => { if (ref && !effects.has(ref)) err(`vfx bindings ${where}: efeito '${ref}' inexistente`); };
  const skillsDir = join(root, "data", "skills");
  const skillIds = existsSync(skillsDir) ? readdirSync(skillsDir).filter((f) => f.endsWith(".tres")).map((f) => f.slice(0, -5)) : [];
  for (const [sid, b] of Object.entries(bind.skills ?? {})) {
    if (skillIds.length && !skillIds.includes(sid)) err(`vfx bindings: habilidade '${sid}' nao existe em data/skills`);
    for (const f of ["cast", "muzzle", "projectile", "impact", "end", "extra"]) need(b[f], `skills.${sid}.${f}`);
  }
  for (const sid of skillIds) { if (!bind.skills?.[sid]) err(`vfx bindings: habilidade '${sid}' sem binding (cobertura)`); else stats.habilidades_ligadas++; }
  const ea = bind.enemy_attacks ?? {};
  for (const k of ENEMY_KINDS) if (!ea.kinds?.[k]) err(`vfx bindings: tipo de ataque '${k}' sem efeitos`);
  for (const grp of ["kinds", "overrides"]) for (const [k, b] of Object.entries(ea[grp] ?? {})) for (const f of ["windup", "strike", "projectile", "impact", "end"]) need(b[f], `enemy_attacks.${grp}.${k}.${f}`);
  for (const [k, v] of Object.entries(bind.events ?? {})) need(v, `events.${k}`);
  for (const [k, v] of Object.entries(bind.drops ?? {})) need(v, `drops.${k}`);
  return stats;
}
