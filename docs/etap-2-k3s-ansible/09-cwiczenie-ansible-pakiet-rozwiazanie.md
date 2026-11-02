# Etap 2 – ćwiczenie z Ansible: pakiet na wszystkich maszynach – rozwiązanie

Rozwiązanie [ćwiczenia z pakietem](08-cwiczenie-ansible-pakiet.md). Najpierw zrób je sam – tu
porównujesz wynik. Wyniki poniżej to **przykład** tego, co pokazuje ansible-core 2.21: liczby
w `PLAY RECAP` (`ok=…`) mogą się u Ciebie różnić, ważne są `changed`, `failed` i `rc`.

## Część A – stan przed zmianą

🐧 `monitoring`:

```bash
cd ~/k3s-monitoring-lab && git pull
cd ansible
ansible all -m ping
```

```
k3s-master | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
... (tak samo dla 4 pozostałych)
```

`ping` w Ansible to nie ping sieciowy – sprawdza, czy Ansible zaloguje się po SSH i uruchomi Pythona.

```bash
ansible all -m command -a "which tree"
```

```
k3s-master | FAILED | rc=1 >>
non-zero return code
k3s-worker-1 | FAILED | rc=1 >>
non-zero return code
...
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
Updating 1a2b3c3..1a2b3c4
Fast-forward
 ansible/roles/common/tasks/main.yml | 1 +
```

### Krok 4 – próba na sucho

```bash
ansible-playbook playbooks/prepare.yml --check --diff
```

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
The following NEW packages will be installed:
  tree
0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.
changed: [k3s-master]
...
PLAY RECAP *********************************************************************
k3s-master    : ok=…  changed=1  unreachable=0  failed=0  skipped=…
```

`--check` niczego nie instaluje – moduł `apt` pyta tylko, co by zrobił. `--diff` dokłada opis
zmiany (tu: lista nowych pakietów).

Jeśli przy „Zaktualizuj system” też jest `changed`, to są czekające aktualizacje Ubuntu – nie
dotyczy to ćwiczenia, ale playbook je zainstaluje.

### Krok 5 – jedna maszyna

```bash
ansible-playbook playbooks/prepare.yml --limit k3s-worker-1
```

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
changed: [k3s-worker-1]
...
PLAY RECAP *********************************************************************
k3s-worker-1  : ok=…  changed=1  unreachable=0  failed=0
```

W wyniku jest tylko `k3s-worker-1`.

### Krok 6 – sprawdzenie

```bash
ansible all -m command -a "which tree"
```

```
k3s-worker-1 | CHANGED | rc=0 >>
/usr/bin/tree
k3s-master | FAILED | rc=1 >>
non-zero return code
...
```

`CHANGED` przy module `command` nic nie zmieniło – Ansible nie wie, co robi dowolny program,
więc ostrożnie zakłada zmianę. W playbookach dlatego dopisujemy `changed_when: false` przy
poleceniach, które tylko czytają (np. w `playbooks/k3s.yml`).

### Krok 7 i 8 – wszystkie maszyny, dwa razy

```bash
ansible-playbook playbooks/prepare.yml
```

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
ok: [k3s-worker-1]
changed: [k3s-master]
changed: [k3s-worker-2]
changed: [k3s-worker-3]
changed: [monitoring]
```

Drugi raz:

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
ok: [k3s-master]
ok: [k3s-worker-1]
...
PLAY RECAP *********************************************************************
k3s-master    : ok=…  changed=0  unreachable=0  failed=0
k3s-worker-1  : ok=…  changed=0  unreachable=0  failed=0
...
```

### Krok 9 – pakiet działa

```bash
ssh k3s-master "tree -L 1 /etc/rancher"
```

```
/etc/rancher
├── k3s
└── node

2 directories, 0 files
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

Po usunięciu `- tree` z listy, wysłaniu i uruchomieniu playbooka:

```
TASK [common : Zainstaluj potrzebne pakiety] ***********************************
ok: [k3s-master]
...
```

```bash
ansible all -m command -a "which tree"
```

```
k3s-master | CHANGED | rc=0 >>
/usr/bin/tree
...
```

Pakiet **nadal jest**. Zadanie mówi teraz: „curl, ca-certificates, gettext-base, jq i ufw mają być”.
O `tree` nic nie mówi, więc Ansible go nie dotyka.

### Krok 3 – jawne `state: absent`

🪟 `ansible/roles/common/tasks/main.yml`, zaraz pod zadaniem instalacji:

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
ansible-playbook playbooks/prepare.yml
```

```
TASK [common : Usuń niepotrzebne pakiety] **************************************
The following packages will be REMOVED:
  tree
changed: [k3s-master]
changed: [k3s-worker-1]
...
```

### Krok 5 i 6 – sprawdzenie i idempotentność

```bash
ansible all -m command -a "which tree"
```

```
k3s-master | FAILED | rc=1 >>
non-zero return code
...
```

Drugie uruchomienie playbooka: przy „Usuń niepotrzebne pakiety” wszędzie `ok`, `changed=0`.

**Odpowiedzi:**
- **Dlaczego usunięcie linii nie wystarczyło:** Ansible jest deklaratywny, ale tylko w zakresie
  tego, co opisujesz. Nie porównuje maszyny z „pełną listą tego, co powinno być” – pilnuje
  wyłącznie stanu zapisanego w zadaniach. Czego nie ma w kodzie, tego nie zmienia.
- **`present` a `absent`:** `present` – pakiet ma być (zainstaluj, jeśli go nie ma); `absent` –
  pakietu ma nie być (usuń, jeśli jest). W obu przypadkach, gdy stan się zgadza – `ok`.
  Jest też `latest` – zawsze najnowsza wersja, ale wtedy każde uruchomienie może coś aktualizować.

## Część D – sprzątanie w kodzie

Po usunięciu zadania „Usuń niepotrzebne pakiety” i uruchomieniu playbooka – `changed=0`,
a `tree` dalej nie ma (nikt go nie instaluje).

🪟 Historia:

```bash
git log --oneline -5 -- ansible/roles/common/tasks/main.yml
```

```
9d8e7f6 Ansible: koniec ćwiczenia, usunięte zadanie absent
5c4b3a2 Ansible: usuń tree ze wszystkich maszyn (state: absent)
4b3a291 Ansible: tree poza listą pakietów
1a2b3c4 Ansible: pakiet tree na wszystkich maszynach (ćwiczenie)
…
```

**Odpowiedzi:**
- **Kiedy zostawić `state: absent`:** gdy są maszyny, których jeszcze nie przeszedł playbook
  (wyłączona, odtworzona ze starego snapshotu), albo pakiet jest niebezpieczny i ma nigdy nie wrócić
  (np. `telnetd`). Wtedy zadanie pilnuje go stale. Usunąć – gdy wszystkie maszyny są już czyste
  i pakiet nie ma szans wrócić; inaczej kod puchnie od historycznych zadań.
- **Cofnięcie roli do stanu sprzed ćwiczenia:**
  `git checkout <hash> -- ansible/roles/common/tasks/main.yml` (`<hash>` – commit sprzed ćwiczenia,
  z `git log`), potem commit. Plik wraca do dawnej wersji, a historia zostaje.

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
