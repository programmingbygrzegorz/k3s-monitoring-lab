# 4. Monitoring poza klastrem

## Dlaczego

Monitoring uruchomiony wyłącznie w klastrze padnie razem z nim – i nie dostaniesz alertu dokładnie wtedy,
gdy jest najbardziej potrzebny. Dlatego laboratorium ma trzy niezależne warstwy:

1. **Prometheus w klastrze** – pełny dostęp do metryk podów i zdarzeń.
2. **Grafana i Uptime Kuma na osobnej maszynie** – wizualizacja i sprawdzanie dostępności z zewnątrz.
3. **healthchecks.io** – dead man's switch dla całego monitoringu.

## Dead man's switch (healthchecks.io)

1. Załóż darmowe konto na https://healthchecks.io.
2. Utwórz nowy check: *Period* 1 minuta, *Grace* 5 minut.
3. Skopiuj adres pingu (`https://hc-ping.com/...`) do `HEALTHCHECKS_URL` w `lab.env`.
4. Uruchom ponownie `sudo ./scripts/04-install-monitoring.sh`.
5. Ustaw w healthchecks.io powiadomienia (e-mail, Telegram, Discord itp.).

Alertmanager co minutę wysyła alert `Watchdog`. Gdy przestanie przychodzić, healthchecks.io uzna,
że monitoring w klastrze nie działa, i wyśle powiadomienie.

## Grafana i Uptime Kuma

```bash
sudo ./scripts/06-setup-monitoring-vm.sh
```

**Grafana** (`http://<MONITORING_IP>:3000`) ma automatycznie skonfigurowane źródło danych
`Prometheus (k3s-lab)`. Dashboardy zaimportujesz z biblioteki Grafany: *Dashboards → New → Import*
i podaj ID, np. **1860** (*Node Exporter Full*).

**Uptime Kuma** (`http://<MONITORING_IP>:3001`) – przy pierwszym wejściu utwórz konto administratora,
a następnie dodaj monitory typu HTTP:

| Nazwa | Adres | Co sprawdza |
|---|---|---|
| podinfo – NodePort | `http://<MASTER_IP>:30898/healthz` | aplikacja odpowiada przez Service |
| podinfo – Ingress | `http://podinfo.lab.local/healthz` | pełna ścieżka: Traefik → Service → Pod |
| Prometheus | `http://<MASTER_IP>:30090/-/healthy` | monitoring w klastrze działa |
| API Kubernetesa | TCP `<MASTER_IP>:6443` | węzeł sterujący odpowiada |

Nazwa `podinfo.lab.local` jest ustawiona w `docker-compose.yml` (`extra_hosts`) na adres `k3s-worker-2`.

## Test

Wyłącz wszystkie trzy węzły klastra. W ciągu kilku minut powinieneś dostać:
alarm z Uptime Kuma i powiadomienie z healthchecks.io. Jeśli tak – monitoring jest zrobiony poprawnie.
