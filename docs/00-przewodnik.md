# Przewodnik krok po kroku – od pustego VMware do klastra k3s

Ten plik prowadzi przez całą budowę laboratorium **w kolejności**, z każdym poleceniem do
wpisania. Przy każdym kroku jest napisane **gdzie** go wykonać:

| Oznaczenie | Gdzie | Jak rozpoznać |
|---|---|---|
| 🪟 **Windows** | PowerShell na Twoim komputerze | znak zachęty `PS C:\...>` |
| 🖥️ **konsola VMware** | okno maszyny w VMware (logowanie hasłem) | `login:` / `user@nazwa:~$` |
| 🐧 **maszyna** | terminal Linuxa przez SSH (`ssh <nazwa>` z Windowsa) | `user@nazwa:~$` |

Szczegóły i wyjaśnienia są w plikach `docs/01`–`07`; tutaj jest sama ścieżka.

## Plan laboratorium

| Maszyna | Rola | vCPU | RAM (MB) | Dysk | Adres IP (przykład) |
|---|---|---|---|---|---|
| ubuntu-template | szablon do klonowania (wyłączony) | 2 | 4096 | 40 GB | – |
| k3s-master | węzeł sterujący k3s | 2 | 4096 | 40 GB | 192.168.180.51 |
| k3s-worker-1 | węzeł roboczy | 2 | 6144 | 40 GB | 192.168.180.52 |
| k3s-worker-2 | węzeł roboczy | 2 | 6144 | 40 GB | 192.168.180.53 |
| monitoring | monitoring zewnętrzny, węzeł sterujący Ansible | 2 | 4096 | 40 GB | 192.168.180.54 |
| k3s-worker-3 | węzeł roboczy (opcjonalny) | 2 | 6144 | 40 GB | 192.168.180.55 |

Adresy w przykładach dotyczą sieci NAT VMware `192.168.180.0/24`. Twoja sieć VMnet8 może mieć
inny trzeci człon – sprawdzisz go w kroku 1 i wszędzie podstawisz własny.

---

## Etap 0 – sieć i maszyny wirtualne

### Krok 1. Sieć NAT w VMware (VMnet8)

Maszyny dostają stałe adresy w wewnętrznej sieci NAT VMware. Ta sieć nie zależy od Wi-Fi ani
kabla – adresy maszyn nie zmienią się, gdy komputer podłączy się do innej sieci.

🪟 Windows:

```powershell
ipconfig
```

Znajdź **VMware Network Adapter VMnet8**, np. `IPv4 Address: 192.168.180.1`. Wtedy:

| Element | Adres |
|---|---|
| sieć | `192.168.180.0/24` |
| Twój komputer w tej sieci | `192.168.180.1` |
| brama i DNS (router NAT VMware) | **`192.168.180.2`** |
| pula DHCP VMware | `.128` – `.254` (stałe adresy maszyn wybieraj poniżej) |

Bramę potwierdzisz w VMware: **Edit → Virtual Network Editor → VMnet8 → NAT Settings → Gateway IP**.

### Krok 2. Szablon Ubuntu

1. VMware: nowa maszyna `ubuntu-template` (parametry z tabeli), sieć **NAT**, ISO Ubuntu Server.
2. Podczas instalacji zaznacz **Install OpenSSH server**. Zapamiętaj użytkownika i hasło.
3. 🖥️ Po instalacji zaloguj się w konsoli VMware i zaktualizuj system:

   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

4. 🖥️ **Przed klonowaniem** wyczyść identyfikator maszyny i wyłącz ją:

   ```bash
   sudo truncate -s 0 /etc/machine-id
   sudo rm -f /var/lib/dbus/machine-id
   cat /etc/machine-id        # ma nic nie wyświetlić
   sudo poweroff
   ```

   Pusty `machine-id` sprawia, że każdy klon wygeneruje własny przy pierwszym starcie.
   Bez tego klony dostają z DHCP ten sam adres, a systemd i k3s mylą maszyny.

5. VMware: prawy klik na szablonie → **Snapshot → Take Snapshot** → `czysty`.
   Szablonu od tej chwili nie uruchamiaj.

> Zamiast szablonu i klonów możesz budować maszyny **Packerem** – instalacja z ISO bez
> klikania, od razu ze stałym IP i kluczem SSH: [docs/07-packer.md](07-packer.md).

### Krok 3. Klony

Dla każdej maszyny z tabeli (`k3s-master`, `k3s-worker-1`, `k3s-worker-2`, `monitoring`):

1. Prawy klik na `ubuntu-template` → **Manage → Clone…** → snapshot `czysty` →
   **Create a full clone** → nazwa maszyny.
2. **Edit virtual machine settings:**
   - **Memory:** wartość z tabeli (MB),
   - **Network Adapter:** **NAT**, zaznaczone *Connected* i *Connect at power on*,
   - **Network Adapter → Advanced… → Generate** – **nowy adres MAC** (klon ma MAC szablonu;
     dwie maszyny z tym samym MAC gubią ruch sieciowy).
3. Uruchom maszynę. Na pytanie VMware wybierz **I copied it**.

### Krok 4. Tożsamość i stały adres każdego klonu

🖥️ Konsola VMware na każdym klonie (jeszcze nie ma stałego adresu, więc nie przez SSH).
Na początku ustaw dwie zmienne – dalsze polecenia są takie same na każdej maszynie:

```bash
NAME=k3s-master
IP=192.168.180.51
echo $NAME $IP             # sprawdzenie
```

Bez spacji wokół `=`. Zmienne znikają po wylogowaniu – wszystkie kroki wykonaj w jednej sesji.

**4.1. Unikalny machine-id i klucze SSH hosta** (klon odziedziczył je po szablonie):

```bash
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id && sudo systemd-machine-id-setup
sudo rm -f /etc/ssh/ssh_host_* && sudo ssh-keygen -A
```

**4.2. Nazwa hosta** – cloud-init nie przywróci starej przy restarcie:

```bash
sudo hostnamectl set-hostname $NAME
echo "preserve_hostname: true" | sudo tee /etc/cloud/cloud.cfg.d/99-hostname.cfg
```

**4.3. `/etc/hosts`** – własna nazwa (pełną listę maszyn dopisze później skrypt `00-prepare-node.sh`):

```bash
sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NAME/" /etc/hosts
```

**4.4. Stały adres IP** – wyłącz zarządzanie siecią przez cloud-init, odłóż stare pliki
Netplan i zapisz jeden nowy:

```bash
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo mkdir -p /root/netplan-old && sudo mv /etc/netplan/*.yaml /root/netplan-old/
printf "network:\n  version: 2\n  ethernets:\n    ens33:\n      dhcp4: false\n      addresses: [$IP/24]\n      routes:\n        - to: default\n          via: 192.168.180.2\n      nameservers:\n        addresses: [192.168.180.2, 1.1.1.1]\n" | sudo tee /etc/netplan/01-lab.yaml
sudo chmod 600 /etc/netplan/01-lab.yaml
sudo reboot
```

`ens33` to nazwa karty – sprawdź ją wcześniej poleceniem `ip a` i popraw, jeśli jest inna.

**4.5. Sprawdzenie** po restarcie:

```bash
hostname                   # nowa nazwa
ip a                       # ens33: inet 192.168.180.5x/24
cat /etc/machine-id        # inny na każdej maszynie
ping -c 3 google.com       # internet działa
```

> Ten krok automatyzuje rola Ansible `bootstrap` (docs/06, *Klony szablonu*), a Packer
> w ogóle go eliminuje.

---

## Etap 0b – dostęp przez klucz SSH

> Czym różni się klucz użytkownika od klucza hosta, co trafia do `authorized_keys`, a co do
> `known_hosts`: [docs/teoria-ssh-klucze.md](teoria-ssh-klucze.md).

### Krok 5. Klucz na Twoim komputerze

🪟 Windows:

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\k3s-lab -C "k3s-lab"
```

Osobny klucz tylko dla laboratorium – w razie potrzeby unieważnisz go, nie ruszając innych.

### Krok 6. Logowanie po nazwie (`~/.ssh/config`)

🪟 Windows – utwórz plik `C:\Users\<Ty>\.ssh\config` (np. `notepad $env:USERPROFILE\.ssh\config`):

```
Host k3s-master
    HostName 192.168.180.51
Host k3s-worker-1
    HostName 192.168.180.52
Host k3s-worker-2
    HostName 192.168.180.53
Host monitoring
    HostName 192.168.180.54

Host k3s-master k3s-worker-1 k3s-worker-2 monitoring 192.168.180.*
    User <użytkownik>
    IdentityFile ~/.ssh/k3s-lab
    IdentitiesOnly yes
```

Nazwy działają tylko dla `ssh` i `scp` na Windowsie (np. `ping k3s-master` w PowerShell nie zadziała).

### Krok 7. Klucz na maszyny

🪟 Windows, dla każdej maszyny (ostatni raz podajesz hasło):

```powershell
type $env:USERPROFILE\.ssh\k3s-lab.pub | ssh k3s-master "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Przy pierwszym połączeniu z maszyną odpowiedz `yes`. Nie powtarzaj polecenia – każde
uruchomienie dopisuje klucz ponownie.

### Krok 8. Test

🪟 Windows:

```powershell
ssh k3s-master hostname
```

Ma od razu wypisać nazwę maszyny, **bez hasła**. Z maszyny na maszynę nie przeskakuj
(`ssh` wpisane **na** Linuksie zapyta o hasło – klucz jest tylko na Windowsie): `exit`,
potem `ssh <następna>` z Windowsa.

---

## Etap 1 – przygotowanie systemu

### Krok 9. Repozytorium na każdej maszynie

🪟 Windows, dla każdej maszyny:

```powershell
ssh k3s-master "sudo apt install -y git; git clone https://github.com/<twoj-login>/k3s-monitoring-lab.git ~/k3s-monitoring-lab"
```

Jeśli repozytorium już jest: `ssh k3s-master "cd ~/k3s-monitoring-lab && git pull"`.

### Krok 10. `lab.env` na każdej maszynie

🪟 Windows:

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && cp -n lab.env.example lab.env && nano lab.env"
```

Uzupełnij (na wszystkich maszynach te same wartości):

```bash
IFACE=ens33
MASTER_IP=192.168.180.51
WORKER1_IP=192.168.180.52
WORKER2_IP=192.168.180.53
MONITORING_IP=192.168.180.54
#WORKER3_IP=192.168.180.55          # usuń #, jeśli masz trzeciego workera
ADMIN_CIDR=192.168.180.0/24
GRAFANA_ADMIN_PASSWORD=<hasło>
```

Zapisz **Ctrl+O**, Enter, wyjdź **Ctrl+X**. `lab.env` jest w `.gitignore`.

Kontrola: `ssh k3s-master "grep -E '_IP=|ADMIN_CIDR|IFACE' ~/k3s-monitoring-lab/lab.env"`.

### Krok 11. 📸 Snapshot wszystkich maszyn – `przed-prepare`

### Krok 12. Skrypt przygotowania

🪟 Windows, dla każdej maszyny (nazwa **dwa razy** – po `ssh -t` i na końcu):

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"
```

`-t` daje terminal, w którym `sudo` zapyta o hasło. Skrypt: nazwa hosta, `/etc/hosts`,
aktualizacje, swap, **wyłączenie logowania hasłem przez SSH** (tylko gdy jest klucz), firewall.
Opis każdej linii: [docs/skrypty/00-prepare-node.md](skrypty/00-prepare-node.md).

### Krok 13. Sprawdzenie

🪟 Windows:

```powershell
ssh k3s-master "hostname; systemctl is-active ufw; swapon --show; grep k3s-lab /etc/hosts"
ssh -o PubkeyAuthentication=no k3s-master
```

Oczekiwane: nazwa, `active`, brak swapu, wpis każdej maszyny; drugie polecenie –
`Permission denied (publickey)` (hasło przez SSH wyłączone). `ssh k3s-master` kluczem działa dalej.

### Krok 14. 📸 Snapshot wszystkich maszyn – `czysty-system`

---

## Etap 2 – klaster k3s przez Ansible

Ansible nie działa na Windowsie (brak modułu `fcntl`), więc uruchamiasz go z maszyny
`monitoring`. Wariant ze skryptami jest na końcu etapu.

### Krok 15. Ansible na `monitoring`

🐧 `ssh monitoring`:

```bash
sudo apt update && sudo apt install -y pipx
pipx ensurepath
exit
```

🐧 `ssh monitoring` (ponownie – nowy `PATH`):

```bash
pipx install --include-deps ansible
pipx install ansible-lint
ansible --version
```

Pierwszy raz z Ansible? Jak działa i z czego się składa – [docs/teoria-ansible.md](teoria-ansible.md);
czym są pipx, kolekcje i ansible-lint – [docs/06 – Narzędzia](06-ansible.md#narzędzia-pipx-kolekcje-i-ansible-lint).

### Krok 16. Klucz SSH dla Ansible

🐧 monitoring:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ansible -C "ansible@monitoring"   # Enter 2x – bez hasła
exit
```

Logowanie hasłem przez SSH jest już wyłączone, więc klucz rozwozisz z Windowsa.

🪟 Windows, dla `k3s-master`, `k3s-worker-1`, `k3s-worker-2` (i `k3s-worker-3`):

```powershell
ssh monitoring "cat ~/.ssh/ansible.pub" | ssh k3s-master "cat >> ~/.ssh/authorized_keys"
```

oraz dla samego `monitoring`:

```powershell
ssh monitoring "cat ~/.ssh/ansible.pub >> ~/.ssh/authorized_keys"
```

### Krok 17. Test klucza

🐧 monitoring:

```bash
for h in 192.168.180.51 192.168.180.52 192.168.180.53 192.168.180.54; do ssh -i ~/.ssh/ansible -o StrictHostKeyChecking=accept-new <użytkownik>@$h hostname; done
```

Ma wypisać nazwy maszyn bez pytania o hasło. `accept-new` zapisuje klucze hostów w
`~/.ssh/known_hosts` – Ansible sprawdza je przy każdym połączeniu (`host_key_checking = True`).
Jeśli dodajesz `k3s-worker-3`, dopisz `192.168.180.55` do pętli.

Żeby na `monitoring` wystarczyło `ssh k3s-master` (jak na Windowsie), wskaż klucz w `~/.ssh/config`:

```bash
printf 'Host k3s-master k3s-worker-1 k3s-worker-2 k3s-worker-3 monitoring\n    User <użytkownik>\n    IdentityFile ~/.ssh/ansible\n    IdentitiesOnly yes\n' >> ~/.ssh/config
chmod 600 ~/.ssh/config
```

Bez tego `ssh` szuka tylko kluczy o standardowych nazwach (`id_ed25519`) i kończy się
*Connection closed* albo *Permission denied (publickey)*.

### Krok 18. Repozytorium i kolekcje

🐧 monitoring:

```bash
cd ~/k3s-monitoring-lab && git pull && cd ansible
ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force
```

Kolekcja `community.general` (moduły `timezone` i `ufw`) trafia do wspólnego katalogu
`~/.ansible/collections`. pipx trzyma `ansible` i `ansible-lint` w osobnych środowiskach:
pakiet `ansible` ma kolekcje w swoim, a `ansible-lint` widzi tylko wspólny katalog – bez `-p`
lint zgłosi *couldn't resolve module/action 'community.general.timezone'*. `--force` instaluje
kolekcję, nawet jeśli jest już w środowisku `ansible`. Sprawdzenie:

```bash
ansible-galaxy collection list community.general   # ścieżka /home/<użytkownik>/.ansible/collections
```

Jeśli instalacja zawiśnie na zależności (*Skipping ... already installed*), `Ctrl+C` jest
bezpieczne – główna kolekcja jest już zainstalowana.

### Krok 19. Inventory

🐧 monitoring, w `~/k3s-monitoring-lab/ansible`:

```bash
cp inventory.ini.example inventory.ini
nano inventory.ini
```

```ini
[k3s_server]
k3s-master ansible_host=192.168.180.51

[k3s_agents]
k3s-worker-1 ansible_host=192.168.180.52
k3s-worker-2 ansible_host=192.168.180.53
# k3s-worker-3 ansible_host=192.168.180.55

[monitoring_vm]
monitoring ansible_host=192.168.180.54

[k3s_cluster:children]
k3s_server
k3s_agents

[all:vars]
ansible_user=<użytkownik>
ansible_ssh_private_key_file=~/.ssh/ansible
iface=ens33
admin_cidr=192.168.180.0/24
```

`inventory.ini` jest w `.gitignore` – Twoje adresy nie trafią do repozytorium.
Masz trzeciego workera? Usuń `#` przed `k3s-worker-3`.
`admin_cidr` musi być Twoją siecią: tylko z niej firewall wpuści SSH i `kubectl`.
`iface` i `admin_cidr` muszą być w inventory – bez nich playbook przerwie się na brakującej zmiennej.

Sprawdzenie, czy Ansible czyta zmienne (cała wiadomość w cudzysłowie – spacja bez niego
dzieli argumenty):

```bash
ansible all -m debug -a 'msg="{{ admin_cidr }} {{ iface }}"'
```

Każda maszyna: `"msg": "192.168.180.0/24 ens33"`.

### Krok 20. Połączenie i jakość kodu

🐧 monitoring:

```bash
ansible all -m ping                       # każda maszyna: "ping": "pong"
ansible-lint site.yml playbooks roles     # kontrola playbooków i ról
```

`ping` w Ansible to nie ICMP: łączy się przez SSH kluczem, uruchamia Pythona na maszynie
i odsyła `pong`. Lint powinien skończyć się `Passed: 0 failure(s), 0 warning(s)`;
ostrzeżenie *Directory expansion discovered ... file(s)* to tylko informacja.

### Krok 21. Próba na sucho

🐧 monitoring:

```bash
ansible-playbook playbooks/prepare.yml --check --diff --ask-become-pass
```

`--check` niczego nie zmienia, `--diff` pokazuje różnice, `--ask-become-pass` pyta raz o hasło
`sudo`. Po Etapie 1 powinno być głównie `ok`.

Na pytanie `BECOME password:` wpisz hasło użytkownika do `sudo` (nic się nie wyświetla).
SSH działa kluczem, ale `sudo` nadal wymaga hasła.

Jak czytać wynik:

| Wynik | Znaczenie |
|---|---|
| `ok` | już jest dobrze, Ansible nic nie zmienia |
| `changed` | Ansible zmieniłby to (w `--check` tylko pokazuje); `--diff` wypisuje różnice w plikach |
| `skipping` | zadanie nie dotyczy tej maszyny (np. porty 3000/3001 tylko na `monitoring`) |
| `failed` / `unreachable` | błąd – patrz *Najczęstsze problemy* |

Po Etapie 1 typowe `changed` to blok w `/etc/hosts` (zastępuje wpisy ze skryptu) i reguły ufw
(Ansible dodaje je z komentarzem; ufw nie tworzy duplikatów). Ważne jest `failed=0`
i `unreachable=0` w `PLAY RECAP`.

> Ubuntu 25.10 i nowsze mają domyślnie **sudo-rs** (`sudo --version` pokazuje `sudo-rs`).
> Ansible nie rozpoznaje jego pytania o hasło, dlatego `ansible.cfg` ustawia
> `become_exe = sudo.ws` – klasyczne sudo, instalowane obok. Ty nadal używasz zwykłego `sudo`.

### Krok 22. Instalacja klastra

🐧 monitoring:

```bash
ansible-playbook site.yml --ask-become-pass
```

Kolejno: przygotowanie maszyn (rola `common`), k3s na masterze i odczyt tokenu
(`k3s_server`), k3s na workerach z tokenem przekazanym automatycznie (`k3s_agent`), czekanie na
`Ready`, rola `worker`. Na końcu lista węzłów i `PLAY RECAP` (`ok` / `changed` / `failed`).

### Krok 23. Sprawdzenie

🪟 Windows:

```powershell
ssh -t k3s-master "sudo k3s kubectl get nodes -o wide"
```

Wszystkie węzły klastra w stanie `Ready`.

### Krok 24. 📸 Snapshot wszystkich maszyn – `k3s-dziala`

### Krok 25 (opcjonalny). Hasło sudo w Ansible Vault

Żeby uruchamiać playbooki bez `--ask-become-pass`, zapisz hasło sudo w pliku zaszyfrowanym
Ansible Vault – instrukcja krok po kroku: [docs/09-ansible-vault.md](09-ansible-vault.md).

### Wariant: Etap 2 skryptami (bez Ansible)

🪟 Windows:

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/01-install-master.sh"
```

Skopiuj wyświetlony token i wpisz go jako `K3S_TOKEN=` w `lab.env` na każdym workerze, potem:

```powershell
ssh -t k3s-worker-1 "cd ~/k3s-monitoring-lab && sudo ./scripts/02-install-worker.sh 192.168.180.52"
ssh -t k3s-worker-2 "cd ~/k3s-monitoring-lab && sudo ./scripts/02-install-worker.sh 192.168.180.53"
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/03-post-install.sh"
```

Szczegóły: [docs/02-instalacja-k3s.md](02-instalacja-k3s.md).

---

## Dalej

- Etap 3 – monitoring w klastrze: [docs/03-monitoring.md](03-monitoring.md)
- Etap 4 – monitoring poza klastrem: [docs/04-monitoring-zewnetrzny.md](04-monitoring-zewnetrzny.md)
- Etap 5 – scenariusze awarii: [docs/05-scenariusze-awarii.md](05-scenariusze-awarii.md)

## Najczęstsze problemy

Szerszy opis każdego problemu – przyczyna, diagnoza i wnioski:
[docs/08-problemy-administratora.md](08-problemy-administratora.md).

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| maszyna nie ma internetu po ustawieniu IP | adres z innej sieci niż VMnet8 albo zła brama | krok 1 – sieć i brama `.2` z VMnet8 |
| brama `.2` niedostępna, kilka klonów | ten sam MAC na kilku maszynach | krok 3 – **Generate** MAC |
| po restarcie wraca stary adres / nazwa | cloud-init nadpisuje sieć i nazwę albo zostały stare pliki Netplan | krok 4.2 i 4.4 |
| `cat /etc/machine-id` na klonie nic nie wyświetla | ID nie zostało wygenerowane | `sudo systemd-machine-id-setup` |
| `hostnamectl set-hostname $NAME`: *Too few arguments* | zmienna `NAME` pusta (nowa sesja albo spacje wokół `=`) | ustaw `NAME=...` ponownie |
| prompt pokazuje starą nazwę po `hostnamectl` | prompt czyta nazwę przy logowaniu | wyloguj się i zaloguj; sprawdź `hostnamectl` |
| `ssh k3s-...` pyta o hasło | polecenie wpisane na Linuksie, nie w PowerShell | `exit`, potem z Windowsa |
| `sudo: cannot execute ...: Permission denied` | skrypt bez prawa wykonywania | `git pull` (skrypty mają tryb `100755`) |
| test bez klucza pokazuje `(publickey,password)` po skrypcie | stara wersja skryptu (`99-lab.conf` przegrywa z `50-cloud-init.conf`) | `git pull` i ponownie krok 12 |
| `packer build` pokazuje tylko `Usage:` | PowerShell rozbija `-var-file=plik.hcl` na kropce | argumenty w cudzysłowie: `"-var-file=plik.hcl"` |
| `ansible` na Windowsie: `No module named 'fcntl'` | Ansible działa tylko na Linuksie | uruchamiaj z `monitoring` (krok 15) |
| `ansible all -m debug -a "msg={{ a }} {{ b }}"`: *must resolve to a 'dict' not 'str'* | spacja dzieli argumenty na części | całą wiadomość w cudzysłowie: `-a 'msg="{{ a }} {{ b }}"'` |
| `ssh`: *This host key is known by the following other names/addresses* | klony mają wspólny klucz hosta (pominięty `ssh-keygen -A` w kroku 4) | nowe klucze, `ssh-keygen -R`, porównanie odcisków – docs/08 |
| `ssh k3s-master` na `monitoring`: *Connection closed* / *Permission denied (publickey)* | `ssh` nie zna klucza `~/.ssh/ansible` | `ssh -i ~/.ssh/ansible ...` albo `~/.ssh/config` na monitoring (krok 17) |
| Ansible: *Host key verification failed* | klucz maszyny zmienił się (np. nowe klucze, odtworzona maszyna) | sprawdź odcisk, `ssh-keygen -R <adres>`, połącz się ponownie |
| `ansible-playbook`: *Timeout (12s) waiting for privilege escalation prompt* | sudo-rs w Ubuntu 25.10+ | `git pull` (`ansible.cfg` ma `become_exe = sudo.ws`) |
