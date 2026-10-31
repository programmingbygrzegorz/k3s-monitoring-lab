# `00-prepare-node.sh` – co robi każda część

Skrypt przygotowuje świeżą maszynę z Ubuntu Server do roli w laboratorium: nadaje nazwę,
wpisuje sąsiadów do `/etc/hosts`, aktualizuje system, wyłącza swap, zamyka logowanie hasłem
przez SSH i konfiguruje firewall. Uruchamiasz go raz na każdej maszynie, przed instalacją k3s.

```bash
sudo ./scripts/00-prepare-node.sh k3s-master      # na k3s-master
sudo ./scripts/00-prepare-node.sh k3s-worker-1    # na k3s-worker-1 itd.
```

Albo z własnego komputera, bez logowania się na maszynę:

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"
```

`-t` otwiera terminal, w którym `sudo` może zapytać o hasło.

Skrypt jest **idempotentny**: można go uruchomić ponownie (np. po zmianie adresów w `lab.env`
albo po dodaniu maszyny) – za każdym razem doprowadza maszynę do tego samego stanu, bez
dublowania wpisów.

---

## Cała procedura z konsoli (PowerShell na Windowsie)

Wszystkie polecenia wydajesz z **PowerShell na swoim komputerze** (znak zachęty `PS C:\...>`),
nie na maszynie Linux. Zakładają klucz SSH i plik `~/.ssh/config` z nazwami maszyn
([maszyny wirtualne](../etap-0-maszyny-wirtualne/01-maszyny-wirtualne.md), *Klucz SSH zamiast hasła*). Przykłady są dla `k3s-master` – na pozostałych maszynach
zmieniasz tylko nazwę.

### 0. Maszyny włączone i osiągalne

Włącz maszyny w VMware i sprawdź, czy odpowiadają (bez pytania o hasło):

```powershell
ssh k3s-master hostname
ssh k3s-worker-1 hostname
ssh k3s-worker-2 hostname
ssh monitoring hostname
```

Przy okazji sprawdź nazwę karty i adres – nazwa musi zgadzać się z `IFACE` w `lab.env`:

```powershell
ssh k3s-master "ip -4 -o addr show"
```

### 1. Repozytorium na maszynie

Jeśli repozytorium jeszcze nie ma:

```powershell
ssh k3s-master "git clone https://github.com/<twoj-login>/k3s-monitoring-lab.git ~/k3s-monitoring-lab"
```

Jeśli już jest – pobierz najnowszą wersję:

```powershell
ssh k3s-master "cd ~/k3s-monitoring-lab && git pull"
```

### 2. `lab.env` na maszynie

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && cp -n lab.env.example lab.env && nano lab.env"
```

W edytorze uzupełnij adresy wszystkich maszyn, `ADMIN_CIDR`, `IFACE` i `GRAFANA_ADMIN_PASSWORD`
(na wszystkich maszynach te same wartości), zapisz **Ctrl+O**, Enter, wyjdź **Ctrl+X**.
`cp -n` nie nadpisze istniejącego `lab.env`.

Kontrola:

```powershell
ssh k3s-master "cd ~/k3s-monitoring-lab && grep -E '_IP=|ADMIN_CIDR|IFACE' lab.env"
```

> Wygodnie: uzupełnij `lab.env` raz, na jednej maszynie, a potem skopiuj go na pozostałe
> (`scp k3s-master:k3s-monitoring-lab/lab.env .` i `scp lab.env k3s-worker-1:k3s-monitoring-lab/`).
> Usuń potem lokalną kopię – zawiera hasło Grafany.

### 3. Snapshot w VMware

Prawy klik na maszynie → **Snapshot → Take Snapshot**, np. `przed-prepare`.

### 4. Uruchomienie skryptu

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"
```

Nazwa maszyny występuje **dwa razy**: po `ssh -t` (z którą maszyną się łączysz) i na końcu
(jaką nazwę skrypt ustawi). Muszą być takie same. `sudo` zapyta o hasło użytkownika na maszynie.

Wszystkie maszyny po kolei jednym poleceniem (hasło `sudo` podajesz raz dla każdej maszyny):

```powershell
ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"; ssh -t k3s-worker-1 "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-worker-1"; ssh -t k3s-worker-2 "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-worker-2"; ssh -t monitoring "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh monitoring"
```

### 5. Sprawdzenie

```powershell
ssh k3s-master "hostname; systemctl is-active ufw; swapon --show; grep k3s-lab /etc/hosts; ping -c1 k3s-worker-1"
ssh -o PubkeyAuthentication=no k3s-master
```

| Co sprawdzasz | Oczekiwany wynik |
|---|---|
| `hostname` | nazwa maszyny |
| `systemctl is-active ufw` | `active` |
| `swapon --show` | pusto |
| `grep k3s-lab /etc/hosts` | po jednym wpisie na każdą maszynę |
| `ping -c1 k3s-worker-1` | `1 received` |
| `ssh -o PubkeyAuthentication=no` | od razu `Permission denied (publickey)` – hasło przez SSH wyłączone |

Zwykłe `ssh k3s-master` (kluczem) musi dalej działać.

### Najczęstsze błędy

| Komunikat | Przyczyna | Rozwiązanie |
|---|---|---|
| `Permission denied (os error 13)` przy `sudo ./scripts/...` | skrypt bez prawa wykonywania (np. dodany do gita z Windowsa) | `git pull` (w repozytorium skrypty mają tryb `100755`) albo `sudo bash ./scripts/00-prepare-node.sh ...` |
| `Brak pliku lab.env` | nie wykonano kroku 2 | `cp lab.env.example lab.env` i uzupełnij |
| `MASTER_IP: parameter null or not set` | pusta wartość w `lab.env` | uzupełnij brakującą zmienną |
| `ssh k3s-...` pyta o hasło | polecenie wpisane **na maszynie Linux**, a nie w PowerShell | `exit`, potem polecenie w PowerShell |
| po skrypcie `Permission denied (publickey,password)` przy teście bez klucza | starsza wersja skryptu zapisywała `99-lab.conf`, który przegrywa z `50-cloud-init.conf` | `git pull` i uruchom skrypt ponownie |

---

## 1. Nagłówek i bezpieczny tryb pracy (linie 1–9)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
```

| Element | Co robi |
|---|---|
| `#!/usr/bin/env bash` | plik wykonuje Bash (wymaga prawa wykonywania `chmod +x` – w gicie tryb `100755`) |
| `set -e` | przerwij przy pierwszym poleceniu zakończonym błędem – skrypt nie brnie dalej w połowie zepsutej konfiguracji |
| `set -u` | użycie niezdefiniowanej zmiennej to błąd – literówka w nazwie zmiennej nie przejdzie po cichu |
| `set -o pipefail` | błąd w dowolnym elemencie potoku `a \| b` jest błędem całego potoku |
| `source lib.sh` | wczytuje wspólne funkcje i plik `lab.env` (opis niżej) |
| `require_root` | kończy skrypt, jeśli nie uruchomiono go przez `sudo` – prawie każdy krok zmienia pliki systemowe |

### Co robi `lib.sh`

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/lab.env"
[[ -f "${ENV_FILE}" ]] || { echo "Brak pliku lab.env ..."; exit 1; }
source "${ENV_FILE}"
```

- Ustala katalog repozytorium niezależnie od tego, skąd uruchomiono skrypt.
- Wczytuje `lab.env` – od tej chwili `MASTER_IP`, `WORKER1_IP`, `ADMIN_CIDR` itd. są zmiennymi
  w skrypcie. Bez `lab.env` skrypt kończy się od razu i **niczego nie zmienia**.
- Definiuje `log` (kolorowy nagłówek `==> ...` w wyjściu) i `require_root`.

---

## 2. Parametr: nazwa maszyny (linia 11)

```bash
NEW_HOSTNAME="${1:?Podaj nazwę hosta, np. k3s-master}"
```

Pierwszy argument wywołania to nazwa maszyny. Konstrukcja `${1:?komunikat}` przerywa skrypt
z tym komunikatem, jeśli argumentu brakuje. Od nazwy zależy też dalej zestaw reguł firewalla
(`monitoring` dostaje inne niż węzły k3s).

---

## 3. Nazwa hosta (linie 13–14)

```bash
hostnamectl set-hostname "${NEW_HOSTNAME}"
```

Zapisuje nazwę w `/etc/hostname` i ustawia ją od razu, bez restartu. k3s rejestruje węzeł
w klastrze pod tą nazwą – dwie maszyny o tej samej nazwie (np. dwa klony `ubuntu-template`)
nadpisywałyby się nawzajem.

Znak zachęty w już otwartej sesji (`user@stara-nazwa`) zmieni się dopiero po ponownym zalogowaniu.

---

## 4. `/etc/hosts` – maszyny widzą się po nazwie (linie 16–27)

```bash
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
```

**Krok 1 – sprzątanie.** `sed` usuwa z `/etc/hosts` każdą linię, w której występuje nazwa
maszyny labu jako osobne słowo – niezależnie od tego, czy dopisał ją wcześniej ten skrypt, czy
ktoś ręcznie:

| Fragment wyrażenia | Znaczenie |
|---|---|
| `/^127\./!{ ... }` | wykonaj to, co w nawiasie, tylko dla linii, które **nie** zaczynają się od `127.` – `127.0.0.1 localhost` i `127.0.1.1 <własna-nazwa>` zostają |
| `(k3s-master\|k3s-worker-[0-9]+\|monitoring)` | nazwy maszyn labu, także przyszłe `k3s-worker-4`, `-5` … |
| `[[:space:]]` … `([[:space:]]\|$)` | nazwa musi być całym słowem – `monitoring-old` czy `nas.local` nie zostaną usunięte |
| `d` | usuń pasującą linię |

**Krok 2 – dopisanie.** Aktualne adresy z `lab.env` trafiają na koniec pliku, każda linia
z dopiskiem `# k3s-lab`. `:?` przy zmiennej przerywa skrypt, jeśli w `lab.env` brakuje adresu.
Trzeci worker jest dopisywany tylko wtedy, gdy `WORKER3_IP` jest ustawione.

**Dlaczego tak:** `lab.env` jest jedynym źródłem adresów. Zmiana adresu albo nowa maszyna =
poprawka w `lab.env` i ponowne uruchomienie skryptu na wszystkich maszynach; stare linie nie
zostają, więc nie ma duplikatów ani nieaktualnych adresów.

Wynik na przykładzie `k3s-master`:

```
127.0.0.1 localhost
127.0.1.1 k3s-master

192.168.1.51 k3s-master # k3s-lab
192.168.1.52 k3s-worker-1 # k3s-lab
192.168.1.53 k3s-worker-2 # k3s-lab
192.168.1.54 monitoring # k3s-lab
```

---

## 5. Aktualizacja systemu i narzędzia (linie 29–34)

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl ca-certificates gettext-base jq ufw
timedatectl set-timezone Europe/Warsaw
```

| Polecenie | Co robi |
|---|---|
| `DEBIAN_FRONTEND=noninteractive` | apt nie zadaje pytań (np. o pliki konfiguracyjne) – skrypt nie zawiesi się w oczekiwaniu na odpowiedź |
| `apt-get update` | pobiera aktualne listy pakietów |
| `apt-get upgrade` | instaluje aktualizacje – **najdłuższy krok**, wymaga internetu |
| `apt-get install` | narzędzia używane w kolejnych skryptach (tabela niżej) |
| `timedatectl set-timezone` | strefa czasowa – czas w logach i na wykresach Grafany zgadza się z Twoim zegarkiem |

| Pakiet | Do czego |
|---|---|
| `curl` | pobranie instalatora k3s (`01`, `02`), zapytania HTTP w testach |
| `ca-certificates` | zaufane certyfikaty – `curl` może łączyć się po HTTPS |
| `gettext-base` | polecenie `envsubst` – wstawia zmienne z `lab.env` do plików YAML (`04`) |
| `jq` | odczyt JSON-a z `kubectl` w skryptach i przy diagnozie |
| `ufw` | firewall konfigurowany w kroku 8 |

---

## 6. Swap wyłączony (linie 36–38)

```bash
swapoff -a
sed -i.bak '/\sswap\s/ s/^#*/#/' /etc/fstab
```

- `swapoff -a` wyłącza swap od razu.
- `sed` zakomentowuje (`#`) linie swapu w `/etc/fstab`, żeby nie wrócił po restarcie.
  `-i.bak` zostawia kopię pliku jako `/etc/fstab.bak`.

**Dlaczego:** Kubernetes planuje pody na podstawie dostępnej pamięci RAM. Gdy system przenosi
pamięć na dysk, limity pamięci i alerty (np. OOMKilled z [Etapu 5](../etap-5-scenariusze-awarii/01-scenariusze-awarii.md)) przestają zachowywać się
przewidywalnie; kubelet domyślnie nie startuje przy włączonym swapie.

Sprawdzenie: `swapon --show` nic nie wypisuje.

---

## 7. SSH tylko kluczem (linie 40–53)

```bash
ADMIN_USER="${SUDO_USER:-root}"
AUTHORIZED_KEYS="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)/.ssh/authorized_keys"
if [[ -s "${AUTHORIZED_KEYS}" ]]; then
  rm -f /etc/ssh/sshd_config.d/99-lab.conf
  echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/01-lab.conf
  systemctl reload ssh
else
  log "UWAGA: ... logowanie hasłem zostaje włączone"
fi
```

| Krok | Co robi |
|---|---|
| `SUDO_USER` | nazwa użytkownika, który uruchomił `sudo` (np. `grzegorz`) |
| `getent passwd … \| cut -d: -f6` | jego katalog domowy, np. `/home/grzegorz` |
| `[[ -s authorized_keys ]]` | czy plik z kluczami istnieje i **nie jest pusty** |
| `01-lab.conf` | wyłącza logowanie hasłem przez SSH |
| `rm -f 99-lab.conf` | usuwa plik ze starszej wersji skryptu (nie działał – patrz niżej) |
| `systemctl reload ssh` | sshd wczytuje nowe ustawienia; **otwarte połączenia nie są zrywane** |

**Zabezpieczenie przed odcięciem się:** jeśli użytkownik nie ma jeszcze klucza, skrypt tylko
ostrzega i zostawia hasło. Wyłączenie hasła bez klucza oznaczałoby, że przez SSH nie wejdzie
nikt – została by tylko konsola VMware.

**Dlaczego plik nazywa się `01-lab.conf`:** sshd czyta pliki z `sshd_config.d/` alfabetycznie
i dla każdej opcji używa **pierwszej znalezionej wartości**. Ubuntu instaluje
`50-cloud-init.conf` z `PasswordAuthentication yes`. Plik `99-…` byłby czytany później i jego
ustawienie zostałoby zignorowane; `01-…` jest czytany wcześniej, więc wygrywa.

Po tym kroku:
- `ssh <maszyna>` z kluczem działa jak wcześniej,
- `sudo` i logowanie w konsoli VMware nadal wymagają hasła,
- próba bez klucza kończy się od razu `Permission denied (publickey)`.

Sprawdzenie z Windowsa:

```powershell
ssh -o PubkeyAuthentication=no k3s-master
```

---

## 8. Firewall – część wspólna (linie 55–64)

```bash
if [[ "${ENABLE_UFW:-yes}" != "yes" ]]; then exit 0; fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from "${ADMIN_CIDR:?}" to any port 22 proto tcp comment 'SSH z sieci administratora'
```

| Polecenie | Co robi |
|---|---|
| `ENABLE_UFW=no` w `lab.env` | pomija cały firewall (np. przy diagnozie problemów z siecią) |
| `ufw --force reset` | usuwa wszystkie dotychczasowe reguły (kopie zapasowe w `/etc/ufw/*.rules.<data>`) – dzięki temu ponowne uruchomienie nie dubluje reguł |
| `default deny incoming` | **cały** ruch przychodzący jest blokowany, chyba że reguła niżej go wpuszcza |
| `default allow outgoing` | maszyna może łączyć się na zewnątrz (aktualizacje, obrazy kontenerów) |
| `allow … port 22 from ADMIN_CIDR` | SSH tylko z Twojej sieci administratora |

Reguła SSH jest dodawana **przed** włączeniem firewalla, więc połączenie, z którego uruchomiono
skrypt, nie zostanie zerwane.

---

## 9. Firewall – reguły zależne od roli (linie 66–83)

### Maszyna `monitoring`

```bash
ufw allow from "${ADMIN_CIDR}" to any port 3000 proto tcp comment 'Grafana'
ufw allow from "${ADMIN_CIDR}" to any port 3001 proto tcp comment 'Uptime Kuma'
```

Poza SSH tylko interfejsy WWW Grafany i Uptime Kuma, i tylko z Twojej sieci. Maszyna monitoring
sama łączy się z klastrem (ruch wychodzący), więc nie potrzebuje innych reguł przychodzących.

### Węzły k3s (master i workery)

| Reguła | Port / źródło | Po co |
|---|---|---|
| `allow from <IP każdego węzła>` | wszystko, z adresów węzłów | komunikacja wewnątrz klastra: API (6443), kubelet (10250), sieć Flannel VXLAN (8472/udp), metryki node-exportera |
| `allow from 10.42.0.0/16` | sieć podów k3s | ruch od podów, np. Prometheus pobierający metryki |
| `allow from 10.43.0.0/16` | sieć usług k3s | ruch kierowany przez usługi (ClusterIP) |
| `allow … port 6443 from ADMIN_CIDR` | API Kubernetesa | `kubectl` i `k9s` z Twojego komputera |
| `allow 80,443/tcp` | HTTP/HTTPS z dowolnego adresu | Ingress (Traefik) – aplikacja demo pod nazwą domenową |
| `allow … 30000:32767 from ADMIN_CIDR` | NodePorty | Grafana, Prometheus i Alertmanager z klastra w przeglądarce |
| `allow … 30000:32767 from MONITORING_IP` | NodePorty | zewnętrzna Grafana i Uptime Kuma odpytują klaster |

Pętla po adresach węzłów dodaje `WORKER3_IP` tylko wtedy, gdy jest ustawione
(`${WORKER3_IP:+"${WORKER3_IP}"}` rozwija się do niczego, gdy zmienna jest pusta).

---

## 10. Włączenie firewalla i podsumowanie (linie 85–88)

```bash
ufw --force enable
ufw status verbose
log "Gotowe. Węzeł ${NEW_HOSTNAME} jest przygotowany."
```

`--force` pomija pytanie „Command may disrupt existing ssh connections”. Firewall startuje też
automatycznie po każdym restarcie. Na końcu skrypt wypisuje aktywne reguły – warto je przejrzeć.

---

## Jak sprawdzić wynik na wszystkich maszynach

```powershell
ssh k3s-master "hostname; systemctl is-active ufw; swapon --show; grep k3s-lab /etc/hosts; cat /etc/ssh/sshd_config.d/01-lab.conf"
ssh -o PubkeyAuthentication=no k3s-master
```

Oczekiwane: nazwa maszyny, `active`, pusty wynik `swapon`, wpisy wszystkich maszyn,
`PasswordAuthentication no`; drugie polecenie – `Permission denied (publickey)`.

## Czego skrypt nie robi

- nie ustawia adresu IP ani Netplanu (maszyna musi mieć już sieć – [Etap 0](../etap-0-maszyny-wirtualne/README.md)),
- nie instaluje k3s (`01-install-master.sh`, `02-install-worker.sh`),
- nie restartuje maszyny.
