# Etap 3 – rozwiązania ćwiczeń: Ingress, nip.io i HTTPS

Wykonanie [ćwiczeń](13-cwiczenia-ingress.md) w labie 04.11.2026 i odpowiedzi na „Sprawdź się”.
Zrób poziom sam, potem porównaj. Nazwy podów i adresy `10.42/10.43` u Ciebie będą inne.

**Kto co zrobił.** Poziomy 1–6 wykonał właściciel. Wyniki niżej Claude odczytał z klastra
i plików na masterze (tylko odczyt) tego samego dnia. Poziomy 4–6 właściciel robił według
instrukcji z innego czatu AI – certyfikat zrobił od razu z własnym CA, nie samopodpisany.

---

## Poziom 1 – aplikacja i Service

```
NAME                        READY   STATUS    IP           NODE
pod/whoami-9f77f49d-gdpwj   1/1     Running   10.42.1.35   k3s-worker-2
pod/whoami-9f77f49d-ns8rn   1/1     Running   10.42.3.50   k3s-worker-3

NAME             TYPE        CLUSTER-IP    PORT(S)   SELECTOR
service/whoami   ClusterIP   10.43.47.19   80/TCP    app=whoami
```

- `expose` kopiuje selector z etykiet podów Deploymentu (`app=whoami`, nadaną przez
  `create deployment`). Przy literówce w ręcznym selectorze Service powstaje, ale ma puste
  endpointy – ruch nie ma dokąd iść (Traefik zwraca 502/503).
- `10.43.x.x` to adres wewnętrzny klastra – istnieje tylko w regułach sieciowych węzłów
  (kube-proxy). Windows nie ma do niego trasy.

## Poziom 2 – Ingress

```
NAMESPACE     NAME      CLASS     HOSTS               ADDRESS                                                       PORTS
demo          podinfo   traefik   podinfo.lab.local   192.168.180.51,192.168.180.52,192.168.180.53,192.168.180.55   80
ingress-lab   whoami    traefik   whoami.lab.local    192.168.180.51,192.168.180.52,192.168.180.53,192.168.180.55   80
```

Odpowiedź whoami na `curl -H "Host: whoami.lab.local" http://192.168.180.52/` (z mastera):

```
Hostname: whoami-9f77f49d-gdpwj
IP: 10.42.1.35
RemoteAddr: 10.42.3.41:39732
GET / HTTP/1.1
Host: whoami.lab.local
X-Forwarded-For: 10.42.0.0
X-Forwarded-Host: whoami.lab.local
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-7c8544f77-qvhkp
```

Ten sam adres z `Host: podinfo.lab.local` – JSON `"hostname": "podinfo-…"`; bez nagłówka – `404`.

- Po nagłówku HTTP `Host` (i ścieżce). Wszystkie aplikacje mają ten sam IP i port 80 – różni je
  tylko nazwa (*name-based virtual hosting*).
- Bez `-H` curl wysyła `Host: 192.168.180.52`. Żadna reguła nie ma takiego hosta, więc Traefik
  odpowiada 404 – działa, ale „nie wie, do kogo”.
- `RemoteAddr: 10.42.3.41` to **pod Traefika** – to on łączy się z whoami. `X-Forwarded-For`
  miał podać adres klienta, ale pokazuje `10.42.0.0` (z Windowsa: `10.42.2.0`) – adres sieci podów
  węzła, przez który weszło zapytanie. Pody `svclb-traefik` (ServiceLB k3s) podmieniają adres
  źródłowy (SNAT), więc Traefik już nie widzi prawdziwego klienta. W produkcji ustawia się
  `externalTrafficPolicy: Local` albo protokół PROXY na load balancerze, żeby aplikacje (i logi)
  widziały prawdziwe IP.
- Tak – Kubernetes nie sprawdza, czy Service istnieje. `describe` pokaże w Backends
  `<error: services "…" not found>`, a Traefik zwróci błąd, dopóki Service nie powstanie.

## Poziom 3 – nazwa w przeglądarce: plik hosts

Przed dopisaniem linii (sprawdzone z Windowsa):

```
curl.exe http://whoami.lab.local/      → curl: (6) Could not resolve host
curl.exe -H "Host: whoami.lab.local" http://192.168.180.52/   → 200
```

W pliku `hosts` był tylko wpis `192.168.180.52  podinfo.lab.local`.

- Ingress mówi **Traefikowi**, co zrobić z nazwą. **Windows** musi osobno wiedzieć, jaki IP ma ta
  nazwa – z pliku `hosts` albo z DNS. `whoami.lab.local` nie ma w żadnym DNS, wymyśliliśmy ją.
- Pody `svclb-traefik` (DaemonSet) otwierają port 80 na **każdym** węźle i przekazują ruch do
  jedynego poda Traefika (na worker-3). Działa każdy z .51, .52, .53, .55.
- Rekord w firmowym DNS, zwykle jeden wildcard (`*.apps.firma.pl`) wskazujący adres load balancera
  przed klastrem – nowe aplikacje nie wymagają zmian w DNS.

## Poziom 4 – nip.io zamiast pliku hosts

```
Name                         IPAddress
whoami.192.168.180.52.nip.io 192.168.180.52
127.0.0.1.nip.io             127.0.0.1

nip.io   NS   ns-00.nip.io, ns-01.nip.io, ns-ovh.sslip.io
```

```
NAME                                      CLASS     HOSTS                         PORTS
ingress.networking.k8s.io/nginx-ingress   traefik   nginx.192.168.180.51.nip.io   80
```

- Domena `nip.io` jest delegowana do serwerów nip.io. Ich program nie ma tabeli rekordów – wycina
  z pytanej nazwy cztery liczby i odsyła je jako adres. Odpowiedź jest zapisana w pytaniu, więc
  serwer nie musi niczego wiedzieć o labie; łączy się dopiero Twoja przeglądarka.
- Nie. Obcy dostanie odpowiedź `192.168.180.51`, ale to adres prywatny – jego przeglądarka szuka
  go we **własnej** sieci. Lab jest dodatkowo za NAT routera i NAT VMware (VMnet8 widzi tylko
  Twój Windows).
- `backend.service.name: nginx` – nazwa **Service**. Ingress zawsze wskazuje Service (stały adres
  i lista podów), nigdy Deployment ani pod.
- Wady: potrzebny internet przy każdym zapytaniu DNS, długie nazwy z IP w środku, zewnętrzny
  operator widzi nazwy, o które pytasz, niektóre routery blokują odpowiedzi z adresami prywatnymi
  (DNS rebinding protection). Tylko do nauki i testów.

## Poziom 5 – własne CA i certyfikat

Pliki w `~/nipio-demo` na masterze:

```
-rw-rw-r--  ca.crt   -rw-------  ca.key   -rw-rw-r--  ca.srl
-rw-rw-r--  nginx.csr   -rw-rw-r--  nginx.ext
-rw-rw-r--  tls.crt     -rw-------  tls.key
-rw-r--r--  root root  nginx-ingress.yaml
```

```
subject=CN=nginx.192.168.180.51.nip.io
issuer=CN=Grzegorz K3s Lab Root CA
notBefore=Nov  4 11:28:26 2026 GMT
notAfter=Nov  4 11:28:26 2027 GMT
X509v3 Subject Alternative Name:
    DNS:nginx.192.168.180.51.nip.io

CA: subject=CN=Grzegorz K3s Lab Root CA, ważny do Nov  1 2036, Basic Constraints: CA:TRUE
```

`nginx-ingress.yaml` należy do `root` – powstał przez `sudo nano`. Działa, ale żeby go poprawić
jako `grzegorz`: `sudo chown grzegorz:grzegorz ~/nipio-demo/nginx-ingress.yaml`.

- `tls.crt` – certyfikat: nazwa serwera, klucz **publiczny**, daty i podpis CA; można go pokazywać.
  `tls.key` – klucz **prywatny**, tajny: kto go ma, może podszyć się pod serwer.
- `nginx.csr` (*Certificate Signing Request*) – wniosek: „ta nazwa, ten klucz publiczny, podpiszcie”.
  Podpisuje go CA kluczem `ca.key` (`openssl x509 -req … -CA … -CAkey …`); `ca.srl` pilnuje,
  żeby każdy certyfikat miał inny numer seryjny.
- Przeglądarki od lat ignorują `CN` i sprawdzają nazwę wyłącznie w `subjectAltName`. Bez SAN
  certyfikat jest odrzucany jako „nie dla tej nazwy”.
- Kto ma `ca.key`, wystawi certyfikat dla **dowolnej** nazwy, a każdy komputer ufający temu CA
  go przyjmie (np. fałszywy `bank.pl`). Uprawnienia `600`, nigdy w gicie, w firmie – w sejfie
  albo HSM.

## Poziom 6 – HTTPS na Ingressie

```
NAME        TYPE                DATA
nginx-tls   kubernetes.io/tls   2

NAME            CLASS     HOSTS                         PORTS
nginx-ingress   traefik   nginx.192.168.180.51.nip.io   80, 443
```

Testy na masterze:

```
curl --cacert ca.crt … https://nginx.192.168.180.51.nip.io/   → 200, ssl_verify_result=0
curl https://nginx.192.168.180.51.nip.io/                     → curl: (60) SSL certificate OpenSSL verify result:
                                                                 unable to get local issuer certificate (20)
curl -k … | grep title                                        → <title>Welcome to nginx!</title>
curl http://nginx.192.168.180.51.nip.io/                      → 200
```

Na Windowsie CA jest w magazynie `Cert:\CurrentUser\Root` (`CN=Grzegorz K3s Lab Root CA`):

```
curl.exe https://nginx.192.168.180.51.nip.io/
curl: (35) schannel: next InitializeSecurityContext failed: CRYPT_E_NO_REVOCATION_CHECK (0x80092012)
curl.exe --ssl-no-revoke … → 200
```

- Szyfrowanie kończy się na **Traefiku** (*TLS termination*). Traefik odszyfrowuje ruch i do poda
  nginx łączy się zwykłym HTTP na porcie 80 wewnątrz klastra.
- `curl` na masterze ufa tylko CA z systemu Ubuntu – CA labu tam nie ma, stąd `unable to get local
  issuer certificate`. `--cacert ca.crt` dodaje je na jedno polecenie. Przeglądarka na Windowsie
  korzysta z magazynu Windows, do którego CA labu zostało dodane.
- `curl.exe` w Windows używa biblioteki Schannel, która domyślnie sprawdza, czy certyfikat nie
  został **unieważniony** (lista CRL / OCSP). Nasze CA nie publikuje takiej listy, więc sprawdzenie
  się nie udaje. `--ssl-no-revoke` je pomija; przeglądarki przy braku adresu listy nie protestują.
  Opis: [problemy Etapu 3](problemy.md#curlexe-na-windowsie-crypt_e_no_revocation_check).
- Tak – reguła `rules` obsługuje oba porty (`80, 443`). Przekierowanie HTTP→HTTPS w Traefiku robi
  Middleware `redirectScheme` (CRD Traefika) dopięty adnotacją
  `traefik.ingress.kubernetes.io/router.middlewares` albo globalnie w ustawieniach Traefika.
- **cert-manager**: obiekty `Issuer`/`ClusterIssuer` i `Certificate`, a cert-manager sam wystawia
  certyfikat, zapisuje go w Secret i odnawia przed wygaśnięciem. Może korzystać z własnego CA
  (`ca` issuer) albo z Let's Encrypt. HTTP-01 wymaga, żeby serwery Let's Encrypt **z internetu**
  pobrały plik spod tej nazwy – `192.168.180.51` jest prywatny, więc się nie da. Dla sieci
  wewnętrznych zostaje DNS-01 (rekord TXT we własnej, publicznej domenie) albo firmowe CA.
