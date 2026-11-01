import { ApiError, Errors } from "../http/errors.ts";
import type { Db } from "../persistence/db.ts";
import { removeItems } from "../crafting/service.ts";
import { loadRecord, writeState, type CharacterRecord, type ServiceCtx } from "../characters/service.ts";
import type { CharacterState } from "../characters/model.ts";
import type { TalentCatalog } from "./catalog.ts";
import { checkAllocate, checkChooseSpec, checkRespec, normalizeStoredTalents, pointsAvailable, pointsSpent, TALENT_ERROR_MESSAGES, type TalentErrorCode, type TalentsState } from "./rules.ts";

export const TALENT_OPS = ["allocate", "respec", "choose_spec"] as const;
export type TalentOp = (typeof TALENT_OPS)[number];

export interface TalentRequest {
  idempotency_key: string;
  op: TalentOp;
  /** allocate: node_id; choose_spec: spec_id; respec: ausente. */
  arg?: string;
  /** Concorrencia otimista opcional: recusa (409 revision_conflict) se a revision do personagem for outra. */
  expected_revision?: number;
}

export interface TalentResult {
  op: TalentOp;
  arg: string;
  points_total: number;
  points_spent: number;
  points_available: number;
  revision: number;
}

function reject(ctx: ServiceCtx, id: string, code: TalentErrorCode, op: TalentOp): never {
  ctx.log.warn("talent_rejected", { character_id: id, reason: code, op });
  throw new ApiError(409, code, TALENT_ERROR_MESSAGES[code]);
}

/**
 * Comando de talentos ATOMICO e IDEMPOTENTE (E6.2). Uma transacao: trava o personagem (SELECT ... FOR UPDATE; comandos concorrentes do
 * mesmo personagem serializam aqui), confere replay pela chave em `reward_claims` (mesma tabela das recompensas/crafts), valida
 * contra o catalogo (pontos pelo NIVEL do banco, pre-requisitos, max_rank, especializacao, classe), aplica e grava com `revision + 1`.
 * Recusa de regra = 409 com o codigo da regra e NADA e gravado (a chave nao e consumida). Respec: consome `respec.cost_items` do inventario
 * (409 insufficient_items) na mesma transacao. O backend nao conhece zona: "so em zona segura" e checado pelo servidor de sessao.
 */
export async function applyTalentOp(db: Db, ctx: ServiceCtx, cat: TalentCatalog, id: string, req: TalentRequest): Promise<{ replayed: boolean; result: TalentResult; character: CharacterRecord }> {
  const arg = req.arg ?? "";
  const canonical = JSON.stringify({ talent: req.op, arg });
  return db.tx(async (tx) => {
    const cur = await loadRecord(tx, id, { forUpdate: true });
    if (!cur) throw Errors.notFound("personagem nao encontrado");

    const prev = await tx.query<{ payload: { request: string; result: TalentResult } }>(
      "SELECT payload FROM reward_claims WHERE character_id = $1 AND idempotency_key = $2", [id, req.idempotency_key]);
    const claim = prev.rows[0];
    if (claim) {
      if (claim.payload.request !== canonical) throw Errors.conflict("idempotency_key ja usada com outro conteudo", "idempotency_key_reuse");
      return { replayed: true, result: claim.payload.result, character: cur };
    }
    if (req.expected_revision !== undefined && req.expected_revision !== cur.revision) {
      throw Errors.conflict(`revision divergente (atual ${cur.revision})`, "revision_conflict");
    }

    const tree = cat.tree(cur.class_id);
    if (!tree) throw new ApiError(409, "no_talent_tree", "a classe do personagem nao tem arvore de talentos");
    const st: TalentsState = normalizeStoredTalents(cur.talents, tree);
    const level = cur.state.level;
    let next: TalentsState;
    let inventory = cur.state.inventory;
    switch (req.op) {
      case "allocate": {
        const err = checkAllocate(tree, st, level, arg, cat);
        if (err) reject(ctx, id, err, req.op);
        next = { ...st, ranks: { ...st.ranks, [arg]: (st.ranks[arg] ?? 0) + 1 } };
        break;
      }
      case "choose_spec": {
        const err = checkChooseSpec(tree, st, arg);
        if (err) reject(ctx, id, err, req.op);
        next = { ...st, spec: arg };
        break;
      }
      case "respec": {
        const err = checkRespec(st);
        if (err) reject(ctx, id, err, req.op);
        if (cat.respec.cost_items.length > 0) {
          const removed = removeItems(inventory, cat.respec.cost_items);
          if (!removed.ok) reject(ctx, id, "insufficient_items", req.op);
          else inventory = removed.inventory;
        }
        next = { spec: "", ranks: {}, respecs: st.respecs + 1 };
        break;
      }
    }

    let revision: number;
    const nextState: CharacterState = { ...cur.state, inventory };
    if (inventory !== cur.state.inventory) {
      revision = await writeState(tx, ctx, id, cur.revision, nextState); // inventario mudou (custo do respec): mesma transacao, revision + 1
      await tx.query("UPDATE characters SET talents = $2::jsonb WHERE id = $1", [id, JSON.stringify(next)]);
    } else {
      const r = await tx.query<{ revision: string | number }>(
        "UPDATE characters SET talents = $3::jsonb, revision = revision + 1, updated_at = $4 WHERE id = $1 AND revision = $2 AND deleted_at IS NULL RETURNING revision",
        [id, cur.revision, JSON.stringify(next), new Date(ctx.now())]);
      if (r.rows.length !== 1) throw Errors.conflict("revision divergente", "revision_conflict");
      revision = Number(r.rows[0]!.revision);
    }
    const result: TalentResult = {
      op: req.op, arg,
      points_total: cat.pointsForLevel(level),
      points_spent: pointsSpent(tree, next),
      points_available: pointsAvailable(tree, next, level, cat),
      revision,
    };
    await tx.query("INSERT INTO reward_claims (character_id, idempotency_key, payload, created_at) VALUES ($1, $2, $3::jsonb, $4)",
      [id, req.idempotency_key, JSON.stringify({ request: canonical, result }), new Date(ctx.now())]);
    return { replayed: false, result, character: { ...cur, revision, state: nextState, talents: next } };
  });
}
