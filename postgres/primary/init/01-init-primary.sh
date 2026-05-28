#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${REPLICATION_PASSWORD}';
    CREATE USER movida_app WITH ENCRYPTED PASSWORD '${APP_DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON DATABASE movida TO movida_app;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname movida <<-EOSQL
    GRANT ALL ON SCHEMA public TO movida_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO movida_app;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO movida_app;
EOSQL

cat >> "${PGDATA}/postgresql.conf" <<EOF
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
listen_addresses = '*'
EOF

echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "${PGDATA}/pg_hba.conf"
echo "host all all 0.0.0.0/0 scram-sha-256" >> "${PGDATA}/pg_hba.conf"
