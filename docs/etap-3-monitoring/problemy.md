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
  Teoria: [teoria Kubernetes i Helm](03-teoria-kubernetes-helm.md#6-kubeconfig--klucz-do-klastra).

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
