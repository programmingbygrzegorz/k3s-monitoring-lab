# 9. Ansible Vault – hasło sudo bez wpisywania

Do tej pory każde uruchomienie playbooka zaczynało się od `--ask-become-pass` i wpisania hasła
`sudo`. W labie to wystarcza, ale automatyzacja na produkcji ma działać **bez człowieka przy
klawiaturze** – z harmonogramu, z pipeline’u, w nocy. Ten rozdział pokazuje, jak przechować
hasło w pliku **zaszyfrowanym** przez Ansible Vault – najpierw ręcznie, krok po kroku.

## Spis treści

1. [Czym jest Ansible Vault](#1-czym-jest-ansible-vault)
2. [Jak to działa w tym labie](#2-jak-to-działa-w-tym-labie)
3. [Konfiguracja krok po kroku](#3-konfiguracja-krok-po-kroku)
4. [Codzienna praca z vaultem](#4-codzienna-praca-z-vaultem)
5. [Skąd Ansible bierze hasło do vaulta](#5-skąd-ansible-bierze-hasło-do-vaulta)
6. [Dobre praktyki i bezpieczeństwo](#6-dobre-praktyki-i-bezpieczeństwo)
7. [Najczęstsze problemy](#7-najczęstsze-problemy)
8. [Vault a rozwiązania produkcyjne](#8-vault-a-rozwiązania-produkcyjne)
9. [Co chroni sejf i jak wyglądają hasła w firmie](#9-co-chroni-sejf-i-jak-wyglądają-hasła-w-firmie)

---

## 1. Czym jest Ansible Vault

**Ansible Vault** to wbudowane w Ansible szyfrowanie plików (lub pojedynczych wartości)
algorytmem **AES-256**. Zaszyfrowany plik wygląda tak:

```
$ANSIBLE_VAULT;1.1;AES256
62313365396662343061393464336163383764373764613633653634306231386433626436623361
6134333665353966363534333632666535333761666131620a663537646436643839616165376333
...
```

Pierwsza linia to nagłówek – po nim Ansible poznaje, że plik trzeba odszyfrować. Reszta to
szyfrogram: bez hasła do vaulta nikt nie odczyta treści.

Najważniejsze: **Ansible odszyfrowuje plik sam, w pamięci, w chwili uruchomienia playbooka**.
Na dysku plik cały czas jest zaszyfrowany, a w playbookach używasz zmiennych z niego jak
każdych innych.

| Bez vaulta | Z vaultem |
|---|---|
| `--ask-become-pass` przy każdym uruchomieniu | hasło sudo w zaszyfrowanym pliku, uruchomienie bez pytań |
| hasło tylko w głowie administratora | hasło w pliku, który można bezpiecznie przechowywać, a w wielu firmach – trzymać w gicie |
| nie da się uruchomić z harmonogramu ani z CI | da się – wystarczy dostarczyć hasło do vaulta |

## 2. Jak to działa w tym labie

```
 ~/.ansible/vault-pass            ← hasło DO VAULTA (losowe, plik tylko dla Ciebie: 600)
        │  odszyfrowuje
        ▼
 ansible/group_vars/all/vault.yml ← zaszyfrowany plik z hasłem SUDO
        │  ansible_become_password: ...
        ▼
 ansible-playbook site.yml        ← Ansible sam podaje hasło sudo na maszynach
```

Są więc **dwa hasła** – nie myl ich:

| Hasło | Do czego | Gdzie jest |
|---|---|---|
| **hasło sudo** | uprawnienia roota na maszynach labu | zaszyfrowane w `group_vars/all/vault.yml` |
| **hasło do vaulta** | odszyfrowanie pliku `vault.yml` | w `~/.ansible/vault-pass` na `monitoring` |

Pliki:

| Plik | W gicie? | Zawartość |
|---|---|---|
| `ansible/group_vars/all/main.yml` | tak | zwykłe zmienne (strefa czasowa, kanał k3s, ...) |
| `ansible/group_vars/all/vault.yml` | **nie** (`.gitignore`) | `ansible_become_password`, zaszyfrowane |
| `~/.ansible/vault-pass` | **nie** – poza repozytorium | hasło do vaulta |

Ansible wczytuje automatycznie **wszystkie** pliki z katalogu `group_vars/all/` – dlatego
dawny `group_vars/all.yml` jest teraz `group_vars/all/main.yml`, a obok leży `vault.yml`.

`ansible_become_password` to zmienna wbudowana: gdy jest ustawiona, Ansible używa jej jako
hasła `sudo` zamiast pytać.

> **Dlaczego `vault.yml` nie trafia do gita?** W firmach zaszyfrowany plik zwykle **jest**
> w repozytorium – to jedna z głównych zalet vaulta. To repozytorium jest jednak publiczne,
> a hasło sudo labu jest proste – zaszyfrowanego pliku z prostym hasłem nie wystawia się na
> świat (można próbować łamać hasło do vaulta offline, bez limitu prób).

## 3. Konfiguracja krok po kroku

Wszystko na maszynie **monitoring** (węzeł sterujący Ansible).

### Krok 1. Aktualne repozytorium

```bash
cd ~/k3s-monitoring-lab && git pull && cd ansible
ls group_vars/all/
```

Powinieneś zobaczyć `main.yml`.

### Krok 2. Hasło do vaulta

Hasło do vaulta generujesz losowo – nie musisz go pamiętać, bo leży w pliku:

```bash
(umask 077; openssl rand -base64 32 > ~/.ansible/vault-pass)
ls -l ~/.ansible/vault-pass
```

| Część | Znaczenie |
|---|---|
| `openssl rand -base64 32` | 32 losowe bajty zapisane jako tekst (ok. 44 znaki) |
| `umask 077` | nowy plik od razu z uprawnieniami `600` – czyta go tylko właściciel |
| `( ... )` | `umask` działa tylko wewnątrz nawiasów, nie zmienia ustawień Twojej sesji |

`ls -l` ma pokazać `-rw-------`. Gdyby było inaczej: `chmod 600 ~/.ansible/vault-pass`.

### Krok 3. Powiedz Ansible, gdzie jest hasło do vaulta

```bash
echo 'export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/vault-pass' >> ~/.bashrc
echo 'export EDITOR=nano' >> ~/.bashrc
source ~/.bashrc
echo $ANSIBLE_VAULT_PASSWORD_FILE
```

- `ANSIBLE_VAULT_PASSWORD_FILE` – Ansible czyta z tego pliku hasło do vaulta, zamiast pytać.
  Zmienna środowiskowa, a nie wpis w `ansible.cfg`, bo `ansible.cfg` jest w repozytorium,
  a plik z hasłem – tylko na Twojej maszynie.
- `EDITOR=nano` – `ansible-vault` otwiera pliki w tym edytorze (domyślnie byłby `vi`).

### Krok 4. Utwórz zaszyfrowany plik

```bash
ansible-vault create group_vars/all/vault.yml
```

Otworzy się `nano` z pustym plikiem. Wpisz jedną linię (swoje hasło sudo):

```yaml
ansible_become_password: "twoje-haslo-sudo"
```

Zapisz (`Ctrl+O`, `Enter`) i wyjdź (`Ctrl+X`). Dopiero przy zapisie `ansible-vault` szyfruje
treść – niezaszyfrowana wersja istnieje tylko w pliku tymczasowym na czas edycji.

Cudzysłów jest potrzebny, jeśli hasło zawiera znaki specjalne YAML (`:`, `#`, `{`, `'` itp.).

### Krok 5. Sprawdź, co jest na dysku

```bash
cat group_vars/all/vault.yml          # szyfrogram – nagłówek $ANSIBLE_VAULT;1.1;AES256
ansible-vault view group_vars/all/vault.yml   # treść po odszyfrowaniu
git status --short                    # vault.yml nie może się tu pojawić
```

`git status` nie pokazuje `vault.yml`, bo plik jest w `.gitignore`.

### Krok 6. Test bez `-K`

```bash
ansible all -b -m command -a whoami
```

Każda z 5 maszyn powinna odpowiedzieć `root` – bez pytania o hasło. `-b` (become) przełącza
na roota, a hasło Ansible wziął z vaulta.

### Krok 7. Playbook bez `--ask-become-pass`

```bash
ansible-playbook site.yml
```

W `PLAY RECAP` powinno być `failed=0`, a przy już działającym klastrze – `changed=0`.

Od teraz wszystkie polecenia z dokumentacji uruchamiasz **bez** `--ask-become-pass` / `-K`.

## 4. Codzienna praca z vaultem

| Polecenie | Co robi |
|---|---|
| `ansible-vault create plik.yml` | nowy zaszyfrowany plik (otwiera edytor) |
| `ansible-vault edit plik.yml` | edycja – odszyfrowuje do pliku tymczasowego, po zapisie szyfruje ponownie |
| `ansible-vault view plik.yml` | podgląd treści bez edycji |
| `ansible-vault encrypt plik.yml` | szyfruje istniejący zwykły plik |
| `ansible-vault decrypt plik.yml` | odszyfrowuje plik **na dysku** – ostrożnie, potem zaszyfruj z powrotem |
| `ansible-vault rekey plik.yml` | zmiana hasła do vaulta (pyta o nowe) |
| `ansible-vault encrypt_string 'tajne' --name 'zmienna'` | szyfruje jedną wartość do wklejenia w zwykły plik YAML |

Zmiana hasła sudo na maszynach → `ansible-vault edit group_vars/all/vault.yml` i poprawiasz linię.

Szyfrowanie pojedynczej wartości (`encrypt_string`) daje blok do wklejenia w dowolny plik:

```yaml
grafana_admin_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  3862613430653435...
```

Reszta pliku zostaje czytelna, a zaszyfrowana jest tylko ta jedna wartość. Wada: nie widać
jej przez `ansible-vault view` – podgląd: `ansible localhost -m debug -a var=grafana_admin_password -e @plik.yml`.

## 5. Skąd Ansible bierze hasło do vaulta

| Sposób | Jak | Kiedy |
|---|---|---|
| pytanie przy uruchomieniu | `--ask-vault-pass` (`-J`) | ręczna praca – jedno hasło zamiast wielu sekretów |
| plik z hasłem | `--vault-password-file ~/.ansible/vault-pass` | jednorazowo, z wiersza poleceń |
| zmienna środowiskowa | `ANSIBLE_VAULT_PASSWORD_FILE=...` | **ten lab** – ustawione raz w `~/.bashrc` |
| wpis w `ansible.cfg` | `vault_password_file = ...` | gdy plik z hasłem jest wszędzie w tym samym miejscu |
| skrypt | plik wykonywalny, który *wypisuje* hasło (np. z menedżera haseł albo HashiCorp Vault) | produkcja, CI |
| vault ID | `--vault-id prod@~/.vault-prod --vault-id dev@prompt` | kilka vaultów z różnymi hasłami (np. osobno dev i prod) |

Hasło do vaulta przenosi problem w inne miejsce – **ktoś musi je dostarczyć**. Na produkcji
robi to platforma (AWX, CI z sekretami, menedżer sekretów), a nie plik w katalogu domowym.

## 6. Dobre praktyki i bezpieczeństwo

- **Nie commituj hasła do vaulta.** Plik z hasłem leży poza repozytorium (`~/.ansible/`).
- **Losowe hasło do vaulta** – długie i nie do zgadnięcia; i tak go nie wpisujesz.
- **Uprawnienia `600`** na pliku z hasłem. Kto ma dostęp do Twojego konta na `monitoring`, ma
  i plik z hasłem, i vault – dlatego węzeł sterujący trzeba chronić jak sejf.
- **Kopia zapasowa hasła do vaulta** – utracone = zaszyfrowanych plików nie da się odczytać.
  W labie to tylko hasło sudo, więc w razie czego tworzysz vault od nowa (krok 2–4).
- **Konwencja `vault_`** – w większych projektach w `vault.yml` trzyma się zmienne z prefiksem
  (`vault_become_password`), a w zwykłym `main.yml` mapuje je jawnie
  (`ansible_become_password: "{{ vault_become_password }}"`). Wtedy `grep` po repozytorium
  pokazuje, gdzie zmienna jest używana, mimo że wartość jest zaszyfrowana. Tutaj vault jest
  opcjonalny, więc `vault.yml` ustawia `ansible_become_password` wprost – bez pliku działa
  zwykłe `--ask-become-pass`.
- **`no_log: true`** przy zadaniach, które wypisują sekrety – vault chroni plik, a nie wynik
  na ekranie.
- **`decrypt` tylko na chwilę.** Lepiej używać `edit` i `view`, które nie zostawiają
  odszyfrowanego pliku na dysku.

## 7. Najczęstsze problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| *Attempting to decrypt but no vault secrets found* | Ansible nie zna hasła do vaulta | `echo $ANSIBLE_VAULT_PASSWORD_FILE`; nowa sesja → `source ~/.bashrc` |
| *Decryption failed (no vault secrets were found that could decrypt)* | złe hasło do vaulta (np. plik `vault-pass` wygenerowany ponownie) | odtwórz vault: usuń `vault.yml`, krok 4 |
| *Incorrect sudo password* / *Missing sudo password* | złe hasło sudo w vaulcie | `ansible-vault edit group_vars/all/vault.yml` |
| `-K` nie pomaga przy złym haśle | zmienna `ansible_become_password` z vaulta ma pierwszeństwo przed `-K` | popraw hasło w vaulcie albo tymczasowo przenieś `vault.yml` poza `group_vars/all/` |
| `ansible-vault create` otwiera `vi` | brak `EDITOR` | `export EDITOR=nano` (krok 3) |
| *ERROR! input is not vault encrypted data* | `view`/`edit` na zwykłym pliku | najpierw `ansible-vault encrypt plik.yml` |

## 8. Vault a rozwiązania produkcyjne

Ansible Vault to pierwszy stopień. Porównanie sposobów na hasło sudo w automatyzacji:

| Sposób | Zalety | Wady |
|---|---|---|
| `--ask-become-pass` | nic nie jest zapisane | wymaga człowieka – brak automatyzacji |
| **Ansible Vault** (ten rozdział) | wbudowany, prosty, zaszyfrowany plik w repo | hasło do vaulta trzeba gdzieś trzymać i dostarczać |
| użytkownik `ansible` z `NOPASSWD` w sudoers | brak haseł w ogóle | konto automatu = pełny root bez hasła; trzeba je mocno chronić (tylko klucz, ograniczone adresy) |
| menedżer sekretów (HashiCorp Vault, Azure Key Vault) | centralnie, z audytem, rotacją i uprawnieniami | osobna usługa do utrzymania |
| AWX / Ansible Automation Platform | poświadczenia w platformie, ludzie ich nie widzą, log każdego uruchomienia | cięższe wdrożenie |

W praktyce te sposoby się łączy – np. AWX pobiera hasło do vaulta z menedżera sekretów,
a playbooki z repozytorium odszyfrowują nim pliki vault.

## 9. Co chroni sejf i jak wyglądają hasła w firmie

### Co jest w sejfie

Po konfiguracji w `vault.yml` jest **jedno hasło sudo, które działa na wszystkich maszynach** –
wszystkie powstały z jednego szablonu z tym samym użytkownikiem i hasłem.

**Nie ma tam kluczy SSH.** Do logowania służą klucze (`ansible`, `k3s-lab`), a logowanie hasłem
przez SSH jest wyłączone – samo hasło sudo nikogo nie wpuści na maszynę. Żeby go użyć, trzeba
najpierw być zalogowanym ([klucze SSH](teoria-ssh-klucze.md)).

### Klucz do sejfu leży obok sejfu

Na `monitoring` jest i `vault.yml`, i `~/.ansible/vault-pass`.

| Sejf chroni przed | Sejf nie chroni przed |
|---|---|
| `vault.yml` przypadkiem w gicie, w kopii zapasowej, na pendrivie | przejęciem Twojego konta na `monitoring` – jest tam i sejf, i klucz |
| podejrzeniem pliku w repozytorium lub edytorze | kimś z dostępem roota na `monitoring` |
| hasłem zapisanym jawnym tekstem w jakimkolwiek pliku | |

Kto przejmie węzeł sterujący, ma klucz SSH `ansible` i hasło sudo – czyli roota na wszystkich
maszynach. To nie wada Vaulta, tylko natura automatyzacji: narzędzie, które zarządza
wszystkim, ma dostęp do wszystkiego. Dlatego **węzeł sterujący chroni się jak sejf**, a na
produkcji klucz do sejfu dostarcza osobna platforma (AWX, menedżer sekretów), a nie plik
w katalogu domowym.

### Jedno hasło na wszystkich maszynach – nie

| Poziom | Jak | Ocena |
|---|---|---|
| ❌ jedno hasło na wszystkich maszynach | tak jest w labie (z szablonu) | jeden wyciek otwiera wszystko |
| ✅ inne hasło na każdej maszynie | losowe hasła, każde zapisane w sejfie | wyciek dotyczy jednej maszyny |
| ✅✅ brak lokalnych haseł do codziennej pracy | konta z centralnego katalogu, logowanie kluczem lub certyfikatem | standard w firmach |

### Jak to wygląda w firmie

- **Każdy administrator ma własne konto** – nie wspólne `admin`. Konta pochodzą z centralnego
  katalogu (Active Directory, FreeIPA, LDAP), a serwery pobierają je przez SSSD. Ktoś odchodzi –
  blokujesz jedno konto i traci dostęp do wszystkich serwerów naraz.
- **Logowanie kluczem lub certyfikatem SSH**, hasło przez SSH wyłączone.
- **Uprawnienia `sudo` nadaje się grupom** w katalogu, np. „grupa linux-admins może `sudo`
  na serwerach produkcyjnych”.
- **Lokalne konto awaryjne** (root lub admin) ma losowe hasło, **inne na każdej maszynie**,
  przechowywane w sejfie i używane tylko w awarii (katalog nie działa, logowanie z konsoli).
  Narzędzia zmieniają je regularnie – w świecie Windows **LAPS**, w Linuxie np. HashiCorp Vault.
- **Automat (Ansible, CI) ma osobne konto** – bez wspólnego hasła, z wąskimi uprawnieniami.
- **Każde użycie uprawnień zostawia ślad** – logi `sudo` i SSH trafiają do centralnego systemu.

### Wspólne hasło w labie – świadome uproszczenie

Wspólne hasło jest tu akceptowalne: maszyny są z jednego szablonu, a lab stoi w zamkniętej
sieci NAT. Ćwiczenie według sztuki na później:

1. playbook ustawia na każdej maszynie **losowe, inne** hasło sudo
   (`ansible.builtin.user` z `password: "{{ ... | password_hash('sha512') }}"`),
2. hasła zapisane są w osobnych plikach `host_vars/<maszyna>/vault.yml`,
3. Ansible sam bierze z nich hasło właściwe dla danej maszyny (`ansible_become_password`
   zdefiniowane per host ma pierwszeństwo przed `group_vars`).

Alternatywa bez haseł: osobny użytkownik automatu z `sudo` bez hasła (`NOPASSWD` w
`/etc/sudoers.d/`), logujący się wyłącznie kluczem i tylko z adresu `monitoring`.

## Co powiedzieć na rozmowie

> „Hasło sudo dla Ansible trzymam w pliku zaszyfrowanym Ansible Vault (AES-256), a hasło do
> vaulta – losowe – w pliku z uprawnieniami 600 poza repozytorium, wskazanym zmienną
> ANSIBLE_VAULT_PASSWORD_FILE. Dzięki temu playbooki działają bez wpisywania haseł. Wiem, że to
> przenosi problem na ochronę hasła do vaulta – na produkcji dostarczałaby je platforma, np. AWX
> albo menedżer sekretów.”
