# 3. Monitoring w klastrze

Pierwszy raz z Kubernetesem lub Helmem? Pojęcia (chart, values, release, Traefik, CRD, operator)
wyjaśnia [docs/teoria-kubernetes-helm.md](teoria-kubernetes-helm.md). Co robi każda linia pliku values –
[docs/03a-values-monitoringu.md](03a-values-monitoringu.md).

## Instalacja

```bash
sudo ./scripts/04-install-monitoring.sh
sudo ./scripts/05-deploy-demo.sh
```

Instalowany jest chart **kube-prometheus-stack** z wartościami z `monitoring/kube-prometheus-stack-values.yaml`.

| Komponent | Rola |
|---|---|
| Prometheus | zbiera i przechowuje metryki |
| node-exporter | metryki węzłów: CPU, RAM, dysk, sieć |
| kube-state-metrics | stan obiektów Kubernetesa: pody, Deploymenty, restarty |
| Alertmanager | grupuje alerty i wysyła powiadomienia |
| Grafana | dashboardy |

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
