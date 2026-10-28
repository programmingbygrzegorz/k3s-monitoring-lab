#!/usr/bin/env bash
# Scenariusze awarii do ćwiczeń z monitoringu.
# Użycie (na k3s-master): sudo ./scripts/chaos.sh <scenariusz>
#   oom        – kontener przekracza limit pamięci (OOMKilled)
#   crashloop  – aplikacja kończy się błędem (CrashLoopBackOff)
#   imagepull  – nieistniejący obraz (ImagePullBackOff)
#   cpu        – wysokie obciążenie CPU (throttling)
#   bad-deploy – wdrożenie błędnej wersji podinfo i wycofanie (rollout undo)
#   cleanup    – usuwa wszystkie scenariusze
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root
use_k3s_kubeconfig

CHAOS_DIR="${REPO_DIR}/kubernetes/chaos"
scenario="${1:-}"

case "${scenario}" in
  oom | crashloop | imagepull | cpu)
    kubectl apply -f "${CHAOS_DIR}/namespace.yaml"
    kubectl apply -f "${CHAOS_DIR}/${scenario}.yaml"
    log "Scenariusz '${scenario}' uruchomiony. Obserwuj:"
    echo "  kubectl -n chaos get pods -w"
    echo "  kubectl -n chaos describe pod -l scenario=${scenario}"
    echo "  Grafana i Alertmanager: http://${MASTER_IP}:30300 / http://${MASTER_IP}:30093"
    ;;
  bad-deploy)
    log "Wdrażam nieistniejącą wersję obrazu podinfo"
    kubectl -n demo set image deployment/podinfo podinfo=ghcr.io/stefanprodan/podinfo:0.0.0-nie-istnieje
    sleep 20
    kubectl -n demo get pods
    kubectl -n demo rollout history deployment/podinfo
    log "Wycofuję wdrożenie (rollout undo)"
    kubectl -n demo rollout undo deployment/podinfo
    kubectl -n demo rollout status deployment/podinfo --timeout=180s
    ;;
  cleanup)
    kubectl delete namespace chaos --ignore-not-found
    log "Scenariusze usunięte"
    ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
