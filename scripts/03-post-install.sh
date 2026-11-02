#!/usr/bin/env bash
# 03-post-install.sh – kontrola klastra po instalacji (Etap 2, wariant bez Ansible).
#
# Gdzie:   na k3s-master, gdy wszystkie workery przeszły 02-install-worker.sh
# Użycie:  sudo ./scripts/03-post-install.sh
# Wymaga:  lab.env (WORKER3_IP – jeśli jest, skrypt czeka też na k3s-worker-3)
#
# Co robi, po kolei:
#   1. Liczy, ile węzłów powinno być (master + 2 albo 3 workery) i co 10 s sprawdza
#      kubectl get nodes, aż wszystkie będą Ready.
#   2. Nadaje workerom etykietę node-role.kubernetes.io/worker=worker – w kolumnie ROLES
#      widać „worker” zamiast <none>. --overwrite: ponowne uruchomienie nie zgłasza błędu.
#   3. Pokazuje węzły (get nodes -o wide) i wszystkie pody (get pods -A).
#
# Niczego nie instaluje – tylko czeka, etykietuje i pokazuje stan.
# Odpowiednik w Ansible: ostatni play w ansible/playbooks/k3s.yml („Kontrola klastra i role węzłów”)
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
