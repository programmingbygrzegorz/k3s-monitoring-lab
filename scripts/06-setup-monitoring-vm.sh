#!/usr/bin/env bash
# Zewnętrzny monitoring poza klastrem: Grafana + Uptime Kuma w Dockerze.
# Użycie (na maszynie monitoring): sudo ./scripts/06-setup-monitoring-vm.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root

if ! command -v docker > /dev/null; then
  log "Instaluję Dockera"
  curl -fsSL https://get.docker.com | sh
fi

VM_DIR="${REPO_DIR}/monitoring/monitoring-vm"

log "Tworzę plik .env dla Docker Compose"
cat > "${VM_DIR}/.env" << ENVFILE
MASTER_IP=${MASTER_IP:?}
WORKER2_IP=${WORKER2_IP:?}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:?}
ENVFILE
chmod 600 "${VM_DIR}/.env"

log "Uruchamiam Grafanę i Uptime Kuma"
docker compose --project-directory "${VM_DIR}" up -d
docker compose --project-directory "${VM_DIR}" ps

log "Gotowe. Dostęp:"
echo "  Grafana:     http://${MONITORING_IP:?}:3000  (login: admin)"
echo "  Uptime Kuma: http://${MONITORING_IP}:3001  (konto tworzysz przy pierwszym wejściu)"
