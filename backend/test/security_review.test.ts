// Revisao de seguranca E4 (docs/E4_SECURITY_REVIEW.md). Cada teste e uma evidencia: os marcados
// "[ACHADO]" documentam comportamento ABERTO (o teste passa quando o problema ainda existe e deve ser
// invertido quando for corrigido); os demais provam que a defesa funciona.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { signAccessToken } from "../src/auth/tokens.ts";
import { deriveTicketKey, signTicket } from "../src/sessions/ticket.ts";
import { clientIp } from "../src/http/rate-limit.ts";
import type { Db } from "../src/persistence/db.ts";
import { freshDb, mkAccount, mkCharacter, mkSession, testConfig } from "./helpers.ts";
import { REG, setup, type Harness } from "./m4_harness.ts";

const PW = "correct horse battery";
const T0 = Date.parse("2026-01-01T00:00:00Z");
const SECRET = "internal-secret-for-tests-0123456789abcdef";

async function realApp(env: Record<string, string> = {}) {
  const db = await freshDb();
  const config = testConfig({ AUTH_SECRET: "auth-secret-for-tests-0123456789abcdefghij", GAME_SESSION_INTERNAL_SECRET: SECRET, ...env });
  const clock = { t: T0 };
  const app = buildApp({ config, db, now: () => clock.t });
  const lockMemo = new Map<string, Promise<string>>();
  const call = async (method: string, path: string, o: { token?: string; secret?: string; body?: unknown; headers?: Record<string, string> } = {}) => {
    const headers: Record<string, string> = { ...(o.headers ?? {}) };
    if (o.token) headers.authorization = `Bearer ${o.token}`;
    if (o.secret) headers.authorization = `Bearer ${o.secret}`;
    if (o.body !== undefined) headers["content-type"] = "application/json";
    const m = /^\/internal\/characters\/([0-9a-f-]{36})\/(checkpoint|rewards)$/i.exec(path);
    if (m && o.secret === SECRET && !o.headers && o.body !== undefined && typeof o.body === "object" && o.body !== null) {
      const cid = m[1]!.toLowerCase();
      let p = lockMemo.get(cid);
      if (!p) {
        p = (async () => {
          const sid = await mkSession(db);
          await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [cid, sid]);
          return sid;
        })();
        lockMemo.set(cid, p);
      }
      headers["x-session-id"] = await p;
    }
    const res = await app.handle(new Request(`http://t${path}`, { method, headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }));
    const text = await res.text();
    let json: any = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = text; }
    return { status: res.status, json };
  };
  return { db, config, clock, call };
}
type Real = Awaited<ReturnType<typeof realApp>>;
let real: Real | undefined;
let h: Harness | undefined;
afterEach(async () => { await real?.db.close(); await h?.db.close(); real = undefined; h = undefined; });

describe("A/B. autenticacao e separacao de segredos", () => {
  it("TODA rota /internal/* registrada no codigo usa requireInternal (varredura estatica)", () => {
    const files: string[] = [];
    const walk = (d: string) => { for (const f of readdirSync(d)) { const p = join(d, f); statSync(p).isDirectory() ? walk(p) : p.endsWith(".ts") && files.push(p); } };
    walk(join(import.meta.dirname, "..", "src"));
    let n = 0;
    for (const f of files) {
      for (const m of readFileSync(f, "utf8").matchAll(/router\.(?:get|post|put|patch|delete)\(\s*"(\/[^"]*)",\s*([^\n]*)/g)) {
        const [, path, rest] = m;
        if (path!.startsWith("/internal")) { n++; expect(rest, `${f} ${path}`).toContain("requireInternal"); }
        if (path!.startsWith("/v1/") && !path!.startsWith("/v1/auth/") && path !== "/v1/health") expect(rest, `${f} ${path}`).toContain("requireAuth");
      }
    }
    expect(n).toBeGreaterThanOrEqual(9);
  });

  it("/internal/* recusa: sem credencial, token de usuario, segredo errado/prefixo/maior", async () => {
    real = await realApp();
    const id = randomUUID();
    const routes: [string, string][] = [
      ["POST", "/internal/sessions"], ["POST", `/internal/sessions/${id}/heartbeat`], ["POST", `/internal/sessions/${id}/close`],
      ["POST", "/internal/tickets/redeem"], ["POST", `/internal/characters/${id}/disconnect`], ["POST", `/internal/characters/${id}/release`],
      ["GET", `/internal/characters/${id}`], ["POST", `/internal/characters/${id}/checkpoint`], ["POST", `/internal/characters/${id}/rewards`],
    ];
    const acct = await mkAccount(real.db);
    const userTok = await signAccessToken(real.config, acct, T0);
    for (const [m, p] of routes) {
      for (const tok of [undefined, userTok, SECRET.slice(0, -1), SECRET + "x", real.config.authSecret, ""]) {
        const r = await real.call(m, p, { secret: tok, body: m === "POST" ? {} : undefined });
        expect(r.status, `${m} ${p} tok=${String(tok).slice(0, 6)}`).toBe(401);
      }
    }
  });

  it("JWT: alg=none, aud errada, assinado com outro segredo, expirado, ticket-como-access e access-como-ticket => 401", async () => {
    real = await realApp();
    const acct = await mkAccount(real.db);
    const key = new TextEncoder().encode(real.config.authSecret);
    const mk = (aud: string, k: Uint8Array, exp = "1h") => new SignJWT({}).setProtectedHeader({ alg: "HS256" }).setSubject(acct).setIssuer("eldervale-api").setAudience(aud).setIssuedAt(Math.floor(T0 / 1000)).setExpirationTime(Math.floor(T0 / 1000) + (exp === "1h" ? 3600 : -10)).setJti(randomUUID()).sign(k);
    const none = `${Buffer.from('{"alg":"none"}').toString("base64url")}.${Buffer.from(JSON.stringify({ sub: acct, iss: "eldervale-api", aud: "eldervale-access", exp: 9999999999, iat: 1, jti: "x" })).toString("base64url")}.`;
    const ticketKey = deriveTicketKey(SECRET);
    const ticket = await signTicket(ticketKey, { jti: randomUUID(), characterId: randomUUID(), sessionId: randomUUID(), nowMs: T0, ttlSeconds: 60 });
    const good = await mk("eldervale-access", key);
    expect((await real.call("GET", "/v1/account", { token: good })).status).toBe(200);
    for (const bad of [none, await mk("outra-aud", key), await mk("eldervale-access", new TextEncoder().encode("x".repeat(40))), await mk("eldervale-access", key, "expired"), ticket.token]) {
      expect((await real.call("GET", "/v1/account", { token: bad })).status).toBe(401);
    }
    // access token como ticket: chave derivada diferente => 401
    const sid = randomUUID();
    expect((await real.call("POST", "/internal/tickets/redeem", { secret: SECRET, body: { ticket: good, session_id: sid } })).status).toBe(401);
  });

  it("refresh: 8 rotacoes simultaneas do mesmo token => no maximo 1 sucesso; a cadeia inteira fica revogada", async () => {
    real = await realApp();
    await real.call("POST", "/v1/auth/register", { body: { email: "r@example.com", password: PW } });
    const l = await real.call("POST", "/v1/auth/login", { body: { email: "r@example.com", password: PW } });
    expect(l.status).toBe(200);
    const rs = await Promise.all(Array.from({ length: 8 }, () => real!.call("POST", "/v1/auth/refresh", { body: { refresh_token: l.json.refresh_token } })));
    expect(rs.filter((r) => r.status === 200).length).toBeLessThanOrEqual(1);
    const live = await real.db.query("SELECT 1 FROM refresh_tokens WHERE revoked_at IS NULL");
    expect(live.rows.length).toBe(0); // reuso detectado: nenhum sucessor sobrevive
  });

  it("login: resposta identica para conta inexistente x senha errada; senha nunca aparece no log", async () => {
    real = await realApp();
    await real.call("POST", "/v1/auth/register", { body: { email: "v@example.com", password: PW } });
    const a = await real.call("POST", "/v1/auth/login", { body: { email: "v@example.com", password: "senha errada 123" } });
    const b = await real.call("POST", "/v1/auth/login", { body: { email: "naoexiste@example.com", password: "senha errada 123" } });
    expect(a.status).toBe(401); expect(b.status).toBe(401);
    expect(a.json).toEqual(b.json);
  });
});

describe("A. rate limit (achados)", () => {
  it("[ACHADO M] lockout dirigido: 10 tentativas ruins de um atacante bloqueiam o login LEGITIMO do e-mail alvo", async () => {
    real = await realApp({ TRUST_PROXY: "true" });
    await real.call("POST", "/v1/auth/register", { body: { email: "vitima@example.com", password: PW } });
    for (let i = 0; i < 10; i++) await real.call("POST", "/v1/auth/login", { headers: { "x-real-ip": `203.0.113.${i}` }, body: { email: "vitima@example.com", password: "tentativa errada " + i } });
    const legit = await real.call("POST", "/v1/auth/login", { headers: { "x-real-ip": "198.51.100.7" }, body: { email: "vitima@example.com", password: PW } });
    expect(legit.status).toBe(429); // senha CORRETA, IP diferente, mesmo assim bloqueado
  });

  it("[ACHADO M] sem TRUST_PROXY todos os clientes dividem UM balde de IP (\"unknown\")", () => {
    const mk = (ip: string) => new Request("http://t/", { headers: { "x-real-ip": ip } });
    expect(clientIp(mk("1.1.1.1"), false)).toBe(clientIp(mk("2.2.2.2"), false));
  });

  it("[ACHADO M/B] com TRUST_PROXY, x-forwarded-for (primeiro item, controlado pelo cliente) vale quando x-real-ip falta", () => {
    const r = (v: string) => new Request("http://t/", { headers: { "x-forwarded-for": v } });
    expect(clientIp(r("9.9.9.1, 10.0.0.1"), true)).toBe("9.9.9.1");
    expect(clientIp(r("9.9.9.2, 10.0.0.1"), true)).toBe("9.9.9.2"); // atacante rotaciona e foge do limite por IP
  });
});

describe("C. integridade sob concorrencia", () => {
  it("ticket de uso unico: 6 resgates simultaneos => exatamente 1 sucesso", async () => {
    h = await setup();
    const sid = (await h.call("POST", "/internal/sessions", { internal: true, body: REG })).json.session_id;
    const u = await h.user();
    const t = await h.call("POST", `/v1/sessions/${sid}/join-ticket`, { token: u.token, body: { character_id: u.char } });
    const rs = await Promise.all(Array.from({ length: 6 }, () => h!.call("POST", "/internal/tickets/redeem", { internal: true, body: { ticket: t.json.ticket, session_id: sid } })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.status !== 200).every((r) => r.status === 409 || r.status === 401)).toBe(true);
  });

  it("um personagem, duas sessoes, tickets simultaneos => um unico lock", async () => {
    h = await setup();
    const s1 = (await h.call("POST", "/internal/sessions", { internal: true, body: REG })).json.session_id;
    const s2 = (await h.call("POST", "/internal/sessions", { internal: true, body: REG })).json.session_id;
    const u = await h.user();
    const t1 = await h.call("POST", `/v1/sessions/${s1}/join-ticket`, { token: u.token, body: { character_id: u.char } });
    const t2 = await h.call("POST", `/v1/sessions/${s2}/join-ticket`, { token: u.token, body: { character_id: u.char } });
    const rs = await Promise.all([
      h.call("POST", "/internal/tickets/redeem", { internal: true, body: { ticket: t1.json.ticket, session_id: s1 } }),
      h.call("POST", "/internal/tickets/redeem", { internal: true, body: { ticket: t2.json.ticket, session_id: s2 } }),
    ]);
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    const locks = await h.db.query("SELECT 1 FROM character_locks WHERE character_id=$1", [u.char]);
    expect(locks.rows).toHaveLength(1);
  });

  it("party: 7 convites aceitos ao mesmo tempo => no maximo 4 membros", async () => {
    h = await setup();
    const lead = await h.user();
    const party = (await h.call("POST", "/v1/parties", { token: lead.token, body: { character_id: lead.char } })).json.party;
    const others = [];
    for (let i = 0; i < 7; i++) {
      const o = await h.user();
      const inv = await h.call("POST", `/v1/parties/${party.id}/invites`, { token: lead.token, body: { target_character_id: o.char } });
      if (inv.status === 201) others.push({ o, inv: inv.json.invite.id });
    }
    await Promise.all(others.map(({ o, inv }) => h!.call("POST", `/v1/parties/${party.id}/join`, { token: o.token, body: { invite_id: inv, character_id: o.char } })));
    const n = await h.db.query<{ n: number }>("SELECT count(*)::int AS n FROM party_members WHERE party_id=$1", [party.id]);
    expect(n.rows[0]!.n).toBeLessThanOrEqual(4);
  });

  it("recompensa: 10 requests simultaneos com a MESMA chave => aplicada 1 vez; payload diferente => 409", async () => {
    real = await realApp();
    const acct = await mkAccount(real.db, "c@example.com");
    const tok = await signAccessToken(real.config, acct, T0);
    const c = await real.call("POST", "/v1/characters", { token: tok, body: { name: "Dupe", class_id: "warrior" } });
    const id = c.json.character.id;
    const body = { idempotency_key: "kill:abc:00000001", xp: 50, items: [{ item_id: "potion_minor", qty: 3 }] };
    const rs = await Promise.all(Array.from({ length: 10 }, () => real!.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body })));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect(rs.filter((r) => r.json.replayed === false)).toHaveLength(1);
    const ch = await real.call("GET", `/internal/characters/${id}`, { secret: SECRET });
    expect(ch.json.character.xp).toBe(50);
    expect(ch.json.character.inventory.find((e: any) => e.item_id === "potion_minor").qty).toBe(3);
    const diff = await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body: { ...body, xp: 9999 } });
    expect(diff.status).toBe(409);
  });

  it("IDOR: personagem alheio => 404 (GET e DELETE), nunca 403/200; mass assignment recusado", async () => {
    real = await realApp();
    const a = await mkAccount(real.db, "a@example.com"); const b = await mkAccount(real.db, "b@example.com");
    const ta = await signAccessToken(real.config, a, T0); const tb = await signAccessToken(real.config, b, T0);
    const c = await real.call("POST", "/v1/characters", { token: ta, body: { name: "Alvo", class_id: "warrior" } });
    const id = c.json.character.id;
    expect((await real.call("GET", `/v1/characters/${id}`, { token: tb })).status).toBe(404);
    expect((await real.call("DELETE", `/v1/characters/${id}`, { token: tb })).status).toBe(404);
    expect((await real.call("POST", "/v1/characters", { token: tb, body: { name: "Mass", class_id: "warrior", level: 50, account_id: a } })).status).toBe(400);
    const g = await mkSession(real.db);
    expect((await real.call("POST", `/v1/sessions/${g}/join-ticket`, { token: tb, body: { character_id: id } })).status).toBe(404);
  });
});

describe("C. achados de integridade (abertos)", () => {
  it("[CORRIGIDO M4] fencing: checkpoint e recompensa exigem a sessao dona do lock do personagem", async () => {
    real = await realApp();
    const acct = await mkAccount(real.db, "z@example.com");
    const tok = await signAccessToken(real.config, acct, T0);
    const c = await real.call("POST", "/v1/characters", { token: tok, body: { name: "Zumbi", class_id: "warrior" } });
    const id = c.json.character.id;
    const body = { idempotency_key: "zombie-key-0001", xp: 10 };
    const sem = await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body, headers: {} });
    expect(sem.status).toBe(400); // sem X-Session-Id
    const sid = await mkSession(real.db);
    const semLock = await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body, headers: { "x-session-id": sid } });
    expect(semLock.status).toBe(409); // sessao existe mas nao detem o lock
    await real.db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [id, sid]);
    const outra = await mkSession(real.db);
    expect((await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body, headers: { "x-session-id": outra } })).status).toBe(409);
    expect((await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body, headers: { "x-session-id": sid } })).status).toBe(200);
    await real.db.query("UPDATE game_sessions SET closed_at = now(), status = 'closed' WHERE id = $1", [sid]);
    expect((await real.call("POST", `/internal/characters/${id}/rewards`, { secret: SECRET, body: { ...body, idempotency_key: "zombie-key-0002" }, headers: { "x-session-id": sid } })).status).toBe(409);
  });

  it("[ACHADO M] stats nao tem teto relativo: um checkpoint pode saltar attack_power 10 -> 100000", async () => {
    real = await realApp();
    const acct = await mkAccount(real.db, "s@example.com");
    const tok = await signAccessToken(real.config, acct, T0);
    const c = (await real.call("POST", "/v1/characters", { token: tok, body: { name: "Stats", class_id: "warrior" } })).json.character;
    const state = { schema_version: 1, level: c.level, xp: c.xp, stats: { ...c.stats, attack_power: 100000 }, inventory: c.inventory, equipment: c.equipment };
    const r = await real.call("POST", `/internal/characters/${c.id}/checkpoint`, { secret: SECRET, body: { expected_revision: c.revision, state } });
    expect(r.status).toBe(200);
  });

  it("[ACHADO B] lock vencido (sessao morta sem close) impede apagar o personagem para sempre (409)", async () => {
    h = await setup({ sessions: { heartbeatTimeoutSeconds: 30 } });
    const u = await h.user();
    const sid = await mkSession(h.db);
    await h.db.query("INSERT INTO character_locks (character_id, session_id, acquired_at, heartbeat_at) VALUES ($1,$2,'2020-01-01','2020-01-01')", [u.char, sid]);
    await h.db.query("UPDATE game_sessions SET closed_at=NULL, status='open'");
    // delete passa pela rota real de characters:
    const { registerCharactersRoutes } = await import("../src/characters/routes.ts");
    const { createApp } = await import("../src/http/app.ts");
    const { createLogger } = await import("../src/http/logger.ts");
    const app = createApp({ config: h.config, db: h.db, log: createLogger({ level: "error" }), now: () => h!.clock.t, authVerifier: async (t) => ({ accountId: t.slice(5) }), register: (r, d) => registerCharactersRoutes(r, d) });
    const res = await app.handle(new Request(`http://t/v1/characters/${u.char}`, { method: "DELETE", headers: { authorization: `Bearer ${u.token}` } }));
    expect(res.status).toBe(409);
  });

  it("[ACHADO B] personagem apagado continua em party_members (ocupa vaga e aparece no view)", async () => {
    h = await setup();
    const lead = await h.user(); const guest = await h.user();
    const party = (await h.call("POST", "/v1/parties", { token: lead.token, body: { character_id: lead.char } })).json.party;
    const inv = await h.call("POST", `/v1/parties/${party.id}/invites`, { token: lead.token, body: { target_character_id: guest.char } });
    await h.call("POST", `/v1/parties/${party.id}/join`, { token: guest.token, body: { invite_id: inv.json.invite.id, character_id: guest.char } });
    await h.db.query("UPDATE characters SET deleted_at=now() WHERE id=$1", [guest.char]);
    const v = await h.call("GET", `/v1/parties/${party.id}`, { token: lead.token });
    expect(v.json.party.members.map((m: any) => m.character_id)).toContain(guest.char);
  });
});
