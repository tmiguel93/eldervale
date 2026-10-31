import pg from "pg";
import { createTxDb, type Db, type QueryResult } from "./db.ts";

export interface PgDbOptions {
  /** Tamanho maximo do pool. Em Functions serverless mantenha pequeno (padrao 3). */
  max?: number;
}

export function createPgDb(databaseUrl: string, opts: PgDbOptions = {}): Db {
  const pool = new pg.Pool({
    connectionString: databaseUrl,
    max: opts.max ?? 3,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
  });
  // Erro em conexao ociosa nao deve derrubar o processo.
  pool.on("error", () => {});

  const wrap = (r: pg.QueryResult): QueryResult<any> => ({ rows: r.rows, rowCount: r.rowCount ?? 0 });

  return {
    async query(sql, params) {
      return wrap(await pool.query(sql, params as unknown[] | undefined));
    },
    async exec(sql) {
      await pool.query(sql);
    },
    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const txDb = createTxDb({
          query: async (sql, params) => wrap(await client.query(sql, params as unknown[] | undefined)),
          exec: async (sql) => {
            await client.query(sql);
          },
        });
        const out = await fn(txDb);
        await client.query("COMMIT");
        return out;
      } catch (e) {
        try {
          await client.query("ROLLBACK");
        } catch {
          /* conexao ja quebrada; o release abaixo a descarta */
        }
        throw e;
      } finally {
        client.release();
      }
    },
    async close() {
      await pool.end();
    },
  } as Db;
}
