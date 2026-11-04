# Etap 3 – rozwiązania ćwiczeń: własny chart Helma

Odpowiedzi na „Sprawdź się” z [ćwiczeń](11-cwiczenia-wlasny-chart-helm.md). Zrób poziom sam,
potem porównaj.

**Wyniki z labu.** Poziomy 1–3 właściciel przeszedł 04.11.2026 (wyniki niżej). Wyniki poziomów
4–7 zostaną dopisane po ich wykonaniu.

---

## Poziom 1 – szkielet chartu

- **`Chart.yaml`** to „metryczka” chartu: nazwa, opis, wersja chartu, wersja aplikacji, typ
  (`application` albo `library`). **`values.yaml`** to domyślne ustawienia, które trafiają do
  szablonów; użytkownik nadpisuje je przez `-f własne-values.yaml` albo `--set`.
- **`version`** (`0.1.0`) – wersja **paczki** (chartu); podnosisz ją przy każdej zmianie szablonów.
  **`appVersion`** (`"1.16.0"`) – wersja **aplikacji** w środku, zwykle tag obrazu. Ten sam chart
  może mieć kilka wersji z tą samą aplikacją (jak kube-prometheus-stack 92.16.1 z aplikacją v0.94.2).
- `templates/*` usuwa zawartość, katalog zostaje – Helm szuka w nim szablonów. `rm -rf ~/app/templates`
  usuwa katalog i trzeba go utworzyć na nowo (`mkdir ~/app/templates`).

## Poziom 2 – pierwszy szablon

- `{{ .Values.configMap.firstName }}`: z wartości (`.Values`) weź sekcję `configMap`, a z niej pole
  `firstName`. Kropka na początku to „wszystko, co Helm przekazuje do szablonu” (`.Values`,
  `.Release`, `.Chart`…). Wartość pochodzi z `values.yaml`, chyba że nadpiszesz ją `--set` albo `-f`.
- `<<'EOF'` w apostrofach: bash wkleja tekst **dosłownie**. Bez apostrofów podstawiłby `$ZMIENNA`
  od razu – zwykle pustą wartością, bo w Twojej powłoce takiej zmiennej nie ma.
- Cztery warstwy: **bash** (`cat > plik <<'EOF'`) – Twój terminal, gdy tworzysz plik; **szablony Go**
  (`{{ }}`) – Helm przy `template`/`install`/`upgrade`; **YAML** – Kubernetes, gdy dostaje manifest;
  **sh** (`echo $FIRST_NAME`, poziom 5) – kontener, gdy startuje.

**Wynik w labie – dwa problemy przy pierwszym podejściu:**

```
Error: YAML parse error on app/templates/config-map.yaml: error converting YAML to JSON:
yaml: line 7: mapping values are not allowed in this context
```

Na końcu ostatniej linii szablonu był doklejony początek pliku values:
`SECOND_NAME: {{ .Values.configMap.secondName }}configMap:` – dwa dwukropki w jednej linii. Do tego
plik powstał przez `sudo` i należał do `root` (`-rw-r--r-- 1 root root … config-map.yaml`), więc
nie dało się go poprawić jako `grzegorz`. Naprawa: `sudo chown grzegorz:grzegorz …` i ponowny
zapis pliku. Opis: [problemy Etapu 3](problemy.md#helm-template-yaml-parse-error--mapping-values-are-not-allowed).

## Poziom 3 – podgląd bez instalacji

Wynik w labie:

```yaml
---
# Source: app/templates/config-map.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-configuration
data:
  FIRST_NAME: Hello
  SECOND_NAME: World
```

- `helm template` czyta chart, wypełnia szablony wartościami i **wypisuje wynik na ekran**
  (standardowe wyjście). Nie łączy się z klastrem, niczego nie tworzy, nie zapisuje release'u
  i nie tworzy pliku – plik powstaje dopiero przez `>`.
- `my-app` to nazwa release'u, wymyślona w poleceniu. W tym chartcie nie zmienia wyniku, bo żaden
  szablon nie używa `{{ .Release.Name }}` – nazwa ConfigMapa pochodzi z values. Zmieni się od poziomu 5.
- `>` zastępuje zawartość pliku, `>>` dopisuje na końcu, `| tee plik` zapisuje do pliku **i**
  pokazuje na ekranie.

## Poziom 4 – instalacja

- **Release** to jedna instalacja chartu pod wybraną nazwą. Helm zapisuje go w klastrze jako
  Secret w namespace release'u, po jednym na rewizję: `sh.helm.release.v1.my-app.v1`, `…v2`…
  (`kubectl get secret -n helm-lab`). Stąd `helm history` i `helm rollback`.
- `kube-root-ca.crt` Kubernetes tworzy sam w **każdym** namespace: certyfikat CA klastra, którym
  pody sprawdzają, że rozmawiają z prawdziwym API.
- `helm list` bez `-n` pokazuje release'y z namespace `default` – `my-app` nie będzie widoczny.
  Wszystkie: `helm list -A`.

## Poziom 5 – aplikacja czyta ConfigMap

- `my-app-pod` = `{{ .Release.Name }}` + `-pod`. Po `helm install test ~/app` byłby `test-pod`.
  Dzięki temu ten sam chart można zainstalować kilka razy bez konfliktu nazw (ale ConfigMap ma
  nazwę z values, więc dwa release'y w **jednym** namespace i tak by się pokłóciły).
- `envFrom` + `configMapRef` zamienia **każdy** klucz ConfigMapa na zmienną środowiskową.
  `env` + `valueFrom.configMapKeyRef` bierze **jeden** wybrany klucz i pozwala nadać zmiennej
  inną nazwę.
- Bash nie podstawił `$FIRST_NAME` dzięki `'EOF'`; Helm rusza tylko `{{ }}`; YAML traktuje to jako
  tekst. Podstawia dopiero `sh` w kontenerze, który ma już zmienne z ConfigMapa.

## Poziom 6 – zmiana ustawień

- Zmienne środowiskowe ustawia się **raz, przy starcie kontenera**. Zmiana ConfigMapa nie dociera
  do działającego procesu. (ConfigMap zamontowany jako **plik** odświeża się sam po około minucie –
  ale aplikacja musi plik przeczytać ponownie.)
- W Deploymencie: `kubectl rollout restart deployment NAZWA` albo – w chartach – adnotacja
  z sumą kontrolną ConfigMapa w szablonie poda:
  `checksum/config: {{ include (print $.Template.BasePath "/config-map.yaml") . | sha256sum }}`.
  Zmiana ConfigMapa zmienia sumę, a zmiana szablonu poda wywołuje rolling update. Gotowe narzędzie
  do tego samego: Reloader (stakater).
- `values.yaml` (albo osobny plik `-f`), trzymany w gicie: widać, kto i kiedy zmienił ustawienie,
  a następny `helm upgrade` bez `--set` nie cofnie zmiany przypadkiem. `--set` – do szybkich testów.

## Poziom 7 – historia, rollback i sprzątanie

- Nie. Rollback tworzy **nową** rewizję – kopię wskazanej. Po rewizjach 1–4 i `rollback 2`
  historia ma rewizję 5 z opisem `Rollback to 2`, a 3 i 4 zostają jako `superseded`.
- `helm uninstall` usuwa obiekty utworzone przez release (ConfigMap, Pod) i jego historię
  (Secrety `sh.helm.release…`). Nie usuwa namespace'u (utworzonego przez `--create-namespace`),
  chartu na dysku ani – domyślnie – PVC utworzonych przez StatefulSety.
- Nie. Rollback zmienia ConfigMap, ale szablon poda w rewizji 2 jest taki sam jak w 4, więc Helm
  poda nie rusza – pod dalej ma `FIRST_NAME=Grzegorz`, dopóki nie wystartuje od nowa.
