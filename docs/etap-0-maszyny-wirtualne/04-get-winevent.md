# Get-WinEvent – dziennik zdarzeń Windows z PowerShell

`Get-WinEvent` czyta **dziennik zdarzeń Windows** – ten sam, który pokazuje okienkowy *Podgląd zdarzeń*
(`Win + R` → `eventvwr.msc`). Na Linuksie odpowiednikiem jest `journalctl`. Przydaje się zawsze, gdy coś
padło na komputerze z VMware: zawieszenie, restart, usługa, która nie wstała. Przykład użycia w praktyce:
[diagnoza zawieszenia hosta](03-diagnoza-zawieszenia-hosta.md).

🪟 Wszystkie polecenia wpisujesz w **PowerShell na Windowsie**. Wyniki w tym pliku pochodzą z hosta labu
(06.11.2026).

---

## 1. Dzienniki – gdzie Windows zapisuje zdarzenia

Windows ma **setki** osobnych dzienników (na hoście labu: 467). Na co dzień wystarczą cztery:

| Dziennik | Co w nim jest | Kto może czytać |
|---|---|---|
| `System` | sterowniki, usługi, start i wyłączenie, awarie, sieć | każdy |
| `Application` | programy: awarie aplikacji, instalatory, bazy danych | każdy |
| `Security` | logowania, zmiany uprawnień, audyt | **tylko administrator** |
| `Setup` | instalacja aktualizacji Windows | każdy |

```powershell
Get-WinEvent -ListLog Application, System, Setup
```

```text
LogName     RecordCount   MB  LogMode
-------     -----------   --  -------
Application       30196 16,1 Circular
System            33155   20 Circular
Setup              2428    1 Circular
```

- `-ListLog` – nie zdarzenia, tylko **informacje o dziennikach**. `-ListLog *` pokaże wszystkie.
- `RecordCount` – ile zdarzeń jest w dzienniku; `MB` – rozmiar pliku.
- `Circular` – dziennik ma stały rozmiar, **najstarsze wpisy są nadpisywane**. Dlatego stare awarie mogą
  zniknąć – gdy szukasz czegoś sprzed miesięcy, może już tego nie być.

Na Linuksie: `journalctl --disk-usage`, a ustawienia rozmiaru w `/etc/systemd/journald.conf`.

---

## 2. Pierwsze polecenie – ostatnie zdarzenia

```powershell
Get-WinEvent -LogName System -MaxEvents 5
```

- `-LogName System` – z którego dziennika.
- `-MaxEvents 5` – tylko 5 **najnowszych**. **Zawsze** ograniczaj wynik – bez tego PowerShell wypisze
  dziesiątki tysięcy wierszy.
- Domyślnie od najnowszego. `-Oldest` odwraca kolejność (od najstarszego).

Linux: `journalctl -n 5`.

Każde zdarzenie ma kilka stałych pól:

| Pole | Co to | Przykład |
|---|---|---|
| `TimeCreated` | kiedy | `05.11.2026 20:12:51` |
| `Id` | **numer rodzaju zdarzenia** – najważniejszy do wyszukiwania | `41` |
| `LevelDisplayName` | waga słownie | `Krytyczne`, `Błąd`, `Ostrzeżenie`, `Informacje` |
| `ProviderName` | **kto zapisał** (źródło) | `Microsoft-Windows-Kernel-Power` |
| `Message` | opis po polsku | „System został uruchomiony ponownie bez…” |

Ten sam `Id` od **innego** źródła może znaczyć coś innego – przy wyszukiwaniu podawaj oba, jeśli się da.

---

## 3. Filtrowanie – `-FilterHashtable`

Najważniejsza część. Filtr zapisujesz w `@{ … }` (*hashtable* – pary `klucz=wartość` rozdzielone średnikiem):

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41}
```

| Klucz | Co filtruje | Przykład |
|---|---|---|
| `LogName` | dziennik (**wymagany**, chyba że podasz `ProviderName`) | `LogName='System'` |
| `Id` | numer zdarzenia; kilka po przecinku | `Id=41,6008` |
| `Level` | waga (tabela niżej); kilka po przecinku | `Level=1,2` |
| `ProviderName` | źródło | `ProviderName='Microsoft-Windows-WHEA-Logger'` |
| `StartTime` | od kiedy | `StartTime='2026-11-05 19:30'` |
| `EndTime` | do kiedy | `EndTime='2026-11-05 20:30'` |

Klucze łączą się przez **„i”**: `@{LogName='System'; Id=41; StartTime='2026-10-06'}` = z dziennika System
**i** numer 41 **i** od 6.10. Wartości po przecinku w jednym kluczu łączą się przez **„lub”**: `Id=41,6008`.

### Poziomy wagi

| `Level` | Nazwa | Linux (`journalctl -p`) |
|---|---|---|
| 1 | Krytyczne | `crit` (2) |
| 2 | Błąd | `err` (3) |
| 3 | Ostrzeżenie | `warning` (4) |
| 4 | Informacje | `info` (6) |

```powershell
# same błędy i krytyczne z ostatniej doby
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-1)}
```

### Czas

- `StartTime='2026-11-05 19:30'` – konkretna chwila (tekst w formacie `rok-miesiąc-dzień godzina:minuta`).
- `StartTime=(Get-Date).AddDays(-7)` – **względnie**: teraz minus 7 dni. Też `.AddHours(-2)`,
  `.AddMinutes(-30)`. W skrypcie, który ma działać każdego dnia, używaj tej formy.

Linux: `journalctl --since "2026-11-05 19:30" --until "2026-11-05 20:30"` albo `--since "-7d"`.

### Dlaczego `-FilterHashtable`, a nie `Where-Object`

```powershell
# szybko – filtruje Windows, zanim przekaże zdarzenia do PowerShell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41}

# wolno – najpierw pobiera WSZYSTKIE 33 tys. zdarzeń, potem PowerShell je przegląda
Get-WinEvent -LogName System | Where-Object Id -eq 41
```

Zasada: **filtruj jak najwcześniej**. `Where-Object` zostaw na to, czego `-FilterHashtable` nie umie –
np. szukanie słowa w opisie:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-2)} |
  Where-Object Message -like '*VMnet*'
```

`-like '*tekst*'` – zawiera tekst (gwiazdka = dowolne znaki). Linux: `journalctl --since -2d | grep VMnet`.

---

## 4. Kształtowanie wyniku

Domyślna tabela ucina opis. Masz trzy narzędzia:

```powershell
# wybrane kolumny
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 5 |
  Select-Object TimeCreated, Id, ProviderName

# PEŁNY opis jednego zdarzenia – każde pole w osobnej linii
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 1 | Format-List *

# tabela z zawijaniem długich opisów zamiast ucinania
Get-WinEvent -FilterHashtable @{LogName='System'; Level=2} -MaxEvents 5 |
  Format-Table TimeCreated, Id, Message -Wrap
```

- `Select-Object` – wybierz kolumny (wynik nadal można przetwarzać dalej).
- `Format-List *` – wszystkie pola jako lista; najlepsze do **czytania jednego** zdarzenia.
- `Format-Table … -Wrap` – tabela, długi tekst przenoszony do kolejnych linii.
- `Format-*` dawaj **na końcu** – po nim wynik nadaje się już tylko do wyświetlenia.

### Liczenie i grupowanie

```powershell
# ile było zdarzeń
@(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime='2026-10-06'}).Count
# wynik: 8

# które programy najczęściej zgłaszają błędy w ostatnim tygodniu
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=(Get-Date).AddDays(-7)} |
  Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 Count, Name
```

- `@( … ).Count` – `@()` robi z wyniku listę, więc `.Count` działa też przy 0 i 1 wyniku.
- `Group-Object ProviderName` – zlicza zdarzenia według źródła (jak `sort | uniq -c` na Linuksie).

### Zapis do pliku

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008} |
  Select-Object TimeCreated, Id, ProviderName, Message |
  Export-Csv "$HOME\Desktop\awarie.csv" -NoTypeInformation -Encoding UTF8
```

`Export-Csv` – plik do otwarcia w Excelu albo do załączenia w zgłoszeniu. `-NoTypeInformation` – bez
technicznego nagłówka na początku pliku.

---

## 5. Szczegóły zdarzenia – pola z XML

Opis (`Message`) jest dla ludzi. Dokładne wartości (kody błędów, nazwy plików) są w polach `EventData`,
widocznych dopiero w XML:

```powershell
$e = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 1
([xml]$e.ToXml()).Event.EventData.Data
```

```text
Name               #text
----               -----
BugcheckCode       0
BugcheckParameter1 0x0
BugcheckParameter2 0x0
...
SleepInProgress    0
```

- `$e = …` – zapisz zdarzenie do zmiennej, żeby nie pobierać go kilka razy.
- `$e.ToXml()` – zdarzenie jako tekst XML; `[xml]` – zamień tekst na obiekt, po którym można chodzić kropkami.
- `.Event.EventData.Data` – lista pól z nazwami (`Name`) i wartościami (`#text`).

Jedno pole z wielu zdarzeń naraz – tak powstał krok 3 diagnozy:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 8 | ForEach-Object {
  $x = [xml]$_.ToXml()
  [pscustomobject]@{
    Czas         = $_.TimeCreated
    BugcheckCode = ($x.Event.EventData.Data | Where-Object Name -eq 'BugcheckCode').'#text'
  }
}
```

- `ForEach-Object { … }` – wykonaj blok dla każdego zdarzenia; `$_` to bieżące zdarzenie.
- `[pscustomobject]@{ … }` – zbuduj własny wiersz tabeli z wybranymi kolumnami.

---

## 6. Numery warte zapamiętania

| Dziennik | Id | Źródło | Znaczenie |
|---|---|---|---|
| System | **41** | Kernel-Power | start po **nieczystym** wyłączeniu (zawieszenie, zanik prądu, przycisk) |
| System | **6008** | EventLog | „poprzednie zamknięcie było nieoczekiwane” + godzina ostatniego znaku życia |
| System | 6005 / 6006 | EventLog | dziennik uruchomiony (= start systemu) / zatrzymany (= czyste wyłączenie) |
| System | **1074** | User32 | **kto i dlaczego** zrestartował lub wyłączył komputer (program, użytkownik) |
| System | 1001 | WER-SystemErrorReporting | restart po **niebieskim ekranie**, z kodem błędu |
| System | dowolny | WHEA-Logger | błędy zgłoszone przez sprzęt (procesor, pamięć, PCIe) |
| System | 7031 / 7034 | Service Control Manager | usługa nieoczekiwanie się zakończyła |
| System | 7000 / 7009 | Service Control Manager | usługa nie wystartowała / nie odpowiedziała w czasie |
| System | 4231 | Tcpip | zabrakło wolnych portów TCP |
| Application | 1000 / 1002 | Application Error / Hang | program się wysypał / przestał odpowiadać |
| Security | 4624 / 4625 | Security-Auditing | udane / **nieudane** logowanie (tylko administrator) |

Przykład – kto wyłączał komputer:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1074} -MaxEvents 2 | Format-List TimeCreated, Message
```

```text
TimeCreated : 28.10.2026 20:10:27
Message     : Proces C:\WINDOWS\SystemApps\Microsoft.Windows.StartMenuExperienceHost_…\StartMenuExperienceHost.exe
              zainicjował wyłączenie zasilania komputera GRAFIKA w imieniu użytkownika GRAFIKA\User …
              Typ zamknięcia systemu: wyłączenie zasilania
```

`StartMenuExperienceHost.exe` = ktoś kliknął *Start → Wyłącz*. Gdy przyczyną jest aktualizacja, w tym miejscu
będzie usługa Windows Update.

---

## 7. Typowe komunikaty

| Komunikat | Co znaczy | Co zrobić |
|---|---|---|
| `No events were found that match the specified selection criteria` | filtr nic nie znalazł – **to nie awaria**, tylko pusty wynik | dodaj `-ErrorAction SilentlyContinue` albo licz przez `@( … ).Count` |
| `Nastąpiła próba wykonania nieautoryzowanej operacji` | dziennik `Security` wymaga uprawnień | uruchom PowerShell *jako administrator* |
| `The specified channel could not be found` | literówka w `LogName` | `Get-WinEvent -ListLog *` pokaże poprawne nazwy |
| wyniku nie widać, PowerShell „myśli” minutami | brak `-MaxEvents` i filtra czasu | przerwij `Ctrl+C`, dodaj `StartTime` lub `-MaxEvents` |

---

## 8. Ściąga: Windows ↔ Linux

| Cel | Windows (`Get-WinEvent`) | Linux (`journalctl`) |
|---|---|---|
| ostatnie 20 | `-LogName System -MaxEvents 20` | `journalctl -n 20` |
| same błędy | `@{LogName='System'; Level=1,2}` | `journalctl -p err` |
| z przedziału czasu | `StartTime=…; EndTime=…` | `--since … --until …` |
| jedno źródło | `ProviderName='…'` | `-u nazwa.service` |
| szukaj słowa | `\| Where-Object Message -like '*słowo*'` | `\| grep słowo` |
| poprzednie uruchomienia | `@{LogName='System'; Id=6005}` | `journalctl --list-boots` |
| zdarzenia z poprzedniego startu | `StartTime`/`EndTime` z dat 6005 | `journalctl -b -1` |
| pełny opis | `\| Format-List *` | `-o verbose` |
| na żywo | brak – Podgląd zdarzeń albo pętla | `journalctl -f` |

---

## Ćwiczenia

Rozwiązania pod spodem – najpierw spróbuj sam.

1. Pokaż 10 ostatnich zdarzeń z dziennika `Application`.
2. Ile **błędów** (tylko poziom 2) zapisał dziennik `System` w ostatnich 7 dniach?
3. Kiedy ostatnio startował system (3 ostatnie starty)?
4. Kto i kiedy ostatnio wyłączył komputer? Pokaż pełny opis.
5. Pokaż wszystkie ostrzeżenia z dziennika `System` z 5.11.2026 między 18:00 a 19:00, posortowane od najstarszego.
6. Zapisz listę awarii (41 i 6008) z ostatnich 60 dni do pliku `awarie.csv` na pulpicie.

<details>
<summary>Rozwiązania</summary>

```powershell
# 1
Get-WinEvent -LogName Application -MaxEvents 10

# 2
@(Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue).Count

# 3
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005} -MaxEvents 3 | Select-Object TimeCreated

# 4
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1074} -MaxEvents 1 | Format-List TimeCreated, Message

# 5
Get-WinEvent -FilterHashtable @{LogName='System'; Level=3; StartTime='2026-11-05 18:00'; EndTime='2026-11-05 19:00'} |
  Sort-Object TimeCreated | Format-Table TimeCreated, Id, ProviderName, Message -Wrap

# 6
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=(Get-Date).AddDays(-60)} |
  Select-Object TimeCreated, Id, ProviderName, Message |
  Export-Csv "$HOME\Desktop\awarie.csv" -NoTypeInformation -Encoding UTF8
```

</details>

## Pytania rekrutacyjne

**Jak sprawdzisz, czy serwer Windows zrestartował się sam, czy ktoś go zrestartował?**
Zdarzenie 1074 (User32) podaje proces, użytkownika i przyczynę planowanego restartu. Para 41 (Kernel-Power)
+ 6008 oznacza restart **bez** czystego zamknięcia – zawieszenie, awaria, zanik zasilania. 1001 – niebieski ekran.

**Dlaczego `-FilterHashtable` zamiast `Where-Object`?**
`-FilterHashtable` filtruje po stronie usługi dziennika zdarzeń i oddaje tylko pasujące wpisy. `Where-Object`
dostaje wszystkie zdarzenia i przegląda je w PowerShell – przy dziesiątkach tysięcy wpisów różnica to sekundy
kontra minuty. Zasada „filtruj u źródła” obowiązuje też w `journalctl`, SQL i zapytaniach do Prometheusa.

**Co jest odpowiednikiem `journalctl` w Windows?**
Dziennik zdarzeń: okienkowo *Podgląd zdarzeń* (`eventvwr.msc`), z wiersza poleceń `Get-WinEvent` (PowerShell)
albo starsze `wevtutil qe`. W firmie zdarzenia z wielu serwerów zbiera się centralnie – Windows Event Forwarding
albo agent (np. Wazuh, Elastic Agent) – tak jak logi z Linuksa do Loki czy ELK.
