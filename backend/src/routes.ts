import { registerAuthRoutes } from "./auth/routes.ts";
import { registerCharactersRoutes } from "./characters/routes.ts";
import type { RouteDeps } from "./http/app.ts";
import { registerHealthRoutes } from "./http/health.ts";
import type { Router } from "./http/router.ts";
import { registerPartiesRoutes } from "./parties/routes.ts";
import { registerSessionsRoutes } from "./sessions/routes.ts";

/** Ponto unico de registro. M2-M4 so preenchem seus proprios modulos. */
export function registerRoutes(router: Router, deps: RouteDeps): void {
  registerHealthRoutes(router, deps);
  registerAuthRoutes(router, deps);
  registerCharactersRoutes(router, deps);
  registerPartiesRoutes(router, deps);
  registerSessionsRoutes(router, deps);
}
