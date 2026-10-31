import { ApiError } from "../http/errors.ts";
import { EMPTY_QUESTS, type QuestCatalog } from "./catalog.ts";

/** Estado persistido de quests (coluna characters.quests). "ready" e derivado e nao e armazenado. */
export interface QuestsState {
  active: Record<string, { objectives: Record<string, number> }>;
  completed: string[];
}

export const emptyQuests = (): QuestsState => ({ active: {}, completed: [] });

const bad = (m: string): ApiError => new ApiError(422, "invalid_state", m);
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const ID_RE = /^[a-z][a-z0-9_]{0,47}$/;

/** Le o jsonb armazenado de forma tolerante ('{}' => vazio). Nao consulta o catalogo (conteudo pode ter sido removido). */
export function normalizeStoredQuests(raw: unknown): QuestsState {
  const out = emptyQuests();
  if (!isObj(raw)) return out;
  if (isObj(raw.active)) {
    for (const [qid, e] of Object.entries(raw.active)) {
      const objs: Record<string, number> = {};
      if (isObj(e) && isObj(e.objectives)) for (const [oid, v] of Object.entries(e.objectives)) if (Number.isSafeInteger(v) && (v as number) >= 0) objs[oid] = v as number;
      out.active[qid] = { objectives: objs };
    }
  }
  if (Array.isArray(raw.completed)) out.completed = [...new Set(raw.completed.filter((x): x is string => typeof x === "string"))].sort();
  return out;
}

/**
 * Valida o estado de quests vindo do servidor de sessao (422 invalid_state). Regras: ids conhecidos,
 * objetivos conhecidos, progresso inteiro 0..required, concluida nao pode estar ativa, sem duplicatas,
 * no maximo `maxActive` ativas. Devolve a forma canonica (ordenada).
 */
export function validateQuestsState(input: unknown, catalog: QuestCatalog = EMPTY_QUESTS, maxActive = 10): QuestsState {
  if (!isObj(input)) throw bad("quests deve ser um objeto");
  for (const k of Object.keys(input)) if (k !== "active" && k !== "completed") throw bad(`quests: campo desconhecido "${k.slice(0, 40)}"`);
  const active: QuestsState["active"] = {};
  const rawActive = input.active ?? {};
  if (!isObj(rawActive)) throw bad("quests.active deve ser objeto");
  const ids = Object.keys(rawActive);
  if (ids.length > maxActive) throw bad(`quests.active excede o limite (${maxActive})`);
  const rawDone = input.completed ?? [];
  if (!Array.isArray(rawDone)) throw bad("quests.completed deve ser lista");
  if (rawDone.length > 1000) throw bad("quests.completed grande demais");
  const completed = new Set<string>();
  for (const c of rawDone as unknown[]) {
    if (typeof c !== "string" || !ID_RE.test(c)) throw bad("quests.completed: id invalido");
    if (!catalog.has(c)) throw bad(`quests.completed: quest desconhecida "${c.slice(0, 48)}"`);
    if (completed.has(c)) throw bad("quests.completed: id duplicado");
    completed.add(c);
  }
  for (const qid of ids.sort()) {
    const def = catalog.get(qid);
    if (!def) throw bad(`quests.active: quest desconhecida "${qid.slice(0, 48)}"`);
    if (completed.has(qid)) throw bad(`quests.active: ${qid} ja concluida`);
    const e = rawActive[qid];
    if (!isObj(e) || !isObj(e.objectives)) throw bad(`quests.active.${qid}: entrada invalida`);
    for (const k of Object.keys(e)) if (k !== "objectives") throw bad(`quests.active.${qid}: campo desconhecido`);
    const objs: Record<string, number> = {};
    for (const oid of Object.keys(e.objectives).sort()) {
      const od = def.objectives.find((o) => o.id === oid);
      if (!od) throw bad(`quests.active.${qid}: objetivo desconhecido "${oid.slice(0, 48)}"`);
      const v = e.objectives[oid];
      if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 0 || v > od.required) throw bad(`quests.active.${qid}.${oid}: progresso deve ser inteiro 0..${od.required}`);
      objs[oid] = v;
    }
    active[qid] = { objectives: objs };
  }
  return { active, completed: [...completed].sort() };
}

/**
 * Regra do checkpoint: `completed` e SOMENTE-SERVIDOR (so a recompensa da quest o altera, na mesma transacao).
 * O checkpoint nao pode concluir uma quest (senao a recompensa posterior seria negada) nem desfazer uma conclusao.
 * Devolve o estado a gravar: active do cliente sem as quests ja concluidas no banco; completed = o do banco.
 */
export function mergeCheckpointQuests(stored: QuestsState, incoming: QuestsState): QuestsState {
  const done = new Set(stored.completed);
  const active: QuestsState["active"] = {};
  for (const [qid, e] of Object.entries(incoming.active)) if (!done.has(qid)) active[qid] = e;
  return { active, completed: [...stored.completed].sort() };
}

/** Conclui `questId` (puro): remove de ativas e acrescenta a concluidas. */
export function completeQuest(q: QuestsState, questId: string): QuestsState {
  const active = { ...q.active };
  delete active[questId];
  return { active, completed: [...new Set([...q.completed, questId])].sort() };
}
