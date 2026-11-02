# Etap 2 – ćwiczenie z Ansible: pakiet na wszystkich maszynach

Pierwsza własna zmiana w kodzie Ansible: instalujesz mały pakiet `tree` na wszystkich 5 maszynach,
sprawdzasz idempotentność, a potem pakiet usuwasz – też Ansiblem. Zrób to sam, potem porównaj
z [rozwiązaniem](09-cwiczenie-ansible-pakiet-rozwiazanie.md).

`tree` wypisuje zawartość katalogu jako drzewo. Jest mały (ok. 100 KB) i nie ma zależności,
więc nic nie zepsuje. Stan na 2.11.2026: nie ma go na żadnej maszynie.

**Gdzie co wpisujesz:** 🪟 Windows – edycja plików w repozytorium i `git push` (Git Bash
w `C:\Projekty\k3s-monitoring-lab`); 🐧 `monitoring` – `git pull` i polecenia `ansible`
(po `ssh monitoring`, w katalogu `~/k3s-monitoring-lab/ansible`).

| Część | Co ćwiczysz |
|---|---|
| [A](#część-a--stan-przed-zmianą) | polecenie ad-hoc, odczyt stanu maszyn |
| [B](#część-b--instalacja-przez-rolę-common) | zmiana w roli, `--check --diff`, `--limit`, idempotentność |
| [C](#część-c--usunięcie-pakietu) | `state: absent` – usuwanie |
| [D](#część-d--sprzątanie-w-kodzie) | porządek w kodzie po usunięciu |

## Część A – stan przed zmianą

**Cel:** zobaczyć, że pakietu nie ma nigdzie, jednym poleceniem na 5 maszyn.

1. 🐧 Pobierz najnowszą wersję repozytorium: `cd ~/k3s-monitoring-lab && git pull`, potem `cd ansible`.
2. 🐧 Sprawdź, czy Ansible widzi wszystkie maszyny: `ansible all -m ping`.
3. 🐧 Sprawdź, czy `tree` jest zainstalowany: `ansible all -m command -a "which tree"`.

**Co powinieneś zobaczyć:** w kroku 2 – 5 × `SUCCESS` i `"ping": "pong"`. W kroku 3 – 5 × `FAILED`
z `rc=1`.

**Sprawdź się:**
- Czy `FAILED` w kroku 3 oznacza, że coś jest zepsute?
- Co znaczy `rc=1`?

## Część B – instalacja przez rolę `common`

**Cel:** zapisać pakiet w kodzie, sprawdzić zmianę na sucho, wdrożyć najpierw na jednej maszynie,
potem na wszystkich.

1. 🪟 W pliku [ansible/roles/common/tasks/main.yml](../../ansible/roles/common/tasks/main.yml)
   dopisz `tree` do listy w zadaniu „Zainstaluj potrzebne pakiety”. Uważaj na wcięcie – taki sam
   jak przy `- ufw`.
2. 🪟 Wyślij zmianę: `git add` tego pliku (po nazwie), `git commit`, `git push`.
3. 🐧 Pobierz ją na `monitoring`: `git pull`.
4. 🐧 Próba na sucho na wszystkich: `ansible-playbook playbooks/prepare.yml --check --diff`.
   Możesz też sprawdzić cały `site.yml` – przygotowanie systemu i k3s.
5. 🐧 Wdrożenie tylko na jednej maszynie: `ansible-playbook playbooks/prepare.yml --limit k3s-worker-1`.
   Tu celowo `prepare.yml`, nie `site.yml` – dlaczego? (odpowiedź w rozwiązaniu, krok 5)
6. 🐧 Sprawdź: `ansible all -m command -a "which tree"`.
7. 🐧 Wdrożenie na wszystkich: `ansible-playbook playbooks/prepare.yml`.
8. 🐧 Uruchom krok 7 **drugi raz** i porównaj `PLAY RECAP`.
9. 🐧 Wypróbuj pakiet: `ssh k3s-master "tree -L 1 /etc/rancher"`.

**Co powinieneś zobaczyć:**
- krok 4 – przy zadaniu „Zainstaluj potrzebne pakiety” `changed` na każdej maszynie
  i informacja, że zostanie zainstalowany `tree`; nic się jeszcze nie zainstalowało,
- krok 5 – `changed=1` (lub więcej) tylko dla `k3s-worker-1`, pozostałych maszyn nie ma w wyniku,
- krok 6 – `/usr/bin/tree` na `k3s-worker-1`, `FAILED` na pozostałych czterech,
- krok 7 – `changed` przy pakietach na czterech maszynach, `ok` na `k3s-worker-1`,
- krok 8 – przy pakietach wszędzie `ok`, w `PLAY RECAP` `changed=0`.

**Sprawdź się:**
- Dlaczego najpierw `--limit` na jednej maszynie, a nie od razu na wszystkich?
- Dlaczego w kroku 7 `k3s-worker-1` ma `ok`, a nie `changed`?
- Co udowadnia krok 8?
- Dlaczego zmieniasz plik na Windowsie i robisz `git pull`, a nie edytujesz go wprost na `monitoring`?

## Część C – usunięcie pakietu

**Cel:** usunąć `tree` ze wszystkich maszyn.

1. 🪟 Usuń linię `- tree` z listy pakietów w roli `common`. Wyślij zmianę i pobierz ją na `monitoring`.
2. 🐧 Uruchom `ansible-playbook playbooks/prepare.yml` i sprawdź `which tree` na wszystkich.
   Czy pakiet zniknął?
3. 🪟 Dopisz w roli `common`, zaraz pod zadaniem „Zainstaluj potrzebne pakiety”, nowe zadanie
   „Usuń niepotrzebne pakiety”: moduł `ansible.builtin.apt`, lista z `tree`, `state: absent`.
   Wyślij i pobierz.
4. 🐧 Próba na sucho, potem wdrożenie na wszystkich.
5. 🐧 Sprawdź `which tree` na wszystkich.
6. 🐧 Uruchom playbook drugi raz.

**Co powinieneś zobaczyć:**
- krok 2 – `tree` **nadal jest** na wszystkich maszynach, a playbook pokazuje `ok`,
- krok 4 – `changed` przy „Usuń niepotrzebne pakiety” na każdej maszynie,
- krok 5 – 5 × `FAILED`, `rc=1` – jak w części A,
- krok 6 – `changed=0`.

**Sprawdź się:**
- Dlaczego usunięcie linii z listy nie usunęło pakietu?
- Czym różnią się `state: present` i `state: absent`?

## Część D – sprzątanie w kodzie

**Cel:** zdecydować, co zostaje w kodzie po usunięciu pakietu.

1. Zastanów się: czy zadanie „Usuń niepotrzebne pakiety” ma zostać w roli na zawsze?
2. 🪟 Usuń je, wyślij i pobierz. Kod wraca do stanu sprzed ćwiczenia.
3. 🐧 Uruchom playbook jeszcze raz – `changed=0`, `tree` dalej nie ma.
4. 🪟 Sprawdź historię: `git log --oneline -5 -- ansible/roles/common/tasks/main.yml`.

**Co powinieneś zobaczyć:** cztery Twoje commity z tego ćwiczenia, a plik roli taki jak na początku.

**Sprawdź się:**
- Kiedy zadanie `state: absent` warto zostawić w kodzie, a kiedy usunąć?
- Jak w 30 sekund cofnąć cały kod roli do stanu sprzed ćwiczenia, gdybyś się pogubił?

## Pojęcia

| Pojęcie | Znaczenie |
|---|---|
| polecenie ad-hoc | `ansible <maszyny> -m <moduł> -a "<argumenty>"` – jedno zadanie bez playbooka |
| `state: present` / `absent` | pakiet ma być / ma go nie być |
| `--check --diff` | próba na sucho: co by się zmieniło, bez zmieniania |
| `--limit` | tylko wybrane maszyny albo grupy z inventory |
| idempotentność | drugie uruchomienie bez zmian daje `changed=0` |
| stan deklaratywny | Ansible pilnuje tego, co jest **zapisane**; nie usuwa tego, czego nie ma w kodzie |

## Ściągawka

| Polecenie | Co robi |
|---|---|
| `ansible all -m ping` | czy Ansible dosięga wszystkich maszyn |
| `ansible all -m command -a "which tree"` | czy program jest na każdej maszynie |
| `ansible-playbook playbooks/prepare.yml --check --diff` | próba na sucho |
| `ansible-playbook playbooks/prepare.yml --limit k3s-worker-1` | tylko jedna maszyna |
| `ansible-playbook playbooks/prepare.yml` | wdrożenie na wszystkich |

## Zdanie na rozmowę

> „Nowy pakiet dodaję w roli, a nie ręcznie na maszynach: zmiana przechodzi przez gita, sprawdzam ją
> `--check --diff`, wdrażam najpierw na jednej maszynie przez `--limit`, potem na wszystkich,
> a drugie uruchomienie musi dać `changed=0`. Usunięcie wymaga jawnego `state: absent` –
> Ansible nie usuwa tego, czego po prostu nie ma w kodzie.”
