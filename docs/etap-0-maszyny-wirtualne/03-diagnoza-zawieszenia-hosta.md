# Diagnoza: dlaczego zawiesza się komputer z maszynami

05.11.2026 około 20:00 konsola `k3s-master` pokazała `rcu: INFO: rcu_preempt detected stalls on CPUs/tasks`,
SSH przestało odpowiadać, a po chwili zawiesił się cały Windows. Pomogło tylko twarde wyłączenie (ok. 20:12).
Następnego dnia (06.11) host został przejrzany krok po kroku. Wszystkie polecenia **tylko odczytują** – nic nie
zmieniają i nie wymagają uprawnień administratora.

🪟 Wszystko wpisujesz w **PowerShell na Windowsie** (Start → „PowerShell” → Enter).

**Metoda:** najpierw ustal, **kiedy** i **jak** padło, potem wyklucz typowe przyczyny (pamięć, dysk), na końcu
szukaj wzorca. Ta sama kolejność obowiązuje na Linuksie – tam zamiast `Get-WinEvent` jest `journalctl`
([metoda diagnozowania](../problemy-ogolne.md)).

| Krok | Pytanie | Odpowiedź |
|---|---|---|
| 1 | Ile było awarii? | 8 w miesiącu – to wzorzec, nie przypadek |
| 2 | Co działo się tuż przed? | nic – komputer stanął bez ostrzeżenia |
| 3 | Niebieski ekran czy zawieszenie? | zawieszenie (brak zrzutu, `BugcheckCode = 0`) |
| 4 | Czy sprzęt zgłosił błąd? | nie (0 zdarzeń WHEA) |
| 5 | Brak miejsca albo pamięci? | nie |
| 6 | Czy maszyny zabrały za dużo RAM? | nie – 26 z 64 GB |
| 7 | Co mówi VMware? | maszyny przestały dostawać procesor – to skutek |
| 8 | Procesor i BIOS? | i7-14700KF, stary mikrokod 0x129 – najbardziej prawdopodobna przyczyna |

---

## Krok 1 – Ile było awarii

![Lista zdarzeń 41 i 6008 z 30 dni](img/host-1-awarie.png)

**Co robi polecenie:**

- `Get-WinEvent` czyta **dziennik zdarzeń Windows** – ten sam, który pokazuje okienkowy *Podgląd zdarzeń*
  (`Win + R` → `eventvwr.msc`).
- `-FilterHashtable @{…}` – filtr w nawiasach klamrowych: `LogName='System'` – dziennik systemowy,
  `Id=41,6008` – tylko dwa rodzaje zdarzeń, `StartTime='2026-10-06'` – od tego dnia.
- `| Select-Object TimeCreated, Id, ProviderName` – z każdego zdarzenia pokaż tylko czas, numer i źródło.

**Co znaczą numery:**

- **41** (`Kernel-Power`) – Windows uruchomił się, a wcześniej **nie został poprawnie zamknięty**.
- **6008** (`EventLog`) – „poprzednie zamknięcie systemu było nieoczekiwane”.

Zawsze przychodzą w parze, kilka sekund po starcie.

**Co zdiagnozowano:** **8 par** od 7.10 do 5.11 – dwa razy 28.10. Jedna awaria to przypadek, osiem to
**stały problem**. Od tej chwili szukamy przyczyny, która działa od tygodni, a nie czegoś, co zmieniło się 5.11.

---

## Krok 2 – Co działo się tuż przed awarią

![Błędy i ostrzeżenia z 5.11, 18:50–20:13](img/host-2-okno-awarii.png)

**Co robi polecenie:**

- `Level=1,2,3` – tylko **krytyczne** (1), **błędy** (2) i **ostrzeżenia** (3); zwykłe informacje (4) pomija.
- `StartTime` / `EndTime` – okno czasu wokół awarii.
- `Sort-Object TimeCreated` – od najstarszego.
- `@{n='Opis'; e={…}}` – **własna kolumna**: `n` to nazwa, `e` to wyrażenie liczące wartość (tu: pierwsze
  80 znaków opisu, żeby wiersz zmieścił się na ekranie).

**Co zdiagnozowano:**

- **Przed zawieszeniem nie ma żadnego błędu**, który by je zapowiadał. Ostatnie wpisy to 18:54 (DCOM –
  częsty, niegroźny szum w każdym Windowsie) i 18:58 (`Tcpip 4231` – zabrakło wolnych portów TCP; zdarzyło się też
  30.10 i 4.11 bez zawieszenia, więc to osobna sprawa).
- 20:12:50 – start po twardym wyłączeniu (41, 6008).
- **6008 podaje czas: 19:39:47.** To ostatni moment, w którym Windows zdążył zapisać „żyję”. Od tej chwili
  system już był w kłopotach, choć jeszcze częściowo działał (krok 7).
- Wpisy z 20:12:56 i później (DCOM, usługa `TavernComn`, Bluetooth) to zwykłe komunikaty przy starcie.

---

## Krok 3 – Niebieski ekran czy zawieszenie

![Pusty katalog Minidump i BugcheckCode 0](img/host-3-bsod.png)

**Co robi polecenie:**

- `Get-ChildItem C:\Windows\Minidump` – lista plików w katalogu, do którego Windows zapisuje **zrzut pamięci po
  niebieskim ekranie** (BSOD). Pusto = brak zrzutu.
- Drugie polecenie bierze 8 ostatnich zdarzeń 41 (`-MaxEvents 8`) i z każdego wyciąga pole `BugcheckCode`:
  - `ForEach-Object { … }` – wykonaj blok dla każdego zdarzenia, `$_` to bieżące zdarzenie;
  - `[xml]$_.ToXml()` – zdarzenie jako XML, bo tylko tam są jego szczegółowe pola;
  - `[pscustomobject]@{…}` – zbuduj wiersz tabeli z dwiema kolumnami.

**Co zdiagnozowano:** brak zrzutów i `BugcheckCode = 0` przy **każdej** z 8 awarii. Przy niebieskim ekranie
byłby tu kod błędu (np. `0x9C`, `0x124`). Zero znaczy, że Windows nie zdążył nic zgłosić – to **twarde
zawieszenie**: system zamarzł, a komputer wyłączono przyciskiem. Taki objaw zwykle wskazuje na sprzęt albo
sterowniki niskiego poziomu, a nie na zwykły program.

---

## Krok 4 – Czy sprzęt zgłosił błąd

![Liczba zdarzeń WHEA: 0](img/host-4-whea.png)

**Co robi polecenie:**

- `ProviderName='Microsoft-Windows-WHEA-Logger'` – zdarzenia **WHEA** (*Windows Hardware Error Architecture*):
  błędy, które zgłasza sam sprzęt – procesor, pamięć, kontroler PCIe.
- `-ErrorAction SilentlyContinue` – gdy nic nie ma, nie pokazuj czerwonego błędu „No events were found”.
- `@( … ).Count` – policz wyniki (`@()` robi z wyniku listę, więc działa też przy zerze).

**Co zdiagnozowano:** **0**. Sprzęt nie zgłosił żadnego błędu. To wyklucza awarie, które zwykle zostawiają
ślad (np. uszkodzony moduł RAM z błędami korekcji), ale **nie wyklucza procesora** – przy twardym zawieszeniu
komputer staje, zanim cokolwiek zapisze.

---

## Krok 5 – Miejsce na dysku i pamięć

![Wolne miejsce na C:, RAM i plik wymiany](img/host-5-dysk-pamiec.png)

**Co robi polecenie:**

- `Get-PSDrive C` – zajęte i wolne miejsce na dysku C:.
- `Get-CimInstance Win32_OperatingSystem` – informacje o systemie z WMI/CIM (wbudowanej „bazy” Windowsa o sprzęcie
  i systemie); `TotalVisibleMemorySize` i `FreePhysicalMemory` są **w KB**.
- `Win32_PageFileUsage` – plik wymiany (`pagefile.sys`, odpowiednik swapu): `AllocatedBaseSize` – rozmiar w MB,
  `PeakUsage` – **największe użycie** od startu, w MB.

**Co zdiagnozowano:**

- dysk: **1278 GB wolne** – brak miejsca wykluczony;
- RAM: 66 946 680 KB ≈ **64 GB**, wolne ≈ 22 GB przy działających maszynach;
- plik wymiany: szczyt **14 MB** z 13,8 GB – Windows prawie nie sięgał na dysk po pamięć. Gdyby brakowało RAM,
  byłyby tu gigabajty.

---

## Krok 6 – Ile pamięci i procesorów dostały maszyny

![Lista maszyn VMware i ich memsize/numvcpus](img/host-6-pamiec-maszyn.png)

**Co robi polecenie:**

- `$env:APPDATA\VMware\inventory.vmls` – plik, w którym VMware Workstation trzyma **listę maszyn** z biblioteki;
  linie `vmlistN.config` to ścieżki do plików `.vmx`.
- `Select-String` – odpowiednik `grep`: szuka wzorca w plikach. `-Pattern '^memsize|^numvcpus'` – linie
  zaczynające się (`^`) od `memsize` **albo** (`|`) `numvcpus`.
- `.vmx` – plik konfiguracji maszyny: `memsize` – RAM w MB, `numvcpus` – liczba wirtualnych procesorów.
- `"$($_.Filename): $($_.Line)"` – wypisz nazwę pliku i znalezioną linię.

**Co zdiagnozowano:**

| Maszyna | RAM | vCPU |
|---|---|---|
| k3s-master | 4 GB | 2 |
| k3s-worker-1 / -2 / -3 | 3 × 6 GB | 3 × 2 |
| monitoring | 4 GB | 2 |
| **Razem** | **26 z 64 GB** | **10 z 28 wątków** |

Maszyny nie zabrały za dużo pamięci ani procesora – zostaje duży zapas dla Windowsa. Hipoteza „VM-ki zjadły
pamięć” odpada.

---

## Krok 7 – Co zapisał VMware

![Wpisy z vmware-2.log i tryb pracy VMware](img/host-7-logi-vmware.png)

**Co robi polecenie:**

- `vmware.log` – log jednej maszyny w jej folderze. VMware trzyma kilka ostatnich: `vmware.log` (bieżące
  uruchomienie), `vmware-0.log`, `-1`, `-2` (starsze). Wybierz ten, którego data zmiany obejmuje awarię
  (`Get-ChildItem … -Filter 'vmware*.log'`).
- `-Pattern '^2026-11-05T19:12'` – linie z tej minuty; `Select-Object -Last 6` – ostatnie 6.
- ⚠️ **Czas w logach VMware jest w UTC** (litera `Z` na końcu). W Polsce zimą jest +1 h: `19:12Z` = **20:12**.
- `Hyper-V detected|Monitor Mode` – w jakim trybie VMware uruchomił maszynę.
- `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` – czy w Windowsie działa hiperwizor Microsoftu (Hyper-V).

**Co zdiagnozowano:**

- O 20:12 VMware zgłasza `GuestRpcSendTimedOut: message to toolbox timed out` – **system w maszynie nie
  odpowiada**, bo nie dostaje czasu procesora. To ten sam objaw co `rcu_preempt detected stalls` na konsoli
  mastera, tylko widziany z zewnątrz. Maszyny są **ofiarą**, nie przyczyną.
- `Hyper-V detected by CPUID` + `Monitor Mode: ULM` + `True` – w Windowsie działa Hyper-V (włączają go m.in.
  WSL2, Docker Desktop, „Izolacja rdzenia”). VMware nie ma wtedy bezpośredniego dostępu do sprzętowej
  wirtualizacji i pracuje **na Hyper-V** (tryb ULM, *User Level Monitor*, przez Windows Hypervisor Platform).
  To działa, ale wolniej. Samo w sobie raczej nie zawiesza komputera.

---

## Krok 8 – Procesor, mikrokod i BIOS

![Model procesora, mikrokod 0x129, BIOS H.50 i płyta MSI](img/host-8-procesor-bios.png)

**Co robi polecenie:**

- `HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0` – gałąź **rejestru Windows** z opisem pierwszego rdzenia
  procesora. `Get-ItemProperty` czyta jej wartości do zmiennej `$cpu`.
- `ProcessorNameString` – nazwa procesora.
- `'Update Revision'` – wersja **mikrokodu**: wewnętrznego oprogramowania procesora, które poprawia jego błędy.
  Windows zapisuje ją jako 4 bajty **od tyłu**: `41 1 0 0` → szesnastkowo `29 01 00 00` → czytane od końca
  `0x00000129`.
- `[BitConverter]::ToInt32(…, 0)` – zamienia te 4 bajty na liczbę, `'0x{0:X}' -f` – zapisuje ją szesnastkowo.
- `Win32_BIOS` – wersja i data BIOS-u; `Win32_BaseBoard` – model płyty głównej (potrzebny, żeby pobrać
  **właściwy** BIOS).

**Co zdiagnozowano:**

- **i7-14700KF** – 14. generacja Intela. Procesory 13. i 14. generacji mają **znany problem niestabilności**
  (*Vmin shift*): pod długim obciążeniem zbyt wysokie napięcie stopniowo je degraduje, co daje zawieszenia
  i błędy **bez śladu w logach** – dokładnie jak w krokach 2–4.
- Mikrokod **0x129** i BIOS **H.50 z 12.08.2024** – to wczesna poprawka. Intel wydał później kolejne (0x12B,
  0x12F), które przychodzą razem z aktualizacją BIOS-u płyty.
- Lab trzyma 5 maszyn włączonych godzinami – procesor jest stale obciążony, więc problem wychodzi częściej.

---

## Wniosek i co dalej

| Hipoteza | Wynik | Krok |
|---|---|---|
| brak miejsca na dysku | ❌ wykluczona | 5 |
| brak pamięci RAM | ❌ wykluczona | 5, 6 |
| maszyny zabrały za dużo zasobów | ❌ wykluczona | 6 |
| uszkodzony sprzęt zgłaszający błędy (np. RAM) | ❌ mało prawdopodobna | 4 |
| niestabilny procesor ze starym mikrokodem | ✅ **najbardziej prawdopodobna** | 1, 3, 8 |

To **hipoteza, nie pewność**. Potwierdzi ją dopiero to, że po aktualizacji awarie znikną.

**Co zrobić (właściciel):**

1. Wyłącz maszyny wirtualne.
2. Ze strony MSI (Support → **B760M GAMING PLUS WIFI**, MS-7D99) pobierz najnowszy BIOS.
3. Wgraj go przez **M-Flash** z pendrive'a według instrukcji MSI. **Nie wyłączaj komputera w trakcie.**
4. W BIOS-ie wybierz profil **Intel Default Settings**.
5. Po starcie sprawdź mikrokod poleceniem z kroku 8 – ma być większy niż `0x129`.
6. Obserwuj: polecenie z kroku 1 co jakiś czas. Brak nowych par 41/6008 przez kilka tygodni = problem rozwiązany.
   Jeśli awarie wrócą – test stabilności i reklamacja procesora (Intel wydłużył gwarancję tych modeli).

Skrót tego opisu: [problemy Etapu 0](problemy.md#host-zawiesza-się-razem-z-maszynami). Polecenia:
[ściągawka](../sciagawka-polecen.md#sieć-firewall-i-maszyny-vmware).

## Pytania rekrutacyjne

**Serwer się zawiesił i trzeba go było wyłączyć przyciskiem. Od czego zaczniesz?**
Od dziennika: ile razy to się zdarzyło (Windows: zdarzenia 41/6008, Linux: `journalctl --list-boots` i `last -x`),
czy był niebieski ekran / kernel panic (zrzut, kod błędu), co działo się tuż przed, czy sprzęt zgłosił błędy
(WHEA / `mcelog`, `dmesg`). Potem wykluczam typowe przyczyny – dysk, pamięć – i szukam wzorca.

**Maszyna wirtualna pokazuje „rcu_preempt detected stalls”. Co to znaczy?**
Jądro Linuksa przez dłuższy czas nie dostało procesora. W maszynie wirtualnej zwykle oznacza to problem hosta
(przeciążony, zawieszony, za dużo vCPU względem rdzeni), a nie samej maszyny – więc szukam po stronie hiperwizora.

**Czym jest mikrokod procesora i jak się go aktualizuje?**
To oprogramowanie wewnątrz procesora, którym producent poprawia jego błędy (także luki bezpieczeństwa, np.
Spectre). Ładuje go BIOS/UEFI przy starcie, a system operacyjny może załadować nowszy (Linux: pakiet
`intel-microcode`). Na Windowsie najpewniejsza droga to aktualizacja BIOS-u płyty.
