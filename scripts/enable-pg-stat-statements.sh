#!/usr/bin/env bash
# Corrige DBM "pg_stat_statements is not created" em volumes ja existentes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

echo "==> 1/6 Recriando Postgres com shared_preload_libraries (requer git pull recente)..."
./scripts/compose.sh up -d --force-recreate pg-primary pg-replica

echo "==> 2/6 Aguardando primary..."
for _ in $(seq 1 30); do
  if docker exec pg-primary pg_isready -U postgres -d movida &>/dev/null; then
    break
  fi
  sleep 2
done

echo "==> 3/6 Verificando biblioteca carregada..."
docker exec pg-primary psql -U postgres -d movida -c "SHOW shared_preload_libraries;"

echo "==> 4/6 Criando extensao no primary (replica herda via catalogo)..."
docker exec pg-primary psql -U postgres -d movida -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

echo "==> 5/6 Validando extensao nos dois nos..."
docker exec pg-primary psql -U postgres -d movida -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
docker exec pg-replica psql -U postgres -d movida -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"

echo "==> Gerando queries de teste..."
for _ in $(seq 1 25); do
  curl -sf "http://localhost:${APP_ALB_PORT:-8080}/api/metrics/load" >/dev/null 2>&1 || true
done

echo "==> Statements capturados no primary:"
docker exec pg-primary psql -U postgres -d movida -c "SELECT count(*) AS total FROM pg_stat_statements;"

echo "==> 6/6 Reiniciando Datadog Agent..."
./scripts/compose.sh restart datadog-agent

echo ""
echo "Concluido. Aguarde 2-5 min no DBM (us5) e atualize Setup Issues."
echo "Se shared_preload_libraries NAO listar pg_stat_statements, rode:"
echo "  ./scripts/compose.sh down -v && ./scripts/compose.sh up -d --build"
