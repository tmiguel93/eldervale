import { ApiError, Errors } from "../http/errors.ts";
import type { Db } from "../persistence/db.ts";
import { addItems, type InventoryEntry, type CharacterState } from "../characters/model.ts";
import { loadRecord, writeState, type CharacterRecord, type ServiceCtx } from "../characters/service.ts";
import type { Recipe, RecipeStack } from "./catalog.ts";

export type RemoveResult = { ok: true; inventory: InventoryEntry[] } | { ok: false; missing: RecipeStack[] };

/**
 * Remove ingredientes do INVENTARIO (puro, tudo-ou-nada). Itens equipados nao contam: o jogador precisa
 * desequipar antes. Consome das pilhas de maior slot para o menor (como Inventory.remove do jogo).
 */
export function removeItems(inventory: readonly InventoryEntry[], needs: readonly RecipeStack[]): RemoveResult {
  const slots = new Map<number, InventoryEntry>();
  for (const e of inventory) slots.set(e.slot, { ...e });
  const missing: RecipeStack[] = [];
  for (const { item_id, qty } of needs) {
    const have = [...slots.values()].filter((e) => e.item_id === item_id).reduce((n, e) => n + e.qty, 0);
    if (have < qty) missing.push({ item_id, qty: qty - have });
  }
  if (missing.length > 0) return { ok: false, missing };
  for (const { item_id, qty } of needs) {
    let left = qty;
    for (const e of [...slots.values()].filter((x) => x.item_id === item_id).sort((a, b) => b.slot - a.slot)) {
      if (left === 0) break;
      const take = Math.min(e.qty, left);
      e.qty -= take;
      left -= take;
      if (e.qty === 0) slots.delete(e.slot);
    }
  }
  return { ok: true, inventory: [...slots.values()].sort((a, b) => a.slot - b.slot) };
}

export interface CraftResult {
  recipe_id: string;
  consumed: RecipeStack[];
  produced: RecipeStack[];
  revision: number;
}

/**
 * Crafting atomico e idempotente (E5.4). Uma transacao: trava o personagem, confere replay pela chave em
 * `reward_claims` (mesma tabela das recompensas), confere ingredientes (409 insufficient_ingredients), remove,
 * adiciona o resultado (409 inventory_full: tudo-ou-nada, nada e aplicado e a chave NAO e consumida) e grava.
 * O servidor de sessao e quem valida estacao/proximidade (o backend so conhece a receita e o inventario).
 */
export async function craft(db: Db, ctx: ServiceCtx, id: string, idempotencyKey: string, recipe: Recipe): Promise<{ replayed: boolean; result: CraftResult; character: CharacterRecord }> {
  const canonical = JSON.stringify({ craft: recipe.id });
  return db.tx(async (tx) => {
    const cur = await loadRecord(tx, id, { forUpdate: true });
    if (!cur) throw Errors.notFound("personagem nao encontrado");

    const prev = await tx.query<{ payload: { request: string; result: CraftResult } }>(
      "SELECT payload FROM reward_claims WHERE character_id = $1 AND idempotency_key = $2", [id, idempotencyKey]);
    const claim = prev.rows[0];
    if (claim) {
      if (claim.payload.request !== canonical) throw Errors.conflict("idempotency_key ja usada com outro conteudo", "idempotency_key_reuse");
      return { replayed: true, result: claim.payload.result, character: cur };
    }

    const removed = removeItems(cur.state.inventory, recipe.ingredients);
    if (!removed.ok) {
      ctx.log.warn("craft_rejected", { character_id: id, reason: "insufficient_ingredients", recipe_id: recipe.id });
      throw new ApiError(409, "insufficient_ingredients", "ingredientes insuficientes no inventario");
    }
    const added = addItems(removed.inventory, recipe.results, ctx.catalog, ctx.limits.inventoryCapacity);
    if (!added.ok) {
      ctx.log.warn("craft_rejected", { character_id: id, reason: "inventory_full", recipe_id: recipe.id });
      throw new ApiError(409, "inventory_full", "sem espaco no inventario; nada foi aplicado");
    }
    const next: CharacterState = { ...cur.state, inventory: added.inventory };
    const revision = await writeState(tx, ctx, id, cur.revision, next);
    const result: CraftResult = {
      recipe_id: recipe.id,
      consumed: recipe.ingredients.map((s) => ({ ...s })),
      produced: recipe.results.map((s) => ({ ...s })),
      revision,
    };
    await tx.query("INSERT INTO reward_claims (character_id, idempotency_key, payload, created_at) VALUES ($1, $2, $3::jsonb, $4)",
      [id, idempotencyKey, JSON.stringify({ request: canonical, result }), new Date(ctx.now())]);
    return { replayed: false, result, character: { ...cur, revision, state: next } };
  });
}
