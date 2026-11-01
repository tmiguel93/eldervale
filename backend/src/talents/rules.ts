import type { TalentCatalog, TalentTree } from "./catalog.ts";
import { MAX_TALENT_NODES, MAX_TALENT_RANK } from "./catalog.ts";

/** Estado de talentos do personagem (coluna `characters.talents`). */
export interface TalentsState {
  /** "" = nenhuma especializacao escolhida. */
  spec: string;
  ranks: Record<string, number>;
  respecs: number;
}

export const EMPTY_TALENTS_STATE = (): TalentsState => ({ spec: "", ranks: {}, respecs: 0 });

/** Codigos de erro estaveis (iguais aos de scripts/talents/talent_state.gd). */
export type TalentErrorCode =
  | "unknown_node" | "spec_not_chosen" | "wrong_spec" | "max_rank" | "level_too_low" | "prerequisite" | "no_points"
  | "unknown_spec" | "spec_already_chosen" | "nothing_to_reset" | "insufficient_items";

const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);
const MAX_RESPECS = 1_000_000;

/**
 * Normaliza o jsonb lido do banco. LENIENTE: formato invalido vira vazio; com `tree`, nos desconhecidos / de outra especializacao sao
 * descartados e o rank e limitado ao max_rank (a arvore pode mudar entre versoes sem corromper o personagem).
 */
export function normalizeStoredTalents(raw: unknown, tree?: TalentTree): TalentsState {
  const out = EMPTY_TALENTS_STATE();
  if (!isObj(raw)) return out;
  if (isInt(raw.respecs) && raw.respecs >= 0 && raw.respecs <= MAX_RESPECS) out.respecs = raw.respecs;
  if (typeof raw.spec === "string" && ID_RE.test(raw.spec) && (!tree || tree.specs.includes(raw.spec))) out.spec = raw.spec;
  if (isObj(raw.ranks)) {
    for (const [id, v] of Object.entries(raw.ranks)) {
      if (!ID_RE.test(id) || !isInt(v) || v < 1 || v > MAX_TALENT_RANK) continue;
      if (tree) {
        const n = tree.nodes.get(id);
        if (!n || (n.spec !== "" && n.spec !== out.spec)) continue;
        out.ranks[id] = Math.min(v, n.max_rank);
      } else {
        out.ranks[id] = v;
      }
      if (Object.keys(out.ranks).length >= MAX_TALENT_NODES) break;
    }
  }
  return out;
}

/** Pontos gastos nos nos CONHECIDOS da arvore. */
export function pointsSpent(tree: TalentTree, st: TalentsState): number {
  let t = 0;
  for (const [id, r] of Object.entries(st.ranks)) {
    const n = tree.nodes.get(id);
    if (n) t += n.cost * r;
  }
  return t;
}

export function pointsAvailable(tree: TalentTree, st: TalentsState, level: number, cat: TalentCatalog): number {
  return Math.max(0, cat.pointsForLevel(level) - pointsSpent(tree, st));
}

/** null se der para somar 1 rank em `nodeId`; senao o codigo do primeiro impedimento (ordem fixa, igual ao Godot). */
export function checkAllocate(tree: TalentTree, st: TalentsState, level: number, nodeId: string, cat: TalentCatalog): TalentErrorCode | null {
  const n = tree.nodes.get(nodeId);
  if (!n) return "unknown_node";
  if (n.spec !== "") {
    if (st.spec === "") return "spec_not_chosen";
    if (st.spec !== n.spec) return "wrong_spec";
  }
  if ((st.ranks[nodeId] ?? 0) >= n.max_rank) return "max_rank";
  if (level < n.min_level) return "level_too_low";
  for (const r of n.requires) if ((st.ranks[r] ?? 0) < 1) return "prerequisite";
  if (n.min_points_spent > 0 && pointsSpent(tree, st) < n.min_points_spent) return "prerequisite";
  if (pointsAvailable(tree, st, level, cat) < n.cost) return "no_points";
  return null;
}

export function checkChooseSpec(tree: TalentTree, st: TalentsState, spec: string): TalentErrorCode | null {
  if (!tree.specs.includes(spec)) return "unknown_spec";
  if (st.spec !== "") return "spec_already_chosen";
  return null;
}

export function checkRespec(st: TalentsState): TalentErrorCode | null {
  return st.spec === "" && Object.keys(st.ranks).length === 0 ? "nothing_to_reset" : null;
}

export const TALENT_ERROR_MESSAGES: Record<TalentErrorCode, string> = {
  unknown_node: "talento desconhecido",
  spec_not_chosen: "escolha uma especializacao antes",
  wrong_spec: "talento de outra especializacao",
  max_rank: "talento ja esta no maximo",
  level_too_low: "nivel insuficiente",
  prerequisite: "requisitos nao cumpridos",
  no_points: "sem pontos de talento disponiveis",
  unknown_spec: "especializacao desconhecida",
  spec_already_chosen: "especializacao ja escolhida (reset para trocar)",
  nothing_to_reset: "nao ha talentos para resetar",
  insufficient_items: "itens insuficientes para o reset",
};
