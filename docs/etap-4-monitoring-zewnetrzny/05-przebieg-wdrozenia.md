# Etap 4 – przebieg wdrożenia krok po kroku (05.11.2026)

Zapis prawdziwej sesji: od przywrócenia maszyny `monitoring` i resetu rejestru, przez Dockera
i rejestr z TLS zbudowane od zera, po monitoring poza klastrem. Każdy krok ma polecenia, wyjaśnienie
i **wynik z labu** – tak jak wyszło, łącznie z rzeczami, które poszły inaczej niż w planie.

Różnica wobec [ćwiczeń](03-cwiczenia-obraz.md): ćwiczenia mówią, *co* zrobić; ten plik pokazuje,
*jak to wyglądało naprawdę* i dlaczego podjąłem takie decyzje. Dobry materiał do opowiedzenia
na rozmowie („przebudowałem rejestr obrazów, nie tracąc obrazu używanego przez klaster”).

Oznaczenia: 🪟 Windows (VMware, terminal), 🐧 maszyna w labie.

## Plan sesji (ok. 2 h)

| Krok | Co | Stan |
|---|---|---|
| 1 | Przywrócenie snapshotu `monitoring` i sprawdzenie | ✅ |
| 2 | Aktualne repozytorium, kopia obrazu `app`, snapshoty | ⏳ |
| 3 | Pełny reset rejestru, Dockera i CA | |
| 4 | Docker od zera (poziomy 0, 1, 3, 5 ćwiczeń) | |
| 5 | Rejestr z TLS i `app` z powrotem (poziom 6) | |
| 6 | k3s ufa rejestrowi, pody działają (poziom 7) | |
| 7 | Grafana, Uptime Kuma, healthchecks.io | |

Poziomy 2, 4 i 8 ćwiczeń (rozgrzewka i wycofanie wersji) celowo pominięte, żeby zmieścić się w czasie –
do zrobienia osobno.

---

## Stan wyjściowy

Przed sesją na `monitoring` było:

- rejestr `registry:3` z TLS na `192.168.180.54:5000` i Docker – postawione 03.11 przez Claude
  przy robieniu zrzutów do ćwiczeń; cel sesji: **zbudować je samemu**,
- w rejestrze dwa obrazy: `hello-lab:1.0` (z ćwiczeń) i **`app:1.0.0` – mój obraz z kursu
  Kubernetesa**, używany przez pod `default/app` w k3s,
- resztki po [ćwiczeniach z nginx i baz danych](../etap-1-przygotowanie-systemu/04-cwiczenia-nginx-bazy.md)
  z Etapu 1: działające nginx, PostgreSQL, MariaDB, wolumin `/data` i tymczasowy plik
  `/etc/sudoers.d/99-claude-tymczasowe` (sudo bez hasła – do usunięcia koniecznie).

Jak sprawdziłem, kto korzysta z obrazów w rejestrze, zanim cokolwiek skasowałem – opis metody
w [rozwiązaniach, sekcja „Najpierw: czy w rejestrze są Twoje inne obrazy?”](04-cwiczenia-obraz-rozwiazania.md#najpierw-czy-w-rejestrze-są-twoje-inne-obrazy).

**Decyzja:** zamiast sprzątać resztki ręcznie – przywrócić snapshot `przed-cwiczeniami-linux` maszyny
`monitoring` (z 04.11). Jest **późniejszy** niż obraz `app` (03.11), więc rejestr z `app` przetrwa,
a znikną nginx, bazy i plik sudo.

## Krok 1 – przywrócenie snapshotu `monitoring`

🪟 VMware Workstation:

1. **VM → Snapshot → Take Snapshot…** → `przed-revertem` – droga powrotu do stanu sprzed przywrócenia.
2. **VM → Snapshot → Snapshot Manager** → `przed-cwiczeniami-linux` → **Go To** → **Yes**.
3. Jeśli maszyna po przywróceniu jest wyłączona – **Power on**.

Przywracać można „na gorąco”, bez wyłączania maszyny. Snapshot zrobiony z pamięcią RAM wraca od razu
do działania; zrobiony przy wyłączonej maszynie – wraca wyłączony.

Sprawdzenie 🐧 monitoring:

```text
grzegorz@monitoring:~$ ls /etc/sudoers.d/
README
grzegorz@monitoring:~$ systemctl is-active nginx postgresql mariadb
inactive
inactive
inactive
grzegorz@monitoring:~$ docker ps --format "{{.Names}} {{.Image}} {{.Status}}"
rejestr registry:3 Up 43 hours
grzegorz@monitoring:~$ docker images | grep app
192.168.180.54:5000/app:1.0.0       159255640ed6        199MB         49.6MB
grzegorz@monitoring:~$ timedatectl | grep -E "Local time|synchronized"
               Local time: Thu 2026-11-05 13:45:28 CET
System clock synchronized: no
```

| Polecenie | Co sprawdza | Wynik |
|---|---|---|
| `ls /etc/sudoers.d/` | pliki z uprawnieniami sudo | ✅ tylko `README` – sudo bez hasła zniknęło |
| `systemctl is-active …` | czy działają usługi z ćwiczeń | ✅ wszystkie `inactive` |
| `docker ps --format …` | działające kontenery; `{{.Names}}` itd. to szablon wybierający kolumny | ✅ rejestr działa („Up 43 hours” – czas liczony razem z okresem zapisanym w snapshocie) |
| `docker images \| grep app` | czy obraz `app` jest lokalnie | ✅ jest, 199 MB |
| `timedatectl \| grep -E …` | data i synchronizacja zegara | ⚠️ data dobra, ale `synchronized: no` |

**Zegar po przywróceniu snapshotu.** Maszyna wróciła z pamięcią z 04.11 i przez chwilę „żyła w przeszłości”;
usługa synchronizacji czasu jeszcze nie złapała serwera. Do sprawdzenia przed wystawianiem certyfikatu
(krok 5) – certyfikat z datą z przeszłości lub przyszłości to klasyczna przyczyna błędów TLS.

## Krok 2 – aktualne repozytorium, kopia `app`, snapshoty

🐧 monitoring – snapshot cofnął też repozytorium, więc najpierw nowa wersja instrukcji:

```bash
cd ~/k3s-monitoring-lab && git pull --ff-only
```

Kopia obrazu `app` do pliku – reset usuwa wolumin rejestru (`docker volume rm rejestr-dane`)
i lokalne obrazy (`docker image prune -a -f`), czyli **obie** kopie:

```bash
docker save 192.168.180.54:5000/app:1.0.0 -o ~/kopia-app-1.0.0.tar
ls -lh ~/kopia-app-1.0.0.tar
```

🪟 VMware: snapshot `przed-etapem-4` pięciu maszyn – `monitoring`, `k3s-master`, `k3s-worker-1..3`
(reset zmienia pliki na węzłach k3s i je restartuje).

Wynik z labu:

```text
grzegorz@monitoring:~/k3s-monitoring-lab$ ls -lh ~/kopia-app-1.0.0.tar
-rw------- 1 grzegorz grzegorz 48M Nov  5 13:46 /home/grzegorz/kopia-app-1.0.0.tar
```

**Dlaczego 48 MB, a nie 199 MB?** `docker images` w Dockerze 29 pokazuje dwie liczby:
`199MB` to miejsce na dysku po **rozpakowaniu** warstw, a `49.6MB` to rozmiar **skompresowanych**
warstw – tak, jak przechowuje je rejestr. `docker save` zapisuje warstwy skompresowane, więc plik
ma ok. 48 MB i to jest poprawna, pełna kopia. Zawartość archiwum można podejrzeć bez rozpakowywania:

```bash
tar -tf ~/kopia-app-1.0.0.tar | head
```

(`tar -t` – wypisz zawartość, `-f` – z tego pliku). Widać `index.json`, `manifest.json` i katalog
`blobs/sha256/…` z warstwami – format OCI, ten sam, którego używa rejestr.

`-rw-------` – plik czyta tylko właściciel; `docker save` tworzy go z ostrożnymi uprawnieniami.

*Dalsze wyniki – dopisywane w trakcie.*
