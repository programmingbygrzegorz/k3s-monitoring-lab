# Etap 1 – przygotowanie systemu – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## `PasswordAuthentication no` nie działa

- **Objaw:** po wyłączeniu logowania hasłem SSH dalej je przyjmuje.
- **Przyczyna:** pliki w `/etc/ssh/sshd_config.d/` są czytane **alfabetycznie**, a dla większości
  opcji **wygrywa pierwsza** wartość. Ubuntu ma `50-cloud-init.conf` z `PasswordAuthentication yes`,
  więc nasz `99-lab.conf` przegrywał.
- **Diagnoza:** `sudo sshd -T | grep passwordauthentication` – efektywna konfiguracja.
  Test: `ssh -o PubkeyAuthentication=no host` ma dać `Permission denied (publickey)`.
- **Rozwiązanie:** plik `01-lab.conf` – czytany przed `50-cloud-init.conf`.
- **Wniosek:** przy plikach typu *drop-in* kolejność ma znaczenie, a reguła „pierwsza czy ostatnia
  wygrywa” różni się między programami. Sprawdzaj konfigurację efektywną, nie tylko plik.

## Skrypt bez prawa wykonywania

- **Objaw:** `sudo: cannot execute ...: Permission denied`.
- **Przyczyna:** pliki zapisane na Windowsie trafiły do gita bez bitu wykonywania.
- **Rozwiązanie:** `git update-index --chmod=+x scripts/*.sh` i commit (tryb `100755`).
- **Wniosek:** Windows nie zna uprawnień uniksowych – przy pracy między systemami trzeba
  je ustawiać w gicie jawnie.

## Duplikaty po ponownym uruchomieniu

- **Objaw:** w `/etc/hosts` te same maszyny po kilka razy.
- **Przyczyna:** skrypt dopisywał wpisy bez sprawdzania, czy już są; później Ansible dodał
  własny blok obok wpisów skryptu.
- **Rozwiązanie:** skrypt najpierw usuwa stare wpisy, a rola `common` usuwa wpisy skryptu
  przed zapisaniem swojego bloku (`blockinfile`). Próba na sucho (`--check --diff`) pokazała
  problem, zanim cokolwiek się zmieniło.
- **Wniosek:** **idempotentność** – uruchomienie drugi raz nie może psuć. Przy przejściu
  ze skryptów na Ansible trzeba posprzątać po starym sposobie.

## Nowy dysk z VMware niewidoczny w systemie

- **Objaw:** po dodaniu dysku w VMware `lsblk` nie pokazuje `sdb` (ćwiczenia admina, 04.11.2026).
- **Diagnoza:** `lsblk`, `sudo dmesg -T | grep sd` – brak wpisu o nowym dysku. Ponowne skanowanie
  magistrali (`echo "- - -" | sudo tee /sys/class/scsi_host/host*/scan`) nic nie dało.
- **Przyczyna:** pierwsze dodanie dysku nie trafiło do konfiguracji działającej maszyny
  (dokładnej przyczyny nie ustalono – najczęściej okno *Settings* zamknięte bez *OK*).
- **Rozwiązanie:** ponowne dodanie dysku w VMware i restart maszyny – w `dmesg`:
  `[sdb] 20971520 512-byte logical blocks: (10.7 GB/10.0 GiB)`.
- **Wniosek:** najpierw sprawdź, czy dysk w ogóle jest w konfiguracji maszyny, potem szukaj
  przyczyny w systemie.

## `last: command not found` na Ubuntu 26.04

- **Objaw:** polecenie do historii logowań nie istnieje.
- **Przyczyna:** Ubuntu 26.04 nie dostarcza już `last` – stary plik `/var/log/wtmp` miał problem
  roku 2038 (czas zapisany na 32 bitach).
- **Rozwiązanie:** `sudo apt install wtmpdb`, potem `wtmpdb last`. Bieżące sesje:
  `loginctl list-sessions`.
- **Wniosek:** polecenia znane z poradników znikają w nowych wersjach – sprawdzaj następcę,
  zamiast instalować stare pakiety na siłę.

## Usługa po naprawie dalej nie wstaje – `Start request repeated too quickly`

- **Objaw:** po poprawieniu literówki w `ExecStart` i `daemon-reload` `systemctl restart` dalej
  kończy się błędem, `is-active` – `failed`.
- **Przyczyna:** `Restart=on-failure` wznawiał zepsutą usługę wiele razy, a systemd pozwala na
  5 startów w 10 sekund (`StartLimitBurst`, `StartLimitIntervalSec`). Po przekroczeniu blokuje
  usługę, nawet gdy jest już naprawiona.
- **Diagnoza:** `journalctl -u licznik -n 5` – linia `Start request repeated too quickly`;
  `systemctl show -p StartLimitBurst -p StartLimitIntervalUSec licznik`.
- **Rozwiązanie:** `sudo systemctl reset-failed licznik`, potem `restart` (albo odczekać okno
  10 s).
- **Wniosek:** czytaj **ostatnie** linie dziennika – przyczyna obecnego błędu bywa inna niż ta,
  którą właśnie naprawiłeś.

## `logrotate -f`: `parent directory has insecure permissions`

- **Objaw:** `sudo logrotate -f /etc/logrotate.d/kopia-zespol` – `error: skipping … because parent
  directory has insecure permissions … Set "su" directive`.
- **Przyczyna:** `/var/log` ma właściciela `root:syslog` i prawo zapisu dla grupy. W takim katalogu
  `logrotate` wymaga dyrektywy `su`. Ubuntu ma `su root adm` w `/etc/logrotate.conf`, ale
  uruchomienie z jednym plikiem z `logrotate.d/` nie czyta pliku głównego.
- **Rozwiązanie:** `su root adm` (i ewentualnie `create 0640 root adm`) w bloku własnego pliku.
- **Wniosek:** test pojedynczego pliku omija ustawienia globalne – plik w `logrotate.d/` powinien
  być kompletny sam w sobie.

## nginx: nowa strona odpowiada stroną powitalną (IPv6)

- **Objaw:** `curl -H 'Host: sklep.lab' localhost` – `Welcome to nginx!`, a
  `curl -H 'Host: sklep.lab' http://127.0.0.1/` – właściwa strona. `nginx -t` bez błędów.
- **Przyczyna:** `curl` łączy się z `localhost` najpierw po IPv6 (`::1`). Vhost miał tylko
  `listen 80;` (IPv4), więc na `[::]:80` odpowiadał jedyny serwer tam słuchający – `default`.
- **Diagnoza:** `curl -v … 2>&1 | grep Trying` (`Trying [::1]:80`), `sudo nginx -T | grep listen`.
- **Rozwiązanie:** w każdym bloku `server` para `listen 80;` i `listen [::]:80;`.
- **Wniosek:** test przez `127.0.0.1` może przejść, a klienci z IPv6 dostaną inną stronę.
  Testuj tak, jak łączą się klienci.

## `systemctl is-active postgresql` – `active`, a baza nie działa

- **Objaw:** po zmianie konfiguracji restart „przechodzi”, a aplikacja nie może się połączyć.
- **Przyczyna:** w Ubuntu `postgresql.service` to tylko jednostka-parasol. Prawdziwy serwer to
  `postgresql@18-main.service` – on był `failed` (błąd w `postgresql.conf`).
- **Diagnoza:** `pg_lsclusters` (`down`), `systemctl status postgresql@18-main`, przyczyna
  w `/var/log/postgresql/postgresql-18-main.log`.
- **Rozwiązanie:** poprawić konfigurację, `sudo systemctl restart postgresql@18-main`.
- **Wniosek:** sprawdzaj usługę, która naprawdę wykonuje pracę, i to, czy przyjmuje połączenia
  (`pg_isready`), a nie tylko stan jednostki.

## SSH nie wraca po uruchomieniu procesu w tle

- **Objaw:** `ssh host "polecenie &"` wypisuje wynik, ale się nie kończy – czeka, aż proces w tle
  skończy pracę (ćwiczenie z blokadą w PostgreSQL, 04.11.2026).
- **Przyczyna:** proces w tle odziedziczył standardowe wyjście lub błędy sesji SSH; `ssh` czeka
  na zamknięcie wszystkich tych strumieni.
- **Rozwiązanie:** całkowite odłączenie – `setsid nohup polecenie >/dev/null 2>&1 </dev/null &`
  albo uruchomienie jako usługa (`systemd-run`).
- **Wniosek:** proces w tle przez SSH musi mieć przekierowane wszystkie trzy strumienie.
