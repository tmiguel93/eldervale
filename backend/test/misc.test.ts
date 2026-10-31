import { describe, expect, it } from "vitest";
import { ConfigError, loadConfig } from "../src/config.ts";
import { createLogger, maskEmail } from "../src/http/logger.ts";
import { RateLimiter } from "../src/http/rate-limit.ts";

describe("config", () => {
  const good = { NODE_ENV: "production", DATABASE_URL: "postgres://u:p@h/db", AUTH_SECRET: "a".repeat(32), GAME_SESSION_INTERNAL_SECRET: "b".repeat(32) };
  it("production sem segredo ou DATABASE_URL falha", () => {
    expect(() => loadConfig({ ...good, AUTH_SECRET: undefined })).toThrow(ConfigError);
    expect(() => loadConfig({ ...good, GAME_SESSION_INTERNAL_SECRET: "" })).toThrow(/obrigatorio/);
    expect(() => loadConfig({ ...good, DATABASE_URL: undefined })).toThrow(/DATABASE_URL/);
  });
  it("production com segredo curto ou igual falha; sem vazar o valor", () => {
    expect(() => loadConfig({ ...good, AUTH_SECRET: "curto" })).toThrow(/32/);
    try { loadConfig({ ...good, AUTH_SECRET: "curto-secreto" }); } catch (e) { expect(String(e)).not.toContain("curto-secreto"); }
    expect(() => loadConfig({ ...good, GAME_SESSION_INTERNAL_SECRET: good.AUTH_SECRET })).toThrow(/diferentes/);
  });
  it("production valida passa", () => {
    const c = loadConfig(good);
    expect(c.isProduction).toBe(true);
    expect(c.ephemeralSecrets).toBe(false);
  });
  it("dev sem segredos gera valores efemeros aleatorios", () => {
    const a = loadConfig({}), b = loadConfig({});
    expect(a.ephemeralSecrets).toBe(true);
    expect(a.authSecret.length).toBeGreaterThanOrEqual(32);
    expect(a.authSecret).not.toBe(b.authSecret);
    expect(a.authSecret).not.toBe(a.gameSessionInternalSecret);
  });
  it("valida inteiros e NODE_ENV", () => {
    expect(() => loadConfig({ PORT: "abc" })).toThrow(/PORT/);
    expect(() => loadConfig({ NODE_ENV: "staging" })).toThrow(/NODE_ENV/);
    expect(loadConfig({ PORT: "9000" }).port).toBe(9000);
  });
});

describe("RateLimiter", () => {
  it("token bucket com relogio injetado", () => {
    let t = 0;
    const rl = new RateLimiter({ capacity: 3, refillPerSecond: 1, now: () => t });
    expect([1, 2, 3].map(() => rl.take("k").allowed)).toEqual([true, true, true]);
    const denied = rl.take("k");
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterMs).toBe(1000);
    expect(rl.take("outra").allowed).toBe(true);
    t = 1000;
    expect(rl.take("k").allowed).toBe(true);
    expect(rl.take("k").allowed).toBe(false);
    t = 60_000;
    expect(rl.take("k", 3).allowed).toBe(true); // teto = capacity
  });
  it("limita o numero de chaves", () => {
    const rl = new RateLimiter({ capacity: 2, refillPerSecond: 1, maxKeys: 5, now: () => 0 });
    for (let i = 0; i < 50; i++) rl.take(`k${i}`);
    expect(rl.size).toBeLessThanOrEqual(5);
  });
});

describe("logger", () => {
  it("mascara segredos, tokens, senhas e e-mails", () => {
    const lines: string[] = [];
    const log = createLogger({ level: "debug", sink: (l) => lines.push(l) });
    const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl";
    log.info(`login de maria@example.com com Bearer abc.def-123`, {
      password: "hunter2",
      email: "maria@example.com",
      nested: { refreshToken: "rt-123", authorization: `Bearer ${jwt}`, note: `token ${jwt} e joao@dominio.org` },
      dsn: "postgres://user:pw123@host/db",
      ok: 42,
    });
    log.error("falha", { error: new Error("erro para ana@x.com") });
    const all = lines.join("\n");
    for (const leak of ["hunter2", "maria@example.com", "rt-123", jwt, "joao@dominio.org", "pw123", "ana@x.com", "abc.def-123"]) {
      expect(all).not.toContain(leak);
    }
    expect(all).toContain('"ok":42');
    expect(all).toContain("m***@e***.com");
    expect(maskEmail("maria@example.com")).toBe("m***@e***.com");
  });
  it("respeita o nivel", () => {
    const lines: string[] = [];
    const log = createLogger({ level: "warn", sink: (l) => lines.push(l) });
    log.info("x"); log.warn("y");
    expect(lines).toHaveLength(1);
  });
});
