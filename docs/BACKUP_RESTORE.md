# Backup e restore do PostgreSQL (runbook do dono)

**Status: NAO EXECUTADO.** Scripts escritos (`tools/ops/pg_backup.sh`, `tools/ops/pg_restore_test.sh`) mas nunca rodados: nesta VM nao ha PostgreSQL real nem `pg_dump`. Backup so conta depois de um **restore testado**.

## Antes
- PostgreSQL gerenciado com backup automatico (PITR) do provedor e a base; o dump logico e uma segunda camada.
- Cliente `pg_dump`/`pg_restore` na mesma major do servidor.
- Segredos (`DATABASE_URL`) so por variavel de ambiente/cofre; nunca em argumento, log ou Git.

## Backup (diario e antes de cada migracao)
```
export DATABASE_URL=...      # cofre
tools/ops/pg_backup.sh /caminho/seguro/backups
```
Gera `eldervale-<UTC>.dump` (formato custom) + `.sha256` e valida a leitura com `pg_restore --list`. Guarde copias fora do mesmo provedor/conta; criptografe em repouso. Retencao: **[decisao do dono, ex.: 7 diarios + 4 semanais]**.

## Restore em banco descartavel (teste mensal e apos mudar o schema)
```
export TARGET_DATABASE_URL=...scratch...   # NUNCA producao
tools/ops/pg_restore_test.sh /caminho/seguro/backups/eldervale-<UTC>.dump
```
Confira contagens e suba o backend contra o banco restaurado (`/v1/ready` deve dar 200, login deve funcionar). Registre data, tamanho, duracao e resultado aqui.

## Restore de incidente
1. Pare o servidor Godot e o backend (evita escrita durante o restore). 2. Restaure em banco novo e valide. 3. Troque `DATABASE_URL`. 4. Rode `npm run migrate` se o dump for de schema anterior. 5. Suba backend, depois servidor Godot. Dados posteriores ao backup sao perdidos; avise os jogadores.

## Migracoes
Antes de `npm run migrate`: backup. Rollback das migracoes 0005 e 0006 esta no README de `backend/migrations` (SQL testado em copia sintetica: `backend/test/migrate_copy.test.ts`, 7 testes). Migracoes 0001-0004 nao tem rollback documentado: restaure do backup.

## Registro de testes de restore
| Data | Dump | Resultado | Duracao | Quem |
|---|---|---|---|---|
| (nenhum) | | | | |
