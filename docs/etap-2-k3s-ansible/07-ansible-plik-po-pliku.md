# Etap 2 – Ansible plik po pliku: jak obronić go na rozmowie

Ten plik jest do **powtórki przed rozmową o pracę**. Dla każdego pliku z folderu
[ansible/](../../ansible/): co to jest, najważniejsze linie, dlaczego tak, i pytanie, które może
paść – z odpowiedzią. Podstawy (inventory, moduł, rola, idempotentność) są w
[teorii Ansible](01-teoria-ansible.md), a przebieg instalacji w [k3s przez Ansible](02-k3s-przez-ansible.md).

## Spis treści

1. [Cały projekt w 2 minuty](#1-cały-projekt-w-2-minuty)
2. [Mapa plików](#2-mapa-plików)
3. [ansible.cfg – ustawienia Ansible](#3-ansiblecfg--ustawienia-ansible)
4. [inventory.ini – lista maszyn](#4-inventoryini--lista-maszyn)
5. [group_vars/all/ – wspólne zmienne i Vault](#5-group_varsall--wspólne-zmienne-i-vault)
6. [requirements.yml – kolekcje](#6-requirementsyml--kolekcje)
7. [site.yml i playbooks/ – kolejność](#7-siteyml-i-playbooks--kolejność)
8. [Rola common – przygotowanie systemu](#8-rola-common--przygotowanie-systemu)
9. [Role k3s_server i k3s_agent – Kubernetes](#9-role-k3s_server-i-k3s_agent--kubernetes)
10. [Rola bootstrap – klony szablonu](#10-rola-bootstrap--klony-szablonu)
11. [Kontrola jakości – ansible-lint w CI](#11-kontrola-jakości--ansible-lint-w-ci)
12. [Decyzje, które warto umieć uzasadnić](#12-decyzje-które-warto-umieć-uzasadnić)
13. [Pytania podchwytliwe](#13-pytania-podchwytliwe)
14. [Jak się przygotować](#14-jak-się-przygotować)

## 1. Cały projekt w 2 minuty

Naucz się tego na pamięć własnymi słowami – to odpowiedź na „opowiedz o swoim projekcie z Ansible”:

> „Mam lab z pięcioma maszynami Ubuntu w VMware: master k3s, trzy workery i maszynę `monitoring`,
> która jest węzłem sterującym Ansible. Ansible łączy się po SSH kluczem, bez agentów.
>
> Kod jest podzielony na role. `common` przygotowuje każdą maszynę: pakiety, strefa czasowa,
> wyłączony swap, SSH tylko kluczem i firewall ufw z regułami zależnymi od roli maszyny.
> `k3s_server` instaluje k3s na masterze i odczytuje token dołączenia, a `k3s_agent` dołącza workery –
> token przekazuję przez `hostvars`, bez kopiowania ręcznie. Na końcu playbook czeka, aż wszystkie
> węzły będą Ready, i nadaje im etykiety.
>
> Całość uruchamiam jednym poleceniem `ansible-playbook site.yml`. Zadania są idempotentne – drugie
> uruchomienie pokazuje same `ok` – a zmiany sprawdzam najpierw przez `--check --diff`. Hasło sudo
> trzymam zaszyfrowane w Ansible Vault, a ansible-lint i syntax-check działają w GitHub Actions
> przy każdym pushu.”

## 2. Mapa plików

```
ansible/
├── ansible.cfg                     ustawienia samego Ansible
├── inventory.ini                   🔒 lista maszyn (tylko na monitoring; wzór: inventory.ini.example)
├── inventory-bootstrap.ini.example wzór listy świeżych klonów (adresy z DHCP)
├── requirements.yml                dodatkowe moduły do zainstalowania
├── site.yml                        GŁÓWNY plik – uruchamia wszystko po kolei
├── group_vars/all/
│   ├── main.yml                    wspólne zmienne
│   └── vault.yml                   🔒 zaszyfrowane hasło sudo (tylko na monitoring)
├── playbooks/
│   ├── prepare.yml                 rola common na wszystkich maszynach
│   ├── k3s.yml                     master → workery → kontrola
│   └── bootstrap.yml               rola bootstrap (raz, na świeżych klonach)
└── roles/
    ├── common/      tasks/ handlers/
    ├── k3s_server/  tasks/
    ├── k3s_agent/   tasks/
    └── bootstrap/   tasks/ defaults/ templates/
```

🔒 = plik poza gitem (repozytorium jest publiczne). Poza repozytorium jest też
`~/.ansible/vault-pass` – hasło do odszyfrowania `vault.yml`.

Jedna zasada porządkuje wszystko: **inventory mówi „na czym”, playbooki „w jakiej kolejności”,
role „jak”, a group_vars „z jakimi ustawieniami”.**

## 3. `ansible.cfg` – ustawienia Ansible

Plik: [ansible/ansible.cfg](../../ansible/ansible.cfg). Ansible czyta go z bieżącego katalogu,
dlatego polecenia uruchamiasz z `ansible/`.

| Linia | Co robi | Dlaczego |
|---|---|---|
| `inventory = inventory.ini` | domyślna lista maszyn | nie trzeba pisać `-i inventory.ini` |
| `roles_path = roles` | gdzie szukać ról | playbooki w `playbooks/` znajdują role z katalogu wyżej |
| `host_key_checking = True` | sprawdza klucze hostów w `known_hosts` | ochrona przed podszyciem; wyłączone ukryło kiedyś klony ze wspólnym kluczem |
| `StrictHostKeyChecking=accept-new` (w `ssh_args`) | nowy host dopisywany automatycznie, **zmieniony** klucz przerywa połączenie | wygoda przy pierwszym połączeniu bez utraty bezpieczeństwa |
| `become_exe = sudo.ws` | używa klasycznego sudo | Ubuntu 25.10+ ma sudo-rs, którego pytania o hasło Ansible nie rozpoznaje |
| `pipelining = True` | wysyła moduły przez jedno połączenie SSH, bez plików tymczasowych | szybciej |
| `ControlMaster`, `ControlPersist=60s` | jedno połączenie SSH używane wielokrotnie | szybciej przy wielu zadaniach |

> **Pytanie:** Dlaczego nie wyłączyłeś `host_key_checking`? W wielu poradnikach tak jest.
> Wyłączenie ukrywa atak man-in-the-middle i błędy konfiguracji. U mnie ukryło klony z tym samym
> kluczem hosta. `accept-new` daje wygodę (nowe maszyny dopisywane same) i bezpieczeństwo
> (zmiana klucza zatrzymuje połączenie).

> **Pytanie:** Co to jest `become`?
> Przejście na innego użytkownika, domyślnie root przez sudo. `become: true` w playbooku = zadania
> wykonują się z uprawnieniami roota, a Ansible łączy się jako zwykły użytkownik.

## 4. `inventory.ini` – lista maszyn

Wzór: [ansible/inventory.ini.example](../../ansible/inventory.ini.example). Prawdziwy plik
(z Twoimi adresami `192.168.180.x`) jest tylko na `monitoring` i w `.gitignore`.

```ini
[k3s_server]
k3s-master ansible_host=192.168.180.51

[k3s_agents]
k3s-worker-1 ansible_host=192.168.180.52
...

[monitoring_vm]
monitoring ansible_host=192.168.180.54

[k3s_cluster:children]     ← grupa grup: server + agents
k3s_server
k3s_agents

[all:vars]                 ← zmienne dla wszystkich
ansible_user=...
ansible_ssh_private_key_file=~/.ssh/k3s-lab
iface=ens33
admin_cidr=192.168.180.0/24
```

| Element | Znaczenie |
|---|---|
| `k3s-master` | nazwa maszyny w Ansible – staje się też jej hostname (`inventory_hostname`) |
| `ansible_host=` | adres, pod który Ansible się łączy |
| `[k3s_server]` | grupa – playbook pisze `hosts: k3s_server` |
| `:children` | grupa złożona z innych grup |
| `admin_cidr` | sieć administratora – tylko z niej firewall wpuszcza SSH i kubectl |

> **Pytanie:** Dlaczego `inventory.ini` nie jest w repozytorium?
> Zawiera adresy i nazwę użytkownika mojego środowiska. W repozytorium jest wzór `.example`,
> każdy kopiuje go i uzupełnia. W firmie inventory często **jest** w repozytorium (osobne dla dev
> i prod) albo jest dynamiczne – generowane z chmury czy VMware.

> **Pytanie:** Co to jest dynamiczne inventory?
> Lista maszyn pobierana na bieżąco z API (AWS, Azure, VMware, Proxmox) zamiast pisana ręcznie.
> Przy maszynach tworzonych i usuwanych automatycznie plik statyczny szybko by się zdezaktualizował.

## 5. `group_vars/all/` – wspólne zmienne i Vault

Plik: [ansible/group_vars/all/main.yml](../../ansible/group_vars/all/main.yml). Nazwa folderu
= nazwa grupy z inventory; `all` = wszystkie maszyny.

```yaml
timezone: Europe/Warsaw
k3s_channel: stable              # wersja k3s
k3s_pod_cidr: 10.42.0.0/16       # sieć podów – otwierana w firewallu
k3s_service_cidr: 10.43.0.0/16   # sieć usług – otwierana w firewallu
enable_ufw: true
ssh_disable_password: true
```

Obok leży `vault.yml` – zaszyfrowany (`$ANSIBLE_VAULT;1.1;AES256`), w środku
`ansible_become_password`, czyli hasło sudo. Klucz do odszyfrowania: `~/.ansible/vault-pass`,
wskazany zmienną `ANSIBLE_VAULT_PASSWORD_FILE` w `~/.bashrc`. Szczegóły: [Ansible Vault](03-ansible-vault.md).

> **Pytanie:** Gdzie trzymasz sekrety w Ansible?
> W Ansible Vault – plik szyfrowany AES256. Hasło do vaulta jest poza repozytorium, w pliku
> z uprawnieniami 600. W firmie dostarczałby je system CI albo menedżer sekretów (np. HashiCorp Vault).
> W publicznym repozytorium nie trzymam nawet zaszyfrowanego pliku – można by go łamać offline.

> **Pytanie:** Zmienna jest w inventory i w group_vars. Która wygrywa?
> Ansible ma ustaloną kolejność pierwszeństwa (ponad 20 poziomów). `group_vars/all` ma wyższy
> priorytet niż `[all:vars]` w inventory, a najwyższy mają `-e` z wiersza poleceń. Dlatego każdą
> zmienną trzymam w jednym miejscu – raz przez to straciłem czas (problem „Zmienna z inventory
> ignorowana” w [problemach Etapu 2](problemy.md#zmienna-z-inventory-ignorowana)).

## 6. `requirements.yml` – kolekcje

```yaml
collections:
  - name: community.general
```

Kolekcja to paczka dodatkowych modułów. `community.general` daje m.in. `ufw` (firewall)
i `timezone`. Instalacja:

```bash
ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force
```

> **Pytanie:** Czym jest `ansible-core`, a czym `ansible`?
> `ansible-core` to silnik i moduły wbudowane (`ansible.builtin.*`). Pakiet `ansible` to core
> plus zestaw ok. 100 kolekcji. W labie jest pełny pakiet `ansible` 14.5.0 (w środku
> ansible-core 2.21.5) przez pipx, a kolekcje, których projekt używa, są wypisane w
> `requirements.yml` i instalowane do `~/.ansible/collections` – tak wiadomo, od czego zależy kod,
> i ansible-lint (osobne środowisko pipx) też je widzi.

## 7. `site.yml` i `playbooks/` – kolejność

```yaml
# site.yml
- ansible.builtin.import_playbook: playbooks/prepare.yml   # 1. system na wszystkich
- ansible.builtin.import_playbook: playbooks/k3s.yml       # 2. Kubernetes
```

| Playbook | Plays | Na czym |
|---|---|---|
| [prepare.yml](../../ansible/playbooks/prepare.yml) | rola `common` | `all` |
| [k3s.yml](../../ansible/playbooks/k3s.yml) | rola `k3s_server` → rola `k3s_agent` → kontrola | master, workery, master |
| [bootstrap.yml](../../ansible/playbooks/bootstrap.yml) | rola `bootstrap` – **nie** jest w `site.yml` | świeże klony, osobne inventory |

Kontrola w `k3s.yml` – zadania warte omówienia:

```yaml
- name: Poczekaj, aż wszystkie węzły będą Ready
  ansible.builtin.command: k3s kubectl get nodes --no-headers
  register: nodes
  until: (nodes.stdout_lines | select('search', ' Ready') | list | length) == (groups['k3s_cluster'] | length)
  retries: 30
  delay: 10
  changed_when: false
```

- `register` – zapisuje wynik polecenia do zmiennej `nodes`,
- `until` + `retries` + `delay` – powtarza co 10 s, najwyżej 30 razy, aż warunek będzie prawdziwy,
- `changed_when: false` – polecenie tylko czyta, więc raport nie pokazuje fałszywego `changed`.

> **Pytanie:** Czym różni się playbook od roli?
> Rola to wielokrotnego użytku zestaw zadań na jeden temat, z ustaloną strukturą folderów.
> Playbook mówi, które role i zadania uruchomić na których grupach maszyn i w jakiej kolejności.

> **Pytanie:** `import_playbook` a `include_*`?
> `import_*` jest statyczny – Ansible wczytuje wszystko przed startem (lint i `--list-tasks`
> widzą całość). `include_*` jest dynamiczny – wczytywany w trakcie, może zależeć od warunku.

## 8. Rola `common` – przygotowanie systemu

Pliki: [tasks/main.yml](../../ansible/roles/common/tasks/main.yml),
[handlers/main.yml](../../ansible/roles/common/handlers/main.yml). Odpowiednik skryptu
`scripts/00-prepare-node.sh` z Etapu 1.

| Zadanie | Moduł | Uwagi do obrony |
|---|---|---|
| nazwa hosta | `hostname` | z `inventory_hostname` |
| `/etc/hosts` | `lineinfile` (usuń stare) + `blockinfile` | blok z markerami – Ansible zarządza tylko swoim fragmentem pliku; pętla Jinja2 po `groups['all']` |
| aktualizacje | `apt` `upgrade: safe` | `cache_valid_time: 3600` – nie odświeża listy pakietów częściej niż co godzinę |
| pakiety | `apt` `state: present` | curl, ca-certificates, gettext-base, jq, ufw |
| strefa czasowa | `community.general.timezone` | ze zmiennej `timezone` |
| swap | `command: swapoff -a` + `replace` w `/etc/fstab` | `when:` – tylko gdy swap jest; kubelet wymaga wyłączonego swapu |
| SSH tylko kluczem | `copy` → `/etc/ssh/sshd_config.d/01-lab.conf` + `notify` | nazwa `01-` wygrywa z `50-cloud-init.conf` (sshd bierze pierwszą wartość) |
| firewall | `community.general.ufw` w `block` z `when` | inne reguły dla `monitoring`, inne dla węzłów k3s |

Handler:

```yaml
- name: Przeładuj SSH
  ansible.builtin.systemd:
    name: ssh
    state: reloaded
```

Uruchamia się tylko, gdy zadanie z `notify: Przeładuj SSH` zgłosiło `changed`, i to raz – na końcu play.

> **Pytanie:** Czym jest handler?
> Zadanie uruchamiane tylko po zmianie, wywołane przez `notify`. Typowo restart usługi po zmianie
> jej konfiguracji. Kilka zgłoszeń = jedno uruchomienie, na końcu play.

> **Pytanie:** Dlaczego `blockinfile`, a nie `lineinfile` w pętli?
> `blockinfile` zarządza całym fragmentem między markerami: usunięcie maszyny z inventory usuwa
> ją też z `/etc/hosts`. `lineinfile` tylko dopisuje – stare wpisy zostawałyby.

> **Pytanie:** `command` vs `shell`?
> `command` uruchamia program bez powłoki – bezpieczniej, brak `|`, `>`, `&&`. `shell` przez
> `/bin/sh` – gdy potrzebne są przekierowania. Oba nie są idempotentne same z siebie, dlatego
> dopisuję `creates:`, `when:` albo `changed_when:`.

## 9. Role `k3s_server` i `k3s_agent` – Kubernetes

Pliki: [k3s_server/tasks/main.yml](../../ansible/roles/k3s_server/tasks/main.yml),
[k3s_agent/tasks/main.yml](../../ansible/roles/k3s_agent/tasks/main.yml).

**Master:**

1. `get_url` – pobiera oficjalny instalator `https://get.k3s.io`.
2. `command` – `k3s-install.sh server --node-ip … --flannel-iface … --node-taint …NoSchedule`,
   z `creates: /etc/systemd/system/k3s.service` (jest usługa → pomiń).
3. `wait_for` port 6443, potem pętla `until`, aż master jest `Ready`.
4. `slurp` czyta `/var/lib/rancher/k3s/server/node-token` (zwraca base64), `set_fact` zapisuje
   go jako `k3s_server_token`. Oba z `no_log: true` – token nie trafia do logów.

**Workery:**

```yaml
environment:
  K3S_URL: "https://{{ hostvars[groups['k3s_server'][0]].ansible_host }}:6443"
  K3S_TOKEN: "{{ hostvars[groups['k3s_server'][0]].k3s_server_token }}"
```

`hostvars[nazwa]` – zmienne innej maszyny. `groups['k3s_server'][0]` – pierwsza maszyna w grupie.
Worker bierze adres i token mastera bez wpisywania ich ręcznie.

> **Pytanie:** Jak przekazujesz dane między hostami w Ansible?
> `set_fact` na jednym hoście, a na innym odczyt przez `hostvars['nazwa'].zmienna`. Tak przekazuję
> token dołączenia k3s z mastera do workerów.

> **Pytanie:** Instalacja przez `command` nie jest idempotentna. Jak to rozwiązałeś?
> Parametr `creates:` – jeśli plik usługi już istnieje, zadanie jest pomijane. Drugie uruchomienie
> nie przeinstalowuje k3s.

> **Pytanie:** Dlaczego taint `NoSchedule` na masterze?
> Żeby zwykłe pody nie zabierały zasobów warstwie sterującej. Master tylko zarządza klastrem.

> **Pytanie:** Czemu nie gotowa rola z Ansible Galaxy, np. `k3s-ansible`?
> W firmie pewnie tak bym zrobił. Tu chciałem zrozumieć każdy krok – role są krótkie,
> a gotowe rozwiązanie znam i wiem, że istnieje.

## 10. Rola `bootstrap` – klony szablonu

Pliki: [tasks/main.yml](../../ansible/roles/bootstrap/tasks/main.yml),
[defaults/main.yml](../../ansible/roles/bootstrap/defaults/main.yml),
[templates/01-lab.yaml.j2](../../ansible/roles/bootstrap/templates/01-lab.yaml.j2),
playbook [bootstrap.yml](../../ansible/playbooks/bootstrap.yml), wzór inventory
[inventory-bootstrap.ini.example](../../ansible/inventory-bootstrap.ini.example).

Automat do Etapu 0, krok 4 – w labie zrobione ręcznie. Co pokazuje (warto umieć omówić):

| Technika | Gdzie w roli |
|---|---|
| `assert` – przerwij z czytelnym komunikatem | brak `bootstrap_static_ip` |
| **facts** – wiedza zebrana z maszyny | `ansible_facts['machine_id']`, klucz hosta SSH |
| porównanie między hostami | `ansible_play_hosts | map('extract', hostvars, …)` – czy ktoś ma ten sam machine-id |
| `template` (Jinja2) | Netplan ze stałym adresem z `01-lab.yaml.j2` |
| `defaults/` – najsłabsze zmienne | brama, DNS, maska – nadpisywane w inventory |
| restart w tle (`async: 1, poll: 0`) | po restarcie maszyna ma **nowy** adres, więc moduł `reboot` czekałby na stary |
| zmiana `ansible_host` w trakcie | `set_fact: ansible_host: "{{ bootstrap_static_ip }}"` + `wait_for_connection` |

> **Pytanie:** Czym są facts?
> Informacje, które Ansible zbiera z maszyny na początku play (moduł `setup`): system, adresy,
> pamięć, machine-id, klucze hosta. Używam ich w warunkach i szablonach.

> **Pytanie:** `defaults/` a `vars/` w roli?
> `defaults/` mają najniższy priorytet – to wartości do nadpisania przez użytkownika roli.
> `vars/` mają wysoki priorytet – stałe wewnętrzne roli.

## 11. Kontrola jakości – ansible-lint w CI

[.github/workflows/lint.yml](../../.github/workflows/lint.yml) przy każdym pushu:

```bash
ansible-playbook --syntax-check site.yml
ansible-lint site.yml playbooks roles
```

Lokalnie przed uruchomieniem: `ansible-lint`, potem `ansible-playbook site.yml --check --diff`.

> **Pytanie:** Jak testujesz playbooki?
> Trzy poziomy: ansible-lint i syntax-check w CI, `--check --diff` przed zmianą na maszynach,
> a po uruchomieniu – drugie uruchomienie musi dać zero `changed` (test idempotentności).
> Następny krok to Molecule – testy ról w kontenerach.

## 12. Decyzje, które warto umieć uzasadnić

| Decyzja | Uzasadnienie |
|---|---|
| Ansible na osobnej maszynie `monitoring` | Ansible nie działa natywnie na Windowsie; węzeł sterujący poza klastrem nie zniknie razem z nim |
| klucz SSH `~/.ssh/ansible` osobny od klucza administratora | inny „użytkownik” – można go odebrać bez odcinania siebie |
| pełne nazwy modułów (`ansible.builtin.copy`) | jednoznaczność (FQCN), wymaga tego ansible-lint |
| `creates:` / `changed_when:` przy `command` | uczciwy raport i idempotentność |
| `no_log: true` przy tokenie | sekret nie trafia do logów i wyjścia |
| `become_exe = sudo.ws` | obejście niezgodności sudo-rs w Ubuntu 25.10+ |
| `host_key_checking = True` + `accept-new` | bezpieczeństwo bez ręcznego akceptowania kluczy |
| Vault poza gitem | publiczne repozytorium |

## 13. Pytania podchwytliwe

**„Co się stanie, jeśli uruchomisz playbook drugi raz?”**
Nic się nie zepsuje – zadania sprawdzają stan. W `PLAY RECAP` powinny być same `ok` i `changed=0`.

**„Jedna maszyna jest wyłączona. Co zrobi Ansible?”**
Oznaczy ją jako `UNREACHABLE` i będzie kontynuował na pozostałych. Na końcu `PLAY RECAP` pokaże
`unreachable=1`. Ponowne uruchomienie tylko dla niej: `--limit k3s-worker-2`.

**„Jak uruchomić tylko jedną maszynę albo jeden fragment?”**
`--limit nazwa` (maszyny), `--tags`/`--skip-tags` (zadania z tagami), `--start-at-task "nazwa"`.

**„Jak zrobić aktualizację klastra bez przerwy?”**
`serial: 1` w play – Ansible przechodzi po maszynach pojedynczo; przed każdą `kubectl drain`,
po – `uncordon`. W labie tego nie mam, ale tak bym to zrobił.

**„Czym Ansible różni się od Terraform?”**
Terraform tworzy infrastrukturę (maszyny, sieci, w chmurze), Ansible konfiguruje to, co już istnieje.
Często używa się obu: Terraform tworzy maszyny, Ansible je konfiguruje. U mnie rolę „tworzenia”
pełni Packer.

**„Ansible a Puppet/Chef?”**
Ansible jest bezagentowy (SSH) i push – uruchamiam go, kiedy chcę. Puppet i Chef mają agenta
na każdej maszynie i model pull – agent sam co jakiś czas pobiera konfigurację.

## 14. Jak się przygotować

Gotowe ćwiczenie krok po kroku (instalacja i usunięcie pakietu): [08-cwiczenie-ansible-pakiet.md](08-cwiczenie-ansible-pakiet.md).

Czytanie nie wystarczy – na rozmowie liczy się, że **robiłeś to sam**. Na maszynie `monitoring`:

```bash
cd ~/k3s-monitoring-lab/ansible
ansible all -m ping                              # czy dosięgam wszystkich maszyn
ansible-playbook site.yml --list-tasks           # wszystkie zadania po kolei – porównaj z tym plikiem
ansible-playbook site.yml --check --diff         # próba na sucho – powinno być changed=0
ansible k3s_agents -m setup -a 'filter=ansible_machine_id'   # facts z workerów
ansible-vault view group_vars/all/vault.yml      # otwarty sejf
```

Potem jedna mała zmiana od siebie, np. dopisz pakiet `htop` w roli `common`, uruchom
`--check --diff`, potem naprawdę, i drugi raz – zobaczysz `changed`, a potem `ok`.
Taką historię („dodałem, sprawdziłem na sucho, zweryfikowałem idempotentność”) dobrze się opowiada.

Uczciwie o pochodzeniu kodu: jeśli pisałeś go z pomocą AI, możesz to powiedzieć – ważne, żebyś
umiał wyjaśnić każdą linię i zmienić ją sam. Pytanie „dlaczego tak?” padnie na pewno.
