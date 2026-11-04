# Etap 1 – ćwiczenia: 40 typowych problemów z nginx, PostgreSQL i MariaDB

Drugi zestaw ćwiczeń administratora. Instalujesz serwer WWW **nginx** z kilkoma stronami
(wirtualne hosty), aplikację za reverse proxy, HTTPS oraz dwie bazy danych: **PostgreSQL**
i **MariaDB**. Potem psujesz je na 40 sposobów, które najczęściej zdarzają się w pracy, i naprawiasz.

Wykonanie wszystkich problemów ze zrzutami i odpowiedziami:
[rozwiązania](05-cwiczenia-nginx-bazy-rozwiazania.md). Numery procesów, daty i czasy u Ciebie
będą inne.

**Gdzie:** maszyna 🐧 **`monitoring`** (`192.168.180.54`). Ćwiczenia zakładają, że masz już za sobą
[codzienną pracę administratora](02-cwiczenia-admin-linux.md) – z niej jest wolumen `/data`
(poziom 4). Jeśli wróciłeś do snapshotu, zrób najpierw poziom 4 tamtych ćwiczeń.

**Przed startem:** snapshot maszyny `monitoring` (np. `przed-nginx-bazy`) – po ćwiczeniach wracasz
do niego.

**Jak pracować z każdym problemem:**
1. **Zepsuj** – wykonaj polecenia z punktu „Zepsuj” (symulują błąd kolegi, aktualizacji albo
   klienta).
2. **Objaw** – zobacz, co widzi użytkownik.
3. **Znajdź i napraw** – samodzielnie. Podpowiedzi są pod spodem; zajrzyj do nich dopiero, gdy
   utkniesz na 10 minut.
4. Porównaj z [rozwiązaniem](05-cwiczenia-nginx-bazy-rozwiazania.md).

**Hasła w ćwiczeniach** (`Lab-app-123`, `Lab-blog-123`, `Lab-haslo-123`) są testowe, tylko dla
tego labu. W prawdziwej pracy hasło w poleceniu (`-p'haslo'`, `PGPASSWORD=`) zostaje w historii
powłoki – lepiej plik `~/.pgpass` / `~/.my.cnf` z prawami `600`.

| Poziom | Temat | Problemy |
|---|---|---|
| [0](#poziom-0--instalacja-nginx) | instalacja nginx | 1 blokada `apt`, 2 strona niewidoczna z Windowsa |
| [1](#poziom-1--usługa-nginx) | usługa nginx | 3 literówka w konfiguracji, 4 port zajęty, 5 po restarcie maszyny strona nie działa |
| [2](#poziom-2--wirtualne-hosty) | wirtualne hosty | 6 IPv6 i `localhost`, 7 vhost nieaktywny, 8 zła nazwa w `server_name`, 9 404, 10 403 bez `index`, 11 403 uprawnienia |
| [3](#poziom-3--logi-nginx) | logi nginx | 12 kody odpowiedzi, 13 kto nas skanuje, 14 blokada adresu |
| [4](#poziom-4--reverse-proxy) | reverse proxy | 15 502, 16 504, 17 413, 18 adres klienta |
| [5](#poziom-5--https-i-hasła) | HTTPS i hasła | 19 certyfikat, 20 HTTPS i przekierowanie, 21 zła nazwa w certyfikacie, 22 wygasanie, 23 hasło na panel |
| [6](#poziom-6--postgresql-dostęp) | PostgreSQL – dostęp | 24 `role does not exist`, 25 `Peer authentication failed`, 26 `Connection refused` z sieci, 27 `no pg_hba.conf entry` |
| [7](#poziom-7--postgresql-utrzymanie) | PostgreSQL – utrzymanie | 28 usunięta tabela, 29 za dużo połączeń, 30 zapytanie wisi, 31 baza nie wstaje, 32 wolne zapytanie, 33 rozmiar, 34 przeniesienie na inny dysk |
| [8](#poziom-8--mariadb) | MariaDB | 35 `Access denied` dla root, 36 dostęp z sieci, 37 `DELETE` bez `WHERE`, 38 zapomniane hasło |
| [9](#poziom-9--automatyzacja) | automatyzacja | 39 nocne kopie z rotacją, 40 skrypt „czy wszystko działa” |
| [10](#poziom-10--sprzątanie) | sprzątanie | |

**Testy bez DNS:** nazwy `sklep.lab`, `blog.lab`, `app.lab` nie istnieją w żadnym DNS. Z maszyny
testujesz je przez nagłówek `Host` (`curl -H 'Host: sklep.lab' localhost`) albo `curl --resolve
sklep.lab:443:127.0.0.1 https://sklep.lab`. Z Windowsa – wpis w pliku `hosts` (patrz
[ćwiczenia z Ingress](../etap-3-monitoring/13-cwiczenia-ingress.md)).

---

## Poziom 0 – instalacja nginx

### Problem 1 – `Could not get lock /var/lib/dpkg/lock-frontend`

**Sytuacja:** chcesz zainstalować pakiet, a `apt` odmawia. Na świeżym serwerze to zwykle
automatyczne aktualizacje (`unattended-upgrades`), które właśnie działają.

**Zepsuj** – udawana aktualizacja trzyma blokadę 90 sekund:
```bash
sudo systemd-run --unit=niby-aktualizacja python3 -c "import fcntl,time;f=open('/var/lib/dpkg/lock-frontend','w');fcntl.lockf(f,fcntl.LOCK_EX);time.sleep(90)"
sudo apt-get install -y nginx apache2-utils
```

**Znajdź i napraw:** kto trzyma blokadę? Czy można ją „zdjąć”, usuwając plik?

<details><summary>Podpowiedź</summary>

`sudo lsof /var/lib/dpkg/lock-frontend`, `sudo fuser …`, `ps -o pid,etime,cmd -p PID`. Poczekaj,
aż proces się skończy (albo `sudo systemctl stop niby-aktualizacja`), i powtórz instalację.
</details>

**Sprawdź się:** dlaczego **nie wolno** usuwać plików `lock` przy działającym `apt`? Po co
`apache2-utils` (podpowiedź: problem 23)?

### Problem 2 – strona działa na serwerze, z Windowsa nie

**Objaw:** na maszynie `curl -s localhost | grep title` pokazuje `Welcome to nginx!`. 🪟 Na Windowsie:
```powershell
curl.exe -m 5 http://192.168.180.54/
Test-NetConnection 192.168.180.54 -Port 80
```

**Znajdź i napraw.** Otwórz port tylko dla sieci labu, od razu też 443.

<details><summary>Podpowiedź</summary>

`sudo ufw status`, zablokowane pakiety: `sudo grep 'DPT=80 ' /var/log/ufw.log | tail`.
`sudo ufw allow from 192.168.180.0/24 to any port 80,443 proto tcp`.
</details>

**Sprawdź się:** jak odróżnić „firewall blokuje” od „nic nie słucha na porcie” po samym
zachowaniu klienta (czas, komunikat)?

## Poziom 1 – usługa nginx

### Problem 3 – po zmianie konfiguracji `reload` się nie udaje

**Zepsuj** – brakujący średnik (najpierw kopia pliku):
```bash
sudo cp /etc/nginx/sites-available/default /root/default.bak
sudo sed -i 's#root /var/www/html;#root /var/www/html#' /etc/nginx/sites-available/default
sudo systemctl reload nginx
```

**Objaw:** `Job for nginx.service failed`. Czy strona nadal działa (`curl -s -o /dev/null -w
'%{http_code}\n' localhost`)?

**Znajdź i napraw.** Dlaczego błąd wskazuje inną linię niż ta, w której brakuje średnika?

<details><summary>Podpowiedź</summary>

`sudo nginx -t` – test konfiguracji przed każdym `reload`. Numer linii w komunikacie to miejsce,
w którym nginx **zauważył** błąd.
</details>

**Sprawdź się:** co by się stało, gdybyś zamiast `reload` zrobił `restart`? Czym różnią się te
polecenia?

### Problem 4 – nginx nie startuje

**Zepsuj** – „stara aplikacja” zajmuje port 80:
```bash
sudo systemctl stop nginx
sudo systemd-run --unit=stara-aplikacja python3 -m http.server 80 --directory /tmp
sudo systemctl start nginx
```

**Znajdź i napraw.** Kto zajmuje port?

<details><summary>Podpowiedź</summary>

`journalctl -u nginx --since '-5min' | grep -E 'in use|bind'`, `sudo ss -tlnp 'sport = :80'`.
Zatrzymaj intruza (`sudo systemctl stop stara-aplikacja`), uruchom nginx.
</details>

**Sprawdź się:** co znaczy `98: Address already in use`? Jak sprawdzić, jaki pakiet dostarczył
program, który zajął port (`dpkg -S $(which …)`)?

### Problem 5 – po restarcie maszyny strona nie działa

**Zepsuj:**
```bash
sudo systemctl disable nginx
systemctl is-active nginx; systemctl is-enabled nginx
sudo reboot
```

**Objaw:** po ponownym zalogowaniu `curl localhost` – `Connection refused`.

**Znajdź i napraw.** Przy okazji sprawdź, czy `/data` zamontował się sam po restarcie.

<details><summary>Podpowiedź</summary>

`systemctl is-enabled nginx`, `sudo systemctl enable --now nginx`. Lista wyłączonych usług:
`systemctl list-unit-files --state=disabled --type=service`.
</details>

**Sprawdź się:** po każdej zmianie, która ma przetrwać restart, co sprawdzasz? (usługi `enabled`,
`fstab`, reguły firewalla, `sysctl`…)

## Poziom 2 – wirtualne hosty

**Przygotowanie** – dwie strony, na razie włączona tylko `sklep.lab`:
```bash
for s in sklep blog; do
  sudo mkdir -p /var/www/$s
  echo "<h1>Strona $s.lab</h1>" | sudo tee /var/www/$s/index.html
done
sudo tee /etc/nginx/sites-available/sklep.lab >/dev/null <<'EOF'
server {
    listen 80;
    server_name sklep.lab www.sklep.lab;
    root /var/www/sklep;
    index index.html;

    access_log /var/log/nginx/sklep.access.log;
    error_log  /var/log/nginx/sklep.error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
sed "s/sklep/blog/g" /etc/nginx/sites-available/sklep.lab | sudo tee /etc/nginx/sites-available/blog.lab >/dev/null
sudo ln -s /etc/nginx/sites-available/sklep.lab /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### Problem 6 – `sklep.lab` pokazuje stronę powitalną nginx

**Objaw:**
```bash
curl -s -H 'Host: sklep.lab' localhost | grep -o '<title>.*</title>'
curl -s -H 'Host: sklep.lab' http://127.0.0.1/
```
Pierwsze polecenie daje `Welcome to nginx!`, drugie – naszą stronę. Konfiguracja jest poprawna
(`nginx -t` nie protestuje). Dlaczego?

<details><summary>Podpowiedź</summary>

`curl -v … localhost 2>&1 | grep Trying` – na jaki adres łączy się `curl`? Na jakich adresach
słuchają serwery: `sudo nginx -T | grep listen`. Dopisz do obu plików `listen [::]:80;`.
</details>

### Problem 7 – `blog.lab`: plik konfiguracyjny jest, strony nie ma

**Objaw:** `curl -s -H 'Host: blog.lab' localhost` – strona powitalna. Plik
`/etc/nginx/sites-available/blog.lab` istnieje.

<details><summary>Podpowiedź</summary>

Porównaj `ls /etc/nginx/sites-available/` z `ls -l /etc/nginx/sites-enabled/`. nginx czyta tylko
`sites-enabled`. Co naprawdę wczytał: `sudo nginx -T | grep server_name`.
</details>

### Problem 8 – literówka w `server_name`

**Zepsuj:**
```bash
sudo sed -i 's/server_name sklep.lab/server_name skelp.lab/' /etc/nginx/sites-available/sklep.lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -H 'Host: sklep.lab' localhost | grep -o '<title>.*</title>'
curl -s -H 'Host: cokolwiek.pl' localhost | grep -o '<title>.*</title>'
```

**Znajdź i napraw.** Która strona odpowiada na nazwy, których nie zna żaden `server_name`?

<details><summary>Podpowiedź</summary>

`sudo nginx -T | grep -nE 'server_name|default_server'`.
</details>

### Problem 9 – 404 Not Found

**Zepsuj:** `sudo sed -i 's#root /var/www/blog;#root /var/www/blog/public;#' /etc/nginx/sites-available/blog.lab`
i `reload`.

**Objaw:** `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: blog.lab' localhost/` – `404`.
Zajrzyj do `blog.error.log` – czy coś tam jest? A w `blog.access.log`?

### Problem 10 – 403 Forbidden, choć pliki są

**Zepsuj:** `sudo mv /var/www/sklep/index.html /var/www/sklep/start.html`

**Objaw:** `403` dla `sklep.lab`. Przeczytaj `sklep.error.log`.

### Problem 11 – 403 Forbidden przez uprawnienia

**Zepsuj:** `sudo chmod 600 /var/www/blog/index.html`, potem napraw i zepsuj inaczej:
`sudo chmod 644 /var/www/blog/index.html; sudo chmod 750 /var/www/blog`.

**Znajdź i napraw.** Jako jaki użytkownik nginx czyta pliki? Które prawa są potrzebne na plik,
a które na katalogi po drodze?

<details><summary>Podpowiedź</summary>

`ps -o user,cmd -C nginx`, `namei -l /var/www/blog/index.html`, komunikat w `blog.error.log`
(`Permission denied`).
</details>

**Sprawdź się (poziom 2):** co znaczą `404`, `403`, `401`, `500`, `502`, `503`, `504`? Który błąd
jest „po stronie klienta”, a który „po stronie serwera”?

## Poziom 3 – logi nginx

**Przygotowanie** – ruch z kilku maszyn:
🪟 Windows (normalny klient):
```powershell
1..25 | ForEach-Object { curl.exe -s -o NUL -H "Host: sklep.lab" http://192.168.180.54/ }
foreach ($p in "/koszyk","/produkty") { curl.exe -s -o NUL -H "Host: sklep.lab" "http://192.168.180.54$p" }
```
🐧 `k3s-master` (udaje skaner szukający dziur):
```bash
for p in /.env /wp-login.php /phpmyadmin/ /admin /.git/config /wp-admin/ /backup.zip /config.php /xmlrpc.php /shell.php; do
  for i in 1 2 3 4; do curl -s -o /dev/null -A "Mozilla/5.0 zgrab/0.x" -H "Host: sklep.lab" http://192.168.180.54$p; done
done
```
🐧 `k3s-worker-1`: `for i in $(seq 12); do curl -s -o /dev/null -H "Host: sklep.lab" http://192.168.180.54/; done`

Format linii w `access.log` (pola rozdzielone spacjami, `awk` liczy od `$1`):
```
192.168.180.52 - - [04/Nov/2026:17:20:57 +0100] "GET / HTTP/1.1" 200 26 "-" "curl/8.18.0"
$1 adres       $2 $3 $4 data i godzina          $6 $7 $8         $9  $10 $11 $12…
```

### Problem 12 – ile błędów zwraca strona?

Policz w `/var/log/nginx/sklep.access.log`: ile było odpowiedzi każdego kodu (200, 404…), ile
wszystkich błędów (kod ≥ 400) i ile zapytań na minutę.

### Problem 13 – kto nas skanuje?

Ustal: które adresy wysyłają najwięcej zapytań, jakich plików najczęściej szukano bez skutku
(404), kto szukał `wp-login`, `.env`, `.git`, i jakimi programami (`User-Agent`, pole w
cudzysłowie – `awk -F'"' '{print $6}'`).

### Problem 14 – zablokuj skaner

Zablokuj adres skanera tylko dla `sklep.lab` (dyrektywa `deny` w bloku `server`). Sprawdź z
`k3s-master` (ma dostać `403`) i z `k3s-worker-1` (`200`). Co pojawi się w `sklep.error.log`?

**Sprawdź się (poziom 3):** czym blokada w nginx różni się od blokady w `ufw`? Co zrobiłby
`fail2ban` z takim logiem?

## Poziom 4 – reverse proxy

**Przygotowanie** – mała aplikacja w Pythonie na `127.0.0.1:8080` jako usługa systemd i strona
`app.lab`, która przekazuje do niej ruch:
```bash
sudo tee /usr/local/bin/aplikacja.py >/dev/null <<'EOF'
#!/usr/bin/env python3
# Mała aplikacja do ćwiczeń: / – odpowiedź, /wolno – 10 s czekania, POST – przyjmuje plik
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

class H(BaseHTTPRequestHandler):
    def odpowiedz(self, tekst, kod=200):
        dane = tekst.encode()
        self.send_response(kod)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(dane)))
        self.end_headers()
        self.wfile.write(dane)

    def do_GET(self):
        if self.path == "/wolno":
            time.sleep(10)
        self.odpowiedz(f"aplikacja OK, sciezka {self.path}\n"
                       f"polaczenie od: {self.client_address[0]}\n"
                       f"X-Real-IP: {self.headers.get('X-Real-IP')}\n"
                       f"X-Forwarded-For: {self.headers.get('X-Forwarded-For')}\n")

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self.rfile.read(n)
        self.odpowiedz(f"przyjeto {n} bajtow\n")

ThreadingHTTPServer(("127.0.0.1", 8080), H).serve_forever()
EOF
sudo chmod +x /usr/local/bin/aplikacja.py

sudo tee /etc/systemd/system/aplikacja.service >/dev/null <<'EOF'
[Unit]
Description=Aplikacja za nginx - cwiczenie reverse proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/aplikacja.py
User=www-data
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/nginx/sites-available/app.lab >/dev/null <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name app.lab;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_read_timeout 5s;   # na ćwiczenie krótko, domyślnie 60s
    }
}
EOF
sudo ln -s /etc/nginx/sites-available/app.lab /etc/nginx/sites-enabled/
sudo systemctl daemon-reload && sudo systemctl enable --now aplikacja
sudo nginx -t && sudo systemctl reload nginx
curl -s -H 'Host: app.lab' localhost/
```

### Problem 15 – 502 Bad Gateway

**Zepsuj:** `sudo systemctl stop aplikacja`. **Objaw:** `502`. Znajdź przyczynę w
`/var/log/nginx/error.log` i sprawdź, czy coś słucha na porcie 8080.

### Problem 16 – 504 Gateway Timeout

**Objaw:** `time curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: app.lab' localhost/wolno` –
`504` po 5 sekundach. Jak sprawdzić, czy wina leży po stronie nginx, czy aplikacji (zapytanie
**prosto** do `localhost:8080`)? Jak to naprawić na dwa sposoby?

### Problem 17 – 413 Request Entity Too Large

**Zepsuj / objaw:**
```bash
head -c 3M /dev/urandom > /tmp/raport.pdf
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: app.lab' --data-binary @/tmp/raport.pdf localhost/
```
Znajdź komunikat w `error.log` i pozwól na pliki do 10 MB tylko dla `app.lab`.

### Problem 18 – aplikacja widzi adres nginx zamiast klienta

**Objaw:** 🐧 z `k3s-worker-1`: `curl -s -H 'Host: app.lab' http://192.168.180.54/` – aplikacja
pisze `X-Real-IP: None`. Programiści pytają, dlaczego wszyscy klienci mają adres `127.0.0.1`.

<details><summary>Podpowiedź</summary>

`cat /etc/nginx/proxy_params` – gotowy zestaw nagłówków w Ubuntu. Dopisz `include proxy_params;`
w `location /`.
</details>

**Sprawdź się (poziom 4):** po co w ogóle reverse proxy przed aplikacją? Czym różni się `502` od
`504`? Dlaczego aplikacja słucha na `127.0.0.1`, a nie na `0.0.0.0`?

## Poziom 5 – HTTPS i hasła

### Problem 19 – certyfikat dla `sklep.lab`

Wystaw certyfikat z **CA labu** (`~/rejestr-certs/ca.crt` i `ca.key` z [Etapu 4](../etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md);
jeśli ich nie masz – własne CA jak w [ćwiczeniach z Ingress](../etap-3-monitoring/13-cwiczenia-ingress.md)):
```bash
mkdir -p ~/www-certs && cd ~/www-certs
openssl req -new -newkey rsa:2048 -nodes -keyout sklep.key -out sklep.csr -subj '/CN=sklep.lab'
printf 'subjectAltName=DNS:sklep.lab,DNS:www.sklep.lab\n' > sklep.ext
openssl x509 -req -in sklep.csr -CA ~/rejestr-certs/ca.crt -CAkey ~/rejestr-certs/ca.key \
  -CAcreateserial -days 365 -extfile sklep.ext -out sklep.crt
openssl x509 -in sklep.crt -noout -subject -issuer -enddate -ext subjectAltName
sudo install -d -m 700 /etc/nginx/ssl
sudo install -m 600 sklep.key /etc/nginx/ssl/ && sudo install -m 644 sklep.crt /etc/nginx/ssl/
```

### Problem 20 – HTTPS i przekierowanie z HTTP

Przebuduj `/etc/nginx/sites-available/sklep.lab`: blok na porcie 80 tylko przekierowuje
(`return 301 https://$host$request_uri;`), drugi blok słucha na `443 ssl` z
`ssl_certificate` i `ssl_certificate_key`. Sprawdź:
```bash
curl -sI http://sklep.lab --resolve sklep.lab:80:127.0.0.1 | grep -E 'HTTP|Location'
curl -sS https://sklep.lab --resolve sklep.lab:443:127.0.0.1
curl -s https://sklep.lab --resolve sklep.lab:443:127.0.0.1 --cacert ~/rejestr-certs/ca.crt
```
Dlaczego drugie polecenie kończy się błędem `(60)`, a trzecie działa?

### Problem 21 – `no alternative certificate subject name matches`

**Objaw:** `curl -sS https://blog.lab --resolve blog.lab:443:127.0.0.1 --cacert ~/rejestr-certs/ca.crt`.
`blog.lab` nie ma bloku na 443 – kto mu odpowiedział i jakim certyfikatem? Sprawdź
`openssl s_client -connect 127.0.0.1:443 -servername blog.lab`.

### Problem 22 – kiedy wygasa certyfikat?

Wystaw drugi certyfikat (`promocja.sklep.lab`) ważny tylko 3 dni (`-days 3`). Sprawdź daty
obu certyfikatów, użyj `openssl x509 -checkend` z progiem 30 dni i napisz pętlę, która wypisze
„ile dni zostało” dla każdego pliku. Jak sprawdzić datę certyfikatu, który **serwer naprawdę
wysyła** (a nie pliku na dysku)?

### Problem 23 – hasło na panel `/admin/`

Dodaj w `blog.lab` blok `location /admin/` z `auth_basic` i plikiem `/etc/nginx/.htpasswd`
(`htpasswd` z pakietu `apache2-utils`). Sprawdź kody bez hasła, ze złym i z dobrym hasłem. Jakie
prawa powinien mieć plik z hasłami?

**Sprawdź się (poziom 5):** co to SNI? Dlaczego `basic auth` bez HTTPS jest niebezpieczne? Co
by zrobił `certbot` (Let's Encrypt) i dlaczego w labie z nazwami `.lab` nie zadziała?

## Poziom 6 – PostgreSQL: dostęp

```bash
sudo apt-get install -y postgresql
pg_lsclusters
```

### Problem 24 – `role "grzegorz" does not exist`

**Objaw:** wpisujesz `psql`. Jak się zalogować jako administrator bazy? Jakie role istnieją
(`\du`)? Gdzie są pliki konfiguracyjne?

### Problem 25 – `Peer authentication failed`

Utwórz użytkownika i bazę aplikacji:
```bash
sudo -u postgres psql -c "CREATE USER app WITH PASSWORD 'Lab-app-123';"
sudo -u postgres psql -c 'CREATE DATABASE sklep OWNER app;'
psql -U app sklep
```
**Znajdź i napraw** – bez zmieniania konfiguracji. Przeczytaj `pg_hba.conf` bez komentarzy.

<details><summary>Podpowiedź</summary>

Połączenie przez gniazdo (bez `-h`) to `local … peer` – nazwa konta Linux musi być równa nazwie
roli. Przez TCP (`-h localhost`) obowiązuje `host … scram-sha-256` – hasło.
</details>

### Problem 26 – z sieci: `Connection refused`

**Objaw:** `PGPASSWORD='Lab-app-123' psql -h 192.168.180.54 -U app sklep -c 'select 1;'`.
Ustaw nasłuch na wszystkich adresach (`listen_addresses` w pliku `conf.d/siec.conf`), sprawdź
z `k3s-worker-1`, czy port jest osiągalny:
`timeout 3 bash -c '</dev/tcp/192.168.180.54/5432' && echo otwarty || echo zamkniety`.
Ile przeszkód trzeba usunąć?

### Problem 27 – `no pg_hba.conf entry for host`

Pozwól użytkownikowi `app` łączyć się z bazą `sklep` z sieci `192.168.180.0/24` (hasłem). Czy
zmiana działa od razu po zapisaniu pliku? Jak zobaczyć reguły, które PostgreSQL **naprawdę**
wczytał (`pg_hba_file_rules`)?

**Sprawdź się (poziom 6):** które zmiany w PostgreSQL wymagają `restart`, a które wystarczy
`reload`? Co znaczą `peer`, `scram-sha-256`, `trust`? Dlaczego `trust` to zły pomysł?

## Poziom 7 – PostgreSQL: utrzymanie

**Przygotowanie** – trochę danych:
```bash
export PGPASSWORD='Lab-app-123'
psql -h localhost -U app sklep <<'EOF'
CREATE TABLE produkty (id serial PRIMARY KEY, nazwa text, cena numeric(8,2));
INSERT INTO produkty (nazwa, cena) VALUES ('kubek', 29.99), ('koszulka', 79.00), ('naklejka', 4.50);
CREATE TABLE zamowienia (id serial PRIMARY KEY, produkt_id int, ilosc int, data timestamp default now());
INSERT INTO zamowienia (produkt_id, ilosc) SELECT (random()*2+1)::int, (random()*5+1)::int FROM generate_series(1,200000);
EOF
```

### Problem 28 – ktoś usunął tabelę

Zrób kopię `pg_dump -Fc` do `/data/kopie-baz/`, potem `DROP TABLE produkty;` i odtwórz **tylko tę
tabelę** z kopii (`pg_restore -l`, `pg_restore -t`).

### Problem 29 – `too many clients` / `remaining connection slots are reserved`

**Zepsuj:**
```bash
echo 'max_connections = 8' | sudo tee /etc/postgresql/18/main/conf.d/polaczenia.conf
sudo systemctl restart postgresql
for i in $(seq 6); do PGPASSWORD='Lab-app-123' psql -h localhost -U app sklep -c 'select pg_sleep(90);' & done
PGPASSWORD='Lab-app-123' psql -h localhost -U app sklep -c 'select 1;'
```
Kto zajmuje połączenia (`pg_stat_activity`)? Zwolnij je bez restartu bazy. Na koniec usuń
`polaczenia.conf` i zrestartuj.

### Problem 30 – zapytanie wisi

**Zepsuj** – sesja A zaczyna transakcję i „idzie na kawę”, sesja B chce zmienić ten sam wiersz.
Dwa terminale:
```bash
# terminal 1 (sesja A) – w psql:
psql -h localhost -U app sklep
BEGIN;
UPDATE produkty SET cena = 31.00 WHERE id = 1;
# … i nic więcej, nie kończ transakcji

# terminal 2 (sesja B):
PGPASSWORD='Lab-app-123' psql -h localhost -U app sklep -c 'UPDATE produkty SET cena = 35.00 WHERE id = 1;'
```
**Znajdź i napraw** z trzeciego terminala: kto kogo blokuje (`pg_blocking_pids`), od kiedy trwa
transakcja, zakończ winowajcę (`pg_terminate_backend`).

### Problem 31 – PostgreSQL nie wstaje

**Zepsuj:**
```bash
echo 'shared_buffers = 256MBB' | sudo tee /etc/postgresql/18/main/conf.d/pamiec.conf
sudo systemctl restart postgresql; systemctl is-active postgresql
```
`active` – a baza nie działa. Dlaczego? (`pg_lsclusters`, `systemctl is-active postgresql@18-main`,
log w `/var/log/postgresql/`.) Napraw na `256MB`.

### Problem 32 – wolne zapytanie

```bash
export PGPASSWORD='Lab-app-123'
psql -h localhost -U app sklep -c 'ALTER TABLE zamowienia ADD COLUMN klient int;' \
  -c 'UPDATE zamowienia SET klient = (random()*50000)::int;' -c 'VACUUM ANALYZE zamowienia;'
psql -h localhost -U app sklep -c 'EXPLAIN ANALYZE SELECT * FROM zamowienia WHERE klient = 1234;'
```
Co znaczy `Seq Scan` i `Rows Removed by Filter`? Dodaj indeks i porównaj `Execution Time`.

### Problem 33 – baza rośnie

Sprawdź rozmiar każdej bazy (`pg_database_size`), każdej tabeli z indeksami
(`pg_total_relation_size`), katalogu z danymi i katalogu `pg_wal`. Ile miejsca zostało na `/`,
a ile na `/data`?

### Problem 34 – przeniesienie bazy na dysk `/data`

Przenieś dane klastra z `/var/lib/postgresql/18/main` na `/data/postgresql/18/main`: zatrzymaj
klaster, skopiuj z zachowaniem praw (`rsync -a`), zmień `data_directory` w `postgresql.conf`,
dopisz do usługi zależność od montowania `/data` (`RequiresMountsFor=/data` w pliku
`/etc/systemd/system/postgresql@18-main.service.d/data.conf`), stary katalog zmień nazwę (nie
usuwaj!), uruchom i sprawdź dane.

**Sprawdź się (poziom 7):** czym `pg_dump` różni się od kopii plików katalogu z danymi? Po co
`RequiresMountsFor`? Co się stanie z bazą, gdy dysk `/data` się nie zamontuje?

## Poziom 8 – MariaDB

```bash
sudo apt-get install -y mariadb-server
```

### Problem 35 – `Access denied for user 'root'@'localhost'`

**Objaw:** `mariadb -u root` i `mariadb -u root -p'cokolwiek'`. Jak zalogować się jako root?
Jak root jest uwierzytelniany (`show grants for root@localhost`)?

### Problem 36 – dostęp z sieci

```bash
sudo mariadb -e "CREATE DATABASE blog; CREATE USER 'blog'@'localhost' IDENTIFIED BY 'Lab-blog-123'; GRANT ALL ON blog.* TO 'blog'@'localhost';"
mariadb -h 127.0.0.1 -u blog -p'Lab-blog-123' blog -e 'select current_user();'
mariadb -h 192.168.180.54 -u blog -p'Lab-blog-123' blog -e 'select current_user();'
```
Drugie połączenie się nie udaje. Usuń **dwie** przeszkody (`bind-address`, konto
`'blog'@'host'`). Pamiętaj: z innych maszyn potrzebny byłby jeszcze port 3306 w `ufw`.

### Problem 37 – `DELETE` bez `WHERE`

```bash
mariadb -h 127.0.0.1 -u blog -p'Lab-blog-123' blog -e "CREATE TABLE wpisy (id int auto_increment primary key, tytul varchar(100), data date); INSERT INTO wpisy (tytul, data) VALUES ('Pierwszy wpis', '2026-10-01'), ('Kubernetes od zera', '2026-10-20'), ('Monitoring w labie', '2026-11-02');"
```
Zrób kopię `mariadb-dump --single-transaction` do `/data/kopie-baz/mariadb/`, wykonaj
`DELETE FROM wpisy;` i odtwórz dane.

### Problem 38 – aplikacja zapomniała hasła

**Objaw:** `mariadb -h 127.0.0.1 -u blog -p'stare-haslo' blog` – `Access denied`. Gdzie widać
nieudane logowania? Ustaw nowe hasło (`Lab-blog-456`) dla **obu** kont `blog`.

**Sprawdź się (poziom 8):** dlaczego w MariaDB `'blog'@'localhost'` i `'blog'@'192.168.180.%'`
to dwa różne konta? Czym `localhost` różni się od `127.0.0.1` dla klienta `mariadb`? Co robi
`--single-transaction`?

## Poziom 9 – automatyzacja

### Problem 39 – nocne kopie baz i usuwanie starych

Napisz `/usr/local/bin/kopia-baz.sh`: kopia `sklep` (`pg_dump`) i `blog` (`mariadb-dump`),
spakowane `gzip`, do `/data/kopie-baz/nocne/`, a pliki starsze niż 7 dni usuwane (`find -mtime
+7 -delete`). Zadanie w `/etc/cron.d/kopia-baz` o 2:30. Do testu usuwania podrzuć stare pliki:
```bash
for d in 12 9 8 6 2; do for b in sklep blog; do
  sudo touch -d "$d days ago" /data/kopie-baz/nocne/$b-$(date -d "$d days ago" +%F)-0200.sql.gz
done; done
```
Które pliki usunie `-mtime +7` – te sprzed 8 dni też?

### Problem 40 – „czy wszystko działa?” jednym poleceniem

Napisz `/usr/local/bin/sprawdz-uslugi.sh`, który sprawdzi: usługi (`nginx`, `postgresql@18-main`,
`mariadb`, `aplikacja`), kody HTTP trzech stron, `pg_isready` i `mariadb-admin ping`, ile dni
zostało certyfikatowi, zajętość `/` i `/data`, czy jest świeża kopia baz. Ma kończyć się kodem `1`,
gdy cokolwiek jest nie tak (żeby mógł go używać cron albo monitoring). Przetestuj, zatrzymując
`mariadb` i `aplikacja`.

## Poziom 10 – sprzątanie

Najprościej: 🪟 VMware → *Snapshot Manager* → snapshot sprzed ćwiczeń → *Go To*.

Ręcznie (kolejność odwrotna):
```bash
sudo rm /etc/cron.d/kopia-baz /usr/local/bin/kopia-baz.sh /usr/local/bin/sprawdz-uslugi.sh
sudo apt-get purge -y mariadb-server 'postgresql*' && sudo apt-get autoremove -y
sudo rm -rf /etc/systemd/system/postgresql@18-main.service.d /data/postgresql /data/kopie-baz /var/lib/postgresql /var/lib/mysql
sudo systemctl disable --now aplikacja && sudo rm /etc/systemd/system/aplikacja.service /usr/local/bin/aplikacja.py
sudo apt-get purge -y nginx nginx-common apache2-utils && sudo rm -rf /etc/nginx /var/www/sklep /var/www/blog
sudo ufw delete allow from 192.168.180.0/24 to any port 80,443 proto tcp
sudo ufw delete allow from 192.168.180.0/24 to any port 5432 proto tcp
sudo systemctl daemon-reload
```

## Ściągawka

| Sytuacja | Polecenia |
|---|---|
| konfiguracja nginx | `nginx -t`, `nginx -T`, `systemctl reload nginx`, `sites-available` → `ln -s` → `sites-enabled` |
| błędy WWW | `curl -s -o /dev/null -w '%{http_code}'`, `-H 'Host: …'`, `--resolve`, `error.log`, `access.log`, `namei -l` |
| logi | `awk '{print $9}' access.log \| sort \| uniq -c \| sort -nr` |
| proxy | `proxy_pass`, `include proxy_params`, `proxy_read_timeout`, `client_max_body_size` |
| certyfikaty | `openssl x509 -noout -enddate -checkend`, `openssl s_client -servername` |
| PostgreSQL | `sudo -u postgres psql`, `pg_lsclusters`, `pg_hba.conf`, `pg_stat_activity`, `pg_dump`/`pg_restore`, `EXPLAIN ANALYZE` |
| MariaDB | `sudo mariadb`, `'user'@'host'`, `bind-address`, `mariadb-dump`, `ALTER USER` |
| automatyzacja | `/etc/cron.d/`, `find -mtime +7 -delete`, skrypt z kodem wyjścia |

Wszystkie polecenia labu: [ściągawka poleceń](../sciagawka-polecen.md).
