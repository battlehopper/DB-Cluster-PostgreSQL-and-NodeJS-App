#!/usr/bin/env bash
# Corrige hosts DBM ja provisionados (volume existente) sem apagar dados
set -euo pipefail

echo "==> Habilitando pg_stat_statements no pg-primary..."
docker exec pg-primary psql -U postgres -d movida -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

echo "==> Reiniciando PostgreSQL para carregar shared_preload_libraries..."
./scripts/compose.sh restart pg-primary pg-replica

echo "Aguardando primary..."
sleep 8
docker exec pg-primary pg_isready -U postgres -d movida

echo "==> Reiniciando Datadog Agent para re-coletar DBM..."
./scripts/compose.sh restart datadog-agent

echo ""
echo "OK. Em 2-5 min verifique no DBM (us5) se o issue 'pg-stat-statements-not-created' sumiu."
echo "Se persistir apos restart, recrie o volume (perde dados de demo):"
echo "  ./scripts/compose.sh down -v && ./scripts/compose.sh up -d --build"
