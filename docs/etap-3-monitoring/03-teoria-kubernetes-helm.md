# Kubernetes i Helm – jak to działa

Ten plik jest dla osoby, która **pierwszy raz** widzi Kubernetesa. Tłumaczy od zera pojęcia,
które pojawiają się w Etapie 3: etykiety i selektory, ConfigMap i Secret, pamięć trwała (PVC, CSI, Ceph), węzeł, taint, kubeconfig, Helm, chart, values, release,
Traefik, Ingress, CRD i operator. Każde pojęcie jest pokazane na przykładzie z tego labu.

Polecenia do wpisania są w [przewodniku](../00-przewodnik.md), a ćwiczenia z kubectl
w [ćwiczenia z kubectl](../etap-2-k3s-ansible/05-cwiczenia-kubectl.md).

## Spis treści

1. [Kubernetes w jednym zdaniu](#1-kubernetes-w-jednym-zdaniu)
2. [Obiekty i YAML](#2-obiekty-i-yaml)
3. [Etykiety i selektory – jak obiekty się znajdują](#3-etykiety-i-selektory--jak-obiekty-się-znajdują)
4. [ConfigMap i Secret – ustawienia poza obrazem](#4-configmap-i-secret--ustawienia-poza-obrazem)
5. [Pamięć trwała – w labie i w produkcji](#5-pamięć-trwała--w-labie-i-w-produkcji)
6. [Węzły: master, workery i maszyna monitoring](#6-węzły-master-workery-i-maszyna-monitoring)
7. [Taint i toleration – kto może stanąć na masterze](#7-taint-i-toleration--kto-może-stanąć-na-masterze)
8. [Zasoby węzłów i `kubectl top`](#8-zasoby-węzłów-i-kubectl-top)
9. [Kubeconfig – klucz do klastra](#9-kubeconfig--klucz-do-klastra)
10. [Helm – menedżer paczek](#10-helm--menedżer-paczek)
11. [Chart, values i release](#11-chart-values-i-release)
12. [Repozytorium chartów i wersje](#12-repozytorium-chartów-i-wersje)
13. [Jak dostać się do aplikacji: NodePort i Ingress](#13-jak-dostać-się-do-aplikacji-nodeport-i-ingress)
14. [Traefik – recepcja klastra](#14-traefik--recepcja-klastra)
15. [CRD – nowe słowa w słowniku Kubernetesa](#15-crd--nowe-słowa-w-słowniku-kubernetesa)
16. [Operator – program, który rozumie nowe słowa](#16-operator--program-który-rozumie-nowe-słowa)
17. [Jak to się składa w Etapie 3](#17-jak-to-się-składa-w-etapie-3)
18. [Słowniczek](#18-słowniczek)
19. [Ściągawka poleceń Helm](#19-ściągawka-poleceń-helm)
20. [Pytania, które mogą paść na rozmowie](#20-pytania-które-mogą-paść-na-rozmowie)

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

## 3. Etykiety i selektory – jak obiekty się znajdują

**Etykieta (label)** to para `klucz=wartość` przyklejona do obiektu, jak naklejka na pudle
w magazynie: `app=sklep`, `tier=frontend`, `team=blue`. Sama nic nie robi. Ważne jest to, że
**inne obiekty szukają po etykietach**, a nie po nazwach.

**Selektor** to zapytanie „daj mi wszystko z takimi naklejkami”. Tak działa pół Kubernetesa:

| Kto szuka | Czego | Przykład z labu |
|---|---|---|
| **Service** | podów, do których wysłać ruch | Service `podinfo` ma `selector: {app: podinfo}` |
| **Deployment / ReplicaSet** | podów, które „są jego” i których ma pilnować liczby | `selector.matchLabels: {app: hello-lab}` |
| **ServiceMonitor** (Prometheus) | Service'ów, z których zbierać metryki | [rozdział 16](#16-operator--program-który-rozumie-nowe-słowa) |
| **nodeSelector** w podzie | węzłów, na których może stanąć | `kubernetes.io/hostname=k3s-worker-1` |
| **Ty** w `kubectl` | obiektów do pokazania lub usunięcia | `kubectl get pods -l tier=backend` |

Etykieta to nie nazwa: nazwa jest jedna i unikalna, a etykiet obiekt może mieć wiele i wiele
obiektów może mieć tę samą. Dzięki temu Service nie musi znać nazw podów, które co chwilę się zmieniają
(`podinfo-c9cdb7df5-j9jkm`) – wystarczy, że każdy nowy pod dostaje naklejkę `app=podinfo`.

### Etykiety w praktyce – wyniki z labu

Trzy pody z różnymi naklejkami (namespace `teoria`, usunięty po pokazie):

```
$ kubectl -n teoria run sklep-www   --image=192.168.180.54:5000/hello-lab:1.0 --labels="app=sklep,tier=frontend,team=blue"
$ kubectl -n teoria run sklep-api   --image=... --labels="app=sklep,tier=backend,team=green"
$ kubectl -n teoria run raporty-api --image=... --labels="app=raporty,tier=backend,team=yellow"

$ kubectl -n teoria get pods --show-labels
NAME          READY   STATUS    RESTARTS   AGE   LABELS
raporty-api   1/1     Running   0          1s    app=raporty,team=yellow,tier=backend
sklep-api     1/1     Running   0          1s    app=sklep,team=green,tier=backend
sklep-www     1/1     Running   0          2s    app=sklep,team=blue,tier=frontend
```

Wybieranie selektorem (`-l` to skrót od `--selector`):

| Polecenie | Znaczenie | Wynik w labie |
|---|---|---|
| `-l tier=backend` | równa się | `raporty-api`, `sklep-api` |
| `-l tier=backend,team=green` | przecinek = **i** (oba warunki) | `sklep-api` |
| `-l 'team!=blue'` | różne od | `raporty-api`, `sklep-api` |
| `-l 'team in (blue,yellow)'` | jedna z wartości (= **lub**) | `raporty-api`, `sklep-www` |
| `-l 'app=sklep,tier notin (frontend)'` | żadna z wartości | `sklep-api` |
| `-l team` | ma etykietę, wartość dowolna | wszystkie trzy |
| `-l '!env'` | **nie** ma etykiety | wszystkie trzy (po usunięciu `env` z `sklep-www`) |

Selektory z `in`, `notin`, `!=` i `!` zawsze bierz w apostrofy `'…'` – inaczej bash potraktuje
nawiasy i wykrzyknik po swojemu.

Etykiety jako kolumny zamiast długiego `--show-labels`:

```
$ kubectl -n teoria get pods -L app,team
NAME          READY   STATUS    RESTARTS   AGE   APP       TEAM
raporty-api   1/1     Running   0          1s    raporty   yellow
sklep-api     1/1     Running   0          1s    sklep     green
sklep-www     1/1     Running   0          2s    sklep     blue
```

Dodawanie, zmiana i usuwanie etykiet:

```
$ kubectl -n teoria label pod sklep-www env=prod                  # dodaj
pod/sklep-www labeled
$ kubectl -n teoria label pod sklep-www team=red                  # zmień – bez zgody nie wolno
error: 'team' already has a value (blue), and --overwrite is false
$ kubectl -n teoria label pod sklep-www team=red --overwrite      # zmień
pod/sklep-www labeled
$ kubectl -n teoria label pod sklep-www env-                      # usuń: klucz z minusem
pod/sklep-www unlabeled
$ kubectl -n teoria delete pods -l app=raporty                    # usuń wszystko z etykietą
pod "raporty-api" deleted from teoria namespace
```

⚠️ `kubectl delete pods -l …` usuwa **wszystko**, co pasuje. Najpierw `get` z tym samym `-l`,
potem `delete`.

### Pułapka: zmiana etykiety „zabiera” pod Deploymentowi

ReplicaSet liczy pody **po etykietach**. Zmień etykietę poda, a ReplicaSet uzna, że poda ubyło,
i dorobi nowy. Stary pod działa dalej, ale już nikt go nie pilnuje (sierota):

```
$ kubectl -n teoria label pod/hello-5f7f8fb76f-9mwf4 app=serwis --overwrite
$ kubectl -n teoria get pods -L app
NAME                     READY   STATUS    RESTARTS   AGE   APP
hello-5f7f8fb76f-9mwf4   1/1     Running   0          14s   serwis    ← sierota, bez właściciela
hello-5f7f8fb76f-fwgm5   1/1     Running   0          4s    hello     ← nowy, dorobiony przez ReplicaSet
```

To ma też dobrą stronę: tak **izoluje się chory pod do diagnozy**. Po zmianie etykiety znika
z Service (nie dostaje ruchu), Deployment stawia zdrowy zamiennik, a Ty spokojnie oglądasz
chory pod przez `kubectl exec` i `logs`.

To samo w drugą stronę: literówka w selektorze Service (`app: wep` zamiast `web`) = Service bez
endpointów. Diagnoza w [Etapie 5](../etap-5-scenariusze-awarii/02-typowe-awarie-kubernetesa.md#310-service-nie-działa--brak-endpointów).

### Etykiety, które dodaje sam Kubernetes

```
$ kubectl get node k3s-worker-1 --show-labels      # fragment
kubernetes.io/arch=amd64
kubernetes.io/hostname=k3s-worker-1
kubernetes.io/os=linux
node-role.kubernetes.io/worker=worker

$ kubectl -n demo get pods --show-labels
NAME                      ...   LABELS
podinfo-c9cdb7df5-j9jkm   ...   app=podinfo,pod-template-hash=c9cdb7df5
```

`pod-template-hash` dokleja Deployment – tak odróżnia pody starej i nowej wersji przy aktualizacji.
Etykiety węzłów wykorzystasz w `nodeSelector` (np. „tylko na `kubernetes.io/arch=amd64`”).

Zalecane etykiety w firmach: `app.kubernetes.io/name`, `app.kubernetes.io/instance`,
`app.kubernetes.io/version`, `app.kubernetes.io/part-of` – tak oznacza swoje obiekty np. chart
kube-prometheus-stack.

### Etykieta a adnotacja

| | Etykieta (`labels`) | Adnotacja (`annotations`) |
|---|---|---|
| Do czego | **wyszukiwanie i grupowanie** – selektory | **notatki** dla ludzi i narzędzi |
| Można szukać po niej `-l`? | tak | nie |
| Wartość | krótka (do 63 znaków, litery, cyfry, `-_.`) | dowolny tekst, nawet JSON |
| Przykład | `app=podinfo` | `kubernetes.io/change-cause: "aktualizacja do 6.5"` |

## 4. ConfigMap i Secret – ustawienia poza obrazem

Obraz powinien być **jeden** dla wszystkich środowisk: test i produkcja różnią się tylko
ustawieniami (adres bazy, kolor, poziom logów). Ustawienia nie trafiają więc do obrazu, tylko do:

- **ConfigMap** – zwykłe ustawienia, jawne,
- **Secret** – hasła, tokeny, klucze.

Analogia: obraz to fabrycznie nowy telewizor, a ConfigMap to kartka z ustawieniami, którą
dokładasz w każdym mieszkaniu. Telewizor ten sam, ustawienia inne.

### Tworzenie ConfigMapy

```
$ kubectl -n teoria create configmap hello-config \
    --from-literal=APP_COLOR=#c53030 --from-literal=APP_VERSION=cm-1 \
    --from-file=powitanie.txt
configmap/hello-config created

$ kubectl -n teoria get configmap hello-config -o yaml
apiVersion: v1
data:
  APP_COLOR: '#c53030'
  APP_VERSION: cm-1
  powitanie.txt: |
    Witaj w labie k3s!
kind: ConfigMap
```

- `--from-literal=KLUCZ=wartość` – jedno ustawienie,
- `--from-file=plik` – cały plik; klucz = nazwa pliku, wartość = jego treść.

W gicie trzymasz to samo jako YAML (`kind: ConfigMap`, sekcja `data:`) i wdrażasz przez `kubectl apply`.

### Dwa sposoby podania ConfigMapy do poda

```yaml
spec:
  containers:
    - name: hello
      image: 192.168.180.54:5000/hello-lab:1.0
      envFrom:                      # 1) każdy klucz → zmienna środowiskowa
        - configMapRef:
            name: hello-config
      volumeMounts:                 # 2) każdy klucz → plik w katalogu
        - name: konfiguracja
          mountPath: /etc/hello
  volumes:
    - name: konfiguracja
      configMap:
        name: hello-config
```

Wynik w podzie:

```
$ kubectl -n teoria exec deploy/hello -- env | grep APP_
APP_COLOR=#c53030
APP_VERSION=cm-1
$ kubectl -n teoria exec deploy/hello -- ls /etc/hello
APP_COLOR
APP_VERSION
powitanie.txt
$ kubectl -n teoria exec deploy/hello -- cat /etc/hello/powitanie.txt
Witaj w labie k3s!
```

Aplikacja [hello-lab](../../apps/hello-lab/app.py) czyta `APP_VERSION` ze zmiennej, więc odpowiada
`{"app": "hello-lab", "version": "cm-1", ...}` – ten sam obraz, inna wersja w odpowiedzi.

Zamiast `envFrom` (wszystkie klucze) można wziąć jeden klucz:
`env: - name: KOLOR  valueFrom: configMapKeyRef: {name: hello-config, key: APP_COLOR}`.

### Co się dzieje po zmianie ConfigMapy – ważne na rozmowie

```
12:32:51 $ kubectl -n teoria patch configmap hello-config -p '{"data":{"APP_VERSION":"cm-2"}}'
         $ kubectl -n teoria exec deploy/hello -- env | grep APP_VERSION
         APP_VERSION=cm-1                     ← zmienna: bez zmian
12:34:08 $ kubectl -n teoria exec deploy/hello -- cat /etc/hello/APP_VERSION
         cm-2                                 ← plik: zmienił się sam, po 77 s
         $ kubectl -n teoria rollout restart deploy/hello
         $ kubectl -n teoria exec deploy/hello -- env | grep APP_VERSION
         APP_VERSION=cm-2                     ← zmienna: dopiero w nowym podzie
```

| Sposób | Po zmianie ConfigMapy |
|---|---|
| zmienna środowiskowa (`env`, `envFrom`) | **nie zmienia się** – zmienne ustawia się raz, przy starcie kontenera. Potrzebny restart: `kubectl rollout restart deploy/…` |
| plik z wolumenu | zmienia się sam po ok. 1–2 min (kubelet sprawdza okresowo), ale aplikacja musi plik **przeczytać ponownie** |
| plik z `subPath` | **nie zmienia się** nigdy – pułapka |

Dlatego w firmach po zmianie konfiguracji robi się `rollout restart`, a Helm często dokleja do
poda adnotację z sumą kontrolną ConfigMapy – zmiana ustawień = zmiana sumy = nowe pody.

Brak ConfigMapy albo klucza, do którego odwołuje się pod = pod w stanie
`CreateContainerConfigError` ([Etap 5](../etap-5-scenariusze-awarii/02-typowe-awarie-kubernetesa.md#36-createcontainerconfigerror--brak-secretu-lub-configmapy)).

### Secret – prawie to samo, ale na hasła

Secret tworzy się i podaje do poda tak samo (`kubectl create secret generic`, `secretRef`,
`secretKeyRef`, wolumen `secret:`). Różnica w zapisie:

```
$ kubectl -n teoria create secret generic baza --from-literal=haslo=Lab123!
secret/baza created
$ kubectl -n teoria get secret baza -o jsonpath='{.data.haslo}'
TGFiMTIzIQ==
$ kubectl -n teoria get secret baza -o jsonpath='{.data.haslo}' | base64 -d
Lab123!
```

⚠️ **base64 to nie szyfrowanie**, tylko zapis. Każdy, kto może czytać Secrety, odczyta hasło
jednym poleceniem. Secret chronią: uprawnienia RBAC (kto może `get secrets`), szyfrowanie bazy
klastra (etcd) i to, że **nie trafia do gita** w jawnej postaci. W gicie: Sealed Secrets, SOPS
albo zewnętrzny sejf (Vault) – podobnie jak Ansible Vault w Etapie 2.

W tym labie Secretem jest np. hasło Grafany: chart zrobił z `adminPassword` Secret
`monitoring-grafana`, a pod czyta go przez `secretKeyRef` (`kubectl -n monitoring get deploy
monitoring-grafana -o yaml | grep -A3 secretKeyRef`).

| | ConfigMap | Secret |
|---|---|---|
| Na co | ustawienia | hasła, tokeny, certyfikaty |
| Zapis w `-o yaml` | jawny tekst | base64 |
| Limit rozmiaru | 1 MiB | 1 MiB |
| W gicie | tak, zwykły YAML | nie wprost – zaszyfrowany (Sealed Secrets, SOPS) |
| Gdzie w labie | 25 dashboardów Grafany (chart), [kubernetes/](../../kubernetes/) | hasło Grafany, `lab.env` → Secret |

## 5. Pamięć trwała – w labie i w produkcji

Pod jest jednorazowy: znika, a nowy powstaje gdzie indziej. Dane, które mają przetrwać, muszą więc
leżeć **poza podem**. Kubernetes rozdziela to na trzy role (wdrożenie w labie krok po kroku:
[trwałe dane monitoringu](08-trwale-dane.md)):

| Rola | Kto ją pełni | Analogia |
|---|---|---|
| **PVC** – wniosek | aplikacja: „potrzebuję 10Gi, tryb RWO, klasa `fast-ssd`” | wniosek o mieszkanie |
| **StorageClass** – rodzaj pamięci | administrator: jaki system dyskowy, jakie parametry | spółdzielnia, która je przydziela |
| **PV** – konkretny dysk | tworzony automatycznie przez sterownik | przydzielone mieszkanie |

Aplikacja **nie wie**, skąd jest dysk. Ten sam YAML z PVC działa w labie (`local-path`),
w AWS (EBS) i na Cephie – zmienia się tylko `storageClassName`.

### Na którym węźle powstaje dysk – decyduje scheduler, nie PV

Przy `WaitForFirstConsumer` (local-path) kolejność jest odwrotna, niż się wydaje: najpierw
**scheduler wybiera węzeł dla poda**, a dopiero potem provisioner zakłada dysk na tym węźle.
Od tej chwili dysk przyciąga pod: PV ma `nodeAffinity`, więc każdy kolejny pod z tym PVC
trafi tylko na ten węzeł.

Scheduler wybiera węzeł w dwóch krokach:

| Krok | Co robi | Przykłady |
|---|---|---|
| **1. Filtrowanie** | odrzuca węzły, na których pod **nie może** stanąć | za mało wolnych zasobów względem `requests`, taint bez tolerancji (master), niepasujący `nodeSelector` / affinity, PV przypięty do innego węzła, węzeł `NotReady` lub `cordon` |
| **2. Punktacja** | ocenia pozostałe węzły 0–100 kilkoma wtyczkami i bierze najwyższy wynik; remis = losowanie | **najmniej zajęty** węzeł (suma `requests`), **zrównoważone** CPU i pamięć, **rozproszenie** podów tego samego Deploymentu/Service na różne węzły, **obraz już pobrany** na węźle, preferencje affinity |

Stan workerów w labie 03.11.2026 (`kubectl describe node … | grep -A5 "Allocated resources"`):

| Węzeł | CPU requests | Pamięć requests | Pody |
|---|---|---|---|
| k3s-worker-1 | 10m (0%) | 232Mi (4%) | 6 |
| k3s-worker-2 | 250m (12%) | 576Mi (10%) | 11 |
| k3s-worker-3 | 110m (5%) | 160Mi (2%) | 8 |

Worker-2 jest najbardziej zajęty (Prometheus rezerwuje 200m CPU i 512Mi), więc nowe pody
trafiały głównie na worker-1 i worker-3: `notatnik` z ćwiczeń i Grafana z Alertmanagerem
na worker-1, `hello` na worker-3. Punktacja liczy się od nowa przy każdym podzie, dlatego wynik
bywa różny, a przy zbliżonych węzłach praktycznie nie do zgadnięcia.

Gdy chcesz **zdecydować sam**: `nodeSelector` (np. `kubernetes.io/hostname: k3s-worker-2`),
`nodeAffinity` (twardo lub „preferuj”) albo, przy local-path, ścieżka per węzeł w `local-path-config`.

### CSI – wtyczka do systemu dyskowego

Kubernetes sam nie umie tworzyć dysków. Robi to **sterownik CSI** (Container Storage Interface) –
osobny program od producenta pamięci, instalowany w klastrze (zwykle Helmem). Działa jak
sterownik drukarki: Kubernetes mówi „utwórz dysk 10Gi i podłącz go do węzła X”, a sterownik
wie, jak to zrobić w konkretnym systemie.

```
 PVC ──▶ StorageClass ──▶ sterownik CSI ──▶ system dyskowy (EBS / Ceph / macierz / vSphere)
                               │                     │
                               │    ① utwórz dysk ◀──┘
                               └──▶ ② podłącz do węzła, na którym jest pod
                                    ③ kubelet montuje go w kontenerze
```

Pod się przenosi → sterownik **odłącza** dysk od starego węzła i **podłącza** do nowego.
Tego `local-path` nie umie – stąd przywiązanie do jednego węzła w labie.

### Co spotkasz w firmach

| Gdzie działa klaster | Typowa pamięć | Jak działa |
|---|---|---|
| **chmura** (AWS, Azure, GCP) | EBS, Azure Disk, Persistent Disk | dysk sieciowy w chmurze; CSI zakłada go przez API chmury. Najprostsze – często już skonfigurowane jako domyślna klasa |
| **własna serwerownia, VMware** | **vSphere CSI** | dysk to plik `.vmdk` w datastore vSphere, dopinany do maszyny wirtualnej węzła – jak dodanie dysku w VMware Workstation, tylko automatycznie |
| **własna serwerownia, sprzęt** | **Ceph** (przez operatora **Rook**) | dyski z wielu serwerów łączone w jedną pulę; każdy blok danych w 3 kopiach na różnych maszynach |
| | **Longhorn** | prostszy od Cepha; kopie dysku na kilku węzłach klastra. Popularny z k3s (ten sam producent – SUSE/Rancher) |
| | **macierz dyskowa** (NetApp, Pure Storage, Dell) | firmowa macierz z własnym sterownikiem CSI |
| | **NFS** | zwykły serwer plików; prosty, ale wolny i słaby pod bazy danych |
| **bazy o dużej wydajności** | **lokalne dyski NVMe** (Local PV) | najszybsze, ale przywiązane do węzła jak `local-path`; kopie robi sama baza (replikacja PostgreSQL, Kafka) |

### Ceph – najczęściej wymieniany on-premise

Ceph to rozproszony system pamięci: kilka serwerów z dyskami tworzy jedną dużą, odporną pulę.

- Każdy kawałek danych zapisany jest w **3 kopiach na 3 różnych serwerach**. Padnie serwer –
  dane są na dwóch pozostałych, a Ceph sam odtwarza trzecią kopię.
- Daje trzy rodzaje pamięci naraz:

| Rodzaj Cepha | Co to jest | W Kubernetesie |
|---|---|---|
| **RBD** (blokowy) | „wirtualny dysk” | PVC w trybie RWO – bazy danych, Prometheus |
| **CephFS** (plikowy) | wspólny katalog sieciowy | PVC w trybie **RWX** – wiele podów na różnych węzłach pisze naraz |
| **RGW** (obiektowy) | magazyn zgodny z S3 | kopie zapasowe, długa historia metryk (Thanos, Mimir) |

- W Kubernetesie instaluje się go operatorem **Rook** (`rook-ceph`) – tak jak operator Prometheusa
  w Etapie 3: opisujesz klaster Cepha obiektem, operator resztę robi sam.
- Wymaga: min. 3 węzłów z **osobnymi, pustymi dyskami**, szybkiej sieci (10 Gb/s) i sporo pamięci.
  To duży system – w firmach często ma osobny zespół.

### Tryby dostępu (`accessModes`)

| Tryb | Znaczenie | Kto daje |
|---|---|---|
| `ReadWriteOnce` (RWO) | zapis z jednego węzła naraz | prawie wszystko: EBS, RBD, vSphere, local-path |
| `ReadWriteMany` (RWX) | zapis z wielu węzłów naraz | pamięć plikowa: CephFS, NFS, EFS, Azure Files |
| `ReadOnlyMany` (ROX) | odczyt z wielu węzłów | jak wyżej |
| `ReadWriteOncePod` | tylko jeden **pod** w całym klastrze | nowe sterowniki CSI |

### Co jeszcze ustawia się w produkcji

| Ustawienie | Po co |
|---|---|
| kilka StorageClass, np. `fast-ssd`, `standard`, `archive` | różne ceny i prędkości dla różnych aplikacji |
| `reclaimPolicy: Retain` | usunięcie PVC **nie kasuje** danych (domyślne `Delete` kasuje – w labie tak jest) |
| `allowVolumeExpansion: true` | powiększanie dysku edycją PVC, bez przenosin danych |
| **VolumeSnapshot** | migawka dysku przez CSI – jak snapshot w VMware, ale dla jednego PVC |
| **kopie zapasowe** (Velero, Kasten) | kopia obiektów i dysków poza klaster; replikacja to **nie** backup – skasowany plik znika ze wszystkich kopii naraz |
| bazy danych **poza Kubernetesem** | wiele firm trzyma bazy w usługach zarządzanych (RDS, Cloud SQL), a w klastrze tylko aplikacje bezstanowe |

### Lab a produkcja

| | Lab (`local-path`) | Produkcja (np. Ceph RBD, EBS) |
|---|---|---|
| Skąd miejsce | katalog na głównym dysku workera | osobny system dyskowy |
| Kopie danych | brak | 3 kopie (Ceph) / w chmurze |
| Awaria węzła | pod czeka na powrót węzła | dysk przepinany do innego węzła, pod startuje w 1–2 min |
| Limit rozmiaru | brak | dysk ma dokładnie tyle, ile w PVC |
| Migawki, powiększanie | nie | tak |

Naturalny następny krok w labie: **Longhorn** na trzech workerach – prawdziwa pamięć
replikowana bez osobnych serwerów.

## 6. Węzły: master, workery i maszyna monitoring

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
| `k3s-master` | **tak** | „mózg” klastra: API, scheduler, baza danych klastra. Aplikacje na nim nie startują (rozdział 7) |
| `k3s-worker-1..3` | **tak** | tu działają aplikacje i monitoring z Etapu 3 |
| `monitoring` | **nie** | osobna maszyna poza klastrem: kontroler Ansible, a w Etapie 4 zewnętrzna Grafana i Uptime Kuma |

**Dlaczego monitoring stoi poza klastrem?** Prometheus i Grafana z Etapu 3 działają **wewnątrz**
klastra. Gdy klaster padnie, padną razem z nim i nie powiedzą, że jest awaria. Maszyna monitoring
stoi obok i dalej działa. Zasada: **monitoring nie może zależeć od tego, co monitoruje.**

## 7. Taint i toleration – kto może stanąć na masterze

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

## 8. Zasoby węzłów i `kubectl top`

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

## 9. Kubeconfig – klucz do klastra

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

## 10. Helm – menedżer paczek

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

## 11. Chart, values i release

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

## 12. Repozytorium chartów i wersje

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

## 13. Jak dostać się do aplikacji: NodePort i Ingress

Pody mają wewnętrzne adresy IP, których nie widać z Twojego komputera. Są dwa sposoby, żeby
wejść do aplikacji z zewnątrz:

| Sposób | Jak działa | Przykład w labie |
|---|---|---|
| **NodePort** | otwiera ten sam port (30000–32767) na **każdym** węźle | Grafana `:30300`, Prometheus `:30090`, nginx `:30317` z ćwiczeń |
| **Ingress** | jedno wejście (port 80/443), które **po nazwie domeny** kieruje ruch do właściwej aplikacji | `http://podinfo.lab.local` |

NodePort jest prosty, ale przy wielu aplikacjach trzeba pamiętać wiele numerów portów. Ingress
daje ładne adresy i jedno wejście dla wszystkich.

## 14. Traefik – recepcja klastra

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

### Droga jednego zapytania krok po kroku

Co się dzieje, gdy wpiszesz w przeglądarce `http://podinfo.lab.local` (sprawdzone w labie 04.11):

| # | Gdzie | Co się dzieje |
|---|---|---|
| 1 | 🪟 Windows | nazwa `podinfo.lab.local` zamienia się na IP – z pliku `hosts` (`192.168.180.52  podinfo.lab.local`), bo w DNS jej nie ma |
| 2 | sieć | przeglądarka łączy się z `192.168.180.52:80` i w zapytaniu wysyła nagłówek **`Host: podinfo.lab.local`** |
| 3 | węzeł | port 80 trzyma pod `svclb-traefik-…` (ServiceLB z k3s – obsługa Service typu LoadBalancer) i przekazuje ruch do poda Traefika, nawet jeśli ten stoi na innym węźle |
| 4 | Traefik | czyta nagłówek `Host` i ścieżkę, szuka pasującej reguły we wszystkich Ingressach z `ingressClassName: traefik` – pasuje `podinfo` w `demo` |
| 5 | Traefik | reguła wskazuje Service `podinfo`, port `http`; Traefik bierze adresy podów z jego EndpointSlice i wysyła zapytanie **prosto do jednego z podów** (`10.42.x.x:9898`) |
| 6 | pod | podinfo odpowiada, Traefik odsyła odpowiedź przeglądarce |

Traefik obserwuje API Kubernetesa: nowy albo zmieniony Ingress działa po kilku sekundach, bez
restartu czegokolwiek. Dzięki nagłówkowi `Host` jedno IP i jeden port obsługują dowolnie wiele
aplikacji – to **name-based virtual hosting**, ten sam mechanizm co w nginx czy Apache.

Jak to sprawdzić i co znaczą błędy:

```bash
curl -H "Host: podinfo.lab.local" http://192.168.180.52/   # 200 – reguła pasuje, JSON z podinfo
curl http://192.168.180.52/                                # 404 – Traefik działa, ale brak reguły dla tej nazwy
kubectl describe ingress podinfo -n demo                   # reguły i adresy podów za Service
```

| Wynik | Znaczenie | Gdzie szukać |
|---|---|---|
| brak połączenia / timeout | ruch nie dochodzi do Traefika | firewall (port 80), pod Traefika, IP węzła |
| **404** | Traefik działa, żadna reguła nie pasuje | nazwa w `host:` / plik `hosts`, `ingressClassName`, namespace |
| **502 / 503** | reguła pasuje, ale nie ma zdrowego poda za Service | `kubectl get endpointslices -n NS`, selector Service vs etykiety podów, readinessProbe |

### Ingress w produkcji – gdzie stoi

Kontroler Ingress (Traefik, ingress-nginx) to **pody w klastrze**, na węzłach – nie osobna maszyna
„przed” klastrem. Przed nim w produkcji stoi za to **zewnętrzny load balancer** z jednym stałym
adresem (VIP), a DNS kieruje nazwy aplikacji na ten adres:

```
Internet → DNS (*.firma.pl → VIP) → firewall / WAF → load balancer (VIP)
         → węzły z kontrolerem Ingress (pody Traefika/nginx, często 2–3 repliki)
         → Service → pody aplikacji
```

| Element | Lab | Produkcja |
|---|---|---|
| nazwa → IP | plik `hosts` na Windowsie | rekord DNS, często wildcard `*.apps.firma.pl` |
| wejście do klastra | IP dowolnego węzła (ServiceLB k3s na każdym) | load balancer: w chmurze (AWS ELB, Azure LB) albo on-premise (HAProxy/keepalived, F5, MetalLB) |
| kontroler Ingress | 1 pod Traefika | kilka replik, czasem na **dedykowanych węzłach brzegowych** (taint + nodeSelector) |
| HTTPS | brak | certyfikaty na Ingressie (cert-manager + Let's Encrypt) albo na load balancerze |

Load balancer sprawdza, które węzły odpowiadają (health check) – awaria węzła nie zatrzymuje
ruchu, czego w labie nie daje wpis z jednym IP (.52) w pliku `hosts`.

## 15. CRD – nowe słowa w słowniku Kubernetesa

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

## 16. Operator – program, który rozumie nowe słowa

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

## 17. Jak to się składa w Etapie 3

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

## 18. Słowniczek

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
| **etykieta (label)** | naklejka `klucz=wartość` na obiekcie, po której inne obiekty go znajdują |
| **selektor** | zapytanie „wszystko z takimi etykietami” – używa go Service, Deployment, `kubectl -l` |
| **adnotacja** | notatka na obiekcie dla ludzi i narzędzi; nie da się po niej szukać |
| **ConfigMap** | ustawienia aplikacji poza obrazem, jako zmienne albo pliki |
| **Secret** | jak ConfigMap, ale na hasła; zapis base64, który **nie** jest szyfrowaniem |
| **PVC / PV / StorageClass** | wniosek o dysk / przydzielony dysk / rodzaj pamięci, który je tworzy |
| **CSI** | sterownik, przez który Kubernetes zakłada i podłącza dyski w danym systemie dyskowym |
| **Ceph (Rook)** | rozproszona pamięć z kilku serwerów, dane w 3 kopiach; Rook to jej operator w Kubernetesie |

Na rozmowie: *"Helm is a package manager for Kubernetes – a chart is a templated package, values
customize it, and a release is an installed instance."*

## 19. Ściągawka poleceń Helm

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

Pełna lista poleceń z przełącznikami: oficjalna ściągawka Helma (po angielsku) –
[helm.sh/docs/intro/cheatsheet](https://helm.sh/docs/intro/cheatsheet/). Polecenia używane w labie
zebrane razem: [ściągawka poleceń labu](../sciagawka-polecen.md#helm).

## 20. Pytania, które mogą paść na rozmowie

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

### Etykiety i konfiguracja

**Do czego służą etykiety i selektory?**
Etykiety to pary klucz=wartość na obiektach, a selektory wybierają obiekty po etykietach. Tak
Service znajduje pody, a Deployment liczy swoje repliki. W labie Service `podinfo` ma selektor
`app: podinfo` i nie zna nazw podów, które zmieniają się przy każdym restarcie.

**Co się stanie, gdy zmienię etykietę poda z Deploymentu?**
ReplicaSet przestanie go liczyć i dorobi nowy pod, a stary zostanie bez właściciela i wypadnie
z Service. Używa się tego do izolowania chorego poda do diagnozy.

**Etykieta a adnotacja?**
Po etykietach się wyszukuje (selektory), adnotacje to notatki dla ludzi i narzędzi, np. powód zmiany.

**ConfigMap a Secret?**
Oba przechowują konfigurację poza obrazem i podaje się je do poda jako zmienne albo pliki. Secret
jest na dane wrażliwe, ale base64 to nie szyfrowanie – chroni go RBAC, szyfrowanie etcd i to, że
nie trafia jawnie do gita (Sealed Secrets, SOPS, Vault).

**Zmieniłem ConfigMapę, a aplikacja ma stare ustawienia. Dlaczego?**
Zmienne środowiskowe ustawia się tylko przy starcie kontenera – trzeba `kubectl rollout restart`.
Pliki z wolumenu odświeżają się same po ok. minucie (w labie 77 s), ale nie przy `subPath`,
a aplikacja i tak musi przeczytać plik ponownie.

### Pamięć trwała

**Czym różni się PV od PVC i StorageClass?**
PVC to wniosek aplikacji o dysk, StorageClass opisuje rodzaj pamięci, a PV to konkretny dysk,
który sterownik CSI tworzy automatycznie na podstawie PVC. W labie klasą jest `local-path` z k3s.

**Co to jest CSI?**
Standardowy interfejs wtyczek pamięci. Producent (AWS, Ceph, NetApp, VMware) dostarcza sterownik,
który zakłada dyski i podpina je do węzłów. Dzięki temu ten sam PVC działa w każdym środowisku.

**Jaką pamięć dałbyś bazie danych w Kubernetesie on-premise?**
Blokową z replikacją, np. Ceph RBD przez Rook albo Longhorn, w trybie RWO, z `reclaimPolicy: Retain`
i kopiami zapasowymi (Velero, VolumeSnapshot). Dla dużej wydajności lokalne NVMe, a replikację
robi sama baza.

**RWO a RWX?**
RWO – dysk podłączony do jednego węzła naraz (bloki: EBS, RBD). RWX – wiele węzłów pisze naraz
(pliki: CephFS, NFS). Większość baz danych potrzebuje RWO.

**Czy replikacja (3 kopie w Cephie) zastępuje backup?**
Nie. Skasowany albo zaszyfrowany przez ransomware plik znika ze wszystkich kopii naraz. Backup to
osobna kopia w czasie, poza klastrem.

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

**Jak Ingress rozpoznaje, do której aplikacji wysłać zapytanie, skoro wszystkie mają ten sam IP i port?**
Po nagłówku HTTP `Host` (i ścieżce). Przeglądarka dopisuje do zapytania nazwę z paska adresu,
kontroler dopasowuje ją do `host:` w regułach. W labie: `curl -H "Host: whoami.lab.local"` na
IP węzła daje whoami, `Host: podinfo.lab.local` – podinfo, bez nagłówka – 404.

**Gdzie w produkcji stoi Ingress Controller i co jest przed nim?**
W klastrze, jako pody (często kilka replik, czasem na dedykowanych węzłach). Przed nim zewnętrzny
load balancer z jednym adresem VIP (w chmurze usługa dostawcy, on-premise np. HAProxy z keepalived
albo MetalLB), a DNS kieruje nazwy aplikacji na ten VIP. Load balancer omija niedziałające węzły.

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
