#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "==> Health via ALB (nginx)"
curl -sf "${BASE_URL}/health" | jq .

echo "==> Status do cluster (via API)"
curl -sf "${BASE_URL}/api/status" | jq .

echo "==> Criando reserva de teste"
curl -sf -X POST "${BASE_URL}/api/reservas" \
  -H "Content-Type: application/json" \
  -d '{"cliente":"Movida Demo","veiculo":"Grupo B","dias":5}' | jq .

echo "==> Listando reservas"
curl -sf "${BASE_URL}/api/reservas" | jq .

echo ""
echo "Smoke test OK. Verifique no Datadog:"
echo "  - APM: service movida-reservas-api"
echo "  - Metrics: postgres.* nos hosts pg-primary e pg-replica"
echo "  - Logs: containers api-1, api-2, pg-primary, pg-replica"
