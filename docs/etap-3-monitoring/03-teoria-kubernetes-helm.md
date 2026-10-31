# Kubernetes i Helm – jak to działa

Ten plik jest dla osoby, która **pierwszy raz** widzi Kubernetesa. Tłumaczy od zera pojęcia,
które pojawiają się w Etapie 3: węzeł, taint, kubeconfig, Helm, chart, values, release,
Traefik, Ingress, CRD i operator. Każde pojęcie jest pokazane na przykładzie z tego labu.

Polecenia do wpisania są w [przewodniku](../00-przewodnik.md), a ćwiczenia z kubectl
w [ćwiczenia z kubectl](../etap-2-k3s-ansible/05-cwiczenia-kubectl.md).

## Spis treści

1. [Kubernetes w jednym zdaniu](#1-kubernetes-w-jednym-zdaniu)
2. [Obiekty i YAML](#2-obiekty-i-yaml)
3. [Węzły: master, workery i maszyna monitoring](#3-węzły-master-workery-i-maszyna-monitoring)
4. [Taint i toleration – kto może stanąć na masterze](#4-taint-i-toleration--kto-może-stanąć-na-masterze)
5. [Zasoby węzłów i `kubectl top`](#5-zasoby-węzłów-i-kubectl-top)
6. [Kubeconfig – klucz do klastra](#6-kubeconfig--klucz-do-klastra)
7. [Helm – menedżer paczek](#7-helm--menedżer-paczek)
8. [Chart, values i release](#8-chart-values-i-release)
9. [Repozytorium chartów i wersje](#9-repozytorium-chartów-i-wersje)
10. [Jak dostać się do aplikacji: NodePort i Ingress](#10-jak-dostać-się-do-aplikacji-nodeport-i-ingress)
11. [Traefik – recepcja klastra](#11-traefik--recepcja-klastra)
12. [CRD – nowe słowa w słowniku Kubernetesa](#12-crd--nowe-słowa-w-słowniku-kubernetesa)
13. [Operator – program, który rozumie nowe słowa](#13-operator--program-który-rozumie-nowe-słowa)
14. [Jak to się składa w Etapie 3](#14-jak-to-się-składa-w-etapie-3)
15. [Słowniczek](#15-słowniczek)
16. [Ściągawka poleceń Helm](#16-ściągawka-poleceń-helm)
17. [Pytania, które mogą paść na rozmowie](#17-pytania-które-mogą-paść-na-rozmowie)

---

## 1. Kubernetes w jednym zdaniu

Kubernetes to **kierownik magazynu**. Mówisz mu, **co ma być** – na przykład „3 kopie aplikacji
nginx” – a on sam decyduje, **gdzie** to postawić (na którym workerze), i **pilnuje**, żeby tak
zostało. Gdy pod padnie, stawia nowy; gdy węzeł padnie, przenosi pody na inne.

To podejście nazywa się **deklaratywnym**: opisujesz stan docelowy, a nie kroki. Porównaj:

| Imperatywnie (jak skrypt Bash) | Deklaratywnie (jak Kubernetes) |
|---|---|
| „uruchom kontener, potem drugi, potem trzeci” | „mają być 3 kontenery” |
| gdy jeden padnie – nic się nie dzieje | gdy jeden padnie – Kubernetes stawia nowy |

Ansible z Etapu 2 działa podobnie: opisujesz stan, a moduł sprawdza, czy trzeba coś zmienić.

## 2. Obiekty i YAML

To, co mówisz kierownikowi, zapisujesz w plikach **YAML** jako **obiekty**. Każdy obiekt ma typ
(`kind`), nazwę i opis stanu (`spec`):

```yaml
apiVersion: apps/v1
kind: Deployment          # typ obiektu
metadata:
  name: nginx             # nazwa
spec:
  replicas: 3             # stan docelowy: 3 kopie
  ...
```

Najważniejsze typy, które znasz z [ćwiczeń](../etap-2-k3s-ansible/05-cwiczenia-kubectl.md):

| Typ | Rola |
|---|---|
| **Pod** | najmniejsza jednostka: jeden lub kilka kontenerów, które działają razem |
| **Deployment** | pilnuje liczby podów i robi aktualizacje |
| **Service** | stały adres dla grupy podów (pody zmieniają IP, Service – nie) |
| **DaemonSet** | po jednym podzie na każdym węźle |
| **Namespace** | „folder” na obiekty, np. `demo`, `monitoring`, `kube-system` |
| **Ingress** | reguła: ruch dla domeny X kieruj do Service Y |
| **Secret / ConfigMap** | hasła / ustawienia przekazywane do podów |

## 3. Węzły: master, workery i maszyna monitoring

**Węzeł (node)** to maszyna, na której Kubernetes może uruchamiać pody. Na każdym węźle działa
**kubelet** – agent, który dostaje polecenia od mastera i uruchamia kontenery.

```
$ kubectl get nodes
NAME           STATUS   ROLES           VERSION
k3s-master     Ready    control-plane   v1.36.5+k3s1
k3s-worker-1   Ready    worker          v1.36.5+k3s1
k3s-worker-2   Ready    worker          v1.36.5+k3s1
k3s-worker-3   Ready    worker          v1.36.5+k3s1
```

| Maszyna | Czy jest węzłem? | Rola |
|---|---|---|
| `k3s-master` | **tak** | „mózg” klastra: API, scheduler, baza danych klastra. Aplikacje na nim nie startują (rozdział 4) |
| `k3s-worker-1..3` | **tak** | tu działają aplikacje i monitoring z Etapu 3 |
| `monitoring` | **nie** | osobna maszyna poza klastrem: kontroler Ansible, a w Etapie 4 zewnętrzna Grafana i Uptime Kuma |

**Dlaczego monitoring stoi poza klastrem?** Prometheus i Grafana z Etapu 3 działają **wewnątrz**
klastra. Gdy klaster padnie, padną razem z nim i nie powiedzą, że jest awaria. Maszyna monitoring
stoi obok i dalej działa. Zasada: **monitoring nie może zależeć od tego, co monitoruje.**

## 4. Taint i toleration – kto może stanąć na masterze

W k3s master też jest węzłem – ma kubeleta i mógłby uruchamiać pody. W tym labie ma jednak
**taint**, czyli „znak zakazu wjazdu”:

```
$ kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints[*].key,EFFECT:.spec.taints[*].effect
NAME           TAINTS                                  EFFECT
k3s-master     node-role.kubernetes.io/control-plane   NoSchedule
k3s-worker-1   <none>                                  <none>
```

- **Taint** na węźle: „nie stawiaj tu podów” (`NoSchedule`).
- **Toleration** w podzie: „mam przepustkę na ten zakaz”.

Scheduler postawi pod na masterze tylko wtedy, gdy pod ma toleration. Mają je pody systemowe
(np. `coredns`, `metrics-server`) oraz DaemonSety, które muszą działać wszędzie.

Po co? Master to mózg klastra. Gdyby aplikacja zjadła na nim całą pamięć, padłby cały klaster.
Dlatego w firmach aplikacje działają tylko na workerach.

W Etapie 3:

| Komponent | Gdzie wyląduje |
|---|---|
| Prometheus, Grafana, Alertmanager, kube-state-metrics, operator | tylko na workerach |
| node-exporter (DaemonSet z toleration) | na wszystkich 4 węzłach, także na masterze |

## 5. Zasoby węzłów i `kubectl top`

```
$ kubectl top nodes
NAME           CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k3s-master     32m          1%       1319Mi          39%
k3s-worker-1   10m          0%       628Mi           11%
k3s-worker-2   11m          0%       631Mi           11%
k3s-worker-3   14m          0%       813Mi           13%
```

| Zapis | Znaczenie |
|---|---|
| `32m` | 32 **milicore'y** = 0,032 rdzenia; `1000m` = 1 rdzeń |
| `Mi`, `Gi` | mebibajty, gibibajty (potęgi 1024) – Kubernetes używa jednostek binarnych |
| `MEMORY(%)` | procent z pamięci **dostępnej dla podów** (allocatable), nie z całej maszyny |

Dane dostarcza **metrics-server** (pod w `kube-system`). Zaraz po starcie maszyny nie ma jeszcze
pomiarów i pojawia się błąd `Metrics API not available` – wystarczy odczekać 1–2 minuty.

Master zużywa najwięcej pamięci, choć nie ma aplikacji: proces `k3s server` to API, scheduler,
controller-manager i baza danych klastra w jednym. Przed instalacją monitoringu liczy się
**wolna pamięć workerów** – tam trafi Prometheus.

**requests i limits** – w YAML poda można zapisać:

```yaml
resources:
  requests:
    memory: 512Mi    # tyle scheduler rezerwuje; pod trafi na węzeł, który ma tyle wolnego
  limits:
    memory: 1536Mi   # tego pod nie może przekroczyć – inaczej zostanie zabity (OOMKilled)
```

## 6. Kubeconfig – klucz do klastra

**Kubeconfig** to plik, który mówi narzędziom (kubectl, Helm), **gdzie jest klaster** (adres API)
i **kim jesteś** (certyfikat). Kto ma ten plik, ten jest administratorem klastra.

| Plik | Kto go używa |
|---|---|
| `/etc/rancher/k3s/k3s.yaml` | k3s tworzy go przy instalacji; wbudowany w k3s `kubectl` czyta go automatycznie |
| `~/.kube/config` | standardowe miejsce, w którym szukają go **wszystkie inne** narzędzia, w tym Helm |

Na masterze `kubectl` to dowiązanie do programu k3s (`/usr/local/bin/kubectl -> k3s`), dlatego
działał od razu. Helm to osobny program – nie znalazł `~/.kube/config` i próbował starego
domyślnego adresu:

```
Error: kubernetes cluster unreachable: Get "http://localhost:8080/version": dial tcp 127.0.0.1:8080: connect: connection refused
```

Rozwiązanie – kopia z uprawnieniami tylko dla właściciela:

```bash
mkdir -p ~/.kube && install -m 600 /etc/rancher/k3s/k3s.yaml ~/.kube/config
```

> **Uwaga bezpieczeństwa.** W labie `/etc/rancher/k3s/k3s.yaml` ma uprawnienia `644` – każdy
> użytkownik mastera może go przeczytać i zostać administratorem klastra. W firmie byłby to błąd:
> kubeconfig ma uprawnienia `600`, a administratorzy pracują z własnego komputera z osobnym
> kubeconfigiem, zamiast logować się na mastera.

## 7. Helm – menedżer paczek

Na Ubuntu instalujesz program przez `apt install nginx` i nie piszesz ręcznie plików
konfiguracyjnych ani usług systemd – paczka ma to w sobie. **Helm to `apt` dla Kubernetesa.**

Bez Helma zainstalowanie Prometheusa z Grafaną i resztą wymagałoby napisania ręcznie **setek
plików YAML**: Deploymentów, Service'ów, uprawnień, konfiguracji, dashboardów. Z Helmem to jedno
polecenie.

| Ubuntu | Kubernetes |
|---|---|
| `apt` | `helm` |
| paczka `.deb` | **chart** |
| repozytorium apt | repozytorium chartów |
| `apt update` | `helm repo update` |
| `apt install` | `helm install` |
| zainstalowany program | **release** |
| Twoje ustawienia w `/etc/...` | **values** |

Helm **nie instaluje niczego na maszynie, na której go uruchamiasz**. Wysyła gotowe obiekty do
API klastra, a Kubernetes sam rozkłada pody na workery. Helm mógłby działać z dowolnej maszyny,
która ma kubeconfig – w labie używamy mastera, bo tam wszystko jest gotowe.

## 8. Chart, values i release

### Chart – paczka

Chart to **katalog z szablonami YAML i domyślnymi ustawieniami**:

```
kube-prometheus-stack/
├── Chart.yaml        ← nazwa, wersja, opis paczki
├── values.yaml       ← domyślne ustawienia (tysiące linii)
└── templates/        ← szablony YAML z lukami do wypełnienia
    ├── prometheus.yaml
    ├── grafana.yaml
    └── ...
```

W szablonach są **luki**:

```yaml
nodePort: {{ .Values.grafana.service.nodePort }}
```

### Values – Twoje wypełnienie

Plik [monitoring/kube-prometheus-stack-values.yaml](../../monitoring/kube-prometheus-stack-values.yaml)
**nadpisuje tylko to, co chcesz zmienić** – reszta zostaje domyślna:

```yaml
grafana:
  service:
    type: NodePort
    nodePort: 30300     # ← ta wartość trafi w lukę z szablonu
```

Helm bierze szablony, wstawia w luki wartości i wysyła gotowy YAML do Kubernetesa.

### Release – zainstalowana kopia

**Release** (liczba mnoga: release'y, czytaj „rilisy”) to **jedna zainstalowana w klastrze kopia
chartu, pod własną nazwą**.

Porównanie z grą komputerową:
- **chart** – płyta z grą w sklepie, każdy może ją kupić,
- **values** – Twoje ustawienia gry,
- **release** – gra **zainstalowana u Ciebie**, z Twoimi ustawieniami i zapisami.

Ten sam chart można zainstalować kilka razy pod różnymi nazwami – np. `monitoring-test`
i `monitoring-prod` – i będą to dwa niezależne release'y.

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack ...
#                      ^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#                      nazwa       z jakiego chartu
#                      release'u
```

Helm pamięta każdy release (trzyma go w klastrze jako Secret typu `helm.sh/release.v1`), dlatego
potrafi go później zaktualizować, cofnąć albo usunąć w całości.

### Jak czytać `helm list -A`

```
$ helm list -A
NAME         NAMESPACE    REVISION  UPDATED                  STATUS    CHART                        APP VERSION
traefik      kube-system  1         2026-10-29 14:44:28 UTC  deployed  traefik-40.1.5+up40.1.0      v3.7.1
traefik-crd  kube-system  1         2026-10-29 14:44:15 UTC  deployed  traefik-crd-40.1.5+up40.1.0  v3.7.1
```

| Kolumna | Znaczenie |
|---|---|
| NAME | nazwa release'u |
| NAMESPACE | gdzie stoją jego obiekty |
| REVISION | numer wersji instalacji: każdy `helm upgrade` podnosi go o 1, `helm rollback` wraca do wcześniejszego |
| UPDATED | kiedy ostatnio instalowano lub aktualizowano |
| STATUS | `deployed` – działa; inne: `failed`, `pending-install`, `superseded` |
| CHART | nazwa i wersja chartu; `+up40.1.0` – paczka Ranchera oparta na oryginalnym chartcie 40.1.0 |
| APP VERSION | wersja aplikacji w środku (tu Traefika) |

Tych dwóch release'ów nie instalował administrator – zrobił to wbudowany w k3s
**helm-controller** przy budowie klastra. Nie aktualizuj ich ręcznie przez `helm upgrade`: k3s
nadpisze zmiany przy restarcie. Ustawienia Traefika w k3s zmienia się plikiem `HelmChartConfig`.

## 9. Repozytorium chartów i wersje

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo kube-prometheus-stack
```

- `helm repo add NAZWA URL` – zapisuje repozytorium pod krótką nazwą (w
  `~/.config/helm/repositories.yaml`). Pod adresem leży `index.yaml` – spis chartów i wersji.
- `helm repo update` – pobiera świeże spisy (do `~/.cache/helm/`), jak `apt update`.
- `helm search repo` – przeszukuje pobrane spisy. **Nie łączy się z klastrem.**

Każdy chart ma **dwie** wersje:

| Wersja | Czego dotyczy |
|---|---|
| **CHART VERSION** | paczki Helm: szablonów i domyślnych ustawień; zmienia się często |
| **APP VERSION** | głównej aplikacji w środku (np. prometheus-operatora) |

Dobra praktyka: **przypinaj wersję chartu** (`--version`). Bez tego każda instalacja bierze
najnowszą wersję, która może zmienić zachowanie. W labie służy do tego zmienna
`KPS_CHART_VERSION` w `lab.env`. Wszystkie wersje pokazuje
`helm search repo kube-prometheus-stack --versions`.

## 10. Jak dostać się do aplikacji: NodePort i Ingress

Pody mają wewnętrzne adresy IP, których nie widać z Twojego komputera. Są dwa sposoby, żeby
wejść do aplikacji z zewnątrz:

| Sposób | Jak działa | Przykład w labie |
|---|---|---|
| **NodePort** | otwiera ten sam port (30000–32767) na **każdym** węźle | Grafana `:30300`, Prometheus `:30090`, nginx `:30317` z ćwiczeń |
| **Ingress** | jedno wejście (port 80/443), które **po nazwie domeny** kieruje ruch do właściwej aplikacji | `http://podinfo.lab.local` |

NodePort jest prosty, ale przy wielu aplikacjach trzeba pamiętać wiele numerów portów. Ingress
daje ładne adresy i jedno wejście dla wszystkich.

## 11. Traefik – recepcja klastra

Ingress to tylko **reguła** zapisana w YAML. Żeby ktoś ją wykonywał, potrzebny jest
**Ingress Controller** – program, który przyjmuje ruch i kieruje go według reguł. W k3s jest nim
domyślnie **Traefik** (w innych klastrach często spotkasz **ingress-nginx**).

Traefik to **reverse proxy** – działa jak **recepcja w biurowcu**:
- wszyscy wchodzą jednymi drzwiami (port 80),
- recepcjonista pyta „do kogo?” (nazwa domeny lub ścieżka w adresie),
- i kieruje do właściwego pokoju (Service → pod).

```
przeglądarka → podinfo.lab.local:80 → Traefik → Service podinfo → pod podinfo
              grafana.lab.local:80 → Traefik → Service grafana → pod grafana
```

Reguła dla aplikacji demo – [kubernetes/demo-app/30-ingress.yaml](../../kubernetes/demo-app/30-ingress.yaml):

```yaml
kind: Ingress
spec:
  ingressClassName: traefik      # tę regułę obsługuje Traefik
  rules:
    - host: podinfo.lab.local    # gdy ktoś pyta o tę domenę...
      http:
        paths:
          - path: /
            backend:
              service:
                name: podinfo    # ...wyślij go do tego Service
```

Pody `svclb-traefik` widoczne na każdym węźle to „drzwi” Traefika – otwierają porty 80 i 443
na każdej maszynie.

## 12. CRD – nowe słowa w słowniku Kubernetesa

Kubernetes zna z fabryki pewien zestaw typów obiektów: Pod, Deployment, Service, Ingress… To jego
**słownik**.

**CRD (Custom Resource Definition)** to **dopisanie nowego słowa do słownika**. Po instalacji CRD
można tworzyć obiekty nowego typu tak samo jak Deploymenty – przez YAML i `kubectl apply`.

Traefik potrafi więcej niż zwykły Ingress, więc dodaje własne typy, m.in.:
- `IngressRoute` – bardziej rozbudowana reguła kierowania ruchu,
- `Middleware` – np. logowanie hasłem, przekierowanie http→https, limit zapytań.

Dlatego k3s instaluje **dwa** release'y:

| Release | Co instaluje | Analogia |
|---|---|---|
| `traefik-crd` | tylko **definicje** nowych typów | najpierw dopisujesz słowo do słownika |
| `traefik` | **samą aplikację** Traefik | potem możesz go używać w zdaniach |

Kolejność ma znaczenie: nie da się utworzyć obiektu `IngressRoute`, zanim Kubernetes dowie się,
co to jest.

Sprawdzenie, jakie słowa dopisano do słownika:

```bash
kubectl get crd                 # wszystkie CRD w klastrze
kubectl api-resources | less    # wszystkie typy obiektów, wbudowane i dodane
```

## 13. Operator – program, który rozumie nowe słowa

Sam CRD to tylko słowo w słowniku – nic nie robi. Potrzebny jest program, który **czyta obiekty
nowego typu i wykonuje to, co opisują**. Takie połączenie – **CRD + program, który je obsługuje** –
nazywa się **operatorem**.

kube-prometheus-stack instaluje **prometheus-operator** i jego słowa:

| Typ (CRD) | Co znaczy |
|---|---|
| `Prometheus` | „ma działać Prometheus z takimi ustawieniami” |
| `Alertmanager` | „ma działać Alertmanager z takimi ustawieniami” |
| `ServiceMonitor` | „Prometheusie, zbieraj metryki z tej aplikacji” |
| `PrometheusRule` | „oto reguły alertów” |

Przykład z labu – [kubernetes/monitoring/servicemonitor-podinfo.yaml](../../kubernetes/monitoring/servicemonitor-podinfo.yaml):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor             # nowe słowo dodane przez operator
metadata:
  name: podinfo
  namespace: demo
spec:
  selector:
    matchLabels:
      app: podinfo               # znajdź Service z tą etykietą
  endpoints:
    - port: http
      path: /metrics             # i co 15 s pobieraj z niego metryki
      interval: 15s
```

Operator widzi nowy ServiceMonitor i sam dopisuje go do konfiguracji Prometheusa. Nie trzeba
ręcznie edytować pliku `prometheus.yml` ani restartować Prometheusa.

## 14. Jak to się składa w Etapie 3

```
helm upgrade --install monitoring ...       ← jedno polecenie
        │
        ├─ CRD: Prometheus, Alertmanager, ServiceMonitor, PrometheusRule, ...
        ├─ prometheus-operator            ← czyta obiekty nowych typów
        ├─ Prometheus                     ← zbiera metryki            (worker)
        ├─ Alertmanager                   ← wysyła powiadomienia      (worker)
        ├─ Grafana                        ← dashboardy, :30300        (worker)
        ├─ kube-state-metrics             ← stan obiektów Kubernetesa (worker)
        └─ node-exporter (DaemonSet)      ← metryki maszyn            (wszystkie 4 węzły)

kubectl apply -f kubernetes/demo-app/      ← aplikacja podinfo + Ingress (Traefik)
kubectl apply -f kubernetes/monitoring/    ← ServiceMonitor + PrometheusRule (dla operatora)
```

Ten sam monitoring zainstalujesz w labie na trzy sposoby:

| Sposób | Etap |
|---|---|
| ręcznie, polecenie po poleceniu | 3 |
| skryptem `scripts/04-install-monitoring.sh` | 3 (na koniec) |
| przez GitOps: Argo CD instaluje i pilnuje stanu z gita | 7 |

## 15. Słowniczek

| Pojęcie | Jednym zdaniem |
|---|---|
| **Kubernetes** | kierownik, który stawia i pilnuje aplikacji na węzłach |
| **węzeł (node)** | maszyna, na której mogą działać pody |
| **kubelet** | agent na węźle, który uruchamia kontenery |
| **control-plane / master** | „mózg” klastra: API, scheduler, baza danych klastra |
| **taint / toleration** | zakaz stawiania podów na węźle / przepustka na ten zakaz |
| **kubeconfig** | plik z adresem klastra i certyfikatem dostępu |
| **Helm** | `apt` dla Kubernetesa |
| **chart** | paczka: szablony YAML z lukami i domyślne ustawienia |
| **values** | Twoje ustawienia, które wypełniają luki |
| **release** | zainstalowana kopia chartu pod nazwą |
| **revision** | numer kolejnej instalacji lub aktualizacji release'u |
| **NodePort** | port otwarty na każdym węźle, prowadzący do aplikacji |
| **Ingress** | reguła: ruch dla domeny X kieruj do Service Y |
| **Ingress Controller / Traefik** | recepcja klastra, która wykonuje reguły Ingress |
| **CRD** | nowe słowo w słowniku Kubernetesa, czyli nowy typ obiektu |
| **operator** | CRD + program, który wykonuje to, co opisują obiekty nowego typu |

Na rozmowie: *"Helm is a package manager for Kubernetes – a chart is a templated package, values
customize it, and a release is an installed instance."*

## 16. Ściągawka poleceń Helm

```bash
# Repozytoria
helm repo add NAZWA URL                    # dodaj repozytorium
helm repo update                           # odśwież spisy chartów
helm repo list                             # lista repozytoriów
helm search repo SŁOWO                     # szukaj chartu
helm search repo CHART --versions          # wszystkie wersje chartu

# Zanim zainstalujesz
helm show values REPO/CHART > domyslne.yaml        # domyślne ustawienia chartu
helm template NAZWA REPO/CHART -f values.yaml      # pokaż gotowy YAML, nic nie instaluj

# Instalacja i aktualizacja
helm upgrade --install NAZWA REPO/CHART -n NS --create-namespace -f values.yaml
#   upgrade --install = zainstaluj, a jeśli już jest – zaktualizuj (idempotentnie)

# Stan
helm list -A                               # release'y we wszystkich namespace'ach
helm status NAZWA -n NS                    # stan release'u
helm history NAZWA -n NS                   # historia rewizji
helm get values NAZWA -n NS                # z jakimi values zainstalowano

# Cofanie i usuwanie
helm rollback NAZWA 1 -n NS                # wróć do rewizji 1
helm uninstall NAZWA -n NS                 # usuń wszystko, co założył release
```

## 17. Pytania, które mogą paść na rozmowie

Pytania z rozmów na stanowisko junior DevOps / administratora, z krótkimi odpowiedziami. Odpowiedź
na rozmowie powinna mieć 2–4 zdania i – jeśli się da – przykład z labu („w moim labie…”).
Nie ucz się ich na pamięć: zrozum i powiedz własnymi słowami.

### Podstawy – pytania, które padają prawie zawsze

**Czym jest pod, Deployment i Service?**
Pod to najmniejsza jednostka – jeden lub kilka kontenerów ze wspólnym adresem IP. Deployment
pilnuje, żeby działała określona liczba podów, i robi aktualizacje. Service daje grupie podów
stały adres i nazwę DNS, bo pody zmieniają IP przy każdym restarcie.

**Co się stanie, gdy usuniesz pod należący do Deploymentu?**
Od razu powstanie nowy. ReplicaSet porównuje liczbę podów, która ma być, z tą, która jest,
i wyrównuje różnicę. W labie nowy pod powstał w tej samej sekundzie ([rozwiązania ćwiczeń z kubectl, poziom 3](../etap-2-k3s-ansible/06-cwiczenia-kubectl-rozwiazania.md#poziom-3--samonaprawa)).

**Jakie znasz typy Service?**
ClusterIP – adres widoczny tylko w klastrze (domyślny). NodePort – port 30000–32767 otwarty na
każdym węźle. LoadBalancer – zewnętrzny adres IP, zwykle od chmury. W labie NodePort odpowiadał
także na węzłach, na których nie było poda.

**Czym różni się Deployment od DaemonSetu?**
Deployment uruchamia N kopii gdziekolwiek. DaemonSet – po jednej kopii na każdym węźle; używa się
go do agentów, które muszą być wszędzie, np. node-exporter albo zbieracz logów.

**Do czego służy namespace?**
To „folder” na obiekty: oddziela aplikacje, zespoły lub środowiska. Można na nim ustawić limity
zasobów i uprawnienia. W labie: `kube-system`, `monitoring`, `demo`.

**Czym jest master (control plane), a czym worker?**
Control plane to mózg klastra: API server, scheduler, controller-manager i baza danych stanu
(etcd, w k3s domyślnie SQLite). Workery uruchamiają aplikacje – działa na nich kubelet i runtime
kontenerów.

### Diagnostyka – sprawdzają, czy umiesz szukać przyczyny

**Pod nie startuje. Co robisz?**
`kubectl get pods` – status. `kubectl describe pod` – zdarzenia (Events) na dole zwykle mówią
dlaczego. `kubectl logs`, a gdy kontener się restartował – `kubectl logs --previous`. Do tego
`kubectl get events --sort-by=.lastTimestamp`.

**Co znaczą ImagePullBackOff, CrashLoopBackOff, OOMKilled, Pending?**
ImagePullBackOff – nie da się pobrać obrazu (zła nazwa, tag, brak dostępu). CrashLoopBackOff –
kontener startuje i od razu kończy się błędem, w kółko. OOMKilled – przekroczył limit pamięci
i został zabity. Pending – scheduler nie znalazł węzła: za mało zasobów, taint albo brak wolumenu.

**Aplikacja działa, ale Service nie odpowiada. Gdzie szukasz?**
Sprawdzam, czy selektor Service'u pasuje do etykiet podów: `kubectl get endpointslices` – jeśli
lista adresów jest pusta, selektor nie pasuje albo pody nie są gotowe (readiness probe). Potem
port docelowy (`targetPort`) i firewall na węzłach.

**Czym różnią się requests od limits?**
Requests to rezerwacja – scheduler stawia pod tylko tam, gdzie tyle jest wolne. Limits to sufit –
po przekroczeniu limitu pamięci kontener zostaje zabity (OOMKilled), a CPU jest dławione.

**Czym różni się liveness probe od readiness probe?**
Liveness – „czy żyjesz?”; gdy nie odpowiada, kubelet restartuje kontener. Readiness – „czy jesteś
gotowy przyjmować ruch?”; gdy nie, pod znika z Service'u, ale nie jest restartowany.

### Węzły i harmonogram

**Czym jest taint i toleration?**
Taint na węźle mówi schedulerowi „nie stawiaj tu podów”. Toleration w podzie to przepustka na
ten zakaz. Mój master ma taint `NoSchedule`, więc aplikacje działają tylko na workerach,
a node-exporter (DaemonSet z toleration) działa wszędzie.

**Jak bezpiecznie wyłączyć węzeł do konserwacji?**
`kubectl drain` – oznacza węzeł jako niedostępny i przenosi pody na inne węzły. Po konserwacji
`kubectl uncordon`. Ćwiczyłem to w labie ([rozwiązania ćwiczeń z kubectl, poziom 7](../etap-2-k3s-ansible/06-cwiczenia-kubectl-rozwiazania.md#poziom-7--konserwacja-węzła)).

**Jak zaktualizować aplikację bez przerwy w działaniu?**
Rolling update: Deployment wymienia pody po kolei, więc część zawsze działa. Gdy nowa wersja jest
zepsuta, `kubectl rollout undo`. W labie podałem nieistniejący obraz – stare pody działały dalej.

### Helm

**Czym jest Helm i po co go używać?**
To menedżer paczek dla Kubernetesa. Zamiast setek plików YAML instaluję jedną paczkę (chart)
i podaję tylko swoje ustawienia (values). Helm pamięta instalację, więc mogę ją zaktualizować,
cofnąć albo usunąć jednym poleceniem.

**Czym są chart, values i release?**
Chart – paczka: szablony YAML z lukami i domyślne ustawienia. Values – moje ustawienia, które
wypełniają luki. Release – zainstalowana kopia chartu pod nazwą; ten sam chart mogę zainstalować
kilka razy jako różne release'y.

**Czym różni się `helm install` od `helm upgrade --install`?**
`install` zwraca błąd, gdy release już istnieje. `upgrade --install` instaluje, a jeśli release
istnieje – aktualizuje. Dzięki temu polecenie jest idempotentne i nadaje się do skryptów i CI/CD.

**Jak cofnąć nieudaną aktualizację w Helmie?**
`helm history NAZWA` – lista rewizji, potem `helm rollback NAZWA <numer>`. Rollback tworzy nową
rewizję z ustawieniami starej.

**Czym różni się CHART VERSION od APP VERSION?**
Chart version to wersja paczki (szablonów i ustawień), app version – wersja aplikacji w środku.
Przy aktualizacji chartu aplikacja nie musi się zmienić i odwrotnie.

**Jak sprawdzić, co Helm zainstaluje, zanim to zrobisz?**
`helm template` – pokazuje gotowy YAML bez instalacji. `helm show values` – domyślne ustawienia
chartu. `helm upgrade --install --dry-run` – symulacja na klastrze.

**Gdzie Helm przechowuje informacje o release'ach?**
W klastrze, jako Secrety typu `helm.sh/release.v1` w namespace release'u. Helm 3 i nowsze nie
mają już serwera po stronie klastra (Tiller z Helma 2 usunięto).

### Ruch z zewnątrz

**Czym różni się Ingress od Service typu NodePort?**
NodePort otwiera osobny port na każdym węźle dla każdej aplikacji. Ingress to jedno wejście
(80/443), które po nazwie domeny lub ścieżce kieruje ruch do właściwej aplikacji, i może
obsługiwać HTTPS.

**Czym jest Ingress Controller? Dlaczego sam obiekt Ingress nie wystarcza?**
Ingress to tylko reguła. Ingress Controller to program, który przyjmuje ruch i wykonuje reguły –
np. Traefik (domyślny w k3s) albo ingress-nginx. Bez kontrolera reguły Ingress nic nie robią.

### Rozszerzanie Kubernetesa

**Czym jest CRD?**
Custom Resource Definition – dodaje do API Kubernetesa nowy typ obiektu. Potem można tworzyć
obiekty tego typu przez YAML i `kubectl apply`, tak jak Deploymenty.

**Czym jest operator?**
To CRD plus program (kontroler), który czyta obiekty nowego typu i doprowadza klaster do opisanego
stanu. Przykład z labu: prometheus-operator widzi obiekt ServiceMonitor i sam dopisuje aplikację
do konfiguracji Prometheusa.

### Dostęp i bezpieczeństwo

**Czym jest kubeconfig i jak go chronić?**
Plik z adresem API klastra i certyfikatem użytkownika. Kto go ma, ma dostęp do klastra, więc
uprawnienia `600` i nigdy w repozytorium. W firmie każdy użytkownik ma własny kubeconfig
z ograniczonymi uprawnieniami (RBAC), a nie certyfikat administratora.

**Czym jest RBAC?**
Role-Based Access Control – uprawnienia w Kubernetesie. Role (lub ClusterRole) mówi, co wolno
robić z jakimi obiektami, a RoleBinding przypisuje ją użytkownikowi lub ServiceAccountowi.
Zasada najmniejszych uprawnień: tylko to, co potrzebne.

**Jak przechowywać hasła w Kubernetesie?**
W obiektach Secret – ale to tylko base64, nie szyfrowanie. W produkcji: szyfrowanie Secretów
w etcd, RBAC ograniczające odczyt i zewnętrzny sejf (np. Vault, Sealed Secrets, External
Secrets). W labie hasło do Grafany jest w `lab.env`, który nie trafia do gita.

### Pytania-pułapki

**„Czy k3s to prawdziwy Kubernetes?”**
Tak – to certyfikowana dystrybucja Kubernetesa (przechodzi testy zgodności CNCF). Jest lżejsza:
jeden plik binarny, domyślnie SQLite zamiast etcd, wbudowane Traefik i metrics-server. Polecenia
kubectl i manifesty są takie same jak w dużych klastrach.

**„Co się stanie, gdy padnie master w twoim labie?”**
Aplikacje na workerach działają dalej, ale nie da się nic zmienić: nie zadziała kubectl, nie
powstaną nowe pody, a padnięty pod nie zostanie odtworzony. Dlatego w produkcji control plane ma
3 węzły (HA). W labie jest jeden master – świadomie, dla prostoty.

**„Dlaczego masz monitoring poza klastrem?”**
Bo monitoring w klastrze pada razem z klastrem. Zewnętrzna maszyna i dead man's switch informują,
że cały klaster przestał działać.

**„Czy kubectl wystarczy, żeby zarządzać klastrem w firmie?”**
Do diagnostyki tak, ale zmiany robi się deklaratywnie: pliki YAML lub charty w gicie i wdrożenie
przez CI/CD albo GitOps (Argo CD). Wtedy każda zmiana ma historię i przegląd – to plan Etapu 7.

## Dalej

- Etap 3 krok po kroku: [docs/00-przewodnik.md](../00-przewodnik.md), opis monitoringu: [docs/etap-3-monitoring/01-instalacja-monitoringu.md](01-instalacja-monitoringu.md)
- Ćwiczenia z kubectl: [docs/etap-2-k3s-ansible/05-cwiczenia-kubectl.md](../etap-2-k3s-ansible/05-cwiczenia-kubectl.md)
- Problemy, które wystąpiły w labie: [docs/problemy-ogolne.md](../problemy-ogolne.md)
