# Etap 7 – CI/CD – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## packer validate: Missing plugins (github.com/hashicorp/vmware)

- **Objaw:** `packer validate` kończy się `Error: Missing plugins … github.com/hashicorp/vmware >= 1.1.0 …
  Did you run packer init for this project?`, choć ten sam przepis zbudował wcześniej worker-3.
- **Przyczyna:** pluginy Packera leżą osobno (`%APPDATA%\packer.d\plugins`), nie w repozytorium. Po miesiącu
  (aktualizacja Packera, czyszczenie katalogu) pluginu już nie było.
- **Diagnoza:** sam komunikat – nazwa pluginu i wersja z bloku `required_plugins` w `k3s-node.pkr.hcl`.
- **Rozwiązanie:** 🪟 `packer init .` w folderze `packer` – pobiera brakujące pluginy, potem `validate` → valid.
- **Wniosek:** `packer init` to odpowiednik `terraform init` / `ansible-galaxy install` – uruchamiaj go
  zawsze na nowym komputerze i po aktualizacji Packera.

## ssh gitlab: user@192.168.180.56: Permission denied (publickey)

- **Objaw:** po dopisaniu `Host gitlab` + `HostName 192.168.180.56` do `~/.ssh/config` połączenie
  odrzucone, a w komunikacie użytkownik **`user`** (nazwa konta Windows), nie `grzegorz`.
- **Przyczyna:** wspólne ustawienia (`User grzegorz`, `IdentityFile ~/.ssh/k3s-lab`, `IdentitiesOnly yes`)
  są w osobnym bloku `Host k3s-master … monitoring 192.168.180.*`. Wzorzec `Host` jest porównywany
  z nazwą **wpisaną w poleceniu** (`gitlab`), nie z `HostName` – więc `192.168.180.*` nie pasował.
- **Diagnoza:** nazwa użytkownika w komunikacie błędu; `ssh -G gitlab | findstr /b "user identityfile"`
  pokazuje ustawienia, które SSH naprawdę wybrał.
- **Rozwiązanie:** dopisać `gitlab` do linii `Host k3s-master k3s-worker-1 … monitoring gitlab 192.168.180.*`.
- **Wniosek:** nowa maszyna = dwa miejsca w `~/.ssh/config`: adres i grupa ze wspólnymi ustawieniami.

## This job is stuck because the project doesn't have any runners online assigned to it

- **Objaw:** pierwszy pipeline wisi jako *Pending* (pomarańczowa ikonka przy commicie), w zadaniu `hello`
  żółta ramka z tym komunikatem – mimo że Runner `monitoring-docker` w **Settings → CI/CD → Runners** jest
  *Online* (Idle), a `sudo gitlab-runner verify` daje `is valid`.
- **Przyczyna:** Runner ma tag `docker` i **nie** bierze zadań bez tagów (*Run untagged jobs* odznaczone),
  a zadanie `hello` nie miało żadnego tagu. Żaden Runner „nie pasuje”, więc GitLab nie wydaje zadania.
- **Diagnoza:** log Runnera (`journalctl -u gitlab-runner` – działa bez `sudo` dla grupy `adm`) bez błędów,
  ale `builds=0`; strona zadania mówi, czego brakuje; na liście Runnerów: status, tagi, *Paused*.
- **Rozwiązanie:** w `.gitlab-ci.yml` blok `default: tags: [docker]` – tag dla wszystkich zadań. Nowy push →
  pipeline zielony (commit `ea3a755`). Stary pipeline anulować (**Build → Pipelines → Cancel**).
  Prostsza droga: ✏️ przy Runnerze → *Run untagged jobs* – ale wtedy Runner bierze wszystko.
- **Wniosek:** tagi decydują, który Runner weźmie zadanie (Docker, GPU, Windows, produkcja). Jawny tag
  w każdym zadaniu jest bezpieczniejszy niż Runner „bierze wszystko”.

## Failed to load config – Key 'runners.docker.volumes' has already been defined

- **Objaw:** po dopisaniu `docker.sock` do `/etc/gitlab-runner/config.toml` w logu Runnera
  (`journalctl -u gitlab-runner`) `ERROR: Failed to load config … toml: line 42 (last key "runners.docker.volumes"):
  Key 'runners.docker.volumes' has already been defined`; po usunięciu jednej linii – to samo dla `volume_keep`.
- **Przyczyna:** nowa linia `volumes` dopisana obok starej (dwa razy ten sam klucz w sekcji = błąd TOML), a potem
  wklejony cały fragment z `volume_keep`, `shm_size`, `network_mtu`, które w pliku już były. Runner **nie wczytuje**
  błędnego pliku i działa dalej na poprzedniej konfiguracji – bez sygnału w GitLabie.
- **Diagnoza:** `sudo grep -n -E 'volume|shm_size|network_mtu|disable_cache' /etc/gitlab-runner/config.toml` – numery
  linii pokazały duplikaty 42–44 (`grep` po wybranych kluczach, żeby nie wyświetlać linii z tokenem).
- **Rozwiązanie:** `sudo sed -i '42,44d' /etc/gitlab-runner/config.toml` (usuń linie 42–44); w logu `Configuration loaded`.
  Pułapka: `sed` wklejony za zaznaczonym poprzednim poleceniem dokleił się do linii `grep` – najpierw Ctrl+C, potem wklejanie.
- **Wniosek:** po każdej zmianie `config.toml` sprawdź `journalctl -u gitlab-runner`. `sed -i` nie pyta i nie robi
  kopii – najpierw `grep -n`, ewentualnie `sed -i.bak`.

## app.py w obrazie z prawami 666 (-rw-rw-rw-)

- **Objaw:** `docker run --rm --entrypoint sh …/hello-lab:729765dc -c "ls -la /app"` → `-rw-rw-rw- root root app.py`,
  choć aplikacja działa jako `app` (uid 10001) – każdy w kontenerze może zmienić kod. gitleaks, Semgrep i Trivy – zielone.
- **Przyczyna:** GitLab Runner z executorem Docker klonuje repozytorium z `umask 0000`, pliki dostają 666, a `COPY`
  w `Dockerfile` przenosi prawa do obrazu. Przy ręcznym budowaniu (Etap 4, `umask` 0002/0022) problemu nie było.
- **Rozwiązanie:** `COPY --chmod=644 app.py .` → w obrazie `8480121a`: `-rw-r--r--`.
- **Wniosek:** pipeline może wprowadzić słabość, której nie widać w kodzie; skanery nie łapią wszystkiego – ręczna
  kontrola zbudowanego obrazu (`id`, `ls -la`) uzupełnia automaty.
