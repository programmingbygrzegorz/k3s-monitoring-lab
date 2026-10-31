#!/usr/bin/env bash
# Przygotowanie maszyny wirtualnej: nazwa hosta, /etc/hosts, aktualizacje, swap, firewall.
# Użycie (na każdej maszynie): sudo ./scripts/00-prepare-node.sh <nazwa-hosta>
# Opis każdej części: docs/etap-1-przygotowanie-systemu/01-skrypt-prepare-node.md
# Nazwy hostów: k3s-master, k3s-worker-1, k3s-worker-2, (opcjonalnie k3s-worker-3), monitoring
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require_root

NEW_HOSTNAME="${1:?Podaj nazwę hosta, np. k3s-master}"

log "Ustawiam nazwę hosta: ${NEW_HOSTNAME}"
hostnamectl set-hostname "${NEW_HOSTNAME}"

log "Aktualizuję /etc/hosts"
# Usuń każdy wpis z nazwą maszyny labu (także dopisany ręcznie), poza liniami 127.x
sed -i -E '/^127\./!{/[[:space:]](k3s-master|k3s-worker-[0-9]+|monitoring)([[:space:]]|$)/d}' /etc/hosts
cat >> /etc/hosts << HOSTS
${MASTER_IP:?} k3s-master # k3s-lab
${WORKER1_IP:?} k3s-worker-1 # k3s-lab
${WORKER2_IP:?} k3s-worker-2 # k3s-lab
${MONITORING_IP:?} monitoring # k3s-lab
HOSTS
if [[ -n "${WORKER3_IP:-}" ]]; then
  echo "${WORKER3_IP} k3s-worker-3 # k3s-lab" >> /etc/hosts
fi

log "Aktualizuję system i instaluję narzędzia"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl ca-certificates gettext-base jq ufw
timedatectl set-timezone Europe/Warsaw

log "Wyłączam swap"
swapoff -a
sed -i.bak '/\sswap\s/ s/^#*/#/' /etc/fstab

# Logowanie hasłem przez SSH wyłączamy tylko wtedy, gdy użytkownik ma już klucz –
# inaczej odcięlibyśmy się od maszyny (zostałaby tylko konsola VMware).
ADMIN_USER="${SUDO_USER:-root}"
AUTHORIZED_KEYS="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)/.ssh/authorized_keys"
if [[ -s "${AUTHORIZED_KEYS}" ]]; then
  log "Wyłączam logowanie hasłem przez SSH (${ADMIN_USER} ma klucz w authorized_keys)"
  # sshd bierze pierwszą znalezioną wartość, a pliki czyta alfabetycznie – nazwa 01-
  # wyprzedza 50-cloud-init.conf z Ubuntu, w którym jest PasswordAuthentication yes
  rm -f /etc/ssh/sshd_config.d/99-lab.conf
  echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/01-lab.conf
  systemctl reload ssh
else
  log "UWAGA: ${ADMIN_USER} nie ma klucza SSH – logowanie hasłem zostaje włączone (docs/etap-0-maszyny-wirtualne/01-maszyny-wirtualne.md, Klucz SSH)"
fi

if [[ "${ENABLE_UFW:-yes}" != "yes" ]]; then
  log "Pomijam konfigurację firewalla (ENABLE_UFW=${ENABLE_UFW})"
  exit 0
fi

log "Konfiguruję firewall (ufw)"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from "${ADMIN_CIDR:?}" to any port 22 proto tcp comment 'SSH z sieci administratora'

if [[ "${NEW_HOSTNAME}" == "monitoring" ]]; then
  ufw allow from "${ADMIN_CIDR}" to any port 3000 proto tcp comment 'Grafana'
  ufw allow from "${ADMIN_CIDR}" to any port 3001 proto tcp comment 'Uptime Kuma'
else
  # Pełna komunikacja między węzłami klastra
  for ip in "${MASTER_IP}" "${WORKER1_IP}" "${WORKER2_IP}" ${WORKER3_IP:+"${WORKER3_IP}"}; do
    ufw allow from "${ip}" comment 'węzeł k3s'
  done
  # Sieci podów i usług k3s (domyślne zakresy)
  ufw allow from 10.42.0.0/16 comment 'k3s pody'
  ufw allow from 10.43.0.0/16 comment 'k3s usługi'
  # API Kubernetesa dla kubectl z komputera administratora
  ufw allow from "${ADMIN_CIDR}" to any port 6443 proto tcp comment 'API Kubernetesa'
  # Ruch HTTP/HTTPS do Ingressu i NodePorty (Grafana, Prometheus, aplikacja demo)
  ufw allow 80,443/tcp comment 'Ingress'
  ufw allow from "${ADMIN_CIDR}" to any port 30000:32767 proto tcp comment 'NodePort'
  ufw allow from "${MONITORING_IP}" to any port 30000:32767 proto tcp comment 'NodePort dla maszyny monitoring'
fi

ufw --force enable
ufw status verbose

log "Gotowe. Węzeł ${NEW_HOSTNAME} jest przygotowany."
