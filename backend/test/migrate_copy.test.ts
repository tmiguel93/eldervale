// E7.1: migracoes em COPIA de dados. Para cada versao anterior (1..5): cria o banco naquela versao, grava dados sinteticos validos
// naquele esquema, aplica as migracoes restantes e confere integridade (contagens, conteudo das colunas antigas, defaults novos,
// restricoes, leitura pela aplicacao). Tambem executa o SQL de rollback DOCUMENTADO em migrations/README.md (o teste le o README).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { createLogger } from "../src/http/logger.ts";
import { loadCatalogFromDisk } from "../src/characters/catalog.ts";
import { DEFAULT_LIMITS } from "../src/characters/limits.ts";
import { loadRecord } from "../src/characters/service.ts";
import { createPgliteDb } from "../src/persistence/pglite.ts";
import { loadMigrations, migrate } from "../src/persistence/migrate.ts";
import { MIGRATIONS_DIR } from "../src/persistence/paths.ts";
import type { Db } from "../src/persistence/db.ts";

const ALL = loadMigrations();
const A1 = "aaaaaaaa-0000-4000-8000-000000000001";
const A2 = "aaaaaaaa-0000-4000-8000-000000000002";
const A3 = "aaaaaaaa-0000-4000-8000-000000000003";
const C1 = "cccccccc-0000-4000-8000-000000000001";
const C2 = "cccccccc-0000-4000-8000-000000000002";
const C3 = "cccccccc-0000-4000-8000-000000000003";
const C4 = "cccccccc-0000-4000-8000-000000000004";
const P1 = "dddddddd-0000-4000-8000-000000000001";
const S1 = "eeeeeeee-0000-4000-8000-000000000001";
const STATS = (atk: number) => JSON.stringify({ max_health: 100, max_resource: 50, resource_regen: 5, attack_power: atk, defense: 1, resistance: 0.1, move_speed: 5 });

/** Dados sinteticos validos no esquema da versao 1 (colunas que existem desde o 0001). Sem dado real. */
async function seedV1(db: Db): Promise<void> {
  await db.query("INSERT INTO accounts (id, email, password_hash) VALUES ($1,'a1@example.test','scrypt$x'),($2,'a2@example.test','scrypt$x'),($3,'a3@example.test','scrypt$x')", [A1, A2, A3]);
  await db.query(
    `INSERT INTO characters (id, account_id, name, class_id, level, xp, stats, revision) VALUES
       ($4,$1,'Alfa','warrior',3,300,$8::jsonb,7),($5,$1,'Bravo','warrior',1,0,$9::jsonb,0),
       ($6,$2,'Carlos','warrior',10,4200,$10::jsonb,42),($7,$3,'Delta','warrior',2,120,$8::jsonb,3)`,
    [A1, A2, A3, C1, C2, C3, C4, STATS(10), STATS(11), STATS(30)]);
  await db.query("UPDATE characters SET deleted_at = now() WHERE id = $1", [C4]); // soft delete preservado
  await db.query(
    `INSERT INTO character_inventory (character_id, slot, item_id, qty) VALUES ($1,0,'potion_minor',5),($1,1,'scrap_material',12),($2,0,'sword_basic',1),($3,0,'potion_minor',99)`,
    [C1, C2, C3]);
  await db.query(`INSERT INTO character_equipment (character_id, slot_name, item_id) VALUES ($1,'weapon','sword_basic'),($1,'armor','armor_leather'),($2,'weapon','sword_basic')`, [C1, C3]);
  await db.query(`INSERT INTO reward_claims (character_id, idempotency_key, payload) VALUES ($1,'quest:gw_welcome:x01','{"request":"r","result":{"xp_granted":60}}'::jsonb),($2,'boss-kill-0000001','{"request":"r2","result":{"xp_granted":1200}}'::jsonb)`, [C1, C3]);
  await db.query("INSERT INTO parties (id, leader_account_id) VALUES ($1,$2)", [P1, A1]);
  await db.query("INSERT INTO party_members (party_id, character_id) VALUES ($1,$2),($1,$3)", [P1, C1, C3]);
  await db.query("INSERT INTO party_invites (party_id, target_character_id, expires_at) VALUES ($1,$2,now() + interval '1 day')", [P1, C2]);
  await db.query("INSERT INTO game_sessions (id, region, status, capacity, protocol_version, endpoint) VALUES ($1,'sa-east','open',4,2,'127.0.0.1:24680')", [S1]);
  await db.query("INSERT INTO join_tickets (jti_hash, character_id, session_id, expires_at) VALUES ('h1',$1,$2,now() + interval '1 minute')", [C1, S1]);
  await db.query("INSERT INTO character_locks (character_id, session_id) VALUES ($1,$2)", [C1, S1]);
  await db.query("INSERT INTO refresh_tokens (account_id, token_hash, expires_at) VALUES ($1,'th1',now() + interval '30 days')", [A1]);
}

const TABLES_V1 = ["accounts", "refresh_tokens", "characters", "character_inventory", "character_equipment", "reward_claims", "parties", "party_members", "party_invites", "game_sessions", "join_tickets", "character_locks"];
// Colunas que existem desde a v1 (comparadas antes/depois). game_sessions.heartbeat_at nasce no 0002 e e ignorada na comparacao.
const OLD_COLS: Record<string, string> = {
  accounts: "id, email, password_hash, disabled",
  refresh_tokens: "account_id, token_hash, revoked_at",
  characters: "id, account_id, name, class_id, level, xp::text AS xp, stats, schema_version, revision::text AS revision, (deleted_at IS NOT NULL) AS deleted",
  character_inventory: "character_id, slot, item_id, qty",
  character_equipment: "character_id, slot_name, item_id",
  reward_claims: "character_id, idempotency_key, payload",
  parties: "id, leader_account_id, (disbanded_at IS NOT NULL) AS disbanded",
  party_members: "party_id, character_id",
  party_invites: "party_id, target_character_id, status",
  game_sessions: "id, region, status, capacity, protocol_version, endpoint, (closed_at IS NOT NULL) AS closed",
  join_tickets: "jti_hash, character_id, session_id, (used_at IS NOT NULL) AS used",
  character_locks: "character_id, session_id",
};

async function fingerprint(db: Db): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  for (const t of TABLES_V1) {
    const r = await db.query<{ j: unknown }>(`SELECT row_to_json(x) AS j FROM (SELECT ${OLD_COLS[t]} FROM ${t}) x ORDER BY 1::text`);
    out[t] = JSON.stringify(r.rows.map((x) => x.j).map((j) => JSON.stringify(j)).sort());
  }
  return out;
}

const count = async (db: Db, t: string) => Number((await db.query<{ n: number | string }>(`SELECT count(*) AS n FROM ${t}`)).rows[0]!.n);

describe("migracoes em copia de dados (E7.1)", () => {
  for (const from of [1, 2, 3, 4, 5]) {
    it(`banco na v${from} com dados sinteticos -> aplica ${from + 1}..${ALL.length}: dados intactos, defaults novos, app le`, async () => {
      const db = await createPgliteDb();
      await migrate(db, { migrations: ALL.slice(0, from) });
      // Os dados sinteticos usam colunas da v1; 0002+ so acrescentam colunas com default, entao o seed vale para qualquer from.
      await seedV1(db);
      const before = await fingerprint(db);
      const counts: Record<string, number> = {};
      for (const t of TABLES_V1) counts[t] = await count(db, t);
      const sumXp = (await db.query<{ s: string }>("SELECT sum(xp)::text AS s FROM characters")).rows[0]!.s;

      const r = await migrate(db); // restante, a partir da copia
      expect(r.applied).toEqual(ALL.slice(from).map((m) => m.version));

      expect(await fingerprint(db)).toEqual(before); // nenhuma coluna antiga mudou
      for (const t of TABLES_V1) expect(await count(db, t), t).toBe(counts[t]);
      expect((await db.query<{ s: string }>("SELECT sum(xp)::text AS s FROM characters")).rows[0]!.s).toBe(sumXp);

      // checksums gravados = checksums do disco
      const sm = await db.query<{ version: number; checksum: string }>("SELECT version, checksum FROM schema_migrations ORDER BY version");
      expect(sm.rows.map((x) => x.version)).toEqual(ALL.map((m) => m.version));
      expect(sm.rows.map((x) => x.checksum)).toEqual(ALL.map((m) => m.checksum));

      // defaults das colunas novas
      const ch = await db.query<{ quests: unknown; talents: unknown }>("SELECT quests, talents FROM characters ORDER BY name");
      for (const row of ch.rows) { expect(row.quests).toEqual({}); expect(row.talents).toEqual({}); }
      const inst = await db.query<{ n: number | string }>("SELECT (SELECT count(*) FROM character_inventory WHERE inst IS NOT NULL) + (SELECT count(*) FROM character_equipment WHERE inst IS NOT NULL) AS n");
      expect(Number(inst.rows[0]!.n)).toBe(0);
      expect((await db.query("SELECT 1 FROM game_sessions WHERE heartbeat_at IS NOT NULL")).rows).toHaveLength(1);

      // a aplicacao le o personagem migrado exatamente como foi gravado
      const rec = await loadRecord(db, C1);
      expect(rec).not.toBeNull();
      expect(rec!.state.level).toBe(3);
      expect(rec!.state.xp).toBe(300);
      expect(rec!.revision).toBe(7);
      expect(rec!.state.inventory.map((e) => `${e.slot}:${e.item_id}:${e.qty}`)).toEqual(["0:potion_minor:5", "1:scrap_material:12"]);
      expect(rec!.state.equipment).toEqual({ weapon: "sword_basic", armor: "armor_leather" });
      expect(rec!.state.stats.attack_power).toBe(10);
      expect(rec!.state.quests?.completed ?? []).toEqual([]);
      expect(await loadRecord(db, C4)).toBeNull(); // apagado continua apagado
      expect(loadCatalogFromDisk().get("potion_minor")).toBeTruthy();
      expect(DEFAULT_LIMITS.inventoryCapacity).toBeGreaterThan(0);

      // restricoes novas valem sobre os dados migrados
      await expect(db.query("UPDATE characters SET quests = '[]'::jsonb WHERE id = $1", [C1])).rejects.toThrow();
      await expect(db.query("UPDATE characters SET talents = '[]'::jsonb WHERE id = $1", [C1])).rejects.toThrow();
      await db.query("UPDATE character_inventory SET inst = $2::jsonb WHERE character_id = $1 AND slot = 0", [C1, JSON.stringify({ uid: "u1" })]);
      await expect(db.query("UPDATE character_inventory SET inst = $2::jsonb WHERE character_id = $1 AND slot = 1", [C1, JSON.stringify({ uid: "u1" })])).rejects.toThrow(); // uid unico por personagem
      // idempotencia de recompensas segue valendo
      await expect(db.query("INSERT INTO reward_claims (character_id, idempotency_key, payload) VALUES ($1,'quest:gw_welcome:x01','{}'::jsonb)", [C1])).rejects.toThrow();
      // reexecutar nao muda nada
      expect((await migrate(db)).applied).toEqual([]);
      await db.close();
    }, 60_000);
  }

  it("0004 normaliza class_id malformado de dados antigos e preserva ids bem formados (incl. classes futuras)", async () => {
    const db = await createPgliteDb();
    await migrate(db, { migrations: ALL.slice(0, 3) });
    await db.query("INSERT INTO accounts (id, email, password_hash) VALUES ($1,'x@example.test','h')", [A1]);
    await db.query("INSERT INTO characters (id, account_id, name, class_id) VALUES ($2,$1,'Velho','Classe Estranha!'),($3,$1,'Futuro','summoner_x'),($4,$1,'Normal','warrior')", [A1, C1, C2, C3]);
    await migrate(db);
    const r = await db.query<{ name: string; class_id: string }>("SELECT name, class_id FROM characters ORDER BY name");
    expect(Object.fromEntries(r.rows.map((x) => [x.name, x.class_id]))).toEqual({ Velho: "warrior", Futuro: "summoner_x", Normal: "warrior" });
    await db.close();
  }, 60_000);

  it("SQL de rollback do README (0006 e 0005) roda sobre a copia migrada, preserva os dados e a migracao pode ser reaplicada", async () => {
    const readme = readFileSync(join(MIGRATIONS_DIR, "README.md"), "utf8");
    const rollback = (name: string): string => {
      const m = new RegExp(`### ${name}[\\s\\S]*?\`\`\`sql\\n([\\s\\S]*?)\`\`\``).exec(readme);
      if (!m) throw new Error(`rollback de ${name} nao encontrado no README`);
      return m[1]!;
    };
    const db = await createPgliteDb();
    await migrate(db);
    await seedV1(db);
    await db.query("UPDATE character_inventory SET inst = $2::jsonb WHERE character_id = $1 AND slot = 0", [C1, JSON.stringify({ uid: "u1", rarity: "rare", ilvl: 3, affixes: [] })]);
    await db.query("UPDATE characters SET talents = $2::jsonb, quests = $3::jsonb WHERE id = $1", [C1, JSON.stringify({ spec: "berserker", ranks: { w_might: 1 }, respecs: 0 }), JSON.stringify({ active: {}, completed: ["gw_welcome"] })]);
    const before = await fingerprint(db);
    await db.exec(rollback("0006_item_instances"));
    expect((await db.query("SELECT column_name FROM information_schema.columns WHERE table_name='character_inventory' AND column_name='inst'")).rows).toHaveLength(0);
    await db.exec(rollback("0005_character_talents"));
    expect((await db.query("SELECT column_name FROM information_schema.columns WHERE table_name='characters' AND column_name='talents'")).rows).toHaveLength(0);
    expect(await fingerprint(db)).toEqual(before); // dados antigos intactos apos os dois rollbacks
    expect((await db.query<{ quests: { completed: string[] } }>("SELECT quests FROM characters WHERE id=$1", [C1])).rows[0]!.quests.completed).toEqual(["gw_welcome"]);
    expect((await db.query("SELECT version FROM schema_migrations ORDER BY version")).rows.map((x: any) => x.version)).toEqual([1, 2, 3, 4]);
    const again = await migrate(db); // reaplica 5 e 6 (checksum conferido)
    expect(again.applied).toEqual([5, 6]);
    expect(await fingerprint(db)).toEqual(before);
    await db.close();
  }, 60_000);
});
