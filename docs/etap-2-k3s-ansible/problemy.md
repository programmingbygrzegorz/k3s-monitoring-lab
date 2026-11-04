# Etap 2 – klaster k3s przez Ansible – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Ansible nie może przejść na roota (sudo-rs)

- **Objaw:** `Timeout (12s) waiting for privilege escalation prompt` na wszystkich maszynach,
  mimo poprawnego hasła.
- **Przyczyna:** Ubuntu 25.10+ ma domyślnie **sudo-rs** (sudo przepisane w Rust). Ansible czeka
  na swój tekst pytania o hasło i go nie rozpoznaje.
- **Diagnoza:** `sudo --version` → `sudo-rs ...`.
- **Rozwiązanie:** `become_exe = sudo.ws` w `ansible.cfg` – klasyczne sudo, nadal instalowane obok.
- **Wniosek:** najnowsza wersja systemu potrafi wyprzedzić narzędzia. W produkcji wybiera się
  wersje LTS i testuje aktualizacje na kopii.

## Ansible nie działa na Windowsie

- **Objaw:** `No module named 'fcntl'`.
- **Przyczyna:** Ansible korzysta z funkcji systemów uniksowych; Windows może być tylko
  maszyną *zarządzaną*, nie sterującą.
- **Rozwiązanie:** węzeł sterujący na Linuxie (tu: `monitoring`), alternatywnie WSL.

## ansible-lint nie widzi modułów

- **Objaw:** `couldn't resolve module/action 'community.general.timezone'`, choć playbook działa.
- **Przyczyna:** pipx trzyma `ansible` i `ansible-lint` w osobnych środowiskach; kolekcje są
  tylko w środowisku `ansible`.
- **Rozwiązanie:** `ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force`.
  Szczegóły: [k3s przez Ansible – Narzędzia](02-k3s-przez-ansible.md#narzędzia-pipx-kolekcje-i-ansible-lint).
- **Wniosek:** izolacja środowisk chroni przed konfliktami, ale każde narzędzie widzi tylko
  swoje zależności.

## Zmienna z inventory ignorowana

- **Objaw:** w inventory jest `admin_cidr`, a playbook używa innej wartości.
- **Przyczyna:** **pierwszeństwo zmiennych** – `group_vars/all/main.yml` wygrywa z `[all:vars]`
  w inventory.
- **Diagnoza:** `ansible all -m debug -a 'msg="{{ admin_cidr }}"'` – wartość, którą widzi Ansible.
- **Rozwiązanie:** zmienne zależne od środowiska tylko w inventory, wspólne – w `group_vars`.
- **Wniosek:** gdy ta sama zmienna jest w kilku miejscach, trzeba znać kolejność pierwszeństwa.

## Cudzysłowy i dzielenie argumentów

- **Ansible:** `-a "msg={{ a }} {{ b }}"` → *must resolve to a 'dict' not 'str'* – spacja dzieli
  argumenty. Poprawnie: `-a 'msg="{{ a }} {{ b }}"'`.
- **PowerShell:** `packer build -var-file=plik.pkrvars.hcl` pokazuje tylko `Usage:` – PowerShell 5.1
  rozbija argument na kropce. Poprawnie: `"-var-file=plik.pkrvars.hcl"`.
- **Wniosek:** każda powłoka i narzędzie ma własne reguły dzielenia argumentów. Gdy argument
  zawiera spacje, kropki lub `{}`, otocz go cudzysłowem.

## `site.yml --check` kończy się failed na masterze

- **Objaw:** `ansible-playbook site.yml --check --diff` – zadanie „Poczekaj, aż węzeł sterujący
  będzie Ready” pokazuje 30 × `FAILED - RETRYING`, potem `fatal` z
  `"msg": "Command would have run if not in check mode"`. W `PLAY RECAP` `failed=1` na `k3s-master`.
  Klaster działa normalnie.
- **Przyczyna:** w trybie `--check` moduły `command` i `shell` **nie są uruchamiane** – Ansible
  nie wie, co zmieniłoby dowolne polecenie. Pętla `until` czekała na wynik `kubectl get node`,
  a dostawała pusty. Wcześniej próbę na sucho robiło się tylko na `prepare.yml`, więc nikt tego
  nie zauważył (2.11.2026, przy ćwiczeniu z pakietem `tree`).
- **Diagnoza:** treść `msg` mówi wprost, że polecenie zostało pominięte w check mode.
- **Rozwiązanie:** `check_mode: false` przy zadaniach, które **tylko czytają** stan
  (czekanie na `Ready`, `kubectl get nodes`) – w `roles/k3s_server/tasks/main.yml`
  i `playbooks/k3s.yml`. Wtedy działają także w próbie na sucho.
- **Wniosek:** `check_mode: false` tylko dla zadań bez skutków ubocznych – zadanie zmieniające
  system z tą opcją zmieniłoby go także w „próbie na sucho”. Dobry nawyk: `--check` na całym
  `site.yml`, nie tylko na fragmencie.

## `--limit` na workerze w `site.yml` – brak tokenu

- **Objaw:** `ansible-playbook site.yml --limit k3s-worker-1` (sprawdzone z `--check`, 2.11.2026):
  `Error processing keyword 'environment': object of type 'HostVarsVars' has no attribute
  'k3s_server_token'` przy „Zainstaluj k3s (agent)”, `failed=1`.
- **Przyczyna:** token powstaje w play mastera (`set_fact`), a `hostvars` innej maszyny ma tylko
  to, co już zostało na niej wykonane. Z `--limit` play mastera się nie uruchamia.
- **Rozwiązanie:** zmiany w roli `common` testuj na jednej maszynie przez
  `playbooks/prepare.yml --limit …`; do roli `k3s_agent` dołącz mastera: `--limit k3s-master,k3s-worker-1`.
- **Wniosek:** `--limit` ogranicza też maszyny, z których zbierane są dane – przy rolach
  zależnych od innych hostów trzeba je dołączyć.
