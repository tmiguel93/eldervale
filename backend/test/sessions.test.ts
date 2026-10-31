import { createHash, randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterEach, describe, expect, it } from "vitest";
import { deriveTicketKey } from "../src/sessions/ticket.ts";
import { REG, setup, type Harness } from "./m4_harness.ts";

let h: Harness;
afterEach(async () => { await h.db.close(); });

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
const decode = (t: string) => JSON.parse(Buffer.from(t.split(".")[1]!, "base64url").toString());

async function register(over: Record<string, unknown> = {}): Promise<string> {
  const r = await h.call("POST", "/internal/sessions", { internal: true, body: { ...REG, ...over } });
  expect(r.status).toBe(201);
  return r.json.session_id;
}
const ticket = (u: { token: string; char: string }, sid: string) =>
  h.call("POST", `/v1/sessions/${sid}/join-ticket`, { token: u.token, body: { character_id: u.char } });
const redeem = (t: string, sid: string) => h.call("POST", "/internal/tickets/redeem", { internal: true, body: { ticket: t, session_id: sid } });
const disconnect = (char: string, sid: string) => h.call("POST", `/internal/characters/${char}/disconnect`, { internal: true, body: { session_id: sid } });
const release = (char: string, sid: string) => h.call("POST", `/internal/characters/${char}/release`, { internal: true, body: { session_id: sid } });
const heartbeat = (sid: string) => h.call("POST", `/internal/sessions/${sid}/heartbeat`, { internal: true });
async function enter(u: { token: string; char: string }, sid: string) {
  const t = await ticket(u, sid);
  expect(t.status).toBe(201);
  const r = await redeem(t.json.ticket, sid);
  expect(r.status).toBe(200);
  return r;
}

describe("sessoes: registro e ticket", () => {
  it("fluxo ponta a ponta; so o hash do jti e guardado; ticket/jti nunca vao para o log", async () => {
    h = await setup();
    const sid = await register();
    const u = await h.user();
    const t = await ticket(u, sid);
    expect(t.status).toBe(201);
    expect(t.json.session).toEqual({ id: sid, region: "sa-east", endpoint: "127.0.0.1:7777", protocol_version: 1 });
    expect(t.json.expires_at).toBe(new Date(h.clock.t + 60_000).toISOString());
    const claims = decode(t.json.ticket);
    expect(claims).toMatchObject({ sub: u.char, sid, iss: "eldervale-backend", aud: "eldervale-game-session" });
    expect(claims.exp - claims.iat).toBe(60);
    const rows = await h.db.query<{ jti_hash: string }>("SELECT jti_hash FROM join_tickets");
    expect(rows.rows).toHaveLength(1);
    expect(rows.rows[0]!.jti_hash).toBe(createHash("sha256").update(claims.jti).digest("hex"));
    expect(JSON.stringify(rows.rows)).not.toContain(claims.jti);

    const r = await redeem(t.json.ticket, sid);
    expect(r.status).toBe(200);
    expect(r.json).toEqual({ character_id: u.char, account_id: u.account, session_id: sid, reconnected: false });
    const lock = await h.db.query<{ session_id: string; reconnect_until: unknown }>("SELECT session_id, reconnect_until FROM character_locks WHERE character_id=$1", [u.char]);
    expect(lock.rows[0]!.session_id).toBe(sid);
    expect(lock.rows[0]!.reconnect_until).toBeNull();
    const logs = h.lines.join("\n");
    expect(logs).not.toContain(t.json.ticket);
    expect(logs).not.toContain(claims.jti);
    expect(logs).not.toContain(rows.rows[0]!.jti_hash);
  });

  it("registro valida entrada e versao de protocolo", async () => {
    h = await setup();
    const bad = async (over: Record<string, unknown>, status = 400) =>
      expect((await h.call("POST", "/internal/sessions", { internal: true, body: { ...REG, ...over } })).status).toBe(status);
    await bad({ region: "SA EAST!" });
    await bad({ capacity: 0 });
    await bad({ capacity: 65 });
    await bad({ capacity: 2.5 });
    await bad({ endpoint: "no-port" });
    await bad({ endpoint: "host:99999" });
    await bad({ protocol_version: 99 });
    await bad({ protocol_version: "1" });
    expect((await h.call("POST", "/internal/sessions", { internal: true, body: [] })).status).toBe(400);
  });

  it("ticket exige ownership, sessao existente, ativa, protocolo suportado", async () => {
    h = await setup();
    const sid = await register();
    const a = await h.user();
    const b = await h.user();
    expect((await h.call("POST", `/v1/sessions/${sid}/join-ticket`, { token: b.token, body: { character_id: a.char } })).status).toBe(404);
    expect((await ticket(a, "00000000-0000-4000-8000-000000000000")).status).toBe(404);
    expect((await h.call("POST", `/v1/sessions/xx/join-ticket`, { token: a.token, body: { character_id: a.char } })).status).toBe(400);
    expect((await h.call("POST", `/v1/sessions/${sid}/join-ticket`, { body: { character_id: a.char } })).status).toBe(401);
    // protocolo nao suportado (sessao inserida direto)
    const old = await h.db.query<{ id: string }>("INSERT INTO game_sessions (region,status,capacity,protocol_version) VALUES ('sa','open',4,99) RETURNING id");
    const p = await ticket(a, old.rows[0]!.id);
    expect(p.status).toBe(409);
    expect(p.json.error.code).toBe("unsupported_protocol");
    // encerrada
    await h.call("POST", `/internal/sessions/${sid}/close`, { internal: true });
    const c = await ticket(a, sid);
    expect(c.status).toBe(409);
    expect(c.json.error.code).toBe("session_unavailable");
  });

  it("ticket expirado, adulterado, de outra sessao, de outro segredo e reusado", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();

    // expirado (exp == agora ja expira)
    const t1 = await ticket(u, s1);
    h.advance(60_000);
    const e = await redeem(t1.json.ticket, s1);
    expect(e.status).toBe(401);
    expect(e.json.error.code).toBe("unauthorized");

    // adulterado: assinatura e payload
    const t2 = await ticket(u, s1);
    const [hd, pl, sig] = t2.json.ticket.split(".");
    const flipped = sig.slice(0, -2) + (sig.endsWith("AA") ? "BB" : "AA");
    expect((await redeem(`${hd}.${pl}.${flipped}`, s1)).status).toBe(401);
    const other = await h.user();
    const forged = { ...decode(t2.json.ticket), sub: other.char };
    expect((await redeem(`${hd}.${b64(forged)}.${sig}`, s1)).status).toBe(401);
    expect((await redeem(`${b64({ alg: "none" })}.${pl}.`, s1)).status).toBe(400); // formato invalido
    expect((await redeem(`${b64({ alg: "none", typ: "JWT" })}.${pl}.x`, s1)).status).toBe(401);

    // assinado com outra chave
    const claims = decode(t2.json.ticket);
    const foreign = await new SignJWT({ sid: s1 }).setProtectedHeader({ alg: "HS256" }).setJti(claims.jti).setSubject(u.char)
      .setIssuer("eldervale-backend").setAudience("eldervale-game-session").setExpirationTime(Math.floor(h.clock.t / 1000) + 60)
      .sign(new TextEncoder().encode("outro-segredo-qualquer-0123456789abcdef"));
    expect((await redeem(foreign, s1)).status).toBe(401);
    // assinado com a chave do AUTH_SECRET/segredo interno cru (nao derivada)
    const raw = await new SignJWT({ sid: s1 }).setProtectedHeader({ alg: "HS256" }).setJti(claims.jti).setSubject(u.char)
      .setIssuer("eldervale-backend").setAudience("eldervale-game-session").setExpirationTime(Math.floor(h.clock.t / 1000) + 60)
      .sign(new TextEncoder().encode(h.config.gameSessionInternalSecret));
    expect((await redeem(raw, s1)).status).toBe(401);

    // sessao errada
    const wrong = await redeem(t2.json.ticket, s2);
    expect(wrong.status).toBe(401);
    // o ticket continua valido na sessao certa, uma vez so
    const good = await redeem(t2.json.ticket, s1);
    expect(good.status).toBe(200);
    const reused = await redeem(t2.json.ticket, s1);
    expect(reused.status).toBe(409);
    expect(reused.json.error.code).toBe("ticket_already_used");
    expect(JSON.stringify(reused.json)).not.toMatch(/stack|\.ts|jti/i);
  });

  it("ticket com aud/iss/sid/sub invalidos (mesmo com a chave certa) e sem registro no banco e recusado", async () => {
    h = await setup();
    const s1 = await register();
    const u = await h.user();
    const key = deriveTicketKey(h.config.gameSessionInternalSecret);
    const exp = Math.floor(h.clock.t / 1000) + 60;
    const mk = (o: { aud?: string; iss?: string; sid?: string; sub?: string }) =>
      new SignJWT({ sid: o.sid ?? s1 }).setProtectedHeader({ alg: "HS256" }).setJti(randomUUID()).setSubject(o.sub ?? u.char)
        .setIssuer(o.iss ?? "eldervale-backend").setAudience(o.aud ?? "eldervale-game-session").setExpirationTime(exp).sign(key);
    expect((await redeem(await mk({ aud: "outro" }), s1)).status).toBe(401);
    expect((await redeem(await mk({ iss: "outro" }), s1)).status).toBe(401);
    expect((await redeem(await mk({ sub: "nao-uuid" }), s1)).status).toBe(401);
    // assinatura e claims corretos, mas jti nunca emitido (sem linha em join_tickets)
    expect((await redeem(await mk({}), s1)).status).toBe(401);
    expect((await h.db.query("SELECT 1 FROM character_locks")).rows).toHaveLength(0);
  });

  it("resgate concorrente do mesmo ticket: so um vence", async () => {
    h = await setup();
    const sid = await register();
    const u = await h.user();
    const t = await ticket(u, sid);
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => redeem(t.json.ticket, sid)));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    const others = rs.filter((r) => r.status !== 200);
    expect(others).toHaveLength(4);
    expect(others.every((r) => r.status === 409 && ["ticket_already_used", "character_already_connected"].includes(r.json.error.code))).toBe(true);
    const used = await h.db.query("SELECT 1 FROM join_tickets WHERE used_at IS NOT NULL");
    expect(used.rows).toHaveLength(1);
    const locks = await h.db.query("SELECT 1 FROM character_locks");
    expect(locks.rows).toHaveLength(1);
  });

  it("sessao cheia: na emissao e no resgate; vaga reservada em reconexao", async () => {
    h = await setup();
    const sid = await register({ capacity: 2 });
    const [a, b, c] = [await h.user(), await h.user(), await h.user()];
    // c e d emitem ANTES de a e b entrarem
    const tc = await ticket(c, sid);
    await enter(a, sid);
    await enter(b, sid);
    const full = await ticket(c, sid);
    expect(full.status).toBe(409);
    expect(full.json.error.code).toBe("session_full");
    const late = await redeem(tc.json.ticket, sid);
    expect(late.status).toBe(409);
    expect(late.json.error.code).toBe("session_full");
    // desconectado em janela de reconexao ainda ocupa a vaga
    await disconnect(a.char, sid);
    expect((await ticket(c, sid)).status).toBe(409);
    // apos release, ha vaga; o ticket do resgate recusado continua utilizavel (nao foi consumido)
    await release(a.char, sid);
    expect((await redeem(tc.json.ticket, sid)).status).toBe(200);
  });
});

describe("locks entre sessoes", () => {
  it("um personagem = uma sessao ativa (emissao e resgate)", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    const early = await ticket(u, s2); // emitido antes do lock
    await enter(u, s1);
    const t = await ticket(u, s2);
    expect(t.status).toBe(409);
    expect(t.json.error.code).toBe("character_locked");
    const r = await redeem(early.json.ticket, s2);
    expect(r.status).toBe(409);
    expect(r.json.error.code).toBe("character_locked");
    // segundo login na MESMA sessao sem desconexao previa tambem e recusado
    const dup = await ticket(u, s1);
    expect(dup.status).toBe(409);
    expect(dup.json.error.code).toBe("character_already_connected");
    const rows = await h.db.query("SELECT 1 FROM character_locks WHERE character_id=$1", [u.char]);
    expect(rows.rows).toHaveLength(1);
  });

  it("resgates simultaneos do mesmo personagem em duas sessoes: so um lock", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    const t1 = await ticket(u, s1);
    const t2 = await ticket(u, s2);
    const [r1, r2] = await Promise.all([redeem(t1.json.ticket, s1), redeem(t2.json.ticket, s2)]);
    expect([r1.status, r2.status].sort()).toEqual([200, 409]);
    const rows = await h.db.query("SELECT 1 FROM character_locks WHERE character_id=$1", [u.char]);
    expect(rows.rows).toHaveLength(1);
  });

  it("party: companheiros em outra sessao bloqueiam; na mesma sessao liberam", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const a = await h.user();
    const b = await h.user();
    const pc = await h.call("POST", "/v1/parties", { token: a.token, body: { character_id: a.char } });
    const pid = pc.json.party.id;
    const inv = await h.call("POST", `/v1/parties/${pid}/invites`, { token: a.token, body: { target_character_id: b.char } });
    await h.call("POST", `/v1/parties/${pid}/join`, { token: b.token, body: { invite_id: inv.json.invite.id, character_id: b.char } });
    await enter(a, s1);
    const wrong = await ticket(b, s2);
    expect(wrong.status).toBe(409);
    expect(wrong.json.error.code).toBe("party_in_other_session");
    expect((await ticket(b, s1)).status).toBe(201);
  });
});

describe("desconexao, reconexao e release", () => {
  it("dentro da janela: novo ticket na mesma sessao reconecta; fora, o lock expira", async () => {
    h = await setup({ sessions: { heartbeatTimeoutSeconds: 600 } }); // isola a janela de reconexao do heartbeat
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    await enter(u, s1);
    const d = await disconnect(u.char, s1);
    expect(d.status).toBe(200);
    expect(d.json.reconnect_until).toBe(new Date(h.clock.t + 90_000).toISOString());
    // idempotente: nao estende
    h.advance(10_000);
    expect((await disconnect(u.char, s1)).json.reconnect_until).toBe(d.json.reconnect_until);

    // em outra sessao, ainda dentro da janela: recusado
    const other = await ticket(u, s2);
    expect(other.status).toBe(409);
    expect(other.json.error.code).toBe("character_locked");
    // mesma sessao, dentro da janela: novo ticket e permitido e limpa reconnect_until
    h.advance(30_000);
    const t = await ticket(u, s1);
    expect(t.status).toBe(201);
    const r = await redeem(t.json.ticket, s1);
    expect(r.status).toBe(200);
    expect(r.json.reconnected).toBe(true);
    const lock = await h.db.query<{ reconnect_until: unknown }>("SELECT reconnect_until FROM character_locks WHERE character_id=$1", [u.char]);
    expect(lock.rows[0]!.reconnect_until).toBeNull();

    // nova desconexao e a janela vence sem reconexao: outra sessao passa a poder entrar
    const d2 = await disconnect(u.char, s1);
    h.advance(89_000);
    expect((await ticket(u, s2)).status).toBe(409);
    h.advance(1_000);
    expect(new Date(d2.json.reconnect_until).getTime()).toBe(h.clock.t);
    const t2 = await ticket(u, s2);
    expect(t2.status).toBe(201);
    const r2 = await redeem(t2.json.ticket, s2);
    expect(r2.status).toBe(200);
    expect(r2.json.reconnected).toBe(false);
    const lock2 = await h.db.query<{ session_id: string }>("SELECT session_id FROM character_locks WHERE character_id=$1", [u.char]);
    expect(lock2.rows[0]!.session_id).toBe(s2);
  });

  it("ticket anterior a janela nao pode ser reutilizado; reconexao exige ticket novo", async () => {
    h = await setup();
    const s1 = await register();
    const u = await h.user();
    const t = await enter(u, s1);
    await disconnect(u.char, s1);
    expect(t.status).toBe(200);
    const again = await h.db.query<{ n: number }>("SELECT count(*)::int AS n FROM join_tickets WHERE used_at IS NOT NULL");
    expect(again.rows[0]!.n).toBe(1);
  });

  it("disconnect/release: validacoes de dono do lock", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    expect((await disconnect(u.char, s1)).status).toBe(404); // sem lock
    await enter(u, s1);
    const wrong = await disconnect(u.char, s2);
    expect(wrong.status).toBe(409);
    expect(wrong.json.error.code).toBe("lock_held_by_other_session");
    expect((await h.call("POST", `/internal/characters/${u.char}/disconnect`, { internal: true, body: {} })).status).toBe(400);
    // release por quem nao e dono nao libera
    const rel = await release(u.char, s2);
    expect(rel.json.released).toBe(false);
    expect((await h.db.query("SELECT 1 FROM character_locks")).rows).toHaveLength(1);
    const ok = await release(u.char, s1);
    expect(ok.json.released).toBe(true);
    expect((await release(u.char, s1)).json.released).toBe(false);
    // liberado: pode entrar em outra sessao imediatamente
    expect((await enter(u, s2)).json.session_id).toBe(s2);
  });
});

describe("heartbeat e encerramento", () => {
  it("sem heartbeat dentro do limite o lock expira (lazy); heartbeat renova", async () => {
    h = await setup({ sessions: { heartbeatTimeoutSeconds: 30 } });
    const s1 = await register();
    const s2 = await register();
    const a = await h.user();
    const b = await h.user();
    await enter(a, s1);
    await enter(b, s1);
    h.advance(20_000);
    await heartbeat(s2);
    expect((await heartbeat(s1)).json.locks_refreshed).toBe(2);
    h.advance(20_000); // 40s desde o inicio, 20s desde o heartbeat: vivo
    await heartbeat(s2);
    expect((await ticket(a, s2)).status).toBe(409);
    h.advance(11_000); // 31s sem heartbeat: morto
    await heartbeat(s2);
    const t = await ticket(a, s2);
    expect(t.status).toBe(201);
    const r = await redeem(t.json.ticket, s2);
    expect(r.status).toBe(200);
    // o lock de b tambem expirou, mesmo sem ninguem consultar antes
    expect((await enter(b, s2)).json.session_id).toBe(s2);
  });

  it("heartbeat nao ressuscita lock cuja janela de reconexao venceu", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    await enter(u, s1);
    await disconnect(u.char, s1);
    h.advance(91_000);
    await heartbeat(s1);
    expect((await enter(u, s2)).json.session_id).toBe(s2);
  });

  it("close libera os locks e e idempotente; heartbeat de sessao encerrada/inexistente", async () => {
    h = await setup();
    const s1 = await register();
    const s2 = await register();
    const u = await h.user();
    await enter(u, s1);
    const c = await h.call("POST", `/internal/sessions/${s1}/close`, { internal: true });
    expect(c.json).toMatchObject({ status: "closed", locks_released: 1 });
    expect((await h.call("POST", `/internal/sessions/${s1}/close`, { internal: true })).status).toBe(200);
    const hb = await heartbeat(s1);
    expect(hb.status).toBe(409);
    expect(hb.json.error.code).toBe("session_closed");
    expect((await heartbeat("00000000-0000-4000-8000-000000000000")).status).toBe(404);
    expect((await h.call("POST", `/internal/sessions/zzz/close`, { internal: true })).status).toBe(400);
    expect((await enter(u, s2)).json.session_id).toBe(s2);
    // ticket para sessao encerrada nao e resgatavel
    const s3 = await register();
    const t3 = await ticket(await h.user(), s3);
    await h.call("POST", `/internal/sessions/${s3}/close`, { internal: true });
    const r = await redeem(t3.json.ticket, s3);
    expect(r.status).toBe(409);
    expect(r.json.error.code).toBe("session_unavailable");
  });
});

describe("seguranca", () => {
  it("/internal/* sem segredo, com segredo errado ou com token de usuario => 401", async () => {
    h = await setup();
    const sid = await register();
    const u = await h.user();
    const urls: [string, string, unknown][] = [
      ["POST", "/internal/sessions", REG],
      ["POST", `/internal/sessions/${sid}/heartbeat`, undefined],
      ["POST", `/internal/sessions/${sid}/close`, undefined],
      ["POST", "/internal/tickets/redeem", { ticket: "a.b.c", session_id: sid }],
      ["POST", `/internal/characters/${u.char}/disconnect`, { session_id: sid }],
      ["POST", `/internal/characters/${u.char}/release`, { session_id: sid }],
    ];
    for (const [m, p, body] of urls) {
      expect((await h.call(m, p, { body })).status, `${p} sem credencial`).toBe(401);
      expect((await h.call(m, p, { body, internal: true, secret: "segredo-errado" })).status, `${p} segredo errado`).toBe(401);
      expect((await h.call(m, p, { body, token: u.token })).status, `${p} token de usuario`).toBe(401);
    }
    // /v1 com o segredo interno tambem nao autentica
    expect((await h.call("POST", `/v1/sessions/${sid}/join-ticket`, { internal: true, body: { character_id: u.char } })).status).toBe(401);
  });

  it("entrada validada: ticket malformado/grande e session_id invalido", async () => {
    h = await setup();
    const sid = await register();
    const bad = (body: unknown) => h.call("POST", "/internal/tickets/redeem", { internal: true, body });
    expect((await bad({ ticket: "x", session_id: sid })).status).toBe(400);
    expect((await bad({ ticket: "a.b.c".repeat(1000), session_id: sid })).status).toBe(400);
    expect((await bad({ ticket: "a.b.c", session_id: "nope" })).status).toBe(400);
    expect((await bad({ session_id: sid })).status).toBe(400);
    expect((await bad({ ticket: "a.b.c", session_id: sid })).status).toBe(401);
  });

  it("rate limit por conta na emissao de tickets", async () => {
    h = await setup({ sessions: { ticketRateCapacity: 2, ticketRefillPerSecond: 0.1 } });
    const sid = await register({ capacity: 10 });
    const u = await h.user();
    const other = await h.user();
    expect((await ticket(u, sid)).status).toBe(201);
    expect((await ticket(u, sid)).status).toBe(201);
    const limited = await ticket(u, sid);
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBeTruthy();
    expect((await ticket(other, sid)).status).toBe(201); // outra conta nao e afetada
    h.advance(10_000);
    expect((await ticket(u, sid)).status).toBe(201);
  });

  it("derivacao da chave: ticket de um backend com outro segredo interno nao vale", async () => {
    h = await setup();
    const sid = await register();
    const u = await h.user();
    const t = await ticket(u, sid);
    const h2 = await setup({ env: { GAME_SESSION_INTERNAL_SECRET: "outro-segredo-interno-com-mais-de-32-chars" } });
    try {
      const r = await h2.call("POST", "/internal/tickets/redeem", { internal: true, body: { ticket: t.json.ticket, session_id: sid } });
      expect(r.status).toBe(401);
    } finally {
      await h2.db.close();
    }
  });
});

describe("vivacidade da sessao (heartbeat_at) e listagem", () => {
  const hbAt = async (sid: string) => new Date((await h.db.query<{ t: unknown }>("SELECT heartbeat_at AS t FROM game_sessions WHERE id=$1", [sid])).rows[0]!.t as Date).getTime();

  it("registro e heartbeat atualizam heartbeat_at", async () => {
    h = await setup({ sessions: { heartbeatTimeoutSeconds: 30 } });
    const sid = await register();
    expect(await hbAt(sid)).toBe(h.clock.t);
    h.advance(10_000);
    await heartbeat(sid);
    expect(await hbAt(sid)).toBe(h.clock.t);
  });

  it("sessao sem heartbeat: nao emite ticket, nao resgata, nao conta vaga, sai da lista; heartbeat revive", async () => {
    h = await setup({ sessions: { heartbeatTimeoutSeconds: 30 } });
    const dead = await register({ capacity: 2 });
    const live = await register({ capacity: 2 });
    const u = await h.user();
    const v = await h.user();
    const early = await ticket(u, dead);
    h.advance(31_000);
    await heartbeat(live);
    const list = await h.call("GET", "/v1/sessions", { token: u.token });
    expect(list.json.sessions.map((s: any) => s.id)).toEqual([live]);
    const t = await ticket(v, dead);
    expect(t.status).toBe(409);
    expect(t.json.error.code).toBe("session_unavailable");
    const r = await redeem(early.json.ticket, dead);
    expect(r.status).toBe(409);
    expect(r.json.error.code).toBe("session_unavailable");
    // sem close, o personagem pode entrar em outra sessao viva
    expect((await enter(v, live)).json.session_id).toBe(live);
    await heartbeat(dead);
    expect((await h.call("GET", "/v1/sessions", { token: u.token })).json.sessions).toHaveLength(2);
  });

  it("GET /v1/sessions: vaga, regiao, fechadas, protocolo, formato sem dados sensiveis", async () => {
    h = await setup();
    const a = await register({ region: "sa-east", capacity: 2 });
    const b = await register({ region: "us-east", capacity: 1 });
    const c = await register({ region: "sa-east", capacity: 1 });
    const u = await h.user();
    const w = await h.user();
    await h.db.query("INSERT INTO game_sessions (region,status,capacity,protocol_version,endpoint) VALUES ('sa-east','open',4,99,'1.2.3.4:1')");
    await h.call("POST", `/internal/sessions/${c}/close`, { internal: true });
    await enter(u, a);
    await enter(w, b); // b fica cheia
    const all = await h.call("GET", "/v1/sessions", { token: u.token });
    expect(all.status).toBe(200);
    expect(all.json.sessions).toEqual([{ id: a, region: "sa-east", capacity: 2, free_slots: 1, protocol_version: 1, endpoint: "127.0.0.1:7777" }]);
    expect((await h.call("GET", "/v1/sessions?region=us-east", { token: u.token })).json.sessions).toEqual([]);
    expect((await h.call("GET", "/v1/sessions?region=sa-east", { token: u.token })).json.sessions).toHaveLength(1);
    expect((await h.call("GET", "/v1/sessions?region=BAD!", { token: u.token })).status).toBe(400);
    expect((await h.call("GET", "/v1/sessions")).status).toBe(401);
    // reconexao em janela ainda ocupa vaga
    await disconnect(u.char, a);
    expect((await h.call("GET", "/v1/sessions", { token: u.token })).json.sessions[0].free_slots).toBe(1);
    await release(u.char, a);
    expect((await h.call("GET", "/v1/sessions", { token: u.token })).json.sessions[0].free_slots).toBe(2);
  });

  it("lista limitada a 50 e com rate limit por conta", async () => {
    h = await setup({ sessions: { listRateCapacity: 2, listRefillPerSecond: 0.1 } });
    for (let i = 0; i < 52; i++) {
      await h.db.query("INSERT INTO game_sessions (region,status,capacity,protocol_version,endpoint,created_at,heartbeat_at) VALUES ('sa','open',4,1,'h:1',$1,$1)", [new Date(h.clock.t).toISOString()]);
    }
    const u = await h.user();
    const x = await h.user();
    const r = await h.call("GET", "/v1/sessions", { token: u.token });
    expect(r.json.sessions).toHaveLength(50);
    expect((await h.call("GET", "/v1/sessions", { token: u.token })).status).toBe(200);
    const limited = await h.call("GET", "/v1/sessions", { token: u.token });
    expect(limited.status).toBe(429);
    expect((await h.call("GET", "/v1/sessions", { token: x.token })).status).toBe(200);
  });
});
