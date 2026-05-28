#!/usr/bin/env bash
# Bootstrap para Amazon Linux 2023 / Ubuntu 22.04+ na EC2
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/movida-datadog-lab}"

echo "==> Instalando Docker..."
if command -v dnf &>/dev/null; then
  sudo dnf update -y
  sudo dnf install -y docker git docker-compose-plugin 2>/dev/null || sudo dnf install -y docker git
  sudo systemctl enable --now docker
  sudo usermod -aG docker "${USER}"
elif command -v apt-get &>/dev/null; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl git
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "${USER}"
else
  echo "SO nao suportado automaticamente. Instale Docker manualmente."
  exit 1
fi

echo "==> Instalando Docker Compose plugin..."
if ! docker compose version &>/dev/null; then
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  COMPOSE_VERSION="v2.32.4"
  sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

echo "==> Clonando projeto..."
sudo mkdir -p "$(dirname "${INSTALL_DIR}")"
if [ ! -d "${INSTALL_DIR}/.git" ]; then
  sudo git clone "${REPO_URL}" "${INSTALL_DIR}"
else
  cd "${INSTALL_DIR}" && sudo git pull
fi
sudo chown -R "${USER}:${USER}" "${INSTALL_DIR}"

cd "${INSTALL_DIR}"
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "ATENCAO: Edite ${INSTALL_DIR}/.env e defina DD_API_KEY antes de subir o stack."
fi

echo ""
echo "Bootstrap concluido."
echo "Proximos passos:"
echo "  1) newgrp docker   # ou faca logout/login"
echo "  2) nano ${INSTALL_DIR}/.env"
echo "  3) cd ${INSTALL_DIR} && ./scripts/compose.sh up -d --build"
echo "  4) ./scripts/smoke-test.sh"
