import { ApiError, Errors } from "../http/errors.ts";
import type { Logger } from "../http/logger.ts";
import { isUniqueViolation, type Db } from "../persistence/db.ts";
import type { Catalog } from "./catalog.ts";
import type { CharacterLimits } from "./limits.ts";
import {
  addItems, BASE_STATS, EQUIP_SLOTS, itemTotals, invalidState, SCHEMA_VERSION, STARTING_EQUIPMENT,
  type CharacterState, type Equipment, type EquipSlot, type InventoryEntry, type RewardRequest, type Stats,
} from "./model.ts";
import { applyXp, xpToNext } from "./progression.ts";
import { EMPTY_QUESTS, type QuestCatalog } from "../quests/catalog.ts";
import { completeQuest, emptyQuests, mergeCheckpointQuests, normalizeStoredQuests } from "../quests/state.ts";

export interface ServiceCtx {
  catalog: Catalog;
  limits: CharacterLimits;
  now: () => number;
  log: Logger;
  /** Catalogo de quests (E5.1). Ausente = vazio (nenhuma quest conhecida). */
  quests?: QuestCatalog;
}

export interface CharacterRecord {
  id: string;
  account_id: string;
  name: string;
  class_id: string;
  created_at: string;
  revision: number;
  state: CharacterState;
}

interface CharRow {
  id: string; account_id: string; name: string; class_id: string; level: number; xp: string | number;
  stats: Record<string, unknown>; quests?: unknown; schema_version: number; revision: string | number; created_at: Date | string;
}

const COLS = "id, account_id, name, class_id, level, xp, stats, quests, schema_version, revision, created_at";

/** Carrega personagem ativo (nao apagado) com inventario/equipamento. `forUpdate` trava a linha ate o fim da transacao. */
export async function loadRecord(db: Db, id: string, opts: { accountId?: string; forUpdate?: boolean } = {}): Promise<CharacterRecord | null> {
  const params: unknown[] = [id];
  let sql = `SELECT ${COLS} FROM characters WHERE id = $1 AND deleted_at IS NULL`;
  if (opts.accountId) {
    params.push(opts.accountId);
    sql += " AND account_id = $2";
  }
  if (opts.forUpdate) sql += " FOR UPDATE";
  const r = await db.query<CharRow>(sql, params);
  const row = r.rows[0];
  if (!row) return null;
  const inv = await db.query<{ slot: number; item_id: string; qty: number }>(
    "SELECT slot, item_id, qty FROM character_inventory WHERE character_id = $1 ORDER BY slot", [id]);
  const eq = await db.query<{ slot_name: string; item_id: string }>(
    "SELECT slot_name, item_id FROM character_equipment WHERE character_id = $1", [id]);
  const equipment: Equipment = {};
  for (const e of eq.rows) if ((EQUIP_SLOTS as readonly string[]).includes(e.slot_name)) equipment[e.slot_name as EquipSlot] = e.item_id;
  const stats = { ...BASE_STATS, ...(row.stats as Partial<Stats>) } as Stats;
  return {
    id: row.id,
    account_id: row.account_id,
    name: row.name,
    class_id: row.class_id,
    created_at: new Date(row.created_at).toISOString(),
    revision: Number(row.revision),
    state: {
      schema_version: row.schema_version,
      level: row.level,
      xp: Number(row.xp),
      stats,
      inventory: inv.rows.map((e) => ({ slot: e.slot, item_id: e.item_id, qty: e.qty })),
      equipment,
      quests: normalizeStoredQuests(row.quests),
    },
  };
}

async function replaceInventory(db: Db, id: string, inv: readonly InventoryEntry[]): Promise<void> {
  await db.query("DELETE FROM character_inventory WHERE character_id = $1", [id]);
  if (inv.length === 0) return;
  const params: unknown[] = [id];
  const values = inv.map((e, i) => {
    params.push(e.slot, e.item_id, e.qty);
    return `($1, $${i * 3 + 2}, $${i * 3 + 3}, $${i * 3 + 4})`;
  });
  await db.query(`INSERT INTO character_inventory (character_id, slot, item_id, qty) VALUES ${values.join(", ")}`, params);
}

async function replaceEquipment(db: Db, id: string, eq: Equipment): Promise<void> {
  await db.query("DELETE FROM character_equipment WHERE character_id = $1", [id]);
  const entries = Object.entries(eq).filter(([, v]) => v) as [string, string][];
  if (entries.length === 0) return;
  const params: unknown[] = [id];
  const values = entries.map(([slot, item], i) => {
    params.push(slot, item);
    return `($1, $${i * 2 + 2}, $${i * 2 + 3})`;
  });
  await db.query(`INSERT INTO character_equipment (character_id, slot_name, item_id) VALUES ${values.join(", ")}`, params);
}

/** Persiste o estado e incrementa a revision (a linha deve estar travada/validada pelo chamador). */
async function writeState(db: Db, ctx: ServiceCtx, id: string, expectedRevision: number, s: CharacterState): Promise<number> {
  const r = await db.query<{ revision: string | number }>(
    `UPDATE characters SET level = $3, xp = $4, stats = $5::jsonb, schema_version = $6, revision = revision + 1, updated_at = $7, quests = $8::jsonb
     WHERE id = $1 AND revision = $2 AND deleted_at IS NULL RETURNING revision`,
    [id, expectedRevision, s.level, s.xp, JSON.stringify(s.stats), SCHEMA_VERSION, new Date(ctx.now()), JSON.stringify(s.quests ?? emptyQuests())]);
  if (r.rows.length !== 1) throw Errors.conflict("revision divergente", "revision_conflict");
  await replaceInventory(db, id, s.inventory);
  await replaceEquipment(db, id, s.equipment);
  return Number(r.rows[0]!.revision);
}

// ------------------------------------------------------------------ publico
export async function listCharacters(db: Db, accountId: string) {
  const r = await db.query<CharRow>(
    `SELECT ${COLS} FROM characters WHERE account_id = $1 AND deleted_at IS NULL ORDER BY created_at, id`, [accountId]);
  return r.rows.map((row) => ({
    id: row.id, name: row.name, class_id: row.class_id, level: row.level, xp: Number(row.xp),
    revision: Number(row.revision), created_at: new Date(row.created_at).toISOString(),
  }));
}

export async function createCharacter(db: Db, ctx: ServiceCtx, accountId: string, name: string, classId: string): Promise<CharacterRecord> {
  return db.tx(async (tx) => {
    // Trava a linha da conta: serializa criacoes concorrentes da mesma conta (limite exato).
    const acc = await tx.query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", [accountId]);
    if (acc.rows.length === 0) throw Errors.unauthorized();
    const cnt = await tx.query<{ n: number }>("SELECT count(*)::int AS n FROM characters WHERE account_id = $1 AND deleted_at IS NULL", [accountId]);
    if (cnt.rows[0]!.n >= ctx.limits.maxCharactersPerAccount) {
      throw Errors.conflict(`limite de ${ctx.limits.maxCharactersPerAccount} personagens por conta`, "character_limit");
    }
    let id: string;
    try {
      const ins = await tx.tx((t) =>
        t.query<{ id: string }>(
          "INSERT INTO characters (account_id, name, class_id, stats, schema_version, created_at, updated_at) VALUES ($1, $2, $3, $4::jsonb, $5, $6, $6) RETURNING id",
          [accountId, name, classId, JSON.stringify(BASE_STATS), SCHEMA_VERSION, new Date(ctx.now())]));
      id = ins.rows[0]!.id;
    } catch (e) {
      if (isUniqueViolation(e)) throw Errors.conflict("nome ja em uso", "name_taken");
      throw e;
    }
    await replaceEquipment(tx, id, STARTING_EQUIPMENT as Equipment);
    return (await loadRecord(tx, id))!;
  });
}

export async function getOwned(db: Db, accountId: string, id: string): Promise<CharacterRecord | null> {
  return loadRecord(db, id, { accountId });
}

/** Soft delete. Recusa (409) se ha lock de sessao. 404 se nao e da conta. Atomico em um UPDATE. */
export async function deleteCharacter(db: Db, ctx: ServiceCtx, accountId: string, id: string): Promise<void> {
  const r = await db.query(
    `UPDATE characters SET deleted_at = $3, updated_at = $3, revision = revision + 1
     WHERE id = $1 AND account_id = $2 AND deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM character_locks l WHERE l.character_id = characters.id)`,
    [id, accountId, new Date(ctx.now())]);
  if (r.rowCount === 1) return;
  const exists = await loadRecord(db, id, { accountId });
  if (!exists) throw Errors.notFound("personagem nao encontrado");
  throw Errors.conflict("personagem em sessao ativa", "character_in_session");
}

// ------------------------------------------------------------------ interno
export async function checkpoint(db: Db, ctx: ServiceCtx, id: string, expectedRevision: number, next: CharacterState): Promise<CharacterRecord> {
  return db.tx(async (tx) => {
    const cur = await loadRecord(tx, id, { forUpdate: true });
    if (!cur) throw Errors.notFound("personagem nao encontrado");
    if (cur.revision !== expectedRevision) {
      ctx.log.warn("checkpoint_rejected", { character_id: id, reason: "revision_conflict", expected: expectedRevision, actual: cur.revision });
      throw Errors.conflict(`revision divergente (atual ${cur.revision})`, "revision_conflict");
    }
    const reject = (reason: string, message: string): never => {
      ctx.log.warn("checkpoint_rejected", { character_id: id, reason });
      throw invalidState(message);
    };
    if (next.xp < cur.state.xp) reject("xp_decrease", "xp nao pode diminuir");
    if (next.xp - cur.state.xp > ctx.limits.checkpointMaxXpGain) {
      reject("xp_gain_limit", `ganho de xp acima do limite por checkpoint (${ctx.limits.checkpointMaxXpGain})`);
    }
    const before = itemTotals(cur.state);
    for (const [item, n] of itemTotals(next)) {
      if (n - (before.get(item) ?? 0) > ctx.limits.checkpointMaxItemGain) {
        reject("item_gain_limit", `ganho de ${item} acima do limite por checkpoint (${ctx.limits.checkpointMaxItemGain})`);
      }
    }
    // E5.1: `completed` e somente-servidor; ausente no checkpoint = manter o do banco.
    const quests = mergeCheckpointQuests(cur.state.quests ?? emptyQuests(), next.quests ?? cur.state.quests ?? emptyQuests());
    const toWrite: CharacterState = { ...next, quests };
    const revision = await writeState(tx, ctx, id, expectedRevision, toWrite);
    return { ...cur, revision, state: toWrite };
  });
}

export interface RewardResult {
  xp_granted: number;
  xp_total: number;
  level_before: number;
  level_after: number;
  levels_gained: number;
  items_added: { item_id: string; qty: number }[];
  revision: number;
}

export async function grantReward(db: Db, ctx: ServiceCtx, id: string, req: RewardRequest): Promise<{ replayed: boolean; result: RewardResult; character: CharacterRecord }> {
  const canonical = JSON.stringify(req.quest_id ? { xp: req.xp, items: req.items, quest_id: req.quest_id } : { xp: req.xp, items: req.items });
  return db.tx(async (tx) => {
    // Trava a linha: requests concorrentes do mesmo personagem (e da mesma chave) serializam aqui.
    const cur = await loadRecord(tx, id, { forUpdate: true });
    if (!cur) throw Errors.notFound("personagem nao encontrado");

    const prev = await tx.query<{ payload: { request: string; result: RewardResult } }>(
      "SELECT payload FROM reward_claims WHERE character_id = $1 AND idempotency_key = $2", [id, req.idempotency_key]);
    const claim = prev.rows[0];
    if (claim) {
      if (claim.payload.request !== canonical) {
        throw Errors.conflict("idempotency_key ja usada com outro conteudo", "idempotency_key_reuse");
      }
      return { replayed: true, result: claim.payload.result, character: cur };
    }

    const curQuests = cur.state.quests ?? emptyQuests();
    if (req.quest_id && curQuests.completed.includes(req.quest_id)) {
      throw Errors.conflict("quest ja concluida", "quest_already_completed");
    }
    const xpRes = applyXp(cur.state.xp, req.xp);
    let inventory = cur.state.inventory;
    if (req.items.length > 0) {
      const add = addItems(inventory, req.items, ctx.catalog, ctx.limits.inventoryCapacity);
      if (!add.ok) {
        ctx.log.warn("reward_rejected", { character_id: id, reason: "inventory_full" });
        throw new ApiError(409, "inventory_full", "sem espaco no inventario; nada foi aplicado");
      }
      inventory = add.inventory;
    }
    const next: CharacterState = { ...cur.state, xp: xpRes.xp, level: xpRes.level, inventory, quests: req.quest_id ? completeQuest(curQuests, req.quest_id) : curQuests };
    const revision = await writeState(tx, ctx, id, cur.revision, next);
    const result: RewardResult = {
      xp_granted: xpRes.xp - cur.state.xp,
      xp_total: xpRes.xp,
      level_before: cur.state.level,
      level_after: xpRes.level,
      levels_gained: xpRes.level - cur.state.level,
      items_added: req.items,
      revision,
    };
    await tx.query("INSERT INTO reward_claims (character_id, idempotency_key, payload, created_at) VALUES ($1, $2, $3::jsonb, $4)",
      [id, req.idempotency_key, JSON.stringify({ request: canonical, result }), new Date(ctx.now())]);
    return { replayed: false, result, character: { ...cur, revision, state: next } };
  });
}

export function publicView(r: CharacterRecord, limits: CharacterLimits) {
  return {
    id: r.id, name: r.name, class_id: r.class_id, created_at: r.created_at,
    level: r.state.level, xp: r.state.xp, xp_to_next: xpToNext(r.state.level),
    stats: r.state.stats, schema_version: r.state.schema_version, revision: r.revision,
    inventory_capacity: limits.inventoryCapacity, inventory: r.state.inventory, equipment: r.state.equipment,
    quests: r.state.quests ?? emptyQuests(),
  };
}

export function internalView(r: CharacterRecord, limits: CharacterLimits) {
  return { account_id: r.account_id, ...publicView(r, limits) };
}
