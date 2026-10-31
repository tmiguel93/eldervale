import { randomUUID } from "node:crypto";
import type { Config } from "../config.ts";
import { Errors } from "../http/errors.ts";
import { RateLimiter } from "../http/rate-limit.ts";
import { isUniqueViolation, type Db } from "../persistence/db.ts";
import { deriveTicketKey, hashJti, signTicket, verifyTicket } from "./ticket.ts";
import { iso, toIso } from "./validate.ts";

/** Versoes do protocolo de rede aceitas (shared/contracts/network_protocol.md: PROTOCOL_VERSION = 1). */
export const SUPPORTED_PROTOCOL_VERSIONS: readonly number[] = [1, 2]; // 2 = protocolo de rede v2 (c_hello com ticket); 1 mantido só para os testes do backend

export interface SessionsOptions {
  /** Sem heartbeat por mais que isto, os locks do servidor expiram (lazy). */
  heartbeatTimeoutSeconds: number;
  supportedProtocolVersions: readonly number[];
  ticketRateCapacity: number;
  ticketRefillPerSecond: number;
  listRateCapacity: number;
  listRefillPerSecond: number;
}

export const DEFAULT_SESSIONS_OPTIONS: SessionsOptions = {
  heartbeatTimeoutSeconds: 30,
  supportedProtocolVersions: SUPPORTED_PROTOCOL_VERSIONS,
  ticketRateCapacity: 10,
  ticketRefillPerSecond: 0.5,
  listRateCapacity: 20,
  listRefillPerSecond: 1,
};

/** SESSION_HEARTBEAT_TIMEOUT_SECONDS (5..3600, padrao 30). */
export function sessionsOptionsFromEnv(env: Record<string, string | undefined> = process.env): SessionsOptions {
  const raw = env.SESSION_HEARTBEAT_TIMEOUT_SECONDS?.trim();
  if (!raw) return DEFAULT_SESSIONS_OPTIONS;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 5 || n > 3600) throw new Error("SESSION_HEARTBEAT_TIMEOUT_SECONDS invalido (5..3600)");
  return { ...DEFAULT_SESSIONS_OPTIONS, heartbeatTimeoutSeconds: n };
}

interface Deps {
  db: Db;
  config: Pick<Config, "gameSessionInternalSecret" | "joinTicketTtlSeconds" | "reconnectWindowSeconds">;
  now: () => number;
}

/**
 * Lock "ativo" (alias l = character_locks, s = game_sessions; $nowP/$staleP sao placeholders):
 * heartbeat recente E fora de janela de reconexao vencida E sessao nao encerrada. Resolvido "lazy" na consulta.
 */
const activeLock = (nowP: string, staleP: string): string =>
  `(l.heartbeat_at > ${staleP}::timestamptz AND (l.reconnect_until IS NULL OR l.reconnect_until > ${nowP}::timestamptz)
    AND s.closed_at IS NULL AND s.status IN ('starting','open','full') AND s.heartbeat_at > ${staleP}::timestamptz)`;

const unauthorizedTicket = () => Errors.unauthorized("Ticket invalido");

export function createSessionsService(deps: Deps, opts: SessionsOptions = DEFAULT_SESSIONS_OPTIONS) {
  const { db, config } = deps;
  const key = deriveTicketKey(config.gameSessionInternalSecret);
  const limiter = new RateLimiter({ capacity: opts.ticketRateCapacity, refillPerSecond: opts.ticketRefillPerSecond, now: deps.now });
  const listLimiter = new RateLimiter({ capacity: opts.listRateCapacity, refillPerSecond: opts.listRefillPerSecond, now: deps.now });
  const nowIso = () => toIso(deps.now());
  const staleIso = () => toIso(deps.now() - opts.heartbeatTimeoutSeconds * 1000);

  async function ownedCharacter(q: Db, accountId: string, characterId: string): Promise<void> {
    const r = await q.query("SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL", [characterId, accountId]);
    if (r.rows.length === 0) throw Errors.notFound("Personagem nao encontrado");
  }

  /** Locks ativos na sessao, excluindo o proprio personagem. */
  async function activeCount(q: Db, sessionId: string, exceptCharacterId: string): Promise<number> {
    const r = await q.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM character_locks l JOIN game_sessions s ON s.id=l.session_id
        WHERE l.session_id=$1 AND l.character_id<>$2 AND ${activeLock("$3", "$4")}`,
      [sessionId, exceptCharacterId, nowIso(), staleIso()],
    );
    return r.rows[0]!.n;
  }

  interface LockState { session_id: string; reconnect_until: unknown; active: boolean }
  async function lockState(q: Db, characterId: string, forUpdate: boolean): Promise<LockState | undefined> {
    const r = await q.query<LockState>(
      `SELECT l.session_id, l.reconnect_until, ${activeLock("$2", "$3")} AS active
         FROM character_locks l JOIN game_sessions s ON s.id=l.session_id
        WHERE l.character_id=$1 ${forUpdate ? "FOR UPDATE OF l" : ""}`,
      [characterId, nowIso(), staleIso()],
    );
    return r.rows[0];
  }

  return {
    // ------------------------------------------------------------- servidor de sessao (interno)
    async register(a: { region: string; capacity: number; protocolVersion: number; endpoint: string }) {
      if (!opts.supportedProtocolVersions.includes(a.protocolVersion)) {
        throw Errors.badRequest("Versao de protocolo nao suportada", "unsupported_protocol");
      }
      const r = await db.query<{ id: string }>(
        `INSERT INTO game_sessions (region, status, capacity, protocol_version, endpoint, created_at, heartbeat_at)
         VALUES ($1,'open',$2,$3,$4,$5::timestamptz,$5::timestamptz) RETURNING id`,
        [a.region, a.capacity, a.protocolVersion, a.endpoint, nowIso()],
      );
      return {
        session_id: r.rows[0]!.id,
        status: "open",
        heartbeat_timeout_seconds: opts.heartbeatTimeoutSeconds,
        reconnect_window_seconds: config.reconnectWindowSeconds,
      };
    },

    async heartbeat(sessionId: string) {
      return db.tx(async (t) => {
        const s = await t.query<{ closed_at: unknown; status: string }>("SELECT closed_at, status FROM game_sessions WHERE id=$1 FOR UPDATE", [sessionId]);
        const row = s.rows[0];
        if (!row) throw Errors.notFound("Sessao nao encontrada");
        if (row.closed_at !== null || row.status === "closed") throw Errors.conflict("Sessao encerrada", "session_closed");
        await t.query("UPDATE game_sessions SET heartbeat_at=$2::timestamptz WHERE id=$1", [sessionId, nowIso()]);
        const u = await t.query(
          "UPDATE character_locks SET heartbeat_at=$2::timestamptz WHERE session_id=$1 AND (reconnect_until IS NULL OR reconnect_until > $2::timestamptz)",
          [sessionId, nowIso()],
        );
        return { session_id: sessionId, status: row.status, heartbeat_at: nowIso(), locks_refreshed: u.rowCount };
      });
    },

    async close(sessionId: string) {
      return db.tx(async (t) => {
        const s = await t.query<{ closed_at: unknown }>("SELECT closed_at FROM game_sessions WHERE id=$1 FOR UPDATE", [sessionId]);
        const row = s.rows[0];
        if (!row) throw Errors.notFound("Sessao nao encontrada");
        if (row.closed_at === null) {
          await t.query("UPDATE game_sessions SET status='closed', closed_at=$2::timestamptz WHERE id=$1", [sessionId, nowIso()]);
        }
        const d = await t.query("DELETE FROM character_locks WHERE session_id=$1", [sessionId]);
        return { session_id: sessionId, status: "closed", locks_released: d.rowCount };
      });
    },

    /** Sessoes abertas, vivas e com vaga (max 50), da mais vazia para a mais cheia. */
    async list(accountId: string, region: string | null) {
      const rl = listLimiter.take(`session-list:acct:${accountId}`);
      if (!rl.allowed) throw Errors.tooManyRequests(rl.retryAfterMs / 1000);
      const r = await db.query<{ id: string; region: string; capacity: number; protocol_version: number; endpoint: string | null; used: number }>(
        `SELECT s.id, s.region, s.capacity, s.protocol_version, s.endpoint,
                (SELECT count(*)::int FROM character_locks l WHERE l.session_id=s.id AND ${activeLock("$1", "$2")}) AS used
           FROM game_sessions s
          WHERE s.closed_at IS NULL AND s.status IN ('starting','open','full') AND s.heartbeat_at > $2::timestamptz
            AND s.endpoint IS NOT NULL AND s.protocol_version = ANY($3::int[]) AND ($4::text IS NULL OR s.region = $4)
          ORDER BY s.created_at, s.id`,
        [nowIso(), staleIso(), [...opts.supportedProtocolVersions], region],
      );
      const sessions = r.rows
        .filter((x) => x.capacity - x.used > 0)
        .slice(0, 50)
        .map((x) => ({ id: x.id, region: x.region, capacity: x.capacity, free_slots: x.capacity - x.used, protocol_version: x.protocol_version, endpoint: x.endpoint }));
      return { sessions };
    },

    // ----------------------------------------------------------------------- join ticket
    async issueTicket(accountId: string, sessionId: string, characterId: string) {
      const rl = limiter.take(`join-ticket:acct:${accountId}`);
      if (!rl.allowed) throw Errors.tooManyRequests(rl.retryAfterMs / 1000);
      return db.tx(async (t) => {
        await ownedCharacter(t, accountId, characterId);
        const s = await t.query<{ region: string; status: string; capacity: number; protocol_version: number; endpoint: string | null; closed_at: unknown; alive: boolean }>(
          "SELECT region, status, capacity, protocol_version, endpoint, closed_at, (heartbeat_at > $2::timestamptz) AS alive FROM game_sessions WHERE id=$1",
          [sessionId, staleIso()],
        );
        const session = s.rows[0];
        if (!session) throw Errors.notFound("Sessao nao encontrada");
        if (session.closed_at !== null || !session.alive || !["starting", "open", "full"].includes(session.status)) {
          throw Errors.conflict("Sessao indisponivel", "session_unavailable");
        }
        if (!opts.supportedProtocolVersions.includes(session.protocol_version)) {
          throw Errors.conflict("Versao de protocolo da sessao nao suportada", "unsupported_protocol");
        }
        const lock = await lockState(t, characterId, false);
        if (lock?.active) {
          if (lock.session_id !== sessionId) throw Errors.conflict("Personagem ja esta em outra sessao", "character_locked");
          if (lock.reconnect_until === null) throw Errors.conflict("Personagem ja esta conectado nesta sessao", "character_already_connected");
        }
        if ((await activeCount(t, sessionId, characterId)) >= session.capacity) throw Errors.conflict("Sessao cheia", "session_full");

        // Party: se algum companheiro ja esta ativo em alguma sessao e nenhum esta NESTA, recusa.
        const mates = await t.query<{ session_id: string }>(
          `SELECT DISTINCT l.session_id
             FROM party_members me
             JOIN party_members m ON m.party_id=me.party_id AND m.character_id<>me.character_id
             JOIN character_locks l ON l.character_id=m.character_id
             JOIN game_sessions s ON s.id=l.session_id
            WHERE me.character_id=$1 AND ${activeLock("$2", "$3")}`,
          [characterId, nowIso(), staleIso()],
        );
        if (mates.rows.length > 0 && !mates.rows.some((x) => x.session_id === sessionId)) {
          throw Errors.conflict("Sua party esta em outra sessao", "party_in_other_session");
        }

        const jti = randomUUID();
        const { token, exp } = await signTicket(key, { jti, characterId, sessionId, nowMs: deps.now(), ttlSeconds: config.joinTicketTtlSeconds });
        const expiresAt = toIso(exp * 1000);
        await t.query(
          "INSERT INTO join_tickets (jti_hash, character_id, session_id, expires_at, created_at) VALUES ($1,$2,$3,$4::timestamptz,$5::timestamptz)",
          [hashJti(jti), characterId, sessionId, expiresAt, nowIso()],
        );
        return {
          ticket: token,
          expires_at: expiresAt,
          character_id: characterId,
          session: { id: sessionId, region: session.region, endpoint: session.endpoint, protocol_version: session.protocol_version },
        };
      });
    },

    // ------------------------------------------------------------------------- resgate
    async redeem(ticket: string, sessionId: string) {
      const claims = await verifyTicket(key, ticket, deps.now());
      // Assinatura/exp/aud invalidos OU ticket de outra sessao: mesma resposta, sem detalhes.
      if (!claims || claims.sessionId !== sessionId) throw unauthorizedTicket();
      const jtiHash = hashJti(claims.jti);
      try {
        return await db.tx(async (t) => {
          // Serializa resgates/capacidade por sessao.
          const s = await t.query<{ capacity: number; status: string; closed_at: unknown; alive: boolean }>(
            "SELECT capacity, status, closed_at, (heartbeat_at > $2::timestamptz) AS alive FROM game_sessions WHERE id=$1 FOR UPDATE",
            [sessionId, staleIso()],
          );
          const session = s.rows[0];
          if (!session) throw unauthorizedTicket();
          if (session.closed_at !== null || !session.alive || !["starting", "open", "full"].includes(session.status)) {
            throw Errors.conflict("Sessao indisponivel", "session_unavailable");
          }
          // Uso unico ATOMICO: so um UPDATE condicional pode vencer.
          const upd = await t.query(
            `UPDATE join_tickets SET used_at=$4::timestamptz
              WHERE jti_hash=$1 AND session_id=$2 AND character_id=$3 AND used_at IS NULL AND expires_at > $4::timestamptz
              RETURNING id`,
            [jtiHash, sessionId, claims.characterId, nowIso()],
          );
          if (upd.rows.length === 0) {
            const ex = await t.query<{ used_at: unknown }>(
              "SELECT used_at FROM join_tickets WHERE jti_hash=$1 AND session_id=$2 AND character_id=$3",
              [jtiHash, sessionId, claims.characterId],
            );
            if (ex.rows[0]?.used_at != null) throw Errors.conflict("Ticket ja utilizado", "ticket_already_used");
            throw unauthorizedTicket();
          }
          const who = await t.query<{ account_id: string }>(
            `SELECT c.account_id FROM characters c JOIN accounts a ON a.id=c.account_id
              WHERE c.id=$1 AND c.deleted_at IS NULL AND a.disabled=false`,
            [claims.characterId],
          );
          const accountId = who.rows[0]?.account_id;
          if (!accountId) throw unauthorizedTicket();

          const lock = await lockState(t, claims.characterId, true);
          let reconnected = false;
          if (lock?.active) {
            if (lock.session_id !== sessionId) throw Errors.conflict("Personagem ja esta em outra sessao", "character_locked");
            if (lock.reconnect_until === null) throw Errors.conflict("Personagem ja esta conectado", "character_already_connected");
            reconnected = true; // mesma sessao dentro da janela de reconexao
          }
          if ((await activeCount(t, sessionId, claims.characterId)) >= session.capacity) throw Errors.conflict("Sessao cheia", "session_full");

          if (!lock) {
            await t.query(
              "INSERT INTO character_locks (character_id, session_id, acquired_at, heartbeat_at, reconnect_until) VALUES ($1,$2,$3::timestamptz,$3::timestamptz,NULL)",
              [claims.characterId, sessionId, nowIso()],
            );
          } else if (reconnected) {
            await t.query("UPDATE character_locks SET reconnect_until=NULL, heartbeat_at=$2::timestamptz WHERE character_id=$1", [claims.characterId, nowIso()]);
          } else {
            // Lock vencido (janela expirada / sem heartbeat / sessao encerrada): tomada de posse.
            await t.query(
              "UPDATE character_locks SET session_id=$2, acquired_at=$3::timestamptz, heartbeat_at=$3::timestamptz, reconnect_until=NULL WHERE character_id=$1",
              [claims.characterId, sessionId, nowIso()],
            );
          }
          return { character_id: claims.characterId, account_id: accountId, session_id: sessionId, reconnected };
        });
      } catch (e) {
        // Corrida: dois resgates de sessoes diferentes inserindo o primeiro lock do mesmo personagem.
        if (isUniqueViolation(e)) throw Errors.conflict("Personagem ja esta em outra sessao", "character_locked");
        throw e;
      }
    },

    // --------------------------------------------------------- desconexao / liberacao (interno)
    async disconnect(characterId: string, sessionId: string) {
      return db.tx(async (t) => {
        const lock = await lockState(t, characterId, true);
        if (!lock || !lock.active) throw Errors.notFound("Lock nao encontrado");
        if (lock.session_id !== sessionId) throw Errors.conflict("Lock pertence a outra sessao", "lock_held_by_other_session");
        // Idempotente: nao estende uma janela ja aberta.
        const until = lock.reconnect_until !== null ? iso(lock.reconnect_until) : toIso(deps.now() + config.reconnectWindowSeconds * 1000);
        await t.query("UPDATE character_locks SET reconnect_until=$2::timestamptz WHERE character_id=$1", [characterId, until]);
        return { character_id: characterId, session_id: sessionId, reconnect_until: until };
      });
    },

    async release(characterId: string, sessionId: string) {
      const r = await db.query("DELETE FROM character_locks WHERE character_id=$1 AND session_id=$2", [characterId, sessionId]);
      return { character_id: characterId, released: r.rowCount > 0 };
    },
  };
}
