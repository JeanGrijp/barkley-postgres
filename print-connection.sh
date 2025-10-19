#!/usr/bin/env bash
set -euo pipefail
# carrega variáveis do .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

: "${POSTGRES_USER:?Please set POSTGRES_USER in .env}"
: "${POSTGRES_PASSWORD:?Please set POSTGRES_PASSWORD in .env}"
: "${POSTGRES_DB:?Please set POSTGRES_DB in .env}"
: "${PG_HOST:=barkley_db}"
: "${PG_PORT:=5432}"

# Connection string para apps que rodam em containers na mesma network Docker
CONN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${PG_HOST}:${PG_PORT}/${POSTGRES_DB}"
echo "${CONN}"

# Se quiser já exportar pro ambiente atual:
# export DATABASE_URL="${CONN}"
