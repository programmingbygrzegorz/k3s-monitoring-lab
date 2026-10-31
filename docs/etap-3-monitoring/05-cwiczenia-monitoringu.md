# Etap 3 – ćwiczenia z monitoringu: Prometheus, Grafana, Alertmanager

Osiem poziomów, od „gdzie co jest” do własnego wykresu. Każdy zajmuje 10–20 minut. Robisz je
**w przeglądarce** na Windowsie, a kilka poleceń – na `k3s-master`.

Teoria do tych ćwiczeń: [docs/etap-3-monitoring/04-teoria-monitoringu.md](04-teoria-monitoringu.md). Wykonanie wszystkich
poziomów ze zrzutami ekranu i prawdziwymi wynikami z labu: [rozwiązania ćwiczeń z monitoringu](06-cwiczenia-monitoringu-rozwiazania.md)
– zajrzyj tam, gdy utkniesz albo chcesz porównać wynik.

**Przed startem:** Etap 3 zakończony – działają Prometheus, Alertmanager, Grafana i podinfo
(3 repliki). 📸 Snapshot `k3s-monitoring`.

| Adres | Program | Logowanie |
|---|---|---|
| `http://192.168.180.51:30090` | Prometheus | brak |
| `http://192.168.180.51:30093` | Alertmanager | brak |
| `http://192.168.180.51:30300` | Grafana | `admin`, hasło: `grep GRAFANA_ADMIN_PASSWORD ~/k3s-monitoring-lab/lab.env` na masterze |

| Poziom | Program | Temat |
|---|---|---|
| [1](#poziom-1--co-prometheus-zbiera) | Prometheus | co Prometheus zbiera – *Target health* |
| [2](#poziom-2--pierwsze-zapytania) | Prometheus | pierwsze zapytania: metryka, etykieta, wartość |
| [3](#poziom-3--historia-na-wykresie) | Prometheus | historia na wykresie |
| [4](#poziom-4--reguły-i-alerty) | Prometheus | reguły i alerty – *Rule health*, *Alerts* |
| [5](#poziom-5--gotowe-dashboardy-w-grafanie) | Grafana | gotowe dashboardy |
| [6](#poziom-6--narodziny-alertu) | wszystkie trzy | narodziny alertu: *inactive* → *pending* → *firing* |
| [7](#poziom-7--wyciszenie-na-czas-prac) | Alertmanager | wyciszenie (silence) na czas prac |
| [8](#poziom-8--własny-wykres-w-grafanie) | Grafana | własny wykres |

---

## Poziom 1 – co Prometheus zbiera

**Cel:** zobaczyć, skąd Prometheus pobiera dane i czy wszystkie źródła działają.

1. Otwórz `http://192.168.180.51:30090`, menu **Status → Target health**.
2. Znajdź grupę `serviceMonitor/demo/podinfo/0`. Ile ma celów? Skąd ta liczba?
3. W polu *Filter by endpoint or labels* wpisz `node-exporter`. Porównaj adresy z adresami maszyn
   labu (`.51`, `.52`, `.53`, `.55`).
4. Przy jednym celu kliknij adres (`http://…/metrics`) – zobaczysz surowe metryki w formie
   tekstu. Tak wygląda to, co Prometheus pobiera co 15–30 sekund.

**Co powinieneś zobaczyć:** wszystkie cele **UP**, przy każdym czas ostatniego pobrania
(*Last scrape*) i jego długość w milisekundach.

**Sprawdź się:**
- Dlaczego podinfo ma 3 cele, a node-exporter 4?
- Dlaczego adresy node-exportera to adresy maszyn (`192.168.180.x`), a podinfo – adresy podów
  (`10.42.x.x`)? *(Podpowiedź: node-exporter ma `hostNetwork: true` – działa w sieci maszyny.)*
- Na której maszynie nie ma poda podinfo i dlaczego?

## Poziom 2 – pierwsze zapytania

**Cel:** zadać Prometheusowi pytanie i odczytać odpowiedź.

1. Menu **Query**, zakładka **Table**.
2. Wpisz `up` i kliknij **Execute**. Każdy wiersz to jeden cel z poziomu 1, wartość `1` = działa.
3. Wpisz `node_memory_MemAvailable_bytes` – wolna pamięć w bajtach. Nieczytelne? Spróbuj:
   ```
   node_memory_MemAvailable_bytes / 1024 / 1024
   ```
   Teraz w MiB.
4. Zawęź do jednej maszyny – filtr po etykiecie:
   ```
   node_memory_MemAvailable_bytes{instance="192.168.180.51:9100"} / 1024 / 1024
   ```
5. Porównaj z terminalem: na masterze `free -m` (kolumna *available*).

**Co powinieneś zobaczyć:** 4 wiersze (po jednym na węzeł). Master ma najmniej wolnej pamięci.

**Sprawdź się:**
- Co jest nazwą metryki, co etykietą, co wartością w wierszu wyniku?
- Dlaczego wynik w Prometheusie i `free -m` mogą się trochę różnić? *(różny moment pomiaru)*

## Poziom 3 – historia na wykresie

**Cel:** zobaczyć, jak wartość zmieniała się w czasie – to główna przewaga Prometheusa nad
`kubectl top`.

1. To samo zapytanie co w poziomie 2, zakładka **Graph**.
2. Zmień zakres na `1h`, potem `6h` (przyciski `−` / `+` przy zakresie).
3. Najedź myszą na linię – zobaczysz wartość i etykiety w danym momencie.
4. Zużycie CPU w procentach na węzeł:
   ```
   100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100
   ```
5. Restarty kontenerów (zakładka **Table**):
   ```
   kube_pod_container_status_restarts_total > 0
   ```

**Co powinieneś zobaczyć:** płaskie linie pamięci (lab nic nie robi) i niskie CPU, kilka procent.

**Sprawdź się:**
- Co robi `rate(...[5m])` i dlaczego liczników nie czyta się bez niego?
- Co zrobiłbyś, gdyby linia pamięci jednego węzła cały czas spadała? *(wyciek pamięci – szukasz,
  który pod rośnie)*

## Poziom 4 – reguły i alerty

**Cel:** odróżnić regułę, która działa, od alertu, który jest aktywny.

1. Menu **Status → Rule health**. Wszystkie reguły `ok`? Znajdź grupę `lab.demo-app`.
2. Menu **Alerts**. Znajdź grupy `lab.demo-app`, `lab.nodes`, `lab.pods` – to 5 reguł labu.
3. Rozwiń `PodinfoDown` – zobaczysz zapytanie (`expr`), czas `for` i etykiety.
4. Znajdź alerty w stanie **FIRING**. Który zawsze jest aktywny i dlaczego to dobrze?
5. Otwórz Alertmanagera `http://192.168.180.51:30093` – te same alerty, pogrupowane według
   odbiorcy (`deadmans-switch`, `null`).

**Co powinieneś zobaczyć:** reguły labu *inactive*, `Watchdog` *firing*, do tego
`AlertmanagerFailedToSendAlerts` (przykładowy adres healthchecks.io – Etap 4).

**Sprawdź się:**
- Czym różni się *Rule health* `ok` od alertu *firing*?
- Dlaczego `Watchdog` w Alertmanagerze jest przy odbiorcy `deadmans-switch`, a reszta przy `null`?

## Poziom 5 – gotowe dashboardy w Grafanie

**Cel:** korzystać z gotowych dashboardów zamiast pisać zapytania.

1. Zaloguj się do Grafany `http://192.168.180.51:30300`.
2. **Dashboards** → *Node Exporter / Nodes*. U góry wybierz `instance` – przełączaj między
   maszynami.
3. *Kubernetes / Compute Resources / Cluster* – zużycie całego klastra, tabela namespace'ów.
4. *Kubernetes / Compute Resources / Namespace (Pods)* → namespace `monitoring`. Który pod zużywa
   najwięcej pamięci? *(Prometheus)*
5. W prawym górnym rogu zmień zakres czasu (`Last 1 hour` → `Last 6 hours`) i odświeżanie
   (`Refresh` → `30s`).
6. Na dowolnym wykresie: menu panelu (trzy kropki) → **Edit** – zobaczysz zapytanie PromQL, które
   rysuje ten wykres. Wyjdź bez zapisywania (**Discard**).

**Co powinieneś zobaczyć:** te same liczby co w Prometheusie, tylko czytelniej.

**Sprawdź się:**
- Skąd Grafana bierze dane? *(Connections → Data sources → Prometheus)*
- Czy Grafana przechowuje metryki?

## Poziom 6 – narodziny alertu

**Cel:** zobaczyć cały łańcuch: awaria → reguła → *pending* → *firing* → Alertmanager.

1. Otwórz w przeglądarce dwie karty: Prometheus **Alerts** (filtr `podinfo`) i Alertmanagera.
2. Na `k3s-master`:
   ```bash
   kubectl -n demo scale deployment podinfo --replicas=0
   kubectl -n demo get deploy,pods
   ```
   `scale --replicas=0` usuwa wszystkie pody – aplikacja przestaje działać.
3. Odświeżaj kartę **Alerts** co ~15 sekund i zapisuj czas:
   - `PodinfoDown` → **PENDING** (warunek spełniony, Prometheus odlicza `for: 1m`),
   - `PodinfoDown` → **FIRING** (minęła minuta),
   - `PodinfoDegraded` → **FIRING** (po `for: 2m`).
4. Karta Alertmanagera – po chwili pojawi się `PodinfoDown` (z `group_wait: 30s`).
5. Prometheus **Query** → **Graph**, zakres `15m`:
   ```
   kube_deployment_status_replicas_available{namespace="demo"}
   ```
   Spadek z 3 do 0 na wykresie.
6. **Nie przywracaj jeszcze replik** – poziom 7 korzysta z tego alertu.

**Sprawdź się:**
- Ile czasu minęło od `scale` do *firing*? Dlaczego nie od razu? *(czas pobierania metryk
  + interwał oceny reguł + `for`)*
- Dlaczego jednocześnie odpaliły się dwa alerty? Czy to dobrze?

## Poziom 7 – wyciszenie na czas prac

**Cel:** wyciszyć alert, o którym już wiesz – jak administrator przed planowaną konserwacją.

1. Alertmanager → przy alercie `PodinfoDown` kliknij **Silence** (albo **New Silence**).
2. *Matchers*: `alertname="PodinfoDown"`, czas: `1h`, *Creator*: Twoje imię, *Comment*:
   `Ćwiczenie – podinfo celowo wyłączone`. **Create**.
3. Zakładka **Silences** – Twoje wyciszenie jako *Active*.
4. Zakładka **Alerts** – `PodinfoDown` zniknął z domyślnej listy. Zaznacz pole **Silenced** – wraca,
   oznaczony jako wyciszony.
5. Prometheus **Alerts** – alert nadal *firing*. Wyciszenie działa tylko w Alertmanagerze:
   problem dalej jest, tylko nikt nie dostaje powiadomień.
6. Sprzątanie:
   - Alertmanager → **Silences** → przy wyciszeniu **Expire**,
   - na masterze:
     ```bash
     kubectl -n demo scale deployment podinfo --replicas=3
     kubectl -n demo rollout status deployment/podinfo
     ```
   - po 1–2 minutach alerty `Podinfo…` wracają do *inactive*.

**Sprawdź się:**
- Czym różni się wyciszenie (silence) od usunięcia reguły?
- Dlaczego wyciszenie ma zawsze czas końca i autora?

## Poziom 8 – własny wykres w Grafanie

**Cel:** zbudować coś samemu – pierwszy własny dashboard.

1. Grafana → **Dashboards** → **New** → **New dashboard** → **Add visualization** → źródło
   **Prometheus**.
2. Na dole, w polu zapytania (przełącz z *Builder* na **Code**):
   ```
   sum by (namespace) (container_memory_working_set_bytes{container!=""})
   ```
   Pamięć zużywana przez każdy namespace.
3. Po prawej: *Title* `Pamięć według namespace`, *Standard options → Unit* → `Data / bytes(IEC)`.
4. **Back to dashboard** → dodaj drugi panel:
   ```
   sum by (pod) (increase(kube_pod_container_status_restarts_total[1h]))
   ```
   *Title* `Restarty w ostatniej godzinie`, typ wykresu **Bar chart** albo **Table**.
5. **Save dashboard** – nazwa `Lab – mój dashboard`.

**Co powinieneś zobaczyć:** największy namespace to `monitoring` (Prometheus, Grafana), potem
`kube-system`.

**Uwaga:** Grafana w labie nie ma trwałego dysku – dashboard zrobiony w przeglądarce zniknie po
restarcie poda Grafany ([plik values, rozdział 9](02-plik-values.md#9-czego-ten-plik-świadomie-nie-ustawia)).
Żeby go zachować: menu dashboardu → **Export** → **Export as JSON** i zapisz plik. W produkcji
dashboardy trzyma się w gicie jako kod.

**Sprawdź się:**
- Co znaczy `{container!=""}` i co by się stało bez tego? *(podwójne liczenie: suma dla poda bez
  nazwy kontenera)*

---

## Po ćwiczeniach

- podinfo ma z powrotem 3 repliki: `kubectl -n demo get deploy podinfo`,
- w Alertmanagerze nie ma aktywnych wyciszeń,
- w Prometheusie alerty `Podinfo…` – *inactive*.

## Co powiedzieć na rozmowie

*"In my lab I use Prometheus, Alertmanager and Grafana. I can check target health, write basic
PromQL queries – for example memory and CPU per node – and read them as graphs. I triggered an
alert on purpose by scaling the demo app to zero, watched it go from pending to firing and reach
Alertmanager, and silenced it like you would during planned maintenance. I also built a simple
Grafana dashboard with memory per namespace and pod restarts."*

Mów to dopiero, gdy sam przejdziesz wszystkie poziomy.
