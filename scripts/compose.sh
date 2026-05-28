#!/usr/bin/env bash
# Wrapper Docker Compose: plugin v2 -> binario local -> instalacao automatica -> container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_BIN="${PROJECT_DIR}/bin/docker-compose"
COMPOSE_VERSION="${COMPOSE_VERSION:-v2.32.4}"
COMPOSE_IMAGE="${COMPOSE_IMAGE:-docker/compose:2.32.4}"

compose_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *)
      echo "Arquitetura nao suportada: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_local_binary() {
  local arch url
  arch="$(compose_arch)"
  url="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${arch}"
  echo "==> Baixando Docker Compose ${COMPOSE_VERSION} para ${LOCAL_BIN} ..."
  mkdir -p "${PROJECT_DIR}/bin"
  curl -fsSL "${url}" -o "${LOCAL_BIN}"
  chmod +x "${LOCAL_BIN}"
  echo "==> Instalado: $("${LOCAL_BIN}" version)"
}

install_system_plugin() {
  if ! command -v sudo &>/dev/null; then
    return 1
  fi
  local arch plugin_path
  arch="$(compose_arch)"
  plugin_path="/usr/local/lib/docker/cli-plugins/docker-compose"
  echo "==> Tentando instalar plugin em ${plugin_path} (sudo) ..."
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -fsSL \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${arch}" \
    -o "${plugin_path}"
  sudo chmod +x "${plugin_path}"
  docker compose version
}

run_via_compose_container() {
  if ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; then
    return 1
  fi
  echo "==> Executando via container ${COMPOSE_IMAGE} ..."
  local -a env_file_arg=()
  [[ -f "${PROJECT_DIR}/.env" ]] && env_file_arg=(--env-file "${PROJECT_DIR}/.env")
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${PROJECT_DIR}:${PROJECT_DIR}" \
    -w "${PROJECT_DIR}" \
    "${env_file_arg[@]}" \
    "${COMPOSE_IMAGE}" \
    "$@"
}

# 1) Plugin oficial: docker compose
if docker compose version &>/dev/null 2>&1; then
  exec docker compose "$@"
fi

# 2) Binario standalone no PATH
if command -v docker-compose &>/dev/null && docker-compose version &>/dev/null 2>&1; then
  exec docker-compose "$@"
fi

# 3) Binario baixado neste projeto (git pull anterior ou nova instalacao)
if [[ -x "${LOCAL_BIN}" ]] && "${LOCAL_BIN}" version &>/dev/null 2>&1; then
  exec "${LOCAL_BIN}" "$@"
fi

# 4) Instalacao automatica
if command -v curl &>/dev/null; then
  install_local_binary || true
  if [[ -x "${LOCAL_BIN}" ]] && "${LOCAL_BIN}" version &>/dev/null 2>&1; then
    exec "${LOCAL_BIN}" "$@"
  fi
  install_system_plugin 2>/dev/null && exec docker compose "$@"
fi

# 5) Fallback: imagem docker/compose (so precisa do Docker Engine)
if run_via_compose_container "$@"; then
  exit $?
fi

echo "ERRO: Docker Compose nao encontrado e instalacao automatica falhou." >&2
echo "" >&2
echo "Corrija manualmente na EC2:" >&2
echo "  sudo dnf install -y docker-compose-plugin && sudo systemctl start docker" >&2
echo "  # ou" >&2
echo "  ./scripts/install-docker-compose.sh" >&2
exit 1
