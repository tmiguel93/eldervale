import type { Config } from "../config.ts";
import type { Db } from "./db.ts";
import { createPgDb } from "./pg.ts";
import { createPgliteDb } from "./pglite.ts";

/** pg se houver DATABASE_URL; senao PGlite (persistente em `pgliteDir`, ou memoria). */
export async function openDb(config: Pick<Config, "databaseUrl">, pgliteDir?: string): Promise<Db> {
  if (config.databaseUrl) return createPgDb(config.databaseUrl);
  return createPgliteDb(pgliteDir);
}
