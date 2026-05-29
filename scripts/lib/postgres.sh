#!/usr/bin/env bash
# Helpers psql nos scripts (conexoes TCP exigem PGPASSWORD via pg_hba scram-sha-256)

load_pg_env() {
  local project_dir="${1:-.}"
  if [[ -f "${project_dir}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${project_dir}/.env"
    set +a
  fi
  export PG_USER="${POSTGRES_USER:-postgres}"
  export PG_PASSWORD="${POSTGRES_PASSWORD:-postgres_admin}"
}

# Uso: pg_exec pg-primary -h pg-router -p 6446 -d movida -c "SELECT 1"
pg_exec() {
  local container="$1"
  shift
  docker exec -e PGPASSWORD="${PG_PASSWORD}" "${container}" \
    psql -U "${PG_USER}" "$@"
}

pg_ready() {
  local container="$1"
  shift
  docker exec -e PGPASSWORD="${PG_PASSWORD}" "${container}" \
    pg_isready -U "${PG_USER}" "$@"
}
