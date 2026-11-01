import type { Db } from "../persistence/db.ts";
import type { RouteDeps } from "../http/app.ts";
import { Errors } from "../http/errors.ts";
import { created, noContent, ok } from "../http/respond.ts";
import type { Router } from "../http/router.ts";
import type { Catalog } from "./catalog.ts";
import { loadCatalogFromDisk } from "./catalog.ts";
import { loadClassCatalogFromDisk, type ClassCatalog } from "./classes.ts";
import { loadCharacterLimits, type CharacterLimits } from "./limits.ts";
import { loadQuestCatalogFromDisk, type QuestCatalog } from "../quests/catalog.ts";
import { loadRecipeCatalogFromDisk, type RecipeCatalog } from "../crafting/catalog.ts";
import { craft } from "../crafting/service.ts";
import { loadTalentCatalogFromDisk, type TalentCatalog } from "../talents/catalog.ts";
import { applyTalentOp, TALENT_OPS, type TalentOp } from "../talents/service.ts";
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

const SESSION_UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const LOOT_KEY_RE = new RegExp(`^loot:(${SESSION_UUID}):(\\d{1,12}):(${SESSION_UUID})$`, "i");
const CRAFT_KEY_RE = new RegExp(`^craft:(${SESSION_UUID}):(\\d{1,12}):(${SESSION_UUID})$`, "i");
const TALENT_KEY_RE = new RegExp(`^talent:(${SESSION_UUID}):(\\d{1,12}):(${SESSION_UUID})$`, "i");

/**
 * Chaves reservadas (E5.4): `loot:<session>:<drop_id>:<character_id>` (pickup coletado) e
 * `craft:<session>:<n>:<character_id>`. A sessao e o personagem da chave TEM de ser os do cabecalho X-Session-Id e
 * da URL: uma sessao nao consegue "gastar" a chave de outra nem de outro personagem. `loot:` paga exatamente UM
 * item e nenhum xp; `craft:` so e aceita em /craft.
 */
function assertReservedKey(re: RegExp, key: string, ctx: { req: Request }, characterId: string): void {
  const m = re.exec(key);
  const sid = (ctx.req.headers.get("x-session-id") ?? "").toLowerCase();
  if (!m || m[1]!.toLowerCase() !== sid || m[3]!.toLowerCase() !== characterId) {
    throw Errors.badRequest("idempotency_key reservada nao confere com a sessao/personagem", "invalid_idempotency_key");
  }
}

function objectBody(b: unknown): Record<string, unknown> {
  if (typeof b !== "object" || b === null || Array.isArray(b)) throw Errors.badRequest("corpo deve ser um objeto", "invalid_body");
  return b as Record<string, unknown>;
}

/** `opts` existe para testes; em producao use os padroes (catalogo do disco, limites de env). */
export function registerCharactersRoutes(router: Router, deps: RouteDeps, opts: { catalog?: Catalog; limits?: CharacterLimits; quests?: QuestCatalog; recipes?: RecipeCatalog; classes?: ClassCatalog; talents?: TalentCatalog } = {}): void {
  const catalog = opts.catalog ?? loadCatalogFromDisk();
  const limits = opts.limits ?? loadCharacterLimits();
  const quests = opts.quests ?? loadQuestCatalogFromDisk(catalog);
  const recipes = opts.recipes ?? loadRecipeCatalogFromDisk(catalog);
  const classes = opts.classes ?? loadClassCatalogFromDisk();
  const talents = opts.talents ?? loadTalentCatalogFromDisk(catalog, classes);
  const { db, requireAuth, requireInternal } = deps;
  const svc = (log: ServiceCtx["log"]): ServiceCtx => ({ catalog, limits, now: deps.now, log, quests, classes });

  // ----------------------------------------------------------- publico
  router.get("/v1/characters", requireAuth(async (ctx) => ok({ characters: await listCharacters(db, ctx.auth.accountId) })));

  router.post("/v1/characters", requireAuth(async (ctx) => {
    const body = objectBody(await ctx.json());
    for (const k of Object.keys(body)) if (k !== "name" && k !== "class_id") throw Errors.badRequest(`campo desconhecido "${k.slice(0, 40)}"`, "invalid_body");
    const name = validateCharacterName(body.name);
    const classId = validateClassId(body.class_id, classes);
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
    if (req.idempotency_key.startsWith("craft:")) throw Errors.badRequest("prefixo craft: e reservado ao endpoint /craft", "invalid_idempotency_key");
    if (req.idempotency_key.startsWith("talent:")) throw Errors.badRequest("prefixo talent: e reservado ao endpoint /talents", "invalid_idempotency_key");
    if (req.idempotency_key.startsWith("loot:")) {
      assertReservedKey(LOOT_KEY_RE, req.idempotency_key, ctx, id);
      if (req.xp !== 0 || req.items.length !== 1 || req.quest_id) throw Errors.badRequest("recompensa loot: paga exatamente um item e nenhum xp", "invalid_reward");
    }
    const out = await grantReward(db, svc(ctx.log), id, req);
    return ok({ replayed: out.replayed, result: out.result, character: internalView(out.character, limits) });
  }));

  router.post("/internal/characters/:id/craft", requireInternal(async (ctx) => {
    const id = uuidParam(ctx.params.id);
    await assertSessionHoldsLock(db, ctx, id);
    const body = objectBody(await ctx.json());
    for (const k of Object.keys(body)) if (k !== "idempotency_key" && k !== "recipe_id") throw Errors.badRequest(`campo desconhecido "${k.slice(0, 40)}"`, "invalid_body");
    const key = body.idempotency_key;
    if (typeof key !== "string" || key.length > 128) throw Errors.badRequest("idempotency_key invalida", "invalid_idempotency_key");
    assertReservedKey(CRAFT_KEY_RE, key, ctx, id);
    const rid = body.recipe_id;
    if (typeof rid !== "string" || !/^[a-z][a-z0-9_]{0,47}$/.test(rid)) throw Errors.badRequest("recipe_id invalido", "invalid_recipe");
    const recipe = recipes.get(rid);
    if (!recipe) throw Errors.badRequest("receita desconhecida", "unknown_recipe");
    const out = await craft(db, svc(ctx.log), id, key, recipe);
    return ok({ replayed: out.replayed, result: out.result, character: internalView(out.character, limits) });
  }));

  // E6.2: comandos de talentos (allocate / respec / choose_spec). Chave reservada talent:<sessao>:<n>:<personagem>.
  router.post("/internal/characters/:id/talents", requireInternal(async (ctx) => {
    const id = uuidParam(ctx.params.id);
    await assertSessionHoldsLock(db, ctx, id);
    const body = objectBody(await ctx.json());
    for (const k of Object.keys(body)) if (!["idempotency_key", "op", "arg", "expected_revision"].includes(k)) throw Errors.badRequest(`campo desconhecido "${k.slice(0, 40)}"`, "invalid_body");
    const key = body.idempotency_key;
    if (typeof key !== "string" || key.length > 128) throw Errors.badRequest("idempotency_key invalida", "invalid_idempotency_key");
    assertReservedKey(TALENT_KEY_RE, key, ctx, id);
    const op = body.op;
    if (typeof op !== "string" || !(TALENT_OPS as readonly string[]).includes(op)) throw Errors.badRequest("op invalida (allocate|respec|choose_spec)", "invalid_op");
    const arg = body.arg;
    if (op === "respec") {
      if (arg !== undefined && arg !== "") throw Errors.badRequest("respec nao leva arg", "invalid_arg");
    } else if (typeof arg !== "string" || !/^[a-z][a-z0-9_]{0,47}$/.test(arg)) {
      throw Errors.badRequest("arg invalido (id de no/especializacao)", "invalid_arg");
    }
    const exp = body.expected_revision;
    if (exp !== undefined && (typeof exp !== "number" || !Number.isSafeInteger(exp) || exp < 0)) throw Errors.badRequest("expected_revision deve ser inteiro >= 0", "invalid_body");
    const out = await applyTalentOp(db, svc(ctx.log), talents, id, { idempotency_key: key, op: op as TalentOp, arg: typeof arg === "string" ? arg : undefined, expected_revision: exp as number | undefined });
    return ok({ replayed: out.replayed, result: out.result, character: internalView(out.character, limits) });
  }));
}
