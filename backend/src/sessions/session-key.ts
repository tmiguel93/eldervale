import { createHmac, timingSafeEqual } from "node:crypto";
import type { Config } from "../config.ts";
import { Errors } from "../http/errors.ts";

/**
 * Chave por sessao (M5). Sem estado nem migracao: key = HMAC-SHA256(GAME_SESSION_INTERNAL_SECRET, "eldervale/session-key/v1:" + session_id).
 * O backend a devolve UMA vez em `POST /internal/sessions` (campo `session_key`); o servidor Godot a envia em `X-Session-Key`
 * nas rotas /internal ligadas a sessao. Um servidor que so conhece a sessao A nao consegue agir na sessao B (heartbeat, close,
 * resgate de ticket, checkpoint, recompensa), mesmo que um segredo vaze entre servidores. Dominio separado do ticket e do segredo interno.
 */
export function deriveSessionKey(internalSecret: string, sessionId: string): string {
  return createHmac("sha256", internalSecret).update(`eldervale/session-key/v1:${sessionId.toLowerCase()}`).digest("base64url");
}

export const SESSION_KEY_HEADER = "x-session-key";

/**
 * Confere `X-Session-Key` contra a sessao. Presente e errada => 403 sempre. Ausente => 403 se `requireSessionKey`
 * (padrao em production), senao aceita (compatibilidade com clientes anteriores ao E7.1).
 */
export function assertSessionKey(config: Pick<Config, "gameSessionInternalSecret" | "requireSessionKey">, req: Request, sessionId: string): void {
  const given = req.headers.get(SESSION_KEY_HEADER);
  if (given === null || given === "") {
    if (config.requireSessionKey) throw Errors.forbidden("X-Session-Key obrigatorio");
    return;
  }
  const want = Buffer.from(deriveSessionKey(config.gameSessionInternalSecret, sessionId));
  const got = Buffer.from(given);
  if (got.length !== want.length || !timingSafeEqual(got, want)) throw Errors.forbidden("X-Session-Key invalida");
}
