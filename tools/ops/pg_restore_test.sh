#!/usr/bin/env bash
# Teste de restore: restaura um .dump em um banco DESCARTAVEL e confere contagens basicas.
# NUNCA aponte TARGET_DATABASE_URL para producao. Segredos so por ambiente:
#   TARGET_DATABASE_URL=postgres://...scratch ./pg_restore_test.sh backups/eldervale-XXXX.dump
set -euo pipefail
: "${TARGET_DATABASE_URL:?defina TARGET_DATABASE_URL (banco descartavel) no ambiente}"
dump="${1:?informe o arquivo .dump}"
[ -f "$dump" ] || { echo "arquivo nao encontrado: $dump" >&2; exit 2; }
if [ -f "$dump.sha256" ]; then ( cd "$(dirname "$dump")" && sha256sum -c "$(basename "$dump").sha256" ); fi
pg_restore --clean --if-exists --no-owner --no-privileges --dbname="$TARGET_DATABASE_URL" "$dump"
for t in accounts characters character_locks reward_claims schema_migrations; do
  n="$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from $t" 2>/dev/null || echo 'tabela ausente')"
  echo "$t: $n"
done
echo "Restore concluido. Compare as contagens com o banco de origem e suba o backend apontando para este banco para um teste de login."
