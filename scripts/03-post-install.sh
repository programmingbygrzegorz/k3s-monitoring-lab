#!/usr/bin/env bash
# Etykiety ról dla workerów i sprawdzenie stanu klastra.
# Użycie (na k3s-master): sudo ./scripts/03-post-install.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root
use_k3s_kubeconfig

WORKERS=(k3s-worker-1 k3s-worker-2)
[[ -n "${WORKER3_IP:-}" ]] && WORKERS+=(k3s-worker-3)
EXPECTED=$(( ${#WORKERS[@]} + 1 ))

log "Czekam na wszystkie ${EXPECTED} węzły w stanie Ready"
until [[ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -eq "${EXPECTED}" ]]; do
  kubectl get nodes --no-headers 2>/dev/null || true
  sleep 10
done

log "Nadaję workerom rolę 'worker'"
for node in "${WORKERS[@]}"; do
  kubectl label node "${node}" node-role.kubernetes.io/worker=worker --overwrite
done

kubectl get nodes -o wide
kubectl get pods -A
