import type { RouteDeps } from "../http/app.ts";
import { created, ok } from "../http/respond.ts";
import type { Router } from "../http/router.ts";
import { bodyObject, uuid } from "../sessions/validate.ts";
import { createPartiesService, partiesOptionsFromEnv, type PartiesOptions } from "./service.ts";

/**
 * Party (M4). Todas as rotas exigem Bearer de usuario. Recurso alheio => 404 (nao revela existencia).
 * `opts` opcional (testes); por padrao le PARTY_INVITE_TTL_SECONDS do ambiente.
 */
export function registerPartiesRoutes(router: Router, deps: RouteDeps, opts?: PartiesOptions): void {
  const svc = createPartiesService({ db: deps.db, now: deps.now }, opts ?? partiesOptionsFromEnv());

  router.post("/v1/parties", deps.requireAuth(async (ctx) => {
    const body = bodyObject(await ctx.json());
    const party = await svc.create(ctx.auth.accountId, uuid(body.character_id, "character_id"));
    return created({ party });
  }));

  router.get("/v1/parties/:id", deps.requireAuth(async (ctx) => {
    const party = await svc.get(ctx.auth.accountId, uuid(ctx.params.id, "id"));
    return ok({ party });
  }));

  router.post("/v1/parties/:id/invites", deps.requireAuth(async (ctx) => {
    const partyId = uuid(ctx.params.id, "id");
    const body = bodyObject(await ctx.json());
    const invite = await svc.invite(ctx.auth.accountId, partyId, uuid(body.target_character_id, "target_character_id"));
    return created({ invite });
  }));

  router.post("/v1/parties/:id/join", deps.requireAuth(async (ctx) => {
    const partyId = uuid(ctx.params.id, "id");
    const body = bodyObject(await ctx.json());
    const party = await svc.join(ctx.auth.accountId, partyId, uuid(body.invite_id, "invite_id"), uuid(body.character_id, "character_id"));
    return ok({ party });
  }));

  router.post("/v1/parties/:id/leave", deps.requireAuth(async (ctx) => {
    const res = await svc.leave(ctx.auth.accountId, uuid(ctx.params.id, "id"));
    return ok(res);
  }));

  router.post("/v1/parties/:id/kick", deps.requireAuth(async (ctx) => {
    const partyId = uuid(ctx.params.id, "id");
    const body = bodyObject(await ctx.json());
    await svc.kick(ctx.auth.accountId, partyId, uuid(body.character_id, "character_id"));
    return ok({ ok: true });
  }));
}
