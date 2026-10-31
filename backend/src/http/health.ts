import type { RouteDeps } from "./app.ts";
import { json } from "./respond.ts";
import type { Router } from "./router.ts";

/** GET /v1/health: sem dados sensiveis (sem versao de DB, env ou config). */
export function registerHealthRoutes(router: Router, deps: RouteDeps): void {
  router.get("/v1/health", async () => {
    let dbOk = true;
    try {
      await deps.db.query("SELECT 1");
    } catch {
      dbOk = false;
    }
    return json(dbOk ? 200 : 503, { status: dbOk ? "ok" : "degraded", db: dbOk ? "ok" : "down" });
  });
}
