# Etap 3 – monitoring w klastrze

Co powstaje: Helm, Prometheus, Alertmanager i Grafana (kube-prometheus-stack), aplikacja demo
podinfo i reguły alertów.

Polecenia krok po kroku: [przewodnik, kroki 26–32](../00-przewodnik.md#etap-3--monitoring-w-klastrze).

## Etap 3 w pigułce – zacznij tutaj

**Jedno polecenie tworzy wszystko.** Nikt nie zakłada podów ręcznie – zamawiasz gotowy zestaw,
a automaty rozpakowują go na części:

```
① Ty:        helm upgrade --install monitoring prometheus-community/kube-prometheus-stack ...
                  │
② Helm:      pobiera gotową paczkę (chart), wypełnia jej szablony ustawieniami z pliku values
             i wysyła do klastra 99 obiektów (30 zestawów reguł alertów, 28 ConfigMap
             z dashboardami, 9 ServiceMonitorów, Service'y, uprawnienia…), w tym:
                  │
③ Kubernetes: ├── Deployment grafana            → pod grafana
              ├── Deployment kube-state-metrics → pod kube-state-metrics
              ├── Deployment operator           → pod operator
              ├── DaemonSet node-exporter       → 4 pody, po jednym na każdym węźle
              └── „zamówienia” Prometheus i Alertmanager (obiekty, nie programy)
                  │
④ Operator:  czyta „zamówienia” i sam tworzy pody prometheus-…-0 i alertmanager-…-0
```

**Co powstało – 9 podów, 6 programów** (`kubectl -n monitoring get pods -o wide`):

| Słowo w nazwie poda | Rola | Ile | W przeglądarce |
|---|---|---|---|
| `prometheus` | **mózg i pamięć**: co 30 s zbiera dane, przechowuje je, sprawdza reguły alertów | 1 | `:30090` |
| `alertmanager` | **dyspozytor alarmów**: grupuje, wycisza, wysyła dalej | 1 | `:30093` |
| `grafana` | **wykresy** i dashboardy z danych Prometheusa | 1 | `:30300` |
| `node-exporter` | **czujnik maszyny**: CPU, pamięć, dysk | 4 – jeden na węzeł | – |
| `kube-state-metrics` | **czujnik Kubernetesa**: repliki, restarty, stan węzłów | 1 | – |
| `operator` | **kierownik w tle**: pilnuje Prometheusa i Alertmanagera | 1 | – |

```
 czujniki                          mózg                   wyjścia
 node-exporter ×4  (maszyny)  ─┐
                               ├─▶  prometheus  ──▶  grafana       (wykresy)
 kube-state-metrics (klaster) ─┘        └───────▶  alertmanager  (alarmy)
```

Długie nazwy podów (`prometheus-monitoring-kube-prometheus-prometheus-0`) to „adres”: program +
nazwa instalacji (`monitoring`) + nazwa paczki + rola + numer. Wystarczy szukać w nich słowa
z tabeli. Szczegóły:
[jak czytać nazwy podów](01-instalacja-monitoringu.md#krok-4-instalacja) – tabele „Co robi każdy pod” i „Skąd tak długie nazwy”.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-instalacja-monitoringu.md](01-instalacja-monitoringu.md) | instalacja ręczna krok po kroku, każde polecenie wyjaśnione |
| 2 | [02-plik-values.md](02-plik-values.md) | co robi każda linia pliku values |
| 3 | [03-teoria-kubernetes-helm.md](03-teoria-kubernetes-helm.md) | teoria: węzły, kubeconfig, Helm, chart, release, CRD, operator |
| 4 | [04-teoria-monitoringu.md](04-teoria-monitoringu.md) | teoria: Prometheus, ServiceMonitor, PromQL, alerty, Alertmanager, Grafana |
| 5 | [05-cwiczenia-monitoringu.md](05-cwiczenia-monitoringu.md) | **ćwiczenia**, 8 poziomów – zrób je sam |
| 6 | [06-cwiczenia-monitoringu-rozwiazania.md](06-cwiczenia-monitoringu-rozwiazania.md) | **rozwiązania** ćwiczeń ze zrzutami – porównaj po wykonaniu |
| – | [07-symulator-servicemonitor.html](07-symulator-servicemonitor.html) | interaktywny symulator ServiceMonitor → Service → pody: pobierz plik i otwórz w przeglądarce |
| – | [problemy.md](problemy.md) | problemy z tego etapu: Helm, ErrImagePull, Alertmanager |

Pierwszy raz z Kubernetesem? Przeczytaj pliki 3 i 4 przed instalacją albo w jej trakcie.

Następny etap: [Etap 4 – monitoring poza klastrem](../etap-4-monitoring-zewnetrzny/README.md).
