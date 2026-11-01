import { readFileSync } from "node:fs";
import type { Catalog } from "../characters/catalog.ts";
import type { ClassCatalog } from "../characters/classes.ts";

export interface TalentNode {
  id: string;
  /** "" = no generico da classe; senao exige essa especializacao escolhida. */
  spec: string;
  requires: readonly string[];
  min_points_spent: number;
  min_level: number;
  cost: number;
  max_rank: number;
}
export interface TalentTree {
  class_id: string;
  specs: readonly string[];
  nodes: ReadonlyMap<string, TalentNode>;
}
export interface TalentPoints {
  first_point_level: number;
  points_per_level: number;
  max_points: number;
}
export interface RespecConfig {
  cost_items: readonly { item_id: string; qty: number }[];
  require_safe_zone: boolean;
}
export interface TalentCatalog {
  tree(classId: string): TalentTree | undefined;
  classIds(): string[];
  points: TalentPoints;
  respec: RespecConfig;
  /** Pontos de talento totais concedidos pelo nivel (curva de dado). */
  pointsForLevel(level: number): number;
}

const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

export const MAX_TALENT_NODES = 40;
export const MAX_TALENT_RANK = 5;

/**
 * Valida o JSON do catalogo (gerado por tools/gen_talents_catalog.mjs a partir de data/talents/*.json) e devolve um catalogo
 * imutavel. Lanca Error em qualquer inconsistencia (falha na inicializacao, nunca em request). Confere de novo o grafo (acíclico,
 * requisitos existentes), as especializacoes iniciais (`classes`) e os itens do custo do respec (`items`).
 */
export function createTalentCatalog(raw: unknown, items?: Catalog, classes?: ClassCatalog): TalentCatalog {
  if (!isObj(raw)) throw new Error("talentos: raiz invalida");
  if (raw.schema_version !== 1) throw new Error("talentos: schema_version nao suportada");
  const pt = raw.points;
  if (!isObj(pt) || !isInt(pt.first_point_level) || pt.first_point_level < 2 || pt.first_point_level > 50
    || !isInt(pt.points_per_level) || pt.points_per_level < 1 || pt.points_per_level > 5 || !isInt(pt.max_points) || pt.max_points < 1 || pt.max_points > 500) {
    throw new Error("talentos: points invalido");
  }
  const points: TalentPoints = Object.freeze({ first_point_level: pt.first_point_level, points_per_level: pt.points_per_level, max_points: pt.max_points });
  const rs = raw.respec;
  if (!isObj(rs) || typeof rs.require_safe_zone !== "boolean" || !Array.isArray(rs.cost_items) || rs.cost_items.length > 3) throw new Error("talentos: respec invalido");
  const cost: { item_id: string; qty: number }[] = [];
  for (const c of rs.cost_items as unknown[]) {
    if (!isObj(c) || typeof c.item_id !== "string" || !ID_RE.test(c.item_id) || !isInt(c.qty) || c.qty < 1 || c.qty > 99 || cost.some((x) => x.item_id === c.item_id)) {
      throw new Error("talentos: respec.cost_items invalido");
    }
    if (items && !items.has(c.item_id)) throw new Error(`talentos: item do respec desconhecido ${c.item_id}`);
    cost.push(Object.freeze({ item_id: c.item_id, qty: c.qty }));
  }
  const respec: RespecConfig = Object.freeze({ cost_items: Object.freeze(cost), require_safe_zone: rs.require_safe_zone });
  if (!Array.isArray(raw.trees) || raw.trees.length === 0) throw new Error("talentos: trees vazio");
  const trees = new Map<string, TalentTree>();
  for (const t of raw.trees as unknown[]) {
    if (!isObj(t) || typeof t.class_id !== "string" || !ID_RE.test(t.class_id) || trees.has(t.class_id)) throw new Error("talentos: arvore invalida");
    const cid = t.class_id;
    if (classes && !classes.has(cid)) throw new Error(`talentos: classe desconhecida ${cid}`);
    if (!Array.isArray(t.specs) || t.specs.some((s) => typeof s !== "string" || !ID_RE.test(s))) throw new Error(`talentos: specs invalido em ${cid}`);
    const specs = t.specs as string[];
    if (classes) {
      const active = classes.get(cid)!.specializations.filter((s) => !s.planned).map((s) => s.id).sort().join(",");
      if (active !== [...specs].sort().join(",")) throw new Error(`talentos: specs de ${cid} divergem da classe`);
    }
    if (!Array.isArray(t.nodes) || t.nodes.length < 1 || t.nodes.length > MAX_TALENT_NODES) throw new Error(`talentos: nodes invalido em ${cid}`);
    const nodes = new Map<string, TalentNode>();
    for (const n of t.nodes as unknown[]) {
      if (!isObj(n) || typeof n.id !== "string" || !ID_RE.test(n.id) || nodes.has(n.id)) throw new Error(`talentos: no invalido em ${cid}`);
      const w = `${cid}/${n.id}`;
      if (typeof n.spec !== "string" || (n.spec !== "" && !specs.includes(n.spec))) throw new Error(`talentos: spec invalida em ${w}`);
      if (!Array.isArray(n.requires) || n.requires.length > 4 || n.requires.some((r) => typeof r !== "string" || !ID_RE.test(r)) || new Set(n.requires).size !== n.requires.length) throw new Error(`talentos: requires invalido em ${w}`);
      if (!isInt(n.cost) || n.cost < 1 || n.cost > 10) throw new Error(`talentos: cost invalido em ${w}`);
      if (!isInt(n.max_rank) || n.max_rank < 1 || n.max_rank > MAX_TALENT_RANK) throw new Error(`talentos: max_rank invalido em ${w}`);
      if (!isInt(n.min_points_spent) || n.min_points_spent < 0 || n.min_points_spent > 100) throw new Error(`talentos: min_points_spent invalido em ${w}`);
      if (!isInt(n.min_level) || n.min_level < 1 || n.min_level > 50) throw new Error(`talentos: min_level invalido em ${w}`);
      nodes.set(n.id, Object.freeze({ id: n.id, spec: n.spec, requires: Object.freeze([...(n.requires as string[])]), min_points_spent: n.min_points_spent, min_level: n.min_level, cost: n.cost, max_rank: n.max_rank }));
    }
    // referencias + aciclico (DFS)
    for (const n of nodes.values()) {
      for (const r of n.requires) {
        const rn = nodes.get(r);
        if (!rn || r === n.id) throw new Error(`talentos: requisito invalido ${cid}/${n.id} -> ${r}`);
        if (n.spec === "" && rn.spec !== "") throw new Error(`talentos: no generico ${cid}/${n.id} exige no de especializacao`);
      }
    }
    const color = new Map<string, 1 | 2>();
    const visit = (id: string): void => {
      if (color.get(id) === 2) return;
      if (color.get(id) === 1) throw new Error(`talentos: ciclo de requisitos em ${cid} (${id})`);
      color.set(id, 1);
      for (const r of nodes.get(id)!.requires) visit(r);
      color.set(id, 2);
    };
    for (const id of nodes.keys()) visit(id);
    trees.set(cid, Object.freeze({ class_id: cid, specs: Object.freeze([...specs]), nodes }));
  }
  if (classes) for (const id of classes.ids()) if (!trees.has(id)) throw new Error(`talentos: classe ${id} sem arvore`);
  return {
    tree: (id) => trees.get(id),
    classIds: () => [...trees.keys()],
    points,
    respec,
    pointsForLevel: (level) => Math.min(Math.max(0, level - points.first_point_level + 1) * points.points_per_level, points.max_points),
  };
}

export const TALENTS_JSON_URL = new URL("../../../shared/content_schemas/talents.json", import.meta.url);

/** Le shared/content_schemas/talents.json (relativo a este arquivo). */
export function loadTalentCatalogFromDisk(items?: Catalog, classes?: ClassCatalog, url: URL = TALENTS_JSON_URL): TalentCatalog {
  return createTalentCatalog(JSON.parse(readFileSync(url, "utf8")), items, classes);
}

/** Sem arvores (testes que nao usam talentos). */
export const EMPTY_TALENTS: TalentCatalog = Object.freeze({
  tree: () => undefined,
  classIds: () => [],
  points: Object.freeze({ first_point_level: 2, points_per_level: 1, max_points: 60 }),
  respec: Object.freeze({ cost_items: Object.freeze([]), require_safe_zone: true }),
  pointsForLevel: () => 0,
});
