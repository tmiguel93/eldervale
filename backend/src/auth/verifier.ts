import type { RouteDeps } from "../http/app.ts";
import type { AuthVerifier } from "../http/context.ts";
import { verifyAccessToken } from "./tokens.ts";

/**
 * Verificador do access token (JWT HS256). Devolve null para token invalido/expirado/adulterado/alg none
 * e para conta inexistente ou desabilitada (consulta ao banco a cada chamada: revogacao imediata).
 * So lanca em falha de infraestrutura (banco).
 */
export function createAuthVerifier(deps: Pick<RouteDeps, "config" | "db" | "now">): AuthVerifier {
  return async (token) => {
    const sub = await verifyAccessToken(deps.config, token, deps.now());
    if (!sub) return null;
    const r = await deps.db.query<{ disabled: boolean }>("SELECT disabled FROM accounts WHERE id = $1", [sub]);
    if (r.rows.length === 0 || r.rows[0]!.disabled) return null;
    return { accountId: sub };
  };
}
