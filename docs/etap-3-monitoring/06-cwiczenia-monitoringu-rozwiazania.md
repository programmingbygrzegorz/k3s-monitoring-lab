# Etap 3 – rozwiązania ćwiczeń z monitoringu (wykonanie ze zrzutami)

Wykonanie poziomów z [ćwiczenia z monitoringu](05-cwiczenia-monitoringu.md) na klastrze labu, 30.10.2026, ze
zrzutami ekranu i prawdziwymi wynikami. Służy do porównania: zrób poziom sam, potem zajrzyj tutaj.

**Jak powstały zrzuty.** Poziomy 1–4, 6 i 7 wykonano automatycznie: polecenia `kubectl` przez SSH
na masterze, wyciszenie przez API Alertmanagera (`POST /api/v2/silences` – to samo, co robi
przycisk **Create** w przeglądarce), a zrzuty stron – przeglądarką Edge bez okna, sterowaną przez
DevTools Protocol. Poziomy w **Grafanie** (5 i 8) wymagają zalogowania hasłem, więc nie zostały
wykonane automatycznie – zamiast zrzutu Grafany przy poziomie 8 jest to samo zapytanie PromQL
w Prometheusie. Zrzuty Grafany dodasz po wykonaniu tych poziomów samodzielnie
(`docs/img/monitoring/`).

Na końcu przywrócono stan wyjściowy: podinfo ma 3 repliki, brak aktywnych wyciszeń, alerty
`Podinfo…` – *inactive*.

> **Czas na zrzutach.** Prometheus pokazuje godziny w **UTC** – o godzinę mniej niż zegar w Polsce
> zimą. Przełącznik strefy: ikona ustawień (koło zębate) → *Use local time*.

---

## Poziom 1 – co Prometheus zbiera

*Status → Target health*:

![Target health – podinfo, Grafana, Alertmanager](img/1-target-health.png)

- `serviceMonitor/demo/podinfo/0` – **3 / 3 up**: trzy repliki, każda pod własnym adresem poda
  (`10.42.2.19`, `10.42.3.11`, `10.42.1.15`) na porcie `9898`, ścieżka `/metrics`.
- Etykiety przy celu (`namespace`, `pod`, `service`, `job`…) Prometheus dokleja do każdej metryki
  z tego celu – po nich później filtrujesz.
- *Last scrape* – kiedy ostatnio pobrano dane (kilka sekund temu), obok czas pobrania (1–2 ms).

Filtr `node-exporter`:

![Target health – node-exporter](img/1-target-health-node-exporter.png)

Cztery cele z adresami **maszyn** (`192.168.180.51/52/53/55:9100`) – node-exporter działa
w sieci maszyny (`hostNetwork`), bo mierzy samą maszynę.

Surowe metryki, czyli to, co Prometheus pobiera z celu (na masterze):

```
$ curl -s http://192.168.180.52:9100/metrics | grep -E "^node_memory_Mem(Available|Total)_bytes"
node_memory_MemAvailable_bytes 4.779139072e+09
node_memory_MemTotal_bytes 5.6209408e+09
$ curl -s http://192.168.180.52:9100/metrics | wc -l
1353
```

Jedna strona node-exportera to ~1350 linii – Prometheus pobiera ją z każdego węzła co 30 sekund.

**Odpowiedzi:** podinfo ma 3 cele, bo ma 3 repliki; node-exporter 4, bo jest DaemonSetem na
4 węzłach. Podinfo nie ma na masterze – taint `NoSchedule`.

## Poziom 2 – pierwsze zapytania

`up` – zakładka *Table*:

![Zapytanie up](img/2-query-up.png)

Każdy wiersz to jeden cel z poziomu 1, wartość `1` – odpowiada.

`node_memory_MemAvailable_bytes / 1024 / 1024`:

![Wolna pamięć węzłów w MiB](img/2-query-pamiec.png)

| Część wiersza | Przykład | Co to jest |
|---|---|---|
| nazwa metryki | `node_memory_MemAvailable_bytes` | co mierzymy |
| etykiety | `{instance="192.168.180.51:9100", …}` | skąd – tu: master |
| wartość | `1787.1875` | wolne MiB w chwili zapytania |

| Węzeł | Wolna pamięć |
|---|---|
| master `.51` | ~1787 MiB |
| worker-2 `.53` | ~4180 MiB |
| worker-1 `.52` | ~4527 MiB |
| worker-3 `.55` | ~4776 MiB |

Porównanie z terminalem na masterze – kolumna *available*:

```
$ free -m
               total        used        free      shared  buff/cache   available
Mem:            3350        1636         857          85        1159        1714
```

`1714` w `free -m` a `1787` w Prometheusie – inny moment pomiaru (kilka minut różnicy), ta sama
metryka z jądra (`MemAvailable` z `/proc/meminfo`).

## Poziom 3 – historia na wykresie

Wolna pamięć, zakładka *Graph*, zakres `1h`:

![Wykres wolnej pamięci z ostatniej godziny](img/3-graph-pamiec.png)

Cztery prawie płaskie linie – lab nic nie robi. Dolna (~1,75 GiB) to master.

Zużycie CPU w procentach:

```
100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100
```

![Wykres CPU węzłów](img/3-graph-cpu.png)

`node_cpu_seconds_total{mode="idle"}` to licznik sekund bezczynności procesora. `rate(...[5m])`
zamienia go na „ile sekund bezczynności na sekundę” (0–1 na rdzeń), `avg by (instance)` uśrednia
rdzenie maszyny, a `100 - … * 100` odwraca bezczynność w zajętość w procentach.

Restarty kontenerów (`kube_pod_container_status_restarts_total`, *Table*):

![Liczniki restartów kontenerów](img/3-graph-restarty.png)

Licznik tylko rośnie – dlatego reguła `PodRestartingTooOften` liczy `increase(...[10m])`, czyli
przyrost w ostatnich 10 minutach, a nie samą wartość.

## Poziom 4 – reguły i alerty

*Status → Rule health*:

![Rule health](img/4-rule-health.png)

Każda grupa reguł z plikiem, z którego operator ją wygenerował (`/etc/prometheus/rules/…`), stan
`ok` i czas ostatniego obliczenia.

*Alerts*:

![Alerts – reguły labu inactive, alertmanager.rules firing](img/4-alerts-poczatek.png)

- `lab.demo-app`, `lab.nodes`, `lab.pods` – 5 reguł labu, wszystkie **INACTIVE** (zielone).
- `alertmanager.rules` – **FIRING (2)**: `AlertmanagerFailedToSendAlerts` i
  `AlertmanagerClusterFailedToSendAlerts` – przykładowy adres healthchecks.io
  ([problemy](problemy.md#alertmanagerfailedtosendalerts-zaraz-po-instalacji)).

Alertmanager (`:30093`):

![Alertmanager – alerty pogrupowane według odbiorcy](img/5-alertmanager-alerty.png)

Alerty pogrupowane według **odbiorcy**: `Watchdog` → `deadmans-switch` (trasa szczegółowa
z pliku values), reszta → `null` (trasa domyślna). Każda grupa ma etykiety z `group_by`
(`alertname`, `namespace`).

*Status* Alertmanagera – *Cluster Status: disabled* (jedna replika, opis w
[teorii](04-teoria-monitoringu.md#8-alertmanager--decyduje-kogo-powiadomić)):

![Alertmanager – status](img/5-alertmanager-status.png)

## Poziom 5 – gotowe dashboardy w Grafanie

Nie wykonano automatycznie – Grafana wymaga logowania hasłem. Do zrobienia samodzielnie według
[ćwiczenia z monitoringu](05-cwiczenia-monitoringu.md#poziom-5--gotowe-dashboardy-w-grafanie).

## Poziom 6 – narodziny alertu

```
$ kubectl -n demo get deploy podinfo
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
podinfo   3/3     3            3           93m

$ kubectl -n demo scale deployment podinfo --replicas=0
deployment.apps/podinfo scaled

$ kubectl -n demo get deploy,pods
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/podinfo   0/0     0            0           93m
```

Zero podów – lista podów jest pusta.

Stan alertów co ~10 sekund (z API Prometheusa), licząc od `scale` o 11:22:07:

| Czas | PodinfoDown | PodinfoDegraded | Co się dzieje |
|---|---|---|---|
| +0 s … +46 s | – | – | Prometheus jeszcze nie wie: kube-state-metrics musi zauważyć zmianę, Prometheus pobrać metryki (co 30 s), a reguła się obliczyć (co 30 s) |
| **+56 s** | **pending** | **pending** | warunek spełniony; zaczyna się odliczanie `for` |
| **+112 s** | **firing** | pending | minęła minuta (`for: 1m`) – alert idzie do Alertmanagera |
| **+171 s** | firing | **firing** | minęły 2 minuty (`for: 2m`) |

Zrzut przy *pending* (+56 s):

![PodinfoDown i PodinfoDegraded w stanie pending](img/6-alert-pending.png)

Zrzut przy *firing* (+112 s):

![PodinfoDown firing, PodinfoDegraded pending](img/6-alert-firing.png)

Alertmanager – nowe grupy `PodinfoDown` i `PodinfoDegraded` przy odbiorcy `null`:

![Alertmanager z alertami podinfo](img/6-alertmanager-podinfo.png)

Wykres dostępnych replik (`kube_deployment_status_replicas_available{namespace="demo"}`, 15 min) –
spadek z 3 do 0:

![Wykres replik podinfo spadający do zera](img/6-query-repliki.png)

**Odpowiedzi:**
- Od awarii do *firing* minęło **~1 min 52 s**: ~56 s, zanim Prometheus w ogóle zobaczył zmianę
  (pobieranie metryk + ocena reguły co 30 s), plus 1 minuta `for`. Do powiadomienia doszłoby
  jeszcze `group_wait: 30s` w Alertmanagerze. Monitoring zawsze ma takie opóźnienie – to cena za
  brak fałszywych alarmów.
- Dwa alerty naraz: `PodinfoDegraded` (< 3 repliki) też jest prawdziwy, gdy jest 0 replik. W
  produkcji ukrywa się go regułą **tłumienia** (inhibition): gdy aplikacja leży, „działa słabiej”
  nie jest już potrzebne.

## Poziom 7 – wyciszenie na czas prac

Wyciszenie utworzone przez API Alertmanagera – dokładnie to, co wysyła formularz **New Silence**:

```bash
curl -X POST -H 'Content-Type: application/json' http://192.168.180.51:30093/api/v2/silences -d '{
  "matchers": [{"name": "alertname", "value": "PodinfoDown", "isRegex": false, "isEqual": true}],
  "startsAt": "2026-10-30T10:25:35Z", "endsAt": "2026-10-30T11:25:35Z",
  "createdBy": "grzegorz", "comment": "Ćwiczenie – podinfo celowo wyłączone"}'
```

Zakładka *Silences* – jedno aktywne wyciszenie, koniec za godzinę, warunek `alertname="PodinfoDown"`:

![Lista wyciszeń – jedno aktywne](img/7-silences.png)

Szczegóły wyciszenia (*View*): kto, kiedy, do kiedy, komentarz i **Affected alerts: 1** – które
alerty obejmuje:

![Szczegóły wyciszenia](img/7-silence-szczegoly.png)

> **Nieudany komentarz.** Polskie litery w komentarzu zamieniły się w `�`. Wyciszenie wysłano
> poleceniem `curl` z Git Bash na Windowsie, który przekazał tekst w kodowaniu Windows (CP-1250),
> a Alertmanager oczekuje UTF-8. Z formularza w przeglądarce ten problem nie wystąpi. Wniosek:
> przy wysyłaniu danych przez API z Windowsa pilnuj kodowania (np. plik JSON zapisany w UTF-8
> i `curl -d @plik.json`) albo pisz komentarze bez polskich znaków.

Zakładka *Alerts*, domyślny widok – `PodinfoDown` **zniknął**, `PodinfoDegraded` został (wyciszenie
obejmuje tylko `alertname="PodinfoDown"`):

![Alerty bez wyciszonych](img/7-alerts-bez-wyciszonych.png)

Po zaznaczeniu **Silenced** – `PodinfoDown` wraca na listę:

![Alerty z wyciszonymi](img/7-alerts-wyciszone.png)

W Prometheusie w tym samym czasie oba alerty dalej **firing** (`PodinfoDegraded=firing
PodinfoDown=firing` z API) – wyciszenie działa tylko w Alertmanagerze: problem jest, ale nikt nie
dostaje powiadomień.

**Sprzątanie.** Wyciszenie wygaszone (`DELETE /api/v2/silence/<id>` – przycisk **Expire**,
odpowiedź `200`), potem:

```
$ kubectl -n demo scale deployment podinfo --replicas=3
deployment.apps/podinfo scaled

$ kubectl -n demo rollout status deployment/podinfo --timeout=120s
Waiting for deployment "podinfo" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "podinfo" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "podinfo" rollout to finish: 2 of 3 updated replicas are available...
deployment "podinfo" successfully rolled out

$ kubectl -n demo get pods -o wide
NAME                      READY   STATUS    RESTARTS   AGE   IP           NODE
podinfo-c9cdb7df5-j9jkm   1/1     Running   0          67s   10.42.3.12   k3s-worker-3
podinfo-c9cdb7df5-s6qlz   1/1     Running   0          67s   10.42.1.16   k3s-worker-2
podinfo-c9cdb7df5-xzb8w   1/1     Running   0          67s   10.42.2.20   k3s-worker-1
```

Nowe pody mają **nowe adresy IP** (`10.42.3.12` zamiast `10.42.3.11` itd.) – ServiceMonitor sam je
znalazł, bez zmiany konfiguracji Prometheusa.

Alerty `Podinfo…` zniknęły z *firing* po **~61 sekundach** od przywrócenia replik (znowu: pobranie
metryk + ocena reguły). Alerty labu wróciły do *inactive*:

![Alerty podinfo po sprzątaniu – inactive](img/7-po-sprzataniu.png)

Wykres replik z ostatnich 15 minut – spadek do 0 w poziomie 6 i powrót do 3:

![Wykres replik – spadek i powrót](img/7-query-repliki-powrot.png)

Aktywne wyciszenia po sprzątaniu: **0**.

**Odpowiedzi:**
- Wyciszenie nie zmienia reguły ani nie ukrywa problemu w Prometheusie – tylko zatrzymuje
  powiadomienia, na określony czas. Usunięcie reguły wyłączyłoby wykrywanie na zawsze, także
  wtedy, gdy ktoś zapomni ją przywrócić.
- Czas końca chroni przed wyciszeniem „zapomnianym” na tygodnie, a autor i komentarz mówią
  dyżurnemu, kto i dlaczego to zrobił.

## Poziom 8 – własny wykres w Grafanie

Dashboard w Grafanie nie został zbudowany automatycznie (logowanie hasłem). To samo zapytanie
w Prometheusie, wykres warstwowy (*Stacked*), 1 godzina:

```
sum by (namespace) (container_memory_working_set_bytes{container!=""})
```

![Pamięć według namespace – wykres warstwowy](img/8-query-pamiec-namespace.png)

| Warstwa | Namespace | Pamięć |
|---|---|---|
| górna (czerwona) | `monitoring` | ~887 MiB |
| środkowa (turkusowa) | `kube-system` | ~439 MiB |
| dolna (zielona) | `demo` | ~24 MiB – **znika o 10:22 UTC**, gdy w poziomie 6 podinfo zeszło do 0 replik |

Monitoring zużywa dwa razy więcej pamięci niż cały system k3s. W Grafanie zbudujesz ten sam
wykres jako panel – według [ćwiczenia z monitoringu, poziom 8](05-cwiczenia-monitoringu.md#poziom-8--własny-wykres-w-grafanie).

---

## Jak powstały zrzuty – dla ciekawych

Zrzut strony bez otwierania okna przeglądarki:

```bash
msedge --headless=new --window-size=1400,900 --screenshot=plik.png http://192.168.180.51:30090/targets
```

Wystarcza dla stron, które rysują się od razu (tabele). Wykresy Prometheusa rysują się dopiero po
pobraniu danych, a `--screenshot` robi zdjęcie za wcześnie – pusty wykres. Dlatego przeglądarka
była sterowana przez **DevTools Protocol** (ten sam mechanizm, którego używają Playwright
i Puppeteer): skrypt w Node.js uruchamia Edge, otwiera stronę, czeka kilka sekund naprawdę
i dopiero wtedy prosi o zrzut. Takie testy „przez przeglądarkę” to codzienność w CI/CD.
