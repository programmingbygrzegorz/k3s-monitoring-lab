#!/usr/bin/env bash
# 05-deploy-demo.sh – aplikacja demo i własne alerty (Etap 3, wariant skryptem).
#
# Gdzie:   na k3s-master, po 04-install-monitoring.sh (potrzebne CRD ServiceMonitor i PrometheusRule)
# Użycie:  sudo ./scripts/05-deploy-demo.sh
# Wymaga:  lab.env z MASTER_IP (tylko do wypisania adresu)
#
# Co robi, po kolei:
#   1. kubectl apply -f kubernetes/demo-app/ – namespace demo i aplikacja podinfo
#      (Deployment, Service NodePort 30898, Ingress), potem czeka do 3 min, aż wdrożenie
#      się zakończy (rollout status).
#   2. kubectl apply -f kubernetes/monitoring/ – ServiceMonitor (Prometheus zaczyna zbierać
#      metryki podinfo) i PrometheusRule (własne reguły alertów labu).
#   3. Pokazuje pody podinfo i adresy: http://MASTER_IP:30898 oraz http://podinfo.lab.local
#      (Ingress – wymaga wpisu w pliku hosts na Twoim komputerze).
#
# kubectl apply jest deklaratywne – ponowne uruchomienie tylko wyrównuje stan do plików.
# Instalacja ręczna: docs/etap-3-monitoring/01-instalacja-monitoringu.md
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
