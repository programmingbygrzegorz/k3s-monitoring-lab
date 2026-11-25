# Maszyna `gitlab` i instalacja GitLab CE

Przebieg z labu (25.11.2026), wykonany przez właściciela krok po kroku.

## Dlaczego osobna maszyna

GitLab CE potrzebuje sam ok. 4–6 GB RAM (nginx, PostgreSQL, Redis, Puma, Sidekiq, Gitaly). W klastrze
zabrałby miejsce aplikacjom, a gdy klaster padnie, nie dałoby się nim wdrożyć poprawki. W firmach CI/CD
stoi **obok** klastra produkcyjnego.

| Parametr | worker-3 (domyślne z przepisu) | gitlab |
|---|---|---|
| CPU | 2 | **4** |
| RAM | 6144 MB | **8192 MB** |
| dysk | 40960 MB | **61440 MB** (repozytoria, rejestr obrazów, kopie) |
| IP / MAC | .55 / `…:01:55` | **.56 / `…:01:56`** |

## Krok 1. Plik parametrów maszyny

Ten sam przepis co dla worker-3 (`packer/k3s-node.pkr.hcl`), nowy plik parametrów – poza gitem
(`.gitignore`: `packer/*.pkrvars.hcl`):

```powershell
cd C:\Projekty\k3s-monitoring-lab\packer          # 🪟
copy k3s-worker-3.pkrvars.hcl gitlab.pkrvars.hcl
notepad gitlab.pkrvars.hcl
```

```hcl
node_name        = "gitlab"
node_ip          = "192.168.180.56"
node_mac         = "00:50:56:00:01:56"
memory           = 8192
cpus             = 4          # nie było w pliku worker-3 – tam wystarczała wartość domyślna (2)
disk_size        = 61440      # j.w. (domyślnie 40960)
output_directory = "C:/Users/User/Documents/Virtual Machines/gitlab"

lab_hosts = {
  # … pięć dotychczasowych maszyn …
  "gitlab"       = "192.168.180.56"
}
```

Zasada Packera: wartość z `.pkrvars.hcl` wygrywa, brak wartości = `default` z bloku `variable` w przepisie.
Pułapka: po `copy` plik ma jeszcze `node_name = "k3s-worker-3"` – zbudowanie go bez zmian dałoby drugi
worker-3 z tym samym IP.

## Krok 2. Sprawdzenie i budowa

```powershell
packer init .                                                                       # 🪟 pobiera plugin vmware
packer validate "-var-file=gitlab.pkrvars.hcl" "-var-file=secrets.pkrvars.hcl" .    # The configuration is valid.
packer build    "-var-file=gitlab.pkrvars.hcl" "-var-file=secrets.pkrvars.hcl" .
```

`packer init` był potrzebny, bo pluginu już nie było ([problem](problemy.md#packer-validate-missing-plugins-githubcomhashicorpvmware)).

Wynik `build` (skrócony):

```
==> vmware-iso.k3s_node: Trying C:/Users/User/Downloads/ubuntu-26.04.1-live-server-amd64.iso
==> vmware-iso.k3s_node: Creating virtual machine disks...
==> vmware-iso.k3s_node: Starting HTTP server on port 8053
==> vmware-iso.k3s_node: Typing the boot command over VNC...
==> vmware-iso.k3s_node: Using SSH communicator to connect: 192.168.180.56
==> vmware-iso.k3s_node: Waiting for SSH to become available...
==> vmware-iso.k3s_node: Connected to SSH!
==> vmware-iso.k3s_node: Provisioning with shell script: ...
==> vmware-iso.k3s_node: Cloning into '/home/grzegorz/k3s-monitoring-lab'...
==> vmware-iso.k3s_node: Gracefully halting virtual machine...
Build 'vmware-iso.k3s_node' finished after 9 minutes 35 seconds.
--> vmware-iso.k3s_node: VM files in directory: C:/Users/User/Documents/Virtual Machines/gitlab
```

| Linia | Co się dzieje |
|---|---|
| `Trying …iso` | ISO z dysku (nie z internetu), sprawdzenie sumy `sha256` |
| `Starting HTTP server` | Packer wystawia wypełniony `user-data.pkrtpl.yaml` dla instalatora (autoinstall) |
| `Typing the boot command over VNC` | Packer sam wpisuje polecenie startu instalatora |
| `Waiting for SSH` | ok. 7 min – Ubuntu instaluje się bez klikania |
| `Provisioning` | `/etc/hosts` z `lab_hosts`, wyłączenie logowania hasłem przez SSH |
| `Cloning into` | repozytorium labu na maszynie |
| `Gracefully halting` | maszyna wyłączona, gotowa |

Skąd co pochodzi: ISO z `Pobranych`, klucz publiczny z `C:\Users\User\.ssh\k3s-lab.pub` (`file()` w przepisie
→ `authorized-keys` w `user-data`), hasło z `secrets.pkrvars.hcl`. Opis przepisu: [packer/README.md](../../packer/README.md).

## Krok 3. VMware i SSH

1. 🪟 VMware: **File → Open** → `…\Virtual Machines\gitlab\gitlab.vmx` → **Power on** (Packer tworzy pliki,
   ale nie dopisuje maszyny do biblioteki).
2. 🪟 `notepad C:\Users\User\.ssh\config` – dwa miejsca:

```
Host gitlab
    HostName 192.168.180.56

Host k3s-master k3s-worker-1 k3s-worker-2 k3s-worker-3 monitoring gitlab 192.168.180.*
    User grzegorz
    IdentityFile ~/.ssh/k3s-lab
    IdentitiesOnly yes
```

3. 🪟 `ssh gitlab` → przy pierwszym połączeniu `yes` (odcisk nowej maszyny) → `grzegorz@gitlab:~$`.
   Bez `gitlab` w drugiej linii: `user@192.168.180.56: Permission denied (publickey)`
   ([problem](problemy.md#ssh-gitlab-user19216818056-permission-denied-publickey)).

Sprawdzenie (🐧 gitlab): `lsb_release -cs` → `resolute`, `free -g` → 7 GB, `nproc` → 4, `df -h /` → 59G, wolne 49G.

## Krok 4. 📸 Snapshot – `2026-11-25 czysta po Packerze`

## Krok 5. Repozytorium pakietów GitLaba

GitLaba nie ma w repozytoriach Ubuntu – źródło pakietów dodaje skrypt firmy GitLab (dla `resolute` dostępne):

```bash
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh -o gitlab-repo.sh   # 🐧 gitlab
less gitlab-repo.sh          # przeczytaj, zanim uruchomisz
sudo bash gitlab-repo.sh     # The repository is setup! You can now install packages.
```

Instrukcja GitLaba podaje `curl … | sudo bash` – to uruchamia jako root kod z internetu bez czytania.
Pobranie do pliku, przejrzenie i dopiero uruchomienie to dobra praktyka (i pytanie na rozmowie AppSec).

## Krok 6. Instalacja GitLab CE

```bash
sudo EXTERNAL_URL="http://192.168.180.56" apt install -y gitlab-ce     # 🐧 gitlab, ok. 10 min
```

| Część | Co robi |
|---|---|
| `sudo` | uruchamia jako root (instalacja pakietów) |
| `EXTERNAL_URL="http://192.168.180.56"` | zmienna środowiskowa **tylko dla tego polecenia**; skrypt instalacyjny pakietu wpisuje ją do `/etc/gitlab/gitlab.rb` jako `external_url` – adres, pod którym GitLab się przedstawia (linki, klonowanie, przekierowania) |
| `apt install -y gitlab-ce` | pakiet „Omnibus”: GitLab + nginx, PostgreSQL, Redis, Gitaly, Prometheus – wszystko w jednym, w `/opt/gitlab` |

Po rozpakowaniu instalator sam uruchamia `gitlab-ctl reconfigure` – Chef czyta `gitlab.rb` i konfiguruje
wszystkie usługi. Na razie `http`: HTTPS (certyfikat z CA labu) można dodać później zmianą `external_url`.

Wynik: GitLab CE **19.6.1** (`dpkg -l gitlab-ce`), strona logowania `http://192.168.180.56/users/sign_in` → `200`.

## Krok 7. Pierwsze logowanie i zabezpieczenie

Hasło konta `root` generuje instalator (plik znika po 24 h):

```bash
sudo cat /etc/gitlab/initial_root_password     # 🐧 gitlab – hasła nie wklejaj nigdzie
```

Po zalogowaniu GitLab sam pokazuje dwa ostrzeżenia bezpieczeństwa:

| Ostrzeżenie | Ryzyko | Co zrobione |
|---|---|---|
| *Check the restrictions for new users* | każdy w sieci może założyć konto (`/users/sign_up`) i uruchamiać pipeline'y na runnerach | **Admin → Settings → General → New user account restrictions** → odznaczone *Allow new user accounts* → na stronie logowania nie ma już „Register now” |
| *Web IDE single origin fallback is enabled* | gdy domena `cdn.web-ide.gitlab-static.net` jest niedostępna, edytor VS Code ładuje się z adresu GitLaba – kod rozszerzeń działa wtedy w tej samej domenie co sesja użytkownika (same-origin policy) | **Admin → Settings → General → Web IDE** → odznaczone *Enable single origin fallback* (domena rozszerzeń bez zmian) |

Hasło roota zmienione na własne (**Edit profile → Password**), plik `initial_root_password` do usunięcia
(`sudo rm`). Odzyskanie hasła z serwera: `sudo gitlab-rake "gitlab:password:reset[root]"` – kto ma `sudo` na
maszynie, ma cały GitLab.

## Krok 8. Własne konto zamiast `root`

Na co dzień nie pracuje się jako administrator (zasada najmniejszych uprawnień, jak `sudo` na Linuksie):

1. **Admin → Users → New user**: `grzegorz`, e-mail `grzegorz@lab.local`, **Access level: Regular**;
   hasło tymczasowe przez **Edit** (poczty nie ma) – przy pierwszym logowaniu GitLab każe je zmienić.
2. Grupa `lab` → **Manage → Members → Invite members** → `grzegorz`, rola **Owner** – uprawnienia
   dziedziczą wszystkie projekty grupy (`lab/hello-lab` też).

Kreator przy pierwszym logowaniu roota założył grupę `lab` i pusty, prywatny projekt `hello-lab`
(`http://192.168.180.56/lab/hello-lab`).

## Krok 9. Osobny klucz SSH do GitLaba

Klucz `k3s-lab` otwiera wszystkie serwery labu – nie dokładamy mu dostępu do kodu. Osobny klucz tylko do gita:

```powershell
ssh-keygen -t ed25519 -f C:\Users\User\.ssh\gitlab-lab -C "gitlab-lab"      # 🪟
Get-Content C:\Users\User\.ssh\gitlab-lab.pub | Set-Clipboard
```

GitLab (jako `grzegorz`): **Edit profile → SSH Keys → Add new key**. Jeden klucz = jedno konto – przy próbie
dodania tego samego klucza drugiemu kontu: `Fingerprint has already been taken`.

Wpis w `C:\Users\User\.ssh\config`:

```
# GitLab w labie – tylko git push/pull, osobny klucz
Host gitlab-git
    HostName 192.168.180.56
    User git
    IdentityFile ~/.ssh/gitlab-lab
    IdentitiesOnly yes
```

`ssh -T gitlab-git` → `Welcome to GitLab, @grzegorz!`. Wszyscy łączą się jako systemowy użytkownik `git`
(założony przez Omnibus); GitLab dopisuje każdy klucz do `/var/opt/gitlab/.ssh/authorized_keys` z
`command="gitlab-shell key-N"` – po kluczu rozpoznaje osobę, a powłoki nie daje.

Adres `git@192.168.180.56:lab/hello-lab.git` (podpowiadany przez GitLab) by nie zadziałał: pasuje do bloku
`Host … 192.168.180.*` z kluczem `k3s-lab`, którego GitLab nie zna. Alias `gitlab-git` wybiera właściwy klucz.

## Krok 10. Kod `hello-lab` w GitLabie

Aplikacja z Etapu 4 (`apps/hello-lab`) jako osobne repozytorium:

```powershell
mkdir C:\Projekty\hello-lab                                                       # 🪟
cd C:\Projekty\hello-lab
copy C:\Projekty\k3s-monitoring-lab\apps\hello-lab\Dockerfile, C:\Projekty\k3s-monitoring-lab\apps\hello-lab\app.py .
git init -b main
git config user.name "Grzegorz"                 # bez --global: tylko to repo
git config user.email "grzegorz@lab.local"      # ten sam e-mail co konto w GitLabie
git add Dockerfile app.py
git commit -m "hello-lab: kod aplikacji i Dockerfile (z Etapu 4)"
git remote add origin git@gitlab-git:lab/hello-lab.git
git push -u origin main
```

Pułapki po drodze:

| Komunikat | Przyczyna |
|---|---|
| `fatal: pathspec 'Dockerfile' did not match any files` | pominięte `copy` – pusty folder |
| `warning: LF will be replaced by CRLF` | tylko ostrzeżenie: `core.autocrlf=true` – w repo `LF`, na dysku Windows `CRLF` |
| `error: src refspec main does not match any` | brak commita – gałąź `main` jeszcze nie istnieje |
| `error: remote origin already exists` | `remote add` wykonane wcześniej – pominąć |

Wynik: commit `14f055d` w GitLabie. GitLab od razu uruchomił **pipeline nr 1 – Auto DevOps** (gotowy pipeline,
gdy brak `.gitlab-ci.yml`), wiszący jako *pending*, bo nie ma Runnera. Wyłączone: projekt → **Settings → CI/CD →
Auto DevOps** → odznaczone *Default to Auto DevOps pipeline*. Na produkcji zwykle wyłączone globalnie – zamiast
tego jawne pipeline'y ze wspólnych szablonów (`include:`).

## Dalej

GitLab Runner (executor `docker`) na `monitoring` – osobno od serwera GitLab, bo zadania uruchamiają kod
z każdego commita.

## Pytania rekrutacyjne

- *Po co Packer, skoro można sklonować maszynę?* – przepis w gicie jest powtarzalny i przeglądalny;
  nowa maszyna to jeden plik parametrów i ~10 minut, bez ręcznego klikania i bez kopiowania tożsamości klonu.
- *Czym jest GitLab Omnibus?* – jeden pakiet ze wszystkimi składnikami GitLaba i Chefem, który je konfiguruje
  z jednego pliku `/etc/gitlab/gitlab.rb` (`gitlab-ctl reconfigure`).
- *Dlaczego nie `curl | sudo bash`?* – uruchamiasz jako root nieprzejrzany kod; podmiana po stronie serwera
  albo urwane pobieranie wykonuje się od razu. Bezpieczniej: pobierz, sprawdź, uruchom.
- *Co zabezpieczasz zaraz po instalacji GitLaba?* – wyłączenie samodzielnej rejestracji, własne hasło roota
  i usunięcie `initial_root_password`, osobne konto do pracy zamiast roota, Web IDE bez single origin fallback.
- *Dlaczego osobny klucz SSH do GitLaba?* – rozdzielenie uprawnień: kradzież jednego klucza nie daje naraz
  dostępu do serwerów i do kodu; klucz można unieważnić osobno.
- *Dlaczego runner nie stoi na serwerze GitLab?* – zadania wykonują kod z każdego commita; na tej samej maszynie
  złośliwy pipeline mógłby sięgnąć do bazy i sekretów GitLaba. Do tego budowanie obrazów zabiera RAM i CPU.
