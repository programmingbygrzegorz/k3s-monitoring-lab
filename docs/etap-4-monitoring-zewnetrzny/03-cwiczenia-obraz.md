# Etap 4 – ćwiczenia: własny obraz od Dockerfile do k3s

Osiem poziomów: od pierwszego kontenera, przez własny Dockerfile, warstwy i bezpieczny obraz,
po prywatny rejestr z TLS i wdrożenie na klaster z aktualizacją i wycofaniem. Każdy poziom
zajmuje 10–20 minut. Teoria do tych ćwiczeń: [jak zbudować własny obraz](02-wlasny-obraz.md).

Wykonanie wszystkich poziomów z prawdziwymi wynikami:
[rozwiązania ćwiczeń z obrazu](04-cwiczenia-obraz-rozwiazania.md). Identyfikatory obrazów,
nazwy podów i czasy u Ciebie będą inne.

**Przed startem:** klaster z Etapu 2 działa (4 węzły `Ready`), na `monitoring` jest aktualne
repozytorium (`cd ~/k3s-monitoring-lab && git pull`). 📸 Snapshot `monitoring` i węzłów k3s.

| Poziom | Temat | Gdzie |
|---|---|---|
| [0](#poziom-0--docker-na-monitoring) | Docker na `monitoring` | 🐧 monitoring |
| [1](#poziom-1--pierwszy-kontener) | pierwszy kontener: obraz, kontener, port | 🐧 monitoring |
| [2](#poziom-2--pierwszy-dockerfile) | pierwszy Dockerfile: strona na nginx | 🐧 monitoring |
| [3](#poziom-3--własna-aplikacja) | własna aplikacja: `ARG`, `ENV`, `CMD`, logi, `exec` | 🐧 monitoring |
| [4](#poziom-4--warstwy-cache-i-dockerignore) | warstwy, cache i `.dockerignore` | 🐧 monitoring |
| [5](#poziom-5--lepszy-obraz-nie-root-healthcheck-rozmiar) | lepszy obraz: nie-root, HEALTHCHECK, rozmiar | 🐧 monitoring |
| [6](#poziom-6--prywatny-rejestr-z-tls) | prywatny rejestr z TLS i własnym CA | 🐧 monitoring |
| [7](#poziom-7--obraz-z-rejestru-na-k3s) | obraz z rejestru na k3s | 🐧 monitoring + k3s-master |
| [8](#poziom-8--nowa-wersja-i-wycofanie) | nowa wersja i wycofanie | 🐧 monitoring + k3s-master |
| [–](#sprzątanie) | sprzątanie | |

---

## Poziom 0 – Docker na monitoring

🪟 Windows: `ssh monitoring`

Sprawdź, czy Docker już jest: `docker --version`. Jeśli nie ma (`command not found`):

```bash
curl -fsSL https://get.docker.com | sudo sh      # oficjalny skrypt instalacyjny Dockera
sudo usermod -aG docker $USER                    # docker bez sudo
exit                                             # wyloguj się i zaloguj ponownie (ssh monitoring)
```

Po ponownym zalogowaniu: `id` (na liście grup jest `docker`) i `docker version`.

**Sprawdź się:** dlaczego członkostwo w grupie `docker` jest tak samo groźne jak `sudo`?
(Podpowiedź: `docker run -v /:/host ...`.)

## Poziom 1 – pierwszy kontener

**Cel:** zobaczyć różnicę między obrazem a kontenerem.

1. `docker run hello-world`: Docker pobiera obraz i uruchamia z niego kontener, który wypisuje
   powitanie i kończy działanie.
2. `docker images`: obrazy na dysku.
3. `docker ps` (działające kontenery) i `docker ps -a` (także zakończone).
4. Serwer WWW w tle: `docker run -d --name web -p 8081:80 nginx:alpine`.
5. `curl localhost:8081` i `docker logs web`.
6. Usuń kontener: `docker rm -f web`. Sprawdź `docker images`: obraz `nginx:alpine` **został**.

**Co powinieneś zobaczyć:** `Hello from Docker!`, stronę `Welcome to nginx!`, w logach nginx
Twoje zapytanie `GET / ... curl`.

**Sprawdź się:**
- Co zostaje po `docker rm`, a co po `docker rmi`?
- Co oznacza `-p 8081:80`? Która liczba to port maszyny, a która kontenera?

## Poziom 2 – pierwszy Dockerfile

**Cel:** zbudować własny obraz z gotowego obrazu bazowego.

```bash
mkdir -p ~/strona && cd ~/strona
echo '<h1>Moja pierwsza strona w kontenerze</h1>' > index.html
nano Dockerfile
```

Treść `Dockerfile`:

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
```

Zbuduj, uruchom, sprawdź, usuń:

```bash
docker build -t moja-strona:1 .
docker images moja-strona
docker run -d --name strona -p 8082:80 moja-strona:1
curl localhost:8082
docker rm -f strona
```

**Co powinieneś zobaczyć:** w wyniku `build` dwa kroki `[1/2] FROM` i `[2/2] COPY`, a `curl`
zwraca Twój nagłówek.

**Sprawdź się:** co oznacza kropka na końcu `docker build ... .`?

## Poziom 3 – własna aplikacja

**Cel:** obraz dla programu w Pythonie, z wersją podawaną przy budowaniu.

```bash
mkdir -p ~/hello-lab && cd ~/hello-lab
cp ~/k3s-monitoring-lab/apps/hello-lab/app.py .
less app.py                     # przeczytaj: adresy /, /healthz, /api, zmienne APP_VERSION i PORT
nano Dockerfile
```

Pierwsza, prosta wersja `Dockerfile` (poprawisz ją w poziomie 5):

```dockerfile
FROM python:3.14-slim
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
```

```bash
docker build --build-arg APP_VERSION=1.0 -t hello-lab:1.0 .
docker run -d --name hello -p 8080:8080 hello-lab:1.0
curl localhost:8080/api
curl localhost:8080/healthz
docker logs hello
docker exec hello whoami
docker exec hello env | grep APP
```

Otwórz też w przeglądarce na Windowsie `http://192.168.180.54:8080`.

**Co powinieneś zobaczyć:** `{"app": "hello-lab", "version": "1.0", "host": "<id kontenera>"}`,
`ok`, w logach linię startową i Twoje zapytania, a `whoami` zwraca **`root`**.

**Sprawdź się:**
- Zbuduj jeszcze raz **bez** `--build-arg`. Jaką wersję pokaże `/api` i dlaczego?
- Skąd się wzięła nazwa `host` w odpowiedzi?
- Dlaczego `root` w kontenerze to problem?

## Poziom 4 – warstwy, cache i .dockerignore

**Cel:** zrozumieć, z czego składa się obraz i dlaczego kolejność w Dockerfile ma znaczenie.

1. Warstwy obrazu:
   ```bash
   docker history hello-lab:1.0
   ```
2. Zbuduj jeszcze raz bez zmian. Ile kroków ma `CACHED`?
3. Zmień w `app.py` domyślny kolor (`#2b6cb0` na `#c05621`) i zbuduj ponownie. Który krok się
   wykonał, a który był `CACHED`?
4. Doświadczenie z `.dockerignore`. Zmień w Dockerfile `COPY app.py .` na `COPY . .`, a potem:
   ```bash
   dd if=/dev/zero of=kopia-zapasowa.tar bs=1M count=200     # udajemy duży plik w katalogu
   docker build --build-arg APP_VERSION=1.0 -t hello-lab:test .
   docker images hello-lab
   docker run --rm hello-lab:test ls -la /app
   ```
5. Utwórz `.dockerignore`:
   ```bash
   cp ~/k3s-monitoring-lab/apps/hello-lab/.dockerignore .
   cat .dockerignore
   ```
   Zbuduj `hello-lab:test` jeszcze raz i porównaj rozmiar oraz zawartość `/app`.
6. Posprzątaj: `rm kopia-zapasowa.tar && docker rmi hello-lab:test`, przywróć `COPY app.py .`
   i kolor `#2b6cb0`.

**Co powinieneś zobaczyć:** w kroku 4 `transferring context: ~210MB` i obraz większy o 200 MB,
a w `/app` plik `kopia-zapasowa.tar`. W kroku 5 kontekst ma kilkaset bajtów, a obraz wraca do
dawnego rozmiaru.

**Sprawdź się:**
- Dlaczego `COPY app.py .` powinno być **po** `RUN`, które instaluje pakiety?
- Jakie pliki z prawdziwego projektu wpisałbyś do `.dockerignore`?

## Poziom 5 – lepszy obraz: nie-root, HEALTHCHECK, rozmiar

**Cel:** obraz, który da się obronić na rozmowie.

1. Porównaj obrazy bazowe:
   ```bash
   docker pull python:3.14
   docker pull python:3.14-alpine
   docker images python
   ```
2. Zastąp swój Dockerfile wersją końcową i przeczytaj komentarze:
   ```bash
   cp ~/k3s-monitoring-lab/apps/hello-lab/Dockerfile .
   less Dockerfile
   ```
3. Zbuduj i uruchom od nowa:
   ```bash
   docker rm -f hello
   docker build --build-arg APP_VERSION=1.0 -t hello-lab:1.0 .
   docker run -d --name hello -p 8080:8080 hello-lab:1.0
   docker ps                         # kolumna STATUS: (health: starting), po ~30 s (healthy)
   docker exec hello id
   ```
4. Usuń obraz `python:3.14`, bo zajmuje dużo miejsca: `docker rmi python:3.14 python:3.14-alpine`.

**Co powinieneś zobaczyć:** `python:3.14` ok. 1,6 GB, `-alpine` ok. 74 MB; po chwili `(healthy)`;
`id` zwraca `uid=10001(app)`.

**Sprawdź się:**
- Dlaczego `RUN useradd` jest **przed** `COPY app.py .`?
- Czym różni się HEALTHCHECK w Dockerze od `livenessProbe` w Kubernetesie? Kto reaguje na wynik?

## Poziom 6 – prywatny rejestr z TLS

**Cel:** miejsce, z którego każdy węzeł k3s pobierze Twój obraz, po szyfrowanym połączeniu.

1. Najpierw zobacz, dlaczego potrzebny jest certyfikat. Uruchom rejestr bez TLS i spróbuj wysłać obraz:
   ```bash
   docker run -d --name rejestr -p 5000:5000 registry:3
   docker tag hello-lab:1.0 192.168.180.54:5000/hello-lab:1.0
   docker push 192.168.180.54:5000/hello-lab:1.0
   docker rm -f rejestr
   ```
   Przeczytaj błąd. Nie rób obejścia z `insecure-registries`.
2. Utwórz CA labu i certyfikat rejestru: polecenia `openssl` z teorii, w
   [sekcji o własnym CA](02-wlasny-obraz.md#dlaczego-https-i-własny-urząd-certyfikacji-ca).
   Sprawdź wynik:
   ```bash
   openssl x509 -in ~/rejestr-certs/registry.crt -noout -subject -issuer -ext subjectAltName
   ```
3. Uruchom rejestr z TLS (polecenie `docker run ... registry:3` z
   [teorii](02-wlasny-obraz.md#6-rejestr--skąd-klaster-weźmie-obraz)).
4. Sprawdź połączenie bez CA i z CA:
   ```bash
   curl https://192.168.180.54:5000/v2/_catalog; echo "kod: $?"
   curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/_catalog
   ```
5. Spróbuj `docker push` (błąd `x509`), potem naucz Dockera ufać CA labu dla tego rejestru:
   ```bash
   sudo mkdir -p /etc/docker/certs.d/192.168.180.54:5000
   sudo cp ~/rejestr-certs/ca.crt /etc/docker/certs.d/192.168.180.54:5000/ca.crt
   docker push 192.168.180.54:5000/hello-lab:1.0
   curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/hello-lab/tags/list
   ```

**Co powinieneś zobaczyć:** w kroku 1 `server gave HTTP response to HTTPS client`, w kroku 4 kod `60`
bez CA i `{"repositories":[]}` z CA, a w kroku 5 najpierw
`x509: certificate signed by unknown authority`, potem `Pushed` i `{"name":"hello-lab","tags":["1.0"]}`.

**Sprawdź się:**
- Który plik jest „pieczątką”, a który „wzorem pieczątki”? Którego nie wolno nikomu dać?
- Po co `subjectAltName=IP:192.168.180.54`?
- Port 5000 nie jest otwarty w ufw. Dlaczego workery i tak się połączą?

## Poziom 7 – obraz z rejestru na k3s

**Cel:** wdrożyć własny obraz na klaster, najpierw zobaczyć błąd, potem go naprawić.

1. 🐧 **k3s-master:** wdróż od razu, bez konfigurowania węzłów:
   ```bash
   cd ~/k3s-monitoring-lab && git pull
   kubectl apply -f kubernetes/hello-lab/hello-lab.yaml
   kubectl -n hello-lab get pods -o wide -w        # Ctrl+C po ~30 s
   kubectl -n hello-lab get events --sort-by=.lastTimestamp
   ```
2. 🐧 **monitoring:** roześlij CA i `registries.yaml` na wszystkie węzły przez Ansible:
   ```bash
   cd ~/k3s-monitoring-lab/ansible
   ansible k3s_cluster -b -m file -a "path=/etc/rancher/k3s state=directory mode=0755"
   ansible k3s_cluster -b -m copy -a "src=$HOME/rejestr-certs/ca.crt dest=/etc/rancher/k3s/lab-ca.crt mode=0644"
   ansible k3s_cluster -b -m copy -a "src=$HOME/k3s-monitoring-lab/apps/hello-lab/k3s-registries.yaml dest=/etc/rancher/k3s/registries.yaml mode=0644"
   ansible k3s_server -b -m systemd -a "name=k3s state=restarted"
   ansible k3s_agents -b -f 1 -m systemd -a "name=k3s-agent state=restarted"
   ```
3. 🐧 **k3s-master:**
   ```bash
   kubectl get nodes
   kubectl -n hello-lab get pods -o wide
   for i in 1 2 3 4 5 6; do curl -s http://192.168.180.52:30880/api; done
   ```
4. 🪟 W przeglądarce: `http://192.168.180.51:30880`.

**Co powinieneś zobaczyć:** w kroku 1 `ErrImagePull` / `ImagePullBackOff`, a w zdarzeniach `x509`.
Po kroku 2 pody same przechodzą w `1/1 Running` przy następnej próbie (albo przyspiesz:
`kubectl -n hello-lab rollout restart deploy/hello-lab`). `curl` pokazuje na zmianę **dwie**
różne nazwy podów, a strona jest zielona (kolor z `APP_COLOR` w manifeście).

**Sprawdź się:**
- Dlaczego `-f 1` przy restarcie agentów?
- Po co pierwszy `ansible ... -m file`? Co się stanie bez niego? (Zobacz
  [problemy](problemy.md#ansible-copy-destination-directory-etcrancherk3s-does-not-exist).)
- Kto pobiera obraz: kubelet, containerd czy Docker?

## Poziom 8 – nowa wersja i wycofanie

**Cel:** pełny cykl wydania: build → push → wdrożenie → wycofanie.

1. 🐧 **monitoring:**
   ```bash
   cd ~/hello-lab
   docker build --build-arg APP_VERSION=1.1 -t 192.168.180.54:5000/hello-lab:1.1 .
   docker push 192.168.180.54:5000/hello-lab:1.1
   ```
2. 🐧 **k3s-master:**
   ```bash
   kubectl -n hello-lab set image deployment/hello-lab hello-lab=192.168.180.54:5000/hello-lab:1.1
   kubectl -n hello-lab annotate deployment/hello-lab kubernetes.io/change-cause="wersja 1.1" --overwrite
   kubectl -n hello-lab rollout status deployment/hello-lab
   curl -s http://192.168.180.51:30880/api
   kubectl -n hello-lab rollout history deployment/hello-lab
   kubectl -n hello-lab rollout undo deployment/hello-lab
   kubectl -n hello-lab rollout status deployment/hello-lab
   curl -s http://192.168.180.51:30880/api
   ```
3. Zepsuj wdrożenie: `kubectl -n hello-lab set image deployment/hello-lab hello-lab=192.168.180.54:5000/hello-lab:2.0`
   (takiego tagu nie ma). Obserwuj `kubectl -n hello-lab get pods`, a potem wycofaj.

**Co powinieneś zobaczyć:** przy `push` wersji 1.1 większość warstw ma `Layer already exists`,
`/api` pokazuje `1.1`, a po `undo` znowu `1.0`. W kroku 3 jeden nowy pod w `ImagePullBackOff`,
a stare dalej odpowiadają.

**Sprawdź się:**
- Dlaczego przy `push` wersji 1.1 wysłana została tylko jedna nowa warstwa?
- Dlaczego w kroku 3 aplikacja dalej działa?
- Po `rollout undo` kubectl ostrzega o `last-applied-configuration`. Co to znaczy dla
  następnego `kubectl apply`?

## Sprzątanie

Usunięcie aplikacji z klastra (rejestr i konfiguracja węzłów zostają, przydadzą się w Etapie 5):

```bash
kubectl delete namespace hello-lab                  # 🐧 k3s-master
docker rm -f hello && docker image prune -f         # 🐧 monitoring
```

Pełny reset, żeby przejść ćwiczenie od zera: w [rozwiązaniach](04-cwiczenia-obraz-rozwiazania.md#pełny-reset).
