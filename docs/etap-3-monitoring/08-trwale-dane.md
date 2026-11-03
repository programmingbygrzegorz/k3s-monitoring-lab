# Etap 3 – trwałe dane monitoringu (local-path)

Po instalacji z Etapu 3 Prometheus, Grafana i Alertmanager trzymają dane w `emptyDir` – katalogu
tymczasowym, który znika razem z podem. Usunięcie poda, `helm upgrade` czy awaria węzła kasuje
historię metryk, ustawienia Grafany zrobione w przeglądarce i wyciszenia alertów.

Ten rozdział włącza **trwałe dyski** bez podłączania nowego dysku: k3s ma wbudowaną klasę
pamięci `local-path`, która wydziela katalog na dysku węzła (`/var/lib/rancher/k3s/storage`).

Czas: ok. 20 minut. **Przed startem:** Etap 3 zakończony, 4 węzły `Ready`.
📸 Snapshot – opcjonalny (zmiana da się wycofać `helm rollback`).

⚠️ Jednorazowa strata: przy tej zmianie Prometheus zacznie z pustą bazą, a Grafana straci to,
co zrobiłeś ręcznie w przeglądarce. Obecne dane leżą w `emptyDir` – nie da się ich przenieść.

## Pojęcia – analogia z urzędem

| Pojęcie | Analogia | W labie |
|---|---|---|
| **PVC** (PersistentVolumeClaim) | wniosek: „potrzebuję 10 GB na stałe” | składa go Grafana albo operator (za Prometheusa i Alertmanagera) |
| **StorageClass** | urzędnik, który rozpatruje wnioski | `local-path` (domyślna w k3s) |
| **PV** (PersistentVolume) | przydzielone miejsce | katalog `/var/lib/rancher/k3s/storage/pvc-…` na dysku węzła |
| **Bound** | wniosek załatwiony, PVC połączony z PV | status w `kubectl get pvc` |
| `WaitForFirstConsumer` | urzędnik czeka, aż ktoś przyjdzie po klucze | PV powstaje dopiero na węźle, na którym wystartuje pod |
| `ReadWriteOnce` (RWO) | klucz tylko dla jednego węzła | dysk może być podłączony do podów na jednym węźle naraz |

Pod usuwa się i tworzy na nowo, a PVC i PV zostają. Nowy pod podłącza ten sam katalog, więc
dane przeżywają.

## Skąd bierze się PVC i miejsce na dysku

Kolejność zdarzeń po `helm upgrade`:

```
① Helm / operator   tworzy PVC (wniosek): „10Gi, klasa local-path”         → PVC Pending
② scheduler         wybiera węzeł dla poda Prometheusa, np. k3s-worker-2
③ local-path-provisioner (pod w kube-system, działa na masterze) widzi PVC
                    i uruchamia na k3s-worker-2 pomocniczy pod helper-pod-…,
                    który robi mkdir /var/lib/rancher/k3s/storage/pvc-<id>_monitoring_<nazwa>
④ provisioner       tworzy PV wskazujący ten katalog, przypięty do k3s-worker-2 → PVC Bound
⑤ kubelet           montuje katalog w kontenerze (Prometheus widzi go jako /prometheus)
```

Ścieżkę ustawia ConfigMapa provisionera (wynik z labu):

```
$ kubectl -n kube-system get configmap local-path-config -o jsonpath='{.data.config\.json}'
{ "nodePathMap":[ { "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES",
                    "paths":["/var/lib/rancher/k3s/storage"] } ] }
```

**Miejsce pochodzi z głównego dysku workera** – tego samego, na którym jest system, obrazy
kontenerów i logi. Na k3s-worker-2:

```
$ lsblk
sda                         40G disk            ← wirtualny dysk VMware
├─sda2                       2G part /boot
└─sda3                      38G part
  └─ubuntu--vg-ubuntu--lv   38G lvm  /           ← tu jest też /var/lib/rancher/k3s/storage
$ df -h /var/lib/rancher/k3s
/dev/mapper/ubuntu--vg-ubuntu--lv   38G   11G   25G  32% /
```

Wnioski:

- **Nic nie jest rezerwowane.** `10Gi` w PVC to tylko opis – katalog zajmuje tyle, ile faktycznie
  zapisze Prometheus, i może urosnąć ponad 10Gi. Ogranicza go `retention: 7d`.
- **Dane monitoringu konkurują z systemem o te same 25 GB.** Gdy dysk zapełni się w ok. 85–90%,
  kubelet zgłasza `DiskPressure` i zaczyna wyrzucać pody
  ([Evicted](../etap-5-scenariusze-awarii/02-typowe-awarie-kubernetesa.md#316-evicted--pody-wyrzucone-z-węzła)).
  Pilnuje tego alert `NodeDiskAlmostFull` z Etapu 5.
- Dodatkowy dysk nie jest potrzebny. W firmach dane trzyma się jednak na **osobnym dysku**:
  w VMware dodaje się drugi dysk do workera, formatuje i montuje np. w `/mnt/dane`, a potem
  wpisuje tę ścieżkę do `local-path-config` (`"paths":["/mnt/dane"]`). Wtedy pełny dysk z danymi
  nie zatrzyma systemu.

## Co zmienia się w pliku values

W [monitoring/kube-prometheus-stack-values.yaml](../../monitoring/kube-prometheus-stack-values.yaml)
doszły trzy bloki:

```yaml
grafana:
  persistence:
    enabled: true              # zamiast emptyDir – PVC
    storageClassName: local-path
    size: 2Gi                  # baza SQLite Grafany zajmuje kilka MB, 2Gi to zapas

prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:     # wzór wniosku – operator złoży go za Prometheusa
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi    # metryki z 7 dni (retention: 7d) w labie to ok. 1–2 GB

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:     # to samo dla Alertmanagera: wyciszenia i zapis powiadomień
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi
```

Dlaczego Grafana ma `persistence`, a Prometheus `volumeClaimTemplate`? Grafana to Deployment
z jednym PVC. Prometheus i Alertmanager to StatefulSety, a te dostają **wzór** wniosku – każda
replika (`-0`, `-1`…) składa według niego własny PVC.

`local-path` nie pilnuje rozmiaru: `10Gi` to tylko opis wniosku, a pod może zapisać tyle, ile
jest wolnego miejsca na dysku węzła. Pilnuje tego `retention: 7d`.

## Co jeszcze w labie potrzebuje trwałych danych

Zasada: trwały dysk potrzebny jest tam, gdzie program **sam tworzy dane**, których nie da się
odtworzyć z gita, obrazu czy ConfigMapy. Przegląd wolumenów wszystkich podów
(`kubectl get pods -A -o jsonpath=…` po `.spec.volumes`) i kontenerów Dockera (`docker inspect`):

| Usługa | Gdzie | Trwałe dane? | Stan |
|---|---|---|---|
| Prometheus, Grafana, Alertmanager | klaster | **tak** – metryki, ustawienia, wyciszenia | ten rozdział |
| **baza klastra k3s** (wszystkie obiekty) | master, `/var/lib/rancher/k3s/server/db` (SQLite) | **tak – najważniejsze** | na dysku mastera, poza podami; kopię robi snapshot VMware |
| rejestr obrazów `registry:3` | `monitoring`, Docker | **tak** – obrazy | ✅ wolumen Dockera `rejestr-dane` → `/var/lib/registry` |
| Grafana i Uptime Kuma (Etap 4) | `monitoring`, docker compose | **tak** | ✅ wolumeny `grafana-data`, `uptime-kuma-data` w [docker-compose.yml](../../monitoring/monitoring-vm/docker-compose.yml) |
| coredns, metrics-server, local-path-provisioner | klaster | nie – konfiguracja z ConfigMap | – |
| traefik | klaster | nie – w labie nie wystawia certyfikatów Let's Encrypt (wtedy trzymałby je w `/data`) | – |
| operator, kube-state-metrics, node-exporter | klaster | nie – tylko czytają i przeliczają | – |
| podinfo, hello-lab, ćwiczenia | klaster | nie – aplikacje bezstanowe | – |

Na przyszłość (dane własne – trzeba zaplanować dysk i kopię): GitLab (Etap 7: repozytoria, baza),
Semaphore i Portainer (Etap 6: baza ustawień), Wazuh (Etap 9b: zdarzenia bezpieczeństwa).
Nie potrzebują: Headlamp, Argo CD (stan bierze z gita i klastra), Kyverno, Falco.

## Krok 1. Pobierz zmiany na masterze

🪟 Windows:

```powershell
ssh k3s-master
```

🐧 k3s-master:

```bash
cd ~/k3s-monitoring-lab
git pull
```

- `git pull` pobiera z GitHuba nowe commity, w tym zmieniony plik values.
- Plik `api.yaml` z ćwiczeń z kubectl (nieśledzony, `??` w `git status`) nie przeszkadza.

**Co powinieneś zobaczyć:** `Fast-forward` i listę plików, w niej
`monitoring/kube-prometheus-stack-values.yaml`.

Obejrzyj samą zmianę:

```bash
git log -1 -p -- monitoring/kube-prometheus-stack-values.yaml
```

`-p` pokazuje różnice: linie z `+` zostały dopisane.

## Krok 2. Przypnij wersję chartu

```bash
grep KPS_CHART_VERSION lab.env
```

Jeśli wynik to `KPS_CHART_VERSION=` (pusto), skrypt pobrałby **najnowszą** wersję chartu
i przy okazji zaktualizował wszystkie programy monitoringu. Chcesz zmienić jedną rzecz naraz,
więc przypnij wersję, którą masz zainstalowaną:

```bash
helm list -n monitoring
sed -i 's/^KPS_CHART_VERSION=$/KPS_CHART_VERSION=92.16.1/' lab.env
grep KPS_CHART_VERSION lab.env
```

- `helm list` – kolumna `CHART` pokazuje `kube-prometheus-stack-92.16.1`.
- `sed -i 's/stare/nowe/' plik` zamienia tekst w pliku. `^` = początek linii, `$` = koniec,
  więc zmieni się tylko pusta linia `KPS_CHART_VERSION=`.

**Co powinieneś zobaczyć:** `KPS_CHART_VERSION=92.16.1`.

## Krok 3. Stan przed zmianą

```bash
kubectl get storageclass
kubectl get pvc -A
helm history monitoring -n monitoring
```

**Co powinieneś zobaczyć:**

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ...
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   ...
No resources found
REVISION  UPDATED  STATUS    CHART                          ...
1         ...      deployed  kube-prometheus-stack-92.16.1  ...
```

Jest klasa `local-path` (`(default)` = używana, gdy PVC nie poda klasy), nie ma żadnego PVC,
a release ma jedną wersję (rewizję).

## Krok 4. Podgląd bez instalacji

```bash
helm template monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 \
  -n monitoring -f monitoring/kube-prometheus-stack-values.yaml \
  | grep -E 'kind: PersistentVolumeClaim|storage: "?[0-9]+Gi|storageClassName'
```

- `helm template` tylko **generuje** obiekty i wypisuje je na ekran, niczego nie wysyła do klastra.
- `grep -E` zostawia linie o dyskach.

**Co powinieneś zobaczyć** (wynik z labu):

```
kind: PersistentVolumeClaim
      storage: "2Gi"
  storageClassName: local-path
            storage: 1Gi
        storageClassName: local-path
            storage: 10Gi
        storageClassName: local-path
```

Jeden gotowy PVC (Grafana, 2Gi) i dwa wzory (Alertmanager 1Gi, Prometheus 10Gi).

## Krok 5. Aktualizacja

Otwórz **drugi terminal** i najpierw zaloguj się na mastera (🪟 `ssh k3s-master`). Nowe okno
startuje na Windowsie – tam `kubectl` zgłosi błąd `localhost:8080`
([problem](problemy.md#kubectl-w-drugim-terminalu-localhost8080-refused-windows)). Potem obserwuj zmiany na żywo:

```bash
kubectl -n monitoring get pods,pvc -w
```

`-w` (watch) dopisuje każdą zmianę. Zakończysz `Ctrl+C`.

W pierwszym terminalu:

```bash
sudo ./scripts/04-install-monitoring.sh
```

Skrypt robi `helm upgrade` z Twoim plikiem values (szczegóły w nagłówku
[skryptu](../../scripts/04-install-monitoring.sh)). Trwa 1–5 minut, bo `--wait` czeka, aż
wszystko wstanie.

**Co powinieneś zobaczyć w drugim terminalu:**

- trzy PVC: najpierw `Pending` (czekają na pod – `WaitForFirstConsumer`), po chwili `Bound`,
- nowy pod `monitoring-grafana-…` i `Terminating` starego,
- `prometheus-…-0` i `alertmanager-…-0` znikają i startują na nowo (operator odtwarza
  StatefulSet, bo wzoru dysku w istniejącym StatefulSecie nie da się zmienić).

## Krok 6. Sprawdź wynik

```bash
kubectl -n monitoring get pvc
kubectl get pv -o custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,SIZE:.spec.capacity.storage,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
helm history monitoring -n monitoring
```

**Co powinieneś zobaczyć:**

- 3 PVC ze statusem `Bound`: `monitoring-grafana`,
  `prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-…-0`,
  `alertmanager-monitoring-kube-prometheus-alertmanager-db-alertmanager-…-0`,
- przy każdym PV kolumna `NODE` – węzeł, na którego dysku leżą dane,
- w `helm history` rewizję `2` ze statusem `deployed`.

Zajrzyj na dysk węzła z kolumny `NODE` (np. worker-2):

```bash
ssh k3s-worker-2 sudo ls /var/lib/rancher/k3s/storage
```

Zobaczysz katalogi `pvc-<numer>_monitoring_<nazwa-pvc>` – to są dane.

## Krok 7. Test: czy dane przeżyją usunięcie poda

**Grafana.** W przeglądarce `http://192.168.180.51:30300` (logujesz się sam) utwórz pusty
dashboard: *Dashboards → New → New dashboard → Save*, nazwa `test-trwalosci`. Potem:

```bash
kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana -w
```

Gdy nowy pod ma `3/3 Running`, odśwież stronę. Dashboard `test-trwalosci` jest.
Przed zmianą by zniknął.

**Prometheus.** Odczekaj ok. 15 minut, żeby zebrała się historia. W `http://192.168.180.51:30090`
wpisz `up`, zakładka *Graph*, zakres `1h`. Potem:

```bash
kubectl -n monitoring delete pod prometheus-monitoring-kube-prometheus-prometheus-0
```

Po starcie poda wykres `up` nadal pokazuje dane sprzed usunięcia, z krótką przerwą w środku.
Przed zmianą zaczynałby się od chwili startu.

## Wycofanie

```bash
helm rollback monitoring 1 -n monitoring
kubectl -n monitoring get pvc
```

`helm rollback` wraca do rewizji 1 (`emptyDir`). PVC Grafany zostanie usunięty razem z nią, ale
PVC Prometheusa i Alertmanagera **zostaną** – Kubernetes nie usuwa dysków StatefulSetów, żeby nie
skasować danych przez pomyłkę. Usuwasz je ręcznie: `kubectl -n monitoring delete pvc <nazwa>`.

## Czego local-path nie załatwia

Dane leżą na dysku **jednego** węzła, a PV ma przypisany ten węzeł (`nodeAffinity`). Gdy węzeł
padnie, pod nie przeniesie się – czeka, aż węzeł wróci. Przedtem wstawał gdzie indziej, ale pusty.
Wybór: „pełny, ale czeka” zamiast „szybko wraca, ale pusty”. Szczegóły:
[co się dzieje z podami, gdy węzeł pada](../etap-5-scenariusze-awarii/01-scenariusze-awarii.md#co-się-dzieje-z-podami-gdy-węzeł-pada).

Oba naraz daje pamięć sieciowa albo replikowana: NFS, Longhorn (kopie danych na kilku węzłach),
w chmurze dyski typu EBS. Najlepiej i tak trzymać ustawienia **w gicie** (dashboardy jako ConfigMapy),
a dysk traktować jako zapas.

## Pytania rekrutacyjne

- *Czym różni się PV od PVC?* PVC to wniosek aplikacji o miejsce (rozmiar, tryb dostępu, klasa).
  PV to konkretne miejsce. StorageClass tworzy PV automatycznie na podstawie PVC.
- *Co to `emptyDir` i kiedy go używać?* Katalog tymczasowy poda, znika razem z nim. Do cache
  i plików roboczych, nigdy do danych, które mają przetrwać.
- *Usunąłem StatefulSet. Co z danymi?* PVC z `volumeClaimTemplates` zostają – trzeba je usunąć
  ręcznie. To celowe zabezpieczenie.
- *Co oznacza `WaitForFirstConsumer`?* PV powstaje dopiero, gdy scheduler wybierze węzeł dla poda.
  Do tego czasu PVC jest `Pending` – to normalne.
- *ReadWriteOnce a ReadWriteMany?* RWO: dysk podłączony do jednego węzła naraz (dyski blokowe,
  local-path). RWX: wiele węzłów jednocześnie (NFS, CephFS).
- *Jakie są wady local-path?* Dane przywiązane do jednego węzła, brak kopii, brak limitu rozmiaru.
  Dobre do labu i testów, w produkcji pamięć sieciowa lub replikowana.
