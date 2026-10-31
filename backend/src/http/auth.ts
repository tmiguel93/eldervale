import { timingSafeEqual } from "node:crypto";
import type { AuthedHandler, AuthVerifier, Handler } from "./context.ts";
import { Errors } from "./errors.ts";

function bearer(req: Request): string | null {
  const h = req.headers.get("authorization");
  if (!h) return null;
  const m = /^Bearer\s+(\S{1,4096})$/i.exec(h);
  return m ? m[1]! : null;
}

/**
 * Ponto de extensao de autenticacao de usuario: envolve um handler exigindo `Authorization: Bearer`.
 * O verificador e injetado (M2). Sem token ou token invalido => 401 padronizado.
 */
export function requireAuth(verify: AuthVerifier, handler: AuthedHandler): Handler {
  return async (ctx) => {
    const token = bearer(ctx.req);
    if (!token) throw Errors.unauthorized();
    const principal = await verify(token, ctx.req);
    if (!principal) throw Errors.unauthorized("Token invalido ou expirado");
    ctx.auth = principal;
    return handler(ctx as Parameters<AuthedHandler>[0]);
  };
}

/**
 * Autenticacao servico-a-servico (servidor Godot => /internal/*): `Authorization: Bearer <GAME_SESSION_INTERNAL_SECRET>`,
 * comparacao em tempo constante. Restricao de rede continua necessaria em producao (ARQ. 9).
 */
export function requireInternal(secret: string, handler: Handler): Handler {
  const expected = Buffer.from(secret);
  return async (ctx) => {
    const token = bearer(ctx.req);
    const given = Buffer.from(token ?? "");
    if (!token || given.length !== expected.length || !timingSafeEqual(given, expected)) {
      throw Errors.unauthorized("Credencial de servico invalida");
    }
    return handler(ctx);
  };
}
