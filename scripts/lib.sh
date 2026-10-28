#!/usr/bin/env bash
# Wspólne funkcje dla skryptów laboratorium.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/lab.env"
export REPO_DIR

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Brak pliku lab.env. Skopiuj lab.env.example do lab.env i uzupełnij wartości." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

log() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Uruchom skrypt jako root (sudo)." >&2
    exit 1
  fi
}

use_k3s_kubeconfig() {
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
}
