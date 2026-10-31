import { ApiError, Errors } from "../http/errors.ts";
import { RateLimiter } from "../http/rate-limit.ts";
import { isUniqueViolation, type Db } from "../persistence/db.ts";
import { iso, toIso } from "../sessions/validate.ts";

export const MAX_PARTY_MEMBERS = 4;

export interface PartiesOptions {
  inviteTtlSeconds: number;
}

export const DEFAULT_PARTIES_OPTIONS: PartiesOptions = { inviteTtlSeconds: 300 };

/** Le overrides do ambiente (PARTY_INVITE_TTL_SECONDS, 10..86400). */
export function partiesOptionsFromEnv(env: Record<string, string | undefined> = process.env): PartiesOptions {
  const raw = env.PARTY_INVITE_TTL_SECONDS?.trim();
  if (!raw) return DEFAULT_PARTIES_OPTIONS;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 10 || n > 86_400) throw new Error("PARTY_INVITE_TTL_SECONDS invalido (10..86400)");
  return { inviteTtlSeconds: n };
}

export interface PartyView {
  id: string;
  leader_character_id: string;
  created_at: string;
  max_members: number;
  members: { character_id: string; name: string; class_id: string; level: number; joined_at: string; is_leader: boolean }[];
}

export interface InviteView {
  id: string;
  party_id: string;
  target_character_id: string;
  status: string;
  expires_at: string;
}

interface PartyRow {
  id: string;
  leader_account_id: string;
}

export function createPartiesService(deps: { db: Db; now: () => number }, opts: PartiesOptions = DEFAULT_PARTIES_OPTIONS) {
  const { db } = deps;
  const inviteLimiter = new RateLimiter({ capacity: 30, refillPerSecond: 0.5, now: deps.now });
  const nowIso = () => toIso(deps.now());

  /** Personagem ativo da conta; 404 para inexistente OU alheio (sem distinguir). */
  async function owned(q: Db, accountId: string, characterId: string): Promise<void> {
    const r = await q.query("SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL", [characterId, accountId]);
    if (r.rows.length === 0) throw Errors.notFound("Personagem nao encontrado");
  }

  /** Trava a linha da party (serializa entradas/saidas). 404 se inexistente ou dissolvida. */
  async function lockParty(q: Db, partyId: string): Promise<PartyRow> {
    const r = await q.query<PartyRow>("SELECT id, leader_account_id FROM parties WHERE id=$1 AND disbanded_at IS NULL FOR UPDATE", [partyId]);
    const row = r.rows[0];
    if (!row) throw Errors.notFound("Party nao encontrada");
    return row;
  }

  async function memberCount(q: Db, partyId: string): Promise<number> {
    const r = await q.query<{ n: number }>("SELECT count(*)::int AS n FROM party_members WHERE party_id=$1", [partyId]);
    return r.rows[0]!.n;
  }

  async function accountIsMember(q: Db, partyId: string, accountId: string): Promise<boolean> {
    const r = await q.query(
      "SELECT 1 FROM party_members m JOIN characters c ON c.id=m.character_id WHERE m.party_id=$1 AND c.account_id=$2",
      [partyId, accountId],
    );
    return r.rows.length > 0;
  }

  async function view(q: Db, partyId: string): Promise<PartyView> {
    const p = await q.query<{ id: string; leader_account_id: string; created_at: unknown }>(
      "SELECT id, leader_account_id, created_at FROM parties WHERE id=$1",
      [partyId],
    );
    const party = p.rows[0]!;
    const m = await q.query<{ character_id: string; account_id: string; name: string; class_id: string; level: number; joined_at: unknown }>(
      `SELECT m.character_id, c.account_id, c.name, c.class_id, c.level, m.joined_at
         FROM party_members m JOIN characters c ON c.id=m.character_id
        WHERE m.party_id=$1 ORDER BY m.joined_at, m.character_id`,
      [partyId],
    );
    const leader = m.rows.find((x) => x.account_id === party.leader_account_id);
    return {
      id: party.id,
      leader_character_id: leader?.character_id ?? "",
      created_at: iso(party.created_at),
      max_members: MAX_PARTY_MEMBERS,
      members: m.rows.map((x) => ({
        character_id: x.character_id,
        name: x.name,
        class_id: x.class_id,
        level: x.level,
        joined_at: iso(x.joined_at),
        is_leader: x.account_id === party.leader_account_id,
      })),
    };
  }

  const conflictOnUnique = (e: unknown, code: string, msg: string): never => {
    if (isUniqueViolation(e)) throw Errors.conflict(msg, code);
    throw e;
  };

  return {
    async create(accountId: string, characterId: string): Promise<PartyView> {
      try {
        return await db.tx(async (t) => {
          await owned(t, accountId, characterId);
          const inParty = await t.query("SELECT 1 FROM party_members WHERE character_id=$1", [characterId]);
          if (inParty.rows.length > 0) throw Errors.conflict("Personagem ja esta em uma party", "already_in_party");
          const p = await t.query<{ id: string }>(
            "INSERT INTO parties (leader_account_id, created_at) VALUES ($1, $2::timestamptz) RETURNING id",
            [accountId, nowIso()],
          );
          const partyId = p.rows[0]!.id;
          await t.query("INSERT INTO party_members (party_id, character_id, joined_at) VALUES ($1,$2,$3::timestamptz)", [partyId, characterId, nowIso()]);
          return view(t, partyId);
        });
      } catch (e) {
        return conflictOnUnique(e, "already_in_party", "Personagem ja esta em uma party");
      }
    },

    async get(accountId: string, partyId: string): Promise<PartyView> {
      const r = await db.query(
        `SELECT 1 FROM parties p WHERE p.id=$1 AND p.disbanded_at IS NULL
            AND EXISTS (SELECT 1 FROM party_members m JOIN characters c ON c.id=m.character_id WHERE m.party_id=p.id AND c.account_id=$2)`,
        [partyId, accountId],
      );
      if (r.rows.length === 0) throw Errors.notFound("Party nao encontrada");
      return view(db, partyId);
    },

    async invite(accountId: string, partyId: string, targetCharacterId: string): Promise<InviteView> {
      const rl = inviteLimiter.take(`party-invite:acct:${accountId}`);
      if (!rl.allowed) throw Errors.tooManyRequests(rl.retryAfterMs / 1000);
      try {
        return await db.tx(async (t) => {
          const party = await lockParty(t, partyId);
          if (!(await accountIsMember(t, partyId, accountId))) throw Errors.notFound("Party nao encontrada");
          if (party.leader_account_id !== accountId) throw Errors.forbidden("Somente o lider pode convidar");
          const target = await t.query("SELECT 1 FROM characters WHERE id=$1 AND deleted_at IS NULL", [targetCharacterId]);
          if (target.rows.length === 0) throw Errors.notFound("Personagem alvo nao encontrado");
          const inParty = await t.query("SELECT 1 FROM party_members WHERE character_id=$1", [targetCharacterId]);
          if (inParty.rows.length > 0) throw Errors.conflict("Personagem alvo ja esta em uma party", "target_in_party");
          if ((await memberCount(t, partyId)) >= MAX_PARTY_MEMBERS) throw Errors.conflict("Party cheia", "party_full");
          const pend = await t.query<{ id: string; expires_at: unknown }>(
            "SELECT id, expires_at FROM party_invites WHERE party_id=$1 AND target_character_id=$2 AND status='pending' FOR UPDATE",
            [partyId, targetCharacterId],
          );
          const old = pend.rows[0];
          if (old) {
            if (new Date(iso(old.expires_at)).getTime() > deps.now()) throw Errors.conflict("Ja existe convite pendente para este personagem", "invite_pending");
            await t.query("UPDATE party_invites SET status='expired' WHERE id=$1", [old.id]);
          }
          const expires = toIso(deps.now() + opts.inviteTtlSeconds * 1000);
          const r = await t.query<{ id: string }>(
            `INSERT INTO party_invites (party_id, target_character_id, status, expires_at, created_at)
             VALUES ($1,$2,'pending',$3::timestamptz,$4::timestamptz) RETURNING id`,
            [partyId, targetCharacterId, expires, nowIso()],
          );
          return { id: r.rows[0]!.id, party_id: partyId, target_character_id: targetCharacterId, status: "pending", expires_at: expires };
        });
      } catch (e) {
        return conflictOnUnique(e, "invite_pending", "Ja existe convite pendente para este personagem");
      }
    },

    async join(accountId: string, partyId: string, inviteId: string, characterId: string): Promise<PartyView> {
      try {
        return await db.tx(async (t) => {
          await owned(t, accountId, characterId);
          await lockParty(t, partyId);
          const inv = await t.query<{ party_id: string; target_character_id: string; status: string; expires_at: unknown }>(
            "SELECT party_id, target_character_id, status, expires_at FROM party_invites WHERE id=$1 FOR UPDATE",
            [inviteId],
          );
          const invite = inv.rows[0];
          // Convite inexistente, de OUTRA party ou para OUTRO personagem: indistinguiveis (404).
          if (!invite || invite.party_id !== partyId || invite.target_character_id !== characterId) throw Errors.notFound("Convite nao encontrado");
          if (invite.status !== "pending") throw Errors.conflict("Convite ja utilizado ou invalido", "invite_not_pending");
          if (new Date(iso(invite.expires_at)).getTime() <= deps.now()) throw Errors.conflict("Convite expirado", "invite_expired");
          const inParty = await t.query("SELECT 1 FROM party_members WHERE character_id=$1", [characterId]);
          if (inParty.rows.length > 0) throw Errors.conflict("Personagem ja esta em uma party", "already_in_party");
          if (await accountIsMember(t, partyId, accountId)) throw Errors.conflict("A conta ja tem um personagem nesta party", "account_already_in_party");
          if ((await memberCount(t, partyId)) >= MAX_PARTY_MEMBERS) throw Errors.conflict("Party cheia", "party_full");
          await t.query("INSERT INTO party_members (party_id, character_id, joined_at) VALUES ($1,$2,$3::timestamptz)", [partyId, characterId, nowIso()]);
          await t.query("UPDATE party_invites SET status='accepted' WHERE id=$1", [inviteId]);
          return view(t, partyId);
        });
      } catch (e) {
        return conflictOnUnique(e, "already_in_party", "Personagem ja esta em uma party");
      }
    },

    async leave(accountId: string, partyId: string): Promise<{ party_disbanded: boolean; new_leader_character_id: string | null }> {
      return db.tx(async (t) => {
        const party = await lockParty(t, partyId);
        const mine = await t.query<{ character_id: string }>(
          "SELECT m.character_id FROM party_members m JOIN characters c ON c.id=m.character_id WHERE m.party_id=$1 AND c.account_id=$2",
          [partyId, accountId],
        );
        const me = mine.rows[0];
        if (!me) throw Errors.notFound("Party nao encontrada");
        await t.query("DELETE FROM party_members WHERE party_id=$1 AND character_id=$2", [partyId, me.character_id]);
        const next = await t.query<{ character_id: string; account_id: string }>(
          `SELECT m.character_id, c.account_id FROM party_members m JOIN characters c ON c.id=m.character_id
            WHERE m.party_id=$1 ORDER BY m.joined_at, m.character_id LIMIT 1`,
          [partyId],
        );
        const heir = next.rows[0];
        if (!heir) {
          await t.query("UPDATE parties SET disbanded_at=$2::timestamptz WHERE id=$1", [partyId, nowIso()]);
          await t.query("UPDATE party_invites SET status='revoked' WHERE party_id=$1 AND status='pending'", [partyId]);
          return { party_disbanded: true, new_leader_character_id: null };
        }
        if (party.leader_account_id === accountId) {
          await t.query("UPDATE parties SET leader_account_id=$2 WHERE id=$1", [partyId, heir.account_id]);
          return { party_disbanded: false, new_leader_character_id: heir.character_id };
        }
        return { party_disbanded: false, new_leader_character_id: null };
      });
    },

    async kick(accountId: string, partyId: string, targetCharacterId: string): Promise<void> {
      await db.tx(async (t) => {
        const party = await lockParty(t, partyId);
        if (!(await accountIsMember(t, partyId, accountId))) throw Errors.notFound("Party nao encontrada");
        if (party.leader_account_id !== accountId) throw Errors.forbidden("Somente o lider pode remover membros");
        const target = await t.query<{ account_id: string }>(
          "SELECT c.account_id FROM party_members m JOIN characters c ON c.id=m.character_id WHERE m.party_id=$1 AND m.character_id=$2",
          [partyId, targetCharacterId],
        );
        const tg = target.rows[0];
        if (!tg) throw Errors.notFound("Membro nao encontrado");
        if (tg.account_id === accountId) throw new ApiError(400, "cannot_kick_self", "Use /leave para sair da party");
        await t.query("DELETE FROM party_members WHERE party_id=$1 AND character_id=$2", [partyId, targetCharacterId]);
      });
    },
  };
}
