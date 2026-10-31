# Etap 5 – scenariusze awarii

Każdy scenariusz opisuj w sekcji „Czego się nauczyłem” w README: co się stało, co pokazał monitoring,
jak znalazłeś przyczynę i jak ją usunąłeś.

## Awaria węzła

1. Wyłącz maszynę `k3s-worker-1` (twarde wyłączenie w VMware).
2. Obserwuj: `kubectl get nodes -w` oraz `kubectl -n demo get pods -o wide -w`.
3. Oczekiwane:
   - po ok. 40 s węzeł przechodzi w `NotReady`, pojawia się alert `KubeNodeNotReady`,
   - po ok. 5 minutach pody z wyłączonego węzła są tworzone na `k3s-worker-2`,
   - w tym czasie aplikacja działa dalej dzięki replikom na drugim węźle.
4. Włącz węzeł z powrotem i sprawdź, czy wrócił do stanu `Ready`.

Pytanie do przemyślenia: dlaczego Kubernetes czeka kilka minut, zanim przeniesie pody?

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
