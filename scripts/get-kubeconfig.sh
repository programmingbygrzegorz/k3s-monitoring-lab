#!/usr/bin/env bash
# get-kubeconfig.sh – dostęp do klastra z Twojego komputera (kubectl, k9s, Headlamp lokalnie).
#
# Gdzie:   na SWOIM komputerze (Git Bash na Windowsie, Linux, macOS), w katalogu repozytorium
# Użycie:  ./scripts/get-kubeconfig.sh <użytkownik-ssh>      (bez sudo)
# Wymaga:  lab.env z MASTER_IP także na tym komputerze; dostęp ssh do k3s-master
#
# Co robi, po kolei:
#   1. Kopiuje przez scp plik /etc/rancher/k3s/k3s.yaml z mastera do ~/.kube/k3s-lab.kubeconfig
#      (adres API, certyfikat klastra i klucz administratora).
#   2. Podmienia adres https://127.0.0.1:6443 (dobry tylko na samym masterze) na
#      https://MASTER_IP:6443.
#   3. Ustawia uprawnienia 600 – plik daje pełną władzę nad klastrem.
#   4. Wypisuje, jak go użyć: export KUBECONFIG=~/.kube/k3s-lab.kubeconfig && kubectl get nodes
#
# Firewall wpuszcza port 6443 tylko z ADMIN_CIDR (00-prepare-node.sh / rola common).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

SSH_USER="${1:?Podaj użytkownika SSH na k3s-master}"
TARGET="${HOME}/.kube/k3s-lab.kubeconfig"

mkdir -p "${HOME}/.kube"
scp "${SSH_USER}@${MASTER_IP:?}:/etc/rancher/k3s/k3s.yaml" "${TARGET}"
sed -i.bak "s#https://127.0.0.1:6443#https://${MASTER_IP}:6443#" "${TARGET}"
rm -f "${TARGET}.bak"
chmod 600 "${TARGET}"

echo "Zapisano: ${TARGET}"
echo "Użyj: export KUBECONFIG=${TARGET} && kubectl get nodes"
