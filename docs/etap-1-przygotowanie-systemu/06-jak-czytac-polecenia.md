# Etap 1 – jak czytać polecenia ze zrzutów (słowniczek składni)

Na zrzutach w rozwiązaniach ([admin Linux](03-cwiczenia-admin-linux-rozwiazania.md),
[nginx i bazy](05-cwiczenia-nginx-bazy-rozwiazania.md)) wiele poleceń jest połączonych w jedną
linię: `grep … | sort | uniq -c | sort -nr`, `2>/dev/null`, `$(…)`, `awk '{print $1}'`. Tu jest
wyjaśniony każdy element, który się tam pojawia, z przykładami z labu. Pod każdym zrzutem jest
rozpiska jego poleceń, która odsyła do tego słowniczka.

**Jak się uczyć:** weź długie polecenie i uruchamiaj je **kawałek po kawałku** – najpierw sam
`grep`, potem `grep … | sort`, potem z `uniq -c`. Po każdym kroku zobaczysz, co zmienił następny
element.

## Spis treści

1. [Znak zachęty i budowa polecenia](#1-znak-zachęty-i-budowa-polecenia)
2. [`sudo`](#2-sudo)
3. [Cudzysłowy i znaki specjalne](#3-cudzysłowy-i-znaki-specjalne)
4. [Łączenie poleceń: `;` `&&` `||` `|`](#4-łączenie-poleceń----)
5. [Przekierowania: `>` `>>` `<` `2>` `2>&1` `/dev/null` `tee`](#5-przekierowania-i-devnull)
6. [Zmienne i podstawianie: `$x` `$(…)` `$((…))` `$?`](#6-zmienne-i-podstawianie-x---)
7. [Wiele linii naraz: heredoc `<<'EOF'`](#7-wiele-linii-naraz-heredoc-eof)
8. [Pętle i warunki](#8-pętle-i-warunki)
9. [Przycinanie i liczenie wyników](#9-przycinanie-i-liczenie-wyników)
10. [`grep` i wyrażenia regularne](#10-grep-i-wyrażenia-regularne)
11. [`awk`](#11-awk)
12. [`sed`](#12-sed)
13. [`find`](#13-find)
14. [`curl`](#14-curl)
15. [`systemctl` i `journalctl`](#15-systemctl-i-journalctl)
16. [`psql` i `mariadb`](#16-psql-i-mariadb)

## 1. Znak zachęty i budowa polecenia

```
grzegorz@monitoring:~$ df -h /
└──┬───┘ └───┬────┘ │ │ └─┬──┘
 konto    maszyna   │ │   polecenie, które wpisujesz
                    │ └ $ – zwykły użytkownik (# – root)
                    └ ~ – bieżący katalog (~ = katalog domowy /home/grzegorz)
```

Na zrzutach linia ze znakiem zachęty (pogrubiona) to **polecenie**, linie pod nią to **wynik**.
`PS C:\Users\User>` to PowerShell na Windowsie, `grzegorz@k3s-master:~$` – polecenie wpisane na
innej maszynie.

Polecenie = **program**, **opcje** (zaczynają się od `-` lub `--`) i **argumenty** (na czym
działać):

```
ls   -l -h   /var/log
│    └─┬─┘   └──┬───┘
│   opcje     argument
program
```

- Krótkie opcje można sklejać: `ls -lh` = `ls -l -h`, `ss -tulpn` = `-t -u -l -p -n`.
- Długie opcje mają dwa myślniki: `--human-readable`, `--no-pager`, `--since '10 min ago'`.
- Opcja może mieć wartość: `head -n 5` (albo `head -5`), `cut -c1-130`, `-o /dev/null`.
- Co znaczy opcja: `man ls` (podręcznik, wyjście `q`) albo `ls --help`.

## 2. `sudo`

| Zapis | Znaczenie |
|---|---|
| `sudo polecenie` | uruchom jako **root** (administrator). Potrzebne do zmian w systemie i czytania chronionych plików |
| `sudo -u postgres psql` | uruchom jako **inny użytkownik** (`-u` = *user*), tu `postgres` |
| `sudo -l -U anna` | pokaż, co użytkownik `anna` może robić przez `sudo` (`-l` = *list*) |

Pułapka: `sudo` działa tylko na **pierwsze** polecenie. W `sudo grep … | sort` root uruchamia
tylko `grep`; `sort` działa jako Ty (i to wystarczy, bo dostaje już gotowy tekst).

## 3. Cudzysłowy i znaki specjalne

Powłoka (bash) przed uruchomieniem polecenia **przetwarza** linię: dzieli ją na słowa po
spacjach, zamienia `$zmienna`, `*`, `~`. Cudzysłowy to kontrolują:

| Zapis | Co robi powłoka | Przykład |
|---|---|---|
| `'tekst'` | nic – tekst idzie do programu **dokładnie** taki | `grep -E 'error\|fail'`, `awk '{print $1}'` – `$1` ma dostać `awk`, nie bash |
| `"tekst"` | podstawia `$zmienne` i `$(…)`, reszta bez zmian | `echo "kod: $?"` |
| bez cudzysłowów | dzieli na słowa, rozwija `*`, `~`, `$` | `ls /var/log/auth.log*` |
| `\` przed znakiem | ten jeden znak traktuj dosłownie | `\;` w `find`, `\$` |
| `\` na końcu linii | polecenie ciągnie się w następnej linii | długie `openssl x509 … \` |

Dlatego wzorce dla `grep`, `awk`, `sed` prawie zawsze są w `'…'`. Gdy w środku potrzebny jest
apostrof (SQL: `'Lab-app-123'`), całość bierze się w `"…"`:
`psql -c "CREATE USER app WITH PASSWORD 'Lab-app-123';"`.

Inne znaki: `*` – dowolne znaki w nazwie pliku (`auth.log*` = `auth.log`, `auth.log.1`,
`auth.log.2.gz`), `~` – katalog domowy, `#` – komentarz do końca linii, `&` na końcu – uruchom
w tle.

## 4. Łączenie poleceń: `;` `&&` `||` `|`

| Zapis | Znaczenie | Przykład ze zrzutów |
|---|---|---|
| `a ; b` | wykonaj `a`, potem `b` – **zawsze** | `systemctl is-active nginx; systemctl is-enabled nginx` |
| `a && b` | `b` tylko gdy `a` się **udało** | `sudo nginx -t && sudo systemctl reload nginx` – przeładuj tylko po udanym teście |
| `a \|\| b` | `b` tylko gdy `a` się **nie udało** | `pgrep -a yes \|\| echo 'brak procesow yes'` |
| `a \| b` | **potok**: wynik `a` staje się wejściem `b` | `grep 'Accepted' auth.log \| tail -3` |

„Udało się” = program zakończył się **kodem wyjścia** `0`. Każdy inny kod (1, 2, 7, 60…) to
błąd. Kod ostatniego polecenia jest w `$?` (patrz [punkt 6](#6-zmienne-i-podstawianie-x---)).

**Potok czytaj od lewej do prawej jak taśmę w fabryce:**

```
grep 'Invalid user' /var/log/auth.log | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -nr
└──────────┬────────────────────────┘   └──────────┬──────────┘   └─┬┘   └───┬──┘   └──┬───┘
  linie z nieudanym logowaniem           wytnij „from ADRES”     ułóż    policz    największe
                                                                        powtórzenia  na górę
```

## 5. Przekierowania i /dev/null

Każdy program ma trzy strumienie: **wejście** (0, *stdin*), **wyjście** (1, *stdout* – wynik) i
**błędy** (2, *stderr* – komunikaty o błędach). Na ekranie wyjście i błędy się mieszają, ale to
dwa osobne kanały.

| Zapis | Znaczenie | Przykład |
|---|---|---|
| `> plik` | wynik do pliku (plik **nadpisany**) | `head -c 3M /dev/urandom > /tmp/raport.pdf` |
| `>> plik` | wynik **dopisany** na końcu pliku | `echo "… OK" >> /var/log/kopia-zespol.log` |
| `< plik` | plik jako wejście programu | `sudo mariadb blog < kopia.sql` |
| `2>/dev/null` | błędy wyrzuć | `sudo find / … 2>/dev/null` – bez setek „Permission denied” |
| `2>&1` | błędy wyślij tam, gdzie wynik | `apt-get install … 2>&1 \| tail -3` – żeby `tail` dostał też błędy |
| `>/dev/null` | wynik wyrzuć (interesuje nas tylko kod albo błąd) | `mariadb-admin ping >/dev/null 2>&1` |
| `\| tee plik` | wynik do pliku **i** na ekran | `echo 'linia' \| sudo tee plik` |
| `\| tee -a plik` | jak wyżej, ale dopisz (`-a` = *append*) | `echo 'UUID=…' \| sudo tee -a /etc/fstab` |

`/dev/null` to „czarna dziura” – wszystko, co tam trafi, znika.

**Dlaczego `echo … | sudo tee plik`, a nie `sudo echo … > plik`?** Przekierowanie `>` robi
**Twoja** powłoka, jeszcze przed `sudo` – jako zwykły użytkownik nie możesz pisać do `/etc`.
`tee` uruchomione przez `sudo` pisze już jako root. `>/dev/null` po `tee` ukrywa powtórzenie
tekstu na ekranie.

## 6. Zmienne i podstawianie: `$x` `$(…)` `$((…))` `$?`

| Zapis | Znaczenie | Przykład |
|---|---|---|
| `$nazwa`, `"$nazwa"` | wartość zmiennej | `for c in …; do … $c …; done` |
| `NAZWA=wartość polecenie` | zmienna **tylko dla tego jednego** polecenia | `PGPASSWORD='Lab-app-123' psql …` – `psql` bierze hasło ze zmiennej |
| `export NAZWA=wartość` | zmienna dla wszystkich kolejnych poleceń w sesji | `export PGPASSWORD=…` |
| `$(polecenie)` | wstaw **wynik** polecenia w to miejsce | `sklep-$(date +%F).dump` → `sklep-2026-11-04.dump` |
| `$((wyrażenie))` | arytmetyka | `$((30*24*3600))` → `2592000` (30 dni w sekundach) |
| `$?` | kod wyjścia **ostatniego** polecenia | `openssl … -checkend …; echo "kod: $?"` |
| `${PIPESTATUS[0]}` | kod wyjścia **pierwszego** polecenia w potoku (`$?` dałby kod ostatniego) | `sprawdz-uslugi.sh \| grep …; echo ${PIPESTATUS[0]}` |
| `${p%\%}` | wartość zmiennej bez końcowego `%` | `85%` → `85` w skrypcie kontrolnym |

Przykład złożony z poziomu 5 nginx:
```bash
ps -o pid,user,etime,cmd -p $(sudo fuser /var/lib/dpkg/lock-frontend 2>/dev/null)
#                            └──────────── najpierw to: PID procesu trzymającego plik ───┘
# potem ps pokazuje szczegóły tego PID
```

`date` z formatem: `+%F` → `2026-11-04`, `+%T` → `17:03:23`, `+%H%M` → `1703`, `+%s` →
sekundy od 1.01.1970 (do odejmowania dat).

## 7. Wiele linii naraz: heredoc `<<'EOF'`

```bash
sudo tee /etc/logrotate.d/kopia-zespol >/dev/null <<'EOF'
/var/log/kopia-zespol.log {
    daily
}
EOF
```

`<<'EOF'` znaczy: „wszystko od następnej linii aż do linii `EOF` podaj programowi jako wejście”.
Tu – do `tee`, które zapisuje to do pliku. `EOF` to tylko umówione słowo-znacznik. Apostrofy
w `'EOF'` wyłączają podstawianie `$…` w środku – plik dostaje `$uri` dosłownie (ważne
w konfiguracji nginx). Bez apostrofów bash zamieniłby `$uri` na pustą zmienną.

## 8. Pętle i warunki

```bash
for s in sklep blog; do sudo mkdir -p /var/www/$s; done
#   │       └─ lista wartości        └─ dla każdej: s=sklep, potem s=blog
#   └ nazwa zmiennej
for i in $(seq 1 12); do curl …; done     # seq 1 12 = liczby 1..12 – powtórz 12 razy
```

| Zapis | Znaczenie |
|---|---|
| `[ "$kod" = 200 ]` | test: czy tekst równy (`[` to polecenie testujące, spacje są obowiązkowe) |
| `[ "$p" -lt 85 ]` | liczba mniejsza niż (`-lt` *less than*, `-gt` *greater than*, `-eq` równa) |
| `[ -n "$x" ]` / `[ -f plik ]` | tekst niepusty / plik istnieje |
| `warunek && ok \|\| zle` | skrót: jeśli warunek, to `ok`, inaczej `zle` |
| `timeout 9 polecenie` | przerwij polecenie po 9 sekundach |
| `sleep 3` | czekaj 3 sekundy |
| `time polecenie` | zmierz, ile trwało (`real` – czas zegarowy) |

## 9. Przycinanie i liczenie wyników

Na zrzutach wyniki są często przycięte, żeby zmieściły się na ekranie:

| Polecenie | Co robi | Przykład |
|---|---|---|
| `head -5`, `head -n 5` | pierwsze 5 linii | `ps aux --sort=-%cpu \| head -5` |
| `tail -3` | ostatnie 3 linie | `tail -3 /etc/fstab` |
| `tail -n +2` | od 2. linii do końca (pomiń nagłówek) | `df --output=… \| tail -n +2` |
| `tail -f plik` | pokazuj nowe linie na żywo | `sudo tail -f /var/log/nginx/error.log` |
| `cut -c1-130` | tylko znaki 1–130 każdej linii (obcina długie linie) | prawie każdy zrzut z logami |
| `cut -d: -f1-3` | podziel linię po `:` i weź pola 1–3 | `anna:!:20761` z `/etc/shadow` |
| `cut -d= -f2` | weź to, co po `=` | `notAfter=Nov 4…` → `Nov 4…` |
| `wc -l` | policz linie | `zgrep … \| wc -l` |
| `wc -c plik` | policz bajty | pusty `error.log` → `0` |
| `sort` | ułóż alfabetycznie | |
| `sort -n` / `-h` / `-r` | liczbowo / „ludzko” (`4G` > `900M`) / odwrotnie | `du … \| sort -h` |
| `sort -u` | ułóż i usuń powtórzenia | |
| `uniq -c` | sklej **sąsiednie** identyczne linie i policz je (dlatego przed nim `sort`) | `sort \| uniq -c` |
| `column -t` | wyrównaj kolumny | `df … \| awk … \| column -t` |
| `basename /ścieżka/plik` | sama nazwa pliku | |
| `zcat plik.gz`, `zgrep` | `cat`/`grep` na spakowanym pliku | `zcat kopia-zespol.log.1.gz` |

## 10. `grep` i wyrażenia regularne

`grep WZORZEC plik` – linie, w których jest wzorzec. Opcje używane na zrzutach:

| Opcja | Znaczenie |
|---|---|
| `-i` | bez rozróżniania wielkich i małych liter |
| `-v` | odwrotnie – linie **bez** wzorca |
| `-c` | tylko liczba pasujących linii |
| `-n` | z numerami linii |
| `-o` | wypisz tylko **pasujący fragment**, nie całą linię |
| `-E` | rozszerzone wyrażenia: działają `\|`, `+`, `?`, `( )` bez `\` |
| `-r` | szukaj w katalogu i podkatalogach |
| `-l` | tylko nazwy plików z trafieniem |
| `-h` | bez nazw plików przy wielu plikach |
| `-A 2` / `-B 2` | dodatkowo 2 linie **po** / **przed** trafieniem |
| `-m1` | zakończ po pierwszym trafieniu |
| `-P` | wyrażenia w stylu Perla (tu: `\K` – „to, co przed, nie wypisuj”) |

Wyrażenia regularne – mini-słownik:

| Znak | Znaczenie | Przykład |
|---|---|---|
| `^` | początek linii | `'^bind-address'` – linia zaczyna się od `bind-address` |
| `$` | koniec linii | `'^\s*(#\|$)'` |
| `.` | dowolny jeden znak | `'<title>.*</title>'` |
| `*` | poprzedni znak 0 lub więcej razy | `.*` – cokolwiek |
| `+` | poprzedni znak 1 lub więcej razy (z `-E`) | `[0-9.]+` – ciąg cyfr i kropek (adres IP) |
| `[0-9.]` | jeden znak z zestawu | cyfra albo kropka |
| `[^ ]` | jeden znak **spoza** zestawu | `[^ ]+` – ciąg znaków bez spacji (jedno słowo) |
| `\s` | biały znak (spacja, tabulator) | |
| `a\|b` | `a` **albo** `b` | `'error\|fail'` |
| `( )` | grupa | `'(invalid\|authenticating) user'` |
| `\b` | granica słowa | `'sd[ab]\b'` |
| `\.` | dosłowna kropka (sama `.` = dowolny znak) | `'\.env'` |
| `.\{0,55\}` | od 0 do 55 dowolnych znaków | |

Przykład: `grep -oE 'Invalid user [^ ]+'` – wypisz tylko fragmenty „Invalid user” + spacja +
jedno słowo (nazwa konta).

## 11. `awk`

`awk` dzieli każdą linię na **pola** (domyślnie po spacjach) i robi coś z każdą linią. Program
w `'{…}'`, pola to `$1`, `$2`…, `$0` – cała linia, `NF` – liczba pól, `NR` – numer linii.

```
192.168.180.52 - - [04/Nov/2026:17:20:57 +0100] "GET / HTTP/1.1" 200 26 "-" "curl/8.18.0"
      $1       $2 $3          $4            $5    $6  $7    $8    $9  $10 $11     $12
```

| Zapis | Znaczenie |
|---|---|
| `awk '{print $1}'` | wypisz pierwsze pole (adres klienta) |
| `awk '{print $5, $7, $9}'` | pola 5, 7 i 9 rozdzielone spacją |
| `awk '$9 >= 400'` | tylko linie, w których pole 9 (kod) ≥ 400 – sam warunek bez `{…}` wypisuje całą linię |
| `awk '$9 == 404 {print $7}'` | dla linii z kodem 404 wypisz pole 7 (adres strony) |
| `awk 'NR>1 {print $9}'` | od drugiej linii (pomiń nagłówek) |
| `awk -F'"' '{print $6}'` | dziel po cudzysłowie zamiast spacji – pole 6 to `User-Agent` |
| `awk -F: '…'` | dziel po dwukropku |

## 12. `sed`

`sed` to edytor strumieniowy – zmienia tekst bez otwierania edytora. Na zrzutach głównie
**zamiana w pliku**:

```
sudo sed -i 's#root /var/www/html;#root /var/www/html#' /etc/nginx/sites-available/default
          │  │└──────┬──────────┘└───────┬──────────┘
          │  │     szukaj               zamień na
          │  └ s = substitute (zamień); # to separator (zwykle /, ale ścieżki zawierają /)
          └ -i = zmień plik na miejscu (bez -i tylko wypisze wynik na ekran)
```

| Zapis | Znaczenie |
|---|---|
| `s/stare/nowe/` | zamień pierwsze wystąpienie w każdej linii (`s/…/…/g` – wszystkie) |
| `s#^    daily#    su root adm\n    daily#` | `^` – tylko na początku linii; `\n` w zamianie – nowa linia (dopisanie linii przed `daily`) |
| `s#…html$#…html;#` | `$` – tylko na końcu linii |
| `sed -n '3p'` | wypisz tylko 3. linię (`-n` – nie wypisuj reszty, `p` – *print*) |

Przed `sed -i` na ważnym pliku zrób kopię (`sudo cp plik plik.bak`).

## 13. `find`

```
sudo find / -xdev -type f -size +500M -exec ls -lh {} \; 2>/dev/null
          │   │      │       │          └─────┬──────┘
          │   │      │       │        dla każdego znalezionego pliku uruchom ls -lh,
          │   │      │       │        {} = nazwa pliku, \; = koniec polecenia
          │   │      │       └ większe niż 500 MB
          │   │      └ tylko zwykłe pliki (nie katalogi)
          │   └ nie wchodź na inne systemy plików (/boot, /data, /proc)
          └ szukaj od /
```

| Zapis | Znaczenie |
|---|---|
| `-name "*.sql.gz"` | nazwa pasuje do wzorca |
| `-mtime +7` | zmieniony **więcej niż 7 pełnych dób** temu (`-mtime -1` – w ostatniej dobie) |
| `-size +1k` | większy niż 1 KB |
| `-print -delete` | wypisz i usuń |

## 14. `curl`

| Opcja | Znaczenie |
|---|---|
| `-s` | cicho – bez paska postępu |
| `-S` | z `-s`: mimo to pokaż błędy |
| `-o /dev/null` | treść strony wyrzuć |
| `-w '%{http_code}\n'` | wypisz kod odpowiedzi (`\n` – nowa linia); `%{time_total}` – czas |
| `-H 'Host: sklep.lab'` | dodaj nagłówek – udajemy, że wpisano adres `sklep.lab` |
| `-I` | tylko nagłówki odpowiedzi (`HTTP/1.1 301`, `Location:`) |
| `-v` | szczegóły połączenia (`Trying [::1]:80…`) – idą na *stderr*, stąd `2>&1` |
| `-L` | idź za przekierowaniami (301 → nowy adres) |
| `-m 5` | przerwij po 5 sekundach |
| `--resolve nazwa:port:IP` | „ta nazwa to ten adres” – zamiast DNS i pliku `hosts` |
| `--cacert ca.crt` | ufaj certyfikatom podpisanym przez to CA |
| `-k` | nie sprawdzaj certyfikatu (tylko do testów!) |
| `-u user:hasło` | logowanie `basic auth` |
| `--data-binary @plik` | wyślij plik (POST); `@` = „treść z pliku” |
| `-A 'tekst'` | ustaw `User-Agent` (przedstaw się jako inny program) |
| `-X POST` | metoda HTTP |

Kody wyjścia `curl` (nie mylić z kodem HTTP): `0` OK, `7` nie da się połączyć, `28` przekroczony
czas, `60` certyfikat niezaufany.

## 15. `systemctl` i `journalctl`

| Polecenie | Znaczenie |
|---|---|
| `systemctl status X --no-pager` | stan usługi; `--no-pager` – wypisz całość, nie otwieraj przeglądarki tekstu |
| `systemctl is-active X` / `is-enabled X` | jedno słowo: `active`/`inactive`/`failed`; `enabled`/`disabled` |
| `systemctl start/stop/restart/reload X` | uruchom / zatrzymaj / zatrzymaj i uruchom / wczytaj konfigurację |
| `systemctl enable --now X` | włącz przy starcie systemu i uruchom teraz |
| `systemctl show -p MainPID -p NRestarts X` | wybrane właściwości (`-p` = *property*) |
| `systemctl list-units --type=service --state=running` | lista działających usług |
| `systemd-run --unit=nazwa polecenie` | uruchom polecenie jako tymczasową usługę w tle |
| `journalctl -u X` | dziennik usługi (`-u` = *unit*) |
| `-n 20` / `-f` / `-b` / `-k` | ostatnie 20 linii / na żywo / od startu systemu / tylko jądro |
| `-p err` | tylko błędy i poważniejsze |
| `--since '10 min ago'`, `--since '-1min'` | od chwili w przeszłości |

## 16. `psql` i `mariadb`

| Zapis | Znaczenie |
|---|---|
| `psql -h localhost -U app sklep` | połącz przez TCP (`-h` *host*) jako rola `app` (`-U` *user*) z bazą `sklep` |
| `psql … -c 'select 1;'` | wykonaj jedno polecenie SQL i wyjdź (`-c` *command*); kilka `-c` – po kolei |
| `psql -t` / `-tc` | sam wynik, bez nagłówków (`-t` *tuples only*) |
| `$$host$$` | w PostgreSQL: tekst jak `'host'` – używane, bo całe polecenie jest już w apostrofach |
| `\du`, `\di+` | polecenia `psql` (nie SQL): role, indeksy z rozmiarami |
| `mariadb -h 127.0.0.1 -u blog -p'haslo' blog` | host, użytkownik, hasło (**bez spacji** po `-p`), baza |
| `mariadb -e '…'` | wykonaj SQL i wyjdź (`-e` *execute*) |
| `\G` na końcu SQL | wynik pionowo (pole pod polem) zamiast tabeli |

SQL na zrzutach: `select kolumny from tabela where warunek order by kolumna desc` – „pokaż …
z … gdzie … posortuj malejąco”; `group by` – grupuj i licz (`count(*)`); `as nazwa` – nazwa
kolumny w wyniku; `left(query,30)` – pierwsze 30 znaków.
