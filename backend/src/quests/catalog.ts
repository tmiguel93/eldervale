import { existsSync, readFileSync } from "node:fs";
import type { Catalog } from "../characters/catalog.ts";

export interface QuestObjectiveDef {
  id: string;
  type: string;
  target: string;
  required: number;
}
export interface QuestDefLite {
  id: string;
  prerequisites: { quests: string[]; min_level: number };
  objectives: QuestObjectiveDef[];
  rewards: { xp: number; items: { item_id: string; qty: number }[] };
}
/** E6.4: ponto de exploracao (marco/bau/segredo). A descoberta e unica por personagem; a recompensa e a do catalogo. */
export interface PoiDefLite {
  id: string;
  zone: string;
  min_level: number;
  requires_quests: string[];
  rewards: { xp: number; items: { item_id: string; qty: number }[] };
}
export interface QuestCatalog {
  get(id: string): QuestDefLite | undefined;
  has(id: string): boolean;
  ids(): string[];
  /** E6.4: pontos de exploracao (vazio quando o catalogo foi criado sem exploration.json). */
  poi(id: string): PoiDefLite | undefined;
  hasPoi(id: string): boolean;
  poiIds(): string[];
}

const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const OBJ_TYPES = new Set(["kill", "collect", "reach_area", "talk", "craft", "discover"]);
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);

export const EMPTY_QUESTS: QuestCatalog = Object.freeze({ get: () => undefined, has: () => false, ids: () => [], poi: () => undefined, hasPoi: () => false, poiIds: () => [] });

/**
 * Valida shared/content_schemas/quests.json (gerado por tools/gen_quests_catalog.mjs) e cruza com o
 * catalogo de itens. Lanca Error em qualquer inconsistencia (falha na inicializacao).
 */
export function createQuestCatalog(raw: unknown, items: Catalog, explorationRaw?: unknown): QuestCatalog {
  if (typeof raw !== "object" || raw === null) throw new Error("quests: raiz invalida");
  const obj = raw as { schema_version?: unknown; quests?: unknown };
  if (obj.schema_version !== 1) throw new Error("quests: schema_version nao suportada");
  if (!Array.isArray(obj.quests)) throw new Error("quests: lista invalida");
  const map = new Map<string, QuestDefLite>();
  for (const q of obj.quests as unknown[]) {
    if (typeof q !== "object" || q === null) throw new Error("quests: entrada invalida");
    const r = q as Record<string, any>;
    const id = r.id;
    if (typeof id !== "string" || !ID_RE.test(id)) throw new Error(`quests: id invalido ${String(id)}`);
    if (map.has(id)) throw new Error(`quests: id duplicado ${id}`);
    const pq = r.prerequisites?.quests ?? [];
    const ml = r.prerequisites?.min_level ?? 1;
    if (!Array.isArray(pq) || !pq.every((x: unknown) => typeof x === "string" && ID_RE.test(x))) throw new Error(`quests: prerequisitos invalidos em ${id}`);
    if (!isInt(ml) || ml < 1) throw new Error(`quests: min_level invalido em ${id}`);
    if (!Array.isArray(r.objectives) || r.objectives.length === 0) throw new Error(`quests: ${id} sem objetivos`);
    const seen = new Set<string>();
    const objectives: QuestObjectiveDef[] = r.objectives.map((o: any) => {
      if (typeof o?.id !== "string" || !ID_RE.test(o.id) || seen.has(o.id)) throw new Error(`quests: objetivo invalido/duplicado em ${id}`);
      seen.add(o.id);
      if (!OBJ_TYPES.has(o.type) || typeof o.target !== "string" || !ID_RE.test(o.target)) throw new Error(`quests: objetivo ${o.id} invalido em ${id}`);
      if (!isInt(o.required) || o.required < 1 || o.required > 999) throw new Error(`quests: required invalido em ${id}.${o.id}`);
      return { id: o.id, type: o.type, target: o.target, required: o.required };
    });
    const xp = r.rewards?.xp ?? 0;
    if (!isInt(xp) || xp < 0) throw new Error(`quests: xp invalido em ${id}`);
    const merged = new Map<string, number>();
    for (const it of (r.rewards?.items ?? []) as any[]) {
      if (typeof it?.item_id !== "string" || !items.has(it.item_id)) throw new Error(`quests: item de recompensa desconhecido em ${id}`);
      if (!isInt(it.qty) || it.qty < 1) throw new Error(`quests: qty invalida em ${id}`);
      merged.set(it.item_id, (merged.get(it.item_id) ?? 0) + it.qty);
    }
    if (xp === 0 && merged.size === 0) throw new Error(`quests: ${id} sem recompensa`);
    const rewardItems = [...merged.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([item_id, qty]) => ({ item_id, qty }));
    map.set(id, Object.freeze({ id, prerequisites: { quests: [...pq], min_level: ml }, objectives, rewards: { xp, items: rewardItems } }));
  }
  for (const q of map.values()) for (const p of q.prerequisites.quests) if (!map.has(p)) throw new Error(`quests: prerequisito desconhecido ${p} em ${q.id}`);
  const pois = explorationRaw === undefined ? new Map<string, PoiDefLite>() : parseExploration(explorationRaw, items, map);
  if (explorationRaw !== undefined) {
    for (const q of map.values()) for (const o of q.objectives) if (o.type === "discover" && !pois.has(o.target)) throw new Error(`quests: ponto de exploracao desconhecido ${o.target} em ${q.id}`);
  }
  return {
    get: (id) => map.get(id), has: (id) => map.has(id), ids: () => [...map.keys()],
    poi: (id) => pois.get(id), hasPoi: (id) => pois.has(id), poiIds: () => [...pois.keys()],
  };
}

/** Valida shared/content_schemas/exploration.json (gerado por tools/gen_quests_catalog.mjs). */
function parseExploration(raw: unknown, items: Catalog, quests: Map<string, QuestDefLite>): Map<string, PoiDefLite> {
  if (typeof raw !== "object" || raw === null) throw new Error("exploration: raiz invalida");
  const obj = raw as { schema_version?: unknown; points?: unknown };
  if (obj.schema_version !== 1) throw new Error("exploration: schema_version nao suportada");
  if (!Array.isArray(obj.points)) throw new Error("exploration: lista invalida");
  const out = new Map<string, PoiDefLite>();
  for (const p of obj.points as unknown[]) {
    const r = p as Record<string, any>;
    const id = r?.id;
    if (typeof id !== "string" || !ID_RE.test(id)) throw new Error(`exploration: id invalido ${String(id)}`);
    if (out.has(id)) throw new Error(`exploration: id duplicado ${id}`);
    if (typeof r.zone !== "string" || !ID_RE.test(r.zone)) throw new Error(`exploration: zone invalida em ${id}`);
    const ml = r.min_level ?? 1;
    if (!isInt(ml) || ml < 1) throw new Error(`exploration: min_level invalido em ${id}`);
    const rq = r.requires_quests ?? [];
    if (!Array.isArray(rq) || !rq.every((x: unknown) => typeof x === "string" && quests.has(x))) throw new Error(`exploration: requires_quests invalido em ${id}`);
    const xp = r.rewards?.xp ?? 0;
    if (!isInt(xp) || xp < 0) throw new Error(`exploration: xp invalido em ${id}`);
    const merged = new Map<string, number>();
    for (const it of (r.rewards?.items ?? []) as any[]) {
      if (typeof it?.item_id !== "string" || !items.has(it.item_id)) throw new Error(`exploration: item de recompensa desconhecido em ${id}`);
      if (!isInt(it.qty) || it.qty < 1) throw new Error(`exploration: qty invalida em ${id}`);
      merged.set(it.item_id, (merged.get(it.item_id) ?? 0) + it.qty);
    }
    if (xp === 0 && merged.size === 0) throw new Error(`exploration: ${id} sem recompensa`);
    const rewardItems = [...merged.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([item_id, qty]) => ({ item_id, qty }));
    out.set(id, Object.freeze({ id, zone: r.zone, min_level: ml, requires_quests: [...rq].sort(), rewards: { xp, items: rewardItems } }));
  }
  return out;
}

export const QUESTS_JSON_URL = new URL("../../../shared/content_schemas/quests.json", import.meta.url);

export const EXPLORATION_JSON_URL = new URL("../../../shared/content_schemas/exploration.json", import.meta.url);

export function loadQuestCatalogFromDisk(items: Catalog, url: URL = QUESTS_JSON_URL, explorationUrl: URL | null = EXPLORATION_JSON_URL): QuestCatalog {
  const exploration = explorationUrl && existsSync(explorationUrl) ? JSON.parse(readFileSync(explorationUrl, "utf8")) : undefined;
  return createQuestCatalog(JSON.parse(readFileSync(url, "utf8")), items, exploration);
}
