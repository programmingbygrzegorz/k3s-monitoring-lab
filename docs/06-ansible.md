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
- **Moduł:** gotowy kawałek kodu, który wie, jak zrobić jedną rzecz na maszynie (`apt`, `copy`, `ufw`).
  Każde zadanie w roli to wywołanie modułu.
- **Kolekcja:** paczka modułów, np. `community.general`. Pełna nazwa modułu to
  `przestrzeń.kolekcja.moduł`, np. `community.general.timezone`.
- **Become:** przejście na roota (`sudo`) na maszynie docelowej. Logowanie odbywa się kluczem,
  ale `sudo` pyta o hasło – stąd `--ask-become-pass`.

## Narzędzia: pipx, kolekcje i ansible-lint

Jeśli instalujesz Ansible pierwszy raz, ta część wyjaśnia, co właściwie ląduje na dysku i dlaczego.

### pipx – instalator programów w Pythonie

Ansible i ansible-lint są napisane w Pythonie. Klasyczny `pip` instaluje biblioteki do jednego
wspólnego miejsca, więc programy mogą sobie nawzajem psuć zależności – dlatego Ubuntu blokuje
`pip install` poza środowiskiem wirtualnym. **pipx** instaluje każdy *program* do osobnego
środowiska (*venv* – folder z własnym Pythonem i bibliotekami) i wystawia tylko jego polecenia:

```
~/.local/share/pipx/venvs/ansible/        ← ansible i jego biblioteki
~/.local/share/pipx/venvs/ansible-lint/   ← ansible-lint i jego biblioteki (osobna kopia ansible-core)
~/.local/bin/ansible, ansible-lint, ...   ← skróty do poleceń (pipx ensurepath dodaje je do PATH)
```

| Polecenie | Co robi |
|---|---|
| `pipx install --include-deps ansible` | instaluje Ansible; `--include-deps` wystawia też polecenia zależności (`ansible-playbook`, `ansible-galaxy`) |
| `pipx install ansible-lint` | instaluje lint w osobnym środowisku |
| `pipx ensurepath` | dopisuje `~/.local/bin` do `PATH` – działa po ponownym zalogowaniu |
| `pipx list` / `pipx upgrade ansible` / `pipx uninstall ansible` | lista, aktualizacja, usunięcie (bez śladów w systemie) |

### Pakiet `ansible` a `ansible-core` i kolekcje

| Pakiet | Zawartość |
|---|---|
| `ansible-core` | silnik i moduły `ansible.builtin.*` (`copy`, `apt`, `command`, `template`) |
| `ansible` | `ansible-core` **plus ok. 80 popularnych kolekcji**, m.in. `community.general` |

Rola `common` używa modułów spoza rdzenia (`community.general.timezone`, `community.general.ufw`),
dlatego projekt wymienia je w `requirements.yml`.

Przez osobne środowiska pipx kolekcje z pakietu `ansible` widzi tylko `ansible`. `ansible-lint`
ma w swoim środowisku samo `ansible-core` i zgłasza:

```
couldn't resolve module/action 'community.general.timezone'
```

Rozwiązanie: zainstalować kolekcję do katalogu, który przeszukują **wszystkie** narzędzia Ansible:

```bash
ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force
ansible-galaxy collection list community.general
```

| Część | Znaczenie |
|---|---|
| `ansible-galaxy` | pobiera kolekcje z Ansible Galaxy (katalog dodatków) |
| `-r requirements.yml` | lista kolekcji z projektu |
| `-p ~/.ansible/collections` | katalog docelowy wspólny dla wszystkich narzędzi |
| `--force` | instaluje, nawet jeśli kolekcja jest już w innym miejscu |

`collection list` pokaże kolekcję w dwóch miejscach – to nie przeszkadza, Ansible bierze pierwszą
znalezioną. Jeśli instalacja zatrzyma się na już zainstalowanej zależności, `Ctrl+C` jest bezpieczne.

### ansible-lint – korektor kodu

*Lint* czyta kod i szuka błędów **bez uruchamiania go**. ansible-lint robi to dla playbooków i ról:

| Rodzaj | Przykład | Skutek bez lintu |
|---|---|---|
| błędy | literówka w nazwie modułu, brak kolekcji, zła składnia YAML | playbook przerywa się w połowie, na żywych maszynach |
| dobre praktyki | zadanie bez `name`, `command` bez `changed_when`, plik bez jawnych uprawnień | działa, ale nieprzewidywalnie lub nieidempotentnie |
| styl | wcięcia, krótkie nazwy modułów (`apt` zamiast `ansible.builtin.apt`) | trudniej czytać i utrzymać |

```bash
ansible-lint site.yml playbooks roles
```

Dobry wynik: `Passed: 0 failure(s), 0 warning(s) ... profile 'production'`. Profile to coraz
ostrzejsze zestawy reguł (`min` → `basic` → `moderate` → `safety` → `shared` → `production`).
Ostrzeżenie *Directory expansion discovered N file(s)* to tylko informacja o liczbie znalezionych plików.

### Lint, próba na sucho, uruchomienie

| | `ansible-lint` | `ansible-playbook --check --diff` | `ansible-playbook` |
|---|---|---|---|
| łączy się z maszynami | nie – czyta pliki | tak, przez SSH | tak |
| sprawdza | czy **kod** jest poprawny | co by się **zmieniło** na maszynach | – wykonuje zmiany |
| kiedy | po każdej zmianie kodu | przed uruchomieniem | na końcu |

Ta kolejność to standard pracy z Ansible. W repozytorium lint uruchamia się też automatycznie
w GitHub Actions przy każdym `git push`.

## 1. Węzeł sterujący

Najprościej użyć maszyny `monitoring` (na Windowsie możesz też użyć WSL):

```bash
sudo apt update && sudo apt install -y pipx
pipx install --include-deps ansible
pipx install ansible-lint
pipx ensurepath && source ~/.bashrc
ansible --version
```

Co instalują te polecenia: [Narzędzia: pipx, kolekcje i ansible-lint](#narzędzia-pipx-kolekcje-i-ansible-lint).

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
ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force
```

`-p ~/.ansible/collections` instaluje kolekcję do katalogu wspólnego dla wszystkich narzędzi –
inaczej `ansible-lint` (osobne środowisko pipx) nie znajdzie modułów `community.general`.

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

`--ask-become-pass` pyta raz o hasło `sudo` użytkownika na maszynach (SSH działa kluczem,
ale `sudo` nadal wymaga hasła). Na Ubuntu 25.10+ domyślne jest sudo-rs, którego pytania o hasło
Ansible nie rozpoznaje (*Timeout waiting for privilege escalation prompt*) – dlatego
`ansible.cfg` ustawia `become_exe = sudo.ws`, czyli klasyczne sudo instalowane obok.

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
