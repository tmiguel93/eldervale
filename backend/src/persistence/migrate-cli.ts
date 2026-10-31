import { migrate } from "./migrate.ts";
import { openDb } from "./open.ts";
import { DEV_PGLITE_DIR } from "./paths.ts";

// Nao usa loadConfig(): migrar nao exige segredos de auth.
const config = { databaseUrl: process.env.DATABASE_URL?.trim() || undefined };
const usingPg = Boolean(config.databaseUrl);
const db = await openDb(config, DEV_PGLITE_DIR);
try {
  const r = await migrate(db);
  console.log(`[migrate] alvo=${usingPg ? "postgres (DATABASE_URL)" : DEV_PGLITE_DIR}`);
  console.log(`[migrate] ja aplicadas: ${r.alreadyApplied.join(",") || "-"}; aplicadas agora: ${r.applied.join(",") || "-"}`);
} catch (e) {
  console.error(`[migrate] ERRO: ${e instanceof Error ? e.message : String(e)}`);
  process.exitCode = 1;
} finally {
  await db.close();
}
