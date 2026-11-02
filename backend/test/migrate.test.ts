import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { checksumOf, loadMigrations, migrate, MigrationError } from "../src/persistence/migrate.ts";
import { BACKEND_ROOT, MIGRATIONS_DIR } from "../src/persistence/paths.ts";

// Diretorios temporarios ficam DENTRO do projeto (regra do proprietario), em backend/.data/ (ignorado pelo Git).
const TMP_ROOT = join(BACKEND_ROOT, ".data", "test-tmp");
mkdirSync(TMP_ROOT, { recursive: true });
afterAll(() => rmSync(TMP_ROOT, { recursive: true, force: true }));
const tmpDir = () => mkdtempSync(join(TMP_ROOT, "mig-"));

const EXPECTED_TABLES = [
  "accounts", "refresh_tokens", "characters", "character_inventory", "character_equipment", "reward_claims",
  "parties", "party_members", "party_invites", "game_sessions", "join_tickets", "character_locks", "schema_migrations",
];

describe("migracoes", () => {
  it("aplica do zero e cria todas as tabelas", async () => {
    const db = await createPgliteDb();
    const r = await migrate(db);
    expect(r.applied).toEqual([1, 2, 3, 4, 5, 6]);
    const { rows } = await db.query<{ table_name: string }>("SELECT table_name FROM information_schema.tables WHERE table_schema='public'");
    const names = rows.map((x) => x.table_name);
    for (const t of EXPECTED_TABLES) expect(names).toContain(t);
    const sm = await db.query<{ version: number; name: string; checksum: string }>("SELECT version, name, checksum FROM schema_migrations");
    expect(sm.rows).toHaveLength(6);
    expect(sm.rows[0]!.checksum).toMatch(/^[0-9a-f]{64}$/);
    await db.close();
  });

  it("reexecucao e idempotente", async () => {
    const db = await createPgliteDb();
    await migrate(db);
    const again = await migrate(db);
    expect(again.applied).toEqual([]);
    expect(again.alreadyApplied).toEqual([1, 2, 3, 4, 5, 6]);
    const c = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM schema_migrations");
    expect(c.rows[0]!.n).toBe(6);
    await db.close();
  });

  it("detecta checksum alterado de migracao ja aplicada", async () => {
    const dir = tmpDir();
    cpSync(MIGRATIONS_DIR, dir, { recursive: true });
    const db = await createPgliteDb();
    await migrate(db, { dir });
    writeFileSync(join(dir, "0001_initial_schema.sql"), "-- alterado\nSELECT 1;\n");
    await expect(migrate(db, { dir })).rejects.toThrow(MigrationError);
    await expect(migrate(db, { dir })).rejects.toThrow(/Checksum alterado/);
    await db.close();
  });

  it("aplica migracao nova e faz rollback transacional se falhar", async () => {
    const dir = tmpDir();
    cpSync(MIGRATIONS_DIR, dir, { recursive: true });
    const db = await createPgliteDb();
    await migrate(db, { dir });
    writeFileSync(join(dir, "0007_bad.sql"), "CREATE TABLE t_ok (id int);\nSELECT * FROM tabela_inexistente;\n");
    await expect(migrate(db, { dir })).rejects.toThrow();
    const t = await db.query("SELECT to_regclass('t_ok') AS r");
    expect((t.rows[0] as { r: unknown }).r).toBeNull();
    const n = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM schema_migrations");
    expect(n.rows[0]!.n).toBe(6);
    await db.close();
  });

  it("checksum ignora CRLF e a sequencia deve ser contigua", () => {
    expect(checksumOf("a\r\nb")).toBe(checksumOf("a\nb"));
    const dir = tmpDir();
    writeFileSync(join(dir, "0002_x.sql"), "SELECT 1;");
    expect(() => loadMigrations(dir)).toThrow(/contigua/);
  });
});
