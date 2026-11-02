#!/usr/bin/env bash
# 01-install-master.sh – instalacja węzła sterującego k3s (Etap 2, wariant bez Ansible).
#
# Gdzie:   na k3s-master, po 00-prepare-node.sh
# Użycie:  sudo ./scripts/01-install-master.sh
# Wymaga:  lab.env z MASTER_IP i IFACE (opcjonalnie K3S_CHANNEL, domyślnie stable)
#
# Co robi, po kolei:
#   1. Pobiera oficjalny instalator k3s (https://get.k3s.io) i uruchamia go w trybie "server":
#        --node-ip / --advertise-address  adres mastera z lab.env
#        --flannel-iface                 karta sieciowa dla sieci podów (np. ens33)
#        --write-kubeconfig-mode 0644    /etc/rancher/k3s/k3s.yaml czytelny bez sudo (lab)
#        --node-taint ...:NoSchedule     na masterze nie uruchamiają się zwykłe pody
#      Instalator kopiuje program /usr/local/bin/k3s (z kubectl, crictl) i tworzy
#      usługę systemd k3s.service.
#   2. Czeka, aż węzeł k3s-master będzie Ready, i pokazuje kubectl get nodes.
#   3. Wypisuje token dołączenia (/var/lib/rancher/k3s/server/node-token) – wpisz go jako
#      K3S_TOKEN w lab.env na workerach przed 02-install-worker.sh.
#
# Ponowne uruchomienie przeinstalowuje k3s z tymi samymi ustawieniami – dane klastra zostają.
# Odpowiednik w Ansible: ansible/roles/k3s_server/
# Opis: docs/etap-2-k3s-ansible/04-k3s-skryptami.md
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
