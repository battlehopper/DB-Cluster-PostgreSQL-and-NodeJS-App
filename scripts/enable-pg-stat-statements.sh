#!/usr/bin/env bash
# Corrige DBM "pg_stat_statements is not created" em volumes ja existentes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# shellcheck source=lib/postgres.sh
source "${SCRIPT_DIR}/lib/postgres.sh"
load_pg_env "${PROJECT_DIR}"

echo "==> 1/8 Recriando Postgres com shared_preload_libraries (requer git pull recente)..."
./scripts/compose.sh up -d --build --force-recreate pg-primary pg-replica

echo "==> 2/8 Aguardando primary..."
for _ in $(seq 1 30); do
  if pg_ready pg-primary -d movida &>/dev/null; then
    break
  fi
  sleep 2
done

echo "==> 3/8 Verificando biblioteca carregada..."
pg_exec pg-primary -d movida -c "SHOW shared_preload_libraries;"

echo "==> 4/8 Criando extensao no primary (replica herda via catalogo)..."
pg_exec pg-primary -d movida -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

echo "==> 5/8 Validando via ROUTER :6446 (DBM movida-pg-router)..."
if ! pg_exec pg-primary -h pg-router -p 6446 -d movida -c \
  "SELECT count(*) AS via_router_write FROM pg_stat_statements;"; then
  echo "ERRO: pg_stat_statements indisponivel via pg-router:6446"
  echo "Verifique POSTGRES_PASSWORD no .env (atual: definida=$( [[ -n \"${PG_PASSWORD}\" ]] && echo sim || echo nao ))"
  exit 1
fi

echo "==> 5b/8 Validando via LB externo (caminho completo da APP)..."
pg_exec pg-primary -h haproxy-db -p 5432 -d movida -c \
  "SELECT count(*) AS via_lb FROM pg_stat_statements;" || true

echo "==> 6/8 Validando nos diretamente..."
pg_exec pg-primary -d movida -c "SHOW shared_preload_libraries;"
pg_exec pg-replica -d movida -c "SHOW shared_preload_libraries;"
pg_exec pg-primary -d movida -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
pg_exec pg-replica -d movida -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
echo "==> Teste pg_stat_statements na replica (pode retornar 0 linhas — sem trafego de app):"
pg_exec pg-replica -d movida -c "SELECT count(*) FROM pg_stat_statements;" \
  || echo "AVISO: replica ainda sem preload — sera necessario rebuild da imagem pg-replica"

echo "==> Gerando queries de teste..."
for _ in $(seq 1 25); do
  curl -sf "http://localhost:${APP_ALB_PORT:-8080}/api/metrics/load" >/dev/null 2>&1 || true
done

echo "==> Statements capturados no primary:"
pg_exec pg-primary -d movida -c "SELECT count(*) AS total FROM pg_stat_statements;"

echo "==> 7/8 Grants DBM (vacuum/wraparound) no primary..."
pg_exec pg-primary -d movida -c "GRANT pg_monitor TO movida_app;" 2>/dev/null || true
pg_exec pg-primary -d postgres -c "GRANT pg_monitor TO movida_app;" 2>/dev/null || true

echo "==> 8/8 Reiniciando stack DB + Agent..."
./scripts/compose.sh restart pg-router haproxy-db pg-primary datadog-agent

echo ""
echo "Concluido. Aguarde 2-5 min no DBM (us5) e atualize Setup Issues."
echo "Se shared_preload_libraries NAO listar pg_stat_statements, rode:"
echo "  ./scripts/compose.sh down -v && ./scripts/compose.sh up -d --build"
