import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { isUniqueViolation, PgErrorCode, pgErrorCode, type Db } from "../src/persistence/db.ts";
import { freshDb, mkAccount, mkCharacter, mkSession } from "./helpers.ts";

let db: Db;
beforeAll(async () => { db = await freshDb(); });
afterAll(async () => { await db.close(); });

async function code(p: Promise<unknown>): Promise<string | undefined> {
  try { await p; } catch (e) { return pgErrorCode(e); }
  return undefined;
}

describe("constraints do esquema", () => {
  it("e-mail duplicado (case-insensitive) e rejeitado", async () => {
    await db.query("INSERT INTO accounts (email, password_hash) VALUES ('dup@example.com','x')");
    expect(await code(db.query("INSERT INTO accounts (email, password_hash) VALUES ('dup@example.com','x')"))).toBe(PgErrorCode.uniqueViolation);
    // nao normalizado (maiusculas) viola o CHECK
    expect(await code(db.query("INSERT INTO accounts (email, password_hash) VALUES ('DUP@example.com','x')"))).toBe(PgErrorCode.checkViolation);
  });

  it("nome de personagem duplicado (case-insensitive) e rejeitado; reutilizavel apos soft delete", async () => {
    const acc = await mkAccount(db, "c1@example.com");
    const id = await mkCharacter(db, acc, "Thor");
    let err: unknown;
    try { await mkCharacter(db, acc, "tHOR"); } catch (e) { err = e; }
    expect(isUniqueViolation(err)).toBe(true);
    await db.query("UPDATE characters SET deleted_at = now() WHERE id=$1", [id]);
    await expect(mkCharacter(db, acc, "THOR")).resolves.toBeTruthy();
  });

  it("level < 1, xp < 0 rejeitados", async () => {
    const acc = await mkAccount(db, "c2@example.com");
    expect(await code(db.query("INSERT INTO characters (account_id,name,class_id,level) VALUES ($1,'Lv0','w',0)", [acc]))).toBe(PgErrorCode.checkViolation);
    expect(await code(db.query("INSERT INTO characters (account_id,name,class_id,xp) VALUES ($1,'Xpneg','w',-1)", [acc]))).toBe(PgErrorCode.checkViolation);
  });

  it("qty <= 0 e slot < 0 rejeitados; xp volta como string (int8)", async () => {
    const acc = await mkAccount(db, "c3@example.com");
    const ch = await mkCharacter(db, acc, "Inv");
    expect(await code(db.query("INSERT INTO character_inventory VALUES ($1,0,'item.a',0)", [ch]))).toBe(PgErrorCode.checkViolation);
    expect(await code(db.query("INSERT INTO character_inventory VALUES ($1,0,'item.a',-3)", [ch]))).toBe(PgErrorCode.checkViolation);
    expect(await code(db.query("INSERT INTO character_inventory VALUES ($1,-1,'item.a',1)", [ch]))).toBe(PgErrorCode.checkViolation);
    await db.query("INSERT INTO character_inventory VALUES ($1,0,'item.a',2)", [ch]);
    expect(await code(db.query("INSERT INTO character_inventory VALUES ($1,0,'item.b',1)", [ch]))).toBe(PgErrorCode.uniqueViolation);
    const r = await db.query<{ xp: unknown; revision: unknown; stats: unknown }>("SELECT xp, revision, stats FROM characters WHERE id=$1", [ch]);
    expect(r.rows[0]).toEqual({ xp: "0", revision: "0", stats: {} });
  });

  it("lock unico por personagem", async () => {
    const acc = await mkAccount(db, "c4@example.com");
    const ch = await mkCharacter(db, acc, "Lock");
    const s1 = await mkSession(db);
    const s2 = await mkSession(db);
    await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [ch, s1]);
    expect(await code(db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [ch, s2]))).toBe(PgErrorCode.uniqueViolation);
  });

  it("recompensa idempotente e FKs", async () => {
    const acc = await mkAccount(db, "c5@example.com");
    const ch = await mkCharacter(db, acc, "Reward");
    await db.query("INSERT INTO reward_claims (character_id, idempotency_key, payload) VALUES ($1,'key-12345678','{}')", [ch]);
    expect(await code(db.query("INSERT INTO reward_claims (character_id, idempotency_key, payload) VALUES ($1,'key-12345678','{}')", [ch]))).toBe(PgErrorCode.uniqueViolation);
    expect(await code(db.query("INSERT INTO characters (account_id,name,class_id) VALUES ('00000000-0000-0000-0000-000000000000','Orfao','w')"))).toBe(PgErrorCode.foreignKeyViolation);
  });

  it("personagem em no maximo uma party", async () => {
    const acc = await mkAccount(db, "c6@example.com");
    const ch = await mkCharacter(db, acc, "Party");
    const p = async () => (await db.query<{ id: string }>("INSERT INTO parties (leader_account_id) VALUES ($1) RETURNING id", [acc])).rows[0]!.id;
    const p1 = await p(), p2 = await p();
    await db.query("INSERT INTO party_members (party_id, character_id) VALUES ($1,$2)", [p1, ch]);
    expect(await code(db.query("INSERT INTO party_members (party_id, character_id) VALUES ($1,$2)", [p2, ch]))).toBe(PgErrorCode.uniqueViolation);
  });
});

describe("Db.tx", () => {
  it("faz rollback em excecao e commit em sucesso", async () => {
    await db.exec("CREATE TABLE tx_t (n int)");
    await expect(db.tx(async (t) => {
      await t.query("INSERT INTO tx_t VALUES ($1)", [1]);
      throw new Error("boom");
    })).rejects.toThrow("boom");
    expect((await db.query("SELECT * FROM tx_t")).rows).toHaveLength(0);
    await db.tx(async (t) => { await t.query("INSERT INTO tx_t VALUES ($1)", [2]); });
    expect((await db.query("SELECT * FROM tx_t")).rows).toHaveLength(1);
  });

  it("tx aninhado usa savepoint (rollback parcial)", async () => {
    await db.exec("CREATE TABLE tx_n (n int)");
    await db.tx(async (t) => {
      await t.query("INSERT INTO tx_n VALUES (1)");
      await expect(t.tx(async (t2) => {
        await t2.query("INSERT INTO tx_n VALUES (2)");
        throw new Error("inner");
      })).rejects.toThrow("inner");
      await t.query("INSERT INTO tx_n VALUES (3)");
    });
    const r = await db.query<{ n: number }>("SELECT n FROM tx_n ORDER BY n");
    expect(r.rows.map((x) => x.n)).toEqual([1, 3]);
  });
});
