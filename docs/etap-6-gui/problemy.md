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
