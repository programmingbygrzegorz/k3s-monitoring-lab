# Etap 3 – ćwiczenia: Ingress, nip.io i HTTPS

Siedem poziomów do rozdziałów 13–14 [teorii](03-teoria-kubernetes-helm.md#13-jak-dostać-się-do-aplikacji-nodeport-i-ingress):
wystawiasz aplikacje przez Traefika pod nazwami, najpierw z plikiem `hosts`, potem z nip.io,
na końcu przez HTTPS z certyfikatem od własnego CA. Każdy poziom zajmuje 5–15 minut.

Wykonanie z prawdziwymi wynikami i odpowiedzi na „Sprawdź się”:
[rozwiązania](14-cwiczenia-ingress-rozwiazania.md).

**Przed startem:** klaster działa (4 węzły `Ready`), Traefik jest w `kube-system`
(`kubectl get pod -n kube-system | grep traefik`). Polecenia `kubectl` i `openssl` wpisujesz na
🐧 **k3s-master**, polecenia z 🪟 – w PowerShellu na Windowsie. Pliki w katalogu domowym twórz
**bez `sudo`**.

| Poziom | Temat |
|---|---|
| [1](#poziom-1--aplikacja-i-service) | aplikacja i Service: whoami, ClusterIP, `expose` |
| [2](#poziom-2--ingress) | Ingress: `create ingress`, `describe`, nagłówek `Host` |
| [3](#poziom-3--nazwa-w-przeglądarce-plik-hosts) | nazwa w przeglądarce: plik `hosts` |
| [4](#poziom-4--nipio-zamiast-pliku-hosts) | nip.io zamiast pliku `hosts`: nginx z Ingressem z pliku YAML |
| [5](#poziom-5--własne-ca-i-certyfikat) | własne CA i certyfikat serwera: `openssl` |
| [6](#poziom-6--https-na-ingressie) | HTTPS na Ingressie: Secret `tls`, sekcja `tls:`, zaufanie na Windowsie |
| [7](#poziom-7--sprzątanie) | sprzątanie |

---

## Poziom 1 – aplikacja i Service

**Cel:** uruchomić aplikację dostępną tylko wewnątrz klastra.

`traefik/whoami` to mały serwer WWW, który odpowiada, **który pod** odpowiedział i **jakie
nagłówki** do niego doszły – idealny do oglądania, co robi Ingress.

1. Namespace i aplikacja (2 repliki):
   ```bash
   kubectl create namespace ingress-lab
   kubectl create deployment whoami -n ingress-lab --image=traefik/whoami:v1.10.1 --replicas=2 --port=80
   kubectl get pod -n ingress-lab -o wide
   ```
2. Service – najpierw podgląd, potem naprawdę:
   ```bash
   kubectl expose deployment whoami -n ingress-lab --port=80 --dry-run=client -o yaml
   kubectl expose deployment whoami -n ingress-lab --port=80
   kubectl get svc,endpointslices -n ingress-lab
   ```
3. Test od środka (master należy do klastra, więc widzi adresy ClusterIP) – wpisz adres z kroku 2:
   ```bash
   curl http://10.43.x.x/
   ```

**Co powinieneś zobaczyć:** dwa pody `Running` (zwykle na różnych workerach); w podglądzie
`selector: app: whoami`; Service typu `ClusterIP` z adresem `10.43.x.x`; w EndpointSlice dwa adresy
`10.42.x.x`; odpowiedź z linią `Hostname: whoami-…`.

**Sprawdź się:**
- Skąd `expose` wziął selector? Co by się stało przy literówce w selectorze pisanym ręcznie?
- Dlaczego `curl http://10.43.x.x/` z Windowsa nie zadziała?

## Poziom 2 – Ingress

**Cel:** wystawić whoami pod nazwą przez Traefika.

1. Podgląd i utworzenie:
   ```bash
   kubectl create ingress whoami -n ingress-lab --class=traefik --rule="whoami.lab.local/*=whoami:80" --dry-run=client -o yaml
   kubectl create ingress whoami -n ingress-lab --class=traefik --rule="whoami.lab.local/*=whoami:80"
   kubectl get ingress -A
   kubectl describe ingress whoami -n ingress-lab
   ```
2. Test bez przeglądarki – trzy zapytania pod **ten sam** adres:
   ```bash
   curl -H "Host: whoami.lab.local" http://192.168.180.52/
   curl -H "Host: podinfo.lab.local" http://192.168.180.52/
   curl -s -o /dev/null -w "%{http_code}\n" http://192.168.180.52/
   ```
3. Powtórz pierwsze zapytanie kilka razy i patrz na `Hostname:`. Zobacz całą rozmowę HTTP:
   ```bash
   curl -v -H "Host: whoami.lab.local" http://192.168.180.52/
   ```

**Co powinieneś zobaczyć:** w `get ingress` host `whoami.lab.local`, adresy czterech węzłów, port 80;
w `describe` linia `whoami:80 (10.42.…:80,10.42.…:80)`. W kroku 2: odpowiedź whoami, JSON od
podinfo i `404`. W kroku 3 `Hostname:` zmienia się między dwoma podami; w `-v` linie `> Host: …`
(wysłane) i `< HTTP/1.1 200 OK` (odebrane).

**Sprawdź się:**
- Po czym Traefik rozpoznaje, do której aplikacji wysłać zapytanie?
- Dlaczego bez nagłówka `Host` jest 404, choć Traefik działa?
- Co pokazują `RemoteAddr` i `X-Forwarded-For` w odpowiedzi whoami? Czy w `X-Forwarded-For` jest
  adres Twojego komputera – a jeśli nie, to czyj?
- Czy można utworzyć Ingress przed Service? Co pokaże wtedy `describe`?

## Poziom 3 – nazwa w przeglądarce: plik hosts

**Cel:** otworzyć `http://whoami.lab.local` w przeglądarce na Windowsie.

1. 🪟 Sprawdź, czy Windows zna nazwę:
   ```powershell
   curl.exe http://whoami.lab.local/
   ```
2. 🪟 Notatnik **jako administrator** → `C:\Windows\System32\drivers\etc\hosts` (filtr
   „Wszystkie pliki”) → dopisz na końcu i zapisz:
   ```
   192.168.180.52  whoami.lab.local
   ```
3. 🪟 Sprawdź i otwórz w przeglądarce `http://whoami.lab.local` (z `http://`):
   ```powershell
   ping whoami.lab.local
   curl.exe http://whoami.lab.local/
   ```

**Co powinieneś zobaczyć:** w kroku 1 `curl: (6) Could not resolve host`; po kroku 2 `ping`
pokazuje `[192.168.180.52]`, a przeglądarka – stronę whoami.

**Sprawdź się:**
- Ingress już był – dlaczego przeglądarka go nie znalazła? Kto musi znać nazwę, a kto regułę?
- Dlaczego .52, skoro Traefik działa na jednym węźle? Czy .55 też zadziała?
- Jak rozwiązuje się to w firmie, gdzie aplikacji są dziesiątki?

## Poziom 4 – nip.io zamiast pliku hosts

**Cel:** nazwa, która działa bez żadnego wpisu na Windowsie, i Ingress zapisany w pliku.

1. 🪟 Zobacz, jak nip.io zamienia nazwę na adres:
   ```powershell
   nslookup nginx.192.168.180.51.nip.io
   nslookup cokolwiek.10.20.30.40.nip.io
   ```
2. Aplikacja i Service (tym razem nginx):
   ```bash
   kubectl create namespace nipio-demo
   kubectl create deployment nginx --image=nginx:alpine -n nipio-demo
   kubectl expose deployment nginx --port=80 --target-port=80 --type=ClusterIP -n nipio-demo
   kubectl get pod,svc -n nipio-demo
   ```
3. Ingress z pliku – katalog ćwiczenia i plik:
   ```bash
   mkdir -p ~/nipio-demo && cd ~/nipio-demo
   cat > nginx-ingress.yaml <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: nginx-ingress
     namespace: nipio-demo
   spec:
     ingressClassName: traefik
     rules:
       - host: nginx.192.168.180.51.nip.io
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: nginx
                   port:
                     number: 80
   EOF
   kubectl apply -f nginx-ingress.yaml
   kubectl get ingress -n nipio-demo
   ```
4. 🪟 Otwórz `http://nginx.192.168.180.51.nip.io` – bez dopisywania czegokolwiek do `hosts`.

**Co powinieneś zobaczyć:** `nslookup` zwraca `192.168.180.51` i `10.20.30.40`; pod `nginx-…`
`Running`; Ingress `nginx-ingress` z hostem `nginx.192.168.180.51.nip.io`; w przeglądarce
„Welcome to nginx!”.

**Sprawdź się:**
- Jak działa nip.io? Dlaczego serwer nip.io nie musi znać Twojego labu?
- Czy ktoś z internetu wejdzie na tę stronę, wpisując ten sam adres? Dlaczego?
- Trzy nazwy w tym poziomie: `nginx` (Deployment), `nginx` (Service), `nginx-ingress` (Ingress) –
  która z nich jest w `backend.service.name` i dlaczego właśnie ta?
- Jakie są wady nip.io i dlaczego nie używa się go w firmie?

## Poziom 5 – własne CA i certyfikat

**Cel:** wystawić certyfikat dla `nginx.192.168.180.51.nip.io`, podpisany przez własne CA labu.

Certyfikat **samopodpisany** (`openssl req -x509` dla samej nazwy) też zadziała, ale przeglądarka
zawsze będzie ostrzegać. Z **własnym CA** wystarczy raz zaufać CA na Windowsie – każdy kolejny
certyfikat z labu będzie przyjęty bez ostrzeżeń. Ten sam schemat jest przy rejestrze obrazów
([Etap 4 – własny obraz](../etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md)).

1. Urząd certyfikacji (klucz 4096 bitów, ważny 10 lat):
   ```bash
   cd ~/nipio-demo
   openssl genrsa -out ca.key 4096
   chmod 600 ca.key
   openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=Grzegorz K3s Lab Root CA" -out ca.crt
   ```
2. Klucz i wniosek o certyfikat serwera:
   ```bash
   openssl genrsa -out tls.key 2048
   chmod 600 tls.key
   openssl req -new -key tls.key -subj "/CN=nginx.192.168.180.51.nip.io" -out nginx.csr
   ```
3. Rozszerzenia – najważniejsze `subjectAltName`, bo przeglądarki sprawdzają nazwę **tylko** w nim:
   ```bash
   cat > nginx.ext <<'EOF'
   basicConstraints=critical,CA:FALSE
   keyUsage=critical,digitalSignature,keyEncipherment
   extendedKeyUsage=serverAuth
   subjectAltName=DNS:nginx.192.168.180.51.nip.io
   EOF
   ```
4. CA podpisuje certyfikat (1 rok):
   ```bash
   openssl x509 -req -in nginx.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -sha256 -extfile nginx.ext -out tls.crt
   ```
5. Sprawdź wynik:
   ```bash
   openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName
   openssl verify -CAfile ca.crt tls.crt
   ls -l
   ```

**Co powinieneś zobaczyć:** `subject=CN=nginx.192.168.180.51.nip.io`,
`issuer=CN=Grzegorz K3s Lab Root CA`, ważność rok, w SAN `DNS:nginx.192.168.180.51.nip.io`;
`tls.crt: OK`; `ca.key` i `tls.key` z uprawnieniami `-rw-------`; plik `ca.srl` (numer seryjny).

**Sprawdź się:**
- Co jest w `tls.crt`, a co w `tls.key`? Które z nich jest tajne?
- Do czego służy `nginx.csr`? Kto go „podpisuje”?
- Po co `subjectAltName`, skoro nazwa jest już w `CN`?
- Dlaczego `ca.key` jest najcenniejszym plikiem w tym katalogu?

## Poziom 6 – HTTPS na Ingressie

**Cel:** `https://nginx.192.168.180.51.nip.io` z kłódką w przeglądarce.

1. Certyfikat i klucz do klastra jako Secret typu `tls`:
   ```bash
   cd ~/nipio-demo
   kubectl create secret tls nginx-tls --cert=tls.crt --key=tls.key -n nipio-demo
   kubectl get secret nginx-tls -n nipio-demo
   ```
2. Dopisz do `nginx-ingress.yaml` sekcję `tls` (pod `ingressClassName`, na tym samym poziomie co
   `rules`) i zastosuj:
   ```yaml
     tls:
       - hosts:
           - nginx.192.168.180.51.nip.io
         secretName: nginx-tls
   ```
   ```bash
   kubectl apply -f nginx-ingress.yaml
   kubectl get ingress -n nipio-demo
   ```
3. Test na masterze – z zaufaniem do CA labu, bez niego i bez sprawdzania:
   ```bash
   curl --cacert ca.crt -s -o /dev/null -w "%{http_code}\n" https://nginx.192.168.180.51.nip.io/
   curl https://nginx.192.168.180.51.nip.io/
   curl -k -s https://nginx.192.168.180.51.nip.io/ | grep title
   ```
4. 🪟 Zaufaj CA labu na Windowsie (tylko Twoje konto, bez uprawnień administratora):
   ```powershell
   scp k3s-master:~/nipio-demo/ca.crt $env:USERPROFILE\Downloads\lab-ca.crt
   Import-Certificate -FilePath $env:USERPROFILE\Downloads\lab-ca.crt -CertStoreLocation Cert:\CurrentUser\Root
   ```
   Windows zapyta w okienku, czy zainstalować certyfikat główny – sprawdź nazwę i potwierdź.
5. 🪟 Otwórz `https://nginx.192.168.180.51.nip.io` (przeglądarkę zamknij i otwórz ponownie). Test
   z terminala:
   ```powershell
   curl.exe https://nginx.192.168.180.51.nip.io/
   curl.exe --ssl-no-revoke -s -o NUL -w "%{http_code}`n" https://nginx.192.168.180.51.nip.io/
   ```

**Co powinieneś zobaczyć:** Secret typu `kubernetes.io/tls` z `DATA 2`; w `get ingress` porty
`80, 443`. W kroku 3: `200`, potem błąd `curl: (60) SSL certificate problem`, potem
`<title>Welcome to nginx!</title>`. W przeglądarce kłódka bez ostrzeżenia. W kroku 5 pierwszy
`curl.exe` kończy się `CRYPT_E_NO_REVOCATION_CHECK`, drugi daje `200`.

**Sprawdź się:**
- Gdzie kończy się szyfrowanie? Czym Traefik rozmawia z podem nginx?
- Dlaczego `curl` bez `--cacert` odrzuca certyfikat, a przeglądarka po kroku 4 go przyjmuje?
- Skąd błąd `CRYPT_E_NO_REVOCATION_CHECK` tylko w `curl.exe` na Windowsie?
- Czy `http://` dalej działa? Jak wymusić przekierowanie na HTTPS?
- Co zamiast ręcznego `openssl` robi się w pracy? Dlaczego Let's Encrypt nie wystawi certyfikatu
  dla tej nazwy metodą HTTP-01?

## Poziom 7 – sprzątanie

```bash
kubectl delete namespace ingress-lab nipio-demo
kubectl get ingress -A
```

Plik `hosts` na Windowsie: usuń linię `whoami.lab.local` (albo zostaw – bez Ingressa dostaniesz 404).
Katalog `~/nipio-demo` z CA możesz zostawić na kolejne certyfikaty – `ca.key` nigdy do gita.
Zaufanie do CA usuniesz w 🪟 `certmgr.msc` → Zaufane główne urzędy certyfikacji → Certyfikaty.

**Co powinieneś zobaczyć:** zostaje tylko Ingress `podinfo` w `demo`.

## Ściągawka

| Polecenie | Co robi |
|---|---|
| `kubectl expose deployment NAZWA --port=80` | Service ClusterIP do Deploymentu |
| `kubectl create ingress NAZWA --class=traefik --rule="HOST/*=SERVICE:PORT"` | Ingress jednym poleceniem |
| `kubectl describe ingress NAZWA -n NS` | reguły i adresy podów za Service |
| `curl -H "Host: NAZWA" http://IP/` | test Ingressa bez DNS |
| `openssl x509 -req -in X.csr -CA ca.crt -CAkey ca.key -CAcreateserial -extfile X.ext -out X.crt` | CA podpisuje certyfikat |
| `kubectl create secret tls NAZWA --cert=tls.crt --key=tls.key` | certyfikat do klastra |
| `curl --cacert ca.crt https://…` | HTTPS z zaufaniem do własnego CA |

Wszystkie polecenia labu: [ściągawka poleceń](../sciagawka-polecen.md).
