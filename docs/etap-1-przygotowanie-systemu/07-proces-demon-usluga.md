# Proces, demon i usługa – od podstaw

Trzy pojęcia, które są ze sobą powiązane, ale nie oznaczają tego samego. Na każdym serwerze w labie
coś działa w tle bez otwartego terminala: SSH, k3s, nginx, Docker. Ten rozdział wyjaśnia, czym to
jest i jak tym zarządzać.

| Pojęcie | Co oznacza | Porównanie |
|---|---|---|
| **proces** | uruchomiony program | ktoś, kto teraz pracuje |
| **demon** | proces działający w tle, bez terminala, zwykle czeka na zlecenia | pracownik na zapleczu |
| **usługa** | jednostka systemd, która opisuje, jak program uruchomić, zatrzymać i pilnować | umowa o pracę: kiedy przychodzi, co robić, gdy zachoruje |

## 1. Proces – uruchomiony program

🐧 na dowolnej maszynie:

```bash
sleep 100
```

System utworzył proces `sleep`, który po 100 sekundach sam się zakończy. W drugim terminalu:

```bash
ps aux | grep sleep
```

Zobaczysz ten proces z jego numerem (PID). Zamkniesz terminal albo wciśniesz `Ctrl+C` – proces znika.
Tak samo w Windowsie: otwierasz Chrome, powstają procesy; zamykasz – kończą działanie.

## 2. Demon – proces w tle

Demon nie jest przywiązany do terminala, działa od startu systemu i czeka na pracę. Nazwy często
kończą się na `d` (od *daemon*).

| Demon | Co robi | Gdzie w labie |
|---|---|---|
| `sshd` | nasłuchuje połączeń SSH, sprawdza klucze, obsługuje sesje | wszystkie maszyny |
| `k3s server` / `k3s agent` | klaster Kubernetes | master / workery |
| `dockerd`, `containerd` | kontenery | `monitoring` |
| `systemd-journald` | zbiera logi | wszędzie |
| `cron` | uruchamia zadania o określonej porze | wszędzie |

```bash
pgrep -a sshd
```

Pokazuje PID i pełne polecenie każdego procesu `sshd` (`-a` = z argumentami).

## 3. Usługa – czym zarządza administrator

W Ubuntu usługami zarządza **systemd**. Każda usługa ma plik `.service`, np. `/etc/systemd/system/k3s.service`.

```bash
systemctl cat k3s
```

Kluczowe linie:

| Linia | Znaczenie |
|---|---|
| `ExecStart=` | jaki program uruchomić |
| `Restart=always` | podnieś go po każdej awarii |
| `After=network-online.target` | uruchom dopiero, gdy działa sieć |
| `WantedBy=multi-user.target` | uruchamiaj przy starcie systemu (po `enable`) |

Stany usługi w `systemctl status`:

| Stan | Znaczenie |
|---|---|
| `active (running)` | działa |
| `active (exited)` | wykonała zadanie i skończyła (typ `oneshot`) – to też poprawny stan |
| `inactive (dead)` | nie działa |
| `failed` | padła z błędem |

## 4. Jak to się łączy

```
systemctl start nginx
      │
      ▼
systemd czyta nginx.service → uruchamia ExecStart
      │
      ▼
proces „nginx: master process” (demon) + procesy robocze → obsługują ruch HTTP
```

`systemctl status nginx` pyta o **usługę**, ale pokazuje też **demona**:

```
● nginx.service - A high performance web server      ← usługa
     Loaded: loaded (…/nginx.service; enabled)        ← plik usługi, autostart włączony
     Active: active (running) since …                 ← stan usługi
   Main PID: 1234 (nginx)                             ← demon
     CGroup: /system.slice/nginx.service
             ├─1234 "nginx: master process …"         ← proces główny
             └─1235 "nginx: worker process"           ← proces roboczy
```

**Nie zawsze 1 do 1:**

- usługa bez demona – typ `oneshot`, robi coś raz i kończy (stan `active (exited)`);
- usługa z wieloma procesami – nginx ma proces główny i robocze, wszystkie w jednym `CGroup`;
- demon bez usługi – program puszczony ręcznie (`nohup program &`): działa, ale po restarcie maszyny
  nie wstanie i po awarii nikt go nie podniesie.

**Ubuntu 24.04+ i SSH:** port 22 trzyma `ssh.socket`, a `ssh.service` (demon `sshd`) systemd uruchamia
przy pierwszym połączeniu (*socket activation*). Dlatego po restarcie maszyny `ssh.service` bywa
`inactive`, a SSH i tak działa. Sprawdzaj oba: `systemctl status ssh.socket ssh.service`.

Wynik z `k3s-master` (Ubuntu 26.04, 12.11.2026):

```
$ systemctl is-active ssh.socket ssh.service
active
active
$ systemctl is-enabled ssh.socket ssh.service
enabled
disabled
```

`ssh.service` jest `disabled` (bez autostartu), a mimo to `active` – uruchomił go `ssh.socket`.
Nie „naprawiaj” tego przez `enable` – tak ma być.

## 5. Zarządzanie usługą

| Polecenie | Co robi |
|---|---|
| `sudo systemctl start nginx` | uruchamia **teraz** |
| `sudo systemctl stop nginx` | zatrzymuje **teraz** |
| `sudo systemctl restart nginx` | zatrzymuje i uruchamia (krótka przerwa) |
| `sudo systemctl reload nginx` | wczytuje konfigurację bez przerwy (nie każda usługa to umie) |
| `sudo systemctl enable nginx` | autostart przy uruchomieniu systemu |
| `sudo systemctl disable nginx` | wyłącza autostart |
| `sudo systemctl enable --now nginx` | autostart **i** start teraz |
| `systemctl list-units --type=service` | załadowane usługi |
| `systemctl --failed` | usługi z błędem |
| `journalctl -u nginx -n 50` | ostatnie 50 linii logów usługi |
| `journalctl -u nginx -f` | logi na żywo (`Ctrl+C` kończy) |

**`start` ≠ `enable`.** `start` działa teraz, ale po restarcie maszyny usługa nie wstanie.
`enable` ustawia autostart, ale nie uruchamia jej teraz. Po `systemctl status` widać oba:
`enabled`/`disabled` w linii `Loaded`, `active`/`inactive` w linii `Active`.

## 6. Usługa nie działa – procedura

Pytanie z rozmowy: *„Użytkownicy nie mogą połączyć się przez SSH. Co robisz?”*

1. Stan: `sudo systemctl status ssh.socket ssh.service`
2. Jeśli `failed` – logi: `sudo journalctl -u ssh -n 50`
3. Konfiguracja: `sudo sshd -t` (brak wyniku = poprawna, inaczej numer linii z błędem)
4. Po poprawce: `sudo systemctl restart ssh`
5. Sprawdzenie: `systemctl status ssh` i próba logowania **w drugim oknie** – pierwszej sesji nie
   zamykaj, dopóki nowa nie zadziała.
6. Gdy usługa działa, a połączenia nie ma – sieć i firewall: `ss -tlnp | grep :22`, `sudo ufw status`.

Ta sama kolejność działa dla każdej usługi: **status → logi → test konfiguracji → restart → sprawdzenie**.
Testy konfiguracji innych usług: `sudo nginx -t`, `sudo apachectl configtest`, `promtool check config`.

Prawdziwe przypadki z labu: [problemy Etapu 1](problemy.md) (sshd, systemd) i
[ćwiczenia admina, poziom z usługami](02-cwiczenia-admin-linux.md).

## Sprawdź się

1. Wpisałeś `systemctl start nginx`. Czy nginx wstanie po restarcie maszyny?
2. Które polecenie włącza autostart usługi?
3. Czym jest demon?
4. Usługa SSH ma stan `failed`. Gdzie sprawdzisz jej logi?
5. Czym różni się `restart` od `reload`?
6. Usługa ma stan `active (exited)`. Czy to błąd?
7. Po restarcie Ubuntu 24.04 `ssh.service` jest `inactive`, a mimo to logujesz się przez SSH. Dlaczego?

### Odpowiedzi

1. Nie – `start` uruchamia tylko teraz. Autostart ustawia `enable`.
2. `sudo systemctl enable nginx` (albo `enable --now`, żeby też uruchomić teraz).
3. Procesem działającym w tle, bez terminala, zwykle świadczącym usługę (np. `sshd`).
4. `journalctl -u ssh` (np. `-n 50` – ostatnie 50 linii).
5. `restart` zatrzymuje i uruchamia proces (krótka przerwa), `reload` każe działającemu procesowi
   wczytać konfigurację bez przerwy.
6. Nie – usługa typu `oneshot` wykonała zadanie i zakończyła się poprawnie.
7. Port 22 trzyma `ssh.socket`; systemd uruchamia `ssh.service` dopiero przy pierwszym połączeniu.

## Pytania rekrutacyjne

- **Czym różni się proces, demon i usługa?** – Proces to uruchomiony program; demon to proces w tle
  bez terminala; usługa to jednostka systemd, która nim zarządza: start przy bootowaniu, zależności,
  restart po awarii, logi w journald.
- **Jak sprawdzisz, dlaczego usługa nie wstała?** – `systemctl status`, potem `journalctl -u … -n 50`,
  test konfiguracji (`sshd -t`, `nginx -t`), poprawka, restart, ponowne sprawdzenie.
- **Co zrobisz po ręcznej zmianie pliku `.service`?** – `sudo systemctl daemon-reload`, potem restart usługi.
- **Jak bezpiecznie restartować SSH na zdalnym serwerze?** – najpierw `sshd -t`, potem restart,
  nowe logowanie w drugim oknie; pierwszej sesji nie zamykam, dopóki nowa nie działa.
