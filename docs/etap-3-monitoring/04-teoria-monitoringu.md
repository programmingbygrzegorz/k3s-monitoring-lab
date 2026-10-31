# Monitoring – Prometheus, Grafana i Alertmanager

Ten plik tłumaczy od zera, **co robi każdy z trzech programów** monitoringu z Etapu 3 i jak ze sobą
współpracują. Instalacja krok po kroku: [instalacja monitoringu](01-instalacja-monitoringu.md).

## Spis treści

1. [Trzy programy w jednym zdaniu](#1-trzy-programy-w-jednym-zdaniu)
2. [Porównanie: szpital](#2-porównanie-szpital)
3. [Jak płyną dane](#3-jak-płyną-dane)
4. [Prometheus – zbiera i pamięta liczby](#4-prometheus--zbiera-i-pamięta-liczby)
5. [Skąd biorą się metryki: exportery](#5-skąd-biorą-się-metryki-exportery)
6. [PromQL – pytania do Prometheusa](#6-promql--pytania-do-prometheusa)
7. [Reguły alertów](#7-reguły-alertów)
8. [Alertmanager – decyduje, kogo powiadomić](#8-alertmanager--decyduje-kogo-powiadomić)
9. [Grafana – pokazuje dane na wykresach](#9-grafana--pokazuje-dane-na-wykresach)
10. [Co zobaczysz w przeglądarce](#10-co-zobaczysz-w-przeglądarce)
11. [Czego Prometheus nie robi](#11-czego-prometheus-nie-robi)
12. [Pytania, które mogą paść na rozmowie](#12-pytania-które-mogą-paść-na-rozmowie)

---

## 1. Trzy programy w jednym zdaniu

| Program | Rola | Port w labie |
|---|---|---|
| **Prometheus** | co kilkanaście sekund **zbiera liczby** (metryki) ze wszystkich maszyn i aplikacji, **zapamiętuje** je i **sprawdza reguły** alertów | `:30090` |
| **Alertmanager** | dostaje od Prometheusa alerty i **decyduje, co z nimi zrobić**: grupuje, wycisza, powtarza, wysyła do ludzi | `:30093` |
| **Grafana** | **pokazuje** dane z Prometheusa na wykresach i dashboardach | `:30300` |

Prometheus **wykrywa**, Alertmanager **powiadamia**, Grafana **pokazuje**.

## 2. Porównanie: szpital

| W szpitalu | W labie |
|---|---|
| aparatura przy łóżku mierzy tętno, ciśnienie, temperaturę | **exportery** (node-exporter, kube-state-metrics) wystawiają pomiary |
| pielęgniarka co kwadrans obchodzi sale i **zapisuje odczyty w karcie** | **Prometheus** co 15–30 s pobiera pomiary i zapisuje je w bazie |
| w karcie jest reguła: „tętno > 140 przez 5 minut → wezwij lekarza” | **reguła alertu** w Prometheusie |
| **dyżurka** decyduje, którego lekarza wezwać, i nie dzwoni 10 razy w sprawie tego samego pacjenta | **Alertmanager** |
| **monitor** nad łóżkiem i wykresy w karcie, na które lekarz patrzy | **Grafana** |

Ważne: monitor nad łóżkiem (Grafana) nikogo nie wzywa. Wzywa dyżurka (Alertmanager), a decyzję,
że jest problem, podejmuje reguła w karcie (Prometheus).

## 3. Jak płyną dane

```
 node-exporter (każdy węzeł)  ─┐
 kube-state-metrics           ─┤   Prometheus sam przychodzi
 kubelety, API server         ─┼─▶ i pobiera metryki (pull) ──▶ baza metryk
 podinfo (aplikacja demo)     ─┘   co 15–30 s                        │
                                                                     │
                       ┌─────────────── reguły alertów ◀─────────────┤
                       ▼                                             │
                 Alertmanager ──▶ healthchecks.io / e-mail / …       │
                                                                     │
                 Grafana ◀────────── zapytania PromQL ───────────────┘
                 (wykresy)
```

1. **Exportery** wystawiają pomiary pod adresem `/metrics`.
2. **Prometheus** sam do nich przychodzi i pobiera (model **pull**). Skąd ma pobierać, mówią mu
   ServiceMonitory.
3. Prometheus co chwilę sprawdza **reguły** na zebranych danych. Gdy warunek jest spełniony –
   wysyła alert do **Alertmanagera**.
4. **Grafana** w ogóle nie zbiera danych. Gdy otwierasz dashboard, pyta Prometheusa językiem
   **PromQL** i rysuje odpowiedź.

## 4. Prometheus – zbiera i pamięta liczby

**Metryka** to nazwana liczba, która zmienia się w czasie:

```
node_memory_MemAvailable_bytes{instance="192.168.180.52:9100"}  4.1e+09
```

| Część | Znaczenie |
|---|---|
| `node_memory_MemAvailable_bytes` | nazwa: dostępna pamięć w bajtach |
| `{instance="…"}` | **etykiety** – z której maszyny, poda, namespace'u |
| `4.1e+09` | wartość: 4,1 GB |

Prometheus zapisuje taką liczbę co 15–30 sekund i trzyma historię jako **szereg czasowy**
(time series) – stąd wykresy „jak to się zmieniało”. W labie przez 7 dni (`retention: 7d`).

**Typy metryk:**

| Typ | Zachowanie | Przykład |
|---|---|---|
| **counter** (licznik) | tylko rośnie (zeruje się przy restarcie) | liczba zapytań HTTP od startu, liczba restartów |
| **gauge** (wskaźnik) | rośnie i maleje | wolna pamięć, temperatura, liczba podów |
| **histogram** | rozkład wartości w przedziałach | czasy odpowiedzi: ile poniżej 100 ms, 250 ms, 1 s… |

**Pull, a nie push.** Prometheus sam pyta, a nie czeka, aż ktoś mu przyśle dane. Zaleta: gdy cel
przestanie odpowiadać, Prometheus od razu to wie – metryka `up` ma wtedy wartość `0`. Na stronie
*Status → Targets* widać każdy cel jako **UP** albo **DOWN**.

## 5. Skąd biorą się metryki: exportery

Większość programów nie mówi „po prometheusowemu”. **Exporter** to tłumacz: odczytuje stan
czegoś i wystawia go jako metryki pod `/metrics`.

| Źródło | Co mierzy | Gdzie działa w labie |
|---|---|---|
| **node-exporter** | maszyna: CPU, pamięć, dysk, sieć, obciążenie | DaemonSet – po jednym na każdym węźle |
| **kube-state-metrics** | obiekty Kubernetesa: ile replik chce Deployment, a ile ma; restarty podów; statusy | 1 pod |
| **kubelet / cAdvisor** | zużycie zasobów przez każdy kontener | wbudowane w k3s na każdym węźle |
| **API server** | ile zapytań, jak szybko odpowiada | wbudowane w k3s |
| **podinfo** | własne metryki aplikacji: liczba zapytań, czasy odpowiedzi | aplikacja demo (krok 5) |

Własne aplikacje wystawiają metryki same – dodaje się do nich bibliotekę Prometheusa. Tak robi
podinfo.

### ServiceMonitor – skąd Prometheus wie, gdzie pobierać

> Do przećwiczenia na sucho: [symulator ServiceMonitor](07-symulator-servicemonitor.html) – zmieniasz
> etykiety i porty, a symulator pokazuje, czy Prometheus znajdzie cele i dlaczego.

Pody w Kubernetesie ciągle się zmieniają: nowe repliki, nowe adresy IP po każdym restarcie.
Wpisywanie adresów ręcznie do konfiguracji Prometheusa nie miałoby sensu. **ServiceMonitor** to
obiekt (typ z CRD operatora), który mówi:

> „Znajdź Service z taką etykietą, i z każdego poda za nim pobieraj `/metrics` z tego portu co 15 sekund.”

Porównanie: zamiast dawać listonoszowi listę konkretnych mieszkań (adresy IP podów), dajesz mu
regułę: „roznieś do każdego mieszkania z tabliczką *podinfo*”. Gdy ktoś się wprowadzi albo
wyprowadzi, reguła dalej działa.

Łańcuch w labie – trzy obiekty połączone **etykietami**:

```
ServiceMonitor podinfo            Service podinfo                 Pody podinfo (3 repliki)
(kubernetes/monitoring/)          (kubernetes/demo-app/)          (Deployment)
  selector:                         labels:                         labels:
    matchLabels:          ───▶        app: podinfo                    app: podinfo
      app: podinfo                  selector:              ───▶     ports:
  endpoints:                          app: podinfo                    - name: http
    - port: http          ───▶      ports:                              containerPort: 9898
      path: /metrics                  - name: http ─────────────▶
      interval: 15s                     port: 9898
```

1. ServiceMonitor szuka Service'u z etykietą `app: podinfo` w namespace `demo`.
2. Service przez swój `selector` wie, które pody są „za nim” (lista w EndpointSlice).
3. Port wskazany **nazwą** `http` – nie numerem – więc zmiana numeru portu nic nie psuje.
4. Operator zamienia to na konfigurację Prometheusa, a Prometheus pobiera
   `http://<IP-poda>:9898/metrics` z każdej repliki. Stąd 3 cele w *Target health*.

Gdy przeskalujesz podinfo do 5 replik, cele same zmienią się na 5 – bez dotykania Prometheusa.

**Po co obiekt, a nie wpis w pliku Prometheusa?**

| Zaleta | Znaczenie |
|---|---|
| konfiguracja **obok aplikacji** | zespół aplikacji dodaje swój ServiceMonitor w tym samym repozytorium co Deployment – nie musi edytować centralnego pliku Prometheusa |
| **bez restartu** | operator i config-reloader przeładowują konfigurację w kilka sekund |
| **deklaratywnie** | `kubectl apply`, `kubectl get servicemonitors -A`, historia w gicie, GitOps |

**PodMonitor** robi to samo, ale wybiera pody bezpośrednio, bez Service'u – dla aplikacji, które
nie mają Service'u.

**Gdy cel się nie pojawia w Target health – co sprawdzić po kolei:**

1. Czy Prometheus „widzi” ten ServiceMonitor – w kube-prometheus-stack domyślnie tylko z etykietą
   `release: <nazwa release'u>`; w labie wyłączone przez `serviceMonitorSelectorNilUsesHelmValues: false`
   ([plik values](02-plik-values.md#trzy-linie-selectorniluseshelmvalues-false)).
2. Czy `selector` ServiceMonitora pasuje do **etykiet Service'u** (nie podów!).
3. Czy nazwa portu (`port: http`) istnieje w Service.
4. Czy Service ma pody: `kubectl get endpointslices -n demo`.
5. Czy aplikacja naprawdę wystawia `/metrics`: `curl http://<IP-poda>:9898/metrics`.

## 6. PromQL – pytania do Prometheusa

PromQL to język zapytań. Wpisujesz go w Prometheusie (zakładka *Query*) albo w Grafanie
(*Explore*). Przykłady do wypróbowania w labie:

| Zapytanie | Co zwraca |
|---|---|
| `up` | które cele odpowiadają (1) a które nie (0) |
| `node_memory_MemAvailable_bytes / 1024 / 1024` | wolna pamięć każdego węzła w MiB |
| `100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` | zużycie CPU w % na węzeł |
| `kube_pod_container_status_restarts_total` | liczba restartów każdego kontenera |
| `kube_deployment_status_replicas_available` | ile replik każdego Deploymentu jest dostępnych |
| `sum by (namespace) (container_memory_working_set_bytes)` | pamięć zużywana przez każdy namespace |

Najważniejsze elementy:

| Element | Znaczenie |
|---|---|
| `{mode="idle"}` | filtr po etykiecie |
| `[5m]` | weź wartości z ostatnich 5 minut |
| `rate(...)` | jak szybko rośnie licznik – na sekundę. Liczniki prawie zawsze czyta się przez `rate` |
| `sum by (namespace)` | zsumuj, grupując po etykiecie |

## 7. Reguły alertów

Reguła to zapytanie PromQL z warunkiem i czasem trwania. Przykład z labu
([kubernetes/monitoring/prometheusrule-lab.yaml](../../kubernetes/monitoring/prometheusrule-lab.yaml)):

```yaml
- alert: PodinfoDown
  expr: kube_deployment_status_replicas_available{namespace="demo", deployment="podinfo"} == 0
  for: 1m
```

- `expr` – warunek: podinfo nie ma żadnej dostępnej repliki,
- `for: 1m` – musi trwać co najmniej minutę. Chroni przed alarmem z powodu chwilowego skoku.

Stany alertu na stronie Prometheusa (*Alerts*):

| Stan | Znaczenie |
|---|---|
| **inactive** | warunek nie jest spełniony – wszystko w porządku |
| **pending** | warunek spełniony, ale krócej niż `for` – Prometheus czeka |
| **firing** | warunek trwa dłużej niż `for` – alert idzie do Alertmanagera |

Chart dał ~30 gotowych zestawów reguł (węzły, pody, dyski, sam Prometheus), a lab dodaje 5 własnych.

## 8. Alertmanager – decyduje, kogo powiadomić

Prometheus tylko **stwierdza**, że jest problem. Gdyby sam wysyłał wiadomości, przy awarii 10
podów dostałbyś 10 SMS-ów co minutę. Alertmanager temu zapobiega:

| Funkcja | Co robi | Przykład |
|---|---|---|
| **grupowanie** (`group_by`) | łączy podobne alerty w jedną wiadomość | 10 padniętych podów w `demo` → 1 wiadomość |
| **czekanie** (`group_wait`) | chwilę czeka, czy nie dojdą kolejne alerty z tej samej grupy | 30 s |
| **powtarzanie** (`repeat_interval`) | przypomina, gdy problem trwa – ale rzadko | co 4 godziny |
| **trasowanie** (`routes`) | różne alerty do różnych odbiorców | baza danych → zespół DBA, Watchdog → healthchecks.io |
| **wyciszanie** (silences) | celowo ucisza alerty na czas | „wyłączam worker-2 na godzinę do konserwacji” – przez stronę `:30093` |
| **tłumienie** (inhibition) | gdy jest alert ważniejszy, ukrywa pochodne | węzeł padł → nie pokazuj osobno alertów o każdym podzie na nim |

**Cluster Status: disabled** na stronie *Status* Alertmanagera (`:30093/#/status`) jest w labie
poprawne. W produkcji uruchamia się kilka kopii Alertmanagera (zwykle 3), które łączą się
w **klaster** i wymieniają informacje (protokół gossip): kto już wysłał powiadomienie i jakie są
wyciszenia – żeby przy awarii jednej kopii alerty dalej szły, a ludzie nie dostawali duplikatów.
W labie działa **1 replika** (`kubectl -n monitoring get alertmanager` → `replicas: 1`), więc
operator uruchamia ją z pustym `--cluster.listen-address=` i tryb klastra jest wyłączony.
Gdyby była to produkcja: `alertmanager.alertmanagerSpec.replicas: 3` w pliku values.

W labie domyślnym odbiorcą jest `null` – alerty widać na stronach, ale nikt nie dostaje
wiadomości. Wyjątek to **Watchdog** – alert, który jest zawsze aktywny i co minutę trafia do
healthchecks.io (**dead man's switch**). Gdy przestanie docierać, healthchecks.io zaalarmuje, że
padł cały monitoring. Szczegóły konfiguracji: [plik values, rozdział 6](02-plik-values.md#6-alertmanager--trasy-i-odbiorcy).

## 9. Grafana – pokazuje dane na wykresach

Grafana **nie przechowuje metryk**. Ma tylko:

- **źródła danych** (data sources) – skąd brać dane; w labie Prometheus, ustawiony przez chart,
- **dashboardy** – zestawy wykresów; każdy wykres to jedno lub kilka zapytań PromQL.

Chart dał kilkadziesiąt gotowych dashboardów. Na początek:

| Dashboard | Co pokazuje |
|---|---|
| *Node Exporter / Nodes* | CPU, pamięć, dysk, sieć każdej maszyny |
| *Kubernetes / Compute Resources / Cluster* | zużycie zasobów całego klastra i namespace'ów |
| *Kubernetes / Compute Resources / Namespace (Pods)* | pody w wybranym namespace |
| *Kubernetes / Compute Resources / Node (Pods)* | które pody zjadają zasoby danego węzła |

Grafana potrafi też czytać z wielu źródeł naraz (Prometheus, Loki – logi, bazy SQL) i sama
wysyłać alerty – ale w tym labie alerty obsługuje Prometheus z Alertmanagerem.

W Etapie 4 druga Grafana na maszynie `monitoring` będzie czytać z **tego samego** Prometheusa
(`:30090`) – to pokazuje, że Grafana i Prometheus to niezależne programy.

## 10. Co zobaczysz w przeglądarce

| Adres | Gdzie kliknąć | Co powinno być |
|---|---|---|
| `http://192.168.180.51:30090` – **Prometheus** | *Status → Targets* (lub *Target health*) | lista celów, wszystkie **UP** |
| | *Alerts* | reguły; **Watchdog** w stanie *firing* – tak ma być |
| | *Query* → wpisz `up` → *Execute* | jedna linia na każdy cel z wartością 1 |
| `http://192.168.180.51:30093` – **Alertmanager** | strona główna | aktywny alert **Watchdog** |
| | *Silences* | tu wycisza się alerty na czas konserwacji |
| `http://192.168.180.51:30300` – **Grafana** | *Dashboards* | gotowe dashboardy z rozdziału 9 |
| | *Explore* | wpisywanie zapytań PromQL z podpowiedziami |
| | *Connections → Data sources* | źródło danych Prometheus |

### Skąd w Prometheusie wzięły się alerty, Target health i Rule health

Po instalacji Prometheus od razu ma dziesiątki celów i ponad sto alertów, choć nikt ich ręcznie
nie wpisywał. Skąd?

```
helm install ──▶ 30 obiektów PrometheusRule  ─┐
kubectl apply ─▶  1 obiekt PrometheusRule (lab)┤
                                               ├─▶ operator ──▶ pliki reguł w podzie Prometheusa
helm install ──▶ 9 obiektów ServiceMonitor  ───┤
kubectl apply ─▶ 1 ServiceMonitor (podinfo) ───┘    i lista celów do pobierania
```

Operator czyta obiekty `PrometheusRule` i `ServiceMonitor` z całego klastra, zamienia je na
konfigurację Prometheusa, a `config-reloader` (drugi kontener w podzie Prometheusa) przeładowuje
ją bez restartu.

Trzy strony Prometheusa pokazują trzy różne rzeczy:

| Strona (menu *Status* / *Alerts*) | Pytanie, na które odpowiada | Skąd się bierze |
|---|---|---|
| **Target health** (dawniej *Targets*) | „czy Prometheus **dostaje dane** z każdego źródła?” – każdy cel **UP** lub **DOWN**, czas ostatniego pobrania, błąd | z obiektów **ServiceMonitor** / PodMonitor |
| **Rule health** (dawniej *Rules*) | „czy reguły **dają się obliczyć**?” – każda reguła `ok` albo `err` (np. błąd w zapytaniu PromQL) i ile trwało obliczenie | z obiektów **PrometheusRule** |
| **Alerts** | „czy jakiś warunek **jest spełniony**?” – reguły alertów w stanie *inactive*, *pending* albo *firing* | z tych samych PrometheusRule, tylko reguły typu `alert` |

**Rule health a Alerts:** reguła może być zdrowa (`ok` – zapytanie działa) i jednocześnie
*firing* (warunek spełniony – jest problem). `err` w Rule health oznacza, że reguła jest zepsuta
i **nigdy nie zaalarmuje** – to groźniejsze niż firing.

**Dwa rodzaje reguł** na stronie Rule health:

| Rodzaj | Co robi | Przykład |
|---|---|---|
| **alerting** (alertowe) | sprawdza warunek i wysyła alert | `PodinfoDown`, `KubePodCrashLooping` |
| **recording** (nagrywające) | regularnie liczy zapytanie i zapisuje wynik jako **nową metrykę** – dashboardy liczą się szybciej | `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate` |

Stan w labie zaraz po instalacji (z API Prometheusa):

```
grupy reguł:        33   (30 z chartu + reguły labu + wbudowane)
reguły alertowe:   139
reguły nagrywające: 86
Rule health:       225 × ok
obiekty PrometheusRule: 31 (30 z chartu + prometheusrule-lab)
```

Cele (Target health), wszystkie **UP**:

| Cel (scrape pool) | Ile | Co to jest |
|---|---|---|
| `serviceMonitor/demo/podinfo/0` | 3 | 3 repliki aplikacji demo |
| `…/monitoring-prometheus-node-exporter/0` | 4 | node-exporter na każdym węźle |
| `…/monitoring-kube-prometheus-kubelet/0,1,2` | 4 × 3 | kubelet każdego węzła: jego metryki, cAdvisor (kontenery), sondy |
| `…/monitoring-kube-prometheus-apiserver/0` | 1 | API server |
| `…/monitoring-kube-prometheus-coredns/0` | 1 | DNS klastra |
| `…/monitoring-kube-state-metrics/0` | 1 | stan obiektów Kubernetesa |
| `…/prometheus`, `…/alertmanager`, `…/operator`, `…/grafana` | po 1–2 | monitoring monitoruje sam siebie |

ServiceMonitory to zwykłe obiekty w klastrze – można je wylistować i obejrzeć jak Deploymenty:

```
$ kubectl get servicemonitors -A
NAMESPACE    NAME                                      AGE
demo         podinfo                                   20m
monitoring   monitoring-grafana                        62m
monitoring   monitoring-kube-prometheus-alertmanager   62m
monitoring   monitoring-kube-prometheus-apiserver      62m
monitoring   monitoring-kube-prometheus-coredns        62m
monitoring   monitoring-kube-prometheus-kubelet        62m
monitoring   monitoring-kube-prometheus-operator       62m
monitoring   monitoring-kube-prometheus-prometheus     62m
monitoring   monitoring-kube-state-metrics             62m
monitoring   monitoring-prometheus-node-exporter       62m

$ kubectl get servicemonitor podinfo -n demo -o yaml     # treść jednego
$ kubectl get prometheusrules -A                          # to samo dla reguł
```

9 z chartu (namespace `monitoring`, utworzone przy `helm install`) + 1 z labu (`demo/podinfo`,
utworzony przez `kubectl apply` w kroku 5). Jeden ServiceMonitor może dawać kilka celów: `podinfo`
→ 3 cele (3 repliki), `kubelet` → 3 ścieżki × 4 węzły.

Alerty aktywne (*firing*) zaraz po instalacji:

| Alert | Dlaczego |
|---|---|
| `Watchdog` | zawsze aktywny – dead man's switch; **tak ma być** |
| `AlertmanagerFailedToSendAlerts`, `AlertmanagerClusterFailedToSendAlerts` | Alertmanager nie może wysłać Watchdoga, bo `HEALTHCHECKS_URL` to jeszcze adres przykładowy (`hc-ping.com/0000…`) – serwer odpowiada `400 invalid url format`. Znikną po wpisaniu prawdziwego adresu z healthchecks.io (Etap 4) |

To dobry przykład, że **monitoring monitoruje sam siebie**: błędna konfiguracja powiadomień
sama wywołała alert.

## 11. Czego Prometheus nie robi

| Nie robi | Co się do tego używa |
|---|---|
| nie zbiera **logów** (tekstu z aplikacji) | Loki, Elasticsearch / OpenSearch |
| nie śledzi pojedynczych **zapytań** przez wiele usług | tracing: Tempo, Jaeger |
| nie przechowuje danych latami | długoterminowy magazyn: Thanos, Mimir |
| nie jest dokładny co do pojedynczego zdarzenia | rozliczenia, audyt – zwykła baza danych |

Metryki, logi i tracing to razem **trzy filary obserwowalności** (observability).

## 12. Pytania, które mogą paść na rozmowie

**Czym różnią się Prometheus, Grafana i Alertmanager?**
Prometheus zbiera metryki, przechowuje je i ocenia reguły alertów. Alertmanager przyjmuje alerty,
grupuje je, wycisza i wysyła do ludzi. Grafana wizualizuje dane na dashboardach – sama ich nie
przechowuje.

**Pull czy push – jak działa Prometheus i dlaczego?**
Pull: Prometheus sam pobiera metryki z celów. Od razu wie, gdy cel nie odpowiada (`up == 0`),
a konfiguracja celów jest w jednym miejscu. Dla krótkich zadań, które kończą się przed pobraniem,
jest Pushgateway.

**Czym jest exporter?**
Programem, który odczytuje stan czegoś – maszyny, bazy danych, serwera WWW – i wystawia go jako
metryki pod `/metrics`. Przykład: node-exporter dla maszyn, kube-state-metrics dla obiektów
Kubernetesa.

**Counter a gauge?**
Counter tylko rośnie – np. liczba zapytań; czyta się go przez `rate()`. Gauge rośnie i maleje –
np. wolna pamięć.

**Po co `for:` w regule alertu?**
Żeby alert nie odpalał przy chwilowym skoku. Warunek musi trwać określony czas – do tego czasu
alert jest w stanie *pending*.

**Jak unikasz zalewu alertów?**
Grupowanie w Alertmanagerze, rozsądne `repeat_interval`, `for:` w regułach, tłumienie alertów
pochodnych i alerty tylko na objawy, które wymagają reakcji człowieka.

**Jak wyciszyć alerty na czas prac serwisowych?**
Silence w Alertmanagerze – na określony czas, dla alertów pasujących do etykiet, np. konkretnego
węzła.

**Czym różni się Target health od Rule health?**
Target health mówi, czy Prometheus dostaje dane z każdego celu (UP/DOWN). Rule health mówi, czy
reguły dają się obliczyć. Reguła z błędem nigdy nie zaalarmuje, więc trzeba to też monitorować.

**Czym jest reguła nagrywająca (recording rule)?**
Zapytaniem liczonym regularnie i zapisywanym jako nowa metryka. Przyspiesza dashboardy i złożone
alerty, bo ciężkie obliczenie robi się raz, a nie przy każdym odświeżeniu.

**Co zrobisz, gdy padnie sam monitoring?**
Dead man's switch: alert Watchdog co minutę trafia do zewnętrznej usługi; gdy przestanie
przychodzić, ona alarmuje. Do tego monitoring z zewnątrz klastra – w labie maszyna `monitoring`.

**Jakie są cztery złote sygnały (golden signals)?**
Opóźnienie (latency), ruch (traffic), błędy (errors) i nasycenie (saturation) – według książki
Google SRE to minimum, które warto mierzyć dla każdej usługi.

## Dalej

- Instalacja krok po kroku: [docs/etap-3-monitoring/01-instalacja-monitoringu.md](01-instalacja-monitoringu.md)
- Plik values linia po linii: [docs/etap-3-monitoring/02-plik-values.md](02-plik-values.md)
- Pojęcia Kubernetes i Helm: [docs/etap-3-monitoring/03-teoria-kubernetes-helm.md](03-teoria-kubernetes-helm.md)
