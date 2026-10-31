import { loadConfig, type Config } from "../src/config.ts";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { migrate } from "../src/persistence/migrate.ts";
import type { Db } from "../src/persistence/db.ts";

export function testConfig(over: Record<string, string> = {}): Config {
  return loadConfig({ NODE_ENV: "test", ...over });
}

export async function freshDb(): Promise<Db> {
  const db = await createPgliteDb();
  await migrate(db);
  return db;
}

export async function mkAccount(db: Db, email = "a@example.com"): Promise<string> {
  const r = await db.query<{ id: string }>("INSERT INTO accounts (email, password_hash) VALUES ($1, 'x') RETURNING id", [email]);
  return r.rows[0]!.id;
}

export async function mkCharacter(db: Db, accountId: string, name = "Aria"): Promise<string> {
  const r = await db.query<{ id: string }>("INSERT INTO characters (account_id, name, class_id) VALUES ($1, $2, 'warrior') RETURNING id", [accountId, name]);
  return r.rows[0]!.id;
}

export async function mkSession(db: Db): Promise<string> {
  const r = await db.query<{ id: string }>("INSERT INTO game_sessions (region, capacity, protocol_version) VALUES ('sa', 4, 1) RETURNING id");
  return r.rows[0]!.id;
}
