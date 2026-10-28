#!/usr/bin/env bash
# Wdrożenie aplikacji demo (podinfo) oraz reguł monitoringu laboratorium.
# Użycie (na k3s-master): sudo ./scripts/05-deploy-demo.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root
use_k3s_kubeconfig

log "Wdrażam aplikację demo"
kubectl apply -f "${REPO_DIR}/kubernetes/demo-app/"
kubectl -n demo rollout status deployment/podinfo --timeout=180s

log "Wdrażam ServiceMonitor i reguły alertów"
kubectl apply -f "${REPO_DIR}/kubernetes/monitoring/"

kubectl -n demo get pods -o wide
echo
echo "Aplikacja przez NodePort: http://${MASTER_IP}:30898"
echo "Aplikacja przez Ingress:  http://podinfo.lab.local (dodaj wpis do pliku hosts, wskazujący na IP workera)"
