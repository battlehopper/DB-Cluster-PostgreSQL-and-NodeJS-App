#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"

echo "==> Versao dd-trace na API:"
docker exec api-1 node -e "console.log(require('dd-trace/package.json').version)" 2>/dev/null || true

echo "==> Gerando trafego APM + DBM (40 requests)..."
for _ in $(seq 1 40); do
  curl -sf "${BASE}/api/reservas" >/dev/null 2>&1 || true
  curl -sf -X POST "${BASE}/api/reservas" \
    -H "Content-Type: application/json" \
    -d '{"cliente":"DBM Link Test","veiculo":"SUV","dias":2}' >/dev/null 2>&1 || true
  curl -sf "${BASE}/api/metrics/load" >/dev/null 2>&1 || true
done

echo "==> Queries recentes do usuario movida_app (pg_stat_statements):"
docker exec pg-primary psql -U postgres -d movida -c \
  "SELECT LEFT(query, 140) AS q
   FROM pg_stat_statements s
   JOIN pg_roles r ON r.oid = s.userid
   WHERE r.rolname = 'movida_app'
   ORDER BY s.calls DESC
   LIMIT 5;"

echo ""
echo "==> Busca comentario DBM (pode retornar 0 — Postgres normaliza comentarios):"
docker exec pg-primary psql -U postgres -d movida -c \
  "SELECT COUNT(*) AS com_dddbs
   FROM pg_stat_statements
   WHERE query LIKE '%dddbs%' OR query LIKE '%ddps%';"

echo ""
echo "==> Atividade em tempo real (pg_stat_activity) durante 1 request:"
(curl -sf "${BASE}/api/metrics/load" >/dev/null &)
sleep 0.3
docker exec pg-primary psql -U postgres -d movida -c \
  "SELECT LEFT(query, 160) AS live_query, usename
   FROM pg_stat_activity
   WHERE datname = 'movida' AND state = 'active' AND query NOT LIKE '%pg_stat_activity%';" \
  || true

echo ""
echo "--- Interpretacao ---"
echo "1) Calling Services: verifique APENAS em movida-pg-primary (nao na replica)."
echo "2) Host da API deve ser pg-primary (mesmo hostname do DBM reported_hostname)."
echo "3) Aguarde 5-10 min apos rebuild: ./scripts/compose.sh up -d --build api-1 api-2"
echo "4) Schema: Agent 7.54+ com collect_schemas — aguarde ~15 min apos restart do agent."
