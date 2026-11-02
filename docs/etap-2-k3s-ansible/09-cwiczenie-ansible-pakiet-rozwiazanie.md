# Etap 2 – ćwiczenie z Ansible: pakiet na wszystkich maszynach – rozwiązanie

Rozwiązanie [ćwiczenia z pakietem](08-cwiczenie-ansible-pakiet.md). Najpierw zrób je sam – tu
porównujesz wynik. Wszystkie wyniki to **prawdziwe wyniki z labu** (2.11.2026, ansible-core 2.21.5). Liczby `ok=…` mogą się u Ciebie różnić, ważne są `changed`, `failed` i `rc`.

## Część A – stan przed zmianą

🐧 `monitoring`:

```bash
cd ~/k3s-monitoring-lab && git pull
cd ansible
ansible all -m ping
```

```
monitoring | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.14"
    },
    "changed": false,
    "ping": "pong"
}
k3s-master | SUCCESS => {
...
(tak samo dla k3s-worker-1, -2, -3)
```

`ping` w Ansible to nie ping sieciowy – sprawdza, czy Ansible zaloguje się po SSH i uruchomi Pythona.
`discovered_interpreter_python` – Ansible sam znalazł Pythona 3.14 na maszynie. Kolejność maszyn
w wyniku jest za każdym razem inna – Ansible łączy się z nimi równolegle.

```bash
ansible all -m command -a "which tree"
```

```
[ERROR]: Task failed: Module failed: The command exited with a non-zero return code.
Origin: <adhoc 'command' task>

k3s-worker-3 | FAILED | rc=1 >>
The command exited with a non-zero return code.
k3s-worker-2 | FAILED | rc=1 >>
The command exited with a non-zero return code.
k3s-worker-1 | FAILED | rc=1 >>
The command exited with a non-zero return code.
k3s-master | FAILED | rc=1 >>
The command exited with a non-zero return code.
monitoring | FAILED | rc=1 >>
The command exited with a non-zero return code.
```

| Część polecenia | Znaczenie |
|---|---|
| `all` | wszystkie maszyny z inventory |
| `-m command` | moduł: uruchom program |
| `-a "which tree"` | jaki program: `which` szuka go w `PATH` |

**Odpowiedzi:**
- `FAILED` nie znaczy, że coś jest zepsute. `which` kończy się kodem 1, gdy programu nie znajdzie,
  a Ansible każdy kod różny od 0 pokazuje jako `FAILED`. Tu to po prostu odpowiedź „nie ma”.
- `rc` (return code) to kod wyjścia programu: `0` – sukces, inny – błąd albo „nie znaleziono”.

## Część B – instalacja przez rolę `common`

### Krok 1 – zmiana w roli

🪟 `ansible/roles/common/tasks/main.yml`:

```yaml
- name: Zainstaluj potrzebne pakiety
  ansible.builtin.apt:
    name:
      - curl
      - ca-certificates
      - gettext-base
      - jq
      - ufw
      - tree
    state: present
```

Wcięcie musi być takie samo jak przy `- ufw` – YAML rozpoznaje strukturę po spacjach.

### Krok 2 i 3 – git

🪟 Git Bash w `C:\Projekty\k3s-monitoring-lab`:

```bash
git add ansible/roles/common/tasks/main.yml
git commit -m "Ansible: pakiet tree na wszystkich maszynach (ćwiczenie)"
git push
```

🐧 `monitoring`:

```bash
cd ~/k3s-monitoring-lab && git pull && cd ansible
```

```
From https://github.com/programmingbygrzegorz/k3s-monitoring-lab
   ef30105..38050a1  main       -> origin/main
Updating ef30105..38050a1
Fast-forward
 ansible/roles/common/tasks/main.yml | 1 +
 1 file changed, 1 insertion(+)
```

### Krok 4 – próba na sucho

W labie próba na sucho objęła cały `site.yml` (przygotowanie systemu i k3s) – tak też można:

```bash
ansible-playbook site.yml --check --diff
```

```
TASK [common : Zaktualizuj system] *********************************************
ok: [k3s-worker-3]
ok: [k3s-worker-1]
...

TASK [common : Zainstaluj potrzebne pakiety] ***********************************
Solving dependencies...
The following NEW packages will be installed:
  tree
0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.
changed: [k3s-worker-2]
...  (tak samo dla k3s-worker-1, -3, k3s-master, monitoring)

TASK [k3s_server : Pobierz instalator k3s] *************************************
changed: [k3s-master]
...
PLAY RECAP *********************************************************************
k3s-master                 : ok=27   changed=2    unreachable=0    failed=0    skipped=4    rescued=0    ignored=0
k3s-worker-1               : ok=20   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-2               : ok=20   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-3               : ok=20   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
monitoring                 : ok=13   changed=1    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

`--check` niczego nie instaluje – moduł `apt` pyta tylko, co by zrobił. `--diff` dokłada opis
zmiany: lista nowych pakietów, tak jak przy `apt install`.

Skąd `changed=2` na węzłach k3s? Drugie `changed` to „Pobierz instalator k3s”: plik
`/tmp/k3s-install.sh` znika przy restarcie maszyny (`/tmp` jest czyszczony), więc Ansible pobrałby
go ponownie. Nieszkodliwe – sama instalacja k3s ma `creates:` i jest pomijana (`ok`).

> **Prawdziwy problem znaleziony w tym kroku:** pierwsza próba `site.yml --check` skończyła się
> `failed=1` na masterze – zadanie „Poczekaj, aż węzeł sterujący będzie Ready” 30 razy
> dostało pusty wynik. W trybie `--check` moduł `command` **nie jest uruchamiany**, a pętla `until`
> czekała na wynik `kubectl`. Naprawa: `check_mode: false` przy zadaniach, które tylko czytają.
> Opis: [problemy Etapu 2](problemy.md#siteyml---check-kończy-się-failed-na-masterze).

### Krok 5 – jedna maszyna

```bash
ansible-playbook playbooks/prepare.yml --limit k3s-worker-1
```

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
changed: [k3s-worker-1]
...
PLAY RECAP *********************************************************************
k3s-worker-1               : ok=17   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
```

W wyniku jest tylko `k3s-worker-1`.

Dlaczego tu `prepare.yml`, a nie `site.yml`? Rola `k3s_agent` bierze token z mastera
(`hostvars['k3s-master'].k3s_server_token`), a ten powstaje w play mastera. Z `--limit k3s-worker-1`
play mastera się nie wykona, więc tokenu nie będzie i worker zgłosi błąd niezdefiniowanej
zmiennej. Pakiet jest w roli `common`, więc do próby na jednej maszynie wystarcza `prepare.yml`.

### Krok 6 – sprawdzenie

```bash
ansible all -m command -a "which tree"
```

```
k3s-worker-3 | FAILED | rc=1 >>
k3s-worker-1 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-master | FAILED | rc=1 >>
monitoring | FAILED | rc=1 >>
k3s-worker-2 | FAILED | rc=1 >>
```

`CHANGED` przy module `command` nic nie zmieniło – Ansible nie wie, co robi dowolny program,
więc ostrożnie zakłada zmianę. W playbookach dlatego dopisujemy `changed_when: false` przy
poleceniach, które tylko czytają (np. w `playbooks/k3s.yml`).

### Krok 7 i 8 – wszystkie maszyny, dwa razy

W labie – cały `site.yml` (wystarczy też `playbooks/prepare.yml`):

```bash
ansible-playbook site.yml
```

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
ok: [k3s-worker-1]
changed: [monitoring]
changed: [k3s-master]
changed: [k3s-worker-2]
changed: [k3s-worker-3]
...
TASK [Wynik] *******************************************************************
ok: [k3s-master] => {
    "cluster.stdout_lines": [
        "NAME           STATUS   ROLES           AGE     VERSION        INTERNAL-IP      ...",
        "k3s-master     Ready    control-plane   3d19h   v1.36.5+k3s1   192.168.180.51   ...",
        "k3s-worker-1   Ready    worker          3d19h   v1.36.5+k3s1   192.168.180.52   ...",
        "k3s-worker-2   Ready    worker          3d19h   v1.36.5+k3s1   192.168.180.53   ...",
        "k3s-worker-3   Ready    worker          3d19h   v1.36.5+k3s1   192.168.180.55   ..."
    ]
}

PLAY RECAP *********************************************************************
k3s-master                 : ok=29   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-1               : ok=20   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-2               : ok=20   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-3               : ok=20   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
monitoring                 : ok=13   changed=1    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

`changed` = `tree` (oprócz `k3s-worker-1`) + ponowne pobranie instalatora k3s do `/tmp`.
Na końcu playbook wypisuje stan klastra – 4 węzły `Ready`, k3s nietknięty.

Drugi raz:

```
PLAY RECAP *********************************************************************
k3s-master                 : ok=29   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-1               : ok=20   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-2               : ok=20   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-3               : ok=20   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
monitoring                 : ok=13   changed=0    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

**`changed=0` na wszystkich 5 maszynach** – instalator już jest w `/tmp`, `tree` jest wszędzie.

```bash
ansible all -m command -a "which tree"
```

```
k3s-worker-3 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-master | CHANGED | rc=0 >>
/usr/bin/tree
k3s-worker-1 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-worker-2 | CHANGED | rc=0 >>
/usr/bin/tree
monitoring | CHANGED | rc=0 >>
/usr/bin/tree
```

### Krok 9 – pakiet działa

```bash
ssh k3s-master "tree -L 1 /etc/rancher"
```

```
/etc/rancher
├── k3s
└── node

3 directories, 0 files
```

**Odpowiedzi:**
- **`--limit` najpierw:** jeśli zmiana coś psuje (literówka w nazwie pakietu, konflikt), psuje
  jedną maszynę, a nie cały klaster. W firmie to „canary” – najpierw mała próbka.
- **`ok` na `k3s-worker-1` w kroku 7:** `tree` już tam był po kroku 5. `state: present` znaczy
  „ma być”, a nie „zainstaluj” – Ansible sprawdza stan i nic nie robi.
- **Krok 8 udowadnia idempotentność:** ten sam playbook na gotowych maszynach nic nie zmienia.
  Można go bezpiecznie uruchamiać w każdej chwili, np. z harmonogramu.
- **Windows + `git pull` zamiast edycji na `monitoring`:** jedno źródło prawdy – repozytorium.
  Zmiana ma historię (kto, kiedy, po co), da się ją cofnąć i przejrzeć. Edycja wprost na
  `monitoring` zostałaby tylko tam i przy następnym `git pull` doszłoby do konfliktu.

## Część C – usunięcie pakietu

### Krok 1 i 2 – samo usunięcie linii nie wystarcza

Po usunięciu `- tree` z listy, wysłaniu (commit `0398a02`) i uruchomieniu
`ansible-playbook playbooks/prepare.yml`:

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
ok: [monitoring]
ok: [k3s-worker-1]
ok: [k3s-worker-3]
ok: [k3s-master]
ok: [k3s-worker-2]

PLAY RECAP *********************************************************************
k3s-master                 : ok=17   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
...
monitoring                 : ok=13   changed=0    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

```bash
ansible all -m command -a "which tree"
```

```
monitoring | CHANGED | rc=0 >>
/usr/bin/tree
k3s-worker-1 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-worker-3 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-worker-2 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-master | CHANGED | rc=0 >>
/usr/bin/tree
```

Pakiet **nadal jest** na wszystkich 5 maszynach, a playbook mówi `changed=0` – „wszystko w porządku”.
Zadanie mówi teraz: „curl, ca-certificates, gettext-base, jq i ufw mają być”. O `tree` nic nie
mówi, więc Ansible go nie dotyka.

### Krok 3 – jawne `state: absent`

🪟 `ansible/roles/common/tasks/main.yml`, zaraz pod zadaniem instalacji (commit `d0b21fb`):

```yaml
- name: Usuń niepotrzebne pakiety
  ansible.builtin.apt:
    name:
      - tree
    state: absent
```

### Krok 4 – na sucho i naprawdę

```bash
ansible-playbook playbooks/prepare.yml --check --diff
```

```
TASK [common : Usuń niepotrzebne pakiety] **************************************
Solving dependencies...
The following packages will be REMOVED:
  tree
0 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.
changed: [monitoring]
...  (tak samo dla 4 pozostałych)

PLAY RECAP *********************************************************************
k3s-master                 : ok=18   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
...
```

`ok=18` zamiast 17 – w roli przybyło jedno zadanie.

```bash
ansible-playbook playbooks/prepare.yml
```

```
TASK [common : Usuń niepotrzebne pakiety] **************************************
changed: [k3s-worker-1]
changed: [monitoring]
changed: [k3s-master]
changed: [k3s-worker-2]
changed: [k3s-worker-3]

PLAY RECAP *********************************************************************
k3s-master                 : ok=18   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-1               : ok=18   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-2               : ok=18   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
k3s-worker-3               : ok=18   changed=1    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
monitoring                 : ok=14   changed=1    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

### Krok 5 i 6 – sprawdzenie i idempotentność

```bash
ansible all -m command -a "which tree"
```

```
k3s-worker-1 | FAILED | rc=1 >>
monitoring | FAILED | rc=1 >>
k3s-master | FAILED | rc=1 >>
k3s-worker-2 | FAILED | rc=1 >>
k3s-worker-3 | FAILED | rc=1 >>
```

Drugie uruchomienie playbooka:

```
TASK [common : Usuń niepotrzebne pakiety] **************************************
ok: [k3s-worker-1]
ok: [k3s-master]
ok: [k3s-worker-3]
ok: [monitoring]
ok: [k3s-worker-2]

PLAY RECAP *********************************************************************
k3s-master                 : ok=18   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
...
```

**Odpowiedzi:**
- **Dlaczego usunięcie linii nie wystarczyło:** Ansible jest deklaratywny, ale tylko w zakresie
  tego, co opisujesz. Nie porównuje maszyny z „pełną listą tego, co powinno być” – pilnuje
  wyłącznie stanu zapisanego w zadaniach. Czego nie ma w kodzie, tego nie zmienia. Najgorsze, że
  playbook mówi wtedy `changed=0` – wygląda, jakby wszystko było zgodne z kodem.
- **`present` a `absent`:** `present` – pakiet ma być (zainstaluj, jeśli go nie ma); `absent` –
  pakietu ma nie być (usuń, jeśli jest). W obu przypadkach, gdy stan się zgadza – `ok`.
  Jest też `latest` – zawsze najnowsza wersja, ale wtedy każde uruchomienie może coś aktualizować.

## Część D – sprzątanie w kodzie

Po usunięciu zadania „Usuń niepotrzebne pakiety” (commit `9729d9c`) i uruchomieniu playbooka:

```
PLAY RECAP *********************************************************************
k3s-master                 : ok=17   changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
...
monitoring                 : ok=13   changed=0    unreachable=0    failed=0    skipped=6    rescued=0    ignored=0
```

`ok=17` – znowu tyle zadań co przed ćwiczeniem. `which tree` – 5 × `FAILED rc=1`: nikt go nie
instaluje, więc nie wraca.

🪟 Historia:

```bash
git log --oneline -5 -- ansible/roles/common/tasks/main.yml
```

```
9729d9c Ansible: koniec ćwiczenia z tree – usunięte zadanie absent, rola jak przed ćwiczeniem
d0b21fb Ansible: usuń tree ze wszystkich maszyn (state: absent, ćwiczenie)
0398a02 Ansible: tree poza listą pakietów (ćwiczenie, część C)
38050a1 Ansible: pakiet tree na wszystkich maszynach (ćwiczenie)
efb5951 common: usuń wpisy /etc/hosts ze skryptu przed blokiem Ansible (bez duplikatów)
```

Że plik jest identyczny jak przed ćwiczeniem, potwierdza git – brak różnic z commitem sprzed
ćwiczenia:

```bash
git diff ef30105 HEAD -- ansible/roles/common/tasks/main.yml
```

Wynik pusty. Cztery commity ćwiczenia zostają w historii – widać, kto, kiedy i po co instalował
i usuwał pakiet.

**Odpowiedzi:**
- **Kiedy zostawić `state: absent`:** gdy są maszyny, których jeszcze nie przeszedł playbook
  (wyłączona, odtworzona ze starego snapshotu), albo pakiet jest niebezpieczny i ma nigdy nie wrócić
  (np. `telnetd`). Wtedy zadanie pilnuje go stale. Usunąć – gdy wszystkie maszyny są już czyste
  i pakiet nie ma szans wrócić; inaczej kod puchnie od historycznych zadań.
- **Cofnięcie roli do stanu sprzed ćwiczenia:**
  `git checkout <hash> -- ansible/roles/common/tasks/main.yml` (`<hash>` – commit sprzed ćwiczenia,
  z `git log`, w labie `ef30105`), potem commit. Plik wraca do dawnej wersji, a historia zostaje.

## Droga na skróty – polecenia ad-hoc

To samo bez zmian w kodzie:

```bash
ansible all -m apt -a "name=tree state=present update_cache=true" --become
ansible all -m apt -a "name=tree state=absent" --become
```

Dobre do szybkiej próby, ale **nic nie zostaje zapisane**: nowa maszyna dodana za miesiąc tego
pakietu nie dostanie, a nikt nie będzie wiedział, kto i po co go instalował. Trwałe zmiany –
tylko przez rolę i gita.

## Co powiedzieć na rozmowie

> „Dodanie pakietu na wszystkich serwerach to u mnie zmiana w roli, a nie ręczna instalacja:
> commit, `git pull` na węźle sterującym, `--check --diff`, wdrożenie przez `--limit` na jednej
> maszynie, potem na wszystkich i drugie uruchomienie dla potwierdzenia `changed=0`.
> Przy usuwaniu pamiętam, że Ansible zarządza tylko tym, co opisane – trzeba dodać `state: absent`.”
