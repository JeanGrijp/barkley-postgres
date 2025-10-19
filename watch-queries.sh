#!/usr/bin/env bash
set -euo pipefail

# carrega variáveis do .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

: "${POSTGRES_USER:?Please set POSTGRES_USER in .env}"
: "${POSTGRES_PASSWORD:?Please set POSTGRES_PASSWORD in .env}"
: "${POSTGRES_DB:?Please set POSTGRES_DB in .env}"

QUERY=$'SELECT now() AS ts,\n       pid,\n       usename,\n       state,\n       wait_event,\n       query_start,\n       left(query, 120) AS query\n  FROM pg_stat_activity\n WHERE state <> \'idle\'\n ORDER BY query_start DESC NULLS LAST;'

while true; do
  clear
  echo "[pg_stat_activity] Press Ctrl+C to stop."
  docker exec -e PGPASSWORD="${POSTGRES_PASSWORD}" -it bk_postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "${QUERY}"
  sleep 3
done
