# Etap 5 – scenariusze awarii

Każdy scenariusz opisuj w sekcji „Czego się nauczyłem” w README: co się stało, co pokazał monitoring,
jak znalazłeś przyczynę i jak ją usunąłeś.

## Awaria węzła

1. Wyłącz maszynę `k3s-worker-1` (twarde wyłączenie w VMware).
2. Obserwuj: `kubectl get nodes -w` oraz `kubectl -n demo get pods -o wide -w`.
3. Oczekiwane:
   - po ok. 50 s węzeł przechodzi w `NotReady`; alert `KubeNodeNotReady` jest najpierw `pending`, a `firing` dopiero po 15 min (`for: 15m`),
   - po ok. 5 minutach pody z wyłączonego węzła są tworzone na `k3s-worker-2`,
   - w tym czasie aplikacja działa dalej dzięki replikom na drugim węźle.
4. Włącz węzeł z powrotem i sprawdź, czy wrócił do stanu `Ready`.

Pytanie do przemyślenia: dlaczego Kubernetes czeka kilka minut, zanim przeniesie pody?
Odpowiedź: chwilowy brak sieci nie powinien od razu przenosić wszystkiego. Każdy pod dostaje
automatycznie tolerancję `node.kubernetes.io/unreachable` z `tolerationSeconds: 300`
(sprawdzisz: `kubectl -n hello-lab get pod <pod> -o jsonpath='{.spec.tolerations}'`).

### Co się dzieje z podami, gdy węzeł pada

Oś czasu po twardym wyłączeniu workera:

| Czas | Co się dzieje |
|---|---|
| 0 s | maszyna wyłączona; pody na niej przestają działać od razu |
| ok. 50 s | węzeł `NotReady` (status `Unknown`), pody z niego znikają z endpointów Service |
| ok. 5 min | pody węzła dostają status `Terminating`, kontrolery tworzą nowe na zdrowych węzłach |
| po włączeniu | węzeł `Ready`, stare pody są sprzątane; **nowe nie wracają same** na ten węzeł |

Co przeżyje, a co nie, zależy od rodzaju obiektu:

| Obiekt | Co po awarii węzła |
|---|---|
| Deployment z kilkoma replikami na **różnych** węzłach | aplikacja działa cały czas, przez 5 min z mniejszą liczbą replik |
| Deployment z 1 repliką albo wszystkie repliki na jednym węźle | **przerwa ok. 5–6 min**, potem pod startuje gdzie indziej |
| StatefulSet (Prometheus, Alertmanager) | pod **nie** jest odtwarzany, dopóki węzeł nie wróci albo nie usuniesz poda ręcznie (`kubectl delete pod … --force --grace-period=0`) – StatefulSet nie dopuszcza dwóch kopii tego samego poda |
| DaemonSet (node-exporter, svclb) | na tym węźle po prostu nie działa; nigdzie się nie przenosi |
| pod bez kontrolera (`kubectl run`) | znika na zawsze |
| dane w `emptyDir` | **tracone** razem z podem |
| dane w PVC `local-path` | leżą na dysku tego węzła; pod może wystartować **tylko tam** – czeka na powrót węzła |

### Co jest zagrożone w naszym klastrze (stan 03.11.2026)

Wynik `kubectl get pods -A -o wide` i `kubectl get deploy,sts -A`:

| Węzeł | Pojedyncze pody (1 replika) |
|---|---|
| k3s-master | `coredns`, `metrics-server`, `local-path-provisioner` |
| k3s-worker-2 | `prometheus-…-0`, `prometheus-operator`, `kube-state-metrics` |
| k3s-worker-3 | `alertmanager-…-0`, `grafana`, `traefik` |

Wnioski:

- **worker-3 to najgorszy węzeł do wyłączenia:** jednocześnie znika Grafana i Alertmanager,
  czyli monitoring nie wyśle alertu o własnej awarii. Dlatego potrzebny jest monitoring
  **poza klastrem** (healthchecks.io i Uptime Kuma na `monitoring`, Etap 4).
- **Prometheus trzyma dane w `emptyDir`** (`kubectl get pvc -A` → `No resources found`).
  Po przeniesieniu na inny węzeł zaczyna z pustą bazą – znika historia metryk.
- `podinfo` (3 repliki) i `hello-lab` (2 repliki) mają kopie na dwóch węzłach – przeżyją.
  Ale `podinfo` ma 2 z 3 replik na worker-3: scheduler rozkłada pody „zwykle” równo, nie zawsze.
- **Master jest jeden.** Gdy padnie, działające pody na workerach dalej pracują, ale nie da się
  nic zmienić (`kubectl` nie działa), nic nie zostanie naprawione ani przeniesione, a do tego
  przestaje działać DNS w klastrze (jedyny `coredns` jest na masterze).

### Przewidywanie: wyłączenie k3s-worker-3

Na podstawie stanu klastra (k3s v1.36.5, reguły kube-prometheus-stack). Zapisz przed
ćwiczeniem, a po nim porównaj z tym, co naprawdę zobaczyłeś.

| Czas | Aplikacje | Monitoring |
|---|---|---|
| 0–50 s | `podinfo`, `hello-lab`, `web` odpowiadają **z przerwami** – Service dalej wysyła część ruchu do martwych podów. Grafana (`:30300`) i traefik nie działają wcale | Prometheus (worker-2) działa; cel `node-exporter` worker-3 ma `up = 0` |
| ok. 50 s | węzeł `NotReady`, martwe pody wypadają z endpointów – aplikacje znów odpowiadają za każdym razem (z worker-1 i worker-2) | `KubeNodeNotReady` w stanie `pending` |
| ok. 5 min 50 s | pody worker-3 → `Terminating`; nowe `grafana`, `traefik`, 2× `podinfo`, `hello-lab`, 2× `web` startują na worker-1/2 (miejsca wystarczy – workery mają zajęte ok. 10% CPU i pamięci). Grafana wraca, ale bez zmian zrobionych ręcznie w UI (`emptyDir`); dashboardy z ConfigMap są | `alertmanager-…-0` wisi w `Terminating` i **nie jest odtwarzany** (StatefulSet) |
| 10–15 min | – | `TargetDown` (10 min) i `KubeNodeNotReady` (15 min) przechodzą w `firing`, ale **nikt nie dostaje powiadomienia** – Alertmanager nie działa. Alert widać tylko w Prometheusie `:30090` → Alerts |
| po włączeniu | węzeł `Ready`, pody `Terminating` znikają. Przeniesione pody **zostają** na worker-1/2 – worker-3 jest prawie pusty | `alertmanager-…-0` startuje od nowa (bez historii wyciszeń) |

### Jak się przed tym zabezpieczyć

| Sposób | Co daje |
|---|---|
| `replicas: 2` lub więcej | jest kopia, która przejmuje ruch |
| `topologySpreadConstraints` (`topologyKey: kubernetes.io/hostname`) albo `podAntiAffinity` | **wymusza** repliki na różnych węzłach, a nie tylko „zwykle” |
| `PodDisruptionBudget` (`minAvailable: 1`) | `kubectl drain` przy konserwacji nie zabierze wszystkich replik naraz (nie chroni przed awarią sprzętu) |
| PVC na pamięci sieciowej (NFS, Longhorn, dysk w chmurze) | dane nie są przywiązane do jednego węzła; pod może wstać gdziekolwiek |
| HA control plane: 3 mastery z wbudowanym etcd (`k3s server --cluster-init`) | klaster działa po utracie jednego mastera (potrzebna większość: 2 z 3) |
| monitoring z zewnątrz klastra | alert dochodzi nawet wtedy, gdy klaster leży |

Przykład rozkładania replik na różne węzły (fragment `spec.template.spec` Deploymentu):

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: podinfo
```

`maxSkew: 1` oznacza: na żadnym węźle nie może być o więcej niż 1 pod więcej niż na innym.

**Pytania rekrutacyjne:**

- *Węzeł padł. Po jakim czasie pody pojawią się gdzie indziej?* Po ok. 50 s węzeł jest
  `NotReady`, po kolejnych ok. 5 min (`tolerationSeconds: 300`) pody są tworzone na innych węzłach.
  Dotyczy to Deploymentów; StatefulSet czeka, aż węzeł wróci albo ktoś usunie pod ręcznie.
- *Masz 3 repliki. Czy to gwarantuje wysoką dostępność?* Nie – mogą trafić na jeden węzeł.
  Trzeba `topologySpreadConstraints` lub `podAntiAffinity`, a przy konserwacji `PodDisruptionBudget`.
- *Co się stanie z klastrem, gdy padnie jedyny master?* Działające aplikacje pracują dalej, ale
  nie ma API: brak zmian, samonaprawy i przenoszenia podów. Rozwiązanie: 3 mastery (etcd potrzebuje większości).

## OOMKilled

```bash
sudo ./scripts/chaos.sh oom
kubectl -n chaos get pods -w
kubectl -n chaos describe pod -l scenario=oom    # Last State: Terminated, Reason: OOMKilled
```

W Grafanie: zużycie pamięci kontenera dochodzi do limitu. Alert: `ContainerOOMKilled`.
Rozwiązanie w praktyce: zwiększenie limitu albo znalezienie przyczyny dużego zużycia pamięci w aplikacji.

## CrashLoopBackOff

```bash
sudo ./scripts/chaos.sh crashloop
kubectl -n chaos logs -l scenario=crashloop --previous
```

Logi pokazują przyczynę (brak pliku konfiguracyjnego). Odstępy między restartami rosną (back-off).
Alerty: `PodRestartingTooOften`, a po dłuższym czasie `KubePodCrashLooping`.

## ImagePullBackOff

```bash
sudo ./scripts/chaos.sh imagepull
kubectl -n chaos describe pod -l scenario=imagepull   # sekcja Events
```

Typowe przyczyny w praktyce: literówka w nazwie lub tagu, prywatny rejestr bez danych logowania,
limit pobrań z Docker Hub.

## Obciążenie CPU

```bash
sudo ./scripts/chaos.sh cpu
kubectl top pods -n chaos
```

W Grafanie (*Kubernetes / Compute Resources / Pod*) widać, że kontener jest ograniczany do limitu 500m
(CPU throttling), a nie zabijany – inaczej niż przy pamięci.

## Błędne wdrożenie i wycofanie

```bash
sudo ./scripts/chaos.sh bad-deploy
```

Skrypt wdraża nieistniejącą wersję obrazu, pokazuje historię wdrożeń i wycofuje zmianę przez
`kubectl rollout undo`. Dzięki `maxUnavailable: 1` aplikacja działa przez cały czas.

## Awaria całego klastra

Wyłącz wszystkie węzły. Oczekiwane: alarm w Uptime Kuma i powiadomienie z healthchecks.io
(brak alertu `Watchdog`).

## Ćwiczenie: własna reguła alertu

Reguły w labie przyszły z chartu albo z repozytorium ([instalacja monitoringu](../etap-3-monitoring/01-instalacja-monitoringu.md#własne-alerty)).
W tym ćwiczeniu piszesz **własną** – od zapytania do alertu w stanie *firing*.

Cel: alert `NodeDiskAlmostFull`, gdy główny dysk (`/`) któregoś węzła jest zapełniony w ponad 85%.

**1. Najpierw zapytanie – w Prometheusie** (`http://192.168.180.51:30090`, *Query*):

```
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100
```

Zobaczysz zajętość dysku w % dla każdego węzła. Zawsze zaczynaj od samego zapytania: jeśli nie
zwraca danych, reguła też nic nie wykryje.

| Część | Znaczenie |
|---|---|
| `node_filesystem_avail_bytes` | wolne miejsce w bajtach (z node-exportera) |
| `node_filesystem_size_bytes` | rozmiar systemu plików |
| `{mountpoint="/"}` | tylko główny dysk, bez `/boot` i systemów tymczasowych |
| `1 - wolne/rozmiar` | ułamek zajętego miejsca; `* 100` – procenty |

**2. Reguła – dopisz na końcu pliku** `kubernetes/monitoring/prometheusrule-lab.yaml`
(na masterze: `nano ~/k3s-monitoring-lab/kubernetes/monitoring/prometheusrule-lab.yaml`),
z takimi samymi wcięciami jak grupa `lab.nodes`:

```yaml
        - alert: NodeDiskAlmostFull
          expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Dysk na {{ $labels.instance }} prawie pełny"
            description: "Zajęte {{ $value | humanizePercentage }} głównego systemu plików."
```

`humanizePercentage` zamienia `0.87` na `87%`. Wcięcia w YAML to spacje – zła liczba spacji to
najczęstszy błąd.

**3. Sprawdzenie i wdrożenie:**

```bash
kubectl apply --dry-run=server -f ~/k3s-monitoring-lab/kubernetes/monitoring/prometheusrule-lab.yaml
kubectl apply -f ~/k3s-monitoring-lab/kubernetes/monitoring/prometheusrule-lab.yaml
```

`--dry-run=server` wysyła obiekt do API bez zapisywania – **webhook operatora** sprawdzi przy
tym poprawność reguły (zły PromQL = błąd od razu, a nie zepsuta reguła w Prometheusie).

Po ~1 minucie: *Status → Rule health* – reguła `NodeDiskAlmostFull` w stanie `ok`;
*Alerts* – w stanie *inactive*.

**4. Wywołanie alertu.** Żeby zobaczyć *pending* → *firing* bez zapełniania dysku, zmień
tymczasowo próg z `0.85` na wartość **niższą** niż obecna zajętość (np. `0.10`) i `for` na `1m`,
wykonaj `kubectl apply`, obserwuj stronę *Alerts*. Potem przywróć `0.85` i `10m`.

**5. Do gita** – to Twoja reguła:

```bash
cd ~/k3s-monitoring-lab && git diff && git add kubernetes/monitoring/prometheusrule-lab.yaml && git commit -m "Alert NodeDiskAlmostFull"
```

Na rozmowie: *"I wrote a custom alert rule – I tested the PromQL query in Prometheus first,
validated it with a server-side dry run and deployed it as a PrometheusRule."*

## Sprzątanie

```bash
sudo ./scripts/chaos.sh cleanup
```
