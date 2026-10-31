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
