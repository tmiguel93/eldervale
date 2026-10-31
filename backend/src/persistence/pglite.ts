import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { PGlite, types } from "@electric-sql/pglite";
import { createTxDb, type Db, type QueryResult } from "./db.ts";

/**
 * PGlite (Postgres em WASM). `dataDir` undefined => memoria (testes); caminho => persistente (dev).
 * int8/numeric sao devolvidos como string para igualar o driver `pg`.
 */
// O parser de int8 so e aplicado por consulta (a opcao do construtor nao vale para int8 na 0.5.x).
const QUERY_OPTS = { parsers: { [types.INT8]: (v: string) => v, [types.NUMERIC]: (v: string) => v } };

export async function createPgliteDb(dataDir?: string): Promise<Db> {
  if (dataDir) mkdirSync(dirname(dataDir), { recursive: true });
  const lite = new PGlite(dataDir);
  await lite.waitReady;

  const wrap = (r: { rows: unknown[]; affectedRows?: number }): QueryResult<any> => ({
    rows: r.rows,
    rowCount: r.affectedRows ?? r.rows.length,
  });

  return {
    async query(sql, params) {
      return wrap(await lite.query(sql, params as unknown[] | undefined, QUERY_OPTS));
    },
    async exec(sql) {
      await lite.exec(sql);
    },
    async tx(fn) {
      return lite.transaction(async (t) =>
        fn(
          createTxDb({
            query: async (sql, params) => wrap(await t.query(sql, params as unknown[] | undefined, QUERY_OPTS)),
            exec: async (sql) => {
              await t.exec(sql);
            },
          }),
        ),
      );
    },
    async close() {
      await lite.close();
    },
  } as Db;
}
