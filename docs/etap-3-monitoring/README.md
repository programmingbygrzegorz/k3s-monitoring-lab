# Etap 3 – monitoring w klastrze

Co powstaje: Helm, Prometheus, Alertmanager i Grafana (kube-prometheus-stack), aplikacja demo
podinfo i reguły alertów.

Polecenia krok po kroku: [przewodnik, kroki 26–32](../00-przewodnik.md#etap-3--monitoring-w-klastrze).

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
