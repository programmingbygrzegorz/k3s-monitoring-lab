# Monitoring – Prometheus, Grafana i Alertmanager

Ten plik tłumaczy od zera, **co robi każdy z trzech programów** monitoringu z Etapu 3 i jak ze sobą
współpracują. Instalacja krok po kroku: [docs/03](03-monitoring.md).

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
([kubernetes/monitoring/prometheusrule-lab.yaml](../kubernetes/monitoring/prometheusrule-lab.yaml)):

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

W labie domyślnym odbiorcą jest `null` – alerty widać na stronach, ale nikt nie dostaje
wiadomości. Wyjątek to **Watchdog** – alert, który jest zawsze aktywny i co minutę trafia do
healthchecks.io (**dead man's switch**). Gdy przestanie docierać, healthchecks.io zaalarmuje, że
padł cały monitoring. Szczegóły konfiguracji: [docs/03a, rozdział 6](03a-values-monitoringu.md#6-alertmanager--trasy-i-odbiorcy).

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

**Co zrobisz, gdy padnie sam monitoring?**
Dead man's switch: alert Watchdog co minutę trafia do zewnętrznej usługi; gdy przestanie
przychodzić, ona alarmuje. Do tego monitoring z zewnątrz klastra – w labie maszyna `monitoring`.

**Jakie są cztery złote sygnały (golden signals)?**
Opóźnienie (latency), ruch (traffic), błędy (errors) i nasycenie (saturation) – według książki
Google SRE to minimum, które warto mierzyć dla każdej usługi.

## Dalej

- Instalacja krok po kroku: [docs/03-monitoring.md](03-monitoring.md)
- Plik values linia po linii: [docs/03a-values-monitoringu.md](03a-values-monitoringu.md)
- Pojęcia Kubernetes i Helm: [docs/teoria-kubernetes-helm.md](teoria-kubernetes-helm.md)
