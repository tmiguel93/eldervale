# Migracoes

Arquivos `NNNN_nome.sql` (4 digitos, sequencia contigua a partir de 0001, nome `[a-z0-9_]+`).
O runner (`src/persistence/migrate.ts`, `npm run migrate`) aplica cada arquivo em uma transacao,
registra em `schema_migrations(version, name, checksum, applied_at)` e e idempotente.

Regras:
- Nunca edite uma migracao ja aplicada: o checksum (SHA-256, fins de linha normalizados para LF)
  e verificado e a divergencia e erro. Corrija com uma NOVA migracao.
- Sem `BEGIN`/`COMMIT` dentro do arquivo. Evite DDL que nao roda em transacao
  (`CREATE INDEX CONCURRENTLY`); se for inevitavel, documente e revise.
- Em producao nao se apaga dado sem backup verificado (AGENTS 7). Nao ha `down` automatico.

## Plano de rollback por migracao

Formato: o que desfaz + pre-requisitos. Executar manualmente, em transacao, apos backup.

### 0001_initial_schema
Ainda sem dados de producao: desfazer = `DROP` das tabelas na ordem inversa de dependencia:
```sql
BEGIN;
DROP TABLE character_locks, join_tickets, game_sessions, party_invites, party_members, parties,
           reward_claims, character_equipment, character_inventory, characters,
           refresh_tokens, accounts;
DELETE FROM schema_migrations WHERE version = 1;
COMMIT;
```
Se ja houver dados reais: NAO executar; fazer `pg_dump` verificado e restaurar o backup anterior
(a restauracao e o rollback). Teste a restauracao em staging antes de qualquer producao.

### 0002_game_sessions_heartbeat
Aditiva (coluna NOT NULL com default). Desfazer (apos backup; destrutivo so para a coluna):
```sql
BEGIN;
ALTER TABLE game_sessions DROP COLUMN heartbeat_at;
DELETE FROM schema_migrations WHERE version = 2;
COMMIT;
```
Impacto: o codigo M4 de sessoes passa a exigir a coluna; reverter a migracao exige reverter o codigo antes.

### 0003_character_quests
Aditiva (coluna jsonb NOT NULL com default `{}`). Desfazer (apos backup; PERDE o progresso/conclusao de quests):
```sql
BEGIN;
ALTER TABLE characters DROP COLUMN quests;
DELETE FROM schema_migrations WHERE version = 3;
COMMIT;
```
Impacto: o codigo E5.1 (src/quests, characters/service.ts) le/grava a coluna; reverter a migracao exige reverter o codigo antes.
Recompensas ja pagas (`reward_claims` com chave `quest:...`) permanecem; sem a coluna uma quest concluida poderia ser aceita de novo
e a recompensa NAO duplicaria (a chave idempotente e a mesma), mas o jogador nao a receberia outra vez.

### Modelo para novas migracoes
Toda migracao nova deve acrescentar aqui sua secao: SQL de desfazer (preferir mudancas
aditivas/expand-contract: adicionar coluna nullable -> backfill -> restringir), impacto em dados,
e se o rollback e destrutivo (exige backup).
