import { createHash } from "node:crypto";
import type { RouteDeps } from "../http/app.ts";
import { Errors } from "../http/errors.ts";
import { RateLimiter } from "../http/rate-limit.ts";
import { json } from "../http/respond.ts";
import type { Router } from "../http/router.ts";
import { dummyPasswordHash, hashPassword, passwordNeedsRehash, verifyPassword } from "./password.ts";
import { issueSession, revokeRefresh, rotateRefresh } from "./service.ts";
import { readEmail, readLoginPassword, readNewPassword, readRefreshToken } from "./validate.ts";
import { ApiError } from "../http/errors.ts";

export interface BucketLimit {
  /** Rajada maxima. */
  capacity: number;
  /** Tokens repostos por segundo. */
  refillPerSecond: number;
}

export interface AuthLimits {
  loginIp: BucketLimit;
  loginEmail: BucketLimit;
  registerIp: BucketLimit;
  registerEmail: BucketLimit;
  refreshIp: BucketLimit;
}

/** Padroes: generosos para uso legitimo, curtos o bastante para frear forca bruta. */
export const DEFAULT_AUTH_LIMITS: AuthLimits = {
  loginIp: { capacity: 100, refillPerSecond: 2 },
  loginEmail: { capacity: 10, refillPerSecond: 1 / 6 }, // 10 de rajada, depois 10/min
  registerIp: { capacity: 30, refillPerSecond: 0.1 },
  registerEmail: { capacity: 3, refillPerSecond: 1 / 60 },
  refreshIp: { capacity: 60, refillPerSecond: 1 },
};

const NO_STORE = { "cache-control": "no-store" };
const reply = (status: number, data: unknown) => json(status, data, NO_STORE);
const invalidCredentials = () => new ApiError(401, "invalid_credentials", "E-mail ou senha invalidos", { "www-authenticate": "Bearer" });
/** E-mail nunca fica em memoria/chave em claro: usa-se o digest. */
const emailKey = (email: string) => createHash("sha256").update(email).digest("hex").slice(0, 32);

export function registerAuthRoutes(router: Router, deps: RouteDeps): void {
  createAuthRoutes(router, deps);
}

export function createAuthRoutes(router: Router, deps: RouteDeps, limits: AuthLimits = DEFAULT_AUTH_LIMITS): void {
  const { db, config, now, log } = deps;
  const mk = (l: BucketLimit) => new RateLimiter({ capacity: l.capacity, refillPerSecond: l.refillPerSecond, now });
  const loginIp = mk(limits.loginIp);
  const loginEmail = mk(limits.loginEmail);
  const registerIp = mk(limits.registerIp);
  const registerEmail = mk(limits.registerEmail);
  const refreshIp = mk(limits.refreshIp);

  const limit = (rl: RateLimiter, key: string) => {
    const r = rl.take(key);
    if (!r.allowed) throw Errors.tooManyRequests(r.retryAfterMs / 1000);
  };

  // Resposta identica exista ou nao o e-mail (202 sem tokens); o cliente entao faz login.
  router.post("/v1/auth/register", async (ctx) => {
    limit(registerIp, deps.clientIp(ctx.req));
    const body = await ctx.json();
    const email = readEmail(body);
    const password = readNewPassword(body, email);
    limit(registerEmail, emailKey(email));
    // Hash SEMPRE (mesmo custo se o e-mail ja existe).
    const passwordHash = await hashPassword(password);
    const r = await db.query<{ id: string }>(
      "INSERT INTO accounts (email, password_hash, created_at) VALUES ($1, $2, $3) ON CONFLICT (email) DO NOTHING RETURNING id",
      [email, passwordHash, new Date(now())],
    );
    ctx.log.info("auth_register", { created: r.rows.length === 1, account_id: r.rows[0]?.id });
    return reply(202, { status: "accepted" });
  });

  router.post("/v1/auth/login", async (ctx) => {
    limit(loginIp, deps.clientIp(ctx.req));
    const body = await ctx.json();
    const email = readEmail(body);
    const password = readLoginPassword(body);
    limit(loginEmail, emailKey(email));

    const r = await db.query<{ id: string; password_hash: string; disabled: boolean }>(
      "SELECT id, password_hash, disabled FROM accounts WHERE email = $1",
      [email],
    );
    const acc = r.rows[0];
    // Sem conta: verifica contra hash descartavel para igualar o tempo.
    const okPw = await verifyPassword(password, acc ? acc.password_hash : await dummyPasswordHash());
    if (!acc || !okPw || acc.disabled) {
      ctx.log.warn("auth_login_failed", { reason: !acc ? "no_account" : !okPw ? "bad_password" : "disabled" });
      throw invalidCredentials();
    }
    if (passwordNeedsRehash(acc.password_hash)) {
      await db.query("UPDATE accounts SET password_hash = $2 WHERE id = $1", [acc.id, await hashPassword(password)]);
    }
    const session = await issueSession(db, config, acc.id, now());
    ctx.log.info("auth_login_ok", { account_id: acc.id });
    return reply(200, session);
  });

  router.post("/v1/auth/refresh", async (ctx) => {
    limit(refreshIp, deps.clientIp(ctx.req));
    const token = readRefreshToken(await ctx.json());
    const out = await rotateRefresh(db, config, token, now());
    if (out.kind === "ok") return reply(200, out.session);
    if (out.kind === "reuse") ctx.log.warn("auth_refresh_reuse_detected");
    else ctx.log.info("auth_refresh_rejected", { reason: out.kind });
    throw Errors.unauthorized("Refresh token invalido ou expirado");
  });

  router.post("/v1/auth/logout", async (ctx) => {
    limit(refreshIp, deps.clientIp(ctx.req));
    const token = readRefreshToken(await ctx.json());
    await revokeRefresh(db, token, now());
    return new Response(null, { status: 204, headers: NO_STORE });
  });

  router.get(
    "/v1/account",
    deps.requireAuth(async (ctx) => {
      const r = await db.query<{ id: string; email: string; created_at: unknown }>(
        "SELECT id, email, created_at FROM accounts WHERE id = $1",
        [ctx.auth.accountId],
      );
      const a = r.rows[0];
      if (!a) throw Errors.unauthorized("Token invalido ou expirado");
      const created = a.created_at instanceof Date ? a.created_at.toISOString() : String(a.created_at);
      return reply(200, { id: a.id, email: a.email, created_at: created });
    }),
  );
}
