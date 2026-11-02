#!/usr/bin/env bash
# 06-setup-monitoring-vm.sh – monitoring poza klastrem: Grafana i Uptime Kuma w Dockerze (Etap 4).
#
# Gdzie:   na maszynie monitoring
# Użycie:  sudo ./scripts/06-setup-monitoring-vm.sh
# Wymaga:  lab.env z MASTER_IP, WORKER2_IP, MONITORING_IP, GRAFANA_ADMIN_PASSWORD
#
# Co robi, po kolei:
#   1. Jeśli nie ma Dockera – instaluje go oficjalnym skryptem https://get.docker.com
#      (Docker Engine + plugin docker compose).
#   2. Tworzy monitoring/monitoring-vm/.env z adresami i hasłem Grafany (uprawnienia 600,
#      plik jest w .gitignore) – czyta go docker compose.
#   3. docker compose up -d w katalogu monitoring/monitoring-vm/ – uruchamia w tle kontenery
#      z docker-compose.yml: Grafanę (port 3000, z gotowym źródłem danych z grafana/)
#      i Uptime Kuma (port 3001).
#   4. Pokazuje stan kontenerów (docker compose ps) i adresy.
#
# Po co osobna maszyna: gdy klaster padnie, padnie też Grafana w klastrze – ta na monitoring
# dalej działa i pokaże, że klaster nie odpowiada.
# Opis: docs/etap-4-monitoring-zewnetrzny/01-monitoring-zewnetrzny.md
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
