# Etap 4 – przebieg wdrożenia krok po kroku (05.11.2026)

Zapis prawdziwej sesji: od przywrócenia maszyny `monitoring` i resetu rejestru, przez Dockera
i rejestr z TLS zbudowane od zera, po monitoring poza klastrem. Każdy krok ma polecenia, wyjaśnienie
i **wynik z labu** – tak jak wyszło, łącznie z rzeczami, które poszły inaczej niż w planie.

Różnica wobec [ćwiczeń](03-cwiczenia-obraz.md): ćwiczenia mówią, *co* zrobić; ten plik pokazuje,
*jak to wyglądało naprawdę* i dlaczego podjąłem takie decyzje. Dobry materiał do opowiedzenia
na rozmowie („przebudowałem rejestr obrazów, nie tracąc obrazu używanego przez klaster”).

Oznaczenia: 🪟 Windows (VMware, terminal), 🐧 maszyna w labie.

## Plan sesji (ok. 2 h)

| Krok | Co | Stan |
|---|---|---|
| 1 | Przywrócenie snapshotu `monitoring` i sprawdzenie | ✅ |
| 2 | Aktualne repozytorium, kopia obrazu `app`, snapshoty | ✅ |
| 3 | Pełny reset rejestru, Dockera i CA | ✅ |
| 4 | Docker od zera (poziomy 0, 1, 3, 5 ćwiczeń) | ✅ |
| 5 | Rejestr z TLS i `app` z powrotem (poziom 6) | ✅ |
| 6 | k3s ufa rejestrowi, pody działają (poziom 7) | ✅ |
| 7a | healthchecks.io – dead man's switch | ✅ (helm rewizja 3) |
| 7b | Grafana, Uptime Kuma | 🟡 postawione; przerwane awarią hosta |
| 7c | Reguła 6443 w roli Ansible (krok 9) | ✅ 06.11, `changed=0` |
| 7d | Reszta monitorów, dashboard, test awarii | następna sesja |

Poziomy 2, 4 i 8 ćwiczeń (rozgrzewka i wycofanie wersji) celowo pominięte, żeby zmieścić się w czasie –
do zrobienia osobno.

---

## Stan wyjściowy

Przed sesją na `monitoring` było:

- rejestr `registry:3` z TLS na `192.168.180.54:5000` i Docker – postawione 03.11 przez Claude
  przy robieniu zrzutów do ćwiczeń; cel sesji: **zbudować je samemu**,
- w rejestrze dwa obrazy: `hello-lab:1.0` (z ćwiczeń) i **`app:1.0.0` – mój obraz z kursu
  Kubernetesa**, używany przez pod `default/app` w k3s,
- resztki po [ćwiczeniach z nginx i baz danych](../etap-1-przygotowanie-systemu/04-cwiczenia-nginx-bazy.md)
  z Etapu 1: działające nginx, PostgreSQL, MariaDB, wolumin `/data` i tymczasowy plik
  `/etc/sudoers.d/99-claude-tymczasowe` (sudo bez hasła – do usunięcia koniecznie).

Jak sprawdziłem, kto korzysta z obrazów w rejestrze, zanim cokolwiek skasowałem – opis metody
w [rozwiązaniach, sekcja „Najpierw: czy w rejestrze są Twoje inne obrazy?”](04-cwiczenia-obraz-rozwiazania.md#najpierw-czy-w-rejestrze-są-twoje-inne-obrazy).

**Decyzja:** zamiast sprzątać resztki ręcznie – przywrócić snapshot `przed-cwiczeniami-linux` maszyny
`monitoring` (z 04.11). Jest **późniejszy** niż obraz `app` (03.11), więc rejestr z `app` przetrwa,
a znikną nginx, bazy i plik sudo.

## Krok 1 – przywrócenie snapshotu `monitoring`

🪟 VMware Workstation:

1. **VM → Snapshot → Take Snapshot…** → `przed-revertem` – droga powrotu do stanu sprzed przywrócenia.
2. **VM → Snapshot → Snapshot Manager** → `przed-cwiczeniami-linux` → **Go To** → **Yes**.
3. Jeśli maszyna po przywróceniu jest wyłączona – **Power on**.

Przywracać można „na gorąco”, bez wyłączania maszyny. Snapshot zrobiony z pamięcią RAM wraca od razu
do działania; zrobiony przy wyłączonej maszynie – wraca wyłączony.

Sprawdzenie 🐧 monitoring:

```text
grzegorz@monitoring:~$ ls /etc/sudoers.d/
README
grzegorz@monitoring:~$ systemctl is-active nginx postgresql mariadb
inactive
inactive
inactive
grzegorz@monitoring:~$ docker ps --format "{{.Names}} {{.Image}} {{.Status}}"
rejestr registry:3 Up 43 hours
grzegorz@monitoring:~$ docker images | grep app
192.168.180.54:5000/app:1.0.0       159255640ed6        199MB         49.6MB
grzegorz@monitoring:~$ timedatectl | grep -E "Local time|synchronized"
               Local time: Thu 2026-11-05 13:45:28 CET
System clock synchronized: no
```

| Polecenie | Co sprawdza | Wynik |
|---|---|---|
| `ls /etc/sudoers.d/` | pliki z uprawnieniami sudo | ✅ tylko `README` – sudo bez hasła zniknęło |
| `systemctl is-active …` | czy działają usługi z ćwiczeń | ✅ wszystkie `inactive` |
| `docker ps --format …` | działające kontenery; `{{.Names}}` itd. to szablon wybierający kolumny | ✅ rejestr działa („Up 43 hours” – czas liczony razem z okresem zapisanym w snapshocie) |
| `docker images \| grep app` | czy obraz `app` jest lokalnie | ✅ jest, 199 MB |
| `timedatectl \| grep -E …` | data i synchronizacja zegara | ⚠️ data dobra, ale `synchronized: no` |

**Zegar po przywróceniu snapshotu.** Maszyna wróciła z pamięcią z 04.11 i przez chwilę „żyła w przeszłości”;
usługa synchronizacji czasu jeszcze nie złapała serwera. Do sprawdzenia przed wystawianiem certyfikatu
(krok 5) – certyfikat z datą z przeszłości lub przyszłości to klasyczna przyczyna błędów TLS.

## Krok 2 – aktualne repozytorium, kopia `app`, snapshoty

🐧 monitoring – snapshot cofnął też repozytorium, więc najpierw nowa wersja instrukcji:

```bash
cd ~/k3s-monitoring-lab && git pull --ff-only
```

Kopia obrazu `app` do pliku – reset usuwa wolumin rejestru (`docker volume rm rejestr-dane`)
i lokalne obrazy (`docker image prune -a -f`), czyli **obie** kopie:

```bash
docker save 192.168.180.54:5000/app:1.0.0 -o ~/kopia-app-1.0.0.tar
ls -lh ~/kopia-app-1.0.0.tar
```

🪟 VMware: snapshot `przed-etapem-4` pięciu maszyn – `monitoring`, `k3s-master`, `k3s-worker-1..3`
(reset zmienia pliki na węzłach k3s i je restartuje).

Wynik z labu:

```text
grzegorz@monitoring:~/k3s-monitoring-lab$ ls -lh ~/kopia-app-1.0.0.tar
-rw------- 1 grzegorz grzegorz 48M Nov  5 13:46 /home/grzegorz/kopia-app-1.0.0.tar
```

**Dlaczego 48 MB, a nie 199 MB?** `docker images` w Dockerze 29 pokazuje dwie liczby:
`199MB` to miejsce na dysku po **rozpakowaniu** warstw, a `49.6MB` to rozmiar **skompresowanych**
warstw – tak, jak przechowuje je rejestr. `docker save` zapisuje warstwy skompresowane, więc plik
ma ok. 48 MB i to jest poprawna, pełna kopia. Zawartość archiwum można podejrzeć bez rozpakowywania:

```bash
tar -tf ~/kopia-app-1.0.0.tar | head
```

(`tar -t` – wypisz zawartość, `-f` – z tego pliku). Widać `index.json`, `manifest.json` i katalog
`blobs/sha256/…` z warstwami – format OCI, ten sam, którego używa rejestr.

`-rw-------` – plik czyta tylko właściciel; `docker save` tworzy go z ostrożnymi uprawnieniami.

### Niespodzianka: master nie odpowiadał na ping

Po zrobieniu snapshotów `ssh k3s-master` z Windowsa nie działał, a `ping 192.168.180.51` nie dostawał
odpowiedzi, choć w VMware maszyna była włączona. Kilka minut później Ansible z `monitoring` łączył się
z masterem bez problemu. Wyjaśnienie widać w wyniku restartu z kroku 3.2: k3s na masterze miał
`ActiveEnterTimestampMonotonic: 15180728` – licznik od startu systemu w mikrosekundach, czyli usługa
wystartowała **15 sekund po uruchomieniu maszyny** (13:57). Master właśnie się uruchamiał od nowa,
a w trakcie startu systemu sieć jeszcze nie odpowiada.

Lekcja: „włączona w VMware” ≠ „gotowa”. Przed szukaniem awarii sieci warto odczekać minutę
i sprawdzić konsolę maszyny (ekran logowania = system wstał).

## Krok 3 – Pełny reset

### 3.2. Węzły k3s przestają ufać rejestrowi (🐧 monitoring, Ansible)

```bash
cd ~/k3s-monitoring-lab/ansible
ansible k3s_cluster -b -m file -a "path=/etc/rancher/k3s/registries.yaml state=absent"
ansible k3s_cluster -b -m file -a "path=/etc/rancher/k3s/lab-ca.crt state=absent"
ansible k3s_server -b -m systemd -a "name=k3s state=restarted"
ansible k3s_agents -b -f 1 -m systemd -a "name=k3s-agent state=restarted"
```

| Część | Znaczenie |
|---|---|
| `ansible GRUPA` | polecenie ad-hoc (bez playbooka) na grupie maszyn z `inventory.ini`: `k3s_cluster` = master + 3 workery, `k3s_server` = master, `k3s_agents` = workery |
| `-b` | *become* – przez sudo (pliki w `/etc`, restart usług) |
| `-m file -a "path=… state=absent"` | moduł `file`: plik ma **nie istnieć** – jest, to usuń; nie ma, nic nie rób |
| `-m systemd -a "name=… state=restarted"` | moduł `systemd`: zrestartuj usługę (master: `k3s`, workery: `k3s-agent`) |
| `-f 1` | *forks* – po jednej maszynie naraz, żeby zawsze 2 z 3 workerów działały (*rolling restart*) |

Restart jest potrzebny, bo k3s czyta `registries.yaml` tylko przy starcie.

Wynik z labu (skrócony – moduł `systemd` wypisuje ok. 300 linii stanu usługi):

```text
k3s-master   | CHANGED => { "changed": true, "path": "/etc/rancher/k3s/registries.yaml", "state": "absent" }
k3s-worker-3 | CHANGED => { ... registries.yaml ... }
k3s-worker-2 | CHANGED => { ... }
k3s-worker-1 | CHANGED => { ... }

k3s-worker-3 | CHANGED => { "changed": true, "path": "/etc/rancher/k3s/lab-ca.crt", "state": "absent" }
...                                         (4 × CHANGED)

# to samo polecenie drugi raz:
k3s-worker-2 | SUCCESS => { "changed": false, "path": "/etc/rancher/k3s/lab-ca.crt", "state": "absent" }
...                                         (4 × SUCCESS)

k3s-master   | CHANGED => { "name": "k3s", "state": "started", "status": { "ActiveState": "active", ... } }
k3s-worker-1 | CHANGED => { "name": "k3s-agent", "state": "started", ... }
k3s-worker-2 | CHANGED => { ... }
k3s-worker-3 | CHANGED => { ... }
```

**Idempotencja na żywo.** Polecenie z `lab-ca.crt` uruchomione przypadkiem drugi raz dało
`SUCCESS` i `"changed": false` – pliku już nie było, więc Ansible niczego nie zrobił. To właśnie
idempotencja: to samo polecenie można powtarzać bez szkody, a wynik mówi, czy coś się zmieniło
(`CHANGED`, żółty) czy stan już był dobry (`SUCCESS`/`ok`, zielony).

**Jak czytać wynik modułu `systemd`.** Pole `status` to stan usługi **sprzed** restartu (dlatego na
workerach widać daty z 03.11 – wtedy ostatnio startowały). Najważniejsze: `"changed": true` i brak
`FAILED`. Gdyby trzeba było sprawdzić usługę po restarcie: `ansible k3s_agents -b -a "systemctl is-active k3s-agent"`.

### 3.1. hello-lab znika z klastra (🐧 k3s-master)

```bash
kubectl delete namespace hello-lab
kubectl get pods -n default        # pod app przeżył restart k3s – nadal Running
```

### 3.3. Rejestr, certyfikaty i obrazy (🐧 monitoring)

```bash
docker rm -f hello rejestr                          # kontenery (-f zatrzymuje działający)
docker volume rm rejestr-dane                       # obrazy z rejestru – od teraz app jest tylko w kopii .tar
sudo rm -rf /etc/docker/certs.d/192.168.180.54:5000 # zaufanie Dockera do starego CA
rm -rf ~/rejestr-certs ~/hello-lab ~/strona         # CA labu, certyfikaty, pliki z ćwiczeń
docker image prune -a -f                            # wszystkie nieużywane obrazy
docker ps -a; docker images; docker volume ls       # trzy puste listy
```

### 3.4. Sam Docker (🐧 monitoring)

```bash
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-model-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd     # purge NIE usuwa danych – celowo
sudo rm /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc   # repozytorium apt i klucz
sudo groupdel docker                                # grupa = uprawnienia roota; dodam się świadomie w poziomie 0
exit                                                # grupy wczytują się przy logowaniu
```

Po ponownym `ssh monitoring`: `docker --version` → `command not found`, w `id` brak grupy `docker`,
kopia `~/kopia-app-1.0.0.tar` na miejscu. **Reset zakończony.**

`apt purge` a `apt remove`: `remove` usuwa program i zostawia pliki konfiguracyjne, `purge` usuwa też
konfigurację. Żaden nie rusza danych w `/var/lib/docker` – obrazy i wolumeny trzeba skasować ręcznie,
jeśli naprawdę chcemy zacząć od zera.

## Krok 4 – Docker od zera

### Poziom 0 – instalacja (🐧 monitoring)

```bash
curl -fsSL https://get.docker.com | sudo sh   # oficjalny skrypt: repozytorium apt + pakiety
sudo usermod -aG docker $USER                 # -a = DOPISZ do grupy (bez -a tracisz pozostałe grupy, w tym sudo!)
exit                                          # nowe logowanie = nowa lista grup
id                                            # na liście: docker
docker version                                # sekcje Client i Server – działa bez sudo
```

`curl … | sudo sh` uruchamia cudzy skrypt jako root bez czytania. W firmie: `curl -fsSL https://get.docker.com -o get-docker.sh`,
`less get-docker.sh`, dopiero potem `sudo sh get-docker.sh`.

### Poziom 1 – pierwszy kontener

`docker run hello-world`, `nginx:alpine` z `-p 8081:80`, `docker ps -a`, `docker rm -f web` – obraz
zostaje po usunięciu kontenera (obraz = szablon, kontener = uruchomiona kopia).

### Poziom 3 – obraz hello-lab:1.0

```bash
mkdir -p ~/hello-lab && cd ~/hello-lab
cp ~/k3s-monitoring-lab/apps/hello-lab/app.py .
nano Dockerfile                    # FROM python:3.14-slim, ARG/ENV APP_VERSION, WORKDIR, COPY, EXPOSE, CMD
docker build --build-arg APP_VERSION=1.0 -t hello-lab:1.0 .
docker run -d --name hello -p 8080:8080 hello-lab:1.0
curl localhost:8080/api
docker exec hello whoami           # root – poprawione w poziomie 5
```

**Pierwsza próba się nie udała:** `"/app.py": not found` przy `COPY app.py .` i `transferring context: 2B`.
Budowanie poszło z katalogu domowego (`~`), a nie z `~/hello-lab` – po ponownym zalogowaniu terminal
zaczyna w `~`. Opis: [problemy – docker build: "/app.py": not found](problemy.md#docker-build-apppy-not-found).
Po `cd ~/hello-lab` (Dockerfile i `app.py` w jednym katalogu) budowanie przeszło.

**Kto czyta Dockerfile?** Tylko `docker build` – szuka pliku `Dockerfile` w katalogu kontekstu (kropka)
i zapisuje wynik jako obraz `hello-lab:1.0`. `docker run hello-lab:1.0` bierze **gotowy obraz** po nazwie
(a gdy go nie ma lokalnie – pobiera z rejestru); Dockerfile nie jest mu potrzebny. Dlatego obraz da się
zbudować na `monitoring`, a uruchomić na workerze k3s.

### Poziom 5 – obraz bez roota, z HEALTHCHECK

```bash
cd ~/hello-lab
cp ~/k3s-monitoring-lab/apps/hello-lab/Dockerfile .   # wersja końcowa: useradd, USER 10001, HEALTHCHECK
docker rm -f hello
docker build --build-arg APP_VERSION=1.0 -t hello-lab:1.0 .
docker run -d --name hello -p 8080:8080 hello-lab:1.0
docker ps                                            # (health: starting) → (healthy)
docker exec hello id                                 # uid=10001(app) gid=10001(app)
```

Porównanie pobierania `python:3.14` (ok. 1,6 GB) z `-slim` i `-alpine` pominięte – wniosek znany
z teorii, a pobieranie zjadłoby czas. Jak oglądać obraz: `docker images`, `docker history`,
`docker inspect --format '{{.Config.User}}'` (puste = root, po poziomie 5 – `10001`),
`docker run --rm hello-lab:1.0 ls -la /app`.

**uid, gid, groups** (wynik `id`): uid – numer użytkownika, gid – numer grupy głównej, groups – wszystkie
grupy. Jądro rozpoznaje użytkowników **po numerach**; kontener dzieli jądro z maszyną, więc root w kontenerze
(`uid=0`) to dla jądra root. Dlatego aplikacja działa jako `uid=10001` – numer, którego nie ma nikt na `monitoring`.

## Krok 5 – rejestr z TLS (poziom 6)

### 6.1. Rejestr bez TLS – błąd celowo

```bash
docker run -d --name rejestr -p 5000:5000 registry:3          # oficjalny obraz CNCF Distribution, wersja 3
docker tag hello-lab:1.0 192.168.180.54:5000/hello-lab:1.0     # druga nazwa obrazu = adres rejestru
docker push 192.168.180.54:5000/hello-lab:1.0                  # http: server gave HTTP response to HTTPS client
docker rm -f rejestr                                           # usuń pokazowy rejestr (bez wolumenu – nic nie tracimy)
```

`registry:3` nie ma GUI – tylko API (`/v2/_catalog`, `/v2/NAZWA/tags/list`). GUI daje np. Joxit Registry UI,
Harbor albo rejestr GitLaba (Etap 7).

### 6.2. CA labu i certyfikat rejestru

```bash
mkdir -p ~/rejestr-certs && cd ~/rejestr-certs
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout ca.key -out ca.crt -subj "/CN=k3s-lab CA"
openssl req -newkey rsa:2048 -nodes -keyout registry.key -out registry.csr -subj "/CN=192.168.180.54"
printf "subjectAltName=IP:192.168.180.54,DNS:monitoring\n" > san.ext
openssl x509 -req -in registry.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out registry.crt -days 825 -sha256 -extfile san.ext
chmod 600 ca.key registry.key
```

Wynik z labu:

```text
Certificate request self-signature ok
subject=CN=192.168.180.54

$ openssl x509 -in registry.crt -noout -subject -issuer -ext subjectAltName -dates
subject=CN=192.168.180.54
issuer=CN=k3s-lab CA
X509v3 Subject Alternative Name:
    IP Address:192.168.180.54, DNS:monitoring
notBefore=Nov  5 14:22:29 2026 GMT
notAfter=Feb  7 14:22:29 2029 GMT

$ ls -l
-rw-rw-r-- 1 grzegorz grzegorz 1809 Nov  5 15:19 ca.crt
-rw------- 1 grzegorz grzegorz 3272 Nov  5 15:19 ca.key
-rw-rw-r-- 1 grzegorz grzegorz   41 Nov  5 15:22 ca.srl
-rw-rw-r-- 1 grzegorz grzegorz 1484 Nov  5 15:22 registry.crt
-rw-rw-r-- 1 grzegorz grzegorz  899 Nov  5 15:21 registry.csr
-rw------- 1 grzegorz grzegorz 1704 Nov  5 15:22 registry.key
-rw-rw-r-- 1 grzegorz grzegorz   48 Nov  5 15:22 san.ext
```

Jak czytać: `subject` – dla kogo (adres rejestru), `issuer` – kto podpisał (nasze CA), SAN – adresy, dla
których certyfikat jest ważny, `notBefore`/`notAfter` – ważność (825 dni). Daty są w **GMT**: 14:22 GMT
to 15:22 czasu polskiego – zgadza się z `ls -l`, więc zegar maszyny jest dobry. Klucze prywatne mają
`-rw-------` (tylko właściciel), certyfikaty mogą być czytane przez wszystkich – są publiczne z założenia.
`ca.srl` – numer seryjny ostatnio wystawionego certyfikatu; `registry.csr` i `san.ext` są już niepotrzebne.

### 6.3. Rejestr z TLS – tylko dwa pliki w kontenerze

Pierwsza wersja podpinała cały katalog: `-v ~/rejestr-certs:/certs:ro`. Wtedy `docker exec rejestr ls -l /certs`
pokazuje **7 plików**, w tym `ca.key` – pieczątkę CA. Rejestr nie ma logowania; gdyby ktoś go przejął, mógłby
przeczytać `ca.key` i wystawić „ważny” certyfikat dla dowolnego adresu, a Docker i k3s by mu uwierzyły.
Poprawka – zasada najmniejszych uprawnień: podpinamy **pojedyncze pliki**, nie katalog.

```bash
docker rm -f rejestr          # usuwa kontener; wolumen rejestr-dane (obrazy) zostaje
docker run -d --name rejestr --restart always -p 5000:5000 \
  -v rejestr-dane:/var/lib/registry \
  -v ~/rejestr-certs/registry.crt:/certs/registry.crt:ro \
  -v ~/rejestr-certs/registry.key:/certs/registry.key:ro \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
  registry:3
```

Wynik z labu:

```text
$ docker exec rejestr ls -l /certs
total 8
-rw-rw-r--    1 1000     1000          1484 Nov  5 14:22 registry.crt
-rw-------    1 1000     1000          1704 Nov  5 14:21 registry.key

$ curl https://192.168.180.54:5000/v2/
curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)

$ curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/
{}
```

Jak czytać:

- W kontenerze właściciel plików to `1000` – numer, nie nazwa. W Alpine w kontenerze nie ma użytkownika
  `grzegorz`, a jądro i tak zna tylko uid (zob. poziom 5).
- Kod 60 bez `--cacert` to **dobry** wynik: TLS działa, a curl nie zna naszego CA (nie ma go w systemowych CA Ubuntu).
- `{}` z `--cacert` – rejestr odpowiada na API `/v2/`, certyfikat pasuje do adresu `192.168.180.54` (SAN).

Co jest w kontenerze `rejestr`:

| Skąd | Co |
|---|---|
| obraz `registry:3` | `/bin/registry` (program), `/etc/distribution/config.yml` (domyślna konfiguracja), mały Alpine pod spodem |
| `-v` plik | `/certs/registry.crt`, `/certs/registry.key` (tylko do odczytu) |
| `-v` wolumen | `/var/lib/registry` – warstwy i manifesty obrazów, przetrwa `docker rm` |
| `-e` | `REGISTRY_HTTP_TLS_*` – nadpisują `config.yml` i włączają HTTPS |

Gdzie który klucz leży (diagramy): [06-certyfikaty-gdzie-jaki-klucz.md](06-certyfikaty-gdzie-jaki-klucz.md).

Sprawdzenie: `docker exec rejestr env`, `docker exec rejestr cat /etc/distribution/config.yml`,
`docker inspect rejestr --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'`.

> **Pytanie rekrutacyjne:** *Kontener potrzebuje certyfikatu TLS. Podpinasz cały katalog z certyfikatami czy
> pojedyncze pliki? Dlaczego?* – Pojedyncze pliki (albo Secret w Kubernetesie z samym certyfikatem i kluczem).
> Kontener dostaje tylko to, czego potrzebuje; klucz CA w kontenerze oznacza, że przejęcie jednej usługi
> pozwala podrobić certyfikat dowolnej innej.

### 6.4. Docker ufa rejestrowi, obrazy wracają

```bash
sudo mkdir -p /etc/docker/certs.d/192.168.180.54:5000                       # katalog = adres:port rejestru
sudo cp ~/rejestr-certs/ca.crt /etc/docker/certs.d/192.168.180.54:5000/ca.crt  # tylko wzór pieczątki
docker push 192.168.180.54:5000/hello-lab:1.0
docker load -i ~/kopia-app-1.0.0.tar                                         # obraz app z kopii z kroku 2
docker push 192.168.180.54:5000/app:1.0.0
curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/_catalog
```

Restart Dockera nie jest potrzebny – Docker czyta `certs.d` przy każdym połączeniu.

Wynik z labu:

```text
$ sudo ls -l /etc/docker/certs.d/192.168.180.54:5000/
-rw-r--r-- 1 root root 1809 Nov  5 15:32 ca.crt

$ docker push 192.168.180.54:5000/hello-lab:1.0       # drugi raz
fea618ac8a9a: Layer already exists
...
1.0: digest: sha256:f0d8d9721afcece15164a4490c3638b35a1fd99b89832f471b1620c56dca6ae1 size: 856

$ docker images
IMAGE                                ID             DISK USAGE   CONTENT SIZE   EXTRA
192.168.180.54:5000/hello-lab:1.0    f0d8d9721afc        178MB         43.6MB    U
hello-lab:1.0                        f0d8d9721afc        178MB         43.6MB    U
registry:3                           d4032d4cc323       86.9MB         20.7MB    U

$ docker push 192.168.180.54:5000/app:1.0.0
824416e23423: Pushed
5ed3089f43a6: Pushed
44136fa355b3: Mounted from hello-lab
78fcc2df4797: Pushed
...
1.0.0: digest: sha256:159255640ed6dda8a696f215b3e648d43035ef3e73bbaac7a091ae716eb1138a size: 856

$ curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/_catalog
{"repositories":["app","hello-lab"]}
```

Jak czytać:

- `ca.crt` w `certs.d` ma 1809 bajtów – tyle samo co w `~/rejestr-certs`. Klucza `ca.key` tam nie ma i być nie może.
- **`Layer already exists`** – Docker pyta rejestr o każdą warstwę po skrócie `sha256`; rejestr ją ma, więc nic
  nie leci przez sieć. Ten sam digest = ten sam obraz. Drugi push tej samej wersji trwa ułamek sekundy.
- **`Pushed`** – warstwy `app` trafiły do nowego rejestru pierwszy raz.
- **`Mounted from hello-lab`** – tę warstwę rejestr już miał w repozytorium `hello-lab` (wspólna warstwa
  bazowa obu obrazów). Rejestr tylko ją podlinkował, bez wysyłania drugi raz. Warstwy są przechowywane według
  skrótu, a nie według obrazu.
- **Ten sam ID** `f0d8d9721afc` dla dwóch nazw `hello-lab` – jeden obraz, dwie etykiety (`docker tag`).
- **DISK USAGE** to obraz rozpakowany na dysku, **CONTENT SIZE** to skompresowane warstwy (tyle leci przez sieć).
  Stąd kopia `app` miała 48M, a obraz 199MB. `U` w kolumnie EXTRA – obrazu używa kontener.

> **Pytanie rekrutacyjne:** *Dlaczego drugi `docker push` tego samego obrazu trwa sekundę, a przy pushu
> drugiego obrazu część warstw ma „Mounted from”?* – Rejestr przechowuje warstwy według skrótu treści
> (content-addressable). Klient najpierw pyta, czy warstwa o danym `sha256` istnieje; jeśli tak, nie wysyła jej.
> Wspólne warstwy (np. obraz bazowy) są w rejestrze tylko raz, niezależnie od liczby obrazów.

## Krok 6 – k3s ufa rejestrowi (poziom 7)

### 7.1. Wdrożenie bez zaufania – błąd celowo (🐧 k3s-master)

```bash
cd ~/k3s-monitoring-lab && git pull
kubectl apply -f kubernetes/hello-lab/hello-lab.yaml
kubectl -n hello-lab get pods -o wide
kubectl -n hello-lab get events --sort-by=.lastTimestamp | grep -iE "pull|x509|present"
```

Wynik z labu – **niespodzianka: jeden pod działa, drugi nie**:

```text
NAME                         READY   STATUS             NODE
hello-lab-57dd97cd57-jhckb   1/1     Running            k3s-worker-3
hello-lab-57dd97cd57-rwzzd   0/1     ImagePullBackOff   k3s-worker-2

pod/…-jhckb   Container image "192.168.180.54:5000/hello-lab:1.0" already present on machine and can be accessed by the pod
pod/…-rwzzd   Pulling image "192.168.180.54:5000/hello-lab:1.0"
pod/…-rwzzd   Failed to pull image "192.168.180.54:5000/hello-lab:1.0": failed to pull and unpack image …:
              failed to resolve reference …: failed to do request:
              Head "https://192.168.180.54:5000/v2/hello-lab/manifests/1.0":
              tls: failed to verify certificate: x509: certificate signed by unknown authority
pod/…-rwzzd   Error: ErrImagePull  →  Error: ImagePullBackOff  →  Back-off pulling image
```

Dlaczego tak:

- Manifest nie ustawia `imagePullPolicy`, więc dla tagu innego niż `latest` obowiązuje **`IfNotPresent`** –
  pobieraj tylko, gdy węzła nie ma obrazu.
- **worker-3** miał `hello-lab:1.0` w containerd z ćwiczeń 03.11. Pełny reset usunął zaufanie węzłów
  i namespace, ale **nie obrazy z cache węzłów**. Worker-3 nie łączył się z rejestrem wcale.
- **worker-2** obrazu nie miał, więc containerd zapytał rejestr o manifest (`HEAD /v2/hello-lab/manifests/1.0`
  – to samo API, które pytaliśmy curlem) i nie rozpoznał CA → x509.
- `ErrImagePull` → `ImagePullBackOff` – k3s ponawia próbę coraz rzadziej (10 s, 20 s, 40 s… do 5 min).
- Pod na worker-3 działa najpewniej na **starym** obrazie o tym samym tagu. Tag to tylko etykieta – stąd
  w firmach przypinanie obrazu po digest (`image: …@sha256:…`) i zasada „nigdy nie używaj tagu drugi raz”.
- `tail -5` w tym miejscu ucięło linię `already present` – przy kilku podach lepszy jest `grep` po słowach.

> **Pytanie rekrutacyjne:** *Dwa pody tego samego Deploymentu: jeden `Running`, drugi `ImagePullBackOff`.
> Co sprawdzasz?* – Na których węzłach są (`-o wide`) i zdarzenia (`get events`/`describe pod`).
> Typowo: jeden węzeł ma obraz w cache (`already present`, `IfNotPresent`), drugi musi pobrać i nie może
> (x509, brak dostępu do rejestru, brak `imagePullSecrets`, zła nazwa). Działający pod nie dowodzi, że
> rejestr jest osiągalny.

### 7.2. Zaufanie na węzłach przez Ansible (🐧 monitoring)

```bash
cd ~/k3s-monitoring-lab/ansible
ansible k3s_cluster -b -m file -a "path=/etc/rancher/k3s state=directory mode=0755"
ansible k3s_cluster -b -m copy -a "src=$HOME/rejestr-certs/ca.crt dest=/etc/rancher/k3s/lab-ca.crt mode=0644"
ansible k3s_cluster -b -m copy -a "src=$HOME/k3s-monitoring-lab/apps/hello-lab/k3s-registries.yaml dest=/etc/rancher/k3s/registries.yaml mode=0644"
ansible k3s_server -b -m systemd -a "name=k3s state=restarted"
ansible k3s_agents -b -f 1 -m systemd -a "name=k3s-agent state=restarted"
```

Potem na masterze `kubectl -n hello-lab rollout restart deploy/hello-lab` – i **trzy pody**:

```text
NAME                         READY   STATUS             NODE
hello-lab-55b8fb57c9-fqs7f   0/1     ImagePullBackOff   k3s-worker-2    ← nowy ReplicaSet
hello-lab-57dd97cd57-jhckb   1/1     Running            k3s-worker-3    ← stary, zostaje
hello-lab-57dd97cd57-rwzzd   0/1     ImagePullBackOff   k3s-worker-2    ← stary
```

`rollout restart` tworzy nowy ReplicaSet (inny hash w nazwie). Przy 2 replikach `maxSurge` = 1, a
`maxUnavailable` = 0 (25% z 2 zaokrąglone w dół), więc Deployment dodaje jeden nowy pod i **czeka, aż będzie
Ready**, zanim usunie stary. Nowy nie wstaje, więc wymiana stoi, a działający pod dalej obsługuje ruch –
RollingUpdate chroni przed złym wdrożeniem.

Nowy błąd w `describe pod`:

```text
failed to resolve reference "192.168.180.54:5000/hello-lab:1.0": unable to read CA cert
"/etc/rancher/k3s/lab-ca.crt": open /etc/rancher/k3s/lab-ca.crt: no such file or directory

$ ansible k3s_cluster -a "ls -l /etc/rancher/k3s/"
k3s-master | CHANGED | rc=0 >>
-rw-r--r-- 1 root root 2937 Nov  5 16:23 k3s.yaml
-rw-r--r-- 1 root root  402 Nov  5 16:16 registries.yaml
k3s-worker-3 | CHANGED | rc=0 >>
-rw-r--r-- 1 root root 402 Nov  5 16:16 registries.yaml
(worker-1 i worker-2 tak samo)
```

`registries.yaml` dotarł i został wczytany (containerd szuka `lab-ca.crt` – to on mu kazał), ale polecenie
kopiujące CA się nie wykonało. `k3s.yaml` z 16:23 – k3s przepisuje kubeconfig przy każdym starcie, więc to
dowód restartu mastera. Naprawa: ponowny `copy` z `ca.crt` – opis w
[problemach](problemy.md#unable-to-read-ca-cert-etcrancherk3slab-cacrt-no-such-file-or-directory).

### 7.3. Ten sam tag, dwa różne obrazy

Po skopiowaniu `lab-ca.crt` oba nowe pody wstały, ale który obraz naprawdę działa, pokazuje dopiero digest:

```text
$ kubectl -n hello-lab get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IMAGE:.status.containerStatuses[0].imageID
POD                          NODE           IMAGE
hello-lab-55b8fb57c9-fqs7f   k3s-worker-2   192.168.180.54:5000/hello-lab@sha256:f0d8d9721afcece15164a4490c3638b35a1fd99b89832f471b1620c56dca6ae1
hello-lab-55b8fb57c9-pdrh5   k3s-worker-3   192.168.180.54:5000/hello-lab@sha256:cb8a86b8bb7ca49c27a7112d5d7419836e5986e91af41074d5f948b2e9e1492d
```

- worker-2 pobrał obraz z nowego rejestru – digest `f0d8d97…` jest **ten sam co w `docker push`** z kroku 6.4.
- worker-3 znów wziął obraz z cache (`already present on machine`) – digest `cb8a86b…` to obraz zbudowany 03.11.
- Manifest w obu przypadkach mówi `hello-lab:1.0`. Tag to etykieta, digest to skrót treści.

Naprawa – usunięcie starej kopii z cache containerd na worker-3 i nowy pod:

```bash
# 🐧 k3s-worker-3
sudo k3s crictl images | grep hello-lab                    # obrazy w containerd (Dockera na węzłach nie ma)
sudo k3s crictl rmi 192.168.180.54:5000/hello-lab:1.0      # usuń obraz z cache węzła
# 🐧 k3s-master
kubectl -n hello-lab delete pod hello-lab-55b8fb57c9-pdrh5 # ReplicaSet tworzy nowy pod, ten pobiera obraz z rejestru
```

Po tym oba pody działają na `sha256:f0d8d97…`.

> **Pytanie rekrutacyjne:** *Dwa pody jednego Deploymentu z tym samym `image: app:1.0` zachowują się inaczej. Jak to
> możliwe i jak temu zapobiec?* – Tag został nadpisany nowym obrazem, a węzeł z obrazem w cache przy
> `imagePullPolicy: IfNotPresent` go nie pobrał. Sprawdzam `.status.containerStatuses[].imageID` (digest).
> Zapobieganie: niezmienne tagi (każda wersja = nowy numer, rejestry mają opcję „immutable tags”) albo obraz
> przypięty po digest `image: …@sha256:…`. `imagePullPolicy: Always` też pomaga, ale każdy start poda zależy
> wtedy od rejestru.

### 7.4. Sprawdzenie końcowe (🐧 k3s-master)

```text
$ kubectl get pod app -o wide
NAME   READY   STATUS    RESTARTS   AGE   IP           NODE
app    1/1     Running   0          47h   10.42.3.45   k3s-worker-3
$ kubectl get pod app -o jsonpath='{.status.containerStatuses[0].imageID}{"\n"}'
192.168.180.54:5000/app@sha256:159255640ed6dda8a696f215b3e648d43035ef3e73bbaac7a091ae716eb1138a

$ kubectl -n hello-lab get svc,endpoints hello-lab
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/hello-lab   NodePort   10.43.140.142  <none>        80:30880/TCP   48m
NAME                  ENDPOINTS                           AGE
endpoints/hello-lab   10.42.1.38:8080,10.42.3.56:8080     48m

$ for i in 1 2 3 4 5 6; do curl -s http://192.168.180.52:30880/api; echo; done
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-gtvsg"}
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-fqs7f"}
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-fqs7f"}
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-gtvsg"}
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-fqs7f"}
{"app": "hello-lab", "version": "1.0", "host": "hello-lab-55b8fb57c9-fqs7f"}
```

Jak czytać:

- Pod `app` działa 47 h bez restartu (z cache węzła), a jego digest `159255640ed6…` jest **identyczny** z tym,
  który dziś wypchnęliśmy z kopii. W rejestrze jest dokładnie ten sam obraz – restart poda go odtworzy.
- `80:30880/TCP` – Service słucha w klastrze na porcie **80**, na węzłach na **30880**; `ENDPOINTS` pokazują port
  **8080**, czyli `targetPort` – port aplikacji w kontenerze. Trzy różne porty jednej usługi.
- Dwa endpointy: `10.42.1.38` (worker-2) i `10.42.3.56` (worker-3, nowy pod `gtvsg` po usunięciu starego obrazu).
  Pod, który nie jest Ready, nie trafia na tę listę.
- Zapytanie szło na worker-1 (`.52`), na którym nie ma żadnego poda hello-lab – NodePort działa na każdym węźle.
- Rozkład 2:4, a nie równo na zmianę – kube-proxy w trybie iptables wybiera pod **losowo**, nie po kolei.
- Ostrzeżenie o `Endpoints`: od Kubernetesa 1.33 zastępuje je **EndpointSlice**
  (`kubectl -n hello-lab get endpointslices`). Stare polecenie nadal działa.

**Poziom 7 zakończony.** Wszystko, co 03.11 postawił Claude (Docker, CA, rejestr, zaufanie węzłów, hello-lab),
jest teraz postawione od zera przez właściciela, a obraz `app` wrócił do rejestru bez przerwy w działaniu poda.

> **Pytanie rekrutacyjne:** *Service ma `PORT(S) 80:30880/TCP`, a endpointy `:8080`. Który port do czego?* –
> `port` 80: adres Service w klastrze (`hello-lab.hello-lab.svc:80`); `nodePort` 30880: port na każdym węźle,
> dostęp z zewnątrz; `targetPort` 8080: port kontenera, na który kube-proxy przekazuje ruch.

## Krok 7 – healthchecks.io (dead man's switch)

### Jak to działa

```
Prometheus: alert Watchdog (expr: vector(1) – zawsze aktywny)
  → Alertmanager: trasa alertname="Watchdog" → odbiorca deadmans-switch, co 1 min
     → POST https://hc-ping.com/<uuid>   – healthchecks.io: „żyje” ✅
Klaster / Prometheus / Alertmanager / internet padł → pingi ustają
  → po Period + Grace healthchecks.io wysyła e-mail „DOWN” ❌
```

Prometheus nie zgłosi własnej śmierci – dlatego „strażnik” stoi poza labem i alarmuje o **ciszy**.

Pod Alertmanagera wychodzi do internetu bez żadnej konfiguracji: ruch wychodzący z podów jest domyślnie
dozwolony (brak NetworkPolicy). Węzeł podmienia adres poda `10.42.x.x` na swój (MASQUERADE, flannel),
VMware NAT na adres Windowsa, router na publiczny – healthchecks.io widzi domowy adres IP.

### 7.1. Konto i check (🪟 przeglądarka – właściciel)

Konto na healthchecks.io, check `k3s-lab Watchdog`: **Period 2 min, Grace 5 min** (zamiast domyślnych 1 dzień /
1 h – wtedy o awarii wiedziałbyś po dobie). Period 2 min, a nie 1, daje zapas na drobne opóźnienia Alertmanagera.
Powiadomienie: e-mail (domyślna integracja).

**Ping URL to sekret** – kto go zna, może „meldować się” za klaster i maskować awarię. Trafia tylko do `lab.env`
(poza gitem); w dokumentacji zapisany jako `hc-ping.com/<uuid>`. Po wycieku: *Regenerate* w ustawieniach checka.

Test ręczny z mastera: `curl -fsS -m 10 --retry 3 https://hc-ping.com/<uuid>` → `OK` (bez nowej linii,
więc dokleja się do promptu: `OKgrzegorz@k3s-master:~$`).

### 7.2. Adres do klastra (🐧 k3s-master)

```bash
cd ~/k3s-monitoring-lab
sed -i 's|^HEALTHCHECKS_URL=.*|HEALTHCHECKS_URL=https://hc-ping.com/<uuid>|' lab.env      # albo nano +33 lab.env
set -a && source lab.env && set +a && echo "$HEALTHCHECKS_URL"
umask 077 && envsubst '${GRAFANA_ADMIN_PASSWORD} ${HEALTHCHECKS_URL}' < monitoring/kube-prometheus-stack-values.yaml > /tmp/kps-values.yaml && grep -n "hc-ping" /tmp/kps-values.yaml
helm upgrade monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 -n monitoring -f /tmp/kps-values.yaml --wait --timeout 15m
rm /tmp/kps-values.yaml
```

| Polecenie | Po co |
|---|---|
| `set -a` / `source lab.env` / `set +a` | wczytaj zmienne z pliku do **tej** powłoki i eksportuj je, żeby widział je `envsubst` |
| `umask 077` | nowe pliki od razu `600` – w `/tmp/kps-values.yaml` jest hasło Grafany (`chmod` po fakcie zostawiłby chwilowe okno) |
| `envsubst '${A} ${B}'` | wstaw wartości **tylko** tych dwóch zmiennych w luki pliku values; plik w repo zostaje z lukami |
| `helm upgrade … -f` | pełny plik values = wszystkie ustawienia (dyski, NodePorty, hasło); zmienia się tylko adres |

Niespodzianka: pierwsze `echo "$HEALTHCHECKS_URL"` pokazało zera – adres został wpisany do `lab.env` na
`monitoring`, a `helm` działa na masterze z **jego** kopią
([problem](problemy.md#labenv-zmieniony-a-wczytują-się-stare-wartości)).

Wynik: `Release "monitoring" has been upgraded` – **REVISION 3**.

### 7.3. Sprawdzenie – co ma Alertmanager

```bash
kubectl -n monitoring get secret alertmanager-monitoring-kube-prometheus-alertmanager-generated \
  -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip | grep hc-ping
```

Konfiguracja przechodzi: values → Secret od Helma → operator skleja go w Secret `…-generated` (gzip + base64)
→ kontener `config-reloader` w podzie przeładowuje Alertmanagera bez restartu poda.

`grep -A1 webhook_configs` pokazało tylko `- send_resolved: false` – Alertmanager zapisuje klucze **alfabetycznie**,
więc `url` jest linię niżej. Lepiej szukać samej wartości (`grep hc-ping`).

> **Pytanie rekrutacyjne:** *Co to jest dead man's switch w monitoringu i po co, skoro jest Prometheus?* –
> Alert, który jest zawsze aktywny i stale wysyła sygnał do zewnętrznej usługi. Alarm przychodzi, gdy sygnał
> **ustaje** – czyli gdy padł Prometheus, Alertmanager, cały klaster albo łączność. Monitoring nie może
> zgłosić własnej awarii, więc musi go pilnować coś poza nim.

> **Pytanie rekrutacyjne:** *Czym grozi `helm upgrade` bez `-f`, tylko z `--set`?* – Helm nie łączy z poprzednimi
> ustawieniami: wszystko spoza `--set` wraca do domyślnych chartu (np. znikają trwałe dyski, NodePorty).
> Zawsze pełny plik values z repo jako jedyne źródło prawdy; `--reuse-values` ukrywa stan w klastrze.

## Krok 8 – Grafana i Uptime Kuma na `monitoring`

Ręcznie, bez skryptu `06-setup-monitoring-vm.sh` (🐧 monitoring):

```bash
cd ~/k3s-monitoring-lab && git pull
grep -E "^(MASTER_IP|WORKER2_IP|MONITORING_IP)=" lab.env                 # prawdziwe adresy, nie 192.168.1.x z wzoru
grep -c "^GRAFANA_ADMIN_PASSWORD=." lab.env; grep -c "zmien-to-haslo" lab.env   # 1 i 0 – hasło jest, nie przykładowe
cd monitoring/monitoring-vm
set -a && source ../../lab.env && set +a
umask 077 && printf 'MASTER_IP=%s\nWORKER2_IP=%s\nGRAFANA_ADMIN_PASSWORD=%s\n' "$MASTER_IP" "$WORKER2_IP" "$GRAFANA_ADMIN_PASSWORD" > .env
ls -l .env && cut -d= -f1 .env && git check-ignore -v .env              # 600, same nazwy, ignorowany przez git
docker compose up -d
```

Wynik z labu: `.env` z prawami `-rw-------` (600), w środku trzy nazwy zmiennych, `git check-ignore` wskazał
regułę z `.gitignore`, a `docker compose up -d` pobrał obrazy, utworzył sieć `monitoring-vm_default`, wolumeny
`monitoring-vm_grafana-data` i `monitoring-vm_uptime-kuma-data` oraz uruchomił kontenery `grafana` i `uptime-kuma`
(`Started`).

- `.env` czyta Docker Compose sam (luki `${…}` w `docker-compose.yml`). `ls` go nie pokazuje – pliki z kropką są ukryte (`ls -a`).
- `cut -d= -f1` i `grep -c` sprawdzają plik z hasłem **bez wypisywania hasła**.
- Hasło z `GF_SECURITY_ADMIN_PASSWORD` działa tylko przy **pierwszym** starcie Grafany – potem jego hash jest
  w `grafana.db` w wolumenie, a zmiana `.env` nic nie zmienia.
- Zmienne środowiskowe kontenera widzi każdy z grupy `docker` (`docker inspect grafana`) – kolejny powód,
  dla którego grupa `docker` = root.

### Grafana

Pusta po starcie – to poprawne: z `grafana/provisioning/` dostaje tylko **źródło danych** „Prometheus (k3s-lab)”
(`http://192.168.180.51:30090`, Prometheus w klastrze). Dashboard: *Dashboards → New → Import → 1860*
(*Node Exporter Full*) → źródło „Prometheus (k3s-lab)”. Grafana na `monitoring` czyta **te same** dane co
Grafana w klastrze – przy awarii klastra pokaże „No data”. Własne dane dostałaby dopiero z magazynem metryk
poza klastrem (np. VictoriaMetrics + `remote_write`) – pomysł na później.

### Uptime Kuma – wersja 1 nieutrzymywana

Strona `:3001` pokazała: *„This Uptime Kuma version is outdated! Current Version: 1.23.17”*. Plik compose miał
`louislam/uptime-kuma:1` – wersja 1 nie dostaje już poprawek bezpieczeństwa. Zmiana na tag **`2`** (zalecany,
najnowsza 2.x) i wymiana kontenera, zanim powstało konto:

```bash
git pull                                            # docker-compose.yml z uptime-kuma:2
docker compose rm -sf uptime-kuma                   # stop + usuń tylko ten kontener
docker volume rm monitoring-vm_uptime-kuma-data     # pusta baza po v1 – v2 startuje od czysta
docker compose up -d uptime-kuma
```

Przycisk „Stwórz” przy zakładaniu konta nie działał – przeglądarka miała w pamięci stronę wersji 1. Po
`Ctrl+Shift+R` Kuma 2 zapytała najpierw o bazę: **SQLite** (jeden plik w wolumenie; wbudowana MariaDB ma sens
przy setkach monitorów). Konto administratora zakłada właściciel – login inny niż `admin`, hasło w menedżerze haseł.

Monitory:

| Nazwa | Typ | Adres |
|---|---|---|
| hello-lab | HTTP(s) | `http://192.168.180.51:30880/healthz` |
| podinfo (NodePort) | HTTP(s) | `http://192.168.180.51:30898/healthz` |
| podinfo (Ingress) | HTTP(s) | `http://podinfo.lab.local/healthz` |
| Prometheus | HTTP(s) | `http://192.168.180.51:30090/-/healthy` |
| API Kubernetesa | TCP Port | `192.168.180.51` : `6443` |
| Rejestr obrazów | TCP Port | `192.168.180.54` : `5000` |

Interwał 60 s, 2 ponowienia (awaria ogłoszona po ~3 min). `/healthz` to adres zdrowia aplikacji – w hello-lab
napisany w `app.py`; ten sam adres pytają `HEALTHCHECK` w Dockerze i sondy readiness/liveness w Kubernetesie.

**API Kubernetesa – czerwone.** `nc -zv -w 3 192.168.180.51 6443` z `monitoring` → timeout. Rola Ansible `common`
otwiera 6443 tylko dla `admin_cidr`, a NodePorty – dla `admin_cidr` **i** maszyny `monitoring`
([problem](problemy.md#uptime-kuma-api-kubernetesa-6443-czerwone--firewall-na-masterze)). Szybka łatka na masterze:
`sudo ufw allow from 192.168.180.54 to any port 6443 proto tcp` → `Rule added`. Do zrobienia: ta sama reguła
w roli Ansible (właściciel), żeby nie było **configuration drift** – różnicy między kodem a serwerem.

### Awaria hosta (ok. 20:10)

Monitor API dalej czerwony, SSH na mastera nie odpowiadało, a konsola VMware mastera pokazywała:

```text
rcu: INFO: rcu_preempt detected stalls on CPUs/tasks
rcu_preempt kthread timer wakeup didn't happen for 55995 jiffies
Unless rcu_preempt kthread gets sufficient CPU time, OOM is now expected behavior
```

Maszyna przez ~56 s nie dostała procesora od VMware – problem po stronie **hosta**, nie k3s. Chwilę później
zawiesił się cały Windows i trzeba było go wyłączyć twardo (diagnoza następnego dnia: [8 takich zawieszeń w miesiącu,
stary mikrokod procesora](../etap-0-maszyny-wirtualne/problemy.md#host-zawiesza-się-razem-z-maszynami)). Potem k3s-worker-3 nie startował:
*„Cannot open the disk …\k3s-worker-3\disk-000005.vmdk or one of the snapshot disks it depends on”* – zostały
**pliki blokad `*.lck`** po nagłym zakończeniu
([problem](problemy.md#vmware-cannot-open-the-disk--pozostałe-blokady-lck)).

## Krok 9 – reguła 6443 w kodzie, nie tylko na serwerze (06.11.2026)

Ręczna reguła z kroku 8 przetrwała restart, ale istniała tylko na masterze. Przy przebudowie maszyny z Ansible
by zniknęła i monitor API w Kumie znowu by się zaczerwienił. Właściciel przeniósł ją do roli `common`.

### 9.1. Zmiana w roli (🪟 Windows – właściciel, commit `c903998`)

`ansible/roles/common/tasks/main.yml` – zadanie dostało pętlę, tak jak sąsiednia reguła NodePortów:

```diff
-        - name: API Kubernetesa z sieci administratora
+        - name: API Kubernetesa z sieci administratora i z monitoring
           community.general.ufw:
             rule: allow
-            from_ip: "{{ admin_cidr }}"
+            from_ip: "{{ item }}"
             port: "6443"
             proto: tcp
+          loop:
+            - "{{ admin_cidr }}"
+            - 192.168.180.54
```

- `loop` – Ansible wykonuje zadanie raz dla każdej pozycji listy; `item` to bieżąca pozycja.
- Adres `monitoring` jest tu wpisany na sztywno (wybór „na razie prostszy”). Przy pełnej automatyzacji lepiej brać
  go z inwentarza, żeby zmiana adresu maszyny była w jednym miejscu:
  `loop: "{{ [admin_cidr] + (groups['monitoring_vm'] | map('extract', hostvars, 'ansible_host') | list) }}"`.

### 9.2. Sprawdzenie i uruchomienie (🐧 monitoring, w `~/k3s-monitoring-lab/ansible`)

```bash
git pull                                    # zmiana z GitHuba na maszynę sterującą
ansible-playbook site.yml --syntax-check    # składnia YAML i struktura, bez łączenia z maszynami
ansible-lint roles/common                   # dobre praktyki
ansible-playbook playbooks/prepare.yml --limit k3s-master --check --diff \
  --start-at-task "API Kubernetesa z sieci administratora i z monitoring"   # na sucho
ansible-playbook playbooks/prepare.yml --limit k3s-master --diff \
  --start-at-task "API Kubernetesa z sieci administratora i z monitoring"   # naprawdę
```

`--start-at-task` zaczyna od wskazanego zadania (nazwa musi być dokładnie jak w pliku) – pomija m.in. `apt upgrade`
z początku roli. Na końcu wyniku `ansible-lint` była informacja o nowszej wersji (26.10.1 → 26.11.0) – to tylko
podpowiedź, nie błąd; aktualizacja: `pip install --upgrade ansible-lint`.

Wynik z labu – próba na sucho i prawdziwe uruchomienie dały **to samo**:

```text
TASK [common : API Kubernetesa z sieci administratora i z monitoring] **********
ok: [k3s-master] => (item=192.168.180.0/24)
ok: [k3s-master] => (item=192.168.180.54)

TASK [common : Ingress (HTTP i HTTPS)] *****************************************
ok: [k3s-master] => (item=80)
ok: [k3s-master] => (item=443)

TASK [common : NodePorty dla administratora i maszyny monitoring] **************
ok: [k3s-master] => (item=192.168.180.0/24)
ok: [k3s-master] => (item=192.168.180.54)

TASK [common : Włącz firewall] *************************************************
ok: [k3s-master]

PLAY RECAP *********************************************************************
k3s-master                 : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Dlaczego `changed=0`:** reguła dla `.54` już była (ręczna łatka z kroku 8). Moduł `ufw` najpierw sprawdza, czy taka
reguła istnieje, i dodaje ją tylko wtedy, gdy jej brak. Serwer był już w stanie opisanym w kodzie, więc nic się nie
zmieniło – to **idempotentność**. Teraz kod i serwer mówią to samo: drift usunięty. `--start-at-task` uruchamia też
zadania **po** wskazanym (Ingress, NodePorty, włączenie firewalla) – wszystkie `ok`, czyli i one zgadzają się z kodem.

Na pozostałych węzłach (`--limit` tylko na master) nowa reguła pojawi się przy następnym pełnym przebiegu
`prepare.yml` – tam API nie działa, więc nic to nie zmienia.

### Pytania rekrutacyjne

- **Co to jest configuration drift i jak go wykryć?** Różnica między stanem opisanym w kodzie (Ansible, Terraform)
  a rzeczywistym stanem serwera – zwykle po ręcznej „szybkiej łatce”. Wykrywa się ją uruchomieniem w trybie
  `--check --diff` (Ansible) albo `terraform plan`: każde `changed` to miejsce, gdzie serwer różni się od kodu.
- **Co znaczy, że playbook jest idempotentny? Jak to sprawdzisz?** Kolejne uruchomienie na tym samym serwerze nic nie
  zmienia ani nie dubluje – drugi przebieg kończy się `changed=0`. Moduły (`ufw`, `apt`, `copy`) same sprawdzają
  stan przed zmianą; ryzykowne są `command` i `shell`, które bez `creates:` / `changed_when:` wykonują się zawsze.
- **Po co `--check --diff` przed prawdziwym uruchomieniem?** Pokazuje, co *zmieniłoby się*, bez dotykania serwera
  – jak przegląd zmian przed wdrożeniem. Na produkcji to standard przed każdą zmianą.

## Co dalej (następna sesja)

- ~~sprawdzić, czy wszystkie maszyny wstały~~ ✅ 06.11 – wszystkie 5 maszyn działa;
- ~~reguła 6443 dla `monitoring` w roli Ansible~~ ✅ 06.11 ([krok 9](#krok-9--reguła-6443-w-kodzie-nie-tylko-na-serwerze-06112026));
- ~~przyczyna zawieszenia hosta~~ ✅ 06.11 ([diagnoza](../etap-0-maszyny-wirtualne/03-diagnoza-zawieszenia-hosta.md)) – właściciel aktualizuje BIOS;
- healthchecks.io: Period 2 min, Grace 5 min (teraz domyślne 1 dzień / 1 h);
- reszta monitorów w Kumie, dashboard 1860 w Grafanie;
- powiadomienia w Kumie, potwierdzenie pingów healthchecks.io, test awarii, zamknięcie Etapu 4;
- pominięte poziomy ćwiczeń z obrazu: 2 (warstwy), 4 (`.dockerignore`), 8 (nowa wersja i wycofanie).
