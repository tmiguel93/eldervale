import type { Db } from "../persistence/db.ts";
import type { RouteDeps } from "../http/app.ts";
import { Errors } from "../http/errors.ts";
import { created, noContent, ok } from "../http/respond.ts";
import type { Router } from "../http/router.ts";
import type { Catalog } from "./catalog.ts";
import { loadCatalogFromDisk } from "./catalog.ts";
import { loadCharacterLimits, type CharacterLimits } from "./limits.ts";
import { loadQuestCatalogFromDisk, type QuestCatalog } from "../quests/catalog.ts";
import { validateCharacterName, validateClassId, validateRewardRequest, validateState } from "./model.ts";
import { checkpoint, createCharacter, deleteCharacter, getOwned, grantReward, internalView, listCharacters, loadRecord, publicView, type ServiceCtx } from "./service.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function uuidParam(v: string | undefined): string {
  if (!v || !UUID_RE.test(v)) throw Errors.badRequest("id invalido", "invalid_id");
  return v.toLowerCase();
}

/**
 * Fencing (M4): checkpoint/recompensa so sao aceitos da sessao que detem o lock do personagem.
 * A sessao vem no cabecalho X-Session-Id; sem lock, lock de outra sessao ou sessao encerrada => 409.
 */
async function assertSessionHoldsLock(db: Db, ctx: { req: Request }, characterId: string): Promise<void> {
  const raw = ctx.req.headers.get("x-session-id");
  if (!raw || !UUID_RE.test(raw)) throw Errors.badRequest("cabecalho X-Session-Id obrigatorio (uuid)", "invalid_session");
  const r = await db.query(
    `SELECT 1 FROM character_locks l JOIN game_sessions s ON s.id = l.session_id
     WHERE l.character_id = $1 AND l.session_id = $2 AND s.closed_at IS NULL AND s.status <> 'closed'`,
    [characterId, raw.toLowerCase()]);
  if (r.rows.length === 0) throw Errors.conflict("sessao nao detem o lock do personagem", "session_fenced");
}

function objectBody(b: unknown): Record<string, unknown> {
  if (typeof b !== "object" || b === null || Array.isArray(b)) throw Errors.badRequest("corpo deve ser um objeto", "invalid_body");
  return b as Record<string, unknown>;
}

/** `opts` existe para testes; em producao use os padroes (catalogo do disco, limites de env). */
export function registerCharactersRoutes(router: Router, deps: RouteDeps, opts: { catalog?: Catalog; limits?: CharacterLimits; quests?: QuestCatalog } = {}): void {
  const catalog = opts.catalog ?? loadCatalogFromDisk();
  const limits = opts.limits ?? loadCharacterLimits();
  const quests = opts.quests ?? loadQuestCatalogFromDisk(catalog);
  const { db, requireAuth, requireInternal } = deps;
  const svc = (log: ServiceCtx["log"]): ServiceCtx => ({ catalog, limits, now: deps.now, log, quests });

  // ----------------------------------------------------------- publico
  router.get("/v1/characters", requireAuth(async (ctx) => ok({ characters: await listCharacters(db, ctx.auth.accountId) })));

  router.post("/v1/characters", requireAuth(async (ctx) => {
    const body = objectBody(await ctx.json());
    for (const k of Object.keys(body)) if (k !== "name" && k !== "class_id") throw Errors.badRequest(`campo desconhecido "${k.slice(0, 40)}"`, "invalid_body");
    const name = validateCharacterName(body.name);
    const classId = validateClassId(body.class_id);
    const rec = await createCharacter(db, svc(ctx.log), ctx.auth.accountId, name, classId);
    return created({ character: publicView(rec, limits) });
  }));

  router.get("/v1/characters/:id", requireAuth(async (ctx) => {
    const rec = await getOwned(db, ctx.auth.accountId, uuidParam(ctx.params.id));
    if (!rec) throw Errors.notFound("personagem nao encontrado");
    return ok({ character: publicView(rec, limits) });
  }));

  router.delete("/v1/characters/:id", requireAuth(async (ctx) => {
    await deleteCharacter(db, svc(ctx.log), ctx.auth.accountId, uuidParam(ctx.params.id));
    return noContent();
  }));

  // ----------------------------------------------------------- interno
  router.get("/internal/characters/:id", requireInternal(async (ctx) => {
    const rec = await loadRecord(db, uuidParam(ctx.params.id));
    if (!rec) throw Errors.notFound("personagem nao encontrado");
    return ok({ character: internalView(rec, limits) });
  }));

  router.post("/internal/characters/:id/checkpoint", requireInternal(async (ctx) => {
    const id = uuidParam(ctx.params.id);
    await assertSessionHoldsLock(db, ctx, id);
    const body = objectBody(await ctx.json());
    for (const k of Object.keys(body)) if (k !== "expected_revision" && k !== "state") throw Errors.badRequest(`campo desconhecido "${k.slice(0, 40)}"`, "invalid_body");
    const rev = body.expected_revision;
    if (typeof rev !== "number" || !Number.isSafeInteger(rev) || rev < 0) throw Errors.badRequest("expected_revision deve ser inteiro >= 0", "invalid_body");
    const state = validateState(body.state, catalog, limits, quests);
    const rec = await checkpoint(db, svc(ctx.log), id, rev, state);
    return ok({ character: internalView(rec, limits) });
  }));

  router.post("/internal/characters/:id/rewards", requireInternal(async (ctx) => {
    const id = uuidParam(ctx.params.id);
    await assertSessionHoldsLock(db, ctx, id);
    const req = validateRewardRequest(await ctx.json(), catalog, limits, quests, id);
    const out = await grantReward(db, svc(ctx.log), id, req);
    return ok({ replayed: out.replayed, result: out.result, character: internalView(out.character, limits) });
  }));
}
