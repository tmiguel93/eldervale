import { randomUUID } from "node:crypto";
import type { Config } from "../config.ts";
import type { Db } from "../persistence/db.ts";
import { hashRefreshToken, newRefreshToken, signAccessToken } from "./tokens.ts";

export interface SessionTokens {
  access_token: string;
  token_type: "Bearer";
  expires_in: number;
  refresh_token: string;
  refresh_expires_in: number;
}

const ts = (v: unknown): number => (v instanceof Date ? v.getTime() : new Date(String(v)).getTime());

/** Cria um refresh token (so o hash vai ao banco) e o access token correspondente. */
export async function issueSession(db: Db, config: Config, accountId: string, nowMs: number): Promise<SessionTokens> {
  const refresh = newRefreshToken();
  await insertRefresh(db, config, accountId, refresh, randomUUID(), nowMs);
  return {
    access_token: await signAccessToken(config, accountId, nowMs),
    token_type: "Bearer",
    expires_in: config.accessTokenTtlSeconds,
    refresh_token: refresh,
    refresh_expires_in: config.refreshTokenTtlSeconds,
  };
}

async function insertRefresh(db: Db, config: Config, accountId: string, token: string, id: string, nowMs: number): Promise<void> {
  await db.query(
    "INSERT INTO refresh_tokens (id, account_id, token_hash, expires_at, created_at) VALUES ($1, $2, $3, $4, $5)",
    [id, accountId, hashRefreshToken(token), new Date(nowMs + config.refreshTokenTtlSeconds * 1000), new Date(nowMs)],
  );
}

/**
 * Revoga o token `id` e todos os seus sucessores (cadeia de rotacao via replaced_by).
 * Antecessores ja estao revogados por construcao. UNION (sem ALL) protege de ciclos.
 */
async function revokeChain(db: Db, id: string, nowMs: number): Promise<void> {
  await db.query(
    `WITH RECURSIVE chain(id, replaced_by) AS (
       SELECT id, replaced_by FROM refresh_tokens WHERE id = $1
       UNION
       SELECT r.id, r.replaced_by FROM refresh_tokens r JOIN chain c ON r.id = c.replaced_by
     )
     UPDATE refresh_tokens SET revoked_at = $2 WHERE id IN (SELECT id FROM chain) AND revoked_at IS NULL`,
    [id, new Date(nowMs)],
  );
}

export type RotateOutcome =
  | { kind: "ok"; session: SessionTokens }
  | { kind: "invalid" }
  | { kind: "reuse" }
  | { kind: "expired" }
  | { kind: "disabled" };

interface RtRow {
  id: string;
  account_id: string;
  expires_at: unknown;
  revoked_at: unknown;
  replaced_by: string | null;
  disabled: boolean;
}

/**
 * Rotaciona o refresh token: o apresentado e revogado e substituido por um novo.
 * Token ja revogado/substituido reapresentado = REUSO => revoga a cadeia inteira (sucessores).
 * Linha travada com FOR UPDATE: duas requisicoes simultaneas com o mesmo token nao geram dois filhos
 * (a segunda ve o token ja substituido e e tratada como reuso, estrito por desenho).
 */
export async function rotateRefresh(db: Db, config: Config, presented: string, nowMs: number): Promise<RotateOutcome> {
  return db.tx(async (tx): Promise<RotateOutcome> => {
    const r = await tx.query<RtRow>(
      `SELECT rt.id, rt.account_id, rt.expires_at, rt.revoked_at, rt.replaced_by, a.disabled
         FROM refresh_tokens rt JOIN accounts a ON a.id = rt.account_id
        WHERE rt.token_hash = $1 FOR UPDATE OF rt`,
      [hashRefreshToken(presented)],
    );
    const row = r.rows[0];
    if (!row) return { kind: "invalid" };
    if (row.revoked_at !== null || row.replaced_by !== null) {
      await revokeChain(tx, row.id, nowMs);
      return { kind: "reuse" };
    }
    if (row.disabled) {
      await revokeChain(tx, row.id, nowMs);
      return { kind: "disabled" };
    }
    if (ts(row.expires_at) <= nowMs) return { kind: "expired" };

    const next = newRefreshToken();
    const nextId = randomUUID();
    await insertRefresh(tx, config, row.account_id, next, nextId, nowMs);
    await tx.query("UPDATE refresh_tokens SET revoked_at = $2, replaced_by = $3 WHERE id = $1", [row.id, new Date(nowMs), nextId]);
    return {
      kind: "ok",
      session: {
        access_token: await signAccessToken(config, row.account_id, nowMs),
        token_type: "Bearer",
        expires_in: config.accessTokenTtlSeconds,
        refresh_token: next,
        refresh_expires_in: config.refreshTokenTtlSeconds,
      },
    };
  });
}

/** Logout: revoga o token e seus sucessores. Idempotente; nao revela se o token existia. */
export async function revokeRefresh(db: Db, presented: string, nowMs: number): Promise<void> {
  await db.tx(async (tx) => {
    const r = await tx.query<{ id: string }>("SELECT id FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE", [hashRefreshToken(presented)]);
    if (r.rows[0]) await revokeChain(tx, r.rows[0].id, nowMs);
  });
}
