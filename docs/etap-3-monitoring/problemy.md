# Etap 3 – monitoring w klastrze – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## kubectl działa, a Helm nie widzi klastra

- **Objaw:** na masterze `kubectl get nodes` działa, a `helm list -A` kończy się błędem
  `kubernetes cluster unreachable: Get "http://localhost:8080/version": ... connection refused`.
- **Przyczyna:** `kubectl` na masterze to dowiązanie do programu k3s
  (`/usr/local/bin/kubectl -> k3s`), który sam wie, że kubeconfig leży w
  `/etc/rancher/k3s/k3s.yaml`. Helm to osobny program – szuka `~/.kube/config`, a gdy go nie ma,
  próbuje starego domyślnego adresu `localhost:8080`, pod którym nic nie nasłuchuje.
- **Diagnoza:** `ls -l ~/.kube/config /etc/rancher/k3s/k3s.yaml`, `echo $KUBECONFIG`,
  `ls -l $(command -v kubectl)`.
- **Rozwiązanie:** kopia kubeconfigu z uprawnieniami tylko dla właściciela:
  `mkdir -p ~/.kube && install -m 600 /etc/rancher/k3s/k3s.yaml ~/.kube/config`.
- **Przy okazji:** `/etc/rancher/k3s/k3s.yaml` ma w labie uprawnienia `644` – każdy użytkownik
  mastera może go przeczytać i zostać administratorem klastra. Dlatego kubectl działał bez `sudo`.
- **Wniosek:** to, że jedno narzędzie działa, nie znaczy, że drugie użyje tej samej konfiguracji.
  Kubeconfig to klucz administratora klastra – uprawnienia `600`, nigdy w repozytorium.
  Teoria: [teoria Kubernetes i Helm](03-teoria-kubernetes-helm.md#9-kubeconfig--klucz-do-klastra).

## kubectl w drugim terminalu: localhost:8080 refused (Windows)

- **Objaw:** w nowym oknie terminala `kubectl -n monitoring get pods,pvc -w` kończy się błędem
  `couldn't get current server API group list: Get "http://localhost:8080/api?timeout=32s": dial tcp [::1]:8080:
  connectex: No connection could be made because the target machine actively refused it`.
- **Przyczyna:** nowe okno terminala startuje na **Windowsie** (`PS C:\Projekty\...>`), a nie na
  masterze. Na Windowsie też jest `kubectl` – przyszedł z Docker Desktop
  (`C:\Program Files\Docker\Docker\resources\bin\kubectl.exe`) – ale nie ma kubeconfigu
  (`~/.kube/config`), więc próbuje domyślnego `localhost:8080`, gdzie nic nie działa.
- **Diagnoza:** znak zachęty: `PS C:\...>` = Windows, `grzegorz@k3s-master:~$` = master.
  W PowerShellu `(Get-Command kubectl).Source` pokazuje, który kubectl odpowiada.
- **Rozwiązanie:** najpierw `ssh k3s-master`, potem `kubectl …`. Każde nowe okno to nowa sesja –
  trzeba się zalogować od nowa.
- **Wniosek:** `connectex` i `[::1]` w komunikacie to słowa z Windowsa. Zanim zaczniesz szukać
  awarii klastra, sprawdź, **na której maszynie** jesteś. (Powtórzyło się 4.11.2026 przy
  `kubectl get ingress -A` – ten sam objaw.)

## kubectl exec do Grafany: executable file not found

- **Objaw:** `kubectl -n monitoring exec deploy/monitoring-grafana -c grafana -- ls /var/lib/grafana`
  (to samo z `sh`, `cat`) kończy się błędem
  `OCI runtime exec failed: exec failed: unable to start container process: exec: "ls": executable file not found in $PATH`.
- **Przyczyna:** obraz Grafany 13 jest okrojony (tzw. distroless) – zawiera tylko program Grafany,
  bez powłoki i narzędzi. To celowe: mniej programów w obrazie = mniej podatności.
- **Diagnoza:** komunikat `executable file not found` dotyczy **polecenia**, a nie poda – pod działa
  (`Running`), tylko w środku nie ma takiego programu.
- **Rozwiązanie:** zajrzeć do danych z innego poda, który podłącza ten sam PVC (przykład w
  [trwałych danych](08-trwale-dane.md#wynik-testu-w-labie-03112026)), albo dołączyć kontener
  z narzędziami: `kubectl debug -it <pod> --image=busybox --target=grafana` (widzi procesy, ale
  nie wolumeny), albo sprawdzać przez API (`/api/health`).
- **Wniosek:** w nowoczesnych obrazach `kubectl exec … sh` często nie działa. Trzeba znać
  obejścia: `kubectl debug`, pod pomocniczy, logi i API.

## ErrImagePull przez chwilowy błąd DNS

- **Objaw:** w trakcie instalacji monitoringu jeden pod node-exportera (na worker-1) w stanie
  `ErrImagePull`, potem `ImagePullBackOff`; pozostałe pody pobierają obrazy normalnie.
- **Przyczyna:** w zdarzeniach poda:
  `failed to do request: Get "https://cdn01.quay.io/...": dial tcp: lookup cdn01.quay.io: Try again`
  – worker chwilowo nie rozwiązał nazwy serwera z obrazami. Prawdopodobnie wiele równoczesnych
  zapytań DNS przez NAT VMware w chwili, gdy wszystkie węzły naraz pobierały obrazy.
- **Diagnoza:** `kubectl get events -n monitoring --sort-by=.lastTimestamp` albo
  `kubectl describe pod <nazwa>` – sekcja *Events*. Słowo `lookup` w błędzie oznacza DNS, a nie
  zły obraz czy brak uprawnień (wtedy byłoby `not found`, `unauthorized` lub `manifest unknown`).
- **Rozwiązanie:** żadne – Kubernetes sam ponawia pobieranie z rosnącymi przerwami
  (`ImagePullBackOff` = „czekam i spróbuję znowu”). Pod wstał po kilkudziesięciu sekundach,
  z `RESTARTS 0`. Gdyby błąd się utrzymywał: `resolvectl status` i
  `resolvectl query cdn01.quay.io` na węźle, sprawdzenie bramy/DNS `.2` w VMnet8.
- **Wniosek:** nie każdy czerwony status wymaga naprawy. Najpierw przeczytaj **przyczynę**
  w zdarzeniach i odróżnij błąd przejściowy (sieć, DNS, limit zapytań) od trwałego (zła nazwa
  obrazu, brak dostępu). W produkcji przed takimi błędami chroni lokalny rejestr obrazów albo
  pamięć podręczna (mirror), żeby węzły nie zależały od internetu.

## AlertmanagerFailedToSendAlerts zaraz po instalacji

- **Objaw:** chwilę po instalacji monitoringu w Prometheusie (*Alerts*) w stanie *firing* są
  `AlertmanagerFailedToSendAlerts` (warning) i `AlertmanagerClusterFailedToSendAlerts` (critical),
  choć w klastrze nic się nie dzieje.
- **Przyczyna:** Alertmanager co minutę wysyła alert Watchdog na adres z `HEALTHCHECKS_URL`,
  a w `lab.env` jest jeszcze adres przykładowy z `lab.env.example`
  (`https://hc-ping.com/00000000-…`). healthchecks.io odrzuca go, a nieudane wysyłki wykrywa
  reguła z chartu.
- **Diagnoza:** logi Alertmanagera:
  ```bash
  kubectl -n monitoring logs alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager | grep -i notify
  ```
  ```
  msg="Notify for alerts failed" ... aggrGroup="{}/{alertname=\"Watchdog\"}..."
  err="deadmans-switch/webhook[0]: notify retry canceled due to unrecoverable error after 1 attempts: unexpected status code 400: invalid url format"
  ```
  `deadmans-switch/webhook[0]` – nazwa odbiorcy z pliku values; `400` – serwer odrzucił adres.
- **Rozwiązanie:** konto na healthchecks.io, prawdziwy adres w `lab.env`, ponowne wypełnienie
  luk i `helm upgrade --install` (Etap 4). Do tego czasu alert jest spodziewany.
- **Wniosek:** monitoring monitoruje sam siebie – błąd w konfiguracji powiadomień sam wywołał
  alert. Zanim uznasz system za gotowy, sprawdź, czy powiadomienia **naprawdę dochodzą** –
  inaczej pierwsza prawdziwa awaria przejdzie bez echa.

## helm template: YAML parse error – mapping values are not allowed

- **Objaw:** przy własnym chartcie ([ćwiczenia](11-cwiczenia-wlasny-chart-helm.md), 4.11.2026)
  `helm template my-app app` kończy się błędem
  `Error: YAML parse error on app/templates/config-map.yaml: error converting YAML to JSON: yaml: line 7: mapping values are not allowed in this context`.
- **Przyczyna:** do ostatniej linii szablonu przykleił się początek pliku values:
  `SECOND_NAME: {{ .Values.configMap.secondName }}configMap:` – dwa dwukropki w jednej linii.
  Do tego plik powstał przez `sudo` i należał do `root`, więc `grzegorz` nie mógł go poprawić.
- **Diagnoza:** numer linii jest w komunikacie; `cat -A plik` pokazuje koniec każdej linii (`$`),
  `ls -l` – właściciela. `helm template … --debug` wypisuje też zepsuty YAML.
- **Rozwiązanie:** `sudo chown grzegorz:grzegorz ~/app/templates/config-map.yaml` i ponowny zapis
  pliku (`cat > plik <<'EOF'`).
- **Wniosek:** `helm template` łapie takie błędy, zanim cokolwiek trafi do klastra. Pliki
  w katalogu domowym twórz bez `sudo`.

## curl.exe na Windowsie: CRYPT_E_NO_REVOCATION_CHECK

- **Objaw:** po dodaniu CA labu do zaufanych na Windowsie przeglądarka otwiera
  `https://nginx.192.168.180.51.nip.io` bez ostrzeżeń, ale `curl.exe` (4.11.2026) kończy się
  `curl: (35) schannel: next InitializeSecurityContext failed: CRYPT_E_NO_REVOCATION_CHECK (0x80092012)`.
- **Przyczyna:** `curl.exe` w Windows korzysta z Schannel, który domyślnie sprawdza, czy certyfikat
  nie został unieważniony (CRL/OCSP). Certyfikaty z własnego CA labu nie mają adresu listy
  unieważnień, więc sprawdzenia nie da się wykonać – Schannel traktuje to jako błąd.
- **Diagnoza:** `curl.exe --ssl-no-revoke …` → `200`; na masterze `curl --cacert ca.crt …` → `200`.
- **Rozwiązanie:** w labie `--ssl-no-revoke` (albo `curl.exe --ssl-revoke-best-effort`). W firmie CA
  publikuje listę CRL albo serwer OCSP, a certyfikaty zawierają ich adresy.
- **Wniosek:** „certyfikat zaufany” i „certyfikat sprawdzony pod kątem unieważnienia” to dwa różne
  testy; różne programy robią je inaczej.
