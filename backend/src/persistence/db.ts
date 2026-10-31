/**
 * Interface unica de acesso ao banco. Implementacoes: createPgDb (pg Pool) e createPgliteDb (PGlite).
 *
 * Regras:
 *  - Parametros SEMPRE posicionais ($1, $2...). Nunca interpole valores no SQL.
 *  - bigint (int8) e numeric voltam como `string` nos dois drivers; jsonb volta ja parseado.
 *  - Dentro de `tx(fn)` use SOMENTE o `db` recebido por `fn` (nao o externo), senao a
 *    consulta sai da transacao (e, no PGlite, pode travar).
 *  - `tx` aninhado vira SAVEPOINT. Excecao => rollback e a excecao e relancada.
 */
export type Row = Record<string, unknown>;

export interface QueryResult<T> {
  rows: T[];
  rowCount: number;
}

export interface Db {
  query<T = Row>(sql: string, params?: readonly unknown[]): Promise<QueryResult<T>>;
  /** Executa SQL sem parametros, possivelmente com varios comandos (usado por migracoes). */
  exec(sql: string): Promise<void>;
  tx<T>(fn: (db: Db) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

/** Codigos SQLSTATE comuns, para M2-M4 tratarem conflitos. */
export const PgErrorCode = {
  uniqueViolation: "23505",
  foreignKeyViolation: "23503",
  checkViolation: "23514",
  notNullViolation: "23502",
} as const;

export function pgErrorCode(err: unknown): string | undefined {
  if (typeof err === "object" && err !== null && "code" in err) {
    const c = (err as { code: unknown }).code;
    return typeof c === "string" ? c : undefined;
  }
  return undefined;
}

export function isUniqueViolation(err: unknown): boolean {
  return pgErrorCode(err) === PgErrorCode.uniqueViolation;
}

/** Executor minimo de uma conexao/transacao; usado para montar o Db transacional. */
export interface Executor {
  query(sql: string, params?: readonly unknown[]): Promise<QueryResult<any>>;
  exec(sql: string): Promise<void>;
}

/** Db que vive dentro de uma transacao ja aberta (tx aninhado = savepoint). */
export function createTxDb(exec: Executor): Db {
  let depth = 0;
  const self: Db = {
    query: (sql, params) => exec.query(sql, params),
    exec: (sql) => exec.exec(sql),
    async tx<T>(fn: (db: Db) => Promise<T>): Promise<T> {
      const name = `sp_${++depth}`;
      await exec.exec(`SAVEPOINT ${name}`);
      try {
        const out = await fn(self);
        await exec.exec(`RELEASE SAVEPOINT ${name}`);
        return out;
      } catch (e) {
        await exec.exec(`ROLLBACK TO SAVEPOINT ${name}`);
        await exec.exec(`RELEASE SAVEPOINT ${name}`);
        throw e;
      } finally {
        depth--;
      }
    },
    async close() {
      throw new Error("close() nao pode ser chamado dentro de uma transacao");
    },
  };
  return self;
}
