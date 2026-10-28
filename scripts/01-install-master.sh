#!/usr/bin/env bash
# Instalacja węzła sterującego k3s (control plane).
# Użycie (na k3s-master): sudo ./scripts/01-install-master.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root

log "Instaluję k3s (server) na ${MASTER_IP:?}"
# --node-taint: na węźle sterującym nie uruchamiamy zwykłych aplikacji (dobra praktyka),
#               dzięki czemu zasoby mastera zostają dla samego klastra.
# --write-kubeconfig-mode 0644: wygoda w laboratorium; na produkcji zostaw domyślne 0600.
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="${K3S_CHANNEL:-stable}" sh -s - server \
  --node-ip "${MASTER_IP}" \
  --advertise-address "${MASTER_IP}" \
  --flannel-iface "${IFACE:?}" \
  --write-kubeconfig-mode 0644 \
  --node-taint "node-role.kubernetes.io/control-plane=true:NoSchedule"

use_k3s_kubeconfig

log "Czekam, aż węzeł sterujący będzie gotowy"
until kubectl get node k3s-master 2>/dev/null | grep -q ' Ready'; do
  sleep 5
done
kubectl get nodes -o wide

log "Token do dołączenia workerów (wpisz go jako K3S_TOKEN w lab.env na workerach):"
cat /var/lib/rancher/k3s/server/node-token
