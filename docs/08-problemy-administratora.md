# 8. Z czym zmaga się administrator – problemy z budowy laboratorium

Ten dokument zbiera **prawdziwe problemy**, które pojawiły się przy budowie tego laboratorium,
w kolejności, w jakiej wychodziły. Przy każdym: objaw, przyczyna, jak to zdiagnozować, jak naprawić
i czego uczy. Większość z nich spotkasz też w pracy – na serwerach, w chmurze, w automatyzacji.

Krótka ściągawka objaw → rozwiązanie jest w [przewodniku](00-przewodnik.md#najczęstsze-problemy).
Tutaj jest szerszy kontekst.

## Jak diagnozować – metoda ogólna

1. **Przeczytaj cały komunikat błędu**, nie tylko ostatnią linię. Ansible i systemd zwykle mówią
   wprost, co jest nie tak (`Timeout waiting for privilege escalation prompt`,
   `couldn't resolve module`).
2. **Ustal, gdzie jesteś.** Połowa zagadek to polecenie wpisane na złej maszynie. Patrz na znak
   zachęty: `PS C:\...>` to Windows, `user@nazwa:~$` to Linux – i *który* Linux.
3. **Sprawdź stan, nie zakładaj go.** `ip a`, `hostnamectl`, `cat plik`, `sudo --version`,
   `ansible-galaxy collection list` – jedno polecenie rozstrzyga, zamiast zgadywać.
4. **Zmieniaj jedną rzecz naraz** i sprawdzaj efekt.
5. **Miej punkt powrotu.** Snapshot przed każdym większym krokiem kosztuje sekundy.
6. **Zapisz rozwiązanie** – w kodzie (komentarz), w dokumentacji albo w tabeli problemów.

---

## Sieć

### Adres maszyny zależny od Wi-Fi

- **Objaw:** maszyny w trybie *Bridged* dostają adresy z sieci domowej; po zmianie sieci Wi-Fi
  (inne miejsce, inny router) stałe adresy przestają pasować i klaster traci łączność.
- **Przyczyna:** Bridged wpina maszyny bezpośrednio w fizyczną sieć – adresacja zależy od routera.
- **Rozwiązanie:** sieć **NAT VMware (VMnet8)** – własna, stała podsieć wewnątrz komputera,
  niezależna od Wi-Fi. Maszyny wychodzą do internetu przez NAT, a adresy się nie zmieniają.
- **Wniosek:** w labie (i w chmurze – VPC) sieć projektuje się tak, żeby nie zależała od tego,
  gdzie akurat stoi sprzęt.

### Zła brama domyślna

- **Objaw:** po ustawieniu stałego IP brak internetu; `ping 8.8.8.8` nie odpowiada.
- **Przyczyna:** w VMnet8 `.1` to karta hosta (Windows), a bramą NAT i serwerem DNS jest **`.2`**.
  Intuicyjne „brama = .1” tu nie działa.
- **Diagnoza:** Windows: `ipconfig` (adres karty VMnet8); VMware: *Virtual Network Editor → NAT Settings*.
- **Wniosek:** nie zakładaj konwencji – sprawdź konfigurację konkretnej sieci.

### Ten sam MAC na kilku klonach

- **Objaw:** brama `.2` raz odpowiada, raz nie; maszyny „gubią” sieć na zmianę.
- **Przyczyna:** klony skopiowały adres MAC karty. Dwie karty z tym samym MAC w jednej sieci
  przejmują sobie nawzajem ruch.
- **Rozwiązanie:** VMware → *Network Adapter → Advanced → Generate* dla każdego klonu.
- **Wniosek:** klonowanie kopiuje *wszystko*, także to, co musi być unikalne.

---

## Klonowanie maszyn

### Wspólny machine-id i klucze SSH hosta

- **Objaw:** DHCP daje kilku klonom ten sam adres; `ssh` ostrzega o zmienionym kluczu hosta.
- **Przyczyna:** `/etc/machine-id` (z niego DHCP liczy identyfikator klienta) i klucze
  `/etc/ssh/ssh_host_*` zostały skopiowane z szablonu.
- **Diagnoza:** `cat /etc/machine-id` na każdym klonie – wartości muszą się różnić.
- **Rozwiązanie:** przed klonowaniem wyczyścić machine-id na szablonie (`truncate -s 0`), a na
  klonach wygenerować nowe: `systemd-machine-id-setup`, `ssh-keygen -A`. Automatycznie: rola
  `bootstrap` w Ansible wykrywa powtórzenia między maszynami.
- **Wniosek:** szablon trzeba „uogólnić” przed klonowaniem – w świecie Windows to `sysprep`,
  w chmurze robi to cloud-init przy pierwszym starcie.

### Wspólny klucz hosta wykryty dopiero po zbudowaniu klastra

- **Objaw:** `ssh k3s-master` z nowej maszyny pyta o klucz i dodaje: *This host key is known by
  the following other names/addresses* – ten sam klucz jest zapisany pod adresami innych maszyn.
- **Przyczyna:** przy ręcznej konfiguracji klonów pominięto `ssh-keygen -A` – master, dwa workery
  i `monitoring` miały klucz szablonu. Ansible tego nie zgłosił, bo miał `host_key_checking = False`.
- **Diagnoza:** porównanie odcisków wszystkich maszyn z jednego miejsca:
  ```bash
  for ip in 51 52 53 54 55; do ssh-keyscan -t ed25519 192.168.180.$ip 2>/dev/null | ssh-keygen -lf -; done
  ```
- **Rozwiązanie:**
  1. nowe klucze na klonach (master zachował swój):
     `ansible k3s-worker-1,k3s-worker-2,monitoring -b -K -m shell -a "rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && systemctl restart ssh"`,
  2. stare wpisy usunięte z `known_hosts` (`ssh-keygen -R <nazwa lub adres>`) na każdym
     komputerze, z którego się łączysz,
  3. nowe odciski porównane z tym, co podaje sama maszyna
     (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, najlepiej w konsoli VMware), dopiero
     potem `yes`,
  4. w `ansible.cfg` włączone `host_key_checking = True` z `StrictHostKeyChecking=accept-new`.
- **Wniosek:** wyłączone zabezpieczenie nie tylko otwiera lukę, ale też **ukrywa błędy**.
  Ostrzeżenia SSH o kluczach czyta się, a nie odruchowo wpisuje `yes`.

### cloud-init przywraca stary adres i nazwę

- **Objaw:** po restarcie maszyna wraca do adresu z DHCP albo do nazwy szablonu.
- **Przyczyna:** cloud-init przy starcie generuje konfigurację sieci (`50-cloud-init.yaml`) i może
  ustawić nazwę hosta. Do tego zostały stare pliki Netplan, które wygrywają z nowym.
- **Rozwiązanie:** `network: {config: disabled}` i `preserve_hostname: true` w
  `/etc/cloud/cloud.cfg.d/`, stare pliki Netplan przeniesione, jeden plik `01-lab.yaml` z uprawnieniami `600`.
- **Wniosek:** gdy zmiana „sama się cofa”, coś ją nadpisuje przy starcie. Szukaj, kto zarządza plikiem.

---

## Powłoka i miejsce wykonania

### Zmienna pusta w nowej sesji

- **Objaw:** `sudo hostnamectl set-hostname $NAME` → *Too few arguments*.
- **Przyczyna:** zmienna ustawiona w poprzedniej sesji (lub ze spacją wokół `=`) – w nowej
  sesji jest pusta, więc polecenie dostaje o argument mniej.
- **Diagnoza:** `echo "$NAME"` przed użyciem.
- **Wniosek:** zmienne powłoki żyją tylko w bieżącej sesji. W skryptach – `set -u`, który
  przerywa przy pustej zmiennej.

### Polecenie wpisane na złej maszynie

- **Objaw:** `ssh k3s-master` pyta o hasło, choć klucz jest skonfigurowany.
- **Przyczyna:** polecenie wpisane w terminalu Linuxa (np. już na masterze), a klucz i
  `~/.ssh/config` są na Windowsie.
- **Wniosek:** zawsze patrz na znak zachęty. Dlatego przewodnik oznacza każdy krok 🪟 / 🖥️ / 🐧.

### Windows nie ma `ssh-copy-id`

- **Rozwiązanie:** `type klucz.pub | ssh user@host "cat >> ~/.ssh/authorized_keys"` – to samo,
  co robi `ssh-copy-id`, rozpisane ręcznie.
- **Wniosek:** warto wiedzieć, co narzędzie robi pod spodem – wtedy da się je zastąpić.

---

## SSH i uprawnienia

### `PasswordAuthentication no` nie działa

- **Objaw:** po wyłączeniu logowania hasłem SSH dalej je przyjmuje.
- **Przyczyna:** pliki w `/etc/ssh/sshd_config.d/` są czytane **alfabetycznie**, a dla większości
  opcji **wygrywa pierwsza** wartość. Ubuntu ma `50-cloud-init.conf` z `PasswordAuthentication yes`,
  więc nasz `99-lab.conf` przegrywał.
- **Diagnoza:** `sudo sshd -T | grep passwordauthentication` – efektywna konfiguracja.
  Test: `ssh -o PubkeyAuthentication=no host` ma dać `Permission denied (publickey)`.
- **Rozwiązanie:** plik `01-lab.conf` – czytany przed `50-cloud-init.conf`.
- **Wniosek:** przy plikach typu *drop-in* kolejność ma znaczenie, a reguła „pierwsza czy ostatnia
  wygrywa” różni się między programami. Sprawdzaj konfigurację efektywną, nie tylko plik.

### Skrypt bez prawa wykonywania

- **Objaw:** `sudo: cannot execute ...: Permission denied`.
- **Przyczyna:** pliki zapisane na Windowsie trafiły do gita bez bitu wykonywania.
- **Rozwiązanie:** `git update-index --chmod=+x scripts/*.sh` i commit (tryb `100755`).
- **Wniosek:** Windows nie zna uprawnień uniksowych – przy pracy między systemami trzeba
  je ustawiać w gicie jawnie.

### Ansible nie może przejść na roota (sudo-rs)

- **Objaw:** `Timeout (12s) waiting for privilege escalation prompt` na wszystkich maszynach,
  mimo poprawnego hasła.
- **Przyczyna:** Ubuntu 25.10+ ma domyślnie **sudo-rs** (sudo przepisane w Rust). Ansible czeka
  na swój tekst pytania o hasło i go nie rozpoznaje.
- **Diagnoza:** `sudo --version` → `sudo-rs ...`.
- **Rozwiązanie:** `become_exe = sudo.ws` w `ansible.cfg` – klasyczne sudo, nadal instalowane obok.
- **Wniosek:** najnowsza wersja systemu potrafi wyprzedzić narzędzia. W produkcji wybiera się
  wersje LTS i testuje aktualizacje na kopii.

---

## Automatyzacja: skrypty i Ansible

### Duplikaty po ponownym uruchomieniu

- **Objaw:** w `/etc/hosts` te same maszyny po kilka razy.
- **Przyczyna:** skrypt dopisywał wpisy bez sprawdzania, czy już są; później Ansible dodał
  własny blok obok wpisów skryptu.
- **Rozwiązanie:** skrypt najpierw usuwa stare wpisy, a rola `common` usuwa wpisy skryptu
  przed zapisaniem swojego bloku (`blockinfile`). Próba na sucho (`--check --diff`) pokazała
  problem, zanim cokolwiek się zmieniło.
- **Wniosek:** **idempotentność** – uruchomienie drugi raz nie może psuć. Przy przejściu
  ze skryptów na Ansible trzeba posprzątać po starym sposobie.

### Ansible nie działa na Windowsie

- **Objaw:** `No module named 'fcntl'`.
- **Przyczyna:** Ansible korzysta z funkcji systemów uniksowych; Windows może być tylko
  maszyną *zarządzaną*, nie sterującą.
- **Rozwiązanie:** węzeł sterujący na Linuxie (tu: `monitoring`), alternatywnie WSL.

### ansible-lint nie widzi modułów

- **Objaw:** `couldn't resolve module/action 'community.general.timezone'`, choć playbook działa.
- **Przyczyna:** pipx trzyma `ansible` i `ansible-lint` w osobnych środowiskach; kolekcje są
  tylko w środowisku `ansible`.
- **Rozwiązanie:** `ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force`.
  Szczegóły: [docs/06 – Narzędzia](06-ansible.md#narzędzia-pipx-kolekcje-i-ansible-lint).
- **Wniosek:** izolacja środowisk chroni przed konfliktami, ale każde narzędzie widzi tylko
  swoje zależności.

### Zmienna z inventory ignorowana

- **Objaw:** w inventory jest `admin_cidr`, a playbook używa innej wartości.
- **Przyczyna:** **pierwszeństwo zmiennych** – `group_vars/all/main.yml` wygrywa z `[all:vars]`
  w inventory.
- **Diagnoza:** `ansible all -m debug -a 'msg="{{ admin_cidr }}"'` – wartość, którą widzi Ansible.
- **Rozwiązanie:** zmienne zależne od środowiska tylko w inventory, wspólne – w `group_vars`.
- **Wniosek:** gdy ta sama zmienna jest w kilku miejscach, trzeba znać kolejność pierwszeństwa.

### Cudzysłowy i dzielenie argumentów

- **Ansible:** `-a "msg={{ a }} {{ b }}"` → *must resolve to a 'dict' not 'str'* – spacja dzieli
  argumenty. Poprawnie: `-a 'msg="{{ a }} {{ b }}"'`.
- **PowerShell:** `packer build -var-file=plik.pkrvars.hcl` pokazuje tylko `Usage:` – PowerShell 5.1
  rozbija argument na kropce. Poprawnie: `"-var-file=plik.pkrvars.hcl"`.
- **Wniosek:** każda powłoka i narzędzie ma własne reguły dzielenia argumentów. Gdy argument
  zawiera spacje, kropki lub `{}`, otocz go cudzysłowem.

---

## Packer i maszyny od zera

### Instalacja z ISO trwa długo

- **Objaw:** Packer instaluje maszynę kilkanaście minut, a klon powstaje w sekundę.
- **Przyczyna:** Packer (`vmware-iso`) przechodzi pełną instalację systemu i aktualizacje.
- **Wniosek:** to cena powtarzalności – maszyna powstaje zawsze tak samo, z kodu. W praktyce
  Packerem buduje się raz *obraz* (szablon), a z niego szybko klonuje.

---

## Bezpieczeństwo i repozytorium

### Sekrety i prywatne dane poza gitem

- **Problem:** hasła (Grafana, sudo w Packerze), adresy własnej sieci, prywatne notatki łatwo
  wypchnąć do publicznego repozytorium.
- **Rozwiązanie:** w repo tylko wzory (`lab.env.example`, `inventory.ini.example`,
  `*.pkrvars.hcl.example`), prawdziwe pliki w `.gitignore`; prywatne pliki lokalnie w
  `.git/info/exclude`.
- **Gdy już trafiło do gita:** usunięcie pliku w nowym commicie **nie wystarcza** – zostaje w
  historii. Trzeba przepisać historię i wykonać `git push --force`, a hasło i tak uznać za ujawnione
  i zmienić.

### CI nie działa

- **Objaw:** GitHub Actions nie uruchamia się (blokada rozliczeń konta).
- **Rozwiązanie:** te same kontrole lokalnie: `ansible-lint`, `yamllint`, `shellcheck`.
- **Wniosek:** automatyczne kontrole to wygoda, nie jedyna linia obrony – trzeba umieć je
  uruchomić ręcznie.

---

## Środowisko pracy

### Awaria komputera w trakcie pracy

- **Objaw:** komputer wyłączył się podczas robienia snapshotów.
- **Skutek:** maszyny przetrwały; po ponownym uruchomieniu sprawdzono ich stan i działano dalej.
- **Wniosek:** snapshoty i dokumentacja każdego kroku sprawiają, że awaria kosztuje minuty,
  a nie odbudowę od zera. To ta sama idea co kopie zapasowe i *runbooki* w produkcji.

## Co powiedzieć na rozmowie

> „Przy budowie laboratorium najwięcej czasu zajęły nie instalacje, tylko diagnozowanie:
> zduplikowane MAC i machine-id po klonowaniu, cloud-init cofający konfigurację sieci, kolejność
> plików drop-in w sshd, pierwszeństwo zmiennych w Ansible i sudo-rs w nowym Ubuntu, którego
> Ansible nie obsługiwał. Każdy problem rozwiązywałem od sprawdzenia faktycznego stanu, a
> rozwiązanie zapisywałem w kodzie i dokumentacji, żeby nie wróciło.”
