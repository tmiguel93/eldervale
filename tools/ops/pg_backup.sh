#!/usr/bin/env bash
# Backup logico do PostgreSQL do Eldervale (para o DONO executar; NAO foi executado em producao).
# Requer pg_dump/pg_restore compativeis com a versao do servidor. Segredos so por ambiente:
#   DATABASE_URL=postgres://... ./pg_backup.sh [diretorio_saida]
set -euo pipefail
: "${DATABASE_URL:?defina DATABASE_URL no ambiente (nao passe por argumento)}"
out="${1:-./backups}"
mkdir -p "$out"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
file="$out/eldervale-$ts.dump"
pg_dump --format=custom --no-owner --no-privileges --file="$file" "$DATABASE_URL"
pg_restore --list "$file" >/dev/null   # valida que o arquivo e legivel
( cd "$out" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256" )
echo "OK: $file ($(wc -c <"$file") bytes)"
