import { loadMigrations } from "../persistence/migrate.ts";
import type { RouteDeps } from "./app.ts";
import { json } from "./respond.ts";
import type { Router } from "./router.ts";

/**
 * Sondas operacionais (E7.1), sem dados sensiveis (sem versao de DB, env ou config):
 * - `GET /v1/health`  liveness+DB: 200 `ok` / 503 `degraded` (compat. E4).
 * - `GET /v1/ready`   readiness: DB responde E todas as migracoes do disco estao aplicadas (checksum conferido pelo runner). 503 caso contrario.
 * - `GET /internal/metrics` (segredo interno): contadores/latencia da instancia + jogadores online e sessoes vivas (contagens agregadas).
 */
export function registerHealthRoutes(router: Router, deps: RouteDeps): void {
  const expected = (() => {
    try {
      return loadMigrations().length;
    } catch {
      return -1;
    }
  })();

  router.get("/v1/health", async () => {
    let dbOk = true;
    try {
      await deps.db.query("SELECT 1");
    } catch {
      dbOk = false;
    }
    return json(dbOk ? 200 : 503, { status: dbOk ? "ok" : "degraded", db: dbOk ? "ok" : "down" });
  });

  router.get("/v1/ready", async () => {
    let db = "ok";
    let migrations = "ok";
    try {
      const r = await deps.db.query<{ n: number | string; max: number | string | null }>("SELECT count(*) AS n, max(version) AS max FROM schema_migrations");
      const n = Number(r.rows[0]?.n ?? 0);
      const max = Number(r.rows[0]?.max ?? 0);
      // Sem as migracoes em disco (bundle serverless) nao ha o que comparar: exige ao menos uma aplicada e sequencia contigua.
      if (expected < 0 ? n < 1 || max !== n : n !== expected || max !== expected) migrations = "pending";
    } catch {
      try {
        await deps.db.query("SELECT 1");
        migrations = "pending"; // banco responde mas sem tabela de migracoes
      } catch {
        db = "down";
        migrations = "unknown";
      }
    }
    const ready = db === "ok" && migrations === "ok";
    return json(ready ? 200 : 503, { status: ready ? "ready" : "not_ready", db, migrations });
  });

  router.get("/internal/metrics", deps.requireInternal(async () => {
    const snap = deps.metrics.snapshot();
    let online = -1;
    let sessions = -1;
    try {
      const stale = new Date(deps.now() - 30_000).toISOString();
      const a = await deps.db.query<{ n: number | string }>(
        `SELECT count(*) AS n FROM character_locks l JOIN game_sessions s ON s.id = l.session_id
          WHERE s.closed_at IS NULL AND s.heartbeat_at > $1::timestamptz AND l.heartbeat_at > $1::timestamptz AND l.reconnect_until IS NULL`, [stale]);
      const b = await deps.db.query<{ n: number | string }>("SELECT count(*) AS n FROM game_sessions WHERE closed_at IS NULL AND heartbeat_at > $1::timestamptz", [stale]);
      online = Number(a.rows[0]?.n ?? 0);
      sessions = Number(b.rows[0]?.n ?? 0);
    } catch {
      /* -1 = indisponivel */
    }
    return json(200, { ...snap, players_online: online, sessions_alive: sessions }, { "cache-control": "no-store" });
  }));
}
