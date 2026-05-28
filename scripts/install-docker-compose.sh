#!/usr/bin/env bash
# Instala Docker Compose v2 na EC2 (plugin + binario local de fallback)
set -euo pipefail

COMPOSE_VERSION="${COMPOSE_VERSION:-v2.32.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "unsupported"; exit 1 ;;
  esac
}

ARCH="$(arch)"
URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${ARCH}"

echo "==> Garantindo Docker em execucao..."
if command -v systemctl &>/dev/null; then
  sudo systemctl enable --now docker 2>/dev/null || true
fi

echo "==> Pacote dnf (Amazon Linux / RHEL)..."
if command -v dnf &>/dev/null; then
  sudo dnf install -y docker-compose-plugin 2>/dev/null || true
fi

if docker compose version &>/dev/null 2>&1; then
  echo "OK: $(docker compose version)"
  exit 0
fi

echo "==> Plugin em /usr/local/lib/docker/cli-plugins ..."
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fsSL "${URL}" -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

if docker compose version &>/dev/null 2>&1; then
  echo "OK: $(docker compose version)"
  exit 0
fi

echo "==> Binario local em ${PROJECT_DIR}/bin/docker-compose ..."
mkdir -p "${PROJECT_DIR}/bin"
curl -fsSL "${URL}" -o "${PROJECT_DIR}/bin/docker-compose"
chmod +x "${PROJECT_DIR}/bin/docker-compose"
"${PROJECT_DIR}/bin/docker-compose" version

echo ""
echo "Use: ./scripts/compose.sh up -d --build"
