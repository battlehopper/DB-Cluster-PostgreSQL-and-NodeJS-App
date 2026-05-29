#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

PG_USER="${POSTGRES_USER:-postgres}"

echo "=== Diagnostico DBM + Router — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo ""

check_psql() {
  local label="$1"
  local host="$2"
  local port="${3:-5432}"
  echo "--- ${label} (${host}:${port}) ---"
  if ! docker exec pg-primary pg_isready -h "$host" -p "$port" -U "$PG_USER" -d movida &>/dev/null; then
    echo "  FALHA: nao conecta"
    return 1
  fi
  echo "  conexao: OK"
  docker exec pg-primary psql -h "$host" -p "$port" -U "$PG_USER" -d movida -tAc \
    "SHOW shared_preload_libraries;" | sed 's/^/  preload: /'
  local cnt
  cnt=$(docker exec pg-primary psql -h "$host" -p "$port" -U "$PG_USER" -d movida -tAc \
    "SELECT count(*) FROM pg_stat_statements;" 2>/dev/null || echo "ERRO")
  echo "  pg_stat_statements rows: ${cnt}"
  echo ""
}

check_psql "APP path: LB externo" "haproxy-db" 5432
check_psql "Router ESCRITA :6446 (DBM principal)" "pg-router" 6446
check_psql "Router LEITURA :6447" "pg-router" 6447
check_psql "No PRIMARY" "pg-primary" 5432
check_psql "No REPLICA" "pg-replica" 5432 || true

echo "--- Hosts DBM esperados no us5 ---"
echo "  movida-pg-haproxy     (LB)"
echo "  movida-pg-router      (router write :6446 — Queries/Schema/Calling Services)"
echo "  movida-pg-router-read (router read :6447)"
echo "  movida-pg-primary     (vacuum/replication)"
echo "  movida-pg-replica     (standby)"
echo ""
echo "Correcao: ./scripts/enable-pg-stat-statements.sh"
