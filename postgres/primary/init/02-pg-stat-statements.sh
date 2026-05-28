#!/bin/bash
# Obrigatorio para DBM: normaliza queries e habilita metricas de statements
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname movida <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL

echo "pg_stat_statements habilitado no banco movida."
