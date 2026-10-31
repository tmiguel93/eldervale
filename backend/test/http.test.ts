import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { createApp } from "../src/http/app.ts";
import { createLogger } from "../src/http/logger.ts";
import { Errors } from "../src/http/errors.ts";
import { json } from "../src/http/respond.ts";
import { freshDb, testConfig } from "./helpers.ts";

function mk(extra?: (r: import("../src/http/router.ts").Router, d: import("../src/http/app.ts").RouteDeps) => void, cfg = {}) {
  const lines: string[] = [];
  const log = createLogger({ level: "debug", sink: (l) => lines.push(l) });
  const app = createApp({
    config: testConfig(cfg),
    db: null as never,
    log,
    authVerifier: async (t) => (t === "good-token" ? { accountId: "acc-1" } : null),
    register: (r, d) => {
      r.get("/v1/ping", () => json(200, { pong: true }));
      r.post("/v1/echo", async (ctx) => json(200, await ctx.json()));
      r.get("/v1/things/:id", (ctx) => json(200, { id: ctx.params.id }));
      r.get("/v1/boom", () => { throw new Error("segredo-interno at /src/file.ts:10"); });
      r.get("/v1/me", d.requireAuth((ctx) => json(200, { account: ctx.auth.accountId })));
      r.get("/internal/x", d.requireInternal(() => json(200, { ok: true })));
      extra?.(r, d);
    },
  });
  return { app, lines };
}
const req = (path: string, init?: RequestInit) => new Request(`http://t${path}`, init);

describe("HTTP core", () => {
  it("404 padronizado", async () => {
    const { app } = mk();
    const res = await app.handle(req("/nada"));
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Rota nao encontrada" } });
  });

  it("405 com Allow", async () => {
    const { app } = mk();
    const res = await app.handle(req("/v1/ping", { method: "DELETE" }));
    expect(res.status).toBe(405);
    expect(res.headers.get("allow")).toBe("GET");
  });

  it("parametros de rota e cabecalhos de seguranca + request_id", async () => {
    const { app } = mk();
    const res = await app.handle(req("/v1/things/abc%20d", { headers: { "x-request-id": "my-req-id-123" } }));
    expect(await res.json()).toEqual({ id: "abc d" });
    expect(res.headers.get("x-request-id")).toBe("my-req-id-123");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("cache-control")).toBe("no-store");
    const gen = await app.handle(req("/v1/ping", { headers: { "x-request-id": "bad id!" } }));
    expect(gen.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("corpo grande => 413 (content-length e stream)", async () => {
    const { app } = mk();
    const big = JSON.stringify({ a: "x".repeat(70_000) });
    const r1 = await app.handle(req("/v1/echo", { method: "POST", headers: { "content-type": "application/json", "content-length": String(big.length) }, body: big }));
    expect(r1.status).toBe(413);
    const { app: small } = mk(undefined, { MAX_BODY_BYTES: "1024" });
    const r2 = await small.handle(req("/v1/echo", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ a: "y".repeat(2000) }) }));
    expect(r2.status).toBe(413);
  });

  it("content-type errado => 415; JSON invalido => 400; JSON valido ok", async () => {
    const { app } = mk();
    expect((await app.handle(req("/v1/echo", { method: "POST", headers: { "content-type": "text/plain" }, body: "{}" }))).status).toBe(415);
    const bad = await app.handle(req("/v1/echo", { method: "POST", headers: { "content-type": "application/json" }, body: "{oops" }));
    expect(bad.status).toBe(400);
    expect(((await bad.json()) as { error: { code: string } }).error.code).toBe("invalid_json");
    const good = await app.handle(req("/v1/echo", { method: "POST", headers: { "content-type": "application/json; charset=utf-8" }, body: '{"a":1}' }));
    expect(await good.json()).toEqual({ a: 1 });
  });

  it("erro inesperado => 500 sem stack nem mensagem interna; log sem vazar", async () => {
    const { app, lines } = mk();
    const res = await app.handle(req("/v1/boom"));
    expect(res.status).toBe(500);
    const text = await res.text();
    expect(text).not.toContain("segredo-interno");
    expect(text).not.toContain("file.ts");
    expect(JSON.parse(text)).toEqual({ error: { code: "internal_error", message: "Erro interno" } });
    expect(lines.some((l) => l.includes("unhandled_error"))).toBe(true);
    expect(lines.join("\n")).not.toContain("stack");
  });

  it("requireAuth: 401 sem/invalido, 200 com token bom", async () => {
    const { app } = mk();
    expect((await app.handle(req("/v1/me"))).status).toBe(401);
    expect((await app.handle(req("/v1/me", { headers: { authorization: "Bearer nope" } }))).status).toBe(401);
    const ok = await app.handle(req("/v1/me", { headers: { authorization: "Bearer good-token" } }));
    expect(await ok.json()).toEqual({ account: "acc-1" });
  });

  it("requireInternal compara o segredo de servico", async () => {
    const secret = "s".repeat(40);
    const { app } = mk(undefined, { GAME_SESSION_INTERNAL_SECRET: secret });
    expect((await app.handle(req("/internal/x", { headers: { authorization: "Bearer wrong" } }))).status).toBe(401);
    expect((await app.handle(req("/internal/x", { headers: { authorization: `Bearer ${secret}` } }))).status).toBe(200);
  });

  it("ApiError customizado vira JSON padrao com headers", async () => {
    const { app } = mk((r) => r.get("/v1/rl", () => { throw Errors.tooManyRequests(2.2); }));
    const res = await app.handle(req("/v1/rl"));
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("3");
  });

  it("GET /v1/health via buildApp com DB real", async () => {
    const db = await freshDb();
    const app = buildApp({ config: testConfig(), db });
    const res = await app.handle(req("/v1/health"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok", db: "ok" });
    await db.close();
  });
});
