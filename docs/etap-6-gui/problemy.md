# Etap 6 – zarządzanie przez GUI – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Headlamp niedostępny z przeglądarki po instalacji

- **Objaw:** po `helm install` pod jest `Running`, ale `http://192.168.180.51:<port>` nie działa – nie wiadomo nawet, jaki port.
- **Przyczyna:** chart domyślnie tworzy Service typu `ClusterIP` (`80/TCP`) – adres tylko wewnątrz klastra.
- **Diagnoza:** `kubectl -n headlamp get svc` – `TYPE ClusterIP`, w `PORT(S)` brak drugiego numeru.
- **Rozwiązanie:** `helm upgrade … --reuse-values --set service.type=NodePort --set service.nodePort=30400`
  ([krok 3](01-headlamp.md#krok-3-dostęp-z-przeglądarki--nodeport)).
- **Wniosek:** przed instalacją sprawdź w `helm show values`, jak chart wystawia usługę.

## Ostrzeżenie Unhealthy: Readiness probe failed zaraz po starcie

- **Objaw:** w zdarzeniach `Readiness probe failed: … connect: connection refused` (liczba 2).
- **Przyczyna:** test gotowości bez `initialDelaySeconds` trafił, zanim aplikacja otworzyła port 4466.
- **Diagnoza:** `kubectl -n headlamp get events --sort-by=.lastTimestamp` – ostrzeżenie tylko tuż po `Started`;
  `kubectl -n headlamp get pod` – `1/1 Running`, 0 restartów.
- **Rozwiązanie:** żadne – samo minęło. Szczegóły: [01-headlamp.md](01-headlamp.md#pierwsze-ostrzeżenie-readiness-probe-failed).
- **Wniosek:** zdarzenie Warning to nie zawsze awaria – patrz na licznik, „ostatnio widziane” i stan poda.

## Headlamp w CrashLoopBackOff, Exit Code 139, puste logi (po awarii hosta)

- **Objaw (09.11.2026):** pod `headlamp-…` na `k3s-worker-1` – `0/1 CrashLoopBackOff`, **1079 restartów** od 06.11.
  `kubectl -n headlamp describe pod …` → `Last State: Terminated, Reason: Error, Exit Code: 139`, `Started` i
  `Finished` w tej samej sekundzie. `kubectl logs` i `kubectl logs --previous` – **puste**. Alerty
  `KubePodCrashLooping`, `KubePodNotReady`, `KubeDeploymentReplicasMismatch` aktywne od 06.11 – nikt ich nie widział,
  bo w Alertmanagerze trafiają do odbiorcy `null`.
- **Przyczyna (najbardziej prawdopodobna):** uszkodzona lokalna kopia obrazu `headlamp:v0.46.0` na worker-1 po twardym
  wyłączeniu hosta 05.11. Exit Code **139 = 128 + 11 = SIGSEGV** (segmentation fault) – program pada przy starcie,
  zanim cokolwiek wypisze; błąd konfiguracji dałby komunikat w logach. Kubelet widzi obraz jako „already present on
  machine”, więc nie pobiera go ponownie i w kółko uruchamia zepsuty plik.
- **Diagnoza:** `kubectl -n headlamp get pods -o wide` (węzeł, liczba restartów), `describe pod` (Exit Code, czasy),
  `logs --previous` (puste = program nie zdążył nic wypisać), `get events --sort-by=.lastTimestamp`.
- **Rozwiązanie:** na worker-1 `sudo k3s crictl rmi ghcr.io/headlamp-k8s/headlamp:v0.46.0`, na masterze
  `kubectl -n headlamp delete pod -l app.kubernetes.io/name=headlamp`. Nowy pod trafił na **worker-2**, pobrał obraz
  od nowa (108 MB, 49 s) → `1/1 Running`, 0 restartów. Ten sam obraz z sieci działa, kopia z worker-1 nie – usterka
  była lokalna dla worker-1, nie w Headlampie ani w konfiguracji.
- **Potwierdzenie (10.11, dziennik worker-1):** w uruchomieniu z 05.11 pod Headlampa wystartował o 20:21:17 po
  `1m14s` (świeżo pobrany obraz), a ostatni wpis tego uruchomienia jest z **20:21:33** – bez sekwencji wyłączania.
  Pliki obrazu były jeszcze w pamięci, nie na dysku. Szczegóły: [śledztwo w Etapie 4](../etap-4-monitoring-zewnetrzny/07-diagnoza-wezla-journalctl.md#8-śledztwo-skąd-zepsuty-obraz-headlampa).
- **Pomyłki po drodze:** `crictl rmi` na **masterze** → `no such image` (każdy węzeł ma własny magazyn obrazów);
  `kubectl` na **workerze** → `localhost:8080 … connection refused` (kubeconfig jest tylko na masterze – i dobrze).
- **Wniosek:** po twardym wyłączeniu maszyn sprawdź `kubectl get pods -A | grep -v Running` – zepsute pliki obrazów
  nie naprawią się restartami. A alerty bez odbiorcy są bezużyteczne: awaria trwała 3 dni niezauważona.
