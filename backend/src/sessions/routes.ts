import type { RouteDeps } from "../http/app.ts";
import { Errors } from "../http/errors.ts";
import { created, ok } from "../http/respond.ts";
import type { Router } from "../http/router.ts";
import { createSessionsService, sessionsOptionsFromEnv, type SessionsOptions } from "./service.ts";
import { bodyObject, intField, strField, uuid } from "./validate.ts";

const REGION_RE = /^[a-z0-9][a-z0-9-]{1,31}$/;
const ENDPOINT_RE = /^[A-Za-z0-9.-]{1,253}:\d{1,5}$/;

/**
 * Sessoes de jogo, join tickets, locks e reconexao (M4).
 * /v1/* exige Bearer de usuario; /internal/* exige GAME_SESSION_INTERNAL_SECRET.
 * `opts` opcional (testes); por padrao le SESSION_HEARTBEAT_TIMEOUT_SECONDS do ambiente.
 */
export function registerSessionsRoutes(router: Router, deps: RouteDeps, opts?: SessionsOptions): void {
  const svc = createSessionsService({ db: deps.db, config: deps.config, now: deps.now }, opts ?? sessionsOptionsFromEnv());

  router.post("/internal/sessions", deps.requireInternal(async (ctx) => {
    const b = bodyObject(await ctx.json());
    const endpoint = strField(b.endpoint, "endpoint", ENDPOINT_RE, 300);
    const port = Number(endpoint.slice(endpoint.lastIndexOf(":") + 1));
    if (port < 1 || port > 65535) throw Errors.badRequest("Campo invalido: endpoint", "validation_error");
    const res = await svc.register({
      region: strField(b.region, "region", REGION_RE, 32),
      capacity: intField(b.capacity, "capacity", 1, 64),
      protocolVersion: intField(b.protocol_version, "protocol_version", 1, 1_000_000),
      endpoint,
    });
    return created(res);
  }));

  router.post("/internal/sessions/:id/heartbeat", deps.requireInternal(async (ctx) => ok(await svc.heartbeat(uuid(ctx.params.id, "id")))));
  router.post("/internal/sessions/:id/close", deps.requireInternal(async (ctx) => ok(await svc.close(uuid(ctx.params.id, "id")))));

  router.get("/v1/sessions", deps.requireAuth(async (ctx) => {
    const raw = ctx.url.searchParams.get("region");
    const region = raw === null ? null : strField(raw, "region", REGION_RE, 32);
    return ok(await svc.list(ctx.auth.accountId, region));
  }));

  router.post("/v1/sessions/:id/join-ticket", deps.requireAuth(async (ctx) => {
    const sessionId = uuid(ctx.params.id, "id");
    const b = bodyObject(await ctx.json());
    const res = await svc.issueTicket(ctx.auth.accountId, sessionId, uuid(b.character_id, "character_id"));
    return created(res);
  }));

  router.post("/internal/tickets/redeem", deps.requireInternal(async (ctx) => {
    const b = bodyObject(await ctx.json());
    const ticket = strField(b.ticket, "ticket", /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/, 2048);
    return ok(await svc.redeem(ticket, uuid(b.session_id, "session_id")));
  }));

  router.post("/internal/characters/:id/disconnect", deps.requireInternal(async (ctx) => {
    const characterId = uuid(ctx.params.id, "id");
    const b = bodyObject(await ctx.json());
    return ok(await svc.disconnect(characterId, uuid(b.session_id, "session_id")));
  }));

  router.post("/internal/characters/:id/release", deps.requireInternal(async (ctx) => {
    const characterId = uuid(ctx.params.id, "id");
    const b = bodyObject(await ctx.json());
    return ok(await svc.release(characterId, uuid(b.session_id, "session_id")));
  }));
}
