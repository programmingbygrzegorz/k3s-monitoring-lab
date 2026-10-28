#!/usr/bin/env bash
# Dołączenie węzła roboczego do klastra.
# Użycie (na k3s-worker-1): sudo ./scripts/02-install-worker.sh <IP_TEGO_WĘZŁA>
#   np. sudo ./scripts/02-install-worker.sh 192.168.1.52
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root

NODE_IP="${1:?Podaj adres IP tego węzła}"

log "Dołączam węzeł ${NODE_IP} do klastra ${MASTER_IP:?}"
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_CHANNEL="${K3S_CHANNEL:-stable}" \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN:?Uzupełnij K3S_TOKEN w lab.env (token wyświetlił skrypt 01-install-master.sh)}" \
  sh -s - agent \
  --node-ip "${NODE_IP}" \
  --flannel-iface "${IFACE:?}"

log "Gotowe. Sprawdź na masterze: kubectl get nodes -o wide"
