# 5. Scenariusze awarii

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

## Sprzątanie

```bash
sudo ./scripts/chaos.sh cleanup
```
