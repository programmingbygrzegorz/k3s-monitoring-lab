# 3. Monitoring w klastrze

Pierwszy raz z Kubernetesem lub Helmem? Pojęcia (chart, values, release, Traefik, CRD, operator)
wyjaśnia [docs/teoria-kubernetes-helm.md](teoria-kubernetes-helm.md). Co robi każda linia pliku values –
[docs/03a-values-monitoringu.md](03a-values-monitoringu.md).

## Co instalujemy

Chart **kube-prometheus-stack** z ustawieniami z `monitoring/kube-prometheus-stack-values.yaml`,
a potem aplikację demo **podinfo** z własnymi regułami alertów.

| Komponent | Rola |
|---|---|
| Prometheus | zbiera i przechowuje metryki |
| node-exporter | metryki węzłów: CPU, RAM, dysk, sieć |
| kube-state-metrics | stan obiektów Kubernetesa: pody, Deploymenty, restarty |
| Alertmanager | grupuje alerty i wysyła powiadomienia |
| Grafana | dashboardy |
| prometheus-operator | zarządza Prometheusem i Alertmanagerem na podstawie obiektów z CRD |

Dwie drogi: **ręcznie, krok po kroku** (poniżej – zalecana za pierwszym razem) albo
[skryptem](#instalacja-skryptem) jednym poleceniem.

## Instalacja ręczna krok po kroku

Wszystkie polecenia wpisujesz **na `k3s-master`** (połączenie z Windowsa: `ssh k3s-master`).
Tam jest kubeconfig, repozytorium i `lab.env`. Helm nie instaluje niczego na masterze – wysyła
obiekty do API klastra, a pody lądują na workerach.

### Krok 0. Repozytorium i zasoby węzłów

```bash
cd ~/k3s-monitoring-lab && git pull
kubectl top nodes
```

- `&&` – drugie polecenie wykona się tylko wtedy, gdy pierwsze się udało.
- `git pull` – pobiera najnowsze pliki z GitHuba.
- `kubectl top nodes` – bieżące zużycie CPU i pamięci węzłów (dane z metrics-server). Zaraz po
  starcie maszyn: `Metrics API not available` – odczekaj 1–2 minuty.

Wynik z labu przed instalacją monitoringu:

```
NAME           CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k3s-master     32m          1%       1319Mi          39%
k3s-worker-1   10m          0%       628Mi           11%
k3s-worker-2   11m          0%       631Mi           11%
k3s-worker-3   14m          0%       813Mi           13%
```

Liczy się **wolna pamięć workerów** (każdy ma ~4,5 GiB wolnego) – master ma taint `NoSchedule`
i nie dostanie podów monitoringu (poza node-exporterem). Jak czytać `32m` i `Mi` –
[teoria, rozdział 5](teoria-kubernetes-helm.md#5-zasoby-węzłów-i-kubectl-top).

### Krok 1. Instalacja Helma

Skrypt instaluje Helma jedną linią `curl … | bash` – wykonuje kod z internetu bez oglądania go.
Ręcznie robimy to porządniej: pobieramy archiwum, sprawdzamy sumę kontrolną i instalujemy plik.

```bash
HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep -oP '"tag_name": "\K[^"]+'); echo $HELM_VERSION
```

| Część | Znaczenie |
|---|---|
| `curl -s URL` | pobierz stronę po cichu (bez paska postępu) |
| `api.github.com/…/releases/latest` | JSON z opisem najnowszego wydania Helma, w tym `"tag_name": "v4.x.y"` |
| `\|` | potok: wyjście `curl` trafia do `grep` |
| `grep -o` | wypisz tylko dopasowany fragment, nie całą linię |
| `grep -P` | wyrażenia regularne w stylu Perla – tylko one znają `\K` |
| `"tag_name": "\K[^"]+` | znajdź `"tag_name": "`, `\K` – „to, co przede mną, nie wchodzi do wyniku”, `[^"]+` – znaki do następnego cudzysłowu, czyli numer wersji |
| `$( … )` | wynik polecenia staje się tekstem |
| `HELM_VERSION=…` | zapisz go w zmiennej powłoki (bez spacji wokół `=`); zmienna żyje tylko w tej sesji |
| `echo $HELM_VERSION` | sprawdź, czy nie jest pusta |

```bash
cd /tmp && curl -fsSLO https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz && curl -fsSLO https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum
```

| Flaga `curl` | Znaczenie |
|---|---|
| `-f` | przy błędzie HTTP (np. 404) zakończ się błędem i nie zapisuj strony błędu jako pliku |
| `-s` / `-S` | cicho, ale pokaż błąd, jeśli wystąpi |
| `-L` | idź za przekierowaniami |
| `-O` | zapisz plik pod oryginalną nazwą z adresu |

Archiwum to program dla Linuksa na procesorach x86-64 (`linux-amd64`), a plik `.sha256sum` zawiera
jego sumę kontrolną.

```bash
sha256sum -c helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum
```

`sha256sum` liczy „odcisk palca” pliku – zmiana jednego bajtu daje zupełnie inny wynik. `-c`
porównuje go z zapisanym. `OK` – plik dotarł cały. `FAILED` – **nie instaluj**.

> Suma pochodzi z tego samego serwera co archiwum, więc chroni przed uszkodzeniem przy
> pobieraniu, ale nie przed podmianą obu plików przez atakującego – przed tym chroni dopiero
> podpis GPG. W labie suma wystarczy.

```bash
tar -xzf helm-${HELM_VERSION}-linux-amd64.tar.gz && sudo install -m 755 linux-amd64/helm /usr/local/bin/helm
helm version
```

| Część | Znaczenie |
|---|---|
| `tar -x -z -f plik` | rozpakuj (`x`) archiwum gzip (`z`) z pliku (`f`) → katalog `linux-amd64/` |
| `install -m 755 źródło cel` | skopiuj i od razu ustaw uprawnienia: właściciel rwx, reszta r-x |
| `/usr/local/bin` | miejsce na programy instalowane ręcznie; `/usr/bin` należy do `apt` |
| `helm version` | wersja Helma – potwierdza, że działa i jest w `$PATH`; nie łączy się z klastrem |

Wersja v4.x jest w porządku – polecenia z tego etapu działają w Helmie 3 i 4 tak samo.

### Krok 2. Helm widzi klaster

```bash
helm list -A
```

Przy pierwszym uruchomieniu w labie:

```
Error: kubernetes cluster unreachable: Get "http://localhost:8080/version": dial tcp 127.0.0.1:8080: connect: connection refused
```

`kubectl` na masterze to program k3s, który sam wie, że kubeconfig leży w
`/etc/rancher/k3s/k3s.yaml`. Helm szuka `~/.kube/config` – nie znalazł go i próbował starego
domyślnego adresu. Rozwiązanie – kopia z uprawnieniami tylko dla właściciela:

```bash
mkdir -p ~/.kube && install -m 600 /etc/rancher/k3s/k3s.yaml ~/.kube/config
ls -l ~/.kube/config && helm list -A
```

- `mkdir -p` – utwórz katalog, bez błędu, jeśli już jest.
- `install -m 600` – kopia czytelna tylko dla Ciebie: kubeconfig to klucz administratora klastra.

Wynik:

```
-rw------- 1 grzegorz grzegorz 2937 Oct 30 08:35 /home/grzegorz/.kube/config
NAME         NAMESPACE    REVISION  UPDATED                  STATUS    CHART                        APP VERSION
traefik      kube-system  1         2026-10-29 14:44:28 UTC  deployed  traefik-40.1.5+up40.1.0      v3.7.1
traefik-crd  kube-system  1         2026-10-29 14:44:15 UTC  deployed  traefik-crd-40.1.5+up40.1.0  v3.7.1
```

- `helm list -A` – release'y (zainstalowane kopie chartów) we wszystkich namespace'ach.
- Tych dwóch nie instalował administrator – zrobił to wbudowany w k3s helm-controller. Nie
  aktualizuj ich ręcznie: k3s nadpisze zmiany.
- Jak czytać kolumny i czym jest `traefik-crd` –
  [teoria, rozdziały 8, 11 i 12](teoria-kubernetes-helm.md#8-chart-values-i-release).
- Szczegóły problemu: [docs/08](08-problemy-administratora.md#kubectl-działa-a-helm-nie-widzi-klastra).

### Krok 3. Repozytorium chartów i podgląd instalacji

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm search repo kube-prometheus-stack
```

| Polecenie | Co robi |
|---|---|
| `helm repo add NAZWA URL` | zapisuje repozytorium pod krótką nazwą (jak dodanie źródła w `apt`) |
| `helm repo update` | pobiera świeży spis chartów (jak `apt update`) |
| `helm search repo` | szuka w pobranym spisie – nie łączy się z klastrem |

```
NAME                                        CHART VERSION  APP VERSION  DESCRIPTION
prometheus-community/kube-prometheus-stack  92.16.1        v0.94.2      kube-prometheus-stack collects Kubernetes manif...
```

**CHART VERSION** – wersja paczki (szablony i ustawienia), **APP VERSION** – wersja aplikacji
w środku (prometheus-operatora). Przypinamy wersję chartu **92.16.1**, żeby każda instalacja była
taka sama.

Zanim cokolwiek zainstalujesz – zobacz, co zainstalujesz:

```bash
helm show values prometheus-community/kube-prometheus-stack --version 92.16.1 | wc -l
cat ~/k3s-monitoring-lab/monitoring/kube-prometheus-stack-values.yaml
helm template monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 -n monitoring -f ~/k3s-monitoring-lab/monitoring/kube-prometheus-stack-values.yaml | grep '^kind:' | sort | uniq -c | sort -rn
```

| Polecenie | Co robi |
|---|---|
| `helm show values … \| wc -l` | ile linii mają domyślne ustawienia chartu (6340) |
| `cat …values.yaml` | nasze nadpisania – opis każdej linii: [docs/03a](03a-values-monitoringu.md) |
| `helm template` | wypełnia szablony i wypisuje gotowy YAML **bez wysyłania do klastra** |
| `grep '^kind:'` | wybiera linie z typem obiektu |
| `sort \| uniq -c \| sort -rn` | grupuje, liczy i sortuje od najliczniejszych |

Wynik i opis każdego typu obiektu:
[docs/03a – co powstanie w klastrze](03a-values-monitoringu.md#co-powstanie-w-klastrze--wynik-z-labu-chart-92161).
W skrócie: 30 zestawów reguł alertów, 29 dashboardów, 9 ServiceMonitorów, 3 Deploymenty,
DaemonSet node-exportera i obiekty `Prometheus` oraz `Alertmanager`, z których operator zbuduje pody.

### Krok 4. Instalacja

📸 **Snapshot przed instalacją** – np. `k3s-przed-monitoringiem`.

**4a. Wczytaj ustawienia z `lab.env`:**

```bash
cd ~/k3s-monitoring-lab && git pull && set -a && source lab.env && set +a
```

| Część | Znaczenie |
|---|---|
| `set -a` | od teraz każda ustawiona zmienna jest **eksportowana** – widzą ją programy uruchamiane z tej powłoki, np. `envsubst` |
| `source lab.env` | wykonaj plik w bieżącej powłoce – ustawia `GRAFANA_ADMIN_PASSWORD`, `HEALTHCHECKS_URL` itd. |
| `set +a` | wyłącz automatyczne eksportowanie |

**4b. Wypełnij luki w pliku values:**

```bash
umask 077 && envsubst '${GRAFANA_ADMIN_PASSWORD} ${HEALTHCHECKS_URL}' < monitoring/kube-prometheus-stack-values.yaml > /tmp/kps-values.yaml
grep -c '\${' /tmp/kps-values.yaml
```

| Część | Znaczenie |
|---|---|
| `umask 077` | nowe pliki powstają z uprawnieniami `600` – w pliku będzie hasło |
| `envsubst '…'` | zamień `${…}` na wartości – **tylko** tych dwóch zmiennych ([docs/03a, rozdział 3](03a-values-monitoringu.md#3-luki--i-envsubst)) |
| `<` / `>` | czytaj z pliku values, zapisz wynik do `/tmp/kps-values.yaml` |
| `grep -c '\${'` | policz linie, w których została luka – musi wyjść `0` |

**4c. Obserwacja – drugi terminal** (`ssh k3s-master`):

```bash
kubectl get pods -n monitoring -o wide -w
```

`-w` (watch) pokazuje na żywo każdą zmianę stanu podów, `-o wide` – także węzeł. Zanim instalacja
utworzy namespace, lista będzie pusta – wtedy uruchom polecenie jeszcze raz.

**4d. Instalacja – pierwszy terminal:**

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 -n monitoring --create-namespace -f /tmp/kps-values.yaml --wait --timeout 15m
```

| Część | Znaczenie |
|---|---|
| `upgrade --install` | zainstaluj, a jeśli już jest – zaktualizuj (idempotentnie) |
| `monitoring` | nazwa release'u |
| `prometheus-community/kube-prometheus-stack` | z jakiego chartu |
| `--version 92.16.1` | przypięta wersja chartu |
| `-n monitoring --create-namespace` | namespace `monitoring`, utworzony, jeśli go nie ma |
| `-f /tmp/kps-values.yaml` | nasze ustawienia z wypełnionymi lukami |
| `--wait` | czekaj, aż pody będą gotowe – nie tylko wysłane do klastra |
| `--timeout 15m` | ale nie dłużej niż 15 minut |

Pierwsza instalacja trwa kilka minut – workery pobierają obrazy. W drugim terminalu pody
przechodzą przez `Pending` → `ContainerCreating` → `Running`.

**4e. Usuń plik z hasłem:**

```bash
rm /tmp/kps-values.yaml
```

### Krok 5. Aplikacja demo i reguły alertów

```bash
kubectl apply -f ~/k3s-monitoring-lab/kubernetes/demo-app/
kubectl -n demo rollout status deployment/podinfo --timeout=180s
kubectl apply -f ~/k3s-monitoring-lab/kubernetes/monitoring/
kubectl -n demo get pods -o wide
```

| Polecenie | Co robi |
|---|---|
| `kubectl apply -f katalog/` | utwórz lub zaktualizuj wszystkie obiekty z plików w katalogu (w kolejności nazw: `00-namespace`, `10-deployment`, `20-service`, `30-ingress`) |
| `rollout status` | czekaj, aż wszystkie 3 repliki podinfo będą gotowe |
| `apply -f kubernetes/monitoring/` | ServiceMonitor (Prometheus zbiera metryki podinfo) i PrometheusRule (5 alertów labu) – obiekty typów z CRD, które obsługuje operator |

### Krok 6. Sprawdzenie w przeglądarce

| Adres | Co sprawdzić |
|---|---|
| `http://192.168.180.51:30300` | **Grafana** – login `admin`, hasło z `lab.env`; dashboardy w sekcji *Dashboards* |
| `http://192.168.180.51:30090` | **Prometheus** – *Status → Targets*: `serviceMonitor/demo/podinfo` w stanie **UP** |
| `http://192.168.180.51:30093` | **Alertmanager** – aktywny alert `Watchdog` (tak ma być) |
| `http://192.168.180.51:30898` | **podinfo** – strona aplikacji demo |

```bash
helm list -A
kubectl top nodes
```

Porównaj zużycie pamięci z wynikiem z kroku 0 – tyle kosztuje monitoring.

📸 **Snapshot** – np. `k3s-monitoring`.

## Instalacja skryptem

To samo, co kroki 1–5, robią dwa skrypty:

```bash
sudo ./scripts/04-install-monitoring.sh
sudo ./scripts/05-deploy-demo.sh
```

Skrypt `04` instaluje Helma, dodaje repozytorium, wypełnia luki przez `envsubst` w pliku
tymczasowym i uruchamia `helm upgrade --install`. Wersję chartu przypina zmienna
`KPS_CHART_VERSION` w `lab.env`. Uruchomiony po instalacji ręcznej niczego nie zepsuje –
`upgrade --install` jest idempotentny, Helm najwyżej podniesie numer rewizji.

## Co monitorujemy

**Węzły:** CPU, pamięć, dysk, sieć, status `Ready`, `DiskPressure`, `MemoryPressure`.

**Pody:** restarty, statusy `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`, `Pending`,
zużycie zasobów względem limitów.

**Obiekty:** czy Deployment ma wymaganą liczbę replik, zajętość wolumenów.

**Aplikacje:** cztery złote sygnały – opóźnienie, ruch, błędy, nasycenie.

## Szybka diagnostyka z terminala

```bash
kubectl top nodes
kubectl top pods -A
kubectl get events -A --sort-by=.lastTimestamp
kubectl -n demo describe pod <nazwa-poda>
kubectl -n demo logs <nazwa-poda> --previous
```

## Grafana

`http://<MASTER_IP>:30300`, login `admin`, hasło z `lab.env`. Warto zacząć od dashboardów:

- *Kubernetes / Compute Resources / Cluster*
- *Kubernetes / Compute Resources / Namespace (Pods)*
- *Node Exporter / Nodes*

## Własne alerty

Plik `kubernetes/monitoring/prometheusrule-lab.yaml`:

| Alert | Warunek |
|---|---|
| `PodRestartingTooOften` | więcej niż 3 restarty w 10 minut |
| `ContainerOOMKilled` | kontener zabity za przekroczenie limitu pamięci |
| `PodinfoDegraded` | mniej niż 3 dostępne repliki przez 2 minuty |
| `PodinfoDown` | brak dostępnych replik przez 1 minutę |
| `NodeMemoryHigh` | zużycie pamięci węzła powyżej 90% przez 5 minut |

Aktywne alerty: Prometheus → *Alerts* (`:30090`) lub Alertmanager (`:30093`).

## Sprawdzenie, czy Prometheus zbiera dane z aplikacji

Prometheus → *Status → Targets* – na liście powinien być `serviceMonitor/demo/podinfo` w stanie **UP**.
Przykładowe zapytanie PromQL:

```
sum(rate(http_request_duration_seconds_count{namespace="demo"}[5m]))
```
