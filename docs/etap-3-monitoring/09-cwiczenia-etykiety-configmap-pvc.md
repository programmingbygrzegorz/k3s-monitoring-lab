# Etap 3 – ćwiczenia: etykiety, ConfigMap, Secret i trwałe dane

Osiem poziomów do rozdziałów 3–5 [teorii Kubernetesa](03-teoria-kubernetes-helm.md): etykiety
i selektory, ConfigMap i Secret, PVC. Każdy poziom zajmuje 5–15 minut. Wszystko dzieje się
w osobnym namespace `cwiczenia-k8s`, który na końcu usuwasz jednym poleceniem.

Wykonanie wszystkich poziomów ze zrzutami i odpowiedziami:
[rozwiązania](10-cwiczenia-etykiety-configmap-pvc-rozwiazania.md). Nazwy podów, adresy IP
i węzły u Ciebie będą inne.

**Przed startem:** klaster działa (4 węzły `Ready`), w rejestrze na `monitoring` jest obraz
`192.168.180.54:5000/hello-lab:1.0` ([Etap 4 – własny obraz](../etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md)).

| Poziom | Temat |
|---|---|
| [1](#poziom-1--naklejki-na-podach) | naklejki na podach: `--labels`, `--show-labels`, `-L` |
| [2](#poziom-2--selektory) | selektory: `=`, `!=`, `in`, `notin`, istnienie etykiety |
| [3](#poziom-3--etykiety-łączą-obiekty) | etykiety łączą obiekty: Deployment, Service, endpointy |
| [4](#poziom-4--configmap) | ConfigMap jako zmienne i pliki |
| [5](#poziom-5--zmiana-konfiguracji) | zmiana konfiguracji: co zmienia się samo, a co po restarcie |
| [6](#poziom-6--secret) | Secret i base64 |
| [7](#poziom-7--własny-trwały-dysk) | własny trwały dysk: PVC, PV, local-path |
| [8](#poziom-8--sprzątanie-i-reclaimpolicy) | sprzątanie i `reclaimPolicy` |

---

## Przygotowanie

🪟 Windows:

```powershell
ssh k3s-master
```

🐧 k3s-master:

```bash
cd ~/k3s-monitoring-lab
git pull
ls kubernetes/cwiczenia-k8s/
kubectl create namespace cwiczenia-k8s
```

**Co powinieneś zobaczyć:** cztery pliki (`sklep.yaml`, `hello-config.yaml`, `notatnik-pvc.yaml`,
`notatnik-pod.yaml`) i `namespace/cwiczenia-k8s created`.

## Poziom 1 – naklejki na podach

**Cel:** nadać podom etykiety i je zobaczyć.

1. Utwórz trzy pody z różnymi etykietami (`kubectl run` tworzy pojedynczy pod):
   ```bash
   kubectl -n cwiczenia-k8s run sklep-www --image=192.168.180.54:5000/hello-lab:1.0 --labels=app=sklep,tier=frontend,team=blue
   kubectl -n cwiczenia-k8s run sklep-api --image=192.168.180.54:5000/hello-lab:1.0 --labels=app=sklep,tier=backend,team=green
   kubectl -n cwiczenia-k8s run raporty-api --image=192.168.180.54:5000/hello-lab:1.0 --labels=app=raporty,tier=backend,team=yellow
   ```
2. Pokaż etykiety: `kubectl -n cwiczenia-k8s get pods --show-labels`.
3. Pokaż wybrane etykiety jako kolumny: `kubectl -n cwiczenia-k8s get pods -L app,tier,team`.

**Co powinieneś zobaczyć:** 3 pody `Running`; w kolumnie `LABELS` po trzy pary `klucz=wartość`.

**Sprawdź się:**
- Czym etykieta różni się od nazwy poda?
- Który zapis jest wygodniejszy przy 20 etykietach: `--show-labels` czy `-L`?

## Poziom 2 – selektory

**Cel:** wybierać pody po etykietach i zmieniać etykiety.

1. Zadaj pytania (`-l` = `--selector`). Zanim naciśniesz Enter, zgadnij wynik:
   ```bash
   kubectl -n cwiczenia-k8s get pods -l tier=backend
   kubectl -n cwiczenia-k8s get pods -l tier=backend,team=green
   kubectl -n cwiczenia-k8s get pods -l 'team!=blue'
   kubectl -n cwiczenia-k8s get pods -l 'team in (blue,yellow)'
   kubectl -n cwiczenia-k8s get pods -l 'app=sklep,tier notin (frontend)'
   ```
2. Dodaj etykietę i wyszukaj po samym jej istnieniu:
   ```bash
   kubectl -n cwiczenia-k8s label pod sklep-www env=prod
   kubectl -n cwiczenia-k8s get pods -l env
   kubectl -n cwiczenia-k8s get pods -l '!env'
   ```
3. Zmień istniejącą etykietę – najpierw bez, potem z `--overwrite`:
   ```bash
   kubectl -n cwiczenia-k8s label pod sklep-www team=red
   kubectl -n cwiczenia-k8s label pod sklep-www team=red --overwrite
   ```
4. Usuń etykietę (klucz z minusem): `kubectl -n cwiczenia-k8s label pod sklep-www env-`.
5. Usuń pody po etykietach – najpierw zawsze `get` z tym samym `-l`:
   ```bash
   kubectl -n cwiczenia-k8s get pods -l app=raporty
   kubectl -n cwiczenia-k8s delete pods -l app=raporty
   kubectl -n cwiczenia-k8s delete pods -l app=sklep
   ```

**Co powinieneś zobaczyć:** pierwsza próba zmiany `team` kończy się błędem
`'team' already has a value (blue), and --overwrite is false`. Po kroku 5 namespace jest pusty.

**Sprawdź się:**
- Co znaczy przecinek w selektorze: „i” czy „lub”? A jak zapisać „lub”?
- Dlaczego `'team in (blue,yellow)'` musi być w apostrofach?
- Po co `kubectl label` wymaga `--overwrite`?

## Poziom 3 – etykiety łączą obiekty

**Cel:** zobaczyć, że Deployment i Service znajdują pody tylko po etykietach.

1. Obejrzyj plik [sklep.yaml](../../kubernetes/cwiczenia-k8s/sklep.yaml): `cat kubernetes/cwiczenia-k8s/sklep.yaml`.
   Znajdź trzy miejsca z `app: sklep`. Które jest selektorem Deploymentu, które etykietą poda,
   a które selektorem Service?
2. Wdróż i sprawdź, dokąd Service wysyła ruch:
   ```bash
   kubectl apply -f kubernetes/cwiczenia-k8s/sklep.yaml
   kubectl -n cwiczenia-k8s get pods -l app=sklep -o wide
   kubectl -n cwiczenia-k8s get endpointslices -l kubernetes.io/service-name=sklep
   ```
3. „Odklej” jeden pod od reszty – zmień mu etykietę `app` (wstaw nazwę swojego poda):
   ```bash
   kubectl -n cwiczenia-k8s label pod <nazwa-poda> app=naprawa --overwrite
   kubectl -n cwiczenia-k8s get pods -L app
   kubectl -n cwiczenia-k8s get endpointslices -l kubernetes.io/service-name=sklep
   kubectl -n cwiczenia-k8s get pod <nazwa-poda> -o jsonpath='{.metadata.ownerReferences}'; echo
   ```
4. Przyklej etykietę z powrotem i odczekaj kilka sekund:
   ```bash
   kubectl -n cwiczenia-k8s label pod <nazwa-poda> app=sklep --overwrite
   kubectl -n cwiczenia-k8s get pods -L app
   ```

**Co powinieneś zobaczyć:** po kroku 3 są **trzy** pody (ReplicaSet dorobił brakujący), adres
odklejonego poda znika z endpointów, a `ownerReferences` jest puste. Po kroku 4 jeden pod
dostaje `Terminating`.

**Sprawdź się:**
- Dlaczego ReplicaSet utworzył nowy pod, choć żaden nie padł?
- Kto jest „właścicielem” odklejonego poda?
- Dlaczego po kroku 4 Kubernetes usunął pod, i to akurat ten najmłodszy?
- Jak wykorzystać odklejanie przy awarii aplikacji w produkcji?

## Poziom 4 – ConfigMap

**Cel:** podać aplikacji ustawienia z zewnątrz – jako zmienne i jako pliki.

1. Przygotuj plik i utwórz ConfigMapę z dwóch wartości i jednego pliku:
   ```bash
   printf 'Witaj w labie k3s!\nTen plik pochodzi z ConfigMapy.\n' > ~/powitanie.txt
   kubectl -n cwiczenia-k8s create configmap hello-config --from-literal=APP_COLOR='#c53030' \
     --from-literal=APP_VERSION=konfig-1 --from-file=$HOME/powitanie.txt
   kubectl -n cwiczenia-k8s get configmap hello-config
   kubectl -n cwiczenia-k8s describe configmap hello-config
   ```
2. Obejrzyj [hello-config.yaml](../../kubernetes/cwiczenia-k8s/hello-config.yaml) – znajdź
   `envFrom`, `volumeMounts` i `volumes`. Wdróż:
   ```bash
   kubectl apply -f kubernetes/cwiczenia-k8s/hello-config.yaml
   kubectl -n cwiczenia-k8s get pods -l app=hello -o wide
   ```
3. Zajrzyj do kontenera:
   ```bash
   kubectl -n cwiczenia-k8s exec deploy/hello -- env | grep -E 'APP_|DB_'
   kubectl -n cwiczenia-k8s exec deploy/hello -- ls /etc/hello
   kubectl -n cwiczenia-k8s exec deploy/hello -- cat /etc/hello/powitanie.txt
   curl -s http://192.168.180.51:30881/api
   ```
4. 🪟 Otwórz w przeglądarce `http://192.168.180.51:30881`.

**Co powinieneś zobaczyć:** `DATA 3` przy ConfigMapie, zmienne `APP_COLOR` i `APP_VERSION`,
trzy pliki w `/etc/hello`, **czerwoną** stronę z wersją `konfig-1`. Zmiennej `DB_HASLO` nie ma.

**Sprawdź się:**
- Obraz `hello-lab:1.0` ma wpisaną wersję `1.0`. Dlaczego strona pokazuje `konfig-1`?
- Jaki klucz dostał plik dodany przez `--from-file`?
- Dlaczego pod wystartował, choć Secret `baza` z pliku YAML nie istnieje?

## Poziom 5 – zmiana konfiguracji

**Cel:** sprawdzić, kiedy aplikacja widzi nowe ustawienia.

1. Zanotuj godzinę i zmień kolor na zielony oraz wersję:
   ```bash
   date +%T
   kubectl -n cwiczenia-k8s patch configmap hello-config -p '{"data":{"APP_COLOR":"#2f855a","APP_VERSION":"konfig-2"}}'
   ```
2. Od razu sprawdź zmienne, plik i stronę:
   ```bash
   kubectl -n cwiczenia-k8s exec deploy/hello -- env | grep APP_
   kubectl -n cwiczenia-k8s exec deploy/hello -- cat /etc/hello/APP_VERSION; echo
   curl -s http://192.168.180.51:30881/api
   ```
3. Powtarzaj `cat /etc/hello/APP_VERSION` co kilkanaście sekund, aż pokaże `konfig-2`.
   Zanotuj godzinę. Odśwież stronę w przeglądarce – jaki ma kolor?
4. Uruchom pody od nowa:
   ```bash
   kubectl -n cwiczenia-k8s rollout restart deploy/hello
   kubectl -n cwiczenia-k8s rollout status deploy/hello
   kubectl -n cwiczenia-k8s exec deploy/hello -- env | grep APP_
   ```
   Odśwież stronę.

**Co powinieneś zobaczyć:** zaraz po zmianie wszystko stare. Po ok. minucie plik pokazuje
`konfig-2`, ale strona dalej jest czerwona. Po `rollout restart` strona jest **zielona**.

**Sprawdź się:**
- Ile sekund minęło, zanim zmienił się plik? Kto go podmienił?
- Dlaczego zmienna środowiskowa się nie zmieniła?
- Gdyby aplikacja czytała kolor z pliku `/etc/hello/APP_COLOR` przy każdym zapytaniu – czy
  restart byłby potrzebny?

## Poziom 6 – Secret

**Cel:** przekazać hasło przez Secret i zobaczyć, jak (nie)bezpiecznie jest przechowywane.

1. Sprawdź, że hasła jeszcze nie ma, i utwórz Secret:
   ```bash
   kubectl -n cwiczenia-k8s exec deploy/hello -- env | grep DB_ || echo 'brak DB_HASLO'
   kubectl -n cwiczenia-k8s create secret generic baza --from-literal=haslo='Lab-2026!'
   kubectl -n cwiczenia-k8s get secret baza
   kubectl -n cwiczenia-k8s describe secret baza
   ```
2. Odczytaj hasło tak, jak zrobiłby to każdy z dostępem do klastra:
   ```bash
   kubectl -n cwiczenia-k8s get secret baza -o jsonpath='{.data.haslo}'; echo
   kubectl -n cwiczenia-k8s get secret baza -o jsonpath='{.data.haslo}' | base64 -d; echo
   ```
3. Uruchom pod od nowa i sprawdź zmienną:
   ```bash
   kubectl -n cwiczenia-k8s rollout restart deploy/hello
   kubectl -n cwiczenia-k8s rollout status deploy/hello
   kubectl -n cwiczenia-k8s exec deploy/hello -- env | grep DB_
   ```

**Co powinieneś zobaczyć:** `describe` pokazuje tylko `haslo: 9 bytes`, ale `-o jsonpath` zwraca
tekst base64, a `base64 -d` – jawne hasło. Po restarcie pod ma `DB_HASLO=Lab-2026!`.

**Sprawdź się:**
- Czy base64 to szyfrowanie? Kto w labie może odczytać ten Secret?
- Dlaczego tego hasła nie wolno zapisać w YAML-u w repozytorium? Jak robi się to poprawnie?
- Kto jeszcze widzi hasło, gdy aplikacja dostaje je jako zmienną środowiskową?

## Poziom 7 – własny trwały dysk

**Cel:** zamówić dysk, zapisać na nim dane i sprawdzić, że przeżyją usunięcie poda.

1. Sprawdź klasę pamięci i złóż sam wniosek (bez poda):
   ```bash
   kubectl get storageclass
   kubectl apply -f kubernetes/cwiczenia-k8s/notatnik-pvc.yaml
   kubectl -n cwiczenia-k8s get pvc
   kubectl -n cwiczenia-k8s describe pvc notatki | sed -n '/Events:/,$p'
   ```
2. Uruchom pod, który używa tego PVC, i sprawdź, gdzie powstał dysk:
   ```bash
   kubectl apply -f kubernetes/cwiczenia-k8s/notatnik-pod.yaml
   kubectl -n cwiczenia-k8s get pvc
   kubectl -n cwiczenia-k8s get pod notatnik -o wide
   kubectl get pv <VOLUME-z-get-pvc> -o custom-columns=NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],PATH:.spec.local.path,RECLAIM:.spec.persistentVolumeReclaimPolicy
   ```
3. Zapisz notatkę i sprawdź, skąd jest miejsce:
   ```bash
   kubectl -n cwiczenia-k8s exec notatnik -- sh -c 'echo "pierwsza notatka $(date +%T)" >> /dane/notatki.txt'
   kubectl -n cwiczenia-k8s exec notatnik -- cat /dane/notatki.txt
   kubectl -n cwiczenia-k8s exec notatnik -- df -h /dane
   ```
4. Usuń pod, utwórz go od nowa i dopisz drugą notatkę:
   ```bash
   kubectl -n cwiczenia-k8s delete pod notatnik
   kubectl -n cwiczenia-k8s get pvc
   kubectl apply -f kubernetes/cwiczenia-k8s/notatnik-pod.yaml
   kubectl -n cwiczenia-k8s get pod notatnik -o wide
   kubectl -n cwiczenia-k8s exec notatnik -- sh -c 'echo "druga notatka $(date +%T)" >> /dane/notatki.txt'
   kubectl -n cwiczenia-k8s exec notatnik -- cat /dane/notatki.txt
   ```
5. Zajrzyj na dysk węzła z kolumny `NODE` (np. worker-1; `-t`, bo `sudo` zapyta o hasło):
   ```bash
   ssh -t k3s-worker-1 sudo ls -l /var/lib/rancher/k3s/storage
   ```

**Co powinieneś zobaczyć:** PVC najpierw `Pending` ze zdarzeniem `WaitForFirstConsumer`, po
starcie poda `Bound`. `df` pokazuje dysk **workera** (`ubuntu--vg-ubuntu--lv`, 38G), a nie 1Gi.
Nowy pod staje na **tym samym** węźle, a w pliku są obie notatki.

**Sprawdź się:**
- Dlaczego PVC czekał w `Pending`, dopóki nie powstał pod?
- Dlaczego `df` pokazuje 38G, skoro PVC prosi o 1Gi?
- Dlaczego drugi pod trafił na ten sam węzeł? Co by było, gdyby ten węzeł był wyłączony?

## Poziom 8 – sprzątanie i reclaimPolicy

**Cel:** zobaczyć, co dzieje się z danymi po usunięciu wniosku.

1. Zanotuj nazwę PV z poziomu 7 i usuń cały namespace:
   ```bash
   kubectl get pv <nazwa-pv>
   kubectl delete namespace cwiczenia-k8s
   kubectl get pv <nazwa-pv>
   kubectl get namespace cwiczenia-k8s
   ssh -t k3s-worker-1 sudo ls /var/lib/rancher/k3s/storage
   rm ~/powitanie.txt
   ```

**Co powinieneś zobaczyć:** `RECLAIM POLICY Delete`, po usunięciu namespace `NotFound` przy PV
i namespace, a w katalogu workera nie ma już `…_cwiczenia-k8s_notatki` – zostały tylko
dyski monitoringu.

**Sprawdź się:**
- Usunięcie namespace skasowało notatki. Która linia w klasie `local-path` o tym zdecydowała?
- Co zmieniłoby `reclaimPolicy: Retain`? Kiedy w firmie wybrałbyś `Retain`?
- Dlaczego dysków monitoringu nie dotknęło usunięcie `cwiczenia-k8s`?

## Ściągawka

| Polecenie | Do czego |
|---|---|
| `kubectl run <pod> --image=… --labels=a=b,c=d` | pod z etykietami |
| `kubectl get pods --show-labels` / `-L klucz1,klucz2` | etykiety: wszystkie / jako kolumny |
| `kubectl get pods -l 'a=b,c in (x,y),!d'` | wybór po etykietach |
| `kubectl label pod <pod> k=v [--overwrite]` / `k-` | dodaj, zmień / usuń etykietę |
| `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` | dokąd Service wysyła ruch |
| `kubectl create configmap <nazwa> --from-literal=K=V --from-file=plik` | ConfigMap |
| `kubectl create secret generic <nazwa> --from-literal=K=V` | Secret |
| `kubectl get secret <nazwa> -o jsonpath='{.data.K}' \| base64 -d` | odczyt Secretu |
| `kubectl rollout restart deploy/<nazwa>` | nowe pody – np. po zmianie ConfigMapy |
| `kubectl get pvc` / `kubectl get pv` | wnioski o dysk / dyski |
