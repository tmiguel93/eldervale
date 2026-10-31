/**
 * Adaptador Vercel Functions (Web-standard fetch handler). NAO TESTADO NA VERCEL e nenhum deploy foi feito.
 * Em producao exige DATABASE_URL, AUTH_SECRET e GAME_SESSION_INTERNAL_SECRET (>=32 chars) nas env vars.
 * Migracoes NAO rodam aqui: execute `npm run migrate` contra o banco como etapa separada.
 * O catch-all serve /api/*; o prefixo "/api" e removido antes do roteamento (veja vercel.json).
 */
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import type { App } from "../src/http/app.ts";
import { migrate } from "../src/persistence/migrate.ts";
import { openDb } from "../src/persistence/open.ts";

let appPromise: Promise<App> | undefined;

function getApp(): Promise<App> {
  appPromise ??= (async () => {
    const config = loadConfig();
    const db = await openDb(config); // sem DATABASE_URL (nao-producao): PGlite em memoria
    if (!config.databaseUrl) await migrate(db);
    return buildApp({ config, db });
  })();
  appPromise.catch(() => {
    appPromise = undefined; // permite nova tentativa na proxima invocacao
  });
  return appPromise;
}

async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/api" || url.pathname.startsWith("/api/")) {
    url.pathname = url.pathname.slice(4) || "/";
    request = new Request(url, request);
  }
  return (await getApp()).handle(request);
}

export default { fetch: handler };
