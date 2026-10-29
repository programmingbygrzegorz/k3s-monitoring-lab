# 1. Maszyny wirtualne

> Cała ścieżka od pustego VMware do klastra, z poleceniami w kolejności: [00-przewodnik.md](00-przewodnik.md).

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

## Przygotowanie szablonu przed klonowaniem

Klony dziedziczą `/etc/machine-id` szablonu, a router w DHCP może im wtedy przydzielić ten sam adres.
Przed sklonowaniem wyczyść identyfikator na `ubuntu-template` i wyłącz maszynę:

```bash
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo poweroff
```

Każdy klon wygeneruje własny `machine-id` przy pierwszym uruchomieniu. Sprawdź to na klonach
poleceniem `cat /etc/machine-id` – wartości muszą się różnić.

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

## Klucz SSH zamiast hasła

> Jak działają klucze SSH (użytkownika i hosta): [teoria-ssh-klucze.md](teoria-ssh-klucze.md).

Na swoim komputerze utwórz osobny klucz dla laboratorium:

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\k3s-lab -C "k3s-lab"
```

Wgraj klucz publiczny na każdą maszynę (ostatni raz podajesz hasło). Windows nie ma
`ssh-copy-id`, dlatego w PowerShell:

```powershell
type $env:USERPROFILE\.ssh\k3s-lab.pub | ssh <użytkownik>@192.168.1.51 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Powtórz dla pozostałych adresów. W pliku `~/.ssh/config` dopisz maszyny, aby logować się po nazwie:

```
Host k3s-master
    HostName 192.168.1.51
# ... pozostałe maszyny analogicznie

Host k3s-master k3s-worker-1 k3s-worker-2 monitoring
    User <użytkownik>
    IdentityFile ~/.ssh/k3s-lab
    IdentitiesOnly yes
```

Sprawdź, że `ssh k3s-master` loguje bez pytania o hasło. Skrypt `00-prepare-node.sh` wyłączy
wtedy logowanie hasłem przez SSH – ale tylko na maszynie, na której klucz już jest. Hasło zostaje
do `sudo` i do konsoli VMware.

## Przygotowanie systemu

```bash
sudo ./scripts/00-prepare-node.sh k3s-master      # na masterze
sudo ./scripts/00-prepare-node.sh k3s-worker-1    # na workerze 1
sudo ./scripts/00-prepare-node.sh k3s-worker-2    # na workerze 2
sudo ./scripts/00-prepare-node.sh monitoring      # na maszynie monitoring
```

Skrypt ustawia nazwę hosta i `/etc/hosts`, aktualizuje system, wyłącza swap, wyłącza logowanie hasłem
przez SSH (gdy masz już klucz) i konfiguruje firewall `ufw`. Opis każdej części skryptu:
[docs/skrypty/00-prepare-node.md](skrypty/00-prepare-node.md).

**Zrób snapshot wszystkich maszyn.** Gdy coś zepsujesz, wrócisz do czystego stanu w kilka sekund.
