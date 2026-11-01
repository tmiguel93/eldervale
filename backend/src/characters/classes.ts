import { readFileSync } from "node:fs";
import type { Stats } from "./model.ts";

/** Slots de habilidade da classe (mesmos de data/classes/*.json e do protocolo: attack, skill_1, skill_2, dodge). */
export const CLASS_SLOTS = ["attack", "skill_1", "skill_2", "dodge"] as const;
export type ClassSlot = (typeof CLASS_SLOTS)[number];
export const RESOURCE_KINDS = ["stamina", "mana"] as const;
export const DEFAULT_CLASS_ID = "warrior";

export interface ClassSpec {
  id: string;
  planned: boolean;
}
export interface ClassDef {
  id: string;
  resource_kind: (typeof RESOURCE_KINDS)[number];
  /** Stats base na CRIACAO do personagem (gravados em characters.stats). */
  base_stats: Readonly<Stats>;
  skills: Readonly<Record<ClassSlot, string>>;
  specializations: readonly ClassSpec[];
}

export interface ClassCatalog {
  get(id: string): ClassDef | undefined;
  has(id: string): boolean;
  ids(): string[];
  defaultId: string;
}

const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const STAT_KEYS = ["max_health", "max_resource", "resource_regen", "attack_power", "defense", "resistance", "move_speed"] as const;

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/**
 * Valida o JSON do catalogo (gerado por tools/gen_classes_catalog.mjs a partir de data/classes/*.json) e devolve um
 * catalogo imutavel. Lanca Error em qualquer inconsistencia (falha na inicializacao, nunca em runtime de request).
 * Limites dos stats = os de validateState (resistance <= 0.75, move_speed <= 100, demais <= 100000).
 */
export function createClassCatalog(raw: unknown): ClassCatalog {
  if (!isObj(raw)) throw new Error("classes: raiz invalida");
  if (raw.schema_version !== 1) throw new Error("classes: schema_version nao suportada");
  if (!Array.isArray(raw.classes) || raw.classes.length === 0) throw new Error("classes: lista vazia");
  const map = new Map<string, ClassDef>();
  for (const c of raw.classes as unknown[]) {
    if (!isObj(c)) throw new Error("classes: entrada invalida");
    const id = c.id;
    if (typeof id !== "string" || !ID_RE.test(id)) throw new Error(`classes: id invalido ${String(id)}`);
    if (map.has(id)) throw new Error(`classes: id duplicado ${id}`);
    if (typeof c.resource_kind !== "string" || !(RESOURCE_KINDS as readonly string[]).includes(c.resource_kind)) throw new Error(`classes: resource_kind invalido em ${id}`);
    if (!isObj(c.base_stats)) throw new Error(`classes: base_stats invalido em ${id}`);
    const stats = {} as Stats;
    for (const k of STAT_KEYS) {
      const v = c.base_stats[k];
      const max = k === "resistance" ? 0.75 : k === "move_speed" ? 100 : 100_000;
      if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > max) throw new Error(`classes: base_stats.${k} invalido em ${id}`);
      stats[k] = v;
    }
    for (const k of Object.keys(c.base_stats)) if (!(STAT_KEYS as readonly string[]).includes(k)) throw new Error(`classes: base_stats.${k} desconhecido em ${id}`);
    if (!(stats.max_health > 0 && stats.max_resource > 0 && stats.attack_power > 0 && stats.move_speed > 0)) throw new Error(`classes: base_stats de ${id} deve ser > 0`);
    if (!isObj(c.skills)) throw new Error(`classes: skills invalido em ${id}`);
    const skills = {} as Record<ClassSlot, string>;
    const seen = new Set<string>();
    for (const s of CLASS_SLOTS) {
      const sid = c.skills[s];
      if (typeof sid !== "string" || !ID_RE.test(sid) || seen.has(sid)) throw new Error(`classes: skills.${s} invalido em ${id}`);
      seen.add(sid);
      skills[s] = sid;
    }
    if (!Array.isArray(c.specializations) || c.specializations.length === 0) throw new Error(`classes: specializations vazio em ${id}`);
    const specs: ClassSpec[] = [];
    for (const sp of c.specializations as unknown[]) {
      if (!isObj(sp) || typeof sp.id !== "string" || !ID_RE.test(sp.id) || typeof sp.planned !== "boolean") throw new Error(`classes: especializacao invalida em ${id}`);
      if (specs.some((x) => x.id === sp.id)) throw new Error(`classes: especializacao duplicada ${sp.id} em ${id}`);
      specs.push(Object.freeze({ id: sp.id, planned: sp.planned }));
    }
    if (!specs.some((s) => !s.planned)) throw new Error(`classes: ${id} sem especializacao inicial`);
    map.set(id, Object.freeze({ id, resource_kind: c.resource_kind as ClassDef["resource_kind"], base_stats: Object.freeze(stats), skills: Object.freeze(skills), specializations: Object.freeze(specs) }));
  }
  const defaultId = typeof raw.default_class === "string" ? raw.default_class : DEFAULT_CLASS_ID;
  if (!map.has(defaultId)) throw new Error(`classes: classe padrao '${defaultId}' ausente`);
  return { get: (id) => map.get(id), has: (id) => map.has(id), ids: () => [...map.keys()], defaultId };
}

export const CLASSES_JSON_URL = new URL("../../../shared/content_schemas/classes.json", import.meta.url);

/** Le shared/content_schemas/classes.json (relativo a este arquivo). */
export function loadClassCatalogFromDisk(url: URL = CLASSES_JSON_URL): ClassCatalog {
  return createClassCatalog(JSON.parse(readFileSync(url, "utf8")));
}
