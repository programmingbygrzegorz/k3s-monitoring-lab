# Przewodnik krok po kroku – od pustego VMware do klastra k3s

Ten plik prowadzi przez całą budowę laboratorium **w kolejności**, z każdym poleceniem do
wpisania. Przy każdym kroku jest napisane **gdzie** go wykonać:

| Oznaczenie | Gdzie | Jak rozpoznać |
|---|---|---|
| 🪟 **Windows** | PowerShell na Twoim komputerze | znak zachęty `PS C:\...>` |
| 🖥️ **konsola VMware** | okno maszyny w VMware (logowanie hasłem) | `login:` / `user@nazwa:~$` |
| 🐧 **maszyna** | terminal Linuxa przez SSH (`ssh <nazwa>` z Windowsa) | `user@nazwa:~$` |

Szczegóły i wyjaśnienia są w plikach `docs/01`–`09`; tutaj jest sama ścieżka.

## Mapa etapów

| Etap | Co powstaje | Kroki | Szczegóły |
|---|---|---|---|
| [Etap 0 – sieć i maszyny wirtualne](#etap-0--sieć-i-maszyny-wirtualne) | sieć NAT, szablon Ubuntu, klony ze stałymi adresami | 1–4 | [docs/01](01-maszyny-wirtualne.md), [Packer](07-packer.md) |
| [Etap 0b – dostęp przez klucz SSH](#etap-0b--dostęp-przez-klucz-ssh) | logowanie z Windowsa kluczem, po nazwie | 5–8 | [klucze SSH](teoria-ssh-klucze.md) |
| [Etap 1 – przygotowanie systemu](#etap-1--przygotowanie-systemu) | `/etc/hosts`, aktualizacje, swap wyłączony, SSH tylko kluczem, firewall | 9–14 | [00-prepare-node.sh](skrypty/00-prepare-node.md) |
| [Etap 2 – klaster k3s przez Ansible](#etap-2--klaster-k3s-przez-ansible) | Ansible na `monitoring`, k3s: master + workery, opcjonalnie Vault | 15–25 | [docs/06](06-ansible.md), [teoria Ansible](teoria-ansible.md), [Vault](09-ansible-vault.md), [docs/02](02-instalacja-k3s.md) (skrypty) |
| Ćwiczenia z kubectl (między etapami 2 i 3) | 8 poziomów: pody, skalowanie, Service, aktualizacje, drain, YAML | – | [docs/10](10-cwiczenia-kubectl.md) |
| [Etap 3 – monitoring w klastrze](#etap-3--monitoring-w-klastrze) | Prometheus, Alertmanager, Grafana, aplikacja demo, Helm | 26–32 | [docs/03](03-monitoring.md), [plik values](03a-values-monitoringu.md), [teoria Kubernetes i Helm](teoria-kubernetes-helm.md), [teoria monitoringu](teoria-monitoring.md) |
| Ćwiczenia z monitoringu (po Etapie 3) | 8 poziomów: Target health, PromQL, wykresy, reguły, dashboardy, alert i wyciszenie, własny wykres | – | [docs/11](11-cwiczenia-monitoring.md), [wykonanie ze zrzutami](11a-cwiczenia-monitoring-wykonanie.md) |
| Etap 4 – monitoring poza klastrem | Grafana i Uptime Kuma na `monitoring`, healthchecks.io | – | [docs/04](04-monitoring-zewnetrzny.md) |
| Etap 5 – scenariusze awarii | awarie węzłów i aplikacji, diagnoza w terminalu | – | [docs/05](05-scenariusze-awarii.md) |
| Etap 6 – zarządzanie przez GUI *(planowany)* | Headlamp (klaster k3s), Portainer (tylko Docker na `monitoring`), Semaphore UI (Ansible) | – | – |
| Etap 7 – CI/CD i GitOps *(planowany)* | GitLab CE na maszynie `gitlab`, GitLab Runner, własny obraz Docker, skan Trivy w pipeline, Argo CD w k3s | – | [plan poniżej](#etapy-6-i-7--plan) |
| Etap 8 – AIOps *(planowany)* | Hermes Agent (Nous Research) jako asystent administratora: diagnoza po alercie, bez zmian bez zgody | – | [plan poniżej](#etap-8--plan) |
| Etap 9 – bezpieczeństwo klastra *(planowany)* | kube-bench (audyt CIS), Falco (wykrywanie w kontenerach, alerty do Alertmanagera), Kyverno (polityki) | – | [plan poniżej](#etap-9--plan) |
| Etap 9b – Wazuh *(planowany, opcjonalny)* | SIEM na maszynie `security`, agenty na wszystkich maszynach: logi, integralność plików, podatności | – | [plan poniżej](#etap-9--plan) |
| Etap 9c – ataki kontrolowane *(planowany, opcjonalny)* | maszyna `kali`: ataki na własny lab i sprawdzenie, czy obrona je wykrywa (purple teaming) | – | [plan poniżej](#etap-9--plan) |

Etapy 3–5 są na razie opisane w osobnych plikach; kroki w tym przewodniku zostaną dopisane po
ich przejściu. Problemy z każdego etapu: [Najczęstsze problemy](#najczęstsze-problemy) i
[docs/08](08-problemy-administratora.md).

### Etapy 6 i 7 – plan

**Etap 6 – zarządzanie przez GUI** (po awariach – najpierw diagnoza w terminalu, potem panele):

| Narzędzie | Gdzie | Do czego | Nie dubluje |
|---|---|---|---|
| Headlamp | klaster k3s | obiekty klastra: pody, logi, skalowanie, YAML, zdarzenia | Grafany – ta pokazuje metryki w czasie |
| Portainer | **tylko** `monitoring`, środowisko *Docker (local)* | kontenery Grafany, Uptime Kumy, Semaphore | Headlampa – bez środowiska Kubernetes i bez agenta w klastrze |
| Semaphore UI | `monitoring` (Docker) | uruchamianie playbooków Ansible z GUI, historia, harmonogram | – |

Na koniec etapu: powtórka 2–3 scenariuszy awarii w Headlampie, naprawa playbookiem z Semaphore
i porównanie „terminal czy GUI”. Każde z tych narzędzi ma szerokie uprawnienia (token klastra,
gniazdo Dockera, klucz SSH i hasło sudo), więc dostęp tylko z `admin_cidr`, osobne konta, RBAC.

**Etap 7 – CI/CD i GitOps** (wszystko we własnym labie, GitHub zostaje portfolio):

```
gitlab (GitLab CE) ── repo z kodem + Dockerfile ── CI (.gitlab-ci.yml) ── GitLab Runner
        │                                              │ buduje obraz → rejestr GitLaba
        │                                              │ zmienia tag obrazu w repo z YAML
        └── repo z manifestami Kubernetes ◀─────────────┘
                     │
                     ▼ pobiera i wyrównuje stan
           Argo CD w k3s → wdraża nową wersję
```

1. maszyna `gitlab` z Packera, instalacja GitLab CE rolą Ansible,
2. GitLab Runner (na `monitoring` albo jako pod w k3s),
3. prosta aplikacja z `Dockerfile` i `.gitlab-ci.yml`,
4. **Trivy w pipeline** – skan zbudowanego obrazu i manifestów YAML; podatność `CRITICAL` zatrzymuje
   pipeline, więc obraz nie trafia do rejestru ani na klaster (*shift left* – bezpieczeństwo
   sprawdzane przy budowie, a nie na produkcji),
5. Argo CD przejmuje `kubernetes/demo-app/` (zamiast `05-deploy-demo.sh`) i nowe wersje aplikacji,
6. GitLab wysyła repozytorium na GitHub (*push mirror*) – portfolio zostaje aktualne.

### Etap 8 – plan

**AIOps – asystent AI administratora** z [Hermes Agent](https://github.com/NousResearch/hermes-agent)
(open source, Nous Research), uruchomionym we własnym labie.

```
Alertmanager ── alert (webhook) ──▶ Hermes Agent ── tylko odczyt ──▶ kubectl describe / events / logs
                                         │                         Prometheus (zapytania PromQL)
                                         ▼
                              podsumowanie: co się stało, prawdopodobna przyczyna, propozycja naprawy
                                         │
                                         ▼  zmiana tylko po Twojej akceptacji
                              playbook w Semaphore / commit w GitLabie (Argo CD wdraża)
```

Zasady, bez których agent AI w infrastrukturze jest ryzykiem:

- **Najmniejsze uprawnienia:** osobny ServiceAccount z RBAC tylko do odczytu, bez dostępu do
  sekretów, bez klucza SSH z uprawnieniami sudo.
- **Człowiek zatwierdza zmiany:** agent proponuje, a zmiana idzie istniejącą ścieżką
  (Semaphore, commit + Argo CD) – z historią i możliwością wycofania.
- **Dane:** świadomy wybór modelu – zewnętrzne API (logi i konfiguracja wychodzą z labu) albo
  model lokalny (osobna maszyna, dużo RAM).
- **Ślad:** każde polecenie agenta w logach.

Test na koniec: scenariusze awarii z Etapu 5 – czy agent trafnie wskazuje przyczynę
(np. `ImagePullBackOff`, `OOMKilled`) i czy jego propozycja naprawy jest poprawna.

### Etap 9 – plan

**Bezpieczeństwo** – w trzech częściach, od lekkich narzędzi w klastrze do ataków na własny lab.
Kolejność ma znaczenie: ataki (9c) mają sens dopiero wtedy, gdy obrona już stoi.

| Narzędzie | Rola | Porównanie | Gdzie |
|---|---|---|---|
| **Trivy** *(Etap 7)* | czy to, co **wdrażam**, ma znane podatności – przed uruchomieniem | przegląd techniczny przed wyjazdem | pipeline GitLab CI |
| **kube-bench** | czy klaster jest skonfigurowany według norm CIS | audyt | jednorazowy Job w k3s |
| **Falco** | czy w kontenerach dzieje się coś podejrzanego – na bieżąco (np. shell w podzie) | czujnik ruchu w pomieszczeniu | DaemonSet w k3s, alerty do Alertmanagera |
| **Kyverno** | zasady, których nie da się złamać (np. pod bez limitów pamięci nie wejdzie do klastra) | regulamin przy wejściu | kontroler w k3s |
| **Wazuh** | czy ktoś próbuje się włamać na **maszyny** albo coś podejrzanie się zmieniło | ochrona budynku z kamerami | serwer na `security`, agenty na wszystkich maszynach |
| **Kali** | atakujący – sprawdza, czy powyższe naprawdę działa | ćwiczenia ewakuacyjne | maszyna `kali` |

Prometheus i Grafana z Etapu 3 odpowiadają na pytanie „czy działa i jak wydajnie” – narzędzia
bezpieczeństwa na pytanie „czy ktoś robi coś, czego nie powinien”.

**Etap 9 – bezpieczeństwo klastra** (w k3s, bez nowych maszyn):

1. kube-bench – raport CIS, poprawki (np. uprawnienia `644` kubeconfigu z
   [docs/08](08-problemy-administratora.md#kubectl-działa-a-helm-nie-widzi-klastra)), raport po poprawkach,
2. Falco – reguły wykrywania, alerty do Alertmanagera (połączenie z Etapem 3),
3. Kyverno – 2–3 polityki: wymagane limity zasobów, zakaz obrazu `:latest`, zakaz kontenerów
   uprzywilejowanych.

**Etap 9b – Wazuh** (opcjonalny, maszyna `security`):

- analiza logów (np. zgadywanie haseł SSH) i automatyczne blokowanie adresu,
- integralność plików: `/etc/ssh/sshd_config`, `/etc/sudoers`, `/etc/rancher/k3s/`,
- podatności pakietów Ubuntu na każdej maszynie,
- audyt konfiguracji maszyn według CIS (wynik w procentach przed i po poprawkach).

**Etap 9c – ataki kontrolowane z Kali** (opcjonalny, maszyna `kali`):

| Atak | Czym | Co powinno wykryć |
|---|---|---|
| skanowanie portów labu | `nmap` | Wazuh (logi firewalla ufw) |
| zgadywanie haseł SSH | `hydra` | Wazuh – reguła brute force, blokada adresu |
| skan podatności aplikacji podinfo | `nikto`, `nuclei` | logi Traefika, Wazuh |
| shell w podzie, odczyt Secretów wykradzionym kubeconfigiem | `kubectl exec` | Falco → Alertmanager |
| zmiana pliku systemowego po „włamaniu” | ręcznie | Wazuh – integralność plików |
| przeciążenie aplikacji | `hey`, `ab` | Prometheus i Grafana, alert |

Każdy scenariusz kończy się pytaniem **„wykryto czy nie?”**. Jeśli nie – poprawka wykrywania,
powtórka i wpis do dokumentacji.

Zasady ataków:
- celem są **wyłącznie maszyny labu** (`192.168.180.51–58`) – nigdy router, inne urządzenia
  w domu ani adresy w internecie,
- przed każdą serią: 📸 snapshot, zapisany cel i oczekiwany wynik,
- dokumentacja opisuje przede wszystkim wykrywanie i obronę.

### Zasoby komputera – profile maszyn

Lab rośnie z każdym etapem. Komputer, na którym powstaje (64 GB RAM, Intel i7-14700KF – 28
wątków, SSD NVMe 2 TB), pomieści wszystkie maszyny naraz (~46 GB dla maszyn + ~8–10 GB dla
Windowsa), ale bez dużego zapasu. Dlatego włączaj tylko maszyny potrzebne w danym etapie:

| Profil | Włączone maszyny | RAM maszyn |
|---|---|---|
| Etapy 2–6 (klaster i monitoring) | master, 3 workery, monitoring | 26 GB |
| Etap 7 (CI/CD) | powyższe + gitlab | 34 GB |
| Etap 9b–9c (bezpieczeństwo) | klaster, monitoring, security, kali – **gitlab wyłączony** | 38 GB |
| wszystko naraz (np. pokaz) | wszystkie | ~46 GB |

Narzędzia w klastrze (Argo CD, Falco, Kyverno, Headlamp) potrzebują łącznie ~1–2 GB na
istniejących workerach, a Trivy to program uruchamiany na chwilę – bez nowych maszyn.

Gdy brakuje pamięci: worker-3 do 4 GB albo wyłączony (k3s działa na 2 workerach), Wazuh
z mniejszą pamięcią indexera (~6 GB), Kali bez pulpitu (2–3 GB).

## Plan laboratorium

| Maszyna | Rola | vCPU | RAM (MB) | Dysk | Adres IP (przykład) |
|---|---|---|---|---|---|
| ubuntu-template | szablon do klonowania (wyłączony) | 2 | 4096 | 40 GB | – |
| k3s-master | węzeł sterujący k3s | 2 | 4096 | 40 GB | 192.168.180.51 |
| k3s-worker-1 | węzeł roboczy | 2 | 6144 | 40 GB | 192.168.180.52 |
| k3s-worker-2 | węzeł roboczy | 2 | 6144 | 40 GB | 192.168.180.53 |
| monitoring | monitoring zewnętrzny, węzeł sterujący Ansible | 2 | 4096 | 40 GB | 192.168.180.54 |
| k3s-worker-3 | węzeł roboczy (opcjonalny) | 2 | 6144 | 40 GB | 192.168.180.55 |
| gitlab | GitLab CE: repozytoria, CI/CD, rejestr obrazów *(Etap 7)* | 4 | 8192 | 60 GB | 192.168.180.56 |
| security | Wazuh: serwer, indexer, dashboard *(Etap 9b, opcjonalny)* | 4 | 8192 | 80 GB | 192.168.180.57 |
| kali | Kali Linux – ataki kontrolowane na lab *(Etap 9c, opcjonalny)* | 2 | 4096 | 60 GB | 192.168.180.58 |

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

## Etap 3 – monitoring w klastrze

Prometheus, Alertmanager i Grafana z chartu Helm **kube-prometheus-stack** oraz aplikacja demo
z własnymi alertami. Wszystkie polecenia na `k3s-master`. Każde polecenie z objaśnieniem
i wynikami z labu: [docs/03-monitoring.md](03-monitoring.md#instalacja-ręczna-krok-po-kroku).
Pojęcia: [teoria Kubernetes i Helm](teoria-kubernetes-helm.md), plik values linia po linii:
[docs/03a](03a-values-monitoringu.md).

| Krok | Co robisz |
|---|---|
| 26 | `git pull`, `kubectl top nodes` – zasoby workerów przed instalacją |
| 27 | Helm: pobranie archiwum, sprawdzenie sumy SHA-256, `install` do `/usr/local/bin` |
| 28 | `~/.kube/config` dla Helma (`install -m 600 /etc/rancher/k3s/k3s.yaml ~/.kube/config`), `helm list -A` |
| 29 | `helm repo add`, `helm search repo`, podgląd: `helm show values`, `helm template` |
| 30 | 📸 snapshot, `lab.env` → `envsubst` → `helm upgrade --install … --version 92.16.1 --wait` |
| 31 | `kubectl apply` aplikacji demo i reguł alertów |
| 32 | Grafana `:30300`, Prometheus `:30090` (Targets), Alertmanager `:30093`, podinfo `:30898`; 📸 snapshot |

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
| `helm`: *cluster unreachable … localhost:8080* | Helm szuka `~/.kube/config`, a k3s trzyma kubeconfig w `/etc/rancher/k3s/k3s.yaml` | krok 28 – `install -m 600 /etc/rancher/k3s/k3s.yaml ~/.kube/config` |
| `kubectl top nodes`: *Metrics API not available* | metrics-server zbiera pierwsze pomiary po starcie maszyn | odczekaj 1–2 minuty |
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
