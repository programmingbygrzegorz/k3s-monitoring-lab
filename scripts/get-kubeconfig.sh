#!/usr/bin/env bash
# Pobiera kubeconfig z mastera na Twój komputer, aby używać kubectl / k9s lokalnie.
# Użycie (na swoim komputerze): ./scripts/get-kubeconfig.sh <użytkownik-ssh>
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
