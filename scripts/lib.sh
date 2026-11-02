#!/usr/bin/env bash
# lib.sh – wspólne funkcje dla wszystkich skryptów laboratorium.
#
# Nie uruchamiasz go sam. Każdy skrypt z tego katalogu wczytuje go na początku:
#   source "$(dirname "$0")/lib.sh"
#
# Co robi po wczytaniu:
#   1. Ustala REPO_DIR – katalog repozytorium (jeden poziom nad scripts/), niezależnie od tego,
#      skąd uruchomiono skrypt.
#   2. Wczytuje lab.env z katalogu repozytorium – adresy maszyn, interfejs sieci, hasła.
#      Brak lab.env = komunikat i koniec (skopiuj lab.env.example do lab.env).
#   3. Udostępnia funkcje:
#        log "tekst"         – wyraźny, kolorowy nagłówek kroku (==> tekst)
#        require_root        – przerywa, jeśli skrypt nie jest uruchomiony przez sudo
#        use_k3s_kubeconfig  – kubectl i helm używają /etc/rancher/k3s/k3s.yaml (na masterze)
#
# set -euo pipefail – przerwij przy pierwszym błędzie (-e), przy nieznanej zmiennej (-u)
# i przy błędzie w środku potoku (pipefail).
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
