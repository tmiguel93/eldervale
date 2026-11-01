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

### 0004_character_class_default
Aditiva e idempotente (E6.1). `characters.class_id` ja existia (0001); a migracao (1) normaliza para `'warrior'` apenas valores FORA do formato de id
estavel (`[a-z][a-z0-9_]{0,47}`; a API nunca os produz), (2) define `DEFAULT 'warrior'` e (3) adiciona o CHECK `characters_class_id_format`
(somente se ausente). Ids bem formados, inclusive de classes futuras, nao sao tocados; a validacao contra o catalogo de classes
(`shared/content_schemas/classes.json`) e da aplicacao. Desfazer (apos backup; NAO restaura os valores malformados normalizados no passo 1,
que nao existem em dados criados pela API):
```sql
BEGIN;
ALTER TABLE characters DROP CONSTRAINT IF EXISTS characters_class_id_format;
ALTER TABLE characters ALTER COLUMN class_id DROP DEFAULT;
DELETE FROM schema_migrations WHERE version = 4;
COMMIT;
```
Impacto: sem a migracao o codigo E6.1 continua funcionando (a coluna e o catalogo ja bastam); so deixam de valer o default e o CHECK de formato.
Reverter o CODIGO E6.1 sem reverter a migracao e seguro: personagens `mage`/`ranger` ja criados passam a falhar na validacao do codigo antigo
(`class_id` fora de `["warrior"]`) ate o deploy ser refeito; os dados nao sao perdidos.

### Modelo para novas migracoes
Toda migracao nova deve acrescentar aqui sua secao: SQL de desfazer (preferir mudancas
aditivas/expand-contract: adicionar coluna nullable -> backfill -> restringir), impacto em dados,
e se o rollback e destrutivo (exige backup).

### E5.4 (loot individual + crafting): sem migracao
Nao ha migracao 0004. Os itens coletados e os crafts reutilizam `reward_claims` (chaves `loot:...` e `craft:...`
em `idempotency_key`, ja `UNIQUE` por personagem) e as tabelas `character_inventory`/`characters` existentes.
Nada a desfazer em rollback de schema; para reverter o codigo basta o deploy anterior (chaves `craft:`/`loot:`
ja gravadas em `reward_claims` ficam inertes).
