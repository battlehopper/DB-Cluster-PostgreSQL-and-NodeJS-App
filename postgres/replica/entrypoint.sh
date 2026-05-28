#!/bin/bash
set -e

export PGPASSWORD="${REPLICATION_PASSWORD}"

until pg_isready -h pg-primary -U "${POSTGRES_USER}" -d postgres; do
  echo "Aguardando pg-primary..."
  sleep 2
done

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  echo "Inicializando replica a partir do primary..."
  rm -rf "${PGDATA}"/*
  pg_basebackup -h pg-primary -D "${PGDATA}" -U replicator -v -P -R -X stream -c fast
fi

exec docker-entrypoint.sh postgres \
  -c shared_preload_libraries=pg_stat_statements \
  -c pg_stat_statements.track=all \
  -c pg_stat_statements.max=10000
