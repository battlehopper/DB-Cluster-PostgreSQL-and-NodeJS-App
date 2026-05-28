#!/usr/bin/env bash
# Valida propagacao DBM no SQL (Calling Services) e orienta refresh no UI
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"

echo "==> Gerando trafego APM + DBM (30 requests)..."
for _ in $(seq 1 30); do
  curl -sf "${BASE}/api/reservas" >/dev/null 2>&1 || true
  curl -sf -X POST "${BASE}/api/reservas" \
    -H "Content-Type: application/json" \
    -d '{"cliente":"DBM Link Test","veiculo":"SUV","dias":2}' >/dev/null 2>&1 || true
  curl -sf "${BASE}/api/metrics/load" >/dev/null 2>&1 || true
done

echo "==> Queries com comentario DBM (dddbs/ddps) no primary:"
docker exec pg-primary psql -U postgres -d movida -c \
  "SELECT LEFT(query, 120) AS query_preview FROM pg_stat_statements WHERE query LIKE '%dddbs%' OR query LIKE '%ddps%' LIMIT 5;"

echo ""
echo "Se retornar linhas acima, Calling Services deve aparecer em 5-10 min no primary."
echo "Verifique: DBM -> movida-pg-primary -> Calling Services (nao na replica)."
echo "Schema: aguarde coleta apos collect_schemas (Agent 7.54+)."
