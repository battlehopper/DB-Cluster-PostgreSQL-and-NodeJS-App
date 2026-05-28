#!/bin/bash
# Permissoes extras para metricas de vacuum/wraparound no DBM
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname movida <<-EOSQL
    GRANT pg_monitor TO movida_app;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    GRANT pg_monitor TO movida_app;
EOSQL

echo "Grants pg_monitor aplicados para DBM (vacuum/wraparound)."
