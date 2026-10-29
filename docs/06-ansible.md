# 6. Automatyzacja w Ansible (Infrastructure as Code)

Skrypty Bash z folderu `scripts/` uruchamiasz na każdej maszynie osobno. Playbooki Ansible robią
to samo **na wszystkich maszynach naraz, z jednego miejsca**, a wynik jest zawsze taki sam.

| Skrypt Bash | Odpowiednik w Ansible |
|---|---|
| ręczna konfiguracja klonów (docs/01) | `playbooks/bootstrap.yml` (rola `bootstrap`) – patrz niżej |
| `00-prepare-node.sh` | `playbooks/prepare.yml` (rola `common`) |
| `01-install-master.sh` | rola `k3s_server` |
| `02-install-worker.sh` | rola `k3s_agent` – token przekazywany automatycznie |
| `03-post-install.sh` | ostatni etap `playbooks/k3s.yml` |

## Najważniejsze pojęcia

- **Węzeł sterujący (control node):** maszyna, z której uruchamiasz Ansible. Na pozostałych maszynach
  nic nie instalujesz – Ansible łączy się z nimi przez SSH.
- **Inventory:** lista maszyn podzielonych na grupy (`k3s_server`, `k3s_agents`, `monitoring_vm`).
- **Playbook:** plik YAML z listą zadań do wykonania na grupach maszyn.
- **Rola:** wielokrotnego użytku zestaw zadań, np. `common` przygotowuje każdy serwer.
- **Idempotentność:** ponowne uruchomienie playbooka nie zmienia niczego, co już jest w porządku.
  Drugie uruchomienie powinno pokazać `changed=0`.

## 1. Węzeł sterujący

Najprościej użyć maszyny `monitoring` (na Windowsie możesz też użyć WSL):

```bash
sudo apt update && sudo apt install -y pipx
pipx install --include-deps ansible
pipx ensurepath && source ~/.bashrc
ansible --version
```

## 2. Klucze SSH

Ansible loguje się na maszyny kluczem, bez hasła. Na węźle sterującym:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/k3s-lab -C "k3s-lab"
for host in 192.168.1.51 192.168.1.52 192.168.1.53 192.168.1.54; do
  ssh-copy-id -i ~/.ssh/k3s-lab.pub <użytkownik>@$host
done
```

Ścieżkę do klucza podaje `ansible_ssh_private_key_file` w inventory. Rola `common` wyłącza potem
logowanie hasłem przez SSH (`ssh_disable_password` w `group_vars/all.yml`).

## 3. Konfiguracja

```bash
cd k3s-monitoring-lab/ansible
cp inventory.ini.example inventory.ini
nano inventory.ini              # adresy IP, użytkownik SSH, klucz, iface, admin_cidr
ansible-galaxy collection install -r requirements.yml
```

Sprawdź połączenie ze wszystkimi maszynami:

```bash
ansible all -m ping
```

## 4. Klony szablonu: bootstrap (opcjonalnie)

Jeśli maszyny powstały przez sklonowanie jednego szablonu, mają te same: `machine-id`, klucze SSH
hosta i nazwę hosta, a do tego adres z DHCP. Ręcznie poprawia się to na każdej maszynie osobno –
playbook `bootstrap.yml` robi to na wszystkich naraz:

- generuje nowy `machine-id` i nowe klucze SSH hosta tam, gdzie powtarzają się między maszynami,
- ustawia nazwę hosta według inventory i wpis `127.0.1.1` w `/etc/hosts`,
- wyłącza w cloud-init zmiany nazwy hosta i sieci,
- przenosi stare pliki Netplan do `/root/netplan-old` i zapisuje `/etc/netplan/01-lab.yaml` ze stałym adresem,
- restartuje maszyny i łączy się z nimi pod nowym adresem.

Kolejność:

1. Uruchom klony z siecią w trybie DHCP i odczytaj na każdym tymczasowy adres (`ip a`).
2. Skopiuj klucz SSH na te adresy (`ssh-copy-id <użytkownik>@<adres-z-DHCP>`).
3. Przygotuj inventory:

   ```bash
   cp inventory-bootstrap.ini.example inventory-bootstrap.ini
   nano inventory-bootstrap.ini   # adresy z DHCP, stałe adresy, brama i DNS
   ```

4. Uruchom:

   ```bash
   ansible-playbook -i inventory-bootstrap.ini playbooks/bootstrap.yml --ask-become-pass
   ```

Na końcu każda maszyna potwierdza swój stały adres i nazwę. Od tej chwili używasz zwykłego
`inventory.ini` ze stałymi adresami.

Bootstrap uruchamiasz raz. Jeśli trzeba go powtórzyć (np. po dołożeniu nowego klonu), wpisz
skonfigurowanym już maszynom w `inventory-bootstrap.ini` jako `ansible_host` ich stały adres –
nic się na nich nie zmieni i nie zostaną zrestartowane.

> Jeśli szablon nie miał wyczyszczonego `machine-id`, klony mogą dostać z DHCP **ten sam adres**.
> Uruchamiaj je wtedy po kolei i odczytuj adres każdego, zanim włączysz następny – albo wyczyść
> `machine-id` na szablonie przed klonowaniem (docs/01).

W VMware zmień też każdemu klonowi adres MAC karty (**Network Adapter → Advanced → Generate**) –
tego Ansible nie zrobi, bo to ustawienie maszyny wirtualnej, a nie systemu.

## 5. Uruchomienie

Najpierw **próba na sucho** – Ansible pokaże, co by zmienił, nic nie zmieniając:

```bash
ansible-playbook playbooks/prepare.yml --check --diff --ask-become-pass
```

Potem właściwe uruchomienie całego laboratorium:

```bash
ansible-playbook site.yml --ask-become-pass
```

Na końcu zobaczysz listę trzech węzłów w stanie `Ready`. Uruchom polecenie drugi raz i sprawdź
podsumowanie `PLAY RECAP` – przy idempotentnych playbookach `changed` powinno wynosić 0
(poza krokiem wyłączania swapu, jeśli system go ponownie włączył).

Dalsze kroki (monitoring, aplikacja demo) wykonujesz skryptami `04`–`06` jak dotychczas.

## 6. Ćwiczenia

1. **Dodaj nowy pakiet** (np. `htop`) do roli `common` i uruchom tylko przygotowanie:
   `ansible-playbook playbooks/prepare.yml --ask-become-pass`. Zobacz, że zmiana dotyczy wszystkich maszyn.
2. **Uruchom tylko na jednej maszynie:** `--limit k3s-worker-1`.
3. **Zepsuj i napraw:** ręcznie usuń wpis z `/etc/hosts` na workerze i uruchom playbook ponownie –
   Ansible przywróci stan opisany w kodzie.
4. **Odtwórz worker od zera:** przywróć snapshot „czysty system” i uruchom `site.yml`.
   Worker sam dołączy do klastra.

## Co powiedzieć na rozmowie

> „Maszyny klonuję z jednego szablonu, a playbook bootstrap nadaje każdemu klonowi unikalny
> machine-id i klucze SSH, nazwę hosta i stały adres IP. Przygotowanie maszyn i instalację k3s mam
> opisane w Ansible: rola wspólna konfiguruje system
> i firewall, osobne role instalują węzeł sterujący i workery, a token do dołączania przekazywany
> jest automatycznie między etapami. Playbooki są idempotentne, więc mogę je uruchamiać wielokrotnie,
> a zmiany najpierw sprawdzam w trybie --check --diff. Jakość kodu pilnuje ansible-lint w GitHub Actions.”
