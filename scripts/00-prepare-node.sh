#!/usr/bin/env bash
# 00-prepare-node.sh – przygotowanie systemu jednej maszyny labu (Etap 1).
#
# Gdzie:   na KAŻDEJ maszynie osobno (k3s-master, k3s-worker-1/2/3, monitoring)
# Użycie:  sudo ./scripts/00-prepare-node.sh <nazwa-hosta>
#          np. ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"
# Wymaga:  lab.env z MASTER_IP, WORKER1_IP, WORKER2_IP, (WORKER3_IP), MONITORING_IP, ADMIN_CIDR
#
# Co robi, po kolei:
#   1. Ustawia nazwę hosta (hostnamectl) na podaną w argumencie.
#   2. /etc/hosts: usuwa stare wpisy z nazwami maszyn labu i dopisuje aktualne adresy
#      z lab.env (z dopiskiem "# k3s-lab") – maszyny znają się po nazwach.
#   3. apt-get update + upgrade, instaluje curl, ca-certificates, gettext-base (envsubst), jq, ufw;
#      strefa czasowa Europe/Warsaw.
#   4. Wyłącza swap teraz (swapoff -a) i na stałe (komentuje linię swap w /etc/fstab,
#      kopia: /etc/fstab.bak) – kubelet wymaga wyłączonego swapu.
#   5. SSH tylko kluczem: plik /etc/ssh/sshd_config.d/01-lab.conf z "PasswordAuthentication no"
#      i przeładowanie ssh – ale TYLKO gdy użytkownik ma już klucz w authorized_keys
#      (inaczej zostałby bez dostępu przez SSH).
#   6. Firewall ufw od zera: blokuj ruch przychodzący, SSH tylko z ADMIN_CIDR, potem:
#        - monitoring:   porty 3000 (Grafana) i 3001 (Uptime Kuma) z ADMIN_CIDR
#        - węzły k3s:    wszystko z innych węzłów, sieci 10.42.0.0/16 (pody) i 10.43.0.0/16
#                        (usługi), 6443 (API) z ADMIN_CIDR, 80/443 (Ingress), NodePorty
#                        30000-32767 z ADMIN_CIDR i z maszyny monitoring
#      Pominięte, gdy w lab.env jest ENABLE_UFW=no.
#
# Można uruchomić ponownie – nie dubluje wpisów w /etc/hosts, firewall ustawia od nowa.
# Odpowiednik w Ansible: ansible/roles/common/
# Opis każdej części:    docs/etap-1-przygotowanie-systemu/01-skrypt-prepare-node.md
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
