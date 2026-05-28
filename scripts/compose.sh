#!/usr/bin/env bash
# Wrapper: usa "docker compose" (plugin v2) ou "docker-compose" (standalone v1)
set -euo pipefail

if docker compose version &>/dev/null 2>&1; then
  exec docker compose "$@"
fi

if command -v docker-compose &>/dev/null && docker-compose version &>/dev/null 2>&1; then
  exec docker-compose "$@"
fi

echo "ERRO: Docker Compose nao encontrado."
echo ""
echo "Instale o plugin v2 (recomendado):"
echo "  sudo mkdir -p /usr/local/lib/docker/cli-plugins"
echo "  sudo curl -SL \"https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-\$(uname -m)\" \\"
echo "    -o /usr/local/lib/docker/cli-plugins/docker-compose"
echo "  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
echo "  docker compose version"
echo ""
echo "Ou use: sudo dnf install -y docker-compose-plugin   # Amazon Linux 2023"
exit 1
