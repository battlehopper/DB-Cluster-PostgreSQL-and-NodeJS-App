#!/usr/bin/env bash
# Gera trafego continuo contra a API (via ALB) -> cluster PostgreSQL (via LB)
# Uso: ./scripts/continuous-traffic.sh
#      INTERVAL_SECONDS=60 BASE_URL=http://localhost:8080 ./scripts/continuous-traffic.sh

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
CLIENTES=("Movida Demo" "Cliente Corp" "Locadora Teste" "Fleet A" "Fleet B")
VEICULOS=("Grupo A" "Grupo B" "SUV" "Pickup" "Sedan")

cycle=0
ok=0
fail=0

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

rand_item() {
  local -n arr=$1
  echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

run_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ "$method" == "GET" ]]; then
    if curl -sf --connect-timeout 5 --max-time 30 "${BASE_URL}${path}" >/dev/null; then
      ok=$((ok + 1))
      return 0
    fi
  else
    if curl -sf --connect-timeout 5 --max-time 30 -X POST "${BASE_URL}${path}" \
      -H "Content-Type: application/json" \
      -d "$body" >/dev/null; then
      ok=$((ok + 1))
      return 0
    fi
  fi
  fail=$((fail + 1))
  return 1
}

run_cycle() {
  cycle=$((cycle + 1))
  local cliente veiculo dias payload

  cliente="$(rand_item CLIENTES)"
  veiculo="$(rand_item VEICULOS)"
  dias=$(( (RANDOM % 14) + 1 ))
  payload=$(printf '{"cliente":"%s","veiculo":"%s","dias":%d}' "$cliente" "$veiculo" "$dias")

  log "Ciclo #${cycle} — gerando requests (ALB -> API -> haproxy-db -> PostgreSQL)..."

  run_request GET "/health" || log "  WARN: /health falhou"
  run_request GET "/api/status" || log "  WARN: /api/status falhou"
  run_request GET "/api/reservas" || log "  WARN: /api/reservas falhou"
  run_request POST "/api/reservas" "$payload" || log "  WARN: POST /api/reservas falhou"
  run_request GET "/api/metrics/load" || log "  WARN: /api/metrics/load falhou"

  log "Ciclo #${cycle} concluido | ok=${ok} fail=${fail} | proximo em ${INTERVAL_SECONDS}s"
}

shutdown() {
  log "Encerrando (SIGTERM/SIGINT). Total: ciclos=${cycle} ok=${ok} fail=${fail}"
  exit 0
}

trap shutdown SIGTERM SIGINT

log "Iniciando trafego continuo"
log "  BASE_URL=${BASE_URL}"
log "  INTERVAL_SECONDS=${INTERVAL_SECONDS}"
log "  Ctrl+C para parar"

while true; do
  run_cycle
  sleep "${INTERVAL_SECONDS}"
done
