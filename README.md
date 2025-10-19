# Barkley Postgres – Guia de Execução com Docker

Este guia explica como subir um banco de dados PostgreSQL para desenvolvimento local e estudos, usando sua estrutura de **migrations** e mantendo o acesso somente via rede Docker (sem expor a porta no host). O banco padrão será `barkley_db` e a imagem usada é a mais recente (`postgres:latest`).

## Pré-requisitos

* Docker e Docker Compose instalados
* Acesso ao terminal
* Suas migrations organizadas nesta estrutura:

  ```
  barkley-postgres/
  ├─ .env.example
  ├─ docker-compose.yml
  ├─ up.sh
  ├─ print-connection.sh
  └─ migrations/
     ├─ 000_schema.sql
     ├─ 001_ticket_event_type_extend.sql
     ├─ 002_worker_contact_tenant_slug.sql
     └─ 003_lane_partition.sql
  ```

> Dica: renomeie seu `schema.sql` para `migrations/000_schema.sql` para garantir a execução antes das demais migrations. Os arquivos em `docker-entrypoint-initdb.d` rodam em ordem alfabética somente na primeira inicialização do volume.

## Variáveis de ambiente

Crie um arquivo `.env` com base no `.env.example` para manter suas credenciais fora do repositório.

`.env.example`

```env
POSTGRES_IMAGE=postgres:latest
POSTGRES_USER=postgres
# Crie sua senha em .env (não comite)
# POSTGRES_PASSWORD=troque_com_uma_senha_forte
POSTGRES_DB=barkley_db
PG_HOST=barkley_db
PG_PORT=5432
```

Exemplo de `.env` local (não comitar):

```env
POSTGRES_IMAGE=postgres:latest
POSTGRES_USER=postgres
POSTGRES_PASSWORD=minha_senha_forte
POSTGRES_DB=barkley_db
PG_HOST=barkley_db
PG_PORT=5432
```

## Arquivos do serviço

`docker-compose.yml`

```yaml
version: "3.8"

services:
  barkley_db:
    image: "${POSTGRES_IMAGE:-postgres:latest}"
    container_name: bk_postgres
    env_file: .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB:-barkley_db}
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d:ro
    networks:
      - barkley_network
    restart: unless-stopped

volumes:
  pg_data:

networks:
  barkley_network:
    external: true
```

`up.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME="barkley_network"
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "Criando docker network ${NETWORK_NAME}..."
  docker network create "${NETWORK_NAME}"
else
  echo "Docker network ${NETWORK_NAME} já existe."
fi

if [ ! -f .env ]; then
  echo "⚠️  Arquivo .env não encontrado. Crie um .env baseado em .env.example com POSTGRES_PASSWORD."
  exit 1
fi

docker-compose up -d --remove-orphans

echo "Postgres subiu (container bk_postgres). Use ./print-connection.sh para ver a connection string."
```

`print-connection.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

: "${POSTGRES_USER:?Please set POSTGRES_USER in .env}"
: "${POSTGRES_PASSWORD:?Please set POSTGRES_PASSWORD in .env}"
: "${POSTGRES_DB:?Please set POSTGRES_DB in .env}"
: "${PG_HOST:=barkley_db}"
: "${PG_PORT:=5432}"

CONN="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${PG_HOST}:${PG_PORT}/${POSTGRES_DB}"
echo "${CONN}"
```

Dê permissão de execução nos scripts:

```bash
chmod +x up.sh print-connection.sh watch-queries.sh
```

## Subindo o banco

1. Garanta que `migrations/` contém `000_schema.sql` e demais migrations na ordem desejada.
2. Crie o `.env` com sua senha.
3. No diretório `barkley-postgres/` execute:

```bash
./up.sh
```

Isso criará a rede externa `barkley_network` (se ainda não existir), subirá o container `bk_postgres` e executará as migrations automaticamente na primeira inicialização do volume `pg_data`.

Para ver logs:

```bash
docker-compose logs -f barkley_db
```

## Obtendo a connection string

Para imprimir a URL de conexão que outras aplicações (em containers na mesma rede) devem usar:

```bash
./print-connection.sh
```

Exemplo de saída:

```
postgres://postgres:minha_senha_forte@barkley_db:5432/barkley_db
```

Você pode exportar para o ambiente da sua aplicação:

```bash
export DATABASE_URL=$(./print-connection.sh)
```

## Monitorando conexões e queries

Para acompanhar em tempo real as conexões e consultas ativas (via `pg_stat_activity`):

```bash
./watch-queries.sh
```

Ou com o Makefile:

```bash
make queries
```

O script limpa a tela e atualiza a cada 3 segundos; encerre com `Ctrl+C`.

## Conectando outras aplicações via Docker

Nos `docker-compose.yml` das suas aplicações, use a mesma rede externa `barkley_network` e o host `barkley_db` (nome do serviço no compose do DB):

```yaml
networks:
  default:
    external:
      name: barkley_network

services:
  app:
    image: sua-imagem
    environment:
      - DATABASE_URL=postgres://postgres:senha@barkley_db:5432/barkley_db
    networks:
      - default
```

Se você usa múltiplas aplicações, todas podem se conectar ao Postgres usando `barkley_db:5432` enquanto estiverem na rede `barkley_network`. Como a porta não é exposta no host, o acesso fica restrito à rede Docker.

## Como aplicar mudanças de schema

As migrations em `migrations/` são executadas automaticamente apenas na primeira inicialização do volume. Para aplicar novas migrations depois, você tem duas opções simples para ambiente de estudos:

* Remover o volume para “recriar do zero”:

  ```bash
  docker-compose down -v
  ./up.sh
  ```

  Isso apaga os dados e recria o banco do zero aplicando todas as migrations novamente.

* Aplicar manualmente via `psql` dentro do container (útil para testar scripts incrementais):

  ```bash
  docker exec -it bk_postgres bash
  psql -U $POSTGRES_USER -d $POSTGRES_DB -c '\dt'
  psql -U $POSTGRES_USER -d $POSTGRES_DB -f /docker-entrypoint-initdb.d/003_lane_partition.sql
  ```

Para estudos, a primeira abordagem costuma ser suficiente.

## Limpeza e reset

Parar containers:

```bash
docker-compose down
```

Parar e apagar os dados (reset total):

```bash
docker-compose down -v
```

Se quiser remover a rede externa:

```bash
docker network rm barkley_network
```

## Dicas e observações

* O `POSTGRES_PASSWORD` deve estar somente no `.env` local, não comite credenciais.
* Como os IDs são gerados na aplicação (Snowflake/ULID), o schema usa `BIGINT` sem sequence por padrão.
* Se quiser se conectar do seu host com uma IDE local, você precisará expor a porta no `docker-compose.yml` adicionando `ports: ["5432:5432"]`. Para este setup, mantivemos sem `ports` por segurança, limitando o acesso à rede Docker.

## Fluxo rápido de uso

1. Copie os arquivos deste guia para `barkley-postgres/`.
2. Coloque suas migrations em `barkley-postgres/migrations/` garantindo a ordem (começando por `000_schema.sql`).
3. Crie `.env` com `POSTGRES_PASSWORD`.
4. Rode `./up.sh`.
5. Rode `./print-connection.sh` e use a URL nas suas aplicações que também estejam na `barkley_network`.

Pronto. Se quiser, posso adaptar este README para o seu repositório específico e incluir badges, targets de `make` e um exemplo de `docker compose` de uma app cliente usando `DATABASE_URL`. Quer que eu inclua essa sessão também?
