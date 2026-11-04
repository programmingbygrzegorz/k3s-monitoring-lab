# Etap 1 – ćwiczenia: codzienna praca administratora Linuxa

Dziesięć poziomów z prawdziwych sytuacji, które spotyka administrator: „co to za maszyna”, „kto
próbował się logować”, „skończyło się miejsce”, „dokładamy dysk”, „usługa nie wstaje”, „coś
zjada procesor”. Każdy poziom zajmuje 10–20 minut. Uczysz się przy okazji czytać logi i używać
`grep`, który wraca w każdym poziomie.

Wykonanie wszystkich poziomów ze zrzutami i odpowiedziami:
[rozwiązania](03-cwiczenia-admin-linux-rozwiazania.md). Rozmiary, daty i numery procesów u Ciebie
będą inne.

**Gdzie:** maszyna 🐧 **`monitoring`** (`192.168.180.54`) – stoi poza klastrem, więc nic, co tu
zepsujesz, nie ruszy Kubernetesa. Połączenie z 🪟 Windows: `ssh monitoring`.

**Przed startem:**
1. Do `monitoring` dodany w VMware **drugi dysk 10 GB** (potrzebny w poziomie 4) – patrz
   [przygotowanie](#przygotowanie).
2. **Snapshot** maszyny `monitoring` – po ćwiczeniach wracasz do niego i masz czysty system.
3. `sudo` działa (pyta o Twoje hasło).

| Poziom | Sytuacja | Czego się uczysz |
|---|---|---|
| [0](#poziom-0--co-to-za-maszyna) | „co to za maszyna?” | `hostnamectl`, `uptime`, `free`, `df`, `lsblk`, `ip`, `ss` |
| [1](#poziom-1--kto-próbował-się-zalogować) | „kto próbował się zalogować?” | `/var/log/auth.log`, `grep`, `awk`, `sort \| uniq -c`, `loginctl`, `wtmpdb last` |
| [2](#poziom-2--logi-systemowe-journalctl) | „co się działo w nocy?” | `journalctl`: `-u`, `-p`, `--since`, `-f`, `-b` |
| [3](#poziom-3--grep-w-plikach-konfiguracyjnych) | „gdzie to jest ustawione?” | `grep -r -n -i -v -E -A -B`, konfiguracja bez komentarzy |
| [4](#poziom-4--nowy-dysk) | „dokładamy dysk” | `lsblk`, LVM: `pvcreate`, `vgextend`, `lvcreate`, `lvextend`, `mkfs`, `fstab` |
| [5](#poziom-5--kończy-się-miejsce) | „dysk pełny w 95%” | `df`, `du`, `find -size`, `lsof +L1` – plik usunięty, a miejsce nie wróciło |
| [6](#poziom-6--usługa-nie-wstaje) | „usługa nie wstaje” | własna usługa systemd, `systemctl status`, `journalctl -u`, `daemon-reload` |
| [7](#poziom-7--coś-zjada-procesor) | „serwer muli” | `top`, `htop`, `ps --sort`, `kill`, load average |
| [8](#poziom-8--nowy-użytkownik-i-wspólny-katalog) | „nowy kolega w zespole” | `adduser`, grupy, `chmod`, `chown`, setgid, `sudo -l` |
| [9](#poziom-9--zadanie-co-noc-i-rotacja-logów) | „backup co noc i logi, które nie rosną w nieskończoność” | `cron`, `logrotate` |
| [10](#poziom-10--sprzątanie) | sprzątanie | powrót do snapshotu |

**Zasada na każdy poziom:** zanim naciśniesz Enter, powiedz sobie, czego się spodziewasz. Potem
porównaj z wynikiem.

---

## Przygotowanie

🪟 **VMware** (maszyna `monitoring` może działać, ale bezpieczniej ją wyłączyć):
1. *VM → Settings → Add… → Hard Disk → SCSI → Create a new virtual disk*.
2. Rozmiar **10 GB**, *Store virtual disk as a single file* → *Finish* → *OK*.
3. Włącz maszynę i zrób **snapshot** `przed-cwiczeniami-linux`.

🐧 `monitoring` – sprawdź, że system widzi nowy dysk:

```bash
lsblk
```

**Co powinieneś zobaczyć:** oprócz `sda` (40G) nowy dysk `sdb` (10G) **bez** partycji i bez punktu
montowania.

## Poziom 0 – co to za maszyna?

**Sytuacja:** pierwszy dzień w pracy, dostajesz dostęp do serwera. Zanim cokolwiek zmienisz,
musisz wiedzieć, co to za maszyna.

Ustal i zapisz w notatkach:

1. System i jądro: `hostnamectl`, `cat /etc/os-release`, `uname -r`.
2. Jak długo działa i jakie ma obciążenie: `uptime`.
3. Procesor i pamięć: `nproc`, `free -h`.
4. Dyski i miejsce: `lsblk`, `df -h`.
5. Adres i brama: `ip -br a`, `ip r`.
6. Co nasłuchuje na portach: `sudo ss -tulpn`.
7. Jakie usługi działają: `systemctl list-units --type=service --state=running`.

**Co powinieneś zobaczyć:** Ubuntu 26.04, 2 rdzenie, kilka GB RAM, `/` na LVM
(`ubuntu--vg-ubuntu--lv`), adres `192.168.180.54`, brama `192.168.180.2`; porty 22 (SSH) i 5000
(rejestr Dockera); usługi `ssh`, `docker`, `cron`, `rsyslog`…

**Sprawdź się:**
- Co oznaczają trzy liczby `load average` w `uptime`? Kiedy są niepokojące przy 2 rdzeniach?
- `free -h`: dlaczego `free` jest małe, a `available` duże? Czy to problem?
- Jaki proces słucha na porcie 5000 i skąd się wziął?
- Czym różni się `ss -tulpn` uruchomione z `sudo` i bez?

## Poziom 1 – kto próbował się zalogować?

**Sytuacja:** kierownik pyta: „czy ktoś próbował się włamać przez SSH?”.

1. 🪟 Zrób kilka nieudanych prób – z Windowsa, nieistniejący użytkownik (każdą przerwij Ctrl+C,
   jeśli zapyta o hasło):
   ```powershell
   ssh admin@192.168.180.54
   ssh root@192.168.180.54
   ssh test@192.168.180.54
   ```
2. 🐧 Log logowań na Ubuntu to `/var/log/auth.log` (Twoje konto jest w grupie `adm`, więc możesz go
   czytać bez `sudo`). Ostatnie wpisy:
   ```bash
   tail -n 20 /var/log/auth.log
   ```
3. Tylko nieudane próby:
   ```bash
   grep -E "Invalid user|Failed password|Connection closed by invalid user" /var/log/auth.log | tail
   ```
4. Ile ich było i z jakich adresów – policz sam. Podpowiedź: `grep -o`, wyrażenie na adres IP,
   potem `sort | uniq -c | sort -nr`.
5. Jakie nazwy użytkowników próbowano – zestaw je tak samo (podpowiedź: `awk` i numer pola albo
   `grep -oE "invalid user [^ ]+"`).
6. Udane logowania: `grep "Accepted" /var/log/auth.log | tail -5`. Bieżące sesje: `who`
   i `loginctl list-sessions`. Historia logowań: na starszych systemach `last -n 10`, ale
   **Ubuntu 26.04 nie ma już `last`** – zainstaluj następcę `sudo apt install wtmpdb` i użyj
   `wtmpdb last`.
7. Starsze wpisy są w `auth.log.1` (i `.gz`): przeszukaj wszystkie naraz – `zgrep`.

**Co powinieneś zobaczyć:** wpisy `Invalid user admin from 192.168.180.1`; licznik prób
z adresem `192.168.180.1` (Twój Windows widziany przez NAT VMware); udane logowania
`Accepted publickey for grzegorz`.

**Sprawdź się:**
- Dlaczego adres to `192.168.180.1`, a nie adres Twojego komputera w domu?
- Czym różni się `Invalid user` od `Failed password`? Dlaczego u nas nie ma `Failed password`?
- Co robi każdy element w `sort | uniq -c | sort -nr`? Dlaczego `uniq` potrzebuje `sort` przed sobą?
- Jakie narzędzie automatycznie blokuje adresy po wielu nieudanych próbach?

## Poziom 2 – logi systemowe: journalctl

**Sytuacja:** „w nocy coś się działo z serwerem – sprawdź”.

1. Cały dziennik od najnowszych: `journalctl -r`. Wyjście: `q`.
2. Tylko błędy i gorsze od ostatniego uruchomienia: `journalctl -b -p err`.
3. Logi jednej usługi: `journalctl -u ssh --since "1 hour ago"`, potem `journalctl -u docker -n 30`.
4. Przedział czasu: `journalctl --since "today 06:00" --until "today 08:00"`.
5. Na żywo: `journalctl -f -u ssh`, a w drugim oknie 🪟 zaloguj się ponownie `ssh monitoring`.
   Zobacz, jak wpis pojawia się od razu. Przerwij Ctrl+C.
6. Poprzednie uruchomienia: `journalctl --list-boots`, potem `journalctl -b -1 -n 20`.
7. Komunikaty jądra (dyski, sieć, pamięć): `sudo dmesg -T | tail -30`, `journalctl -k -b`.
8. Ile miejsca zajmuje dziennik: `journalctl --disk-usage`.
9. `grep` na dzienniku: `journalctl -b | grep -i -E "error|fail" | head`.

**Co powinieneś zobaczyć:** w `-p err` kilka wpisów (często drobne, np. o sprzęcie wirtualnym);
w kroku 5 wpis `Accepted publickey for grzegorz` w chwili logowania; lista uruchomień z datami;
w `dmesg` wykrycie dysku `sdb`.

**Sprawdź się:**
- Czym różni się `journalctl` od plików w `/var/log` (`syslog`, `auth.log`)? Skąd te same wpisy
  w obu miejscach?
- Co znaczą poziomy `-p` (`emerg` … `debug`)? Co pokaże `-p warning`?
- Dlaczego `journalctl -b -1` może nic nie pokazać na niektórych systemach?
- Jak znaleźć w logach moment, w którym system wykrył nowy dysk?

## Poziom 3 – grep w plikach konfiguracyjnych

**Sytuacja:** „sprawdź, czy SSH na pewno nie pozwala logować się hasłem i gdzie to jest ustawione”.

1. Szukaj ustawienia w głównym pliku i w katalogu z dodatkami:
   ```bash
   grep -n -i "PasswordAuthentication" /etc/ssh/sshd_config
   grep -rn -i "PasswordAuthentication" /etc/ssh/
   ```
2. Pokaż konfigurację **bez komentarzy i pustych linii**:
   ```bash
   grep -Ev "^\s*(#|$)" /etc/ssh/sshd_config
   ```
3. Co SSH **naprawdę** używa (po złożeniu wszystkich plików):
   ```bash
   sudo sshd -T | grep -i -E "passwordauthentication|permitrootlogin|pubkeyauthentication"
   ```
4. Kontekst wokół trafienia: `grep -n -B2 -A2 "Port" /etc/ssh/sshd_config`.
5. Znajdź wszystkie pliki w `/etc`, w których występuje adres `192.168.180.51`
   (podpowiedź: `-r`, `-l`, a błędy uprawnień schowaj przez `2>/dev/null`).
6. Policz linie z `deny` w regułach firewalla: `sudo ufw status | grep -ci deny`.

**Co powinieneś zobaczyć:** `PasswordAuthentication no` w pliku z katalogu
`/etc/ssh/sshd_config.d/` (wpisał go skrypt z Etapu 1), a w głównym pliku zakomentowane `#…`;
`sshd -T` – `passwordauthentication no`; adres mastera w `/etc/hosts`.

**Sprawdź się:**
- Dlaczego sam `grep` w `sshd_config` może wprowadzić w błąd? Co pokazuje `sshd -T`?
- Co znaczą `-r`, `-l`, `-n`, `-i`, `-v`, `-E`, `-c`, `-A`, `-B`?
- Co oznacza wyrażenie `^\s*(#|$)`?

## Poziom 4 – nowy dysk

**Sytuacja:** aplikacja potrzebuje osobnego miejsca na dane (`/data`), a przy okazji główny dysk
trzeba powiększyć o 3 GB. Na serwerze jest LVM.

**LVM w trzech słowach:** dyski fizyczne (**PV**) wrzucasz do wspólnej puli (**VG**), z puli wycinasz
„wirtualne partycje” (**LV**), które można później powiększać bez wyłączania serwera.

```
sda3 (PV) ─┐                         ┌─ ubuntu-lv (LV) → /       38G → 41G
           ├─▶ ubuntu-vg (VG, pula) ─┤
sdb  (PV) ─┘                         └─ data (LV)      → /data   5G
```

1. Rozpoznanie: `lsblk`, `sudo pvs`, `sudo vgs`, `sudo lvs`, `df -h /`.
2. Nowy dysk jako PV i dołączenie do puli:
   ```bash
   sudo pvcreate /dev/sdb
   sudo vgextend ubuntu-vg /dev/sdb
   sudo vgs
   ```
3. Nowy wolumen 5 GB na dane, system plików i montowanie:
   ```bash
   sudo lvcreate -n data -L 5G ubuntu-vg
   sudo mkfs.ext4 /dev/ubuntu-vg/data
   sudo mkdir /data
   sudo mount /dev/ubuntu-vg/data /data
   df -h /data
   ```
4. Montowanie na stałe – wpis w `/etc/fstab` **po UUID** (najpierw kopia pliku):
   ```bash
   sudo cp /etc/fstab /etc/fstab.bak
   sudo blkid /dev/ubuntu-vg/data
   echo "UUID=<UUID z blkid>  /data  ext4  defaults  0  2" | sudo tee -a /etc/fstab
   sudo umount /data
   sudo mount -a
   df -h /data
   ```
5. Powiększenie `/` o 3 GB **w trakcie pracy** (`-r` powiększa od razu system plików):
   ```bash
   sudo lvextend -r -L +3G /dev/ubuntu-vg/ubuntu-lv
   df -h /
   ```
6. Sprawdzenie `fstab` bez restartu: `sudo systemctl daemon-reload` i `sudo findmnt --verify`
   (powinno być `Success, no errors or warnings detected`). Potem ostateczny test – restart:
   `sudo reboot`, `ssh monitoring` i `df -h /data`.

**Co powinieneś zobaczyć:** w `vgs` po kroku 2 około 10 GB wolnego (`VFree`); `/data` ~4,9G;
`mount -a` bez błędów; `/` z 38G na ~41G; po restarcie `/data` zamontowany.

**Sprawdź się:**
- Po co `mount -a` przed restartem? Co by się stało przy literówce w `fstab` bez tego testu?
- Dlaczego w `fstab` UUID, a nie `/dev/sdb`?
- Co zrobiłbyś bez LVM (zwykła partycja)? Jakie polecenia?
- Dlaczego zmniejszyć system plików jest dużo trudniej niż powiększyć?
- Co jeszcze trzeba zrobić, gdy w VMware **powiększysz istniejący** dysk zamiast dodać nowy?

## Poziom 5 – kończy się miejsce

**Sytuacja:** monitoring zgłasza „dysk `/` zajęty w 90%”. Znajdź winnego.

1. Zasymuluj problem – duży plik logu i „zapomniany” plik w katalogu tymczasowym (`fallocate`
   rezerwuje miejsce od razu, bez zapisywania danych). Rozmiary dobierz do wolnego miejsca – po
   poziomie 4 `/` ma ~41G i ~27G wolnego, więc 15G + 8G daje ok. 90%:
   ```bash
   df -h /
   sudo fallocate -l 15G /var/log/aplikacja-debug.log
   sudo fallocate -l 8G /var/tmp/kopia-stara.tar
   df -h /
   ```
2. Gdzie jest najwięcej danych – schodź katalog po katalogu:
   ```bash
   sudo du -xh --max-depth=1 / 2>/dev/null | sort -h | tail
   sudo du -xh --max-depth=1 /var 2>/dev/null | sort -h | tail
   ```
3. Największe pliki w całym systemie:
   ```bash
   sudo find / -xdev -type f -size +500M -exec ls -lh {} \; 2>/dev/null
   ```
4. **Pułapka:** „usunąłem plik, a miejsce nie wróciło”. Uruchom program, który trzyma plik otwarty,
   i usuń plik:
   ```bash
   sudo bash -c 'exec 3</var/log/aplikacja-debug.log; sleep 3600' &
   sudo rm /var/log/aplikacja-debug.log
   df -h /
   ```
   Miejsce **nie** wróciło. Znajdź, kto trzyma usunięty plik:
   ```bash
   sudo lsof +L1
   ```
   Zatrzymaj ten proces (`sudo kill <PID>`) i sprawdź `df -h /` ponownie.
5. Usuń drugi plik i sprawdź miejsce. Dodatkowo: ile zajmuje dziennik i jak go przyciąć –
   `journalctl --disk-usage`, `sudo journalctl --vacuum-size=200M`.
6. Bonus: co jeszcze często zajmuje miejsce na serwerach – `docker system df`, `/var/cache/apt`
   (`sudo apt clean`), stare jądra (`sudo apt autoremove`).

**Co powinieneś zobaczyć:** `df` – `/` zajęty w ~90%; `du` prowadzi do `/var/log` i `/var/tmp`;
`find` pokazuje oba pliki; po `rm` miejsce nie wraca, `lsof +L1` pokazuje proces `sleep`
z plikiem `(deleted)`; po `kill` miejsce wraca.

**Sprawdź się:**
- Czym różnią się wyniki `df` i `du`? Kiedy się nie zgadzają?
- Dlaczego usunięcie pliku otwartego przez proces nie zwalnia miejsca?
- Jak w takiej sytuacji zwolnić miejsce **bez** zatrzymywania procesu (np. ważnej bazy danych)?
- Co znaczy `-x` w `du` i `-xdev` w `find`?
- Co się dzieje z serwerem, gdy `/` ma 100%? Jakie usługi padają pierwsze?

## Poziom 6 – usługa nie wstaje

**Sytuacja:** po wdrożeniu nowej wersji „aplikacja nie działa”. Aplikacja jest usługą systemd.

1. Utwórz prostą aplikację – skrypt, który co 5 sekund zapisuje znacznik czasu:
   ```bash
   sudo tee /usr/local/bin/licznik.sh >/dev/null <<'EOF'
   #!/bin/bash
   while true; do
     echo "licznik: $(date '+%H:%M:%S') wolne na /: $(df -h / | awk 'NR==2 {print $4}')"
     sleep 5
   done
   EOF
   sudo chmod +x /usr/local/bin/licznik.sh
   ```
2. Usługa systemd:
   ```bash
   sudo tee /etc/systemd/system/licznik.service >/dev/null <<'EOF'
   [Unit]
   Description=Licznik - cwiczenie z systemd
   After=network.target

   [Service]
   ExecStart=/usr/local/bin/licznik.sh
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target
   EOF
   sudo systemctl daemon-reload
   sudo systemctl enable --now licznik
   systemctl status licznik
   journalctl -u licznik -f
   ```
3. „Nowa wersja” z błędem – literówka w ścieżce. Wdróż i zobacz, co się dzieje:
   ```bash
   sudo sed -i 's#/usr/local/bin/licznik.sh#/usr/local/bin/licznk.sh#' /etc/systemd/system/licznik.service
   sudo systemctl restart licznik
   ```
   Przeczytaj uważnie, co wypisał `restart`, i zrób to, o co prosi.
4. Diagnoza **samodzielnie**: co mówi `systemctl status licznik`? Co mówi
   `journalctl -u licznik -n 20`? Znajdź przyczynę i napraw (pamiętaj o `daemon-reload`).
   Jeśli po naprawie usługa **dalej** nie wstaje – przeczytaj ostatnie linie dziennika jeszcze raz.
   Podpowiedź: `systemctl show -p StartLimitBurst -p StartLimitIntervalUSec licznik`
   i `systemctl reset-failed`.
5. Odporność: zabij proces usługi i zobacz, czy wstanie sam:
   ```bash
   sudo systemctl kill -s KILL licznik
   sleep 2; systemctl status licznik
   ```
6. Czy usługa wystartuje po restarcie maszyny: `systemctl is-enabled licznik`.

**Co powinieneś zobaczyć:** w kroku 2 `active (running)` i co 5 s nowa linia w dzienniku. W kroku 3
`restart` najpierw ostrzega, że plik się zmienił (`Run 'systemctl daemon-reload'`); po
`daemon-reload` w `status` – `status=203/EXEC`, w dzienniku `Unable to locate executable
'/usr/local/bin/licznk.sh'`. Po naprawie możesz trafić na `Start request repeated too quickly` –
wtedy `reset-failed`. Na końcu znowu `active (running)`.
W kroku 5 usługa startuje ponownie sama (nowy PID).

**Sprawdź się:**
- Po co `systemctl daemon-reload` po zmianie pliku `.service`? Co się stanie bez niego?
- Czym różni się `enable` od `start`? Co robi `enable --now`?
- Co znaczy `Restart=on-failure`? Kiedy usługa **nie** zostanie wznowiona?
- Gdzie systemd zapisał wyjście `echo` ze skryptu, skoro nie podaliśmy żadnego pliku logu?

## Poziom 7 – coś zjada procesor

**Sytuacja:** „serwer strasznie muli”.

1. Zasymuluj problem – dwa procesy, które zajmują po jednym rdzeniu:
   ```bash
   yes > /dev/null &
   yes > /dev/null &
   ```
2. Obejrzyj obciążenie: `uptime` (odczekaj minutę i powtórz), `top` (w środku: `P` – sortuj po CPU,
   `M` – po pamięci, `1` – każdy rdzeń osobno, `q` – wyjście), `htop`.
3. Najbardziej obciążające procesy bez interaktywnego programu:
   ```bash
   ps aux --sort=-%cpu | head -5
   ```
4. Kto uruchomił proces i od kiedy: `ps -o pid,user,lstart,cmd -p <PID>`.
5. Zakończ procesy łagodnie (`kill <PID>`), a gdyby nie chciały – siłą (`kill -9 <PID>`).
   Wszystkie naraz po nazwie: `pkill yes`.
6. Pamięć: `free -h`, `ps aux --sort=-%mem | head -5`. Czy system używa swapu? (`swapon --show`)

**Co powinieneś zobaczyć:** dwa procesy `yes` po ~100% CPU; `load average` rośnie w stronę 2,0;
w `top` `%Cpu(s)` prawie bez `id` (idle); po `pkill` obciążenie spada.

**Sprawdź się:**
- `load average` = 2,0 na maszynie z 2 rdzeniami – dużo czy mało? A na 16 rdzeniach?
- Czym różni się `kill` (SIGTERM) od `kill -9` (SIGKILL)? Dlaczego najpierw zwykły `kill`?
- Co oznaczają w `top` kolumny `us`, `sy`, `wa`, `id`? Na co wskazuje wysokie `wa`?
- Co robi jądro, gdy brakuje pamięci (OOM killer)? Gdzie to widać w logach?

## Poziom 8 – nowy użytkownik i wspólny katalog

**Sytuacja:** do zespołu dochodzi Anna. Ma mieć konto, dostęp do wspólnego katalogu zespołu,
ale **bez** uprawnień administratora.

1. Konto bez hasła (logowanie tylko kluczem – hasła w labie nie ustawiamy):
   ```bash
   sudo adduser --disabled-password --gecos "Anna Nowak" anna
   id anna
   ```
2. Grupa zespołu i wspólny katalog:
   ```bash
   sudo groupadd devops
   sudo usermod -aG devops anna
   sudo usermod -aG devops grzegorz
   sudo mkdir /srv/zespol
   sudo chown root:devops /srv/zespol
   sudo chmod 2770 /srv/zespol
   ls -ld /srv/zespol
   ```
3. Wyloguj się i zaloguj ponownie (żeby dostać nową grupę), potem utwórz plik w katalogu
   i sprawdź jego grupę: `touch /srv/zespol/plan.txt; ls -l /srv/zespol`.
4. Sprawdź, co Anna może: `sudo -u anna touch /srv/zespol/anna.txt`, `sudo -u anna ls /root`,
   `sudo -l -U anna`.
5. Gdzie system trzyma konta i grupy: `grep anna /etc/passwd`, `grep devops /etc/group`,
   `sudo grep anna /etc/shadow`.
6. Zablokowanie konta (np. ktoś odchodzi z firmy): `sudo usermod -L anna`, `sudo passwd -S anna`.
7. Kto ma uprawnienia administratora: `getent group sudo`.

**Co powinieneś zobaczyć:** `uid=1001(anna)`; katalog `drwxrws--- root devops`; nowy plik ma grupę
`devops` (nie `grzegorz`); Anna może pisać w `/srv/zespol`, nie może czytać `/root`;
`sudo -l -U anna` – brak uprawnień; w `/etc/shadow` hasło `!` (konto bez hasła / zablokowane).

**Sprawdź się:**
- Co oznacza `2770`? Co robi cyfra `2` (setgid) na katalogu?
- Dlaczego trzeba się wylogować po dodaniu do grupy?
- Co jest w `/etc/passwd`, a co w `/etc/shadow`? Dlaczego `shadow` czyta tylko root?
- Czym różni się `adduser` od `useradd`?
- Jak dać Annie prawo do restartu **tylko jednej** usługi przez `sudo`?

## Poziom 9 – zadanie co noc i rotacja logów

**Sytuacja:** „rób kopię katalogu zespołu co noc, a log kopii niech nie rośnie w nieskończoność”.

1. Skrypt kopii:
   ```bash
   sudo tee /usr/local/bin/kopia-zespol.sh >/dev/null <<'EOF'
   #!/bin/bash
   cel=/data/kopie/zespol-$(date +%F-%H%M).tar.gz
   mkdir -p /data/kopie
   tar czf "$cel" -C /srv zespol && echo "$(date '+%F %T') OK $cel" >> /var/log/kopia-zespol.log
   EOF
   sudo chmod +x /usr/local/bin/kopia-zespol.sh
   ```
2. Zadanie w cronie roota – na ćwiczenie **co minutę**, w praktyce np. `0 2 * * *` (2:00 w nocy):
   ```bash
   sudo crontab -e
   ```
   Dopisz linię: `* * * * * /usr/local/bin/kopia-zespol.sh`. Sprawdź: `sudo crontab -l`.
3. Po 2–3 minutach: `ls -lh /data/kopie`, `cat /var/log/kopia-zespol.log`,
   `grep CRON /var/log/syslog | tail -3`.
4. Rotacja logu – plik `/etc/logrotate.d/kopia-zespol`:
   ```bash
   sudo tee /etc/logrotate.d/kopia-zespol >/dev/null <<'EOF'
   /var/log/kopia-zespol.log {
       daily
       rotate 7
       compress
       missingok
       notifempty
   }
   EOF
   sudo logrotate -d /etc/logrotate.d/kopia-zespol
   sudo logrotate -f /etc/logrotate.d/kopia-zespol
   ls -l /var/log/kopia-zespol.log*
   ```
   Jeśli `-f` odmówi – przeczytaj komunikat, porównaj z `/etc/logrotate.conf` (`grep -n '^su'`)
   i napraw swój plik.
5. Wyłącz zadanie co minutę (usuń linię w `sudo crontab -e`).

**Co powinieneś zobaczyć:** co minutę nowy plik `zespol-….tar.gz` i linia `OK` w logu; w `syslog`
wpisy `CRON[…]: (root) CMD (/usr/local/bin/kopia-zespol.sh)`; `logrotate -d` opisuje, co **by**
zrobił; `-f` najpierw odmawia (`insecure permissions`), a po naprawie tworzy
`kopia-zespol.log.1.gz`.

**Sprawdź się:**
- Co znaczy każde z pięciu pól w `0 2 * * *`? Jak zapisać „w dni robocze o 6:30”?
- Dlaczego skrypt w cronie ma pełne ścieżki? Czym środowisko crona różni się od Twojej sesji?
- Co robi `logrotate -d`, a co `-f`? Kto uruchamia logrotate codziennie?
- Czym jest `systemd timer` i dlaczego coraz częściej zastępuje crona?

## Poziom 10 – sprzątanie

Najprościej: 🪟 VMware → *Snapshot Manager* → `przed-cwiczeniami-linux` → *Go To*. Maszyna wraca
do stanu sprzed ćwiczeń (z nowym, pustym dyskiem `sdb`).

Ręcznie – kolejność odwrotna niż przy tworzeniu:

```bash
sudo crontab -r                                   # usuwa CAŁY crontab roota – był pusty przed ćwiczeniami
sudo rm /etc/logrotate.d/kopia-zespol /usr/local/bin/kopia-zespol.sh /var/log/kopia-zespol.log*
sudo systemctl disable --now licznik
sudo rm /etc/systemd/system/licznik.service /usr/local/bin/licznik.sh
sudo systemctl daemon-reload
sudo deluser --remove-home anna && sudo groupdel devops && sudo rm -rf /srv/zespol
sudo umount /data && sudo cp /etc/fstab.bak /etc/fstab
sudo lvremove ubuntu-vg/data
```

Powiększonego `/` nie da się łatwo cofnąć (ext4 nie zmniejsza się w trakcie pracy), a `sdb` jest
już jego częścią – dlatego snapshot jest lepszą drogą.

## Ściągawka

| Sytuacja | Polecenia |
|---|---|
| co to za maszyna | `hostnamectl`, `uptime`, `free -h`, `df -h`, `lsblk`, `ip -br a`, `ss -tulpn` |
| logowania | `grep … /var/log/auth.log`, `zgrep`, `loginctl list-sessions`, `wtmpdb last` |
| logi | `journalctl -u USŁUGA -p err --since … -f -b`, `dmesg -T` |
| konfiguracja | `grep -rn`, `grep -Ev "^\s*(#\|$)"`, `sshd -T` |
| dysk | `pvcreate`, `vgextend`, `lvcreate`, `lvextend -r`, `mkfs.ext4`, `blkid`, `/etc/fstab`, `mount -a` |
| miejsce | `du -xh --max-depth=1 \| sort -h`, `find -size +500M`, `lsof +L1` |
| usługi | `systemctl status/start/enable/daemon-reload/reset-failed`, `journalctl -u` |
| procesy | `top`, `ps aux --sort=-%cpu`, `kill`, `pkill` |
| użytkownicy | `adduser`, `usermod -aG`, `chmod 2770`, `sudo -l -U` |
| harmonogram | `crontab -e/-l`, `logrotate -d/-f` |

Wszystkie polecenia labu: [ściągawka poleceń](../sciagawka-polecen.md).
