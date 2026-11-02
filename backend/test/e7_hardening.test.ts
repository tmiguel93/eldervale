// E7.1: hardening do backend sem infra externa. Cobre M5 (chave por sessao, orcamento de xp), B4 (falhas de credencial interna),
// sondas health/ready e metricas operacionais. Referencia: docs/E4_SECURITY_REVIEW.md e docs/E7_GATE.md.
import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { createLogger } from "../src/http/logger.ts";
import { migrate } from "../src/persistence/migrate.ts";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { deriveSessionKey } from "../src/sessions/session-key.ts";
import type { Db } from "../src/persistence/db.ts";
import { freshDb, mkAccount, mkSession, testConfig } from "./helpers.ts";

const SECRET = "internal-secret-for-tests-0123456789abcdef";
const AUTH = "auth-secret-for-tests-0123456789abcdefghij";
const T0 = Date.parse("2026-01-01T00:00:00Z");

async function rig(env: Record<string, string> = {}, db?: Db) {
  db ??= await freshDb();
  const config = testConfig({ AUTH_SECRET: AUTH, GAME_SESSION_INTERNAL_SECRET: SECRET, ...env });
  const clock = { t: T0 };
  const lines: string[] = [];
  const app = buildApp({ config, db, now: () => clock.t, log: createLogger({ level: "debug", sink: (l) => lines.push(l) }) });
  const call = async (method: string, path: string, o: { secret?: string | null; body?: unknown; headers?: Record<string, string> } = {}) => {
    const headers: Record<string, string> = { ...(o.headers ?? {}) };
    if (o.secret !== null) headers.authorization = `Bearer ${o.secret ?? SECRET}`;
    if (o.body !== undefined) headers["content-type"] = "application/json";
    const res = await app.handle(new Request(`http://t${path}`, { method, headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) }));
    const text = await res.text();
    let json: any = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = text; }
    return { status: res.status, json };
  };
  return { db, config, clock, lines, call };
}
type Rig = Awaited<ReturnType<typeof rig>>;
let r: Rig | undefined;
afterEach(async () => { await r?.db.close(); r = undefined; });

const REG = { region: "sa-east", capacity: 4, protocol_version: 1, endpoint: "127.0.0.1:7777" };

describe("M5: chave por sessao (X-Session-Key)", () => {
  it("o registro devolve session_key derivada; formato estavel e diferente por sessao", async () => {
    r = await rig();
    const a = await r.call("POST", "/internal/sessions", { body: REG });
    const b = await r.call("POST", "/internal/sessions", { body: REG });
    expect(a.status).toBe(201);
    expect(a.json.session_key).toBe(deriveSessionKey(SECRET, a.json.session_id));
    expect(a.json.session_key).not.toBe(b.json.session_key);
    expect(a.json.session_key).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("requireSessionKey=true: heartbeat/close/redeem/disconnect/release sem chave ou com a chave de OUTRA sessao => 403; com a propria => ok", async () => {
    r = await rig({ REQUIRE_SESSION_KEY: "true" });
    const a = (await r.call("POST", "/internal/sessions", { body: REG })).json;
    const b = (await r.call("POST", "/internal/sessions", { body: REG })).json;
    const ch = "11111111-1111-4111-8111-111111111111";
    const paths: [string, unknown][] = [
      [`/internal/sessions/${a.session_id}/heartbeat`, {}],
      [`/internal/sessions/${a.session_id}/close`, {}],
      ["/internal/tickets/redeem", { ticket: "aaa.bbb.ccc", session_id: a.session_id }],
      [`/internal/characters/${ch}/disconnect`, { session_id: a.session_id }],
      [`/internal/characters/${ch}/release`, { session_id: a.session_id }],
    ];
    for (const [p, body] of paths) {
      expect((await r.call("POST", p, { body })).status, `sem chave ${p}`).toBe(403);
      expect((await r.call("POST", p, { body, headers: { "x-session-key": b.session_key } })).status, `chave alheia ${p}`).toBe(403);
      expect((await r.call("POST", p, { body, headers: { "x-session-key": "x".repeat(43) } })).status, `chave lixo ${p}`).toBe(403);
    }
    // A sessao A continua viva: nada acima a afetou; a propria chave funciona.
    const hb = await r.call("POST", `/internal/sessions/${a.session_id}/heartbeat`, { body: {}, headers: { "x-session-key": a.session_key } });
    expect(hb.status).toBe(200);
    // Servidor B nao consegue encerrar A, mas encerra a si mesmo.
    expect((await r.call("POST", `/internal/sessions/${a.session_id}/close`, { body: {}, headers: { "x-session-key": b.session_key } })).status).toBe(403);
    expect((await r.call("POST", `/internal/sessions/${b.session_id}/close`, { body: {}, headers: { "x-session-key": b.session_key } })).status).toBe(200);
  });

  it("requireSessionKey=false (padrao fora de production): ausente passa (compat.), mas chave PRESENTE e errada sempre falha", async () => {
    r = await rig();
    expect(r.config.requireSessionKey).toBe(false);
    const a = (await r.call("POST", "/internal/sessions", { body: REG })).json;
    expect((await r.call("POST", `/internal/sessions/${a.session_id}/heartbeat`, { body: {} })).status).toBe(200);
    expect((await r.call("POST", `/internal/sessions/${a.session_id}/heartbeat`, { body: {}, headers: { "x-session-key": "errada" } })).status).toBe(403);
  });

  it("checkpoint/rewards: a chave tem de ser da sessao do X-Session-Id; servidor com lock mas chave alheia e barrado", async () => {
    r = await rig({ REQUIRE_SESSION_KEY: "true" });
    const acct = await mkAccount(r.db, "k@example.com");
    const cid = (await r.db.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id) VALUES ($1,'Keyed','warrior') RETURNING id", [acct])).rows[0]!.id;
    const sid = await mkSession(r.db);
    const other = await mkSession(r.db);
    await r.db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [cid, sid]);
    const body = { idempotency_key: "key-session-0001", xp: 10 };
    const h = (key: string | null, session = sid) => ({ "x-session-id": session, ...(key ? { "x-session-key": key } : {}) });
    expect((await r.call("POST", `/internal/characters/${cid}/rewards`, { body, headers: h(null) })).status).toBe(403);
    expect((await r.call("POST", `/internal/characters/${cid}/rewards`, { body, headers: h(deriveSessionKey(SECRET, other)) })).status).toBe(403);
    expect((await r.call("POST", `/internal/characters/${cid}/rewards`, { body, headers: h(deriveSessionKey(SECRET, sid)) })).status).toBe(200);
    // Servidor da sessao `other` (chave propria valida) nao tem o lock => 409 session_fenced, nao 200.
    const r2 = await r.call("POST", `/internal/characters/${cid}/rewards`, { body: { ...body, idempotency_key: "key-session-0002" }, headers: h(deriveSessionKey(SECRET, other), other) });
    expect(r2.status).toBe(409);
    expect(r2.json.error.code).toBe("session_fenced");
  });
});

describe("M5: orcamento de xp por janela e teto de stats", () => {
  async function withLockedChar() {
    const rg = await rig();
    const acct = await mkAccount(rg.db, "b@example.com");
    const cid = (await rg.db.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id) VALUES ($1,'Budget','warrior') RETURNING id", [acct])).rows[0]!.id;
    const sid = await mkSession(rg.db);
    await rg.db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [cid, sid]);
    const rw = (key: string, xp: number) => rg.call("POST", `/internal/characters/${cid}/rewards`, { body: { idempotency_key: key, xp }, headers: { "x-session-id": sid } });
    return { rg, cid, rw };
  }

  it("servidor comprometido nao despeja xp: >20 000 por minuto => 409 reward_budget_exceeded; a janela passa e libera; replay nao conta", async () => {
    const { rg, rw } = await withLockedChar();
    r = rg;
    expect((await rw("budget-key-0001", 15_000)).status).toBe(200);
    const over = await rw("budget-key-0002", 6_000);
    expect(over.status).toBe(409);
    expect(over.json.error.code).toBe("reward_budget_exceeded");
    // replay da primeira recompensa continua devolvendo o resultado salvo (nao entra no orcamento)
    expect((await rw("budget-key-0001", 15_000)).json.replayed).toBe(true);
    // dentro do orcamento ainda cabe (15 000 + 5 000 = 20 000)
    expect((await rw("budget-key-0003", 5_000)).status).toBe(200);
    expect((await rw("budget-key-0004", 1)).status).toBe(409);
    rg.clock.t += 61_000; // fora da janela
    expect((await rw("budget-key-0005", 6_000)).status).toBe(200);
  });

  it("recompensas legitimas do jogo (chefe 1200 xp, quests <= 700) cabem folgadamente: 15 chefes em 1 minuto ainda passam", async () => {
    const { rg, rw } = await withLockedChar();
    r = rg;
    for (let i = 0; i < 15; i++) expect((await rw(`boss-key-${String(i).padStart(4, "0")}`, 1200)).status).toBe(200);
  });
});

describe("B4: falhas de credencial interna", () => {
  it("com IP confiavel: 20 falhas bloqueiam ESSA origem (inclusive com o segredo certo); outra origem segue normal; o log nao tem IP bruto nem segredo", async () => {
    r = await rig({ TRUST_PROXY: "true" });
    const ipA = { "x-real-ip": "203.0.113.50" };
    for (let i = 0; i < 20; i++) expect((await r.call("GET", "/internal/metrics", { secret: "errado-" + i, headers: ipA })).status).toBe(401);
    expect((await r.call("GET", "/internal/metrics", { headers: ipA })).status).toBe(429); // segredo certo, origem bloqueada
    expect((await r.call("GET", "/internal/metrics", { headers: { "x-real-ip": "198.51.100.77" } })).status).toBe(200);
    const all = r.lines.join("\n");
    expect(all).toContain("internal_auth_failed");
    expect(all).not.toContain("203.0.113.50");
    expect(all).not.toContain(SECRET);
    expect(all).not.toContain("errado-");
  });

  it("sem IP confiavel nunca bloqueia (um atacante nao pode travar o servidor de jogo legitimo), mas conta e loga", async () => {
    r = await rig();
    for (let i = 0; i < 30; i++) expect((await r.call("GET", "/internal/metrics", { secret: "errado-" + i })).status).toBe(401);
    expect((await r.call("GET", "/internal/metrics")).status).toBe(200);
    const m = (await r.call("GET", "/internal/metrics")).json;
    expect(m.counters.internal_auth_failed).toBe(30);
  });
});

describe("sondas e metricas", () => {
  it("/v1/health e /v1/ready: 200 com banco migrado; /v1/ready 503 not_ready sem migracoes; sem dados sensiveis", async () => {
    r = await rig();
    const h = await r.call("GET", "/v1/health", { secret: null });
    expect(h).toMatchObject({ status: 200, json: { status: "ok", db: "ok" } });
    const rd = await r.call("GET", "/v1/ready", { secret: null });
    expect(rd).toMatchObject({ status: 200, json: { status: "ready", db: "ok", migrations: "ok" } });
    expect(Object.keys(rd.json).sort()).toEqual(["db", "migrations", "status"]);
    await r.db.close();
    const raw = await createPgliteDb(); // sem migrate
    r = await rig({}, raw);
    const nr = await r.call("GET", "/v1/ready", { secret: null });
    expect(nr.status).toBe(503);
    expect(nr.json).toMatchObject({ status: "not_ready", db: "ok", migrations: "pending" });
    await migrate(raw);
    expect((await r.call("GET", "/v1/ready", { secret: null })).status).toBe(200);
  });

  it("/internal/metrics exige o segredo; conta requisicoes, 4xx/5xx, rate limit, jogadores online e sessoes vivas; sem PII", async () => {
    r = await rig();
    expect((await r.call("GET", "/internal/metrics", { secret: null })).status).toBe(401);
    const s = (await r.call("POST", "/internal/sessions", { body: REG })).json;
    const acct = await mkAccount(r.db, "m@example.com");
    const cid = (await r.db.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id) VALUES ($1,'Metric','warrior') RETURNING id", [acct])).rows[0]!.id;
    await r.db.query("INSERT INTO character_locks (character_id, session_id, heartbeat_at) VALUES ($1,$2,$3::timestamptz)", [cid, s.session_id, new Date(T0).toISOString()]);
    await r.db.query("UPDATE game_sessions SET heartbeat_at = $2::timestamptz WHERE id = $1", [s.session_id, new Date(T0).toISOString()]);
    await r.call("GET", "/nao-existe", { secret: null });
    const m = (await r.call("GET", "/internal/metrics")).json;
    expect(m.players_online).toBe(1);
    expect(m.sessions_alive).toBe(1);
    expect(m.requests_total).toBeGreaterThanOrEqual(3);
    expect(m.status["4xx"]).toBeGreaterThanOrEqual(2);
    expect(m.latency_ms).toMatchObject({ count: expect.any(Number), p50: expect.any(Number), p95: expect.any(Number) });
    const txt = JSON.stringify(m);
    expect(txt).not.toContain("m@example.com");
    expect(txt).not.toContain(SECRET);
    // reconexao em andamento nao conta como online
    await r.db.query("UPDATE character_locks SET reconnect_until = $2::timestamptz WHERE character_id = $1", [cid, new Date(T0 + 60_000).toISOString()]);
    expect((await r.call("GET", "/internal/metrics")).json.players_online).toBe(0);
  });

  it("todo log de request carrega request_id e nunca o e-mail completo nem a senha", async () => {
    r = await rig();
    await r.call("POST", "/v1/auth/register", { secret: null, body: { email: "pessoa.real@example.com", password: "uma senha bem longa 123" } });
    const reqLines = r.lines.map((l) => JSON.parse(l));
    expect(reqLines.every((l) => typeof l.request_id === "string" && l.request_id.length >= 8)).toBe(true);
    const all = r.lines.join("\n");
    expect(all).not.toContain("pessoa.real@example.com");
    expect(all).not.toContain("uma senha bem longa");
  });
});
