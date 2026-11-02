#!/usr/bin/env bash
# Scenariusze awarii do ćwiczeń z monitoringu.
# Użycie (na k3s-master): sudo ./scripts/chaos.sh <scenariusz>
#   oom        – kontener przekracza limit pamięci (OOMKilled)
#   crashloop  – aplikacja kończy się błędem (CrashLoopBackOff)
#   imagepull  – nieistniejący obraz (ImagePullBackOff)
#   cpu        – wysokie obciążenie CPU (throttling)
#   bad-deploy – wdrożenie błędnej wersji podinfo i wycofanie (rollout undo)
#   cleanup    – usuwa wszystkie scenariusze
#
# Linie 2–9 wyżej skrypt wypisuje jako pomoc, gdy podasz zły scenariusz – nie zmieniaj ich układu.
#
# chaos.sh – celowe awarie w klastrze (Etap 5).
# Wymaga:  lab.env z MASTER_IP (tylko do wypisania adresów); działający monitoring z Etapu 3.
#
# Co robi:
#   oom, crashloop, imagepull, cpu:
#     1. kubectl apply kubernetes/chaos/namespace.yaml – namespace chaos (awarie oddzielone
#        od reszty klastra).
#     2. kubectl apply kubernetes/chaos/<scenariusz>.yaml – Deployment, który psuje się
#        w określony sposób (opis w komentarzu na górze każdego pliku YAML).
#     3. Wypisuje, co obserwować: kubectl -n chaos get pods -w, describe, Grafana, Alertmanager.
#   bad-deploy:
#     1. Ustawia w Deploymencie podinfo (namespace demo) nieistniejący obraz – nowe pody
#        nie startują (ImagePullBackOff), stare dalej działają (rolling update).
#     2. Po 20 s pokazuje pody i historię wdrożeń (rollout history).
#     3. Cofa wdrożenie (rollout undo) i czeka, aż podinfo znów działa.
#   cleanup:
#     Usuwa namespace chaos razem ze wszystkimi awariami.
#
# Opis scenariuszy i czego szukać: docs/etap-5-scenariusze-awarii/01-scenariusze-awarii.md
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
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
