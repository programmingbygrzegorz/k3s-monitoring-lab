# Plik values monitoringu – co robi każda linia

Opis pliku [monitoring/kube-prometheus-stack-values.yaml](../../monitoring/kube-prometheus-stack-values.yaml),
z którym instalujesz chart **kube-prometheus-stack** w [Etapie 3](01-instalacja-monitoringu.md).

Czym jest chart, values i release – [docs/etap-3-monitoring/03-teoria-kubernetes-helm.md](03-teoria-kubernetes-helm.md#8-chart-values-i-release).

## Spis treści

1. [Po co ten plik](#1-po-co-ten-plik)
2. [Jak czytać YAML](#2-jak-czytać-yaml)
3. [Luki `${...}` i envsubst](#3-luki--i-envsubst)
4. [Grafana](#4-grafana)
5. [Prometheus](#5-prometheus)
6. [Alertmanager – trasy i odbiorcy](#6-alertmanager--trasy-i-odbiorcy)
7. [Wyłączone części: k3s jest inny](#7-wyłączone-części-k3s-jest-inny)
8. [Wyłączone reguły alertów](#8-wyłączone-reguły-alertów)
9. [Czego ten plik świadomie nie ustawia](#9-czego-ten-plik-świadomie-nie-ustawia)
10. [Jak znaleźć inne ustawienia](#10-jak-znaleźć-inne-ustawienia)
11. [Pytania, które mogą paść na rozmowie](#11-pytania-które-mogą-paść-na-rozmowie)

---

## 1. Po co ten plik

Chart ma **kilka tysięcy linii** domyślnych ustawień:

```bash
helm show values prometheus-community/kube-prometheus-stack | wc -l
```

Nasz plik ma niecałe 80 linii, bo **nadpisuje tylko to, co trzeba zmienić**. Wszystko, czego
w nim nie ma, zostaje domyślne. Zmieniamy trzy rodzaje rzeczy:

| Rodzaj | Przykład |
|---|---|
| **dostęp z zewnątrz** | porty NodePort dla Grafany, Prometheusa i Alertmanagera |
| **dopasowanie do labu** | pamięć Prometheusa, czas przechowywania metryk, powiadomienia |
| **dopasowanie do k3s** | wyłączenie części, które w k3s działają inaczej niż w zwykłym Kubernetesie |

## 2. Jak czytać YAML

Wcięcia (zawsze **spacje**, nigdy tabulatory) pokazują, co jest czym:

```yaml
grafana:              # sekcja "grafana"
  service:            # w niej sekcja "service"
    nodePort: 30300   # w niej ustawienie "nodePort"
```

To samo w zapisie z kropkami: `grafana.service.nodePort = 30300`. W szablonie chartu odpowiada
temu luka `{{ .Values.grafana.service.nodePort }}`.

| Zapis | Znaczenie |
|---|---|
| `klucz: wartość` | ustawienie |
| `- coś` | element listy |
| `# tekst` | komentarz – YAML go pomija |
| `"tekst"` | tekst w cudzysłowie – bezpieczny, gdy zawiera znaki specjalne |

## 3. Luki `${...}` i envsubst

Dwie wartości w pliku to **luki**, a nie prawdziwe dane:

```yaml
adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
url: "${HEALTHCHECKS_URL}"
```

Hasło i prywatny adres nie mogą trafić do publicznego repozytorium. Prawdziwe wartości są
w `lab.env` (poza gitem). Przed instalacją program **`envsubst`** wstawia je w luki:

```bash
envsubst '${GRAFANA_ADMIN_PASSWORD} ${HEALTHCHECKS_URL}' < values.yaml > /tmp/values-gotowe.yaml
```

- `envsubst` zamienia `${ZMIENNA}` na wartość zmiennej środowiskowej.
- Lista w apostrofach mówi: **zamień tylko te dwie**. Bez niej `envsubst` zamieniłby każdy napis
  z `$`, także taki, który ma zostać dosłownie.
- Helm sam nie rozumie `${...}` – to nie jego składnia. Gdyby dostał plik bez podstawienia,
  hasło Grafany brzmiałoby dosłownie `${GRAFANA_ADMIN_PASSWORD}`.

Skrypt `scripts/04-install-monitoring.sh` robi to automatycznie. W Etapie 3 zrobisz to ręcznie.

## 4. Grafana

```yaml
grafana:
  enabled: true
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  defaultDashboardsTimezone: browser
  service:
    type: NodePort
    nodePort: 30300
```

| Linia | Co robi |
|---|---|
| `enabled: true` | zainstaluj Grafanę (chart pozwala ją pominąć, gdy masz własną) |
| `adminPassword` | hasło użytkownika `admin` przy pierwszym uruchomieniu |
| `defaultDashboardsTimezone: browser` | dashboardy pokazują czas w strefie przeglądarki, a nie UTC – godziny zgadzają się z zegarkiem |
| `service.type: NodePort` | Service Grafany dostępny z zewnątrz na porcie każdego węzła (domyślnie byłby `ClusterIP` – tylko w klastrze) |
| `nodePort: 30300` | konkretny numer portu; bez tego Kubernetes wylosowałby port z zakresu 30000–32767 |

Efekt: `http://192.168.180.51:30300` (albo IP dowolnego workera).

Grafana z tego chartu ma od razu **źródło danych** (Prometheus) i **kilkadziesiąt gotowych
dashboardów** – trafiają do klastra jako ConfigMapy, a pomocniczy kontener (sidecar) wczytuje je
do Grafany.

## 5. Prometheus

```yaml
prometheus:
  service:
    type: NodePort
    nodePort: 30090
  prometheusSpec:
    retention: 7d
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        memory: 1536Mi
```

| Linia | Co robi |
|---|---|
| `service` … `30090` | Prometheus dostępny z zewnątrz. Potrzebne w Etapie 4: zewnętrzna Grafana na maszynie `monitoring` czyta dane właśnie stąd |
| `prometheusSpec` | ustawienia samego Prometheusa; operator zamienia je na obiekt typu `Prometheus` |
| `retention: 7d` | trzymaj metryki 7 dni, starsze usuwaj. Dłużej = więcej miejsca na dysku |

### Trzy linie `…SelectorNilUsesHelmValues: false`

To najczęstsza pułapka tego chartu. Domyślnie Prometheus zbiera tylko te ServiceMonitory,
PodMonitory i reguły, które mają etykietę `release: monitoring` – czyli te założone przez
**ten sam** release Helma.

Nasz ServiceMonitor dla podinfo i nasze reguły alertów ([kubernetes/monitoring/](../../kubernetes/monitoring))
nie mają tej etykiety. Bez tych trzech linii Prometheus by je **po cichu pominął** – bez błędu,
po prostu podinfo nie pojawiłoby się w *Status → Targets*.

| Linia | Dotyczy |
|---|---|
| `serviceMonitorSelectorNilUsesHelmValues: false` | ServiceMonitorów – „zbieraj z tych Service'ów” |
| `podMonitorSelectorNilUsesHelmValues: false` | PodMonitorów – to samo, ale bezpośrednio z podów |
| `ruleSelectorNilUsesHelmValues: false` | PrometheusRule – reguł alertów |

`false` znaczy: **bierz wszystkie z całego klastra**. W labie to wygodne. W dużej firmie, gdzie
kilka zespołów ma własne Prometheusy, każdy wybiera „swoje” obiekty po etykietach.

### Zasoby

| Linia | Znaczenie |
|---|---|
| `requests.cpu: 200m` | rezerwacja 0,2 rdzenia – scheduler postawi Prometheusa tylko tam, gdzie tyle jest wolne |
| `requests.memory: 512Mi` | rezerwacja 512 MiB pamięci |
| `limits.memory: 1536Mi` | sufit 1,5 GiB – po przekroczeniu kontener zostanie zabity (OOMKilled) |

Brak limitu CPU jest celowy: limit CPU nie zabija, tylko spowalnia (dławi), a Prometheus przy
starcie potrzebuje chwilowo więcej mocy. Zużycie pamięci Prometheusa rośnie z liczbą metryk – przy
4 węzłach mieści się zwykle w 500–900 MiB.

## 6. Alertmanager – trasy i odbiorcy

Prometheus **wykrywa** problemy według reguł i wysyła alerty do Alertmanagera. Alertmanager
**decyduje, co z nimi zrobić**: grupuje je, czeka, powtarza i wysyła do odbiorców.

```yaml
alertmanager:
  service:
    type: NodePort
    nodePort: 30093
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: "null"
      group_by: ["alertname", "namespace"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - receiver: deadmans-switch
          matchers:
            - alertname = "Watchdog"
          group_wait: 0s
          group_interval: 1m
          repeat_interval: 1m
    receivers:
      - name: "null"
      - name: deadmans-switch
        webhook_configs:
          - url: "${HEALTHCHECKS_URL}"
            send_resolved: false
```

### Ogólne

| Linia | Co robi |
|---|---|
| `nodePort: 30093` | strona Alertmanagera z listą aktywnych alertów i wyciszeń |
| `resolve_timeout: 5m` | jeśli alert przestanie przychodzić i nie ma informacji o końcu, po 5 minutach uznaj go za rozwiązany |

### Trasa główna (`route`) – co robić z alertami domyślnie

Porównanie: Alertmanager to **sortownia poczty**. Trasy mówią, do której skrzynki trafia list.

| Linia | Co robi |
|---|---|
| `receiver: "null"` | domyślnie wysyłaj do odbiorcy `null`, czyli **nigdzie**. Alerty widać na stronie Alertmanagera i w Grafanie, ale nie przychodzą powiadomienia |
| `group_by: ["alertname", "namespace"]` | alerty o tej samej nazwie w tym samym namespace łącz w **jedno** powiadomienie. Gdy padnie 10 podów w `demo`, dostaniesz 1 wiadomość, a nie 10 |
| `group_wait: 30s` | po pierwszym alercie z grupy poczekaj 30 s – może dojdą kolejne, wyślij je razem |
| `group_interval: 5m` | gdy do istniejącej grupy dojdzie nowy alert, wyślij aktualizację najwcześniej po 5 min |
| `repeat_interval: 4h` | jeśli problem trwa, przypominaj co 4 godziny – nie co minutę |

Te trzy czasy chronią przed **zalewem powiadomień** (alert fatigue): gdy telefon dzwoni co
minutę, ludzie zaczynają ignorować alerty.

### Trasa szczegółowa (`routes`) – dead man's switch

| Linia | Co robi |
|---|---|
| `receiver: deadmans-switch` | alerty pasujące do tej trasy idą do odbiorcy `deadmans-switch` |
| `matchers: alertname = "Watchdog"` | trasa dotyczy tylko alertu o nazwie `Watchdog` |
| `group_wait: 0s` | wysyłaj od razu |
| `group_interval: 1m`, `repeat_interval: 1m` | i powtarzaj **co minutę** |

**Watchdog** to alert, który chart ma wbudowany i który jest **zawsze aktywny** – jego warunek
to po prostu `vector(1)`, czyli „zawsze prawda”. Nie oznacza problemu. Oznacza: „łańcuch
Prometheus → Alertmanager → wysyłka działa”.

Dead man's switch („wyłącznik martwego człowieka”, jak w lokomotywie) działa odwrotnie niż zwykły
alert: **niepokojąca jest cisza**. Co minutę Watchdog trafia do healthchecks.io. Gdy przestanie
przychodzić – bo padł Prometheus, Alertmanager, sieć albo cały klaster – healthchecks.io wysyła Ci
powiadomienie. To jedyny alert, który zadziała, gdy cały monitoring leży.

### Odbiorcy (`receivers`)

| Odbiorca | Co robi |
|---|---|
| `null` | nic nie wysyła – „kosz” dla alertów, które mają być tylko widoczne |
| `deadmans-switch` | `webhook_configs` – wysyła żądanie HTTP POST na adres z `HEALTHCHECKS_URL` |
| `send_resolved: false` | nie wysyłaj informacji „alert się skończył” – Watchdog nigdy się nie kończy |

Gdy zechcesz dostawać prawdziwe powiadomienia (e-mail, Telegram, Slack), dodajesz odbiorcę
z `email_configs` / `telegram_configs` / `slack_configs` i ustawiasz go w trasie głównej zamiast
`null`.

## 7. Wyłączone części: k3s jest inny

```yaml
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubeEtcd:
  enabled: false
```

W zwykłym Kubernetesie controller-manager, scheduler, kube-proxy i etcd to **osobne programy**,
każdy z własnym adresem z metrykami. Chart domyślnie zakłada ServiceMonitory dla każdego z nich.

W k3s wszystko działa w **jednym procesie** `k3s server`, a baza danych to domyślnie SQLite
zamiast etcd. Pod adresami, których szuka chart, nikt nie odpowiada. Efekt bez tych linii:

- w *Status → Targets* cele w stanie **DOWN**,
- stale aktywne alerty `KubeControllerManagerDown`, `KubeSchedulerDown`, `KubeProxyDown` – choć
  wszystko działa.

To **fałszywe alarmy**. `enabled: false` mówi: nie zbieraj z tych miejsc.

## 8. Wyłączone reguły alertów

```yaml
defaultRules:
  rules:
    etcd: false
    kubeControllerManager: false
    kubeProxy: false
    kubeSchedulerAlerting: false
    kubeSchedulerRecording: false
```

Chart ma **kilkaset gotowych reguł** pogrupowanych w zestawy. Skoro nie zbieramy metryk tych
części (rozdział 7), reguły dla nich nie mają danych – wyłączamy je, żeby nie zaśmiecały listy.

| Zestaw | Co zawiera |
|---|---|
| `etcd` | alerty bazy etcd (k3s jej domyślnie nie używa) |
| `kubeControllerManager` | alerty controller-managera |
| `kubeProxy` | alerty kube-proxy |
| `kubeSchedulerAlerting` | alerty schedulera |
| `kubeSchedulerRecording` | **reguły nagrywające** schedulera – wstępnie liczone zapytania, które przyspieszają dashboardy |

Pozostałe zestawy – m.in. alerty węzłów, podów, Deploymentów, dysków – zostają włączone.

## 9. Czego ten plik świadomie nie ustawia

Uczciwie o ograniczeniach – to też dobry materiał na rozmowę.

| Brak | Skutek | Jak to się robi w produkcji |
|---|---|---|
| **trwały dysk dla Prometheusa** (`storageSpec`) | metryki leżą w katalogu tymczasowym poda; restart lub przeniesienie poda = **utrata historii**, mimo `retention: 7d` | `storageSpec` z PersistentVolumeClaim – w k3s np. klasa `local-path` |
| **trwały dysk dla Grafany** (`grafana.persistence`) | dashboardy dodane ręcznie w przeglądarce znikną przy restarcie poda | dashboardy jako kod (ConfigMap w gicie) albo `persistence.enabled: true` |
| **przypięta wersja chartu** | bez `--version` każda instalacja bierze najnowszą | `--version 92.16.1` przy instalacji albo `KPS_CHART_VERSION` w `lab.env` |
| **prawdziwe powiadomienia** | alerty widać tylko na stronach | odbiorca e-mail / Slack / Telegram w trasie głównej |
| **HTTPS i logowanie** | strony dostępne po HTTP w sieci labu | Ingress z certyfikatem TLS, logowanie przez SSO |

Trwałe dyski to naturalne rozszerzenie labu – brak historii po restarcie zobaczysz w Etapie 5
(scenariusze awarii).

## 10. Jak znaleźć inne ustawienia

```bash
# Wszystkie domyślne ustawienia chartu – zapisz i przeszukuj
helm show values prometheus-community/kube-prometheus-stack --version 92.16.1 > ~/kps-domyslne.yaml
less ~/kps-domyslne.yaml          # w less: /storageSpec  szuka, n – następne trafienie

# Co Helm wygeneruje z naszym plikiem – bez instalacji
helm template monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 \
  -n monitoring -f ~/k3s-monitoring-lab/monitoring/kube-prometheus-stack-values.yaml | less

# Po instalacji: z jakimi ustawieniami zainstalowano
helm get values monitoring -n monitoring          # tylko nasze nadpisania
helm get values monitoring -n monitoring --all    # wszystko, łącznie z domyślnymi
```

Uwaga: `helm get values` pokazuje ustawienia **po** podstawieniu luk – czyli także hasło Grafany.
Nie wklejaj tego wyniku w publiczne miejsca.

### Co powstanie w klastrze – wynik z labu (chart 92.16.1)

```
$ helm show values prometheus-community/kube-prometheus-stack --version 92.16.1 | wc -l
6340

$ helm template monitoring prometheus-community/kube-prometheus-stack --version 92.16.1 \
    -n monitoring -f monitoring/kube-prometheus-stack-values.yaml | grep '^kind:' | sort | uniq -c | sort -rn
     30 kind: PrometheusRule
     29 kind: ConfigMap
      9 kind: ServiceMonitor
      8 kind: ServiceAccount
      7 kind: Service
      5 kind: ClusterRoleBinding
      5 kind: ClusterRole
      3 kind: Secret
      3 kind: Deployment
      2 kind: Job
      1 kind: ValidatingWebhookConfiguration
      1 kind: RoleBinding
      1 kind: Role
      1 kind: Prometheus
      1 kind: Pod
      1 kind: MutatingWebhookConfiguration
      1 kind: DaemonSet
      1 kind: Alertmanager
```

6340 linii domyślnych ustawień – nasz plik zmienia z tego niecałe 80.

| Obiekty | Co to jest |
|---|---|
| 30 × `PrometheusRule` | gotowe zestawy reguł alertów (węzły, pody, Deploymenty, dyski…) – bez tych wyłączonych w rozdziale 8 |
| 29 × `ConfigMap` | głównie **dashboardy Grafany** zapisane jako JSON; sidecar Grafany wczytuje je automatycznie |
| 9 × `ServiceMonitor` | co Prometheus ma zbierać: sam siebie, Alertmanagera, Grafanę, operator, kubelety, API server, CoreDNS, node-exporter, kube-state-metrics |
| 8 × `ServiceAccount`, 5 × `ClusterRole` + `ClusterRoleBinding`, `Role` + `RoleBinding` | **tożsamości i uprawnienia (RBAC)** – np. Prometheus musi móc odczytać listę podów w całym klastrze |
| 7 × `Service` | stałe adresy: Grafana, Prometheus, Alertmanager, operator, node-exporter, kube-state-metrics… |
| 3 × `Secret` | m.in. hasło Grafany i konfiguracja Alertmanagera |
| 3 × `Deployment` | **operator**, **Grafana**, **kube-state-metrics** |
| 1 × `DaemonSet` | **node-exporter** – po jednym na każdym węźle |
| 1 × `Prometheus`, 1 × `Alertmanager` | **obiekty typów z CRD** – nie Deploymenty. Operator czyta je i sam tworzy dla nich StatefulSety |
| 2 × `Job`, `Validating…`/`MutatingWebhookConfiguration` | **webhook** operatora: sprawdza poprawność `PrometheusRule` przy `kubectl apply`; Joby tworzą dla niego certyfikat |
| 1 × `Pod` | test Helma (`helm test monitoring`) – sprawdza, czy Grafana odpowiada; przy instalacji się nie uruchamia |

Czego tu **nie widać**:
- **CRD** – leżą w osobnym katalogu `crds/` chartu i `helm template` domyślnie ich nie
  wypisuje. Jest ich 10: `helm show crds prometheus-community/kube-prometheus-stack --version 92.16.1 | grep -c '^kind: CustomResourceDefinition'`.
- **StatefulSetów Prometheusa i Alertmanagera** – tworzy je dopiero operator, już w klastrze.
  To pokazuje różnicę między Helmem (instaluje) a operatorem (zarządza na bieżąco).

## 11. Pytania, które mogą paść na rozmowie

**Dlaczego nie edytujesz domyślnego `values.yaml` chartu, tylko masz własny plik?**
Bo własny plik zawiera tylko moje zmiany – widać od razu, co odbiega od domyślnych, a przy
aktualizacji chartu nowe domyślne ustawienia przychodzą same. Plik jest w gicie, więc każda
zmiana ma historię.

**Jak przekazujesz hasła do chartu Helm?**
W labie plik values ma luki, które `envsubst` wypełnia z pliku `lab.env` poza gitem. W produkcji:
istniejący Secret wskazany w values (np. `grafana.admin.existingSecret`), Sealed Secrets,
External Secrets albo `helm secrets` z SOPS.

**Prometheus nie widzi twojego ServiceMonitora. Co sprawdzasz?**
Czy selektor Prometheusa obejmuje ten ServiceMonitor – w kube-prometheus-stack domyślnie wymagana
jest etykieta `release`. Potem czy selektor ServiceMonitora pasuje do etykiet Service'u, czy nazwa
portu się zgadza i czy namespace jest objęty. Wynik widać w *Status → Targets*.

**Czym różni się Prometheus od Alertmanagera?**
Prometheus zbiera metryki i ocenia reguły – wykrywa problem. Alertmanager przyjmuje alerty,
grupuje je, wycisza, powtarza i wysyła do ludzi.

**Czym jest dead man's switch i po co?**
Alert, który jest zawsze aktywny i regularnie trafia do zewnętrznej usługi. Gdy przestanie
przychodzić, usługa alarmuje. Wykrywa sytuację, w której zwykłe alerty nie zadziałają, bo leży sam
monitoring.

**Co to jest alert fatigue i jak mu zapobiegasz?**
Zmęczenie zbyt częstymi alertami – ludzie zaczynają je ignorować. Zapobiega się przez grupowanie
(`group_by`), rozsądne `repeat_interval`, alerty tylko na objawy, które wymagają reakcji,
i wyłączanie fałszywych alarmów – jak w labie wyłączone cele, których k3s nie ma.

**Twoje metryki przetrwają restart poda Prometheusa?**
W obecnej konfiguracji nie – nie ma trwałego wolumenu. W produkcji ustawia się `storageSpec`
z PersistentVolumeClaim, a dla długiej historii – zdalny magazyn, np. Thanos lub Mimir.
