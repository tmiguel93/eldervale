import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Db } from "./db.ts";
import { MIGRATIONS_DIR } from "./paths.ts";

export interface Migration {
  version: number;
  name: string;
  sql: string;
  checksum: string;
}

export class MigrationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MigrationError";
  }
}

const FILE_RE = /^(\d{4})_([a-z0-9_]+)\.sql$/;
/** Chave do advisory lock que serializa runners concorrentes. */
const LOCK_KEY = 727_274_001;

/** SHA-256 do conteudo com fins de linha normalizados (CRLF do Windows nao muda o checksum). */
export function checksumOf(sql: string): string {
  return createHash("sha256").update(sql.replace(/\r\n/g, "\n")).digest("hex");
}

export function loadMigrations(dir: string = MIGRATIONS_DIR): Migration[] {
  const out: Migration[] = [];
  for (const file of readdirSync(dir).sort()) {
    if (!file.endsWith(".sql")) continue;
    const m = FILE_RE.exec(file);
    if (!m) throw new MigrationError(`Nome de migracao invalido: ${file}`);
    const sql = readFileSync(join(dir, file), "utf8");
    out.push({ version: Number(m[1]), name: m[2]!, sql, checksum: checksumOf(sql) });
  }
  out.forEach((mig, i) => {
    if (mig.version !== i + 1) {
      throw new MigrationError(`Sequencia de migracoes nao contigua: esperado ${i + 1}, achei ${mig.version}`);
    }
  });
  return out;
}

export interface MigrateResult {
  applied: number[];
  alreadyApplied: number[];
}

interface AppliedRow {
  version: number;
  name: string;
  checksum: string;
}

/** Aplica migracoes pendentes. Idempotente; erro se uma ja aplicada foi alterada ou sumiu. */
export async function migrate(db: Db, opts: { dir?: string; migrations?: Migration[] } = {}): Promise<MigrateResult> {
  const migrations = opts.migrations ?? loadMigrations(opts.dir);

  await db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version    integer PRIMARY KEY CHECK (version >= 1),
    name       text NOT NULL,
    checksum   text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
  )`);

  const verify = async (q: Db): Promise<AppliedRow[]> => {
    const { rows } = await q.query<AppliedRow>("SELECT version, name, checksum FROM schema_migrations ORDER BY version");
    for (const r of rows) {
      const file = migrations.find((m) => m.version === r.version);
      if (!file) throw new MigrationError(`Migracao ${r.version} (${r.name}) esta aplicada no banco mas nao existe em disco`);
      if (file.checksum !== r.checksum) {
        throw new MigrationError(`Checksum alterado na migracao ja aplicada ${r.version} (${r.name}). Crie uma nova migracao em vez de editar.`);
      }
    }
    return rows;
  };

  const result: MigrateResult = { applied: [], alreadyApplied: [] };
  const initial = await verify(db);
  result.alreadyApplied = initial.map((r) => r.version);

  for (const mig of migrations) {
    if (result.alreadyApplied.includes(mig.version)) continue;
    await db.tx(async (t) => {
      await t.query("SELECT pg_advisory_xact_lock($1)", [LOCK_KEY]);
      // Reconfere sob o lock: outro runner pode ter aplicado enquanto esperavamos.
      const applied = await verify(t);
      if (applied.some((r) => r.version === mig.version)) return;
      await t.exec(mig.sql);
      await t.query("INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)", [
        mig.version,
        mig.name,
        mig.checksum,
      ]);
      result.applied.push(mig.version);
    });
  }
  return result;
}
