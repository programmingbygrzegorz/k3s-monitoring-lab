# Etap 2 – ćwiczenia z kubectl od podstaw

Osiem poziomów na działającym klastrze k3s: od oglądania węzłów, przez pierwszą aplikację,
samonaprawę i skalowanie, po aktualizacje, konserwację węzła i pracę z YAML. Każdy poziom
zajmuje 5–15 minut.

Wykonanie wszystkich poziomów ze zrzutami i wyjaśnieniem wyników:
[rozwiązania ćwiczeń z kubectl](06-cwiczenia-kubectl-rozwiazania.md). Zajrzyj tam po zrobieniu
poziomu, żeby porównać wynik, albo gdy utkniesz. Nazwy podów, adresy IP i porty u Ciebie będą
inne niż na zrzutach.

**Przed startem:** Etap 2 zakończony – 4 węzły `Ready`. 📸 Snapshot `k3s-cluster`.

| Poziom | Temat |
|---|---|
| [1](#poziom-1--rozejrzyj-się) | rozejrzyj się: węzły, przestrzenie nazw, pody systemowe |
| [2](#poziom-2--pierwsza-aplikacja) | pierwsza aplikacja: Deployment, ReplicaSet, pod, logi |
| [3](#poziom-3--samonaprawa) | samonaprawa: usunięty pod wraca |
| [4](#poziom-4--skalowanie) | skalowanie w górę i w dół |
| [5](#poziom-5--service-dostęp-do-aplikacji) | Service: stały adres, DNS i NodePort |
| [6](#poziom-6--aktualizacja-i-wycofanie) | aktualizacja krocząca, zły obraz i wycofanie |
| [7](#poziom-7--konserwacja-węzła) | konserwacja węzła: drain i uncordon |
| [8](#poziom-8--yaml-i-apply) | YAML, diff i apply |
| [–](#sprzątanie) | sprzątanie |

---

## Przygotowanie

🪟 Windows:

```powershell
ssh k3s-master
```

Wszystkie polecenia wpisujesz **na masterze**. `kubectl` działa bez `sudo` (k3s jest
zainstalowany z `--write-kubeconfig-mode 0644`). Ćwiczenia odbywają się w osobnej przestrzeni
nazw `cwiczenia` – na końcu usuniesz ją jednym poleceniem.

## Poziom 1 – rozejrzyj się

**Cel:** poznać klaster, zanim cokolwiek w nim zmienisz. Tylko odczyt – nic nie zepsujesz.

1. Lista węzłów z adresami: `kubectl get nodes -o wide`.
2. Tainty mastera i workera:
   ```bash
   kubectl describe node k3s-master | grep -A1 Taints
   kubectl describe node k3s-worker-1 | grep -A1 Taints
   ```
3. Przestrzenie nazw: `kubectl get namespaces`.
4. Wszystkie pody we wszystkich przestrzeniach: `kubectl get pods -A -o wide`.
5. Zużycie zasobów: `kubectl top nodes`.
6. Deploymenty i usługi systemowe: `kubectl get deployments,services -n kube-system`.

**Co powinieneś zobaczyć:** 4 węzły `Ready`, master z taintem `NoSchedule`, workery bez
taintów, pody tylko w `kube-system`.

**Sprawdź się:**
- Co oznacza taint `NoSchedule` na masterze?
- Do czego służą CoreDNS, Traefik i metrics-server?
- Dlaczego CoreDNS działa na masterze mimo taintu?
- Dlaczego `svclb-traefik-*` jest na każdym węźle?

## Poziom 2 – pierwsza aplikacja

**Cel:** uruchomić aplikację i zobaczyć, z jakich obiektów się składa.

1. Utwórz przestrzeń nazw i aplikację nginx w 3 kopiach:
   ```bash
   kubectl create namespace cwiczenia
   kubectl -n cwiczenia create deployment web --image=nginx --replicas=3
   ```
2. Obejrzyj, co powstało: `kubectl -n cwiczenia get deployment,replicaset,pods -o wide`.
3. Wybierz jeden pod i obejrzyj jego szczegóły: `kubectl -n cwiczenia describe pod <nazwa-poda>`.
   Przeczytaj sekcję `Events` na końcu.
4. Logi i polecenie wewnątrz kontenera:
   ```bash
   kubectl -n cwiczenia logs <nazwa-poda> --tail=3
   kubectl -n cwiczenia exec <nazwa-poda> -- sh -c 'hostname; nginx -v; head -2 /etc/os-release'
   ```

**Co powinieneś zobaczyć:** 1 Deployment, 1 ReplicaSet i 3 pody `Running`, rozłożone na workery.

**Sprawdź się:**
- Jaka jest rola Deploymentu, ReplicaSetu i poda?
- Kto decyduje, na którym węźle stanie pod?
- Ile trwało pobranie obrazu (sekcja `Events`) i dlaczego na innych węzłach start był szybszy?
- Jaki system jest w kontenerze? Dlaczego nie Ubuntu, skoro węzeł ma Ubuntu?

## Poziom 3 – samonaprawa

**Cel:** zobaczyć, że Kubernetes sam przywraca brakujące kopie.

1. `kubectl -n cwiczenia get pods -o wide` – zapamiętaj nazwy podów.
2. Usuń jeden pod: `kubectl -n cwiczenia delete pod <nazwa-poda>`.
3. Znowu `kubectl -n cwiczenia get pods -o wide`.
4. Zdarzenia: `kubectl -n cwiczenia get events --sort-by=.lastTimestamp | tail -6`.
5. *(dodatkowo)* W drugim terminalu `kubectl -n cwiczenia get pods -w` i usuń kolejny pod.

**Co powinieneś zobaczyć:** dalej 3 pody, jeden z nich nowy (krótki `AGE`).

**Sprawdź się:**
- Co to jest pętla uzgadniania (*reconciliation loop*)?
- Co ma wspólnego z idempotentnością w Ansible?

## Poziom 4 – skalowanie

**Cel:** zmienić liczbę kopii aplikacji.

1. Zwiększ do 6: `kubectl -n cwiczenia scale deployment web --replicas=6`, potem `get pods -o wide`.
2. Zmniejsz do 2: `kubectl -n cwiczenia scale deployment web --replicas=2`, potem `get pods -o wide`.

**Co powinieneś zobaczyć:** 6, a potem 2 pody, żaden na masterze.

**Sprawdź się:**
- Dlaczego nowe pody uruchomiły się w kilka sekund, a w poziomie 2 – w kilka minut?
- Które pody Kubernetes usuwa najpierw przy zmniejszaniu?
- Dlaczego żaden pod nie trafił na master?

## Poziom 5 – Service: dostęp do aplikacji

**Cel:** dać podom jeden stały adres i otworzyć aplikację z zewnątrz klastra.

1. Utwórz Service typu NodePort:
   ```bash
   kubectl -n cwiczenia expose deployment web --port=80 --type=NodePort
   kubectl -n cwiczenia get service web
   kubectl -n cwiczenia get endpointslices -l kubernetes.io/service-name=web
   ```
   Zapisz numer portu z kolumny `PORT(S)` (np. `80:30535/TCP` → `30535`).
2. Sprawdź DNS z wnętrza klastra tymczasowym podem:
   ```bash
   kubectl -n cwiczenia run test --restart=Never --image=busybox --command -- \
     sh -c 'nslookup web.cwiczenia.svc.cluster.local | grep -A1 ^Name; wget -qO- http://web | grep -o "<title>.*</title>"'
   kubectl -n cwiczenia logs test
   kubectl -n cwiczenia delete pod test
   ```
3. Z `monitoring` albo z Git Bash na Windowsie odpytaj **każdy** węzeł (wstaw swój port):
   ```bash
   for ip in 51 52 53 55; do printf "192.168.180.$ip:<port> -> "; curl -s http://192.168.180.$ip:<port> | grep -o "<title>.*</title>"; done
   ```
4. Otwórz `http://192.168.180.51:<port>` w przeglądarce.

**Co powinieneś zobaczyć:** „Welcome to nginx!” pod adresem każdego węzła.

**Sprawdź się:**
- Czym różnią się `CLUSTER-IP`, NodePort i adresy w `ENDPOINTS`? Z jakich sieci pochodzą?
- Jak zbudowana jest nazwa DNS usługi? Kiedy wystarczy samo `web`?
- Dlaczego odpowiada też węzeł, na którym nie ma żadnego poda `web`?

## Poziom 6 – aktualizacja i wycofanie

**Cel:** zaktualizować aplikację bez przerwy, zepsuć aktualizację i ją wycofać.

1. Aktualizacja do nginx 1.27:
   ```bash
   kubectl -n cwiczenia scale deployment web --replicas=3
   kubectl -n cwiczenia set image deployment/web nginx=nginx:1.27
   kubectl -n cwiczenia rollout status deployment/web
   kubectl -n cwiczenia rollout history deployment/web
   ```
2. Błędna aktualizacja – obraz, który nie istnieje:
   ```bash
   kubectl -n cwiczenia set image deployment/web nginx=nginx:nie-ma-takiej-wersji
   kubectl -n cwiczenia get pods
   kubectl -n cwiczenia get events --field-selector reason=Failed --sort-by=.lastTimestamp | tail -3
   ```
3. Wycofanie:
   ```bash
   kubectl -n cwiczenia rollout undo deployment/web
   kubectl -n cwiczenia get pods -o custom-columns=POD:.metadata.name,OBRAZ:.spec.containers[0].image,STAN:.status.phase,WEZEL:.spec.nodeName
   ```

**Co powinieneś zobaczyć:** po kroku 2 jeden pod w `ImagePullBackOff` i trzy stare `Running`;
po kroku 3 wszystkie pody z `nginx:1.27`.

**Sprawdź się:**
- Na czym polega aktualizacja krocząca (*rolling update*)?
- Co znaczy `ImagePullBackOff` i gdzie znaleźć przyczynę?
- Czy aplikacja przestała działać po złej aktualizacji? Dlaczego?

## Poziom 7 – konserwacja węzła

**Cel:** opróżnić węzeł przed restartem lub aktualizacją systemu.

1. ```bash
   kubectl -n cwiczenia scale deployment web --replicas=4
   kubectl -n cwiczenia get pods -o wide
   ```
   Zanotuj, które pody są na `k3s-worker-1`.
2. Opróżnij węzeł:
   ```bash
   kubectl drain k3s-worker-1 --ignore-daemonsets --delete-emptydir-data
   kubectl get nodes
   kubectl -n cwiczenia get pods -o wide
   ```
3. Przywróć węzeł: `kubectl uncordon k3s-worker-1`, potem `kubectl get nodes`.

**Co powinieneś zobaczyć:** `k3s-worker-1` w stanie `Ready,SchedulingDisabled`, jego pody
przeniesione na inne workery; po `uncordon` – znów `Ready`.

**Sprawdź się:**
- Czym różni się `cordon` od `drain`?
- Dlaczego pody DaemonSet zostają na węźle?
- Czy po `uncordon` pody wracają na `k3s-worker-1`?

## Poziom 8 – YAML i apply

**Cel:** przejść od poleceń „zrób to” do plików „ma być tak”.

1. Zobacz, jak klaster opisuje istniejący obiekt: `kubectl -n cwiczenia get deployment web -o yaml`.
   Znajdź `replicas`, `selector`, `strategy` i `template`.
2. Wygeneruj szkielet pliku i wdroż go:
   ```bash
   kubectl -n cwiczenia create deployment api --image=nginx:1.27 --replicas=1 --dry-run=client -o yaml > api.yaml
   cat api.yaml
   kubectl apply -f api.yaml
   ```
3. Zmień plik, podejrzyj różnice i wdroż dwa razy:
   ```bash
   sed -i 's/replicas: 1/replicas: 2/' api.yaml
   kubectl diff -f api.yaml
   kubectl apply -f api.yaml
   kubectl apply -f api.yaml
   ```

**Co powinieneś zobaczyć:** `created`, potem `configured`, a przy drugim `apply` – `unchanged`.

**Sprawdź się:**
- Czym różni się styl imperatywny od deklaratywnego?
- Co robi `--dry-run=client -o yaml`?
- Jaki odpowiednik `kubectl diff` i `unchanged` znasz z Ansible?

## Sprzątanie

```bash
kubectl delete namespace cwiczenia
rm -f api.yaml
kubectl get namespaces
kubectl get nodes
```

**Co powinieneś zobaczyć:** nie ma przestrzeni `cwiczenia`, 4 węzły `Ready`.

---

## Pojęcia

| Pojęcie | Znaczenie |
|---|---|
| **Node** | węzeł – maszyna w klastrze |
| **Namespace** | przestrzeń nazw – osobna „szuflada” na zasoby |
| **Pod** | najmniejsza jednostka – jeden lub kilka kontenerów z jednym adresem IP |
| **ReplicaSet** | pilnuje liczby kopii poda |
| **Deployment** | zarządza ReplicaSetami: liczba kopii, aktualizacje, historia, wycofanie |
| **DaemonSet** | jedna kopia poda na każdym węźle |
| **Service** | stały adres i DNS dla grupy podów; `ClusterIP` (w klastrze), `NodePort` (port na węzłach), `LoadBalancer` |
| **EndpointSlice** | lista adresów podów, do których Service kieruje ruch |
| **Taint / toleration** | „nie wpuszczaj podów na ten węzeł” / wyjątek od tego zakazu |
| **Label / selector** | etykiety na obiektach i wybieranie obiektów po etykietach (`app=web`) |
| **Scheduler** | wybiera węzeł dla nowego poda |
| **kubelet** | agent na każdym węźle – uruchamia pody, raportuje stan |
| **Reconciliation loop** | ciągłe wyrównywanie stanu rzeczywistego do pożądanego |

## Ściągawka

| Polecenie | Do czego |
|---|---|
| `kubectl get <typ> [-n ns \| -A] [-o wide\|yaml] [-w]` | lista obiektów |
| `kubectl describe <typ> <nazwa>` | szczegóły i **Events** – pierwsze miejsce diagnozy |
| `kubectl logs <pod> [-f] [--previous] [--tail=N]` | logi kontenera |
| `kubectl exec [-it] <pod> -- <polecenie>` | polecenie w kontenerze |
| `kubectl get events -A --sort-by=.lastTimestamp` | co się ostatnio działo |
| `kubectl create deployment / expose / scale / set image` | szybkie zmiany imperatywne |
| `kubectl rollout status / history / undo` | aktualizacje i wycofanie |
| `kubectl drain / cordon / uncordon <węzeł>` | konserwacja węzła |
| `kubectl apply -f plik.yaml` / `kubectl diff -f plik.yaml` | wdrożenie deklaratywne / podgląd różnic |
| `kubectl top nodes / pods` | zużycie CPU i pamięci |
| `kubectl explain <typ>.<pole>` | dokumentacja pól YAML |

## Co powiedzieć na rozmowie

> „Na klastrze k3s przećwiczyłem podstawowe operacje: wdrożenie aplikacji, samonaprawę
> i skalowanie, Service typu NodePort i DNS w klastrze, aktualizację kroczącą z wycofaniem
> po błędnym obrazie (ImagePullBackOff) oraz drain węzła przed konserwacją. Diagnozę zaczynam
> od `describe` i zdarzeń – np. tam widać było, że pierwszy pod startował 4 minuty, bo węzeł
> pobierał obraz. Zasoby docelowo opisuję w YAML i wdrażam przez `kubectl diff` i `apply`.”

Mów to dopiero, gdy sam przejdziesz wszystkie poziomy.
