#!/usr/bin/env bash
# 02-install-worker.sh – dołączenie węzła roboczego do klastra k3s (Etap 2, wariant bez Ansible).
#
# Gdzie:   na każdym workerze osobno, po 01-install-master.sh
# Użycie:  sudo ./scripts/02-install-worker.sh <IP_TEGO_WĘZŁA>
#          np. na k3s-worker-1: sudo ./scripts/02-install-worker.sh 192.168.180.52
# Wymaga:  lab.env z MASTER_IP, IFACE i K3S_TOKEN (token wypisany przez 01-install-master.sh)
#
# Co robi:
#   1. Pobiera oficjalny instalator k3s (https://get.k3s.io) i uruchamia go w trybie "agent"
#      ze zmiennymi:
#        K3S_URL=https://MASTER_IP:6443   gdzie jest API mastera
#        K3S_TOKEN=...                    „hasło” dołączenia do klastra
#      i opcjami --node-ip (adres z argumentu) oraz --flannel-iface.
#      Instalator kopiuje /usr/local/bin/k3s i tworzy usługę systemd k3s-agent.service,
#      która łączy się z masterem i rejestruje węzeł.
#   2. Przypomina, żeby sprawdzić na masterze: kubectl get nodes -o wide.
#
# Odpowiednik w Ansible: ansible/roles/k3s_agent/ (token przekazywany automatycznie przez hostvars)
# Opis: docs/etap-2-k3s-ansible/04-k3s-skryptami.md
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
