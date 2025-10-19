#!/usr/bin/env bash
set -euo pipefail

# 1) cria a network docker (só cria se não existir)
NETWORK_NAME="barkley_network"
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "Criando docker network ${NETWORK_NAME}..."
  docker network create "${NETWORK_NAME}"
else
  echo "Docker network ${NETWORK_NAME} já existe."
fi

# 2) verifica .env
if [ ! -f .env ]; then
  echo "⚠️  Arquivo .env não encontrado. Crie um .env baseado em .env.example com POSTGRES_PASSWORD."
  exit 1
fi

# 3) sobe o postgres
docker-compose up -d --remove-orphans

echo "Postgres subiu (container bk_postgres). Use ./print-connection.sh para ver a connection string."
