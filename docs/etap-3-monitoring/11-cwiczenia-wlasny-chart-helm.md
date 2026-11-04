# Etap 3 – ćwiczenia: własny chart Helma

Siedem poziomów do rozdziałów 10–11 [teorii Helma](03-teoria-kubernetes-helm.md#10-helm--menedżer-paczek):
budujesz od zera własny chart z ConfigMapem i podem, który z niego czyta. Każdy poziom zajmuje
5–10 minut. Wszystko dzieje się w katalogu `~/app` na masterze i w namespace `helm-lab`, który na
końcu usuwasz.

Ćwiczenie odpowiada lekcji kursu Udemy w `~/kubernetes-course/zarzadzanie_manifestami_helm/`.
Odpowiedzi na „Sprawdź się”: [rozwiązania](12-cwiczenia-wlasny-chart-helm-rozwiazania.md).

**Przed startem:** klaster działa (4 węzły `Ready`), Helm jest zainstalowany (`helm version`).
Wszystkie polecenia wpisujesz na 🐧 **k3s-master** (`ssh k3s-master`), **bez `sudo`** – pliki są
w Twoim katalogu domowym.

| Poziom | Temat |
|---|---|
| [1](#poziom-1--szkielet-chartu) | szkielet chartu: `helm create`, co jest w środku |
| [2](#poziom-2--pierwszy-szablon) | pierwszy szablon: ConfigMap z `{{ .Values… }}` |
| [3](#poziom-3--podgląd-bez-instalacji) | podgląd bez instalacji: `helm template`, `--set`, zapis do pliku |
| [4](#poziom-4--instalacja) | instalacja: `helm install`, release, sprawdzenie w klastrze |
| [5](#poziom-5--aplikacja-czyta-configmap) | aplikacja czyta ConfigMap: drugi szablon, `.Release.Name`, `helm upgrade` |
| [6](#poziom-6--zmiana-ustawień) | zmiana ustawień: dlaczego pod nie widzi nowej wartości |
| [7](#poziom-7--historia-rollback-i-sprzątanie) | historia, rollback i sprzątanie |

---

## Poziom 1 – szkielet chartu

**Cel:** utworzyć chart i zobaczyć, z czego się składa.

1. Utwórz szkielet w katalogu domowym:
   ```bash
   cd ~
   helm create app
   ```
2. Obejrzyj, co powstało:
   ```bash
   find app | sort
   cat app/Chart.yaml
   ```
3. Usuń przykładowe szablony – napiszesz własne. Katalog `templates/` musi zostać (pusty):
   ```bash
   rm -rf ~/app/templates/*
   ls -la ~/app/templates
   ```
4. Wyczyść plik values (sam znak `>` opróżnia plik):
   ```bash
   > ~/app/values.yaml
   ```

**Co powinieneś zobaczyć:** `Creating app`; w drzewie `Chart.yaml`, `values.yaml`, `.helmignore`,
`charts/` i `templates/` z kilkoma plikami (`deployment.yaml`, `service.yaml`, `ingress.yaml`,
`_helpers.tpl`, `NOTES.txt`, `tests/`…). Po kroku 3 `templates/` jest pusty.

**Sprawdź się:**
- Do czego służy `Chart.yaml`, a do czego `values.yaml`?
- Czym różni się `version` od `appVersion` w `Chart.yaml`?
- Dlaczego `rm -rf ~/app/templates/*`, a nie `rm -rf ~/app/templates`?

## Poziom 2 – pierwszy szablon

**Cel:** napisać szablon, w którym wartości pochodzą z `values.yaml`.

1. Wartości:
   ```bash
   cat > ~/app/values.yaml <<'EOF'
   configMap:
     name: app-configuration
     firstName: Hello
     secondName: World
   EOF
   ```
2. Szablon ConfigMapa:
   ```bash
   cat > ~/app/templates/config-map.yaml <<'EOF'
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: {{ .Values.configMap.name }}
   data:
     FIRST_NAME: {{ .Values.configMap.firstName }}
     SECOND_NAME: {{ .Values.configMap.secondName }}
   EOF
   ```
3. Sprawdź oba pliki i właściciela:
   ```bash
   cat ~/app/values.yaml ~/app/templates/config-map.yaml
   ls -l ~/app/templates
   ```

**Co powinieneś zobaczyć:** dokładnie te linie, nic doklejonego na końcu; właściciel pliku
`grzegorz grzegorz` (nie `root`).

**Sprawdź się:**
- Jak czytasz `{{ .Values.configMap.firstName }}`? Skąd Helm weźmie wartość?
- Po co apostrofy w `<<'EOF'`? Co by się stało z `$ZMIENNA` w tekście bez nich?
- W jakich językach jest polecenie z kroku 2? Kto czyta każdą część i kiedy?

## Poziom 3 – podgląd bez instalacji

**Cel:** zobaczyć gotowy YAML, zanim cokolwiek trafi do klastra.

1. Wygeneruj manifest:
   ```bash
   helm template my-app ~/app
   ```
2. Podmień wartość bez zmiany pliku:
   ```bash
   helm template my-app ~/app --set configMap.firstName=Grzegorz
   ```
3. Zapisz wynik do pliku i obejrzyj:
   ```bash
   helm template my-app ~/app > ~/wynik.yaml
   cat ~/wynik.yaml
   ```
4. Sprawdź, czy coś powstało w klastrze:
   ```bash
   kubectl get configmap app-configuration
   ```

**Co powinieneś zobaczyć:** ConfigMap z `name: app-configuration`, `FIRST_NAME: Hello`,
`SECOND_NAME: World` (w kroku 2 – `Grzegorz`); nad nim komentarz `# Source: app/templates/config-map.yaml`.
W kroku 4: `Error from server (NotFound)`.

**Sprawdź się:**
- Co robi `helm template`, a czego nie robi? Gdzie trafia jego wynik?
- Skąd się wzięło `my-app`? Czy zmiana na inną nazwę zmieni wynik w tym chartcie – dlaczego?
- Czym różni się `>` od `>>` i od `| tee`?

## Poziom 4 – instalacja

**Cel:** zainstalować chart jako release w osobnym namespace.

1. Instalacja:
   ```bash
   helm install my-app ~/app -n helm-lab --create-namespace
   ```
2. Sprawdzenie:
   ```bash
   helm list -n helm-lab
   kubectl get configmap -n helm-lab
   kubectl describe configmap app-configuration -n helm-lab
   ```

**Co powinieneś zobaczyć:** `STATUS: deployed`, `REVISION: 1`; w `helm list` release `my-app`
z chartem `app-0.1.0`; ConfigMapy `app-configuration` i `kube-root-ca.crt`; w sekcji `Data`
`FIRST_NAME: Hello` i `SECOND_NAME: World`.

**Sprawdź się:**
- Czym jest release i gdzie Helm go zapisuje?
- Skąd w namespace drugi ConfigMap `kube-root-ca.crt`?
- Co się stanie, gdy wpiszesz `helm list` bez `-n helm-lab`?

## Poziom 5 – aplikacja czyta ConfigMap

**Cel:** dodać pod, który dostaje wartości z ConfigMapa jako zmienne środowiskowe.

1. Drugi szablon:
   ```bash
   cat > ~/app/templates/pod.yaml <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: {{ .Release.Name }}-pod
   spec:
     containers:
       - name: app
         image: busybox:1.36
         command: ["sh", "-c", "echo Czesc $FIRST_NAME $SECOND_NAME; sleep 3600"]
         envFrom:
           - configMapRef:
               name: {{ .Values.configMap.name }}
   EOF
   ```
2. Podgląd, potem aktualizacja release'u:
   ```bash
   helm template my-app ~/app
   helm upgrade my-app ~/app -n helm-lab
   ```
3. Czy aplikacja widzi ustawienia:
   ```bash
   kubectl get pod -n helm-lab
   kubectl logs my-app-pod -n helm-lab
   kubectl exec my-app-pod -n helm-lab -- env | grep NAME
   ```

**Co powinieneś zobaczyć:** w podglądzie dwa obiekty (ConfigMap i Pod `my-app-pod`); po upgrade
`REVISION: 2`; pod `Running`; w logach `Czesc Hello World`; w `env` – `FIRST_NAME=Hello`
i `SECOND_NAME=World`.

**Sprawdź się:**
- Skąd nazwa `my-app-pod`? Jak brzmiałaby po `helm install test ~/app`?
- Co robi `envFrom` z `configMapRef`? Czym różni się od `env` z `valueFrom`?
- Dlaczego `$FIRST_NAME` nie został podmieniony ani przez bash, ani przez Helma?

## Poziom 6 – zmiana ustawień

**Cel:** zmienić wartość przez Helma i zobaczyć, kiedy aplikacja ją widzi.

1. Zmień imię:
   ```bash
   helm upgrade my-app ~/app -n helm-lab --set configMap.firstName=Grzegorz
   kubectl describe configmap app-configuration -n helm-lab
   kubectl logs my-app-pod -n helm-lab
   kubectl exec my-app-pod -n helm-lab -- env | grep FIRST
   ```
2. Uruchom pod od nowa i powtórz upgrade (Helm odtworzy brakujący pod):
   ```bash
   kubectl delete pod my-app-pod -n helm-lab
   helm upgrade my-app ~/app -n helm-lab --set configMap.firstName=Grzegorz
   kubectl logs my-app-pod -n helm-lab
   ```

**Co powinieneś zobaczyć:** w kroku 1 ConfigMap ma już `FIRST_NAME: Grzegorz`, ale logi i `env`
dalej pokazują `Hello`. W kroku 2 – `Czesc Grzegorz World`.

**Sprawdź się:**
- Dlaczego działający pod nie widzi nowej wartości z ConfigMapa?
- Jak to się robi w Deploymencie, żeby nie kasować podów ręcznie?
- Co jest lepsze w pracy: `--set` czy zmiana w `values.yaml` – dlaczego?

## Poziom 7 – historia, rollback i sprzątanie

**Cel:** zobaczyć historię release'u, wrócić do poprzedniej wersji i posprzątać.

1. Historia:
   ```bash
   helm history my-app -n helm-lab
   ```
2. Powrót do rewizji 2 (bez `--set`, `firstName: Hello`):
   ```bash
   helm rollback my-app 2 -n helm-lab
   helm history my-app -n helm-lab
   kubectl describe configmap app-configuration -n helm-lab
   ```
3. Sprzątanie:
   ```bash
   helm uninstall my-app -n helm-lab
   kubectl get all,configmap -n helm-lab
   kubectl delete namespace helm-lab
   rm ~/wynik.yaml
   ```

**Co powinieneś zobaczyć:** w historii kilka rewizji (`Install complete`, `Upgrade complete`);
po rollbacku **nowa** rewizja z opisem `Rollback to 2` i `FIRST_NAME: Hello` w ConfigMapie;
po `uninstall` w namespace zostaje tylko `kube-root-ca.crt`. Katalog `~/app` z chartem zostaje
na dysku – możesz go zainstalować ponownie.

**Sprawdź się:**
- Czy rollback usuwa rewizje 3 i 4? Jak wygląda historia po nim?
- Co usuwa `helm uninstall`, a czego nie?
- Rollback ConfigMapa się udał – czy pod od razu pokaże `Hello`?

## Ściągawka

| Polecenie | Co robi |
|---|---|
| `helm create NAZWA` | szkielet chartu |
| `helm template RELEASE KATALOG` | gotowe YAML-e na ekran, bez instalacji |
| `helm template … --set klucz=wartość` | podgląd z inną wartością |
| `helm install RELEASE KATALOG -n NS --create-namespace` | instalacja własnego chartu z dysku |
| `helm upgrade RELEASE KATALOG -n NS` | wdrożenie zmian w szablonach lub values |
| `helm history RELEASE -n NS` / `helm rollback RELEASE N -n NS` | historia i powrót |
| `helm uninstall RELEASE -n NS` | usunięcie obiektów release'u |

Wszystkie polecenia labu: [ściągawka poleceń](../sciagawka-polecen.md#helm).
