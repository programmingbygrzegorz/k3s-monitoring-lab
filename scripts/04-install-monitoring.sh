#!/usr/bin/env bash
# Instalacja stosu monitoringu: Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics.
# Użycie (na k3s-master): sudo ./scripts/04-install-monitoring.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root
use_k3s_kubeconfig

if ! command -v helm > /dev/null; then
  log "Instaluję Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

log "Dodaję repozytorium chartów prometheus-community"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?Uzupełnij w lab.env}"
export HEALTHCHECKS_URL="${HEALTHCHECKS_URL:?Uzupełnij w lab.env}"

values_file="$(mktemp)"
trap 'rm -f "${values_file}"' EXIT
# shellcheck disable=SC2016  # celowo: envsubst ma podstawić tylko te dwie zmienne
envsubst '${GRAFANA_ADMIN_PASSWORD} ${HEALTHCHECKS_URL}' \
  < "${REPO_DIR}/monitoring/kube-prometheus-stack-values.yaml" > "${values_file}"

version_args=()
if [[ -n "${KPS_CHART_VERSION:-}" ]]; then
  version_args=(--version "${KPS_CHART_VERSION}")
fi

log "Instaluję kube-prometheus-stack (może potrwać kilka minut)"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values "${values_file}" \
  "${version_args[@]}" \
  --wait --timeout 15m

kubectl -n monitoring get pods -o wide

log "Gotowe. Dostęp:"
echo "  Grafana (w klastrze): http://${MASTER_IP}:30300  (login: admin)"
echo "  Prometheus:           http://${MASTER_IP}:30090"
echo "  Alertmanager:         http://${MASTER_IP}:30093"
