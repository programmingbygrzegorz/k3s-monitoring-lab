# Etap 4 – monitoring poza klastrem – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## docker push: http: server gave HTTP response to HTTPS client

- **Objaw:** rejestr `registry:3` uruchomiony bez certyfikatu, `docker push 192.168.180.54:5000/hello-lab:1.0`
  kończy się błędem
  `failed to do request: Head "https://192.168.180.54:5000/v2/...": http: server gave HTTP response to HTTPS client`.
- **Przyczyna:** Docker (i containerd w k3s) łączy się z rejestrem **zawsze po HTTPS**.
  Wyjątkiem jest tylko `localhost`. Rejestr odpowiedział zwykłym HTTP.
- **Diagnoza:** w komunikacie są słowa `https://` (czego chciał klient) i `HTTP response` (co dostał).
  `curl http://192.168.180.54:5000/v2/_catalog` odpowiada, a `curl https://...` nie.
- **Rozwiązanie:** rejestr z TLS: certyfikat podpisany przez własne CA labu, a `ca.crt` w
  `/etc/docker/certs.d/192.168.180.54:5000/` ([opis](02-wlasny-obraz.md#dlaczego-https-i-własny-urząd-certyfikacji-ca)).
  Wpis `insecure-registries` w `/etc/docker/daemon.json` też by „naprawił” błąd, ale wyłącza
  szyfrowanie i sprawdzanie rejestru. W labie ta zmiana została zablokowana jako osłabienie
  zabezpieczeń, i słusznie.
- **Wniosek:** gdy narzędzie odmawia połączenia bez szyfrowania, rozwiązaniem jest szyfrowanie,
  a nie wyłączenie sprawdzania.

## x509: certificate signed by unknown authority

- **Objaw:** rejestr ma już certyfikat, a mimo to `docker push` (i potem pody w k3s:
  `ErrImagePull` → `ImagePullBackOff`) kończy się błędem
  `tls: failed to verify certificate: x509: certificate signed by unknown authority`.
- **Przyczyna:** certyfikat rejestru podpisało CA labu, a Docker i węzły k3s jeszcze tego CA nie znają.
  To jak pieczątka urzędu, o którym nikt nie słyszał.
- **Diagnoza:** `curl https://192.168.180.54:5000/v2/_catalog` zwraca kod `60` (błąd certyfikatu),
  a `curl --cacert ~/rejestr-certs/ca.crt https://...` działa. To dowód, że brakuje tylko zaufania
  do CA. W k3s: `kubectl -n hello-lab get events`, gdzie w komunikacie `Failed to pull image` widać `x509`.
- **Rozwiązanie:** Docker: `ca.crt` w `/etc/docker/certs.d/192.168.180.54:5000/ca.crt`, bez restartu.
  k3s: `ca.crt` jako `/etc/rancher/k3s/lab-ca.crt` i [`registries.yaml`](../../apps/hello-lab/k3s-registries.yaml)
  na **każdym** węźle, potem restart `k3s` / `k3s-agent`. Pody, które czekały w `ImagePullBackOff`,
  przy następnej próbie same pobrały obraz.
- **Wniosek:** `unknown authority` oznacza „nie ufam temu, kto podpisał”, a nie „certyfikat jest zły”.
  Rozwiązanie to dodanie zaufania w jednym, wąskim miejscu, tylko dla tego rejestru.

## Ansible copy: Destination directory /etc/rancher/k3s does not exist

- **Objaw:** `ansible k3s_cluster -b -m copy -a "... dest=/etc/rancher/k3s/lab-ca.crt"`: na masterze
  `CHANGED`, a na trzech workerach `FAILED! ... Destination directory /etc/rancher/k3s does not exist`.
- **Przyczyna:** k3s na masterze (serwer) trzyma konfigurację w `/etc/rancher/k3s`, a agent na
  workerach w `/etc/rancher/node`. Katalog `k3s` na workerze powstaje dopiero wtedy, gdy ktoś go
  utworzy. Moduł `copy` nie tworzy brakujących katalogów.
- **Diagnoza:** `ansible k3s_agents -b -m command -a "ls /etc/rancher"` zwraca tylko `node`.
- **Rozwiązanie:** najpierw `ansible k3s_cluster -b -m file -a "path=/etc/rancher/k3s state=directory mode=0755"`,
  potem `copy`. Restart agentów z `-f 1` (po jednym), żeby nie zatrzymać wszystkich naraz.
- **Wniosek:** master i workery k3s nie są identyczne, nawet jeśli działa na nich ten sam program.
  Przy rozsyłaniu plików Ansible najpierw upewnij się, że katalog istnieje (`file state=directory`).

## Obraz o 200 MB większy – brak .dockerignore

- **Objaw:** po zmianie `COPY app.py .` na `COPY . .` obraz urósł ze 178 MB do 388 MB, a
  `docker build` pokazał `transferring context: 209.77MB`.
- **Przyczyna:** w katalogu leżał plik `kopia-zapasowa.tar` (200 MB). `COPY . .` kopiuje **wszystko**
  z kontekstu budowania, więc plik trafił do obrazu (`ls -la /app` w kontenerze).
- **Diagnoza:** `docker images`, czyli porównanie rozmiarów; `docker history <obraz>`, gdzie widać,
  która warstwa jest duża; `docker run --rm <obraz> ls -la /app`.
- **Rozwiązanie:** plik [`.dockerignore`](../../apps/hello-lab/.dockerignore) z `*.tar`, `.git`,
  `.env` itp. Kontekst spadł do 130 B, a obraz wrócił do 178 MB.
- **Wniosek:** bez `.dockerignore` do obrazu trafia wszystko z katalogu, także sekrety (`.env`)
  i historia gita. Każdy, kto pobierze obraz, może je z niego wyciągnąć.
