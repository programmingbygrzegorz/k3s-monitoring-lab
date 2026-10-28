# 1. Maszyny wirtualne

## Wymagania sprzętowe

Komputer z **minimum 32 GB RAM** (uruchomione maszyny zajmują razem 20 GB), procesorem z obsługą
wirtualizacji (VT-x / AMD-V) i ok. 200 GB wolnego miejsca na dysku.

## Tworzenie maszyn

1. Pobierz obraz **Ubuntu Server 24.04 LTS**.
2. Utwórz maszynę `ubuntu-template`, zainstaluj na niej system i sklonuj z niej 4 maszyny według
   tabeli z README (`k3s-master`, `k3s-worker-1`, `k3s-worker-2`, `monitoring`), ustawiając im
   RAM z tabeli. Szablon potem wyłącz.
3. Kartę sieciową ustaw w trybie **Bridged** – maszyny dostaną adresy w Twojej sieci domowej.
4. Podczas instalacji Ubuntu zaznacz **Install OpenSSH server**.

## Stały adres IP

Klaster wymaga stałych adresów. Edytuj plik Netplan (nazwa może się różnić):

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses: [192.168.1.51/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

```bash
sudo netplan apply
ip a
```

Powtórz na każdej maszynie z jej adresem. Upewnij się, że adresy są poza zakresem DHCP routera.

## Repozytorium i konfiguracja

Na każdej maszynie:

```bash
git clone https://github.com/<twoj-login>/k3s-monitoring-lab.git
cd k3s-monitoring-lab
cp lab.env.example lab.env
nano lab.env      # adresy IP, nazwa interfejsu, sieć administratora, hasło Grafany
```

## Przygotowanie systemu

```bash
sudo ./scripts/00-prepare-node.sh k3s-master      # na masterze
sudo ./scripts/00-prepare-node.sh k3s-worker-1    # na workerze 1
sudo ./scripts/00-prepare-node.sh k3s-worker-2    # na workerze 2
sudo ./scripts/00-prepare-node.sh monitoring      # na maszynie monitoring
```

Skrypt ustawia nazwę hosta i `/etc/hosts`, aktualizuje system, wyłącza swap i konfiguruje firewall `ufw`.

**Zrób snapshot wszystkich maszyn.** Gdy coś zepsujesz, wrócisz do czystego stanu w kilka sekund.
