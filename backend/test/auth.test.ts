import { SignJWT, base64url } from "jose";
import { describe, expect, it } from "vitest";
import { createAuthRoutes, DEFAULT_AUTH_LIMITS } from "../src/auth/routes.ts";
import { createAuthVerifier } from "../src/auth/verifier.ts";
import { dummyPasswordHash, hashPassword, passwordNeedsRehash, verifyPassword } from "../src/auth/password.ts";
import { ACCESS_AUD, ACCESS_ISS, signAccessToken } from "../src/auth/tokens.ts";
import { isValidEmail } from "../src/auth/validate.ts";
import { buildApp } from "../src/app.ts";
import { createApp } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import type { Db } from "../src/persistence/db.ts";
import { freshDb, testConfig } from "./helpers.ts";

const PW = "correct horse battery";
const T0 = Date.parse("2026-01-01T00:00:00Z");

interface Ctx {
  db: Db;
  clock: { t: number };
  logs: string[];
  call: (method: string, path: string, body?: unknown, headers?: Record<string, string>) => Promise<{ res: Response; json: any }>;
  config: ReturnType<typeof testConfig>;
}

async function setup(limits = DEFAULT_AUTH_LIMITS, cfg: Record<string, string> = {}): Promise<Ctx> {
  const db = await freshDb();
  const config = testConfig(cfg);
  const clock = { t: T0 };
  const logs: string[] = [];
  const log = createLogger({ level: "debug", sink: (l) => logs.push(l) });
  const now = () => clock.t;
  const app = createApp({
    config, db, log, now,
    authVerifier: createAuthVerifier({ config, db, now }),
    register: (r, d) => createAuthRoutes(r, d, limits),
  });
  const call: Ctx["call"] = async (method, path, body, headers) => {
    const init: RequestInit = { method, headers: { ...(body !== undefined ? { "content-type": "application/json" } : {}), ...headers } };
    if (body !== undefined) init.body = typeof body === "string" ? body : JSON.stringify(body);
    const res = await app.handle(new Request(`http://t${path}`, init));
    const text = await res.text();
    let j: any = null;
    try { j = text ? JSON.parse(text) : null; } catch { /* not json */ }
    return { res, json: j };
  };
  return { db, clock, logs, call, config };
}

const reg = (c: Ctx, email = "user@example.com", password = PW) => c.call("POST", "/v1/auth/register", { email, password });
const login = (c: Ctx, email = "user@example.com", password = PW) => c.call("POST", "/v1/auth/login", { email, password });
const bearer = (t: string) => ({ authorization: `Bearer ${t}` });

async function loggedIn(c: Ctx) {
  await reg(c);
  const { json } = await login(c);
  return json as { access_token: string; refresh_token: string; expires_in: number };
}

describe("senha scrypt", () => {
  it("hash versionado, salt distinto, verifica e rejeita", async () => {
    const a = await hashPassword(PW);
    const b = await hashPassword(PW);
    expect(a).not.toBe(b);
    expect(a).toMatch(/^scrypt\$1\$15\$8\$1\$[A-Za-z0-9_-]+\$[A-Za-z0-9_-]+$/);
    expect(a).not.toContain(PW);
    expect(await verifyPassword(PW, a)).toBe(true);
    expect(await verifyPassword(PW + "x", a)).toBe(false);
    expect(await verifyPassword(PW, "lixo")).toBe(false);
    expect(await verifyPassword(PW, "scrypt$1$30$8$1$AAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAA")).toBe(false); // custo abusivo
    expect(passwordNeedsRehash(a)).toBe(false);
    expect(passwordNeedsRehash(await hashPassword(PW, { logN: 12, r: 8, p: 1 }))).toBe(true);
    expect(await dummyPasswordHash()).toMatch(/^scrypt\$1\$/);
  });
});

describe("validacao de e-mail", () => {
  it("aceita e rejeita formatos", () => {
    for (const ok of ["a@b.co", "john.doe+tag@sub.example.com"]) expect(isValidEmail(ok)).toBe(true);
    for (const bad of ["", "a@b", "@b.com", "a@@b.com", "a b@c.com", "a..b@c.com", ".a@c.com", "a@-c.com", "a@c.123", "á@c.com", "a@c..com"]) {
      expect(isValidEmail(bad)).toBe(false);
    }
    expect(isValidEmail("a".repeat(65) + "@c.com")).toBe(false);
    expect(isValidEmail("a@" + "b".repeat(250) + ".com")).toBe(false);
    // entrada patologica termina rapido
    const t = Date.now();
    isValidEmail("a".repeat(60) + "@" + "a.".repeat(100) + "!");
    expect(Date.now() - t).toBeLessThan(100);
  });
});

describe("registro e login", () => {
  it("registra (202 generico), normaliza e-mail e loga", async () => {
    const c = await setup();
    const r = await reg(c, "  User@Example.COM ");
    expect(r.res.status).toBe(202);
    expect(r.json).toEqual({ status: "accepted" });
    expect(r.res.headers.get("cache-control")).toBe("no-store");
    const row = await c.db.query<{ email: string; password_hash: string }>("SELECT email, password_hash FROM accounts");
    expect(row.rows).toHaveLength(1);
    expect(row.rows[0]!.email).toBe("user@example.com");
    expect(row.rows[0]!.password_hash).not.toContain(PW);
    const l = await login(c, "USER@example.com");
    expect(l.res.status).toBe(200);
    expect(l.json.token_type).toBe("Bearer");
    expect(l.json.expires_in).toBe(c.config.accessTokenTtlSeconds);
    expect(l.json.refresh_token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(l.res.headers.get("cache-control")).toBe("no-store");
  });

  it("e-mail duplicado (case-insensitive): resposta identica, conta unica, senha original preservada", async () => {
    const c = await setup();
    const a = await reg(c, "dup@example.com");
    const b = await reg(c, "DUP@Example.com", "outra senha longa 123");
    expect(b.res.status).toBe(a.res.status);
    expect(b.json).toEqual(a.json);
    const n = await c.db.query<{ n: number }>("SELECT count(*)::int AS n FROM accounts");
    expect(n.rows[0]!.n).toBe(1);
    expect((await login(c, "dup@example.com", "outra senha longa 123")).res.status).toBe(401);
    expect((await login(c, "dup@example.com")).res.status).toBe(200);
  });

  it("politica de senha", async () => {
    const c = await setup();
    for (const [pw, code] of [
      ["curta", "weak_password"],
      ["x".repeat(129), "weak_password"],
      ["user@example.com", "weak_password"],
      [12345678901, "invalid_password"],
      [undefined, "invalid_password"],
    ] as const) {
      const r = await c.call("POST", "/v1/auth/register", { email: "user@example.com", password: pw });
      expect(r.res.status).toBe(400);
      expect(r.json.error.code).toBe(code);
    }
    expect((await c.call("POST", "/v1/auth/register", { email: "user@example.com", password: "x".repeat(128) })).res.status).toBe(202);
  });

  it("senha errada e e-mail inexistente: mesma resposta 401", async () => {
    const c = await setup();
    await reg(c);
    const wrong = await login(c, "user@example.com", "senha errada demais");
    const none = await login(c, "ninguem@example.com", PW);
    expect(wrong.res.status).toBe(401);
    expect(none.res.status).toBe(401);
    expect(none.json).toEqual(wrong.json);
    expect(none.res.headers.get("www-authenticate")).toBe(wrong.res.headers.get("www-authenticate"));
  });

  it("conta disabled nao loga (resposta igual a credencial invalida) e token existente morre", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    expect((await c.call("GET", "/v1/account", undefined, bearer(s.access_token))).res.status).toBe(200);
    await c.db.query("UPDATE accounts SET disabled = true");
    const l = await login(c);
    expect(l.res.status).toBe(401);
    expect(l.json.error.code).toBe("invalid_credentials");
    expect((await c.call("GET", "/v1/account", undefined, bearer(s.access_token))).res.status).toBe(401);
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token })).res.status).toBe(401);
  });

  it("corpo invalido, tipos errados, grande e content-type", async () => {
    const c = await setup();
    expect((await c.call("POST", "/v1/auth/login", "{nao json")).res.status).toBe(400);
    expect((await c.call("POST", "/v1/auth/login", [1, 2])).res.status).toBe(400);
    expect((await c.call("POST", "/v1/auth/login", { email: 5, password: PW })).res.status).toBe(400);
    expect((await c.call("POST", "/v1/auth/login", { email: "user@example.com", password: "p".repeat(2000) })).res.status).toBe(400);
    expect((await c.call("POST", "/v1/auth/register", { email: "nao-e-email", password: PW })).json.error.code).toBe("invalid_email");
    const big = await c.call("POST", "/v1/auth/register", { email: "a@b.co", password: "x".repeat(200_000) });
    expect(big.res.status).toBe(413);
    const ct = await c.call("POST", "/v1/auth/login", "{}", { "content-type": "text/plain" });
    expect(ct.res.status).toBe(415);
  });

  it("GET /v1/account exige auth e devolve so campos publicos", async () => {
    const c = await setup();
    expect((await c.call("GET", "/v1/account")).res.status).toBe(401);
    const s = await loggedIn(c);
    const a = await c.call("GET", "/v1/account", undefined, bearer(s.access_token));
    expect(a.res.status).toBe(200);
    expect(Object.keys(a.json).sort()).toEqual(["created_at", "email", "id"]);
    expect(a.json.email).toBe("user@example.com");
  });
});

describe("access token / verificador", () => {
  it("rejeita adulterado, expirado, alg none, aud/iss errados, segredo errado", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const acct = (await c.db.query<{ id: string }>("SELECT id FROM accounts")).rows[0]!.id;
    const verify = createAuthVerifier({ config: c.config, db: c.db, now: () => c.clock.t });
    expect(await verify(s.access_token, null as never)).toEqual({ accountId: acct });

    // adulterado
    const [h, p, sig] = s.access_token.split(".");
    expect(await verify(`${h}.${p}.${sig!.slice(0, -2)}AA`, null as never)).toBeNull();
    const forgedPayload = base64url.encode(JSON.stringify({ ...JSON.parse(new TextDecoder().decode(base64url.decode(p!))), sub: "00000000-0000-4000-8000-000000000000" }));
    expect(await verify(`${h}.${forgedPayload}.${sig}`, null as never)).toBeNull();
    expect(await verify("lixo", null as never)).toBeNull();

    // alg none
    const none = `${base64url.encode('{"alg":"none","typ":"JWT"}')}.${p}.`;
    expect(await verify(none, null as never)).toBeNull();

    const key = new TextEncoder().encode(c.config.authSecret);
    const mkTok = (o: { aud?: string; iss?: string; secret?: Uint8Array; exp?: number; sub?: string }) =>
      new SignJWT({}).setProtectedHeader({ alg: "HS256" }).setSubject(o.sub ?? acct).setIssuer(o.iss ?? ACCESS_ISS)
        .setAudience(o.aud ?? ACCESS_AUD).setIssuedAt(T0 / 1000).setExpirationTime(o.exp ?? T0 / 1000 + 900).setJti("j1")
        .sign(o.secret ?? key);
    expect(await verify(await mkTok({}), null as never)).toEqual({ accountId: acct });
    expect(await verify(await mkTok({ aud: "eldervale-join" }), null as never)).toBeNull();
    expect(await verify(await mkTok({ iss: "outro" }), null as never)).toBeNull();
    expect(await verify(await mkTok({ secret: new TextEncoder().encode("x".repeat(48)) }), null as never)).toBeNull();
    expect(await verify(await mkTok({ sub: "nao-uuid" }), null as never)).toBeNull();
    // HS512 com o mesmo segredo tambem e recusado (lista de algoritmos)
    const hs512 = await new SignJWT({}).setProtectedHeader({ alg: "HS512" }).setSubject(acct).setIssuer(ACCESS_ISS).setAudience(ACCESS_AUD)
      .setIssuedAt(T0 / 1000).setExpirationTime(T0 / 1000 + 900).setJti("j").sign(key);
    expect(await verify(hs512, null as never)).toBeNull();

    // expirado (relogio injetado)
    c.clock.t = T0 + (c.config.accessTokenTtlSeconds + 1) * 1000;
    expect(await verify(s.access_token, null as never)).toBeNull();
    expect((await c.call("GET", "/v1/account", undefined, bearer(s.access_token))).res.status).toBe(401);
  });

  it("claims minimas e sem dados sensiveis", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const payload = JSON.parse(Buffer.from(s.access_token.split(".")[1]!, "base64url").toString());
    expect(Object.keys(payload).sort()).toEqual(["aud", "exp", "iat", "iss", "jti", "sub"]);
    expect(payload.exp - payload.iat).toBe(c.config.accessTokenTtlSeconds);
    expect(await signAccessToken(c.config, payload.sub, T0)).not.toBe(await signAccessToken(c.config, payload.sub, T0)); // jti unico
  });

  it("buildApp usa o verificador real", async () => {
    const db = await freshDb();
    const config = testConfig();
    const app = buildApp({ config, db, now: () => T0 });
    const r = await app.handle(new Request("http://t/v1/auth/register", {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "x@example.com", password: PW }),
    }));
    expect(r.status).toBe(202);
    const l = await app.handle(new Request("http://t/v1/auth/login", {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "x@example.com", password: PW }),
    }));
    const tok = ((await l.json()) as { access_token: string }).access_token;
    const me = await app.handle(new Request("http://t/v1/account", { headers: bearer(tok) }));
    expect(me.status).toBe(200);
  });
});

describe("refresh token", () => {
  it("guarda so o hash SHA-256", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const rows = await c.db.query<{ token_hash: string }>("SELECT token_hash FROM refresh_tokens");
    expect(rows.rows).toHaveLength(1);
    expect(rows.rows[0]!.token_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(rows.rows[0]!.token_hash).not.toContain(s.refresh_token);
  });

  it("rotaciona a cada uso; o novo funciona e o antigo nao", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    c.clock.t += 60_000;
    const r1 = await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token });
    expect(r1.res.status).toBe(200);
    expect(r1.json.refresh_token).not.toBe(s.refresh_token);
    expect(r1.res.headers.get("cache-control")).toBe("no-store");
    expect((await c.call("GET", "/v1/account", undefined, bearer(r1.json.access_token))).res.status).toBe(200);
    const r2 = await c.call("POST", "/v1/auth/refresh", { refresh_token: r1.json.refresh_token });
    expect(r2.res.status).toBe(200);
  });

  it("REUSO de token substituido revoga a cadeia inteira (inclui o token novo)", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const r1 = await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token });
    const r2 = await c.call("POST", "/v1/auth/refresh", { refresh_token: r1.json.refresh_token });
    expect(r2.res.status).toBe(200);
    // atacante reapresenta o primeiro token
    const reuse = await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token });
    expect(reuse.res.status).toBe(401);
    // o token legitimo mais recente tambem morreu
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: r2.json.refresh_token })).res.status).toBe(401);
    const live = await c.db.query<{ n: number }>("SELECT count(*)::int AS n FROM refresh_tokens WHERE revoked_at IS NULL");
    expect(live.rows[0]!.n).toBe(0);
    expect(c.logs.some((l) => l.includes("auth_refresh_reuse_detected"))).toBe(true);
  });

  it("reuso nao afeta outra sessao (outro login) da mesma conta", async () => {
    const c = await setup();
    const a = await loggedIn(c);
    const b = (await login(c)).json;
    const r1 = await c.call("POST", "/v1/auth/refresh", { refresh_token: a.refresh_token });
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: a.refresh_token })).res.status).toBe(401);
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: r1.json.refresh_token })).res.status).toBe(401);
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: b.refresh_token })).res.status).toBe(200);
  });

  it("logout revoga (e o token revogado nao renova)", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const out = await c.call("POST", "/v1/auth/logout", { refresh_token: s.refresh_token });
    expect(out.res.status).toBe(204);
    expect(out.res.headers.get("cache-control")).toBe("no-store");
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token })).res.status).toBe(401);
    // idempotente e sem oraculo
    expect((await c.call("POST", "/v1/auth/logout", { refresh_token: s.refresh_token })).res.status).toBe(204);
    expect((await c.call("POST", "/v1/auth/logout", { refresh_token: "A".repeat(43) })).res.status).toBe(204);
    expect((await c.call("POST", "/v1/auth/logout", { refresh_token: "curto" })).res.status).toBe(400);
  });

  it("logout apos rotacao revoga o token vigente quando o antigo e apresentado", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    const r1 = await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token });
    await c.call("POST", "/v1/auth/logout", { refresh_token: s.refresh_token });
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: r1.json.refresh_token })).res.status).toBe(401);
  });

  it("refresh expirado e desconhecido => 401 generico", async () => {
    const c = await setup();
    const s = await loggedIn(c);
    expect((await c.call("POST", "/v1/auth/refresh", { refresh_token: "B".repeat(43) })).res.status).toBe(401);
    c.clock.t += (c.config.refreshTokenTtlSeconds + 1) * 1000;
    const r = await c.call("POST", "/v1/auth/refresh", { refresh_token: s.refresh_token });
    expect(r.res.status).toBe(401);
    expect(r.json.error.code).toBe("unauthorized");
  });
});

describe("rate limit", () => {
  it("login por e-mail dispara 429 com Retry-After e recupera com o tempo", async () => {
    const c = await setup();
    await reg(c);
    let last: Awaited<ReturnType<typeof login>> | undefined;
    for (let i = 0; i < DEFAULT_AUTH_LIMITS.loginEmail.capacity; i++) {
      last = await login(c, "user@example.com", "senha errada demais");
      expect(last.res.status).toBe(401);
    }
    last = await login(c);
    expect(last.res.status).toBe(429);
    expect(Number(last.res.headers.get("retry-after"))).toBeGreaterThanOrEqual(1);
    // outro e-mail nao e afetado
    expect((await login(c, "outro@example.com")).res.status).toBe(401);
    c.clock.t += 10_000;
    expect((await login(c)).res.status).toBe(200);
  });

  it("limite por IP no registro e no refresh", async () => {
    const lim = { ...DEFAULT_AUTH_LIMITS, registerIp: { capacity: 2, refillPerSecond: 0.01 }, refreshIp: { capacity: 2, refillPerSecond: 0.01 } };
    const c = await setup(lim);
    expect((await reg(c, "a1@example.com")).res.status).toBe(202);
    expect((await reg(c, "a2@example.com")).res.status).toBe(202);
    const r = await reg(c, "a3@example.com");
    expect(r.res.status).toBe(429);
    expect(r.res.headers.get("retry-after")).toBeTruthy();
    const tok = { refresh_token: "C".repeat(43) };
    expect((await c.call("POST", "/v1/auth/refresh", tok)).res.status).toBe(401);
    expect((await c.call("POST", "/v1/auth/refresh", tok)).res.status).toBe(401);
    expect((await c.call("POST", "/v1/auth/refresh", tok)).res.status).toBe(429);
  });

  it("registro por e-mail limita repeticao", async () => {
    const c = await setup();
    for (let i = 0; i < DEFAULT_AUTH_LIMITS.registerEmail.capacity; i++) expect((await reg(c, "same@example.com")).res.status).toBe(202);
    expect((await reg(c, "same@example.com")).res.status).toBe(429);
  });
});

describe("nada sensivel em logs ou respostas", () => {
  it("nenhuma resposta ou log contem senha, hash, refresh token ou JWT", async () => {
    const c = await setup();
    const responses: string[] = [];
    const capture = async (p: ReturnType<Ctx["call"]>) => { const r = await p; responses.push(JSON.stringify(r.json)); return r; };
    await capture(reg(c));
    await capture(reg(c));
    await capture(login(c, "user@example.com", "senha errada demais"));
    const l = await capture(login(c));
    const rf = await capture(c.call("POST", "/v1/auth/refresh", { refresh_token: l.json.refresh_token }));
    await capture(c.call("POST", "/v1/auth/refresh", { refresh_token: l.json.refresh_token })); // reuso
    await capture(c.call("POST", "/v1/auth/login", "{quebrado"));
    const acc = await capture(c.call("GET", "/v1/account", undefined, bearer(rf.json.access_token)));
    const hash = (await c.db.query<{ password_hash: string }>("SELECT password_hash FROM accounts")).rows[0]!.password_hash;
    const blob = responses.join("\n");
    const logs = c.logs.join("\n");
    for (const secret of [PW, "senha errada demais", hash, l.json.refresh_token, rf.json.refresh_token, l.json.access_token, c.config.authSecret]) {
      expect(logs).not.toContain(secret);
    }
    // so as respostas de sucesso trazem tokens, e jamais senha/hash/segredo
    for (const secret of [PW, hash, c.config.authSecret]) expect(blob).not.toContain(secret);
    expect(JSON.stringify(acc.json)).not.toContain("password");
    expect(logs).not.toContain("user@example.com");
  });
});
