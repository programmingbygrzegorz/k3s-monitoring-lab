# Teoria Ansible – wprowadzenie dla początkujących

Ten plik tłumaczy, **czym jest Ansible i jak działa**, na przykładach z tego repozytorium.
Nie musisz go czytać, żeby przejść laboratorium – instrukcje są w [przewodniku](00-przewodnik.md)
i w [docs/06](06-ansible.md). Ale po lekturze będziesz rozumieć, co robią polecenia, które wpisujesz.

## Spis treści

1. [Po co Ansible](#1-po-co-ansible)
2. [Jak działa – architektura](#2-jak-działa--architektura)
3. [Inventory – lista maszyn](#3-inventory--lista-maszyn)
4. [Moduły i kolekcje](#4-moduły-i-kolekcje)
5. [Polecenia ad-hoc](#5-polecenia-ad-hoc)
6. [Playbook, play, task](#6-playbook-play-task)
7. [Role](#7-role)
8. [Zmienne i ich pierwszeństwo](#8-zmienne-i-ich-pierwszeństwo)
9. [Facts – wiedza o maszynie](#9-facts--wiedza-o-maszynie)
10. [Szablony Jinja2](#10-szablony-jinja2)
11. [Handlery](#11-handlery)
12. [register, when, loop, until](#12-register-when-loop-until)
13. [Become – uprawnienia roota](#13-become--uprawnienia-roota)
14. [Idempotentność](#14-idempotentność)
15. [Próba na sucho: --check i --diff](#15-próba-na-sucho---check-i---diff)
16. [Jak czytać wynik](#16-jak-czytać-wynik)
17. [ansible.cfg](#17-ansiblecfg)
18. [Narzędzia wokół Ansible](#18-narzędzia-wokół-ansible)
19. [Ansible na tle innych narzędzi](#19-ansible-na-tle-innych-narzędzi)
20. [Mapa tego repozytorium](#20-mapa-tego-repozytorium)
21. [Ściągawka poleceń](#21-ściągawka-poleceń)

---

## 1. Po co Ansible

Bez automatyzacji administrator loguje się na każdy serwer i wpisuje te same polecenia.
Przy pięciu maszynach to nudne, przy pięciuset – niemożliwe, a każda ręczna różnica
(zapomniany krok, literówka) sprawia, że serwery przestają być identyczne.

Ansible pozwala **opisać w plikach, jak ma wyglądać system** („pakiet `curl` zainstalowany,
swap wyłączony, firewall wpuszcza SSH tylko z mojej sieci”), a potem doprowadzić do tego stanu
wiele maszyn naraz. To podejście nazywa się **Infrastructure as Code (IaC)**:

| Ręcznie | Ansible |
|---|---|
| polecenia wpisywane na każdej maszynie | jeden plik, uruchamiany dla wszystkich |
| wiedza w głowie administratora | wiedza w repozytorium – z historią zmian w gicie |
| każde uruchomienie może dać inny wynik | wynik powtarzalny |
| trudno sprawdzić, co się zmieni | `--check --diff` pokazuje zmiany przed wykonaniem |

## 2. Jak działa – architektura

```
         węzeł sterujący (control node)            maszyny zarządzane (managed nodes)
        ┌──────────────────────────────┐          ┌────────────────────┐
        │ monitoring                   │   SSH    │ k3s-master         │
        │  ansible-playbook site.yml   │ ───────▶ │  python3           │
        │  inventory.ini, role, ...    │ ───────▶ │ k3s-worker-1 ...   │
        └──────────────────────────────┘          └────────────────────┘
```

- **Węzeł sterujący** – maszyna z zainstalowanym Ansible, z której uruchamiasz polecenia.
  Musi to być Linux lub macOS (na Windowsie – WSL). W tym labie: `monitoring`.
- **Maszyny zarządzane** – serwery, które konfigurujesz. **Nic na nich nie instalujesz:**
  wystarczy SSH i Python, które Ubuntu ma od początku. To jest cecha **agentless**
  (bez agenta) – w odróżnieniu od np. Puppeta czy Chefa, które wymagają programu-agenta na
  każdym serwerze.

Co się dzieje przy każdym zadaniu:

1. Ansible łączy się z maszyną przez SSH (kluczem z inventory).
2. Kopiuje na nią mały program w Pythonie – kod modułu – z parametrami zadania.
3. Uruchamia go (w razie potrzeby przez `sudo`).
4. Moduł sprawdza stan, w razie potrzeby go zmienia i odsyła wynik w JSON:
   czy coś zmienił (`changed`), czy się udało (`failed`).
5. Ansible usuwa program i przechodzi do kolejnego zadania.

Zadania wykonywane są **na wszystkich maszynach równolegle** (domyślnie 5 naraz – `forks`),
ale **po kolei**: zadanie 2 zaczyna się dopiero, gdy zadanie 1 skończy się wszędzie.

## 3. Inventory – lista maszyn

Inventory mówi Ansible, **jakie maszyny istnieją i jak się z nimi połączyć**. Format INI
(`ansible/inventory.ini`):

```ini
[k3s_server]                              # grupa
k3s-master ansible_host=192.168.180.51    # nazwa maszyny + adres

[k3s_agents]
k3s-worker-1 ansible_host=192.168.180.52
k3s-worker-2 ansible_host=192.168.180.53

[monitoring_vm]
monitoring ansible_host=192.168.180.54

[k3s_cluster:children]                    # grupa złożona z grup
k3s_server
k3s_agents

[all:vars]                                # zmienne dla wszystkich maszyn
ansible_user=grzegorz
ansible_ssh_private_key_file=~/.ssh/ansible
```

| Element | Znaczenie |
|---|---|
| `k3s-master` | nazwa maszyny w Ansible (`inventory_hostname`) – nie musi być nazwą w DNS |
| `ansible_host` | adres, pod który Ansible się łączy |
| `[nazwa]` | grupa – playbook mówi „wykonaj na grupie `k3s_agents`” |
| `[x:children]` | grupa grup – `k3s_cluster` = master + workery, bez `monitoring` |
| `[x:vars]` | zmienne dla grupy |
| `all` | grupa wbudowana – wszystkie maszyny |

Zmienne zaczynające się od `ansible_` sterują połączeniem: `ansible_user` (użytkownik SSH),
`ansible_ssh_private_key_file` (klucz), `ansible_port`, `ansible_python_interpreter`.

Podgląd tego, jak Ansible rozumie inventory:

```bash
ansible-inventory --graph        # drzewo grup i maszyn
ansible-inventory --host k3s-master   # zmienne jednej maszyny
```

## 4. Moduły i kolekcje

**Moduł** to jednostka pracy: wie, jak zrobić jedną rzecz i jak sprawdzić, czy jest już
zrobiona. Przykłady z ról tego repo:

| Moduł | Co robi |
|---|---|
| `ansible.builtin.apt` | instaluje / aktualizuje pakiety |
| `ansible.builtin.hostname` | ustawia nazwę hosta |
| `ansible.builtin.blockinfile` | wstawia blok tekstu do pliku między znacznikami |
| `ansible.builtin.lineinfile` | pilnuje jednej linii w pliku |
| `ansible.builtin.copy` / `template` | wgrywa plik / plik z szablonu |
| `ansible.builtin.systemd` | uruchamia, restartuje, przeładowuje usługi |
| `ansible.builtin.get_url` | pobiera plik z internetu |
| `ansible.builtin.command` | uruchamia dowolne polecenie (ostatnia deska ratunku) |
| `ansible.builtin.wait_for` | czeka, aż port zacznie odpowiadać |
| `community.general.ufw` | reguły firewalla ufw |
| `community.general.timezone` | strefa czasowa |

**Kolekcja** to paczka modułów (i innych dodatków). Pełna nazwa modułu – *FQCN* – ma trzy części:

```
community.general.ufw
│         │       └─ moduł
│         └─ kolekcja
└─ przestrzeń nazw (autor)
```

`ansible.builtin` jest zawsze dostępny (część `ansible-core`). Pozostałe kolekcje instaluje
`ansible-galaxy` według `requirements.yml`. Dokumentacja każdego modułu jest dostępna offline:

```bash
ansible-doc community.general.ufw      # parametry i przykłady
ansible-doc -l | grep ufw              # wyszukiwanie modułów
```

> Moduły zamiast `command` – dlaczego? `apt: name=curl state=present` **sprawdza**, czy pakiet
> jest, i instaluje tylko w razie potrzeby. `command: apt install curl` uruchamia się za każdym
> razem i Ansible nie wie, czy coś zmienił. Moduły dają idempotentność za darmo.

## 5. Polecenia ad-hoc

Jednorazowe zadanie bez pisania playbooka:

```bash
ansible <grupa> -m <moduł> -a "<argumenty>"
```

| Polecenie | Co robi |
|---|---|
| `ansible all -m ping` | test: SSH + Python na każdej maszynie (to **nie** jest ping ICMP) |
| `ansible all -m command -a "uptime"` | polecenie na wszystkich maszynach |
| `ansible k3s_agents -m command -a "free -h"` | tylko na workerach |
| `ansible all -m debug -a 'msg="{{ iface }}"'` | wartość zmiennej, którą widzi Ansible |
| `ansible all -m setup -a "filter=ansible_distribution*"` | wybrane *facts* (rozdział 9) |
| `ansible all -b -K -m apt -a "name=htop state=present"` | instalacja pakietu przez `sudo` (`-b` = become, `-K` = pytaj o hasło) |

Ad-hoc służy do sprawdzania i szybkich akcji. Wszystko, co ma być powtarzalne, trafia do playbooka.

## 6. Playbook, play, task

**Playbook** to plik YAML z listą **plays**. Każdy play mówi: *na jakich maszynach* (`hosts`)
wykonać *jakie zadania* (`tasks` lub `roles`). Fragment `ansible/playbooks/k3s.yml`:

```yaml
- name: Węzeł sterujący k3s        # play 1
  hosts: k3s_server                # na jakiej grupie
  become: true                     # przez sudo
  roles:
    - k3s_server                   # zadania z roli

- name: Kontrola klastra i role węzłów   # play 2
  hosts: k3s_server
  become: true
  tasks:
    - name: Pokaż stan klastra             # task
      ansible.builtin.command: k3s kubectl get nodes -o wide
      register: cluster
      changed_when: false
```

| Pojęcie | Czym jest |
|---|---|
| **playbook** | plik – cały scenariusz |
| **play** | „na tych maszynach zrób to” – jeden element listy na najwyższym poziomie |
| **task** | jedno wywołanie modułu z `name` (opis widoczny w wyniku) |

Playbooki można składać: `ansible/site.yml` to tylko dwa `import_playbook`
(`prepare.yml`, potem `k3s.yml`) – całe laboratorium jednym poleceniem.

**YAML** w skrócie: wcięcia spacjami (nigdy tabulatorem) wyznaczają strukturę, `-` zaczyna
element listy, `klucz: wartość` to słownik. Błędne wcięcie = błąd składni – dlatego lint.

## 7. Role

Gdy zadań przybywa, dzieli się je na **role** – foldery o ustalonej strukturze, które można
używać wielokrotnie:

```
roles/common/
├── tasks/main.yml       # zadania (jedyny wymagany plik)
├── handlers/main.yml    # handlery – rozdział 11
├── defaults/main.yml    # domyślne wartości zmiennych (najniższy priorytet)
├── templates/           # szablony Jinja2 (*.j2) – rozdział 10
├── files/               # pliki kopiowane bez zmian
└── vars/main.yml        # zmienne roli (wysoki priorytet)
```

Ansible sam wie, gdzie szukać: `template: src=01-lab.yaml.j2` szuka w `templates/` roli,
`notify: Przeładuj SSH` – w `handlers/`.

Role w tym repozytorium:

| Rola | Odpowiednik skryptu | Co robi |
|---|---|---|
| `bootstrap` | ręczna konfiguracja klonów | unikalny machine-id i klucze SSH, nazwa hosta, stały IP |
| `common` | `00-prepare-node.sh` | `/etc/hosts`, aktualizacje, swap, SSH, firewall |
| `k3s_server` | `01-install-master.sh` | instalacja mastera, odczyt tokenu |
| `k3s_agent` | `02-install-worker.sh` | dołączenie workera z tokenem mastera |

Gotowe role innych autorów są w **Ansible Galaxy** (`ansible-galaxy role install ...`).

## 8. Zmienne i ich pierwszeństwo

Zmienne pozwalają pisać role ogólne, a konkretne wartości trzymać osobno:

```yaml
- name: Ustaw strefę czasową
  community.general.timezone:
    name: "{{ timezone }}"         # wartość z group_vars/all.yml: Europe/Warsaw
```

Gdzie można je zdefiniować (od **najniższego** do **najwyższego** priorytetu – wybrane):

| # | Miejsce | W tym repo |
|---|---|---|
| 1 | `defaults/main.yml` roli | `roles/bootstrap/defaults/main.yml` |
| 2 | zmienne grup w inventory (`[all:vars]`) | `iface`, `admin_cidr`, `ansible_user` |
| 3 | `group_vars/all.yml` | `timezone`, `k3s_channel`, `enable_ufw` |
| 4 | `group_vars/<grupa>.yml` | – |
| 5 | zmienne hosta w inventory / `host_vars/<host>.yml` | `ansible_host` |
| 6 | facts (rozdział 9) | `ansible_distribution` |
| 7 | `vars:` w playu, `vars/main.yml` roli | – |
| 8 | `set_fact`, `register` | `k3s_server_token` |
| 9 | `-e` w wierszu poleceń (*extra vars*) | – zawsze wygrywa |

Pułapka, która wystąpiła w tym labie: `admin_cidr` był i w inventory, i w `group_vars/all.yml`
– wygrywał `group_vars` (3 > 2), więc zmiana w inventory nic nie dawała. Dlatego wartości
zależne od Twojej sieci są **tylko** w inventory. Sprawdzenie:

```bash
ansible all -m debug -a 'msg="{{ admin_cidr }}"'
```

Zmienne magiczne, które Ansible ustawia sam: `inventory_hostname` (nazwa maszyny z inventory),
`groups` (wszystkie grupy i ich maszyny), `hostvars` (zmienne innych maszyn). Dzięki `hostvars`
rola `k3s_agent` czyta token zapamiętany na masterze:

```yaml
K3S_TOKEN: "{{ hostvars[groups['k3s_server'][0]].k3s_server_token }}"
#              zmienne maszyny  pierwszej z grupy k3s_server   zmienna ustawiona set_fact
```

## 9. Facts – wiedza o maszynie

Na początku każdego playa Ansible zbiera **facts**: system, wersję, adresy IP, karty sieciowe,
pamięć, dyski. To zadanie `Gathering Facts` na początku wyniku.

```bash
ansible k3s-master -m setup                               # wszystko (długie)
ansible k3s-master -m setup -a "filter=ansible_memtotal_mb"
```

Facts używa się jak zmiennych, np. `{{ ansible_distribution_version }}` albo w warunkach
(`when: ansible_os_family == "Debian"`). Gdy nie są potrzebne, `gather_facts: false`
przyspiesza play.

## 10. Szablony Jinja2

Wszystko w `{{ }}` to wyrażenie **Jinja2** – języka szablonów. Moduł `template` wypełnia nim
cały plik. Przykład z `roles/bootstrap/templates/01-lab.yaml.j2` (plik Netplan):

```jinja
      addresses: [{{ bootstrap_static_ip }}/{{ bootstrap_prefix }}]
      nameservers:
        addresses: [{{ bootstrap_dns | join(', ') }}]
```

oraz pętla z roli `common` (blok w `/etc/hosts`):

```jinja
{% for host in groups['all'] %}
{{ hostvars[host].ansible_host }} {{ host }}
{% endfor %}
```

| Składnia | Znaczenie |
|---|---|
| `{{ zmienna }}` | wstaw wartość |
| `{% for %}` / `{% if %}` | pętla / warunek |
| `{{ x \| filtr }}` | przekształcenie: `b64decode`, `trim`, `default('a')`, `length`, `join(',')` |

> W YAML wartość zaczynająca się od `{{` musi być w cudzysłowie: `name: "{{ timezone }}"`.

## 11. Handlery

**Handler** to zadanie uruchamiane **tylko wtedy, gdy coś się zmieniło** – i tylko raz, na końcu
playa. Typowe zastosowanie: przeładowanie usługi po zmianie konfiguracji.

```yaml
# roles/common/tasks/main.yml
- name: Wyłącz logowanie hasłem przez SSH
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/01-lab.conf
    content: "PasswordAuthentication no\n"
  notify: Przeładuj SSH                 # „jeśli zmieniłeś – zawołaj handler”

# roles/common/handlers/main.yml
- name: Przeładuj SSH
  ansible.builtin.systemd:
    name: ssh
    state: reloaded
```

Plik bez zmian → `ok` → SSH nie jest przeładowywany. Dzięki temu drugie uruchomienie niczego
nie restartuje bez potrzeby.

## 12. register, when, loop, until

| Słowo | Co robi | Przykład z repo |
|---|---|---|
| `register` | zapisuje wynik zadania do zmiennej | `register: nodes` → `nodes.stdout` |
| `when` | wykonaj tylko, jeśli warunek prawdziwy | `when: inventory_hostname in groups['k3s_cluster']` |
| `loop` | powtórz zadanie dla każdego elementu | `loop: "{{ groups['k3s_agents'] }}"` → `{{ item }}` |
| `until` + `retries` + `delay` | ponawiaj, aż warunek będzie spełniony | czekanie, aż węzły będą `Ready` (30 × co 10 s) |
| `changed_when` | kiedy uznać zadanie za zmianę | `changed_when: false` dla poleceń tylko odczytujących |
| `creates` | pomiń `command`, jeśli plik istnieje | instalator k3s nie uruchomi się drugi raz |
| `no_log` | nie pokazuj wartości w wyniku | token klastra |

Fragment z `playbooks/k3s.yml` łączący kilka z nich:

```yaml
- name: Poczekaj, aż wszystkie węzły będą Ready
  ansible.builtin.command: k3s kubectl get nodes --no-headers
  register: nodes
  until: (nodes.stdout_lines | select('search', ' Ready') | list | length) == (groups['k3s_cluster'] | length)
  retries: 30
  delay: 10
  changed_when: false
```

„Uruchamiaj `kubectl get nodes`, licz linie z `Ready`, aż będzie ich tyle, ile maszyn
w grupie `k3s_cluster` – najwyżej 30 razy co 10 sekund.”

## 13. Become – uprawnienia roota

Ansible loguje się jako zwykły użytkownik (`ansible_user`). Do zmian w systemie potrzebny jest
root – **become** to przejście na niego, domyślnie przez `sudo`.

| Gdzie | Zapis |
|---|---|
| w playu | `become: true` |
| w wierszu poleceń | `-b` / `--become` |
| hasło sudo | `-K` / `--ask-become-pass` – Ansible pyta raz, na starcie |
| program | `become_exe` w `ansible.cfg` (w tym labie `sudo.ws` – patrz niżej) |

Logowanie przez SSH odbywa się kluczem, ale `sudo` w Ubuntu i tak wymaga hasła – stąd
`BECOME password:`. Ubuntu 25.10+ ma domyślnie sudo-rs, którego pytania o hasło Ansible nie
rozpoznaje, dlatego `ansible.cfg` używa klasycznego `sudo.ws`.

## 14. Idempotentność

Najważniejsza idea Ansible: **opisujesz stan, a nie kroki**.

| Skrypt (kroki) | Ansible (stan) |
|---|---|
| `echo "192.168.180.51 k3s-master" >> /etc/hosts` | „w `/etc/hosts` jest blok z tymi maszynami” |
| uruchomiony 3 razy → 3 kopie wpisu | uruchomiony 3 razy → nadal jeden blok |

Zadanie **idempotentne** daje ten sam wynik bez względu na to, ile razy je uruchomisz.
Praktyczny test: **drugie uruchomienie playbooka powinno pokazać `changed=0`**. Jeśli nie –
któreś zadanie zmienia coś za każdym razem (najczęściej `command` bez `changed_when` lub `creates`).

Dzięki temu playbook to nie tylko instalator, ale też **naprawiacz**: gdy ktoś ręcznie zepsuje
konfigurację, ponowne uruchomienie przywróci stan opisany w kodzie.

## 15. Próba na sucho: --check i --diff

```bash
ansible-playbook playbooks/prepare.yml --check --diff --ask-become-pass
```

- `--check` – moduły tylko sprawdzają, co by zmieniły, **niczego nie zmieniając**.
- `--diff` – pokazuje różnice w plikach (`-` usunięte linie, `+` dodane).

Ograniczenie: moduł `command` w trybie check jest pomijany (Ansible nie wie, co robi dowolne
polecenie), więc zadania zależne od jego wyniku mogą się zachować inaczej niż naprawdę.
W tym labie próba na sucho wykryła np. podwójne wpisy w `/etc/hosts` – zanim cokolwiek zmieniono.

## 16. Jak czytać wynik

```
TASK [common : Ustaw nazwę hosta] ******************
ok: [k3s-master]
changed: [k3s-worker-1]

PLAY RECAP *****************************************
k3s-master   : ok=16  changed=7  unreachable=0  failed=0  skipped=2  rescued=0  ignored=0
```

| Stan | Kolor | Znaczenie |
|---|---|---|
| `ok` | zielony | stan był już poprawny, nic nie zmieniono |
| `changed` | żółty | Ansible coś zmienił (w `--check`: zmieniłby) |
| `skipping` | niebieski | warunek `when` niespełniony – zadanie nie dotyczy tej maszyny |
| `failed` | czerwony | zadanie się nie udało – na tej maszynie dalsze zadania są przerywane |
| `unreachable` | czerwony | brak połączenia SSH lub nie udało się przejść na roota |
| `rescued` / `ignored` | – | błąd obsłużony (`rescue`) / zignorowany (`ignore_errors`) |

`TASK [common : ...]` – nazwa roli przed dwukropkiem, opis zadania po nim.
Więcej szczegółów: `-v`, `-vv`, `-vvv` (im więcej `v`, tym więcej informacji, przy `-vvv` także
polecenia SSH).

## 17. ansible.cfg

Plik konfiguracji czytany z **bieżącego katalogu** – dlatego polecenia uruchamiasz w `ansible/`.
Nasz `ansible/ansible.cfg`:

| Ustawienie | Po co |
|---|---|
| `inventory = inventory.ini` | nie trzeba pisać `-i inventory.ini` |
| `roles_path = roles` | gdzie szukać ról |
| `result_format = yaml` | czytelniejszy wynik |
| `interpreter_python = auto_silent` | sam znajdź Pythona, bez ostrzeżeń |
| `host_key_checking = True` | sprawdzaj klucze hostów w `~/.ssh/known_hosts` |
| `pipelining = True` | mniej połączeń SSH na zadanie – szybciej |
| `ssh_args = ... StrictHostKeyChecking=accept-new` | nową maszynę dopisz do `known_hosts`, zmieniony klucz odrzuć |
| `become_exe = sudo.ws` | klasyczne sudo zamiast sudo-rs |

Podgląd efektywnej konfiguracji: `ansible-config dump --only-changed`.

## 18. Narzędzia wokół Ansible

| Narzędzie | Do czego |
|---|---|
| `ansible` | polecenia ad-hoc |
| `ansible-playbook` | uruchamianie playbooków |
| `ansible-galaxy` | instalacja kolekcji i ról |
| `ansible-doc` | dokumentacja modułów offline |
| `ansible-inventory` | podgląd inventory |
| `ansible-config` | podgląd konfiguracji |
| `ansible-vault` | szyfrowanie sekretów w plikach (hasła w repo) |
| `ansible-lint` | kontrola jakości kodu |
| `pipx` | instalacja Ansible w izolowanym środowisku |

Instalacja i działanie pipx, kolekcji i ansible-lint:
[docs/06 – Narzędzia](06-ansible.md#narzędzia-pipx-kolekcje-i-ansible-lint).

## 19. Ansible na tle innych narzędzi

| Narzędzie | Kategoria | Co robi w tym labie / mógłby robić |
|---|---|---|
| **Packer** | budowanie obrazów | instaluje system z ISO → gotowa maszyna lub szablon |
| **Terraform** | tworzenie infrastruktury | tworzy maszyny, sieci, dyski (chmura, vSphere, Proxmox) |
| **Ansible** | zarządzanie konfiguracją | konfiguruje to, co już istnieje: pakiety, pliki, usługi |
| **Helm / kubectl** | aplikacje w Kubernetesie | monitoring i aplikacja demo w klastrze |

Typowy łańcuch: **Packer** buduje obraz → **Terraform** tworzy z niego maszyny → **Ansible**
je konfiguruje → **Helm** wdraża aplikacje do klastra.

Ansible jest **proceduralny w kolejności** (zadania idą po kolei), ale **deklaratywny w zadaniu**
(opisujesz stan, moduł dba o resztę). Terraform jest w pełni deklaratywny i pamięta stan
infrastruktury w pliku `terraform.tfstate`; Ansible stanu nie przechowuje – za każdym razem
sprawdza maszyny na żywo.

## 20. Mapa tego repozytorium

```
ansible/
├── ansible.cfg                  # konfiguracja (rozdz. 17)
├── inventory.ini.example        # wzór listy maszyn (rozdz. 3) → kopiujesz do inventory.ini
├── inventory-bootstrap.ini.example  # inventory dla świeżych klonów (adresy z DHCP)
├── requirements.yml             # potrzebne kolekcje (rozdz. 4)
├── group_vars/all.yml           # wspólne zmienne (rozdz. 8)
├── site.yml                     # całe lab: prepare.yml + k3s.yml
├── playbooks/
│   ├── bootstrap.yml            # klony → unikalne maszyny ze stałym IP
│   ├── prepare.yml              # rola common na wszystkich maszynach
│   └── k3s.yml                  # master → workery → kontrola klastra
└── roles/                       # rozdz. 7
    ├── bootstrap/
    ├── common/
    ├── k3s_server/
    └── k3s_agent/
```

Przepływ `ansible-playbook site.yml`:

```
prepare.yml  ─▶  wszystkie maszyny: rola common (hosts, swap, SSH, ufw)
k3s.yml      ─▶  k3s-master: instalacja k3s, czekanie na API, odczyt tokenu (set_fact)
             ─▶  workery: instalacja k3s-agent z tokenem z hostvars mastera
             ─▶  k3s-master: czekanie na Ready wszystkich węzłów, etykiety worker, lista węzłów
```

Po zakończeniu stan klastra sprawdzasz z Windowsa:

```powershell
ssh -t k3s-master "sudo k3s kubectl get nodes -o wide"
```

| Część | Znaczenie |
|---|---|
| `ssh -t k3s-master` | połącz się z masterem; `-t` daje terminal, żeby `sudo` mogło zapytać o hasło |
| `sudo k3s kubectl` | `kubectl` wbudowany w k3s; plik dostępu do klastra czyta root |
| `get nodes` | lista węzłów klastra |
| `-o wide` | dodatkowe kolumny: adres IP, system, wersja jądra, środowisko kontenerów |

Wszystkie węzły powinny mieć `STATUS` = `Ready`.

## 21. Ściągawka poleceń

```bash
# Połączenie i zmienne
ansible all -m ping
ansible all -m debug -a 'msg="{{ admin_cidr }} {{ iface }}"'
ansible-inventory --graph

# Kontrola przed uruchomieniem
ansible-lint site.yml playbooks roles
ansible-playbook site.yml --syntax-check
ansible-playbook playbooks/prepare.yml --check --diff --ask-become-pass

# Uruchamianie
ansible-playbook site.yml --ask-become-pass
ansible-playbook site.yml --ask-become-pass --limit k3s-worker-1   # tylko jedna maszyna
ansible-playbook site.yml --ask-become-pass --start-at-task "Nadaj workerom rolę worker"
ansible-playbook site.yml --list-tasks                              # jakie zadania się wykonają
ansible-playbook site.yml --ask-become-pass -vv                     # więcej szczegółów

# Dokumentacja
ansible-doc ansible.builtin.lineinfile
ansible-galaxy collection list
```

## Dalej

- Praktyka krok po kroku: [docs/06-ansible.md](06-ansible.md) i Etap 2 w [przewodniku](00-przewodnik.md).
- Problemy, które wystąpiły przy pracy z Ansible: [docs/08-problemy-administratora.md](08-problemy-administratora.md#automatyzacja-skrypty-i-ansible).
- Oficjalna dokumentacja: <https://docs.ansible.com/>.
