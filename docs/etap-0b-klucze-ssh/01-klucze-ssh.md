# Klucze SSH – jak to działa

W tym laboratorium występują **dwa rodzaje kluczy SSH**, które łatwo pomylić: klucze
**użytkownika** i klucze **hosta**. Ten plik tłumaczy oba od zera, na przykładach z labu.

Instrukcje krok po kroku są w [przewodniku](../00-przewodnik.md) (kroki 4–8 i 16–17).

## Spis treści

1. [Porównanie: wizyta w banku](#1-porównanie-wizyta-w-banku)
2. [Para kluczy: prywatny i publiczny](#2-para-kluczy-prywatny-i-publiczny)
3. [Klucz użytkownika – „to ja, wpuść mnie”](#3-klucz-użytkownika--to-ja-wpuść-mnie)
4. [Klucz hosta – „to naprawdę ta maszyna”](#4-klucz-hosta--to-naprawdę-ta-maszyna)
5. [Co się dzieje przy połączeniu](#5-co-się-dzieje-przy-połączeniu)
6. [Klucze w tym laboratorium](#6-klucze-w-tym-laboratorium)
7. [Klony i wspólny klucz hosta](#7-klony-i-wspólny-klucz-hosta)
8. [Dobre praktyki](#8-dobre-praktyki)
9. [Komunikaty i co znaczą](#9-komunikaty-i-co-znaczą)
10. [Ściągawka poleceń](#10-ściągawka-poleceń)

---

## 1. Porównanie: wizyta w banku

Idziesz do banku. Sprawdzenie działa **w dwie strony**:

1. **Ty sprawdzasz bank** – czy to prawdziwy oddział, a nie podróbka postawiona przez oszusta?
   Patrzysz na szyld i porównujesz z tym, co pamiętasz z poprzedniej wizyty.
2. **Bank sprawdza Ciebie** – pokazujesz dowód osobisty, kasjer sprawdza, czy jesteś na liście klientów.

SSH robi dokładnie to samo:

| W banku | W SSH | Nazwa |
|---|---|---|
| szyld banku, który pamiętasz | serwer pokazuje swój klucz, Ty porównujesz z zapamiętanym | **klucz hosta** |
| Twój dowód osobisty | Ty pokazujesz swój klucz, serwer sprawdza go z listą | **klucz użytkownika** |

> **Klucz użytkownika to Twój dowód osobisty, klucz hosta to szyld maszyny.**

## 2. Para kluczy: prywatny i publiczny

Każdy klucz SSH to **para plików** (kryptografia asymetryczna):

| Połówka | Przykład | Zasada |
|---|---|---|
| **prywatna** | `~/.ssh/k3s-lab` | **tajna** – nigdy nie opuszcza komputera, na którym powstała |
| **publiczna** | `~/.ssh/k3s-lab.pub` | jawna – rozdajesz ją tam, gdzie chcesz być rozpoznawany |

Porównanie: **publiczna to kłódka**, którą rozdajesz, **prywatna to kluczyk**, który zostaje
w kieszeni. Serwer daje Ci zagadkę zamkniętą Twoją kłódką – rozwiązać ją może tylko ktoś
z kluczyka. Sam kluczyk nigdy nie jest przesyłany przez sieć.

Klucz publiczny to jedna linia tekstu: typ, treść i komentarz (np. do kogo należy):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... k3s-lab
```

**Odcisk (fingerprint)** to krótka „suma kontrolna” klucza – łatwiej porównać ją wzrokiem niż
całą treść:

```
SHA256:F6hUDxpWf2ah5ZH/dMJPeagx2DgGDhcjHdesjzhvSqY
```

Typ klucza: w labie wszędzie **ed25519** – nowoczesny, krótki i szybki. Starszy RSA też działa,
ale wymaga długich kluczy (min. 3072 bity).

## 3. Klucz użytkownika – „to ja, wpuść mnie”

Tworzysz go sam (`ssh-keygen`). Część publiczną dopisujesz na serwerze do
**`~/.ssh/authorized_keys`** – to **lista gości**: „wpuszczam tego, kto ma kluczyk do którejś
z tych kłódek”. Dzięki temu logujesz się bez hasła.

Plik `authorized_keys` jest osobny dla każdego użytkownika na każdej maszynie
(`/home/<użytkownik>/.ssh/authorized_keys`). Wymagane uprawnienia: katalog `~/.ssh` – `700`,
plik – `600`; przy zbyt szerokich SSH odmówi użycia klucza.

## 4. Klucz hosta – „to naprawdę ta maszyna”

Każda **maszyna** ma własne klucze, generowane automatycznie przy instalacji systemu:

```
/etc/ssh/ssh_host_ed25519_key        ← prywatny, tylko root
/etc/ssh/ssh_host_ed25519_key.pub    ← publiczny
(oraz wersje _rsa_ i _ecdsa_)
```

Po Twojej stronie jest **`~/.ssh/known_hosts`** – **notes z zapamiętanymi szyldami**:
„pod tym adresem była maszyna z takim kluczem”.

- **Pierwsze połączenie:** SSH pyta *Are you sure you want to continue connecting?* – czyli
  „nie znam tego szyldu, zapamiętać?”. Po `yes` klucz trafia do `known_hosts`.
- **Kolejne połączenia:** SSH porównuje klucz z notesem. Gdy się różni:
  **`REMOTE HOST IDENTIFICATION HAS CHANGED!`** – ktoś mógł podstawić inną maszynę
  (atak *man-in-the-middle*) albo klucz został legalnie wymieniony.

Pierwsze `yes` to zaufanie „na słowo” (*TOFU – trust on first use*). Według sztuki porównujesz
odcisk z pytania z odciskiem odczytanym niezależnym kanałem – np. w konsoli VMware:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

## 5. Co się dzieje przy połączeniu

```
 Ty                                                  serwer
  │  1. „cześć”                                         │
  │ ──────────────────────────────────────────────────▶ │
  │  2. mój klucz HOSTA (+ dowód, że mam prywatny)      │
  │ ◀────────────────────────────────────────────────── │
  │  3. porównanie z known_hosts                        │
  │     zgadza się → dalej / nowy → pytanie / inny → STOP
  │  4. szyfrowany kanał                                │
  │ ◀═════════════════════════════════════════════════▶ │
  │  5. mój klucz UŻYTKOWNIKA (+ podpis prywatnym)      │
  │ ──────────────────────────────────────────────────▶ │
  │                       6. czy jest w authorized_keys? │
  │  7. wpuszczony / Permission denied (publickey)      │
  │ ◀────────────────────────────────────────────────── │
```

Najpierw **Ty** sprawdzasz **maszynę** (klucz hosta), dopiero potem **maszyna** sprawdza **Ciebie**
(klucz użytkownika). Podgląd tego procesu: `ssh -v k3s-master`.

## 6. Klucze w tym laboratorium

### Klucze użytkownika – dwa, bo łączysz się z dwóch miejsc

```
 Windows (Ty)                         każda maszyna labu
 ┌─────────────────────┐              ┌──────────────────────────────┐
 │ ~/.ssh/k3s-lab      │ ──────────▶  │ ~/.ssh/authorized_keys       │
 │   (prywatny)        │              │   ... k3s-lab                │
 └─────────────────────┘              │   ... ansible@monitoring     │
                                      └──────────────────────────────┘
 monitoring (Ansible)                        ▲
 ┌─────────────────────┐                     │
 │ ~/.ssh/ansible      │ ────────────────────┘
 │   (prywatny)        │
 └─────────────────────┘
```

| Klucz | Prywatny leży | Kto go używa | Skąd SSH wie, którego użyć | Krok przewodnika |
|---|---|---|---|---|
| `k3s-lab` | Windows `C:\Users\<Ty>\.ssh\k3s-lab` | Ty, z PowerShella | `IdentityFile` w `~/.ssh/config` na Windowsie | 5–8 |
| `ansible` | monitoring `~/.ssh/ansible` | Ansible (i Ty na monitoring) | `ansible_ssh_private_key_file` w `inventory.ini`; `IdentityFile` w `~/.ssh/config` na monitoring | 16–17 |
| (Packer) | ten sam `k3s-lab.pub` | autoinstall wpisuje go do nowej maszyny | `locals` w `packer/k3s-node.pkr.hcl` | Packer |

Klucze mają niestandardowe nazwy, więc SSH sam ich nie znajdzie (szuka tylko `id_ed25519`,
`id_rsa`...). Stąd `IdentityFile` w `~/.ssh/config` albo `ssh -i <klucz>`. `IdentitiesOnly yes`
sprawia, że SSH próbuje wyłącznie wskazanego klucza.

### Klucze hosta – pięć, po jednym na maszynę

| Maszyna | Klucz hosta |
|---|---|
| k3s-master, k3s-worker-1, k3s-worker-2, monitoring | wygenerowane na nowo na klonach (`ssh-keygen -A`) |
| k3s-worker-3 | wygenerowany przy instalacji z Packera |

Zapisane są w `known_hosts` **na Windowsie** i **na monitoring** – każdy komputer, z którego się
łączysz, ma własny notes. Ansible sprawdza je przy każdym połączeniu
(`host_key_checking = True` w `ansible/ansible.cfg`).

### Wszystko razem

| | Klucz użytkownika | Klucz hosta |
|---|---|---|
| Odpowiada na pytanie | „czy wpuścić tę **osobę**?” | „czy to na pewno ta **maszyna**?” |
| Ile w labie | **2** (`k3s-lab`, `ansible`) | **5** (po jednym na maszynę) |
| Kto tworzy | Ty (`ssh-keygen -t ed25519 -f ...`) | system przy instalacji (`ssh-keygen -A`) |
| Prywatny leży | Windows / monitoring | na samej maszynie, `/etc/ssh/` |
| Publiczny trafia do | `~/.ssh/authorized_keys` na maszynach | `~/.ssh/known_hosts` u Ciebie |
| Gdy się nie zgadza | `Permission denied (publickey)` | `REMOTE HOST IDENTIFICATION HAS CHANGED` |

## 7. Klony i wspólny klucz hosta

Klonowanie maszyny kopiuje cały dysk – razem z `/etc/ssh/ssh_host_*`. Wszystkie klony mają wtedy
**ten sam szyld**:

```
PRZED:  k3s-master   → F6hU...  ┐
        k3s-worker-1 → F6hU...  ├─ cztery różne maszyny z identycznym kluczem hosta
        k3s-worker-2 → F6hU...  │
        monitoring   → F6hU...  ┘

PO:     k3s-master   → F6hU...
        k3s-worker-1 → Ecl5...
        k3s-worker-2 → qSIx...
        monitoring   → JZoF...     każda maszyna ma własny
```

Skutki: SSH nie odróżnia maszyn od siebie, a kto zdobędzie klucz z jednej, może podszyć się pod
wszystkie. Objaw: *This host key is known by the following other names/addresses*.

Wykrycie – porównanie odcisków z jednego miejsca:

```bash
for ip in 51 52 53 54 55; do ssh-keyscan -t ed25519 192.168.180.$ip 2>/dev/null | ssh-keygen -lf -; done
```

Naprawa:

1. nowe klucze na klonach: `sudo rm -f /etc/ssh/ssh_host_* && sudo ssh-keygen -A && sudo systemctl restart ssh`
   (wszystkie naraz: `ansible <maszyny> -b -K -m shell -a "..."`),
2. stare wpisy z `known_hosts` na każdym komputerze, z którego się łączysz: `ssh-keygen -R <nazwa lub adres>`,
3. połączenie i porównanie nowego odcisku z odczytanym na maszynie, dopiero potem `yes`.

Zapobieganie: generowanie kluczy w procedurze klonowania (przewodnik, krok 4) albo rola
`bootstrap` w Ansible, która wykrywa powtórzenia. Pełny opis przypadku:
[problemy](../etap-0-maszyny-wirtualne/problemy.md#wspólny-klucz-hosta-wykryty-dopiero-po-zbudowaniu-klastra).

## 8. Dobre praktyki

- **Jeden klucz użytkownika na jedno miejsce, z którego się łączysz.** Klucza prywatnego nie
  kopiuje się między komputerami. Przejęty komputer = usuwasz z `authorized_keys` jedną linię,
  reszta dostępu działa.
- **Osobne klucze dla ludzi i dla automatów** (Ansible, CI) – wiadomo, kto się łączył, i można
  odebrać dostęp osobno.
- **Komentarz w kluczu** (`-C "ansible@monitoring"`) – po nim rozpoznasz linię w `authorized_keys`.
- **Logowanie hasłem wyłączone**, gdy klucze działają (`PasswordAuthentication no`) – brak
  zgadywania haseł przez sieć.
- **Hasło do klucza (passphrase)** chroni klucz prywatny, gdyby plik wyciekł. W labie klucze są
  bez hasła dla wygody; w pracy – z hasłem i `ssh-agent`, a dla automatów – klucze o wąskich
  uprawnieniach.
- **Unikalne klucze hosta** na każdej maszynie; szablony „uogólnia się” przed klonowaniem.
- **Nie wyłączaj sprawdzania kluczy hosta** (`StrictHostKeyChecking no`, `host_key_checking = False`).
  Rozsądny kompromis: `accept-new` – nowe maszyny dopisywane, zmienione klucze odrzucane.
- **Czytaj ostrzeżenia**, zamiast odruchowo wpisywać `yes`.

## 9. Komunikaty i co znaczą

| Komunikat | Co znaczy | Co zrobić |
|---|---|---|
| *The authenticity of host ... can't be established* | pierwsze połączenie, klucza hosta nie ma w `known_hosts` | porównaj odcisk, potem `yes` |
| *This host key is known by the following other names/addresses* | ten sam klucz hosta jest już zapisany pod innym adresem | często nieszkodliwe (nazwa i IP tej samej maszyny); przy różnych maszynach – wspólny klucz z klonowania (rozdz. 7) |
| *WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!* | klucz hosta inny niż zapamiętany | ustal, czy klucz zmieniono celowo; jeśli tak – `ssh-keygen -R <adres>` i połącz ponownie |
| *Host key verification failed* | to samo, w trybie bez pytań (Ansible, `BatchMode`) | jak wyżej |
| *Permission denied (publickey)* | serwer nie przyjął żadnego klucza użytkownika | zły klucz (`-i`), brak w `authorized_keys`, złe uprawnienia `~/.ssh` |
| *Connection closed by ... port 22* | serwer rozłączył przed zalogowaniem | najczęściej brak pasującego klucza – sprawdź `ssh -v` |
| *Permission denied (publickey,password)* | serwer przyjmuje też hasło | logowanie hasłem nadal włączone (`sudo sshd -T \| grep passwordauthentication`) |

## 10. Ściągawka poleceń

```bash
# Klucze użytkownika
ssh-keygen -t ed25519 -f ~/.ssh/k3s-lab -C "k3s-lab"      # nowa para kluczy
ssh-copy-id -i ~/.ssh/k3s-lab.pub user@host               # wgranie publicznego (Linux)
ssh-keygen -lf ~/.ssh/k3s-lab.pub                          # odcisk klucza
cat ~/.ssh/authorized_keys                                 # kto może się zalogować (na serwerze)
ssh -i ~/.ssh/ansible user@host                            # połączenie wskazanym kluczem

# Klucze hosta
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub           # odcisk klucza tej maszyny (na serwerze)
ssh-keyscan -t ed25519 192.168.180.51 | ssh-keygen -lf -   # odcisk klucza zdalnej maszyny
ssh-keygen -F 192.168.180.51                               # czy maszyna jest w known_hosts
ssh-keygen -R 192.168.180.51                               # usunięcie z known_hosts
sudo rm -f /etc/ssh/ssh_host_* && sudo ssh-keygen -A       # nowe klucze hosta (na serwerze)

# Diagnostyka
ssh -v k3s-master                                          # przebieg połączenia krok po kroku
sudo sshd -T | grep -i -E 'passwordauth|pubkeyauth'        # efektywna konfiguracja serwera
```

Windows (PowerShell) nie ma `ssh-copy-id` – zamiast niego:

```powershell
type $env:USERPROFILE\.ssh\k3s-lab.pub | ssh user@host "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Dalej

- Teoria Ansible (jak Ansible korzysta z SSH): [docs/etap-2-k3s-ansible/01-teoria-ansible.md](../etap-2-k3s-ansible/01-teoria-ansible.md)
- Problemy z kluczami, które wystąpiły w labie: [docs/problemy-ogolne.md](../etap-1-przygotowanie-systemu/problemy.md)
