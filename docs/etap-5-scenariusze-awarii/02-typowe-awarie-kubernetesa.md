# Typowe problemy i awarie Kubernetesa – diagnoza i naprawa

Ten rozdział to **ściągawka na dyżur i na rozmowę kwalifikacyjną**. Przy każdym problemie jest
pytanie, które pada na rozmowach, objaw, polecenia do diagnozy, typowe przyczyny i naprawa.
Wyniki pochodzą z labu (03.11.2026, k3s v1.36.5). Każdy problem został wywołany celowo
manifestem [kubernetes/awarie/zepsute.yaml](../../kubernetes/awarie/zepsute.yaml).

Scenariusze z [01-scenariusze-awarii.md](01-scenariusze-awarii.md) (wyłączenie węzła, OOM,
obciążenie CPU, `chaos.sh`) pokazują awarie w monitoringu. Ten plik pokazuje, jak je
**zdiagnozować w terminalu**.

## Ćwiczenie: najpierw spróbuj sam

🐧 k3s-master (pody z obrazem `hello-lab` wymagają rejestru z
[Etapu 4](../etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md)):

```bash
cd ~/k3s-monitoring-lab && git pull
kubectl apply -f kubernetes/awarie/zepsute.yaml
sleep 90
kubectl -n awarie get pods,pvc,svc
```

W przestrzeni `awarie` jest **11 zepsutych rzeczy**. Dla każdej, zanim przeczytasz opis niżej:
1. nazwij status,
2. znajdź **przyczynę** jednym lub dwoma poleceniami,
3. zaproponuj naprawę i, gdzie się da, napraw (np. utwórz brakujący Secret, popraw selektor).

Prawdziwy wynik z labu:

```
NAME                   READY   STATUS                       RESTARTS      AGE
pod/brak-sekretu       0/1     CreateContainerConfigError   0             75s
pod/crashloop          0/1     Error                        3 (57s ago)   75s
pod/liveness           1/1     Running                      1 (35s ago)   75s
pod/oom                0/1     OOMKilled                    3 (61s ago)   75s
pod/readiness          0/1     Running                      0             75s
pod/web                1/1     Running                      0             75s
pod/za-duzo-pamieci    0/1     Pending                      0             75s
pod/zle-polecenie      0/1     RunContainerError            3 (31s ago)   75s
pod/zly-nodeselector   0/1     Pending                      0             75s
pod/zly-obraz          0/1     ImagePullBackOff             0             75s

NAME                         STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/dane   Pending                                      szybki-dysk

NAME          TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/web   ClusterIP   10.43.22.72   <none>        80/TCP    75s
```

Uwaga: `web` wygląda zdrowo (`1/1 Running`), a jednak jest zepsuty. Problem siedzi w jego Service.

Sprzątanie: `kubectl delete namespace awarie`.

---

## 1. Metoda – w jakiej kolejności szukać

Zawsze od ogółu do szczegółu. Pięć poleceń rozwiązuje większość problemów:

```
kubectl get pods -o wide          1. JAKI status i NA KTÓRYM węźle?
        │
kubectl describe pod <pod>        2. sekcja Events na dole + State / Last State / Exit Code
        │
kubectl logs <pod> [--previous]   3. co powiedziała aplikacja (--previous = poprzednie uruchomienie)
        │
kubectl get events -n <ns> --sort-by=.lastTimestamp     4. co działo się w całej przestrzeni
        │
kubectl describe node <węzeł>     5. czy to nie węzeł: Conditions, Allocated resources
```

Prosta zasada, kiedy co czytać:

| Pod… | Gdzie jest odpowiedź | Dlaczego |
|---|---|---|
| **nie wystartował** (`Pending`, `ImagePullBackOff`, `CreateContainerConfigError`) | `describe` → **Events** | aplikacja nawet nie ruszyła, więc nie ma logów |
| **wystartował i padł** (`CrashLoopBackOff`, `Error`, `OOMKilled`) | `logs --previous` + `describe` → **Last State / Exit Code** | aplikacja zdążyła coś powiedzieć |
| **działa, ale nie odpowiada** (`0/1 Running`, Service milczy) | `describe` → sondy, `get endpointslices`, test z innego poda | problem między Kubernetesem a aplikacją |

## 2. Mapa statusów

| STATUS | Co znaczy | Pierwsze polecenie | Typowe przyczyny |
|---|---|---|---|
| `Pending` | scheduler nie znalazł węzła albo czeka na wolumen | `describe pod` → `FailedScheduling` | za duże `requests`, `nodeSelector`, taint, PVC `Pending` |
| `ContainerCreating` (długo) | węzeł przygotowuje pod | `describe pod` → Events | wolumen się nie podłącza, sieć CNI, wolne pobieranie obrazu |
| `ErrImagePull` / `ImagePullBackOff` | nie można pobrać obrazu; `BackOff` = czekam i spróbuję znowu | `describe pod` → `Failed to pull image` | literówka w nazwie/tagu, brak logowania do rejestru, certyfikat, DNS, limit Docker Hub |
| `CreateContainerConfigError` | brakuje czegoś do konfiguracji kontenera | `describe pod` → Events | brak Secretu / ConfigMapy / klucza w nich |
| `RunContainerError` / `StartError` | kontener nie mógł wystartować | `describe pod` → Events | złe `command`, brak pliku wykonywalnego, uprawnienia |
| `Error` / `CrashLoopBackOff` | proces zakończył się błędem; Kubernetes restartuje z rosnącą przerwą (10 s, 20 s, 40 s… do 5 min) | `logs --previous` | błąd aplikacji, brak konfiguracji, brak bazy danych, zła sonda liveness |
| `OOMKilled` | kontener przekroczył **limit pamięci**, jądro go zabiło (kod 137) | `describe pod` → `Last State` | za mały limit, wyciek pamięci |
| `Running`, `READY 0/1` | proces działa, ale **sonda gotowości** nie przechodzi | `describe pod` → `Readiness probe failed` | zły adres/port sondy, aplikacja czeka na zależność |
| `Terminating` (długo) | pod nie może się zakończyć | `get pod -o yaml` → `finalizers`, stan węzła | węzeł niedostępny, finalizer, proces ignoruje SIGTERM |
| `Evicted` | kubelet wyrzucił pod z węzła | `describe pod` → `Message` | brak miejsca na dysku (`DiskPressure`), brak pamięci na węźle |
| `Completed` | proces zakończył się kodem 0 | – | normalne dla Job; dla Deployment to błąd (program nie powinien się kończyć) |

**Kody wyjścia** (`Exit Code` w `describe`), które warto znać na pamięć:

| Kod | Znaczenie |
|---|---|
| `0` | sukces, program sam się zakończył |
| `1` | ogólny błąd aplikacji, odpowiedź jest w logach |
| `126` / `127` | plik nie jest wykonywalny / nie znaleziono polecenia |
| `137` | = 128 + 9 (**SIGKILL**): OOMKilled albo zabity siłą po przekroczeniu czasu na zamknięcie |
| `139` | = 128 + 11 (SIGSEGV): błąd ochrony pamięci w programie |
| `143` | = 128 + 15 (**SIGTERM**): poprawne zatrzymanie na prośbę Kubernetesa |

---

## 3. Problemy – pytanie, diagnoza, naprawa

### 3.1. ImagePullBackOff – obraz się nie pobiera

**Pytanie na rozmowie:** *Pod jest w ImagePullBackOff. Co sprawdzasz?*

**Diagnoza:**

```bash
kubectl -n awarie describe pod zly-obraz | tail -15        # sekcja Events
kubectl -n awarie get pod zly-obraz -o jsonpath='{.spec.containers[*].image}'
```

Wynik z labu (zdarzenia):

```
Warning   Failed      Failed to pull image "192.168.180.54:5000/hello-lab:9.9": rpc error: code = NotFound
                      desc = ... 192.168.180.54:5000/hello-lab:9.9: not found
Warning   Failed      Error: ErrImagePull
Normal    BackOff     Back-off pulling image "192.168.180.54:5000/hello-lab:9.9"
Warning   Failed      Error: ImagePullBackOff
```

**Najważniejsze jest słowo w komunikacie**, bo każde wskazuje inną przyczynę:

| W komunikacie | Przyczyna | Naprawa |
|---|---|---|
| `not found`, `manifest unknown` | nie ma takiego obrazu albo tagu | popraw nazwę/tag; sprawdź w rejestrze (`/v2/<nazwa>/tags/list`) |
| `unauthorized`, `authentication required` | prywatny rejestr bez logowania | Secret `docker-registry` + `imagePullSecrets` |
| `x509: certificate signed by unknown authority` | węzeł nie ufa certyfikatowi rejestru | CA w `registries.yaml` ([Etap 4](../etap-4-monitoring-zewnetrzny/problemy.md#x509-certificate-signed-by-unknown-authority)) |
| `server gave HTTP response to HTTPS client` | rejestr bez TLS | TLS w rejestrze |
| `lookup ...: Try again`, `no such host` | DNS na węźle | `resolvectl query <rejestr>` na węźle ([Etap 3](../etap-3-monitoring/problemy.md#errimagepull-przez-chwilowy-błąd-dns)) |
| `toomanyrequests` | limit pobrań z Docker Hub | logowanie do Docker Hub, kopia obrazu we własnym rejestrze |

Na węźle można sprawdzić ręcznie: `sudo k3s crictl pull <obraz>` (to samo, co robi kubelet)
i `sudo k3s crictl images`.

### 3.2. CrashLoopBackOff – aplikacja ciągle się wywraca

**Pytanie:** *Pod jest w CrashLoopBackOff. Jak znajdziesz przyczynę?*

**Diagnoza:**

```bash
kubectl -n awarie logs crashloop               # bieżące uruchomienie (może być puste)
kubectl -n awarie logs crashloop --previous    # POPRZEDNIE uruchomienie – zwykle tu jest błąd
kubectl -n awarie describe pod crashloop | grep -A6 "Last State"
```

Wynik z labu:

```
Start aplikacji
BLAD: brak pliku /config/app.conf

    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Tue, 03 Nov 2026 08:58:10 +0100
      Finished:     Tue, 03 Nov 2026 08:58:10 +0100
    Restart Count:  3
```

`Started` i `Finished` w tej samej sekundzie znaczą, że aplikacja padła od razu przy starcie.
To zwykle konfiguracja, a nie przeciążenie. Status w `get pods` przeskakuje między `Error`
(właśnie padł) a `CrashLoopBackOff` (czeka przed kolejną próbą).

**Typowe przyczyny i naprawa:**
- brak pliku/zmiennej konfiguracyjnej: dodaj ConfigMapę/Secret i zamontuj,
- aplikacja nie łączy się z bazą/usługą przy starcie: sprawdź Service i DNS zależności,
- zła sonda liveness zabija zdrowy kontener ([3.9](#39-restarty-przez-sondę-liveness)),
- **OOMKilled** wygląda podobnie, ale ma `Reason: OOMKilled` ([3.3](#33-oomkilled--przekroczony-limit-pamięci)).

**Pułapka z labu:** `kubectl get pods -A --field-selector=status.phase!=Running` **nie pokazuje**
podów w CrashLoopBackOff. Ich faza to formalnie `Running` (kontener jest restartowany). Do
szybkiego przeglądu lepiej: `kubectl get pods -A | grep -v -E "Running|Completed"` i patrzeć
na kolumny `READY` oraz `RESTARTS`.

Gdy kontener pada zbyt szybko, żeby wejść do środka:
`kubectl debug -it <pod> --image=busybox:1.37 --copy-to=<pod>-debug -- sh` tworzy kopię poda
z dodatkowym kontenerem narzędziowym. Inny sposób to tymczasowo nadpisać `command`
na `["sleep", "3600"]` i zajrzeć przez `kubectl exec`.

### 3.3. OOMKilled – przekroczony limit pamięci

**Pytanie:** *Kontener ma restarty i exit code 137. Co to znaczy?*

**Diagnoza:**

```bash
kubectl -n awarie describe pod oom | grep -A6 "Last State"
kubectl -n awarie get pod oom -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
kubectl top pod -n awarie                      # bieżące zużycie (metrics-server)
```

Wynik z labu:

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
```

Program chciał 200 MiB, limit to `64Mi`. Jądro Linuksa (cgroups) zabija proces sygnałem
SIGKILL, którego nie da się przechwycić. Dlatego w logach aplikacji **nie ma** żadnego
komunikatu.

**Naprawa:**
- jeśli aplikacja naprawdę tyle potrzebuje: zwiększ `resources.limits.memory`,
- jeśli zużycie rośnie bez końca (wyciek): to błąd w kodzie, a większy limit tylko odsunie restart,
- w Grafanie: *Kubernetes / Compute Resources / Pod*, gdzie wykres pamięci dochodzi do linii limitu.
  Alert w labie: `ContainerOOMKilled`.

**Pamięć a CPU:** przekroczenie limitu **pamięci** = zabicie. Przekroczenie limitu **CPU**
= spowolnienie (*throttling*), bez restartu ([scenariusz CPU](01-scenariusze-awarii.md#obciążenie-cpu)).

### 3.4. Pending – brak zasobów

**Pytanie:** *Pod wisi w Pending. Gdzie szukasz?*

**Diagnoza:**

```bash
kubectl -n awarie describe pod za-duzo-pamieci | tail -5
kubectl describe node k3s-worker-1 | sed -n '/Allocated resources:/,/Events:/p'
kubectl get node k3s-worker-1 -o jsonpath='{.status.allocatable.memory}'
```

Wynik z labu:

```
Warning   FailedScheduling   0/4 nodes are available: 1 node(s) had untolerated taint(s),
          3 Insufficient memory. ... preemption: 0/4 nodes are available: 4 Preemption is not helpful for scheduling.
```

Komunikat schedulera **liczy węzły według powodu**: 1 węzeł (master) odpada przez taint
`NoSchedule`, a 3 workery przez brak pamięci. Pod żąda `requests.memory: 50Gi`, a worker ma do
przydzielenia `5489200Ki` (ok. 5,2 GiB).

**Ważne:** scheduler patrzy na **`requests`** (zarezerwowane), a nie na rzeczywiste zużycie.
Węzeł może mieć wolne 3 GiB w `free -h`, a i tak odmówić, jeśli suma `requests` podów jest bliska
`allocatable`.

**Naprawa:** zmniejsz `requests` do realnego zużycia (zobacz `kubectl top pod`), usuń zbędne
pody, dodaj węzeł albo pamięć do VM.

### 3.5. Pending – nodeSelector, taint, affinity

**Diagnoza:**

```bash
kubectl -n awarie describe pod zly-nodeselector | tail -3
kubectl get nodes --show-labels
kubectl describe nodes | grep -E "^Name:|^Taints:"
```

Wynik z labu:

```
Warning   FailedScheduling   0/4 nodes are available: 1 node(s) had untolerated taint(s),
          3 node(s) didn't match Pod's node affinity/selector.
```

**Naprawa:** dodaj etykietę węzłowi (`kubectl label node k3s-worker-1 dysk=ssd`) albo popraw
`nodeSelector`. Przy taincie: `tolerations` w podzie albo usunięcie tainta
(`kubectl taint node <węzeł> klucz:NoSchedule-`, z minusem na końcu).

Inne odmiany tego samego komunikatu: `didn't match pod anti-affinity rules`,
`node(s) had volume node affinity conflict` (wolumen jest na innym węźle),
`node(s) were unschedulable` (węzeł po `kubectl cordon`/`drain`, naprawa: `kubectl uncordon`).

### 3.6. CreateContainerConfigError – brak Secretu lub ConfigMapy

**Diagnoza:**

```bash
kubectl -n awarie describe pod brak-sekretu | tail -3
kubectl -n awarie get secrets,configmaps
```

Wynik z labu:

```
Warning   Failed      Error: secret "baza-haslo" not found
```

**Naprawa w labie (sprawdzona):**

```bash
kubectl -n awarie create secret generic baza-haslo --from-literal=password=tajne123
kubectl -n awarie get pod brak-sekretu       # po kilku sekundach: 1/1 Running, bez restartu poda
```

Kubelet sam ponawia próbę, więc nie trzeba usuwać poda. Typowe przyczyny: Secret utworzony
w **innej przestrzeni nazw** (Secrety nie są widoczne między przestrzeniami), literówka
w nazwie klucza (`key: password` a w Secrecie `pasword`), kolejność wdrożenia (aplikacja przed
konfiguracją). W tej samej sytuacji, ale z wolumenem, pod utknie w `ContainerCreating`
z błędem `FailedMount`.

### 3.7. RunContainerError – zły program startowy

**Diagnoza:** `kubectl -n awarie describe pod zle-polecenie | tail -3`

```
Warning   Failed   Error: failed to create containerd task: failed to create shim task: OCI runtime create failed:
          runc create failed: unable to start container process: error during container init:
          exec: "/bin/nie-ma-takiego": stat /bin/nie-ma-takiego: no such file or directory
```

Komunikat czyta się od końca: `no such file or directory`. W obrazie nie ma tego programu.
Typowe przyczyny: literówka w `command`/`args`, program w innym katalogu (`/usr/local/bin`),
obraz `distroless` bez powłoki, a w `command` jest `sh -c`. Ciekawy przypadek: `exec format error`
oznacza obraz zbudowany na inny procesor (np. ARM z Maca na serwerze x86).

### 3.8. Running, ale READY 0/1 – sonda gotowości nie przechodzi

**Pytanie:** *Czym różni się readinessProbe od livenessProbe?*

**Diagnoza:**

```bash
kubectl -n awarie describe pod readiness | grep -E "Readiness|Unhealthy"
kubectl -n awarie get pod readiness -o wide          # IP poda
kubectl -n awarie exec readiness -- python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:8080/healthz').read())"
```

Wynik z labu:

```
Warning   Unhealthy   Readiness probe failed: Get "http://10.42.2.46:8080/gotowe": dial tcp ... connect: connection refused
Warning   Unhealthy   Readiness probe failed: HTTP probe failed with statuscode: 404
```

Pierwszy błąd (`connection refused`) pojawił się w pierwszej sekundzie, gdy aplikacja jeszcze
startowała. Drugi (`404`) to prawdziwa przyczyna: aplikacja nie ma adresu `/gotowe`, ma `/healthz`.

| | readinessProbe | livenessProbe |
|---|---|---|
| pytanie | czy mogę przyjmować ruch? | czy w ogóle żyję? |
| gdy nie przechodzi | pod **wypada z Service** (brak ruchu), kontener działa dalej | kubelet **restartuje** kontener |
| objaw | `READY 0/1`, `RESTARTS 0` | rosnące `RESTARTS`, zdarzenie `Killing` |
| typowe użycie | rozgrzewanie, chwilowa utrata połączenia z bazą | zawieszenie aplikacji (deadlock) |

**Naprawa:** popraw `path`/`port` sondy. Jeśli aplikacja długo startuje, dodaj `startupProbe`
albo `initialDelaySeconds`.

### 3.9. Restarty przez sondę liveness

**Diagnoza:** `kubectl -n awarie describe pod liveness | grep -E "Liveness|Killing"`

```
Warning   Unhealthy   Liveness probe failed: Get "http://10.42.2.45:9999/healthz": dial tcp ... connect: connection refused
Normal    Killing     Container app failed liveness probe, will be restarted
```

Aplikacja jest zdrowa (słucha na 8080), ale sonda pyta port 9999. W labie po 3 minutach pod
miał `RESTARTS 4` przy statusie `1/1 Running`, bo między zabiciami kontener na chwilę działa.
**Zła sonda liveness jest groźniejsza niż jej brak.** Przy przeciążeniu potrafi restartować
po kolei wszystkie pody i dobić aplikację. Liveness ustawia się łagodnie (`failureThreshold`,
`timeoutSeconds`) i sprawdza tylko sam proces, nie bazę danych.

### 3.10. Service nie działa – brak endpointów

**Pytanie:** *Pod działa, a aplikacja przez Service nie odpowiada. Co sprawdzasz?*

**Diagnoza:**

```bash
kubectl -n awarie get endpointslices -l kubernetes.io/service-name=web
kubectl -n awarie get svc web -o jsonpath='{.spec.selector}'; echo
kubectl -n awarie get pods --show-labels
kubectl -n awarie run test --rm -i --restart=Never --image=busybox:1.37 -- wget -qO- -T 3 http://web/api
```

Wynik z labu:

```
NAME        ADDRESSTYPE   PORTS     ENDPOINTS   AGE
web-t6mss   IPv4          <unset>   <unset>     90s          ← Service nie ma żadnego poda

wget: can't connect to remote host (10.43.22.72): Connection refused

NAME   READY   STATUS    RESTARTS   AGE   LABELS
web    1/1     Running   0          96s   app=web           ← pod ma app=web, Service szuka app=wep
```

**Naprawa w labie (sprawdzona):**

```bash
kubectl -n awarie patch service web -p '{"spec":{"selector":{"app":"web"}}}'
kubectl -n awarie get endpointslices -l kubernetes.io/service-name=web
# web-t6mss   IPv4   8080   10.42.2.44
kubectl -n awarie run test2 --rm -i --restart=Never --image=busybox:1.37 -- wget -qO- -T 3 http://web/api
# {"app": "hello-lab", "version": "1.0", "host": "web"}
```

Lista kontrolna Service, po kolei:
1. **Selektor** Service = **etykiety** poda (literówki!),
2. pod jest **READY** (pody `0/1` nie trafiają do endpointów),
3. `targetPort` = port, na którym aplikacja **naprawdę** słucha (`containerPort` to tylko informacja),
4. aplikacja słucha na `0.0.0.0`, a nie na `127.0.0.1` (wtedy działa tylko z wnętrza kontenera),
5. NetworkPolicy nie blokuje ruchu (w labie ich nie ma),
6. dla NodePort: firewall węzła wpuszcza port 30000–32767.

### 3.11. DNS w klastrze

**Pytanie:** *Pod nie może połączyć się z innym serwisem po nazwie. Jak to sprawdzisz?*

**Diagnoza** (wynik z labu):

```bash
kubectl -n awarie run test --rm -i --restart=Never --image=busybox:1.37 -- nslookup web.awarie.svc.cluster.local
# Name:    web.awarie.svc.cluster.local
# Address: 10.43.22.72
kubectl -n awarie run test --rm -i --restart=Never --image=busybox:1.37 -- nslookup nie-ma-takiego
# ** server can't find nie-ma-takiego.svc.cluster.local: NXDOMAIN
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
```

Ciekawostka z wyniku: to DNS **działał**, a nie było **endpointów**. Nazwa `web` zamieniła się
na `10.43.22.72`, a połączenie i tak zostało odrzucone. Zawsze rozdzielaj „nie znam nazwy”
(`NXDOMAIN`, `bad address`) od „znam adres, ale nikt nie odpowiada” (`connection refused`,
`timed out`).

Pełna nazwa usługi: `<service>.<namespace>.svc.cluster.local`. Z tej samej przestrzeni wystarczy
`web`, z innej trzeba `web.awarie`. To najczęstsza przyczyna „DNS nie działa”.

### 3.12. PVC w stanie Pending

**Diagnoza:**

```bash
kubectl -n awarie describe pvc dane | tail -3
kubectl get storageclass
```

Wynik z labu:

```
Warning   ProvisioningFailed   storageclass.storage.k8s.io "szybki-dysk" not found

NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

**Naprawa:** właściwa `storageClassName` (w k3s `local-path`) albo jej pominięcie (użyje domyślnej).
Pułapka: przy `WaitForFirstConsumer` PVC jest `Pending`, **dopóki żaden pod go nie użyje**. To
normalne, a nie błąd. W chmurze dochodzą limity dysków, strefy dostępności i brak sterownika CSI.

### 3.13. Węzeł NotReady

**Pytanie:** *Węzeł jest NotReady. Co robisz?*

**Diagnoza:**

```bash
kubectl get nodes
kubectl describe node k3s-worker-1 | sed -n '/Conditions:/,/Addresses:/p'
```

Zdrowy węzeł w labie:

```
  Type             Status  Reason                       Message
  MemoryPressure   False   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure      False   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready            True    KubeletReady                 kubelet is posting ready status
```

Przy awarii `Ready` ma `Unknown` i komunikat `Kubelet stopped posting node status`. Wtedy
**na węźle**:

```bash
ping 192.168.180.52                          # czy maszyna w ogóle żyje (z mastera)
ssh k3s-worker-1
sudo systemctl status k3s-agent              # na masterze: k3s
sudo journalctl -u k3s-agent -n 50 --no-pager
df -h / ; free -h                            # pełny dysk i brak pamięci to częste przyczyny
```

| Przyczyna | Objaw |
|---|---|
| maszyna wyłączona / sieć | brak `ping`, `Unknown` po ok. 40 s |
| usługa `k3s-agent` padła | `systemctl status` = `failed`, przyczyna w `journalctl` |
| pełny dysk | `DiskPressure True`, pody `Evicted` |
| brak pamięci | `MemoryPressure True`, OOM procesów systemowych |
| zegar się rozjechał / certyfikat | w `journalctl`: `x509: certificate has expired or is not yet valid` |

Kubernetes czeka ok. 5 minut (`tolerationSeconds: 300`), zanim przeniesie pody z niedostępnego
węzła. Pełny scenariusz: [awaria węzła](01-scenariusze-awarii.md#awaria-węzła).

### 3.14. Wdrożenie utknęło (rollout)

**Diagnoza:**

```bash
kubectl -n <ns> rollout status deploy/<nazwa> --timeout=60s
kubectl -n <ns> get rs                        # stary i nowy ReplicaSet
kubectl -n <ns> rollout history deploy/<nazwa>
kubectl -n <ns> rollout undo deploy/<nazwa>
```

Wynik z labu (tag `2.0`, którego nie ma):

```
hello-lab-74569bfdbc-66bfh   0/1     ErrImagePull   0          30s
hello-lab-b758c89db-494rc    1/1     Running        0          7m54s
hello-lab-b758c89db-fr2gx    1/1     Running        0          7m48s
error: timed out waiting for the condition
```

Stare pody działają dalej, bo nowy nigdy nie stał się gotowy. Naprawa: `rollout undo`, potem
poprawka w repozytorium. Cały przypadek:
[ćwiczenie z obrazu, poziom 8](../etap-4-monitoring-zewnetrzny/04-cwiczenia-obraz-rozwiazania.md#poziom-8--nowa-wersja-i-wycofanie).

### 3.15. Pod albo namespace wisi w Terminating

**Diagnoza:**

```bash
kubectl get pod <pod> -o jsonpath='{.metadata.finalizers}'; echo
kubectl get namespace <ns> -o jsonpath='{.status.conditions}' ; echo
kubectl api-resources --verbs=list --namespaced -o name | xargs -n1 kubectl get -n <ns> --ignore-not-found --show-kind
```

| Przyczyna | Naprawa |
|---|---|
| pod na węźle, który nie odpowiada | przywróć węzeł; ostatecznie `kubectl delete pod <pod> --grace-period=0 --force` |
| **finalizer**, czyli „nie usuwaj, dopóki kontroler nie posprząta”, a kontroler nie działa | uruchom kontroler; w ostateczności usuń finalizer `kubectl patch ... -p '{"metadata":{"finalizers":null}}' --type=merge` |
| namespace czeka na zasoby z CRD, których operator został usunięty | trzecie polecenie wyżej pokaże, co zostało |

**Uwaga:** `--force` i usuwanie finalizerów to ostateczność. Kubernetes zapomina o obiekcie, ale
proces na węźle albo zasób w chmurze (dysk, load balancer) może dalej istnieć.

### 3.16. Evicted – pody wyrzucone z węzła

**Diagnoza:**

```bash
kubectl get pods -A | grep Evicted
kubectl describe pod <pod> | grep -E "Reason|Message"
# Message: The node was low on resource: ephemeral-storage.
kubectl describe node <węzeł> | grep -E "DiskPressure|MemoryPressure"
```

Kubelet usuwa pody, gdy na węźle kończy się dysk albo pamięć. Najpierw wyrzuca te, które
zużywają więcej niż zadeklarowały w `requests`. **Naprawa:** zwolnij miejsce na węźle
(`sudo k3s crictl rmi --prune`, logi, `/var/lib/rancher`), ustaw `requests`/`limits`, potem
usuń stare wpisy: `kubectl delete pod -A --field-selector=status.phase=Failed`.

### 3.17. kubectl nie łączy się z klastrem

| Komunikat | Przyczyna | Diagnoza / naprawa |
|---|---|---|
| `The connection to the server 127.0.0.1:6443 was refused` | API nie działa | na masterze `sudo systemctl status k3s`, `sudo journalctl -u k3s -n 50` |
| `dial tcp 192.168.180.51:6443: i/o timeout` | firewall / sieć | `ufw` wpuszcza 6443 tylko z `admin_cidr`; `nc -zv 192.168.180.51 6443` |
| `http://localhost:8080 ... refused` | brak kubeconfigu | `~/.kube/config` albo `KUBECONFIG` ([Etap 3](../etap-3-monitoring/problemy.md#kubectl-działa-a-helm-nie-widzi-klastra)) |
| `x509: certificate has expired` | wygasły certyfikat klastra | na masterze `sudo k3s certificate check` |
| `Forbidden: User "..." cannot list resource` | brak uprawnień RBAC | `kubectl auth can-i list pods -n <ns>` |

Stan API w labie:

```
$ kubectl get --raw '/readyz?verbose' | tail -1
readyz check passed
$ sudo k3s certificate check --output table
FILENAME                SUBJECT              USAGES       EXPIRES                  RESIDUAL TIME   STATUS
client-auth-proxy.crt   system:auth-proxy    ClientAuth   Oct 29, 2027 13:41 UTC   1 year          OK
...
```

Certyfikaty k3s są ważne rok. k3s odnawia je przy restarcie usługi, gdy zbliża się koniec
ważności. Klaster, którego nikt nie restartował ponad rok, potrafi przestać działać właśnie
z tego powodu.

---

## 4. Ściągawka poleceń

| Cel | Polecenie |
|---|---|
| co jest nie tak w całym klastrze | `kubectl get pods -A \| grep -v -E "Running\|Completed"` |
| ostatnie ostrzeżenia | `kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp` |
| szczegóły i zdarzenia poda | `kubectl describe pod <pod> -n <ns>` |
| logi / poprzednie uruchomienie / na żywo | `kubectl logs <pod> [-c kontener] [--previous] [-f]` |
| logi wszystkich podów aplikacji | `kubectl logs -l app=<nazwa> --tail=50` |
| polecenie w kontenerze | `kubectl exec -it <pod> -- sh` |
| tymczasowy pod do testów sieci | `kubectl run test --rm -it --restart=Never --image=busybox:1.37 -- sh` |
| kontener debug (gdy obraz nie ma powłoki) | `kubectl debug -it <pod> --image=busybox:1.37 --target=<kontener>` |
| zużycie zasobów | `kubectl top nodes`, `kubectl top pods -A --sort-by=memory` |
| przydziały na węźle | `kubectl describe node <węzeł>` → `Allocated resources` |
| dokąd prowadzi Service | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` |
| konkretne pole | `kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'` |
| pełna definicja | `kubectl get <obiekt> -o yaml` |
| test przed zmianą | `kubectl apply --dry-run=server -f plik.yaml`, `kubectl diff -f plik.yaml` |
| uprawnienia | `kubectl auth can-i <czasownik> <zasób> -n <ns>` |
| wdrożenia | `kubectl rollout status/history/undo/restart deploy/<nazwa>` |
| na węźle k3s | `sudo systemctl status k3s-agent`, `sudo journalctl -u k3s-agent`, `sudo k3s crictl ps -a`, `sudo k3s crictl logs <id>` |

## 5. Pytania rekrutacyjne – krótkie odpowiedzi

**Pod nie działa. Od czego zaczynasz?**
`kubectl get pods -o wide` (status, węzeł, restarty), potem `kubectl describe pod` (Events,
Last State, Exit Code), potem `kubectl logs --previous`. Gdy pod nie wystartował, odpowiedź jest
w Events. Gdy wystartował i padł, w logach.

**Co oznacza exit code 137? A 143?**
137 = 128 + 9, czyli SIGKILL. Najczęściej OOMKilled albo zabicie po przekroczeniu
`terminationGracePeriodSeconds`. 143 = SIGTERM, czyli normalne zatrzymanie na prośbę Kubernetesa.

**Czym jest CrashLoopBackOff?**
To nie przyczyna, tylko stan: kontener się kończy, a kubelet restartuje go z rosnącą przerwą,
do 5 minut. Przyczyny szukam w `logs --previous` i w `Last State`.

**Różnica między requests a limits?**
`requests` to rezerwacja: scheduler na jej podstawie wybiera węzeł. `limits` to sufit: po
przekroczeniu pamięci kontener jest zabijany (OOMKilled), a CPU spowalniany (throttling).

**Pod Pending – jakie przyczyny?**
Brak zasobów względem `requests`, niepasujący `nodeSelector`/affinity, taint bez tolerancji,
PVC bez wolumenu, węzły `cordon`. Wszystko widać w zdarzeniu `FailedScheduling`.

**Pod działa, Service nie odpowiada – co sprawdzasz?**
Endpointy Service (`get endpointslices`). Jeśli puste: selektor kontra etykiety i gotowość podów.
Jeśli są: `targetPort`, czy aplikacja słucha na `0.0.0.0`, NetworkPolicy. Test z innego poda
przez `kubectl run ... busybox`.

**Liveness a readiness?**
Readiness decyduje, czy pod dostaje ruch. Liveness decyduje, czy kubelet restartuje kontener.
Zła liveness potrafi restartować zdrową aplikację.

**Węzeł NotReady – co robisz?**
`kubectl describe node` (Conditions), potem na węźle `systemctl status` i `journalctl` usługi
kubelet/k3s-agent, dysk, pamięć, sieć. Pody przeniosą się same po ok. 5 minutach. Przy planowanej
pracy robię wcześniej `kubectl drain`.

**Jak wycofać złe wdrożenie?**
`kubectl rollout undo deployment/<nazwa>`, a potem poprawka w repozytorium, żeby następny
`apply` albo GitOps nie przywrócił błędu.

**Dlaczego nie warto od razu usuwać poda albo dawać --force?**
Bo usuwa się dowody (logi `--previous`, zdarzenia), a `--force` może zostawić działający proces
lub zasób poza wiedzą Kubernetesa. Najpierw diagnoza, potem naprawa przyczyny.

Na rozmowie: *"In my lab I deliberately broke eleven things – image pull, crash loop, OOM,
scheduling, missing secret, probes, a Service selector typo, storage class – and diagnosed each
with get, describe, logs --previous, events and endpoint slices. I keep the method and the real
outputs in my documentation."*
