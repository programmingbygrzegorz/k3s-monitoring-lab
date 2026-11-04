# Etap 1 – rozwiązania ćwiczeń: codzienna praca administratora Linuxa

Wykonanie poziomów z [ćwiczeń](02-cwiczenia-admin-linux.md) na maszynie `monitoring`
(`192.168.180.54`, Ubuntu 26.04.1), ze zrzutami terminala i odpowiedziami na „Sprawdź się”.

**Pod każdym zrzutem** jest rozpiska jego poleceń („Polecenia ze zrzutu”). Elementy, które
powtarzają się wszędzie (`|`, `2>/dev/null`, `$(…)`, `awk`, `sed`, `grep -E`…), są wyjaśnione
w [słowniczku składni](06-jak-czytac-polecenia.md) – przeczytaj go przed rozwiązaniami.

**Jak powstały zrzuty (04.11.2026):** polecenia wykonał Claude przez SSH z Windowsa, z tymczasowym
`sudo` bez hasła (`/etc/sudoers.d/99-claude-tymczasowe`). Na zrzucie każde polecenie jest
poprzedzone znakiem zachęty, a długie wyniki są przycięte (`cut`, `head`, `tail`). Restart
z poziomu 4 zastąpiono sprawdzeniem `findmnt --verify` (wynik ten sam: `fstab` jest poprawny).
Potem maszyna wróciła do snapshotu `przed-cwiczeniami-linux`, więc Ty zaczynasz od czystego systemu.

**Najciekawsze rzeczy, które wyszły po drodze** (w ćwiczeniach ich nie zapowiadano):

| Odkrycie | Poziom |
|---|---|
| Ubuntu 26.04 nie ma już polecenia `last` | [1](#poziom-1--kto-próbował-się-zalogować) |
| Dwa pliki SSH mówią co innego o hasłach – wygrywa pierwszy alfabetycznie | [3](#poziom-3--grep-w-plikach-konfiguracyjnych) |
| Port 5000 działa, choć `ufw` go nie wpuszcza – Docker omija `ufw` | [3](#poziom-3--grep-w-plikach-konfiguracyjnych) |
| `find` znalazł zapomniany `/swap.img` (3,8 GB) | [5](#poziom-5--kończy-się-miejsce) |
| Po naprawie usługa dalej nie wstaje – limit startów systemd | [6](#poziom-6--usługa-nie-wstaje) |
| Plik tworzony przez Annę nie ma prawa zapisu dla grupy (`umask`) | [8](#poziom-8--nowy-użytkownik-i-wspólny-katalog) |
| `logrotate -f` z jednym plikiem odmawia – brak ustawień z `logrotate.conf` | [9](#poziom-9--zadanie-co-noc-i-rotacja-logów) |

---

## Przygotowanie

Dysk 10 GB dodany w VMware. Pierwsza próba się nie udała: system nie widział `sdb`, a ponowne
skanowanie magistrali SCSI (`echo "- - -" > /sys/class/scsi_host/host*/scan`) nie pomogło. Dysk
pojawił się dopiero po ponownym dodaniu w VMware i restarcie maszyny. W `lsblk` widać go jako `sdb`
10G, bez partycji (zrzut w poziomie 0).

## Poziom 0 – co to za maszyna?

![hostnamectl, uptime, nproc, free](img/0-system.png)

**Polecenia ze zrzutu:**

- `hostnamectl` – nazwa maszyny, system, jądro, wirtualizacja w jednym miejscu.
- `uname -r` – sama wersja jądra (`-r` = *release*).
- `uptime` – godzina, jak długo działa (`up 2 min`), ilu zalogowanych, `load average` z 1, 5 i 15 minut.
- `nproc` – liczba rdzeni procesora.
- `free -h` – pamięć RAM i swap; `-h` = jednostki „ludzkie” (`Gi`, `Mi`) zamiast bajtów.

![lsblk, df, ip, ss, usługi](img/0-dyski-siec.png)

**Polecenia ze zrzutu:**

- `lsblk -e7` – dyski i partycje jako drzewo; `-e7` ukrywa urządzenia typu 7 (`loop` – obrazy snapów).
- `df -h -x tmpfs -x overlay` – zajętość systemów plików; `-x` wyklucza typy: `tmpfs` (w pamięci) i `overlay` (Docker).
- `ip -br a` – adresy wszystkich interfejsów w skrócie (`-br` = *brief*, `a` = *address*).
- `ip r` – tablica tras (`r` = *route*); `default via` to brama.
- `sudo ss -tulpn` – porty, na których coś słucha: `-t` TCP, `-u` UDP, `-l` tylko nasłuchujące, `-p` z nazwą procesu (stąd `sudo`), `-n` numery zamiast nazw.
- `systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}' | head -25` – działające usługi; `--no-legend` bez nagłówka i podsumowania, `awk '{print $1}'` zostawia tylko pierwszą kolumnę (nazwę), `head -25` – pierwsze 25.

**Notatka o maszynie:**

| Co | Wynik |
|---|---|
| System, jądro | Ubuntu 26.04.1 LTS, jądro `7.0.0-42-generic`, maszyna VMware |
| Procesor, pamięć | 2 rdzenie, 3,3 GiB RAM (`available` 2,6 GiB), **swap 0** |
| Dyski | `sda` 40G: `/boot` 2G, `/` 38G na LVM (33% zajęte); `sdb` 10G pusty |
| Sieć | `ens33` `192.168.180.54/24`, brama `192.168.180.2`; `docker0` `172.17.0.1/16` |
| Porty | 22 (`sshd`), 5000 (`docker-proxy`), 53 tylko lokalnie (`systemd-resolved`), 323/udp lokalnie (`chronyd`) |
| Usługi | `ssh`, `docker`, `containerd`, `cron`, `rsyslog`, `chrony`, `open-vm-tools`… |

**Sprawdź się:**
- **`load average`** to średnia liczba procesów, które chcą procesora (działają albo czekają na
  niego, a w Linuxie także czekają na dysk) – z ostatnich 1, 5 i 15 minut. Odnosisz ją do liczby
  rdzeni: przy 2 rdzeniach wartość 2,0 oznacza pełne obciążenie, a długo powyżej 2 – kolejkę.
  Tu `0.10, 0.16, 0.07` – maszyna odpoczywa.
- **`free` małe, `available` duże:** Linux używa wolnej pamięci jako pamięci podręcznej plików
  (`buff/cache`). Gdy program potrzebuje pamięci, jądro oddaje ją z cache. Liczy się `available`,
  nie `free` – to nie jest problem.
- **Port 5000:** `docker-proxy` – Docker przekazuje ruch z portu hosta do kontenera rejestru
  (`registry:3`, postawiony w Etapie 4 – patrz [własny obraz](../etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md)).
- **`ss -tulpn` bez `sudo`:** kolumna `Process` jest pusta dla procesów innych użytkowników.
  Widzisz, że port słucha, ale nie wiesz, kto. Z `sudo` widać nazwę i PID.

## Poziom 1 – kto próbował się zalogować?

Z Windowsa: `ssh admin@…`, `ssh root@…`, `ssh test@…`, `ssh oracle@…`, `ssh admin@…`.

![nieudane próby w auth.log](img/1-auth-nieudane.png)

**Polecenia ze zrzutu:**

- `grep -E 'Invalid user|Failed password|Connection closed by (invalid|authenticating) user' /var/log/auth.log | tail -6 | cut -c1-140` – linie z którymkolwiek z trzech komunikatów (`-E` pozwala na `|` = „albo” i nawiasy); z nich ostatnie 6 (`tail -6`), każda przycięta do 140 znaków (`cut -c1-140`).
- `grep -c 'Invalid user' /var/log/auth.log` – tylko **liczba** pasujących linii (`-c` = *count*).
- `grep 'Invalid user' … | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -nr` – z linii z nieudanym logowaniem wytnij tylko fragment `from ADRES` (`-o` = tylko pasujący kawałek, `[0-9.]+` = cyfry i kropki), ułóż, policz powtórzenia, największe liczby na górę (`-n` liczbowo, `-r` odwrotnie). Rozpisane w [słowniczku](06-jak-czytac-polecenia.md#4-łączenie-poleceń----).
- `grep -oE 'Invalid user [^ ]+' … | awk '{print $3}' | sort | uniq -c | sort -nr` – wytnij „Invalid user NAZWA” (`[^ ]+` = ciąg znaków bez spacji), `awk` bierze trzecie słowo (samą nazwę), dalej liczenie jak wyżej.
- `zgrep -h 'Invalid user' /var/log/auth.log* | wc -l` – szukaj we **wszystkich** plikach `auth.log`, także spakowanych `.gz` (`zgrep`), bez nazw plików (`-h`), policz linie (`wc -l`).

![udane logowania, last, who, loginctl](img/1-auth-udane.png)

**Polecenia ze zrzutu:**

- `grep 'Accepted' /var/log/auth.log | tail -3 | cut -c1-150` – trzy ostatnie udane logowania.
- `grep 'Accepted' … | awk '{print $5, $7, $9}' | sort | uniq -c` – z każdej linii pola 5, 7 i 9 (metoda, użytkownik, adres), potem policzone. Numery pól ustala się, licząc słowa w linii logu.
- `last -n 5` – historia logowań; w Ubuntu 26.04 nie istnieje (`command not found`).
- `who` – kto jest zalogowany na terminalu (tty).
- `loginctl list-sessions --no-pager` – sesje według `systemd-logind` (także bez terminala).

Rozwiązanie kroków 4 i 5:

```bash
grep 'Invalid user' /var/log/auth.log | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -nr
grep -oE 'Invalid user [^ ]+' /var/log/auth.log | awk '{print $3}' | sort | uniq -c | sort -nr
```

Wynik: **4 próby, wszystkie z `192.168.180.1`**: `admin` 2 razy, `test` i `oracle` po razie.
Próba na `root` nie ma wpisu `Invalid user` – konto istnieje, więc w logu jest `Connection closed by
authenticating user root`. Udanych logowań kluczem: 120 z Windowsa i 8 z samej maszyny
`192.168.180.54` – to Ansible, który łączy się z `monitoring` także do niej samej.

**Niespodzianka – nie ma `last`:** w Ubuntu 26.04 polecenie `last` (pakiet `util-linux`) zniknęło,
bo stary plik `/var/log/wtmp` miał problem roku 2038. Zastępstwa:

```bash
loginctl list-sessions            # bieżące sesje (systemd-logind)
sudo apt install wtmpdb           # nowa baza logowań, potem:
wtmpdb last                       # historia logowań, jak dawniej last
```

`who` jest pusty, bo pokazuje sesje z terminalem (tty), a sesje uruchamiane poleceniem `ssh host
"polecenie"` terminala nie mają. W Twojej interaktywnej sesji `who` pokaże `grzegorz pts/0`.

**Sprawdź się:**
- **`192.168.180.1`:** VMware w trybie NAT ukrywa Twój komputer za adresem `.1` w sieci VMnet8.
  Maszyna widzi tylko ten adres.
- **`Invalid user` / `Failed password`:** `Invalid user` – takiego konta nie ma. `Failed password` –
  konto jest, ale hasło złe. U nas logowanie hasłem jest wyłączone (`PasswordAuthentication no`),
  więc serwer nawet nie pyta o hasło i takiego wpisu nie ma.
- **`sort | uniq -c | sort -nr`:** `sort` układa linie, `uniq -c` skleja **sąsiednie** identyczne
  linie i liczy je (dlatego wcześniej `sort`, inaczej te same adresy rozrzucone po pliku liczyłby
  osobno), `sort -nr` sortuje liczbowo malejąco – najczęstsze na górze.
- **Automatyczna blokada:** `fail2ban` – czyta logi i po kilku nieudanych próbach dopisuje regułę
  firewalla blokującą adres (np. na 10 minut).

## Poziom 2 – logi systemowe: journalctl

![journalctl -p err, -u ssh, -u docker, list-boots](img/2-journal-bledy.png)

**Polecenia ze zrzutu:**

- `journalctl -b -p err --no-pager | cut -c1-130` – dziennik od ostatniego startu (`-b` = *boot*), tylko błędy i gorsze (`-p err` = *priority*), wypisany w całości (`--no-pager`), przycięty.
- `journalctl -u ssh --since '10 min ago' --no-pager | tail -5` – tylko usługa `ssh` (`-u` = *unit*) z ostatnich 10 minut, ostatnie 5 linii.
- `journalctl -u docker -n 5 --no-pager` – 5 ostatnich wpisów usługi `docker` (`-n` = liczba linii).
- `journalctl --list-boots --no-pager` – lista uruchomień systemu z datami; `0` – bieżące, `-1` – poprzednie.
- `journalctl --disk-usage` – ile miejsca zajmuje dziennik.

![journalctl -f – logowanie na żywo](img/2-journal-na-zywo.png)

**Polecenia ze zrzutu:**

- `timeout 9 journalctl -f -n 0 -u ssh --no-pager | cut -c1-140` – śledź dziennik `ssh` na żywo (`-f` = *follow*), bez starych wpisów (`-n 0`). `timeout 9` przerywa po 9 sekundach – w tym czasie nastąpiło logowanie z Windowsa. Ty zamiast `timeout` przerwiesz Ctrl+C.

![dmesg – wykrycie dysku sdb](img/2-dmesg.png)

**Polecenia ze zrzutu:**

- `sudo dmesg -T | grep -iE 'sd[ab]\b|sdb' | tail -8 | cut -c1-130` – komunikaty jądra z czytelnym czasem (`-T`), tylko o dyskach `sda`/`sdb` (`[ab]` = jedna z liter, `\b` = koniec słowa), ostatnie 8.
- `journalctl -k -b --no-pager | grep -i 'sdb' | head -5` – to samo z dziennika: tylko jądro (`-k` = *kernel*) od startu, pierwsze 5 wzmianek o `sdb`.
- `journalctl -b --no-pager | grep -ciE 'error|fail'` – ile linii od startu zawiera „error” albo „fail” bez względu na wielkość liter (`-c` liczba, `-i` wielkość liter, `-E` dla `|`).

Wyniki: w `-p err` tylko jeden wpis – `piix4_smbus … SMBus Host Controller not enabled!`. To znany,
niegroźny komunikat o wirtualnej płycie głównej VMware. Lista uruchomień: 6 (od 28.10). Dziennik
zajmuje 42,1 MB. `grep -ciE 'error|fail'` znalazł 114 linii od startu – większość to zwykłe
komunikaty, w których słowo „fail” występuje w nazwie opcji. Dlatego `-p err` jest lepszym filtrem.

**Sprawdź się:**
- **`journalctl` a `/var/log`:** `journald` zbiera logi w swoim binarnym dzienniku, a `rsyslog`
  dostaje od niego kopię i zapisuje ją jako zwykłe pliki tekstowe (`syslog`, `auth.log`). Stąd te
  same wpisy w obu miejscach. `journalctl` umie filtrować po usłudze, priorytecie i czasie; pliki
  tekstowe przeszukasz `grep`.
- **Poziomy `-p`:** `0 emerg`, `1 alert`, `2 crit`, `3 err`, `4 warning`, `5 notice`, `6 info`,
  `7 debug`. `-p warning` pokazuje poziom `warning` **i wszystkie poważniejsze** (0–4).
- **`-b -1` puste:** gdy dziennik jest trzymany tylko w pamięci (`/run/log/journal`, brak katalogu
  `/var/log/journal` albo `Storage=volatile`), po restarcie znika. U nas jest trwały – widać 6
  uruchomień.
- **Moment wykrycia dysku:** `sudo dmesg -T | grep sdb` albo `journalctl -k | grep sdb` – tu
  `16:52:33` (start maszyny po dodaniu dysku).

## Poziom 3 – grep w plikach konfiguracyjnych

![grep PasswordAuthentication i sshd -T](img/3-grep-ssh.png)

**Polecenia ze zrzutu:**

- `grep -n -i 'PasswordAuthentication' /etc/ssh/sshd_config` – szukaj ustawienia z numerami linii (`-n`), bez względu na wielkość liter (`-i`).
- `sudo grep -rn -i 'PasswordAuthentication' /etc/ssh/sshd_config.d/` – to samo we wszystkich plikach katalogu (`-r` = rekurencyjnie); wynik ma postać `plik:linia:treść`.
- `grep -n -i 'Include' /etc/ssh/sshd_config` – gdzie główny plik dołącza inne pliki.
- `sudo sshd -T | grep -i -E 'passwordauthentication|permitrootlogin|…'` – `sshd -T` (*test*) wypisuje całą ostateczną konfigurację, `grep` zostawia cztery interesujące ustawienia.

![konfiguracja bez komentarzy, kontekst, /etc/hosts, ufw](img/3-grep-bez-komentarzy.png)

**Polecenia ze zrzutu:**

- `grep -Ev '^\s*(#|$)' /etc/ssh/sshd_config` – usuń (`-v`) linie, które od początku (`^`), po ewentualnych odstępach (`\s*`), mają `#` albo od razu koniec linii (`$`). Zostają tylko prawdziwe ustawienia.
- `grep -n -B2 -A2 '^#Port' /etc/ssh/sshd_config` – linia zaczynająca się od `#Port` plus 2 linie przed (`-B2` = *before*) i 2 po (`-A2` = *after*).
- `sudo grep -rl '192.168.180.51' /etc 2>/dev/null` – w całym `/etc` (`-r`) wypisz tylko **nazwy plików** (`-l`) z tym adresem; komunikaty o błędach do kosza (`2>/dev/null`).
- `sudo ufw status | grep -ci deny` – ile linii reguł zawiera „deny”.
- `sudo ufw status numbered | head -12` – reguły z numerami (potrzebne do `ufw delete NUMER`).

**Niespodzianka – dwa pliki, dwa różne ustawienia:**

```
/etc/ssh/sshd_config.d/01-lab.conf:1:PasswordAuthentication no        ← skrypt z Etapu 1
/etc/ssh/sshd_config.d/50-cloud-init.conf:1:PasswordAuthentication yes ← instalator Ubuntu (cloud-init)
```

Które wygrywa? `sshd -T` mówi `passwordauthentication no`. W `sshd` obowiązuje zasada **pierwsza
znaleziona wartość wygrywa**, a pliki z `sshd_config.d/` są czytane alfabetycznie – `01-…` przed
`50-…`. Dlatego pliki labu mają numer `01`. Gdyby skrypt nazwał plik `99-lab.conf`, hasła byłyby
**włączone**. (W wielu innych programach, np. `nginx`, `sysctl`, jest odwrotnie – wygrywa ostatnia.)

Krok 5: adres mastera `192.168.180.51` jest tylko w `/etc/hosts`.

Krok 6: `ufw status | grep -ci deny` daje **0**. Blokowanie robi domyślna polityka
(`Default: deny (incoming)`), a nie osobne reguły. Reguły wpuszczają z sieci labu porty 22, 3000
i 3001 (Grafana i Uptime Kuma z Etapu 4). **Portu 5000 nie ma, a rejestr działa** – Docker dopisuje
własne reguły `iptables` przed regułami `ufw`, więc porty opublikowane przez `docker run -p` są
otwarte mimo `ufw`. To częsta pułapka w produkcji. Rozwiązania: publikować port tylko na
`127.0.0.1` albo dopisać reguły do łańcucha `DOCKER-USER`.

**Sprawdź się:**
- **Sam `grep` w `sshd_config`** pokazuje tylko jeden plik. Ustawienie może być w dołączonym pliku
  (`Include`), może być nadpisane albo wcale nie istnieć (wtedy obowiązuje wartość domyślna).
  `sshd -T` wypisuje **ostateczną** konfigurację, której serwer naprawdę używa.
- **Opcje `grep`:** `-r` rekurencyjnie po katalogach, `-l` tylko nazwy plików, `-n` numery linii,
  `-i` bez rozróżniania wielkości liter, `-v` odwrotnie (linie **bez** wzorca), `-E` rozszerzone
  wyrażenia (`|`, `+`, `()`), `-c` liczba pasujących linii, `-A N` / `-B N` – N linii po / przed
  trafieniem.
- **`^\s*(#|$)`:** początek linii, dowolne odstępy, potem `#` (komentarz) **albo** od razu koniec
  linii (pusta linia). Z `-v` zostają tylko linie z prawdziwymi ustawieniami.

## Poziom 4 – nowy dysk

![lsblk, pvs, vgs, lvs przed zmianami](img/4-lvm-przed.png)

**Polecenia ze zrzutu:**

- `lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS` – drzewo dysków z wybranymi kolumnami (`-o` = *output*): nazwa, rozmiar, typ, system plików, punkt montowania.
- `sudo pvs`, `sudo vgs`, `sudo lvs` – skrócone listy LVM: dyski fizyczne (*physical volumes*), pule (*volume groups*), wolumeny (*logical volumes*). `PFree`/`VFree` – wolne miejsce.
- `df -h /` – zajętość tylko systemu plików `/`.

![pvcreate i vgextend](img/4-lvm-pv-vg.png)

**Polecenia ze zrzutu:**

- `sudo pvcreate /dev/sdb` – oznacz cały dysk `sdb` jako PV (zapisuje nagłówek LVM, kasuje to, co było).
- `sudo vgextend ubuntu-vg /dev/sdb` – dołącz PV do istniejącej puli `ubuntu-vg`.
- `sudo pvs`, `sudo vgs` – sprawdzenie: dwa PV, pula 47,99g, wolne `<10.00g`.

![lvcreate, mkfs, mount](img/4-lvm-data.png)

**Polecenia ze zrzutu:**

- `sudo lvcreate -n data -L 5G ubuntu-vg` – nowy wolumen o nazwie (`-n`) `data`, rozmiarze (`-L`) 5 GB, z puli `ubuntu-vg`.
- `sudo mkfs.ext4 -q /dev/ubuntu-vg/data && echo 'mkfs OK'` – utwórz system plików ext4 (*make filesystem*), cicho (`-q`); po sukcesie wypisz `mkfs OK`.
- `sudo mkdir /data` – katalog, w którym wolumen będzie widoczny (punkt montowania).
- `sudo mount /dev/ubuntu-vg/data /data` – podłącz wolumen do katalogu (do restartu).
- `df -h /data` – sprawdzenie rozmiaru.

![fstab po UUID i mount -a](img/4-fstab.png)

**Polecenia ze zrzutu:**

- `sudo cp /etc/fstab /etc/fstab.bak` – kopia przed zmianą.
- `sudo blkid /dev/ubuntu-vg/data` – UUID i typ systemu plików.
- `echo 'UUID=…  /data  ext4  defaults  0  2' | sudo tee -a /etc/fstab` – dopisz linię na końcu `fstab` (`tee -a`, bo `>>` nie działa z `sudo` – [dlaczego](06-jak-czytac-polecenia.md#5-przekierowania-i-devnull)). Pola: co, gdzie, typ, opcje, `0` – bez `dump`, `2` – sprawdzaj przy starcie po `/`.
- `sudo umount /data` – odłącz, żeby sprawdzić, czy `fstab` sam go podłączy.
- `sudo mount -a && echo 'mount -a OK'` – zamontuj wszystko z `fstab`; komunikat tylko przy sukcesie.
- `findmnt /data` – co i z jakimi opcjami jest zamontowane w `/data`.
- `tail -3 /etc/fstab` – trzy ostatnie linie pliku.

![lvextend -r: / z 38G na 41G](img/4-lvextend.png)

**Polecenia ze zrzutu:**

- `sudo lvextend -r -L +3G /dev/ubuntu-vg/ubuntu-lv` – powiększ wolumen o (`+`) 3 GB (`-L`) i od razu system plików na nim (`-r` = *resizefs*).
- `lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS` – widać, że `ubuntu-lv` leży na `sda3` i `sdb`.

![findmnt --verify zamiast restartu](img/4-fstab-verify.png)

**Polecenia ze zrzutu:**

- `sudo systemctl daemon-reload` – systemd tworzy z `fstab` jednostki montowania; po zmianie `fstab` trzeba je odświeżyć.
- `sudo findmnt --verify --tab-file /etc/fstab` – sprawdź poprawność pliku (`--tab-file` – który plik).

Po kroku 2 pula `ubuntu-vg` urosła do 47,99 GB, wolne `<10.00g`. `/data` ma 4,9G (część zajmują
struktury ext4). `lvextend -r` powiększył wolumen i od razu system plików (`resize2fs … on-line
resizing required`) – `/` ma 41G, bez zatrzymywania czegokolwiek. `lsblk` pokazuje, że
`ubuntu--vg-ubuntu--lv` leży teraz **na dwóch dyskach**: `sda3` i `sdb`.

Zamiast restartu: `sudo findmnt --verify` → `Success, no errors or warnings detected`. To polecenie
sprawdza `fstab` (czy urządzenia istnieją, czy typy systemów plików się zgadzają). Restart w Twoim
wykonaniu jest dobrym, ostatecznym testem.

**Sprawdź się:**
- **`mount -a` przed restartem:** montuje wszystko z `fstab`, więc błąd wychodzi od razu, gdy
  jeszcze masz działającą sesję. Bez tego literówka w `fstab` kończy się tym, że po restarcie
  system staje w trybie awaryjnym (*emergency mode*) – naprawa tylko z konsoli VMware.
- **UUID zamiast `/dev/sdb`:** nazwy `sda`/`sdb` nadawane są w kolejności wykrycia i mogą się
  zamienić po dodaniu dysku. UUID jest zapisany w samym systemie plików i się nie zmienia.
- **Bez LVM:** `sudo fdisk /dev/sdb` (albo `parted`) → partycja `sdb1`, `sudo mkfs.ext4 /dev/sdb1`,
  `mkdir`, `mount`, wpis w `fstab`. Powiększenie zwykłej partycji jest trudniejsze: musi za nią być
  wolne miejsce na **tym samym** dysku (`growpart`, potem `resize2fs`).
- **Zmniejszanie:** ext4 nie zmniejsza się w trakcie pracy – trzeba odmontować (dla `/` – start
  z innego systemu), sprawdzić `e2fsck`, zmniejszyć system plików, a dopiero potem wolumen.
  Pomyłka w kolejności niszczy dane. XFS w ogóle nie umie się zmniejszać.
- **Powiększony istniejący dysk:** system widzi nowy rozmiar po `echo 1 > /sys/class/block/sda/device/rescan`,
  potem powiększasz partycję (`growpart /dev/sda 3`), PV (`pvresize /dev/sda3`), a na końcu
  `lvextend -r`.

## Poziom 5 – kończy się miejsce

Pliki z ćwiczeń (6G i 4G) dały u nas tylko ~55% zajęcia, więc użyto **15G i 8G**, żeby dojść do 91%.

![fallocate – dysk zajęty w 91%](img/5-pelny-dysk.png)

**Polecenia ze zrzutu:**

- `sudo fallocate -l 15G /var/log/aplikacja-debug.log` – utwórz plik o długości (`-l`) 15 GB; miejsce jest rezerwowane od razu, bez zapisywania danych (trwa ułamek sekundy).

![du i find – szukanie winnego](img/5-du-find.png)

**Polecenia ze zrzutu:**

- `sudo du -xh --max-depth=1 / 2>/dev/null | sort -h | tail -5` – ile zajmuje każdy katalog pierwszego poziomu pod `/` (`--max-depth=1`), tylko ten system plików (`-x`), w czytelnych jednostkach (`-h`); bez błędów; posortuj „ludzko” (`sort -h` rozumie `G` i `M`); pokaż 5 największych.
- `sudo find / -xdev -type f -size +500M -exec ls -lh {} \; 2>/dev/null` – pliki większe niż 500 MB, z pełnym opisem z `ls -lh`. Rozpisane w [słowniczku](06-jak-czytac-polecenia.md#13-find).

![rm nie zwolnił miejsca – lsof +L1](img/5-lsof.png)

**Polecenia ze zrzutu:**

- `sudo lsof +L1` – otwarte pliki (*list open files*), które mają mniej niż 1 dowiązanie (`+L1`), czyli są usunięte z katalogu, ale ktoś je trzyma. Kolumny: program, PID, deskryptor (`3r` – numer 3, do odczytu), rozmiar, nazwa z dopiskiem `(deleted)`.

![kill zwalnia miejsce; journal, docker, apt](img/5-kill-miejsce.png)

**Polecenia ze zrzutu:**

- `ps -o pid,user,cmd -p 7097` – pokaż wybrane kolumny (`-o`) dla procesu o numerze (`-p`) 7097.
- `sudo kill 7097` – wyślij procesowi sygnał zakończenia (SIGTERM).
- `docker system df` – ile miejsca zajmują obrazy, kontenery, wolumeny i cache Dockera; `RECLAIMABLE` – do odzyskania.
- `du -sh /var/cache/apt` – suma (`-s`) jednego katalogu.

`du` prowadzi krok po kroku: `/` → `/var` 27G → `/var/log` 16G i `/var/tmp` 8,1G. `find` znalazł oba
pliki i **trzeci, niezapowiedziany: `/swap.img` 3,8G** z 28.10. W Etapie 1 swap został wyłączony
(Kubernetes tego wymaga) i zakomentowany w `fstab`, ale plik został na dysku. Na prawdziwym
serwerze to 3,8 GB do odzyskania: `sudo rm /swap.img`.

Po `rm` dalej 91%. `lsof +L1` pokazuje proces `sleep` (PID 7097) z plikiem `(deleted)` o rozmiarze
16106127360 B (15 GiB). Po `kill` – 51%, po usunięciu drugiego pliku – 30%. Bonus: `docker system df`
pokazuje 1,9 GB obrazów do odzyskania, a `/var/cache/apt` – 219 MB.

**Sprawdź się:**
- **`df` a `du`:** `df` pyta system plików, ile bloków zajętych; `du` sumuje rozmiary plików, które
  widzi w katalogach. Nie zgadzają się, gdy plik jest usunięty, ale otwarty (`du` go nie widzi,
  `df` tak), albo gdy coś jest zamontowane na niepustym katalogu (pliki „pod spodem” są niewidoczne
  dla `du`).
- **Usunięty, a miejsce zajęte:** `rm` usuwa tylko **nazwę** pliku (link w katalogu). Dane są
  zwalniane, gdy znikną wszystkie nazwy **i** zamknie go ostatni proces. Typowy przypadek: program
  pisze do logu, ktoś ręcznie usuwa log.
- **Bez zatrzymywania procesu** – obetnij plik przez otwarty deskryptor:
  ```bash
  sudo ls -l /proc/7097/fd          # widać: 3 -> /var/log/aplikacja-debug.log (deleted)
  sudo truncate -s 0 /proc/7097/fd/3
  ```
  Na przyszłość: logu, który ktoś trzyma otwarty, nie usuwaj – opróżnij go (`sudo truncate -s 0
  plik` albo `: > plik`).
- **`-x` / `-xdev`:** nie wchodź na inne systemy plików (`/boot`, `/data`, `/proc`, montowania
  Dockera). Liczysz tylko ten dysk, który się zapełnia.
- **`/` na 100%:** usługi nie mogą zapisać logów ani plików tymczasowych – padają bazy danych,
  Docker (nie startują kontenery), `apt`, czasem logowanie (brak miejsca na plik sesji). ext4
  rezerwuje ~5% dla roota (`tune2fs -m`), dzięki temu root zwykle może jeszcze się zalogować
  i posprzątać.

## Poziom 6 – usługa nie wstaje

![licznik.service działa](img/6-licznik-start.png)

**Polecenia ze zrzutu:**

- `cat /etc/systemd/system/licznik.service` – wyświetl plik usługi.
- `sudo systemctl enable --now licznik` – włącz przy starcie i uruchom teraz.
- `sleep 11; systemctl status licznik --no-pager | head -12` – odczekaj 11 s (żeby powstały wpisy), potem pierwsze 12 linii statusu.
- `journalctl -u licznik -n 4 --no-pager` – 4 ostatnie wpisy usługi.

![literówka: status=203/EXEC](img/6-licznik-awaria.png)

**Polecenia ze zrzutu:**

- `sudo sed -i 's#/usr/local/bin/licznik.sh#/usr/local/bin/licznk.sh#' /etc/systemd/system/licznik.service` – zamień ścieżkę w pliku na tę z literówką (`-i` – w pliku, `#` – separator, bo ścieżka zawiera `/`). [Więcej o `sed`](06-jak-czytac-polecenia.md#12-sed).
- `sudo systemctl daemon-reload; sudo systemctl restart licznik` – wczytaj zmienione pliki usług, potem restart.
- `systemctl status licznik --no-pager | head -8` – początek statusu z kodem `203/EXEC`.
- `journalctl -u licznik -n 5 --no-pager | cut -c1-150` – przyczyna w dzienniku.

![po naprawie dalej failed – Start request repeated too quickly](img/6-licznik-limit.png)

**Polecenia ze zrzutu:**

- `grep ExecStart /etc/systemd/system/licznik.service` – która ścieżka jest teraz w pliku.
- `sudo sed -i 's#licznk.sh#licznik.sh#' …` – poprawka literówki.
- `sudo systemctl daemon-reload && sudo systemctl restart licznik` – restart tylko po udanym `daemon-reload`.
- `systemctl is-active licznik; systemctl show -p MainPID licznik` – stan jednym słowem i numer głównego procesu (`0` = brak).
- `systemctl show -p StartLimitBurst -p StartLimitIntervalUSec licznik` – limit startów: ile (`Burst`) w jakim czasie (`Interval`).

![reset-failed, restart, odporność na kill](img/6-licznik-naprawa.png)

**Polecenia ze zrzutu:**

- `sudo systemctl reset-failed licznik` – wyzeruj stan `failed` i licznik startów.
- `sudo systemctl kill -s KILL licznik` – wyślij procesom usługi sygnał (`-s`) KILL – jak awaria.
- `sleep 3; systemctl is-active licznik; systemctl show -p MainPID -p NRestarts licznik` – po 3 s: stan, nowy PID i ile razy systemd wznowił usługę.
- `journalctl -u licznik -n 8 --no-pager | grep -v 'licznik: '` – ostatnie wpisy bez zwykłych linii skryptu (`-v` = odwrotnie), zostają komunikaty systemd.

Przebieg:

1. Po `sed` z literówką `systemctl restart` ostrzegł: `The unit file … changed on disk. Run
   'systemctl daemon-reload'` – bez `daemon-reload` systemd dalej używał starej wersji pliku (z
   poprawną ścieżką) i usługa „działała”.
2. Po `daemon-reload` – `status=203/EXEC` i w dzienniku `Unable to locate executable
   '/usr/local/bin/licznk.sh': No such file or directory`. Kod `203/EXEC` oznacza: systemd nie mógł
   uruchomić programu (brak pliku, brak prawa `x`, zła pierwsza linia `#!`).
3. **Pułapka, której nie było w ćwiczeniu:** po poprawieniu ścieżki i `daemon-reload` restart dalej
   się nie udaje, a w dzienniku jest `Start request repeated too quickly`. `Restart=on-failure`
   wznawiał zepsutą usługę raz za razem, a systemd pozwala na **5 startów w 10 sekund**
   (`StartLimitBurst=5`, `StartLimitIntervalUSec=10s`). Po przekroczeniu blokuje usługę. Pomaga:
   ```bash
   sudo systemctl reset-failed licznik
   sudo systemctl restart licznik
   ```
   (Albo odczekanie 10 sekund – limit liczy się w oknie czasu.)
4. Odporność: po `systemctl kill -s KILL` usługa wstała sama – nowy PID (`9424` → `9540`),
   `NRestarts=1`. `is-enabled` – `enabled`.

**Sprawdź się:**
- **`daemon-reload`:** systemd czyta pliki `.service` raz i trzyma je w pamięci. Po zmianie pliku
  trzeba kazać mu przeczytać je ponownie. Bez tego używa starej wersji (i ostrzega, jak wyżej).
- **`enable` / `start`:** `start` – uruchom teraz. `enable` – uruchamiaj przy starcie systemu
  (dowiązanie w `multi-user.target.wants/`). `enable --now` – jedno i drugie.
- **`Restart=on-failure`:** wznawia, gdy proces skończy się kodem różnym od 0, zostanie zabity
  sygnałem (jak nasz `KILL`) albo przekroczy limit czasu. **Nie** wznawia, gdy proces sam skończy
  się kodem 0, gdy zatrzymasz go `systemctl stop` i gdy zadziała limit startów.
- **Gdzie trafiło `echo`:** wyjście (stdout i stderr) usługi systemd przekazuje do `journald` –
  stąd linie `licznik.sh[8076]: licznik: 16:58:22 …` w `journalctl -u licznik`.

## Poziom 7 – coś zjada procesor

![top i ps – dwa procesy yes](img/7-cpu.png)

**Polecenia ze zrzutu:**

- `top -b -n 1 | head -12` – jeden „zrzut” programu `top` jako zwykły tekst (`-b` = *batch*, `-n 1` = jedna klatka), pierwsze 12 linii. Ty uruchomisz `top` interaktywnie.
- `ps aux --sort=-%cpu | head -4` – wszystkie procesy (`aux` – wszystkich użytkowników, z kontem, także bez terminala) posortowane malejąco (`-`) po użyciu CPU.
- `ps -o pid,user,lstart,etime,cmd -C yes` – procesy o nazwie (`-C`) `yes`: PID, właściciel, dokładny czas startu (`lstart`), ile już działają (`etime`), polecenie.

![pkill, swap, pamięć](img/7-kill.png)

**Polecenia ze zrzutu:**

- `pgrep -a yes` – numery procesów o nazwie `yes` z pełnym poleceniem (`-a`).
- `pkill yes` – zakończ wszystkie procesy o tej nazwie.
- `sleep 1; pgrep -a yes || echo 'brak procesow yes'` – `pgrep` nic nie znalazł (kod 1), więc wykonało się `echo` po `||`.
- `top -b -n 1 | sed -n '3p'` – tylko 3. linia wyniku `top` (wiersz `%Cpu(s)`).
- `swapon --show; echo "swap: $(swapon --show | wc -l) urzadzen"` – lista swapu (pusta) i jej długość policzona przez `wc -l` wstawiona w tekst przez `$(…)`.
- `ps aux --sort=-%mem | head -4` – procesy zajmujące najwięcej pamięci.

Dwa procesy `yes` po 100% CPU. Po minucie `load average: 1.44, 0.54, 0.23` – pierwsza liczba rośnie
w stronę 2,0, pozostałe wolniej (dłuższe okno). `%Cpu(s): 9.1 us, 90.9 sy, 0.0 id` – procesor bez
chwili wolnego. Dużo `sy`, bo `yes > /dev/null` głównie wywołuje funkcję jądra `write`. `ps -o lstart`
pokazuje, że oba wystartowały o 16:59:35 i należą do `grzegorz`. Po `pkill yes` – `100.0 id`.
Swapu nie ma (`swapon --show` pusty); najwięcej pamięci zajmują `dockerd`, `containerd` i `snapd`.

**Sprawdź się:**
- **`load average` 2,0:** na 2 rdzeniach – 100% wykorzystania, jeszcze bez kolejki (granica).
  Na 16 rdzeniach – ok. 12% – nic się nie dzieje.
- **`kill` / `kill -9`:** `kill` wysyła SIGTERM – prośbę o zakończenie; program może posprzątać
  (zapisać dane, zamknąć pliki). `kill -9` (SIGKILL) zabija natychmiast przez jądro – bez
  sprzątania, ryzyko uszkodzonych danych. Dlatego najpierw zwykły `kill`, a `-9` dopiero, gdy proces
  nie reaguje.
- **Kolumny CPU:** `us` – programy użytkownika, `sy` – jądro, `wa` – czekanie na dysk/sieć (I/O),
  `id` – bezczynność. Wysokie `wa` = wolny albo przeciążony dysk (sprawdzisz `iostat -x`,
  `iotop`).
- **OOM killer:** gdy brakuje pamięci (a swapu nie ma albo się skończył), jądro wybiera proces
  z największym „oom_score” i go zabija. Ślad w logach: `sudo dmesg -T | grep -i "out of memory"`
  albo `journalctl -k | grep -i oom` – wpis `Out of memory: Killed process 1234 (java)`.

## Poziom 8 – nowy użytkownik i wspólny katalog

![adduser, groupadd, katalog 2770](img/8-konto-grupa.png)

**Polecenia ze zrzutu:**

- `sudo adduser --disabled-password --gecos 'Anna Nowak' anna 2>&1 | tail -3` – nowe konto bez hasła; `--gecos` – opis (imię i nazwisko), dzięki temu `adduser` o nic nie pyta.
- `id anna` – UID, grupa główna i wszystkie grupy konta.
- `sudo groupadd devops` – nowa grupa.
- `sudo usermod -aG devops anna` – dopisz (`-a` = *append*) konto do grupy dodatkowej (`-G`). Bez `-a` konto wypadłoby z pozostałych grup!
- `sudo chown root:devops /srv/zespol` – właściciel `root`, grupa `devops`.
- `sudo chmod 2770 /srv/zespol` – prawa: `2` setgid, `7` właściciel rwx, `7` grupa rwx, `0` inni nic.
- `ls -ld /srv/zespol` – prawa samego katalogu (`-d`), nie jego zawartości.

![po ponownym zalogowaniu: setgid i prawa Anny](img/8-uprawnienia.png)

**Polecenia ze zrzutu:**

- `id -nG` – Twoje grupy w tej sesji, same nazwy (`-n`), wszystkie (`-G`).
- `touch /srv/zespol/plan.txt && ls -l /srv/zespol` – utwórz pusty plik, potem pokaż zawartość katalogu.
- `sudo -u anna touch /srv/zespol/anna.txt` – utwórz plik **jako Anna** (test jej uprawnień).
- `sudo -u anna ls /root` – czy Anna może zajrzeć do katalogu roota.
- `sudo -l -U anna` – co Anna może przez `sudo`.
- `grep anna /etc/passwd`, `grep devops /etc/group` – wpis konta i grupy.
- `sudo grep anna /etc/shadow | cut -d: -f1-3` – wpis z pliku haseł, tylko pola 1–3 rozdzielone `:` (nazwa, skrót hasła, data zmiany).
- `sudo usermod -L anna; sudo passwd -S anna` – zablokuj konto (`-L` = *lock*), pokaż stan hasła (`-S` = *status*).
- `getent group sudo` – członkowie grupy `sudo` (z plików i ewentualnie z LDAP).

Wyniki: `uid=1001(anna)`, katalog `drwxrws--- root devops` (litera `s` w miejscu `x` grupy to
setgid). Oba pliki w `/srv/zespol` mają grupę **`devops`**, choć grupa podstawowa użytkowników to
`grzegorz` i `anna`. Anna nie może czytać `/root` (`Permission denied`), `sudo -l -U anna` – `User
anna is not allowed to run sudo`. W `/etc/shadow` – `anna:!:20761` (`!` = brak hasła, 20761 = dzień
ostatniej zmiany liczony od 1.01.1970). Po `usermod -L` `passwd -S` pokazuje `L` (locked).

**Niespodzianka – prawa plików:** `plan.txt` (grzegorz) ma `-rw-rw-r--`, a `anna.txt` ma
`-rw-r--r--`, czyli inni członkowie `devops` nie mogą go zmieniać. Powód: `umask`. Twoja sesja ma
`umask 002` (grupa może pisać), a polecenie uruchomione przez `sudo -u anna` – `022`. Na wspólnym
katalogu to częsty problem. Rozwiązania: `umask 002` w profilu użytkowników zespołu albo domyślne
listy ACL na katalogu:

```bash
sudo setfacl -d -m g:devops:rwx /srv/zespol    # nowe pliki dostaną prawo zapisu dla devops
```

**Sprawdź się:**
- **`2770`:** `2` – setgid, `7` – właściciel `rwx`, `7` – grupa `rwx`, `0` – inni nic. Setgid na
  katalogu: nowe pliki i katalogi dziedziczą **grupę katalogu** (`devops`) zamiast grupy
  podstawowej twórcy. Dzięki temu cały zespół ma do nich dostęp.
- **Wylogowanie:** lista grup jest przypisywana procesowi przy logowaniu. Bieżąca sesja ma starą
  listę. Pomaga nowe logowanie albo `newgrp devops` (nowa powłoka z grupą). Na zrzucie od razu
  widać `devops`, bo każde polecenie szło przez nowe połączenie SSH.
- **`passwd` / `shadow`:** `/etc/passwd` – nazwa, UID, GID, opis, katalog domowy, powłoka; czytają
  go wszyscy (programy zamieniają UID na nazwę). `/etc/shadow` – skróty haseł i daty ważności;
  czyta tylko root, żeby nikt nie mógł łamać skrótów offline.
- **`adduser` / `useradd`:** `useradd` to niskopoziomowe polecenie – bez opcji nie tworzy katalogu
  domowego ani nie pyta o nic. `adduser` (Debian/Ubuntu) to wygodny skrypt: tworzy katalog,
  kopiuje `/etc/skel`, pyta o dane i hasło.
- **Restart jednej usługi przez `sudo`:** plik w `/etc/sudoers.d/`, edytowany przez `visudo`
  (sprawdza składnię):
  ```bash
  sudo visudo -f /etc/sudoers.d/anna-licznik
  # treść:
  anna ALL=(root) /usr/bin/systemctl restart licznik
  ```
  Wtedy `sudo -l -U anna` pokaże tylko to jedno polecenie.

## Poziom 9 – zadanie co noc i rotacja logów

Zamiast `crontab -e` (edytor) wpis dodano jednym poleceniem – przydatne w skryptach i Ansible:

```bash
(sudo crontab -l 2>/dev/null; echo '* * * * * /usr/local/bin/kopia-zespol.sh') | sudo crontab -
```

![skrypt kopii i crontab roota](img/9-cron.png)

**Polecenia ze zrzutu:**

- `(sudo crontab -l 2>/dev/null; echo '* * * * * /usr/local/bin/kopia-zespol.sh') | sudo crontab -` – nawias grupuje dwa polecenia w jeden wynik: dotychczasowy crontab (błąd „no crontab” wyrzucony) **plus** nowa linia. Całość idzie do `crontab -`, który wczytuje crontab z wejścia (`-`). Tak dopisuje się zadanie bez edytora.
- `date '+%T'` – bieżąca godzina (`%T` = `GG:MM:SS`).

![kopie co minutę, log i wpisy CRON](img/9-wynik.png)

**Polecenia ze zrzutu:**

- `grep CRON /var/log/syslog | tail -3 | cut -c1-120` – kiedy cron uruchamiał zadania.
- `tar tzf $(ls /data/kopie/*.tar.gz | tail -1)` – lista zawartości (`t`) archiwum gzip (`z`) z pliku (`f`); nazwę pliku podstawia `$(…)` – ostatni z listy.

Cron uruchamia zadanie w pełnej minucie (`17:04:01`, `17:05:01`) – co minutę nowy plik
`zespol-…tar.gz`, linia `OK` w logu i wpis `CRON[…]: (root) CMD (…)` w `syslog`. W archiwum są
oba pliki zespołu.

**Niespodzianka – `logrotate -f` odmówił:**

![logrotate -d i -f: skipping … insecure permissions](img/9-logrotate.png)

**Polecenia ze zrzutu:**

- `sudo logrotate -d /etc/logrotate.d/kopia-zespol 2>&1 | grep -vE '^\s*$' | head -14` – próba na sucho (`-d`); `logrotate` pisze na *stderr*, więc `2>&1`; `grep -vE '^\s*$'` usuwa puste linie.
- `sudo logrotate -f …` – wymuś rotację teraz (`-f` = *force*).
- `ls -l /var/log/kopia-zespol.log*` – log i jego rotowane wersje (`*`).
- `sudo crontab -r; sudo crontab -l` – usuń cały crontab roota (`-r`), sprawdź.
- `systemctl list-timers logrotate.timer --no-pager | head -2` – kiedy systemd uruchomi `logrotate` następnym razem.

```
error: skipping "/var/log/kopia-zespol.log" because parent directory has insecure permissions
(It's world writable or writable by group which is not "root") Set "su" directive …
```

Katalog `/var/log` należy do `root:syslog` i grupa `syslog` może w nim pisać (`drwxrwxr-x`).
`logrotate` w takim katalogu nie rotuje, dopóki nie wie, jako kto ma to robić (ochrona przed
atakiem przez podmienione pliki). Ubuntu ma na to ustawienie `su root adm` w **głównym** pliku
`/etc/logrotate.conf` (linia 10). Codzienny przebieg czyta `logrotate.conf`, a on dołącza
`/etc/logrotate.d/` (linia 25) – wtedy wszystko działa. My uruchomiliśmy `logrotate` **tylko
z naszym plikiem**, więc ustawień globalnych nie było. Naprawa – `su` w naszym pliku:

![su root adm i udana rotacja](img/9-logrotate-naprawa.png)

**Polecenia ze zrzutu:**

- `ls -ld /var/log` – prawa katalogu `/var/log`.
- `grep -n '^su' /etc/logrotate.conf`, `grep -n include …` – linie zaczynające się od `su` i linia `include` w głównym pliku.
- `sudo sed -i 's/^    daily/    su root adm\n    daily/' …` – przed linią `    daily` wstaw linię `    su root adm` (`\n` = nowa linia w zamianie).
- `zcat /var/log/kopia-zespol.log.1.gz` – wyświetl spakowany log bez rozpakowywania pliku.

Po rotacji jest `kopia-zespol.log.1.gz`, a nowego, pustego logu **nie ma** – z tego samego powodu
(dyrektywa `create` też jest tylko w `logrotate.conf`). Nie szkodzi: skrypt dopisuje `>>`, więc
przy następnym przebiegu utworzy log sam. Można też dopisać `create 0640 root adm` do naszego pliku.

Na koniec `sudo crontab -r` – zadanie co minutę usunięte (`no crontab for root`). Rotację
codziennie uruchamia `logrotate.timer` (systemd), widoczny w `systemctl list-timers`.

**Sprawdź się:**
- **`0 2 * * *`:** minuta (0), godzina (2), dzień miesiąca (`*` – każdy), miesiąc (`*`), dzień
  tygodnia (`*`; 0 i 7 = niedziela). „W dni robocze o 6:30”: `30 6 * * 1-5`. Pomoc:
  [crontab.guru](https://crontab.guru).
- **Pełne ścieżki:** cron uruchamia zadanie z minimalnym środowiskiem – krótki `PATH`
  (`/usr/bin:/bin`), bez Twoich aliasów i zmiennych z `.bashrc`, katalog bieżący to katalog domowy,
  bez terminala. Polecenie, które działa w Twojej sesji, w cronie może nie znaleźć programu.
  Wyjście zadania nie trafia na ekran – przekieruj je do pliku (`>> /var/log/… 2>&1`).
- **`logrotate -d` / `-f`:** `-d` (debug) – tylko opisuje, co **by** zrobił, niczego nie zmienia.
  `-f` (force) – rotuje teraz, nawet jeśli według `daily` jeszcze nie czas. Codziennie uruchamia
  go `logrotate.timer` (na starszych systemach skrypt `/etc/cron.daily/logrotate`).
- **`systemd timer`:** jednostka `.timer` uruchamiająca jednostkę `.service` według harmonogramu
  (`OnCalendar=*-*-* 02:00`). Przewagi nad cronem: logi w `journalctl -u`, zależności między
  usługami, `Persistent=true` (zadanie pominięte, bo maszyna była wyłączona, wykona się po starcie),
  `RandomizedDelaySec` (nie wszystkie serwery naraz), lista w `systemctl list-timers`.

## Poziom 10 – sprzątanie

Maszyna wróciła do snapshotu `przed-cwiczeniami-linux` – nie ma dysku z danymi, usługi `licznik`,
konta `anna` ani tymczasowego `sudo` dla Claude. Powiększonego `/` nie dałoby się łatwo cofnąć
(`sdb` stał się jego częścią), więc snapshot był jedyną prostą drogą.

**Sprawdź się (cały rozdział):** jeśli umiesz bez zaglądania odpowiedzieć „gdzie są logi logowań”,
„jak dołożyć miejsce na `/` bez restartu”, „dlaczego `rm` nie zwolnił miejsca” i „dlaczego usługa
po naprawie dalej nie wstaje” – jesteś gotowy na typowe pytania o Linuxa na rozmowie na juniora.
