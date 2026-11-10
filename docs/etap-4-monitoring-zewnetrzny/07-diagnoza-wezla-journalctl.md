# Diagnoza węzła k3s i journalctl w praktyce

Rozdział powstał przy teście awarii B (10.11.2026, wyłączony `k3s-worker-1`). Najpierw procedura: w jakiej
kolejności szukać przyczyny, gdy w klastrze coś padło. Potem podstawowe szkolenie z `journalctl` na węźle k3s –
na prawdziwych wpisach z worker-1.

Pełny opis `journalctl` (wszystkie filtry, formaty, kilka maszyn naraz) jest w Etapie 0:
[05-journalctl.md](../etap-0-maszyny-wirtualne/05-journalctl.md). Tu tylko to, czego używa się przy węźle
Kubernetesa.

## Spis treści

1. [Procedura: od ogółu do szczegółu](#1-procedura-od-ogółu-do-szczegółu)
2. [journalctl – kto może czytać dziennik](#2-journalctl--kto-może-czytać-dziennik)
3. [Lista uruchomień: `--list-boots`](#3-lista-uruchomień---list-boots)
4. [Czyste wyłączenie czy awaria?](#4-czyste-wyłączenie-czy-awaria)
5. [Usługa k3s: `-u k3s-agent`](#5-usługa-k3s--u-k3s-agent)
6. [Tylko błędy: `-p err`](#6-tylko-błędy--p-err)
7. [Czas, szukanie, na żywo](#7-czas-szukanie-na-żywo)
8. [Śledztwo: skąd zepsuty obraz Headlampa](#8-śledztwo-skąd-zepsuty-obraz-headlampa)
9. [Ściąga](#9-ściąga)
10. [Ćwiczenia](#10-ćwiczenia)
11. [Pytania rekrutacyjne](#11-pytania-rekrutacyjne)

## 1. Procedura: od ogółu do szczegółu

Wszystkie polecenia `kubectl` – 🐧 **k3s-master** (tylko tam jest kubeconfig; na workerze `kubectl` kończy się
błędem `localhost:8080 … connection refused`).

| Krok | Pytanie | Polecenie / miejsce | Co znaczy wynik |
|---|---|---|---|
| 1 | Czy użytkownik coś odczuwa? | 🪟 Uptime Kuma `http://192.168.180.54:3001` | czerwone = usługa nie odpowiada z zewnątrz |
| 2 | Które węzły są zdrowe? | `kubectl get nodes` | szukasz czegoś innego niż `Ready` |
| 3 | Co master wie o węźle? | `kubectl describe node X \| grep -A8 Conditions` | `Unknown` = węzeł milczy; `True/False` = żyje i coś zgłasza |
| | | `kubectl describe node X \| grep -A1 Taints` | `unreachable:NoExecute` = Kubernetes wyprowadza pody |
| 4 | Czy maszyna żyje? | `ping -c 3 IP`, `ssh X` | `Destination Host Unreachable` = brak maszyny (ARP); cisza = firewall |
| 5 | Które pody ucierpiały? | `kubectl get pods -A -o wide \| grep -v -E "Running\|Completed"` | `Terminating`, `Pending`, `CrashLoopBackOff`… |
| | | `kubectl get pods -A -o wide --field-selector spec.nodeName=X` | wszystko z jednego węzła (też „wiszące” `Running`) |
| 6 | Dlaczego pod nie wstaje? | `Pending`: `kubectl get events -A --field-selector reason=FailedScheduling` | ile węzłów odpadło i dlaczego |
| | | `CrashLoopBackOff`: `kubectl logs POD --previous`, `describe pod` (Exit Code) | co mówił padający kontener |
| 7 | Co widzi monitoring? | Prometheus `/targets`, `/alerts`, Alertmanager, Grafana, healthchecks.io | od kiedy, które cele, czy alarmy dochodzą |
| 8 | Co się działo na węźle? | 🐧 na węźle: `journalctl` – rozdziały 2–7 | przyczyna: wyłączenie, awaria, błąd k3s |

Wynik kroków 2–7 z testu B: [przebieg, krok 11](05-przebieg-wdrozenia.md#krok-11--test-awarii-b-wyłączony-worker-1-10112026).

## 2. journalctl – kto może czytać dziennik

`journalctl` czyta dziennik **systemd-journald**: jedno miejsce na wpisy jądra, usług (k3s, containerd, ssh,
chrony…) i programów. Na Ubuntu dziennik jest trwały (`/var/log/journal`), więc przetrwa restart.

```bash
id
```

```text
uid=1000(grzegorz) gid=1000(grzegorz) groups=1000(grzegorz),4(adm),24(cdrom),27(sudo),…
```

Grupa **`adm`** wystarcza do czytania całego dziennika bez `sudo`. Bez niej użytkownik widzi tylko swoje wpisy.
Z `sudo` – zawsze wszystko (dlatego w instrukcjach często jest `sudo journalctl`).

```bash
journalctl --disk-usage
```

```text
Archived and active journals take up 99.1M in the file system.
```

## 3. Lista uruchomień: `--list-boots`

Każde uruchomienie systemu (boot) ma numer: **0** – bieżące, **-1** – poprzednie, **-2** – jeszcze wcześniejsze.

```bash
journalctl --list-boots --no-pager | tail -3
```

Wynik z worker-1, 10.11 o 10:01:

```text
 -2 b320601739ef411d8af6105793b0b142 Thu 2026-11-05 20:14:12 CET Thu 2026-11-05 20:21:33 CET
 -1 df5930c6a934441ca5146ef60485d14f Thu 2026-11-05 20:30:08 CET Tue 2026-11-10 09:21:43 CET
  0 2e9f5ddf22ea48d3a4475e21e58b49a1 Tue 2026-11-10 09:55:52 CET Tue 2026-11-10 10:01:03 CET
```

| Kolumna | Znaczy |
|---|---|
| `-2`, `-1`, `0` | numer uruchomienia do użycia w `-b` |
| `b3206…` | identyfikator uruchomienia (boot ID) |
| pierwsza data | pierwszy wpis tego uruchomienia (start systemu) |
| druga data | ostatni wpis (dla `0` – „teraz”) |

Już sama lista opowiada historię:

- **-2: 7 minut życia** (20:14 → 20:21) w wieczór awarii hosta 05.11. Krótkie uruchomienie zakończone bez
  wyłączenia – podejrzane.
- **-1: od 05.11 20:30 do 10.11 09:21:43** – normalna praca przez prawie 5 dni, koniec dokładnie w chwili
  wyłączenia w teście B.
- **0: od 09:55:52** – włączenie po teście.

## 4. Czyste wyłączenie czy awaria?

Najważniejsza umiejętność przy padniętym węźle. Patrzysz na **koniec** poprzedniego uruchomienia:

```bash
journalctl -b -1 -n 20 --no-pager
```

`-b -1` – poprzednie uruchomienie, `-n 20` – ostatnie 20 linii.

**Czyste wyłączenie** (worker-1, test B, *Shut Down Guest* w VMware):

```text
Nov 10 09:21:43 k3s-worker-1 systemd[1]: Reached target shutdown.target - System Shutdown.
Nov 10 09:21:43 k3s-worker-1 systemd[1]: Finished systemd-poweroff.service - System Power Off.
Nov 10 09:21:43 k3s-worker-1 systemd[1]: Reached target poweroff.target - System Power Off.
Nov 10 09:21:43 k3s-worker-1 systemd[1]: Shutting down.
Nov 10 09:21:43 k3s-worker-1 systemd-shutdown[1]: Syncing filesystems and block devices.
Nov 10 09:21:43 k3s-worker-1 systemd-shutdown[1]: Sending SIGTERM to remaining processes...
Nov 10 09:21:43 k3s-worker-1 systemd-udevd[753]: Failed to remove file descriptor "config-serialization" from the store, ignoring: Connection refused
Nov 10 09:21:43 k3s-worker-1 systemd-journald[696]: Journal stopped
```

Usługi zatrzymane po kolei, **`Syncing filesystems`** (zapis wszystkiego z pamięci na dysk), na końcu
**`Journal stopped`**. Żółta linia `udevd … Connection refused` to typowy, niegroźny komunikat przy zamykaniu.

**Nagła awaria** (ten sam worker-1, 05.11 – zawieszenie hosta i twarde wyłączenie):

```bash
journalctl -b -2 -n 5 --no-pager -o short-iso
```

```text
2026-11-05T20:21:17+01:00 k3s-worker-1 kernel: audit: type=1400 … apparmor="DENIED" operation="signal" …
2026-11-05T20:21:17+01:00 k3s-worker-1 k3s[1516]: I1105 20:21:17.081426 … "Observed pod startup duration" pod="headlamp/headlamp-6ff8f74776-c54rb" …
2026-11-05T20:21:17+01:00 k3s-worker-1 kernel: audit: type=1400 … apparmor="DENIED" operation="signal" …
2026-11-05T20:21:33+01:00 k3s-worker-1 kernel: audit: type=1400 … apparmor="DENIED" operation="signal" …
```

Zwykłe wpisy z pracy – i **koniec**. Żadnego `Stopped`, `Shutting down`, `Syncing filesystems`. System nie
wiedział, że kończy pracę: zasilanie (tu – cała maszyna wirtualna razem z hostem) zniknęło w pół zdania.

| Koniec logu | Co się stało | Skutki |
|---|---|---|
| `Shutting down` → `Syncing filesystems` → `Journal stopped` | **czyste wyłączenie** (`poweroff`, *Shut Down Guest*) | dane zapisane, start bez niespodzianek |
| `Rebooting` zamiast `Power Off` | czysty restart | jak wyżej |
| zwykłe wpisy, nagle koniec | **twarde wyłączenie / zawieszenie / brak prądu** | ryzyko uszkodzonych plików (patrz [rozdział 8](#8-śledztwo-skąd-zepsuty-obraz-headlampa)) |
| `Kernel panic`, `BUG:`, `Out of memory` przed końcem | awaria jądra albo brak pamięci | przyczyna jest w tych linijkach |

> ⚠️ Pułapka: `grep "Journal stopped"` w uruchomieniu -2 też coś znajdzie – wpis z **20:14:15**, czyli
> z **początku** tego uruchomienia. Przy starcie Ubuntu dziennik z wczesnej fazy (initramfs) zatrzymuje się
> i przechodzi do właściwego systemu. Liczy się to, co jest **na końcu**, a nie samo wystąpienie słowa.

## 5. Usługa k3s: `-u k3s-agent`

Na workerach k3s działa jako usługa **`k3s-agent`**, na masterze – **`k3s`**. W niej są kubelet, flannel
i połączenie z masterem, a containerd ma swój osobny proces, którego wpisy też tu trafiają.

**Zatrzymanie** – koniec poprzedniego uruchomienia:

```bash
journalctl -u k3s-agent -b -1 -n 6 --no-pager -o short-iso
```

```text
2026-11-10T09:21:39+01:00 k3s-worker-1 systemd[1]: k3s-agent.service: Unit process 4311 (containerd-shim) remains running after unit stopped.
2026-11-10T09:21:39+01:00 k3s-worker-1 systemd[1]: Stopped k3s-agent.service - Lightweight Kubernetes.
2026-11-10T09:21:39+01:00 k3s-worker-1 systemd[1]: k3s-agent.service: Consumed 4h 37min 12.799s CPU time over 4d 12h 31min 54.349s wall clock time, 542.4M memory peak.
```

- k3s zatrzymał się o **09:21:39** – 4 s przed końcem systemu.
- `containerd-shim … remains running` – kontenery (każdy ma swój „shim”) działają chwilę dłużej niż sam k3s;
  zatrzyma je dopiero `SIGTERM` przy wyłączaniu systemu. Przy zwykłym restarcie usługi k3s kontenery dzięki temu
  **nie** padają.
- `Consumed 4h 37min CPU … over 4d 12h` – statystyka usługi za całe uruchomienie; `542.4M memory peak` –
  najwięcej RAM-u, ile zajął agent k3s.

**Start** – początek bieżącego uruchomienia, tylko najważniejsze wpisy:

```bash
journalctl -u k3s-agent -b 0 --no-pager -o short-iso | grep -m6 -E "Starting|Connecting to proxy|Remotedialer connected"
```

```text
2026-11-10T09:55:58+01:00 k3s-worker-1 systemd[1]: Starting k3s-agent.service - Lightweight Kubernetes...
2026-11-10T09:55:59+01:00 k3s-worker-1 k3s[1576]: … msg="Starting k3s agent v1.36.5+k3s1 (3dd98cc5)"
2026-11-10T09:56:00+01:00 k3s-worker-1 k3s[1576]: … msg="Starting flannel with backend vxlan"
2026-11-10T09:56:00+01:00 k3s-worker-1 k3s[1576]: … msg="Connecting to proxy" url="wss://192.168.180.51:6443/v1-k3s/connect"
2026-11-10T09:56:00+01:00 k3s-worker-1 k3s[1576]: … msg="Remotedialer connected to proxy" url="wss://192.168.180.51:6443/v1-k3s/connect"
```

| Wpis | Znaczy |
|---|---|
| `Starting k3s agent v1.36.5+k3s1` | wersja – przy aktualizacjach sprawdzasz, czy węzeł ma tę samą co master |
| `Starting flannel with backend vxlan` | sieć podów (`10.42.x.x`) między węzłami, tunelowana VXLAN-em |
| `Connecting to proxy … 192.168.180.51:6443` | agent łączy się z API na masterze |
| `Remotedialer connected` | **połączenie z masterem jest** – od tej chwili węzeł może wrócić do `Ready` |

Od startu systemu (09:55:52) do połączenia z masterem minęło 8 s. Gdy węzeł nie wraca do `Ready`, tu szukasz
błędów: brak `Remotedialer connected`, `connection refused` / `timeout` do `:6443` (firewall, master),
`x509` (certyfikaty, zegar).

## 6. Tylko błędy: `-p err`

```bash
journalctl -b 0 -p err --no-pager -o short-iso | head -8
```

`-p err` – wagi `err` i poważniejsze (`crit`, `alert`, `emerg`). Wynik z worker-1:

```text
2026-11-10T09:55:56+01:00 k3s-worker-1 kernel: piix4_smbus 0000:00:07.3: SMBus Host Controller not enabled!
2026-11-10T09:56:15+01:00 k3s-worker-1 chronyd[1601]: NTS-KE session with 91.189.91.113:4460 (4.ntp.ubuntu.com) timed out
2026-11-10T09:56:48+01:00 k3s-worker-1 chronyd[1601]: NTS-KE session with 91.189.91.113:4460 (4.ntp.ubuntu.com) timed out
```

Błąd w dzienniku **nie zawsze** oznacza problem – trzeba umieć go ocenić:

- **`SMBus Host Controller not enabled!`** – sterownik szuka kontrolera sprzętowego, którego wirtualna płyta
  VMware nie udostępnia. Pojawia się na każdej maszynie VMware przy każdym starcie. **Ignorować.**
- **`NTS-KE session … timed out`** – chrony (synchronizacja zegara) nie może się dogadać z jednym serwerem czasu
  (`4.ntp.ubuntu.com`) przez szyfrowane NTS. Sprawdzenie:

  ```bash
  timedatectl | grep synchronized; chronyc -n sources | head -5
  ```

  ```text
  System clock synchronized: yes
  ^* 185.125.190.122               2   6   377    44  +2409us[ +196us] +/-   20ms
  ^? 91.189.91.113                 0   6     0     -     +0ns[   +0ns] +/-    0ns
  ```

  Zegar jest zsynchronizowany z innym serwerem (`^*` – wybrany, `377` – wszystkie ostatnie próby udane);
  niedostępny jest tylko jeden z pięciu (`^?`, `Reach 0`). **Na razie bez znaczenia.** Gdyby zegar się
  rozjechał, k3s zgłaszałby błędy certyfikatów `x509: certificate has expired or is not yet valid`.

Zasada: **porównaj ze zdrowym węzłem.** Ten sam błąd na wszystkich, także zdrowych maszynach, to zwykle szum.

## 7. Czas, szukanie, na żywo

| Polecenie | Do czego |
|---|---|
| `journalctl --since "2026-11-10 09:15" --until "2026-11-10 09:25"` | okno czasowe – np. wokół godziny z `LastHeartbeatTime` w `describe node` |
| `journalctl --since "30 min ago"` | ostatnie pół godziny |
| `journalctl -u k3s-agent -g "error\|fail"` | szukanie tekstu (wyrażenie regularne, bez rozróżniania wielkości liter przy małych literach) |
| `journalctl -u k3s-agent -f` | na żywo, jak `tail -f` – np. podczas restartu usługi; `Ctrl+C` kończy |
| `journalctl -k -b -1` | tylko jądro z poprzedniego uruchomienia – przy podejrzeniu awarii sprzętu / sterowników |
| `-o short-iso` | daty z rokiem i strefą (`2026-11-10T09:21:39+01:00`) – łatwiej porównać z UTC w Prometheusie |

**Łączenie źródeł po czasie** – w teście B te same minuty widać w czterech miejscach:

| Źródło | Godzina | Wpis |
|---|---|---|
| `journalctl -u k3s-agent -b -1` | 09:21:39 | `Stopped k3s-agent.service` |
| `journalctl -b -1` | 09:21:43 | `Journal stopped` – system wyłączony |
| healthchecks.io (e-mail) | 09:28:34 | `DOWN`, „Last Ping 7 minutes ago” |
| `journalctl -u k3s-agent -b 0` | 09:56:00 | `Remotedialer connected` – węzeł wraca |

Tak odtwarza się przebieg incydentu do raportu (*post-mortem*).

## 8. Śledztwo: skąd zepsuty obraz Headlampa

W [Etapie 6](../etap-6-gui/problemy.md#headlamp-w-crashloopbackoff-exit-code-139-puste-logi-po-awarii-hosta)
Headlamp przez 3 dni padał z `Exit Code 139` na worker-1 i zadziałał dopiero z obrazem pobranym od nowa.
Podejrzenie: uszkodzony plik po twardym wyłączeniu. Dziennik worker-1 to potwierdza:

```bash
journalctl -b -2 --no-pager -o short-iso | grep -i headlamp | grep "startup duration"
```

```text
2026-11-05T20:21:17+01:00 k3s-worker-1 k3s[1516]: … "Observed pod startup duration" pod="headlamp/headlamp-6ff8f74776-c54rb" … podStartE2EDuration="1m14.081416912s"
```

- **20:21:17** – pod Headlampa wystartował po **1 min 14 s**, czyli obraz (108 MB) był właśnie pobierany
  i rozpakowywany na dysk;
- **20:21:33** – ostatni wpis tego uruchomienia, **16 sekund później**, bez sekwencji wyłączania.

Linux nie zapisuje danych na dysk od razu – trzyma je chwilę w pamięci (cache) i zapisuje partiami. Świeżo
rozpakowane pliki obrazu w dużej części były jeszcze tylko w pamięci, gdy maszyna straciła zasilanie. Po
starcie containerd uważał obraz za kompletny („already present on machine”), a w środku były niepełne pliki →
program padał z naruszeniem pamięci (SIGSEGV, kod 139). Czyste wyłączenie zrobiłoby najpierw `Syncing filesystems`.

## 9. Ściąga

| Zadanie | Polecenie |
|---|---|
| lista uruchomień | `journalctl --list-boots` |
| jak skończyło się poprzednie uruchomienie | `journalctl -b -1 -n 20 --no-pager` |
| logi k3s na workerze / masterze | `journalctl -u k3s-agent` / `journalctl -u k3s` |
| start k3s w bieżącym uruchomieniu | `journalctl -u k3s-agent -b 0 \| grep -E "Starting\|Remotedialer"` |
| tylko błędy | `journalctl -b 0 -p err` |
| okno czasowe | `journalctl --since "… 09:15" --until "… 09:25"` |
| szukanie tekstu | `journalctl -u k3s-agent -g "x509\|refused"` |
| na żywo | `journalctl -u k3s-agent -f` |
| jądro, poprzednie uruchomienie | `journalctl -k -b -1` |
| zegar | `timedatectl`, `chronyc sources` |

## 10. Ćwiczenia

Wszystkie na 🐧 `k3s-worker-1` (`ssh k3s-worker-1`), chyba że zaznaczono inaczej.

1. Wypisz listę uruchomień. Które uruchomienie trwało najkrócej i co mogło się wtedy stać?
2. Sprawdź, jak skończyło się uruchomienie `-1`. Czyste wyłączenie czy awaria? Po czym poznajesz?
3. To samo dla uruchomienia `-2`. Jaki był ostatni wpis i o której?
4. O której w bieżącym uruchomieniu agent k3s połączył się z masterem?
5. Wypisz błędy z bieżącego uruchomienia i oceń każdy: problem czy szum? Porównaj z `k3s-worker-2`.
6. 🐧 k3s-master: o której worker-1 wrócił do `Ready`? Porównaj z godziną `Remotedialer connected` z ćwiczenia 4.
7. Na drugim terminalu uruchom `journalctl -u k3s-agent -f`, a na pierwszym `sudo systemctl restart k3s-agent`.
   Co widzisz? Czy pody na tym węźle się zrestartowały (`kubectl get pods -A -o wide` na masterze)?

### Rozwiązania

```bash
# 1
journalctl --list-boots
# 2 – ostatnie linie: Shutting down, Syncing filesystems, Journal stopped = czyste wyłączenie
journalctl -b -1 -n 20 --no-pager
# 3 – 20:21:33, wpis apparmor/audit, bez sekwencji wyłączania = awaria (05.11)
journalctl -b -2 -n 5 --no-pager -o short-iso
# 4 – 09:56:00, "Remotedialer connected to proxy"
journalctl -u k3s-agent -b 0 --no-pager | grep -m1 "Remotedialer connected"
# 5 – SMBus = szum VMware (jest na każdym węźle), NTS-KE timeout = jeden serwer czasu, zegar zsynchronizowany
journalctl -b 0 -p err --no-pager
ssh k3s-worker-2 'journalctl -b 0 -p err --no-pager'
# 6 – kolumna LastTransitionTime w wierszu Ready: kilka sekund po "Remotedialer connected"
#     (master przyjmuje pierwszy raport kubeleta). Uwaga: journalctl -u k3s na masterze przy domyślnym
#     poziomie logów prawie nie wspomina nazw węzłów – stan węzła sprawdzasz przez kubectl, nie przez dziennik.
kubectl describe node k3s-worker-1 | grep -A8 Conditions
# 7 – w logu: Stopping/Stopped/Starting k3s-agent, Remotedialer connected; pody NIE restartują się
#     (kontenery działają w containerd-shim niezależnie od procesu k3s), licznik RESTARTS bez zmian
```

## 11. Pytania rekrutacyjne

- **Serwer się zrestartował w nocy. Jak sprawdzisz, czy ktoś go wyłączył, czy padł?** – `journalctl --list-boots`,
  potem `journalctl -b -1 -n 50`. Czyste wyłączenie kończy się `Shutting down` / `Journal stopped` (wcześniej
  w `last -x` też widać `shutdown`/`reboot`). Awaria – log urywa się w pół pracy; szukam przed końcem
  `Kernel panic`, `Out of memory`, błędów sprzętu (`-k`, `-p err`). Jeśli nic – zasilanie albo hypervisor.
- **Węzeł Kubernetesa nie wraca do `Ready` po restarcie. Gdzie patrzysz?** – na węźle `systemctl status k3s-agent`
  (albo `kubelet`) i `journalctl -u … -b 0`: czy łączy się z API (`:6443`), błędy `x509` (certyfikaty, zegar),
  `connection refused/timeout` (firewall, master), containerd, brak miejsca na dysku.
- **Dlaczego restart usługi k3s nie zabija kontenerów?** – kontenery działają pod procesami `containerd-shim`,
  niezależnie od procesu agenta. Agent po starcie odnajduje je i przejmuje. Zatrzymują się dopiero przy wyłączeniu
  systemu albo przy `k3s-killall.sh`.
- **Co znaczy `Syncing filesystems` i dlaczego twarde wyłączenie może uszkodzić dane?** – Linux trzyma zapisy
  chwilę w pamięci (page cache) i zapisuje na dysk partiami. Przy czystym wyłączeniu wszystko jest dopisywane
  (`sync`); przy utracie zasilania ostatnie zmiany giną, pliki mogą być niepełne.
