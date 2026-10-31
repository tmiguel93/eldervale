import type { Config } from "./config.ts";
import { createAuthVerifier } from "./auth/verifier.ts";
import { createApp, type App } from "./http/app.ts";
import { createLogger, type Logger } from "./http/logger.ts";
import type { Db } from "./persistence/db.ts";
import { registerRoutes } from "./routes.ts";

/** Composition root usado pelos adaptadores (dev-server, Vercel) e pelos testes de integracao. */
export function buildApp(opts: { config: Config; db: Db; log?: Logger; now?: () => number }): App {
  const log = opts.log ?? createLogger({ level: opts.config.logLevel });
  const now = opts.now ?? Date.now;
  return createApp({
    config: opts.config,
    db: opts.db,
    log,
    now,
    authVerifier: createAuthVerifier({ config: opts.config, db: opts.db, now }),
    register: registerRoutes,
  });
}
