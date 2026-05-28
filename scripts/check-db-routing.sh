#!/usr/bin/env bash
# Mostra para qual no o HAProxy envia as conexoes (write 5432 vs read 5433)
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"

echo "==> API via ALB (porta write 5432 no HAProxy — so primary)"
for _ in 1 2 3; do
  curl -sf "${BASE}/api/status" | python3 -m json.tool 2>/dev/null || curl -sf "${BASE}/api/status"
  echo ""
done

echo "==> Teste direto porta READ do HAProxy (5433 — pode ir ao replica)"
if docker exec api-1 sh -c 'PGHOST=haproxy-db PGPORT=5433 psql -U movida_app -d movida -c "SELECT inet_server_addr()::text AS host, pg_is_in_recovery() AS replica;"' 2>/dev/null; then
  true
else
  echo "(requer psql no container api-1 — opcional)"
fi
