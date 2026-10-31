import { createHash, createHmac } from "node:crypto";
import { jwtVerify, SignJWT } from "jose";
import { isUuid } from "./validate.ts";

export const TICKET_ISSUER = "eldervale-backend";
export const TICKET_AUDIENCE = "eldervale-game-session";

/**
 * Chave HS256 do ticket = HMAC-SHA256(key = GAME_SESSION_INTERNAL_SECRET, msg = "eldervale/join-ticket/v1").
 * Separa o dominio de uso (a chave derivada nao e o segredo de /internal/* nem o AUTH_SECRET dos tokens de conta);
 * trocar a string de contexto invalida todos os tickets (rotacao).
 */
export function deriveTicketKey(internalSecret: string): Uint8Array {
  return new Uint8Array(createHmac("sha256", internalSecret).update("eldervale/join-ticket/v1").digest());
}

/** Somente o hash do jti e persistido (join_tickets.jti_hash). */
export const hashJti = (jti: string): string => createHash("sha256").update(jti).digest("hex");

export interface TicketClaims {
  jti: string;
  characterId: string;
  sessionId: string;
  /** exp em segundos epoch. */
  exp: number;
}

export async function signTicket(
  key: Uint8Array,
  a: { jti: string; characterId: string; sessionId: string; nowMs: number; ttlSeconds: number },
): Promise<{ token: string; exp: number }> {
  const iat = Math.floor(a.nowMs / 1000);
  const exp = iat + a.ttlSeconds;
  const token = await new SignJWT({ sid: a.sessionId })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setJti(a.jti)
    .setSubject(a.characterId)
    .setIssuer(TICKET_ISSUER)
    .setAudience(TICKET_AUDIENCE)
    .setIssuedAt(iat)
    .setExpirationTime(exp)
    .sign(key);
  return { token, exp };
}

/** Devolve as claims ou null (assinatura, expiracao, aud/iss, formato: sem distinguir o motivo). */
export async function verifyTicket(key: Uint8Array, token: string, nowMs: number): Promise<TicketClaims | null> {
  try {
    const { payload } = await jwtVerify(token, key, {
      algorithms: ["HS256"],
      issuer: TICKET_ISSUER,
      audience: TICKET_AUDIENCE,
      currentDate: new Date(nowMs),
      requiredClaims: ["jti", "sub", "exp", "sid"],
    });
    const { jti, sub, sid, exp } = payload as { jti?: unknown; sub?: unknown; sid?: unknown; exp?: unknown };
    if (typeof jti !== "string" || jti.length > 64 || !isUuid(sub) || !isUuid(sid) || typeof exp !== "number") return null;
    return { jti, characterId: sub.toLowerCase(), sessionId: sid.toLowerCase(), exp };
  } catch {
    return null;
  }
}
