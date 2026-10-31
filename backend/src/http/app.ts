import { randomUUID } from "node:crypto";
import type { Config } from "../config.ts";
import type { Db } from "../persistence/db.ts";
import { requireAuth, requireInternal } from "./auth.ts";
import type { AuthedHandler, AuthVerifier, Handler, RequestContext } from "./context.ts";
import { ApiError, Errors } from "./errors.ts";
import type { Logger } from "./logger.ts";
import { clientIp } from "./rate-limit.ts";
import { errorBody, json, SECURITY_HEADERS } from "./respond.ts";
import { Router } from "./router.ts";

/** O que os modulos de rota (M2-M4) recebem em `registerXRoutes(router, deps)`. */
export interface RouteDeps {
  config: Config;
  db: Db;
  log: Logger;
  /** Relogio injetavel (ms epoch) para testes deterministas. */
  now: () => number;
  /** Envolve o handler exigindo Bearer valido (ctx.auth garantido). */
  requireAuth: (handler: AuthedHandler) => Handler;
  /** Envolve o handler exigindo o segredo servico-a-servico (para /internal/*). */
  requireInternal: (handler: Handler) => Handler;
  /** IP do cliente para chaves de RateLimiter. */
  clientIp: (req: Request) => string;
}

export interface AppDeps {
  config: Config;
  db: Db;
  log: Logger;
  authVerifier: AuthVerifier;
  /** Registra rotas. Padrao do projeto: `registerRoutes` de src/routes.ts. */
  register: (router: Router, deps: RouteDeps) => void;
  now?: () => number;
}

export interface App {
  handle(req: Request): Promise<Response>;
}

const REQUEST_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const BODY_METHODS = new Set(["POST", "PUT", "PATCH"]);

export function createApp(deps: AppDeps): App {
  const now = deps.now ?? Date.now;
  const router = new Router();
  const routeDeps: RouteDeps = {
    config: deps.config,
    db: deps.db,
    log: deps.log,
    now,
    requireAuth: (h) => requireAuth(deps.authVerifier, h),
    requireInternal: (h) => requireInternal(deps.config.gameSessionInternalSecret, h),
    clientIp: (req) => clientIp(req, deps.config.trustProxy),
  };
  deps.register(router, routeDeps);
  const maxBody = deps.config.maxBodyBytes;

  async function readJson(req: Request): Promise<unknown> {
    if (!req.body) throw Errors.badRequest("Corpo JSON obrigatorio", "invalid_json");
    const reader = req.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBody) {
        await reader.cancel().catch(() => {});
        throw new ApiError(413, "payload_too_large", "Corpo da requisicao grande demais");
      }
      chunks.push(value);
    }
    const text = Buffer.concat(chunks).toString("utf8");
    try {
      return JSON.parse(text);
    } catch {
      throw Errors.badRequest("JSON invalido", "invalid_json");
    }
  }

  async function dispatch(req: Request, ctx: RequestContext): Promise<Response> {
    const m = router.match(req.method, ctx.url.pathname);
    if (m.kind === "not_found") throw new ApiError(404, "not_found", "Rota nao encontrada");
    if (m.kind === "method_not_allowed") {
      throw new ApiError(405, "method_not_allowed", "Metodo nao permitido", { allow: m.allow.join(", ") });
    }
    if (BODY_METHODS.has(req.method) && req.body) {
      const len = req.headers.get("content-length");
      if (len !== null && Number(len) > maxBody) {
        throw new ApiError(413, "payload_too_large", "Corpo da requisicao grande demais");
      }
      const ct = (req.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
      if (ct !== "application/json") {
        throw new ApiError(415, "unsupported_media_type", "Content-Type deve ser application/json");
      }
    }
    ctx.params = m.params;
    return m.handler(ctx);
  }

  return {
    async handle(req: Request): Promise<Response> {
      const started = now();
      const incoming = req.headers.get("x-request-id");
      const requestId = incoming && REQUEST_ID_RE.test(incoming) ? incoming : randomUUID();
      const url = new URL(req.url);
      const log = deps.log.child({ request_id: requestId });
      let cached: Promise<unknown> | undefined;
      const ctx = {
        req,
        url,
        params: {},
        requestId,
        log,
        json: <T>() => (cached ??= readJson(req)) as Promise<T>,
      } as RequestContext;

      let res: Response;
      try {
        res = await dispatch(req, ctx);
      } catch (e) {
        if (e instanceof ApiError) {
          res = json(e.status, errorBody(e.code, e.message), e.headers);
        } else {
          // Nunca vaza detalhes/stack ao cliente; o log recebe nome+mensagem redigidos.
          log.error("unhandled_error", { error: e });
          res = json(500, errorBody("internal_error", "Erro interno"));
        }
      }

      const headers = new Headers(res.headers);
      for (const [k, v] of Object.entries(SECURITY_HEADERS)) headers.set(k, v);
      headers.set("x-request-id", requestId);
      log.info("request", { method: req.method, path: url.pathname, status: res.status, duration_ms: now() - started });
      return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
    },
  };
}
