import { createHash, randomBytes } from "node:crypto";
import { jwtVerify, SignJWT } from "jose";
import { randomUUID } from "node:crypto";
import type { Config } from "../config.ts";

/** iss/aud FIXOS. Outros JWT do sistema (join ticket) devem usar `aud` diferente. */
export const ACCESS_ISS = "eldervale-api";
export const ACCESS_AUD = "eldervale-access";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const isUuid = (s: unknown): s is string => typeof s === "string" && UUID_RE.test(s);

const key = (config: Config) => new TextEncoder().encode(config.authSecret);

export async function signAccessToken(config: Config, accountId: string, nowMs: number): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(accountId)
    .setIssuer(ACCESS_ISS)
    .setAudience(ACCESS_AUD)
    .setIssuedAt(iat)
    .setExpirationTime(iat + config.accessTokenTtlSeconds)
    .setJti(randomUUID())
    .sign(key(config));
}

/** Devolve o `sub` (UUID) ou null para qualquer defeito (assinatura, alg, iss, aud, exp, formato). */
export async function verifyAccessToken(config: Config, token: string, nowMs: number): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, key(config), {
      algorithms: ["HS256"],
      issuer: ACCESS_ISS,
      audience: ACCESS_AUD,
      currentDate: new Date(nowMs),
      requiredClaims: ["sub", "iat", "exp", "jti"],
    });
    return isUuid(payload.sub) ? payload.sub : null;
  } catch {
    return null;
  }
}

/** 256 bits de entropia, base64url (43 caracteres). */
export const newRefreshToken = () => randomBytes(32).toString("base64url");
export const hashRefreshToken = (t: string) => createHash("sha256").update(t).digest("hex");
