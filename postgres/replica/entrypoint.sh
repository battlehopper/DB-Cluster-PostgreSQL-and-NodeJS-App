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

# pg_stat_statements precisa estar no postgresql.conf da replica (nao basta herdar do primary)
if [ -f "${PGDATA}/postgresql.conf" ] && ! grep -q 'pg_stat_statements' "${PGDATA}/postgresql.conf"; then
  cat >> "${PGDATA}/postgresql.conf" <<'EOF'
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000
EOF
  echo "postgresql.conf da replica atualizado com pg_stat_statements."
fi

exec docker-entrypoint.sh postgres \
  -c shared_preload_libraries=pg_stat_statements \
  -c pg_stat_statements.track=all \
  -c pg_stat_statements.max=10000
