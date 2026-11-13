# Różne przykłady – ćwiczenia z kursu przeniesione do labu

Przykłady z kursu „Kubernetes od podstaw” (repozytorium kursu sklonowane na masterze w `~/kubernetes-course`),
przerobione tak, żeby działały w labie k3s: osobny namespace `kurs-kubernetes`, adresy `192.168.180.51`
zamiast `127.0.0.1`, obrazy z rejestru labu. Każdy przykład ma tu opis kroków, prawdziwe wyniki i sprzątanie.

| Folder | Pliki | Temat |
|---|---|---|
| [ingress/](ingress/) | `deployments.yaml`, `ingress.yaml` | dwie aplikacje za jednym Ingressem (Traefik), nip.io, HTTPS z mkcert |
| [stateful_set/](stateful_set/) | `app-stateful-set-solution.yaml` | headless Service a zwykły ClusterIP – co zwraca DNS |

Zasady:

- **Każdy przykład w namespace `kurs-kubernetes`** – sprzątanie to jedno polecenie (`kubectl delete namespace kurs-kubernetes`).
- **Pliki dodaje się w repozytorium na Windowsie, a na masterze tylko `git pull`.** Na masterze nie ma ustawionego
  e-maila i tokenu do GitHuba, więc `git push` stamtąd nie działa (12.11.2026: `git commit` odmówił bez `user.email`).
- **Klucze i certyfikaty nigdy w repozytorium** – leżą w `~/certs-lab` (master) i `C:\Users\User\certs-lab` (Windows).

---

## 1. Ingress: podinfo i httpbin pod jednym adresem (11–12.11.2026)

**Cel:** wejść z przeglądarki na Windowsie do dwóch aplikacji w klastrze, po nazwie, najpierw przez HTTP, potem HTTPS.

```
🪟 przeglądarka: https://podinfo.192.168.180.51.nip.io
   │ 1. DNS nip.io: nazwa → 192.168.180.51 (adres ze środka nazwy)
   ▼
 Traefik (Ingress Controller k3s, porty 80/443 na każdym węźle)
   │ 2. reguła z ingress.yaml: host podinfo… → Service podinfo:8080, certyfikat z Secretu ingress-tls
   ▼
 Service podinfo (ClusterIP 10.43.169.184:8080) ──► pody podinfo :9898 (worker-1, worker-3)
```

### Krok 1 – plik z kursu do repozytorium i własny namespace

Plik `~/kubernetes-course/zaawansowane_koncepcje_ingress/deployments.yaml` (2 Deploymenty + 2 Service) nie miał
`namespace:`, więc trafiłby do `default`. Dopisany został obiekt Namespace i `namespace: kurs-kubernetes` w każdym obiekcie.

```bash
mkdir -p ~/k3s-monitoring-lab/rozneprzyklady/ingress
cp ~/kubernetes-course/zaawansowane_koncepcje_ingress/deployments.yaml ~/k3s-monitoring-lab/rozneprzyklady/ingress/
sed -i "s/kurs-ingress/kurs-kubernetes/g" deployments.yaml     # zmiana nazwy namespace’u w całym pliku
kubectl apply --dry-run=client -f deployments.yaml             # próba na sucho – nic nie tworzy
kubectl apply -f deployments.yaml
kubectl -n kurs-kubernetes get pods -o wide
```

Wynik `--dry-run`:

```
namespace/kurs-kubernetes created (dry run)
service/podinfo created (dry run)
deployment.apps/podinfo created (dry run)
service/httpbin created (dry run)
deployment.apps/httpbin created (dry run)
```

**Pułapka:** pierwsza próba `kubectl delete namespace podinfo` → `Error from server (NotFound)`. W wyniku
`kubectl get deployment -A` pierwsza kolumna to **namespace** (`demo`), druga – nazwa Deploymentu (`podinfo`).

### Krok 2 – test bez Ingressa: ClusterIP z mastera

Service typu ClusterIP działa tylko wewnątrz klastra, ale master jest jego częścią:

```bash
kubectl -n kurs-kubernetes get svc
curl http://10.43.169.184:8080          # podinfo
curl http://10.43.156.116:8080/get      # httpbin
```

```json
{
  "hostname": "podinfo-754bfdb6fd-rhj5m",
  "version": "6.4.0",
  ...
}
```

Kolejne wywołania zwracają raz jeden, raz drugi pod – Service rozkłada ruch.

### Krok 3 – tymczasowy NodePort (test z Windowsa)

```bash
kubectl -n kurs-kubernetes expose deployment podinfo --type=NodePort --name=podinfo-np --port=9898
kubectl -n kurs-kubernetes expose deployment httpbin --type=NodePort --name=httpbin-np --port=80
kubectl -n kurs-kubernetes get svc
```

```
NAME         TYPE        CLUSTER-IP      PORT(S)
httpbin      ClusterIP   10.43.156.116   8080/TCP
httpbin-np   NodePort    10.43.171.53    80:31739/TCP
podinfo      ClusterIP   10.43.169.184   8080/TCP
podinfo-np   NodePort    10.43.139.80    9898:31898/TCP
```

Z przeglądarki: `http://192.168.180.51:31898` i `http://192.168.180.51:31739`. `--port` to port kontenera
(`containerPort` z pliku: podinfo 9898, httpbin 80). `expose` tworzy **jeden** obiekt – Service typu NodePort,
który ma w sobie także ClusterIP. Po teście (to był drift – obiekty spoza plików):

```bash
kubectl -n kurs-kubernetes delete svc podinfo-np httpbin-np
```

### Krok 4 – Ingress (HTTP)

```bash
kubectl get ingressclass                         # traefik (default) – kontroler wbudowany w k3s
kubectl -n kube-system get svc traefik           # LoadBalancer, EXTERNAL-IP = wszystkie 4 węzły, 80 i 443
kubectl apply -f ingress.yaml
kubectl -n kurs-kubernetes get ingress
```

```
NAME          CLASS     HOSTS                                                         ADDRESS                                                       PORTS
k8s-ingress   traefik   podinfo.192.168.180.51.nip.io,httpbin.192.168.180.51.nip.io   192.168.180.51,192.168.180.52,192.168.180.53,192.168.180.55   80
```

### Krok 5 – jak sprawdzaliśmy, czy Ingress działa (i dlaczego nie działał)

Pierwsza próba w przeglądarce nie działała. Diagnoza po kolei – od DNS do reguły:

| Sprawdzenie | Polecenie | Wynik | Wniosek |
|---|---|---|---|
| czy nazwa zamienia się na IP | 🪟 `nslookup podinfo.192.168.180.51.nip.io` | `Address: 192.168.180.51` | DNS działa |
| czy Traefik odpowiada | 🪟 `curl -s -o /dev/null -w "%{http_code}" http://podinfo.192.168.180.51.nip.io/` | `404` | Traefik jest, ale nie zna nazwy |
| czy reguła istnieje | 🐧 `kubectl -n kurs-kubernetes get ingress` | `No resources found` | **Ingressa nie było** |
| czy plik jest | 🐧 `ls` | tylko `deployments.yaml` | `ingress.yaml` nie powstał (heredoc nie został wklejony w całości) |

Po utworzeniu pliku i `kubectl apply` oba adresy zwróciły **200**.

**Ingress routuje po nazwie (nagłówek Host), nie po IP:**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://podinfo.192.168.180.52.nip.io/                                   # 404
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: podinfo.192.168.180.51.nip.io" http://192.168.180.52/         # 200
```

Wejście przez węzeł `.52` działa, ale nazwa `…52.nip.io` nie pasuje do żadnej reguły, więc Traefik zwraca 404.

### Krok 6 – HTTPS z certyfikatem mkcert

mkcert tworzy własne CA i dodaje je do zaufanych **w Windowsie** (tam działa przeglądarka), a potem wystawia
certyfikat dla podanych nazw.

```powershell
# 🪟 PowerShell
winget install FiloSottile.mkcert
mkcert -install                    # „The local CA is now installed in the system trust store!”
cd C:\Users\User\certs-lab
mkcert --key-file key.pem --cert-file cert.pem podinfo.192.168.180.51.nip.io httpbin.192.168.180.51.nip.io
scp cert.pem key.pem k3s-master:certs-lab/
```

`mkcert -install` zgłosił też `ERROR: failed to execute "keytool -importcert"` – to próba dodania CA do Javy (JDK 21)
bez uprawnień administratora; przeglądarce niepotrzebne. Firefox ma własną listę zaufanych CA i pokaże ostrzeżenie.

Sprawdzenie na masterze, że pliki dotarły bez zmian i certyfikat pasuje do klucza:

```bash
chmod 600 ~/certs-lab/key.pem
sha256sum ~/certs-lab/*.pem                                               # te same sumy co na Windowsie
openssl x509 -in ~/certs-lab/cert.pem -noout -pubkey | sha256sum          # klucz publiczny z certyfikatu
openssl pkey -in ~/certs-lab/key.pem -pubout | sha256sum                  # klucz publiczny z klucza prywatnego
openssl x509 -in ~/certs-lab/cert.pem -noout -enddate -ext subjectAltName # dla jakich nazw i do kiedy
```

Oba skróty klucza publicznego takie same (`915223…`) = para pasuje. Certyfikat ważny do 12.02.2029 dla obu nazw.

Secret w klastrze i sekcja `tls` w Ingressie:

```bash
kubectl -n kurs-kubernetes create secret tls ingress-tls --cert ~/certs-lab/cert.pem --key ~/certs-lab/key.pem
kubectl -n kurs-kubernetes describe secret ingress-tls      # tls.crt: 1594 bytes, tls.key: 1704 bytes – bez wartości
kubectl -n kurs-kubernetes get secret ingress-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate
```

```yaml
spec:
  tls:
    - hosts:
        - podinfo.192.168.180.51.nip.io
        - httpbin.192.168.180.51.nip.io
      secretName: ingress-tls      # bez tej linii Traefik pokaże swój domyślny certyfikat i ostrzeżenie
```

Sprawdzenie (13.11.2026):

```bash
# 🪟 – curl na Windowsie sprawdza unieważnienie certyfikatu, a CA z mkcert go nie publikuje
curl -s --ssl-no-revoke -o /dev/null -w "%{http_code}\n" https://podinfo.192.168.180.51.nip.io/   # 200
# 🐧 – który certyfikat podaje Traefik
echo | openssl s_client -connect 192.168.180.51:443 -servername podinfo.192.168.180.51.nip.io 2>/dev/null | openssl x509 -noout -issuer -subject
```

```
issuer=O=mkcert development CA, …
subject=O=mkcert development certificate, …
```

Bez `--ssl-no-revoke` curl na Windowsie kończy się błędem 35 (nie może sprawdzić listy unieważnień) –
przeglądarka tego nie robi i pokazuje kłódkę.

**Lekcja z CI:** po dopisaniu `tls` w pliku zostały dwie spacje na końcu linii `secretName: ingress-tls`.
yamllint w GitHub Actions oznaczył przebieg na czerwono (`trailing spaces`).

---

## 2. Headless Service a zwykły ClusterIP (13.11.2026)

**Cel:** zobaczyć, czym różni się Service z `clusterIP: None` od zwykłego. Plik
[stateful_set/app-stateful-set-solution.yaml](stateful_set/app-stateful-set-solution.yaml): dwa Service
(`app-headless` i `app`) z tym samym selektorem, Deployment z 3 podami i pod `toolbox` do testów DNS.

Zmiany względem kursu: namespace `kurs-kubernetes` i obraz `192.168.180.54:5000/app:1.0.0` – w kursie `app:1.0.0`
budowany jest w minikube; w k3s sama nazwa `app:1.0.0` oznaczałaby Docker Hub i skończyła się ImagePullBackOff.

```bash
kubectl apply -f rozneprzyklady/stateful_set/app-stateful-set-solution.yaml
kubectl -n kurs-kubernetes get svc
```

```
NAME           TYPE        CLUSTER-IP      PORT(S)
app            ClusterIP   10.43.175.3     8080/TCP
app-headless   ClusterIP   None            8080/TCP
```

Co zwraca DNS – z poda `toolbox`:

```bash
kubectl -n kurs-kubernetes exec toolbox -- getent hosts app.kurs-kubernetes.svc.cluster.local
kubectl -n kurs-kubernetes exec toolbox -- getent hosts app-headless.kurs-kubernetes.svc.cluster.local
```

```
10.43.175.3     app.kurs-kubernetes.svc.cluster.local              ← zwykły: 1 adres Service

10.42.3.99      app-headless.kurs-kubernetes.svc.cluster.local     ← headless: adresy wszystkich podów
10.42.2.133     app-headless.kurs-kubernetes.svc.cluster.local
10.42.1.87      app-headless.kurs-kubernetes.svc.cluster.local
```

Oba Service mają te same punkty końcowe – różni się tylko to, co dostaje klient:

```bash
kubectl -n kurs-kubernetes get endpointslices
```

```
NAME                 ADDRESSTYPE   PORTS   ENDPOINTS
app-4dv4z            IPv4          5000    10.42.3.99,10.42.1.87,10.42.2.133
app-headless-wzb8w   IPv4          5000    10.42.3.99,10.42.1.87,10.42.2.133
```

| | Zwykły Service (`app`) | Headless (`app-headless`) |
|---|---|---|
| własny IP | `10.43.175.3`, stały | brak (`None`) |
| DNS zwraca | 1 adres Service | adresy wszystkich podów |
| kto wybiera pod | Service (kube-proxy) | klient |
| zastosowanie | zwykłe aplikacje | bazy i klastry, gdzie każdy pod musi być osiągalny osobno (ze StatefulSetem: `app-0.app-headless…`) |

**Adresy podów nie są stałe** – po odtworzeniu poda CoreDNS podaje nowy. Stała jest nazwa.

**Pułapki z `dig`:**

- `dig` z obrazu `pnowy/toolbox:1.0.0` **wypisuje odpowiedź**, a dopiero przy zamykaniu kończy się błędem
  `isc_app_ctxshutdown(): fatal error: kill: Permission denied`, exit 139. Wynik jest poprawny – błąd na końcu
  można pominąć (albo użyć `getent hosts`). Przykład z labu:
  `app.kurs-kubernetes.svc.cluster.local. 5 IN A 10.43.21.3`.
- `dig getent NAZWA` to pomyłka: `dig` traktuje słowo `getent` jako nazwę do sprawdzenia (`status: NXDOMAIN`).
  Używa się **albo** `dig +short NAZWA`, **albo** `getent hosts NAZWA`.
- Nazwa Service w DNS to `NAZWA.NAMESPACE.svc.cluster.local` – np. `app-headless.kurs-kubernetes.svc.cluster.local`,
  a nie `app.headless.cluster.local`.
- Ostrzeżenie `.local is reserved for Multicast DNS` jest tylko informacją – w Kubernetesie `cluster.local` to norma.

---

## Sprzątanie (13.11.2026)

```bash
kubectl delete namespace kurs-kubernetes
kubectl get ns kurs-kubernetes          # Error from server (NotFound) = usunięty
```

Usuwa wszystko naraz: Deploymenty, pody, Service, Ingress i Secret `ingress-tls`. Wynik z labu:

```
namespace "kurs-kubernetes" deleted
Error from server (NotFound): namespaces "kurs-kubernetes" not found
```

Pierwsze zapytanie do `http://podinfo.192.168.180.51.nip.io/` zaraz po usunięciu zwróciło **503**, kolejne już **404**.
Przez chwilę Traefik miał jeszcze regułę, ale pody za nią już zniknęły (503 = jest dokąd iść, ale nikt nie odpowiada);
chwilę później zniknęła sama reguła (404 = nie ma reguły dla tej nazwy). Pliki `cert.pem` i `key.pem` zostają w `~/certs-lab` – przy ponownym wdrożeniu wystarczy
`kubectl create secret tls …` z kroku 6. Certyfikat CA mkcert zostaje w zaufanych Windowsa
(usunięcie: `mkcert -uninstall`).

## Pytania rekrutacyjne

- **Dlaczego Ingress zwraca 404, choć DNS i Traefik działają?** – Żadna reguła nie pasuje do nazwy z nagłówka Host
  albo Ingressa w ogóle nie ma. Sprawdzam `kubectl get ingress -n …` i porównuję `host` z adresem.
- **Czym różni się 404 od 503 z Ingress Controllera?** – 404: żadna reguła nie pasuje do nazwy. 503: reguła jest,
  ale Service nie ma gotowych podów (puste endpointy, zły selektor, nieprzechodząca readinessProbe).
- **Gdzie kończy się TLS w tym układzie?** – Na Ingress Controllerze (Traefik). Do podów ruch idzie po HTTP wewnątrz klastra.
- **Jak sprawdzisz, że certyfikat pasuje do klucza?** – Porównuję skrót klucza publicznego z `openssl x509 -pubkey` i `openssl pkey -pubout`.
- **Czym różni się headless Service od zwykłego?** – Nie ma własnego IP; DNS zwraca adresy podów, a klient sam wybiera pod.
- **Po co osobny namespace na ćwiczenia?** – Izolacja i sprzątanie jednym poleceniem; nazwy (np. `podinfo`) mogą się powtarzać w różnych namespace’ach.
