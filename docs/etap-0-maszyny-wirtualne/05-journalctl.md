# journalctl – dziennik systemu Linux

`journalctl` czyta **dziennik systemd** (*journal*): jedno miejsce, do którego trafiają komunikaty jądra, usług
(`k3s`, `ssh`, `nginx`…), `sudo` i logowań. To linuksowy odpowiednik dziennika zdarzeń Windows
([`Get-WinEvent`](04-get-winevent.md)). Przykład użycia w praktyce: kroki 9–13
[diagnozy zawieszenia hosta](03-diagnoza-zawieszenia-hosta.md#krok-9--uruchomienia-mastera-od-środka--k3s-master).

🐧 Polecenia wpisujesz **na maszynie** (np. `ssh k3s-master`). Wyniki w tym pliku pochodzą z `k3s-master`
(06.11.2026).

**Uprawnienia:** użytkownik z grupy `adm` (pierwszy użytkownik Ubuntu, na maszynach labu – `grzegorz`) czyta cały
dziennik bez `sudo`. Inny użytkownik bez `sudo` zobaczy tylko własne wpisy. Sprawdzisz to poleceniem `id -nG`.

---

## 1. Gdzie jest dziennik i ile zajmuje

```bash
journalctl --disk-usage
```

```text
Archived and active journals take up 89.1M in the file system.
```

- Dziennik leży w `/var/log/journal/` w plikach binarnych – **nie** czytasz go `cat`, tylko `journalctl`.
- Katalog `/var/log/journal` istnieje = dziennik jest **trwały** (przetrwa restart). Bez niego systemd trzyma
  dziennik tylko w pamięci (`/run/log/journal`) i po restarcie nie ma czego oglądać.
- Ustawienia: `/etc/systemd/journald.conf` (`Storage=`, `SystemMaxUse=` – maksymalny rozmiar). Gdy dziennik
  przekroczy limit, najstarsze wpisy są usuwane – jak `Circular` w Windows.
- Ręczne przycięcie: `sudo journalctl --vacuum-size=200M` albo `--vacuum-time=2weeks`.

---

## 2. Podstawy – co i ile pokazać

| Polecenie | Co robi |
|---|---|
| `journalctl` | **cały** dziennik od najstarszego, w przeglądarce `less` (strzałki, `q` – wyjście) |
| `journalctl -n 20` | 20 ostatnich wpisów |
| `journalctl -e` | otwórz od **końca** (`e` = end) |
| `journalctl -r` | odwrotnie – najnowsze na górze (`r` = reverse) |
| `journalctl -f` | **na żywo**, nowe wpisy pojawiają się na bieżąco; `Ctrl+C` kończy (`f` = follow, jak `tail -f`) |
| `--no-pager` | wypisz wszystko od razu, bez `less` – potrzebne, gdy wynik idzie do `grep` albo do pliku |

```bash
journalctl -n 3 --no-pager
```

Jedna linia wpisu:

```text
Nov 06 09:04:33 k3s-master k3s[1360]: time="…" level=info msg="COMPACT …"
│               │          │    │     └ treść
│               │          │    └ PID procesu
│               │          └ kto zapisał (usługa / program)
│               └ nazwa maszyny
└ czas
```

---

## 3. Filtry – najważniejsza część

Filtry łączą się przez **„i”**: `journalctl -u k3s -p err --since today` = usługa k3s **i** błędy **i** od dziś.

### Usługa: `-u`

```bash
journalctl -u k3s -n 3 --no-pager -o short-iso
```

```text
2026-11-06T09:04:33+01:00 k3s-master k3s[1360]: time="2026-11-06T09:04:33+01:00" level=info msg="COMPACT compactRev=440137 …"
```

`-u` (*unit*) – jedna usługa systemd. Nazwy: `k3s` (master), `k3s-agent` (workery), `ssh`, `docker`,
`containerd`, `nginx`. Lista usług: `systemctl list-units --type=service`. Kilka naraz: `-u k3s -u ssh`.

### Waga: `-p`

| `-p` | Poziom | Windows `Level` |
|---|---|---|
| `0` / `emerg` | system bezużyteczny | – |
| `1` / `alert` | natychmiastowa akcja | – |
| `2` / `crit` | krytyczny | 1 |
| `3` / `err` | błąd | 2 |
| `4` / `warning` | ostrzeżenie | 3 |
| `5` / `notice` | ważna informacja | – |
| `6` / `info` | informacja | 4 |
| `7` / `debug` | szczegóły dla programisty | – |

`-p err` = **błąd i wszystko gorsze** (0–3). Tylko jeden poziom: `-p err..err`.

```bash
journalctl -p err --since today --no-pager
```

### Czas: `--since` / `--until`

```bash
journalctl --since "2026-11-05 19:50" --until "2026-11-05 20:10"
journalctl --since "1 hour ago"
journalctl --since today          # też: yesterday, "-2d", "-30min"
```

### Uruchomienie: `-b`

```bash
journalctl --list-boots           # lista: IDX, BOOT ID, pierwszy i ostatni wpis
journalctl -b                     # bieżące uruchomienie (= -b 0)
journalctl -b -1                  # poprzednie
journalctl -b -2 -n 40            # 40 ostatnich wpisów sprzed dwóch restartów
```

Po awarii **zawsze** zaczynaj od `--list-boots`: kolumna `LAST ENTRY` mówi, kiedy system ostatni raz coś zapisał,
a numer `IDX` wskazuje uruchomienie, w którym była awaria. Wynik z labu:
[krok 9](03-diagnoza-zawieszenia-hosta.md#krok-9--uruchomienia-mastera-od-środka--k3s-master).

### Jądro: `-k`

```bash
journalctl -k -b -2               # komunikaty jądra z uruchomienia -2 (to co dmesg, ale z dowolnego uruchomienia)
```

`dmesg` pokazuje tylko bieżące uruchomienie i znika po restarcie. `journalctl -k -b -1` sięga do poprzednich –
dlatego po awarii to on, nie `dmesg`.

### Szukanie tekstu: `-g` albo `grep`

```bash
journalctl -u ssh --since "-1d" --no-pager | grep -c "Accepted publickey"   # ile udanych logowań kluczem: 29
journalctl -u k3s --since "-10min" -g "error"                              # -g (grep) wbudowany w journalctl
journalctl -b -2 -k --no-pager | grep -iE 'detected stall|Out of memory'    # kilka wzorców naraz
```

- `grep -c` – policz linie; `-i` – bez rozróżniania wielkości liter; `-E 'a|b'` – `a` **lub** `b`; `-v` – linie
  **bez** wzorca.
- `-g` działa podobnie, ale filtruje w `journalctl`, przed wypisaniem.

---

## 4. Wygląd wyniku: `-o`

| `-o` | Wygląd | Kiedy |
|---|---|---|
| `short` (domyślny) | `Nov 06 09:04:33 k3s-master …` | czytanie |
| `short-iso` | `2026-11-06T09:04:33+01:00 k3s-master …` | **pełna data i strefa** – do porównywania czasów między maszynami i z Windowsem |
| `cat` | sama treść, bez czasu i nazwy | gdy liczy się tylko komunikat |
| `verbose` | wszystkie pola wpisu, każde w osobnej linii | szczegóły jednego wpisu |
| `json` / `json-pretty` | JSON | do skryptów i narzędzi (`jq`) |

Fragment `-o verbose` – wpis to nie tylko tekst, ale zestaw pól:

```text
    _BOOT_ID=f7ef6fb9c74c4f9da9772773d3719e12
    _HOSTNAME=k3s-master
    _TRANSPORT=kernel
    SYSLOG_IDENTIFIER=kernel
    PRIORITY=5
    MESSAGE=audit: type=1400 … apparmor="DENIED" …
```

Po każdym polu można filtrować: `journalctl _TRANSPORT=kernel`, `journalctl PRIORITY=3`,
`journalctl _SYSTEMD_UNIT=k3s.service`.

---

## 5. Kilka maszyn naraz

Z Windowsa (Git Bash), pętla po aliasach SSH – tak powstał krok 10 diagnozy:

```bash
for h in k3s-master k3s-worker-1 k3s-worker-2 k3s-worker-3 monitoring; do
  echo "== $h"; ssh $h "journalctl --list-boots --no-pager | tail -3"
done
```

Z `monitoring`, przez Ansible (**w katalogu `~/k3s-monitoring-lab/ansible`**, bo tam jest `ansible.cfg`
z inwentarzem):

```bash
ansible all -m shell -a "journalctl --list-boots --no-pager | tail -3"
```

W firmie logi z wielu maszyn zbiera się centralnie (Loki + Promtail/Alloy, ELK, Graylog) i szuka w jednym miejscu.

---

## 6. Ściąga: zadanie → polecenie

| Zadanie | Polecenie |
|---|---|
| co się działo przed chwilą | `journalctl -e` albo `journalctl -n 50` |
| obserwuj na żywo | `journalctl -f` (jedna usługa: `-u k3s -f`) |
| dlaczego usługa nie wstaje | `systemctl status k3s` (ostatnie linie dziennika), potem `journalctl -u k3s -b -n 100` |
| błędy od startu | `journalctl -b -p err` |
| co było przed awarią / restartem | `journalctl --list-boots`, potem `journalctl -b -1 -n 50` |
| czy jądro zgłaszało problemy | `journalctl -k -b -1 \| grep -iE 'stall\|lockup\|Out of memory\|I/O error'` |
| kto używał `sudo` | `journalctl _COMM=sudo --since today` |
| logowania SSH | `journalctl -u ssh --since "-1d" \| grep -E 'Accepted\|Failed'` |
| ile miejsca zajmuje dziennik | `journalctl --disk-usage` |

---

## Ćwiczenia

Rozwiązania pod spodem. Wykonuj na `k3s-master` (🐧 `ssh k3s-master`).

1. Pokaż 10 ostatnich wpisów usługi `k3s` z pełną datą.
2. Pokaż wszystkie błędy (`err` i gorsze) z bieżącego uruchomienia.
3. Ile razy w ostatniej dobie ktoś zalogował się przez SSH kluczem?
4. Kiedy system ostatni raz startował, a kiedy kończyło się poprzednie uruchomienie?
5. Pokaż komunikaty jądra z poprzedniego uruchomienia zawierające `stall` lub `lockup`.
6. Obserwuj na żywo dziennik `k3s`, a w drugim oknie wykonaj `kubectl get nodes`. Co się pojawiło?

<details>
<summary>Rozwiązania</summary>

```bash
# 1
journalctl -u k3s -n 10 -o short-iso --no-pager

# 2
journalctl -b -p err --no-pager

# 3
journalctl -u ssh --since "-1d" --no-pager | grep -c "Accepted publickey"

# 4 – pierwszy wpis wiersza 0 i ostatni wpis wiersza -1
journalctl --list-boots --no-pager | tail -2

# 5
journalctl -k -b -1 --no-pager | grep -iE 'stall|lockup'

# 6 – w pierwszym oknie; Ctrl+C kończy
journalctl -u k3s -f
```

Ad 6: `kubectl get nodes` to zwykły odczyt, więc k3s zwykle **nic** nie zapisze – dziennik nie notuje każdego
zapytania do API (to robi dopiero osobny *audit log*). Widać za to wpisy, które pojawiają się same, np. okresowe
`COMPACT` bazy kine.

</details>

## Pytania rekrutacyjne

**Serwer Linux zrestartował się w nocy. Jak sprawdzisz, co się stało?**
`journalctl --list-boots` – kiedy kończyło się poprzednie uruchomienie. Potem `journalctl -b -1 -n 100`
(ostatnie wpisy) i `journalctl -k -b -1` (jądro: panika, OOM, błędy dysku). `last -x reboot shutdown` pokaże, czy
był to planowy restart. Jeśli dziennik nie jest trwały (brak `/var/log/journal`), poprzednich uruchomień nie będzie –
dlatego na serwerach włącza się `Storage=persistent`.

**Czym różni się `journalctl -k` od `dmesg`?**
`dmesg` czyta bufor jądra w pamięci – tylko bieżące uruchomienie, ograniczony rozmiar. `journalctl -k` czyta
komunikaty jądra zapisane w dzienniku, także z poprzednich uruchomień (`-b -1`), z filtrowaniem po czasie.

**Usługa nie startuje. Jakie dwa polecenia wpiszesz najpierw?**
`systemctl status nazwa` – stan, kod wyjścia i kilka ostatnich linii logu. Potem `journalctl -u nazwa -b -n 100
--no-pager` – pełny log usługi od startu systemu.
