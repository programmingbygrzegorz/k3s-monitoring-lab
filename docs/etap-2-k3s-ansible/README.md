# Etap 2 – klaster k3s przez Ansible

Co powstaje: Ansible na maszynie `monitoring` i klaster k3s (master + 3 workery), opcjonalnie
hasło sudo w Ansible Vault. Na koniec ćwiczysz pracę z klastrem w kubectl.

Polecenia krok po kroku: [przewodnik, kroki 15–25](../00-przewodnik.md#etap-2--klaster-k3s-przez-ansible).

## Etap 2 w pigułce – zacznij tutaj

**Maszyna `monitoring` steruje resztą.** Ansible łączy się po SSH z węzłami i wykonuje na nich
zadania z ról – Ty uruchamiasz jedno polecenie:

```
① Ty (na monitoring):  ansible-playbook site.yml --ask-become-pass
                            │
② site.yml:            ├── playbooks/prepare.yml → rola common (to samo co skrypt z Etapu 1)
                       └── playbooks/k3s.yml
                            │
③ Role po kolei:       k3s_server  → k3s na masterze, odczytuje token dołączenia
                       k3s_agent   → k3s na workerach, token podany automatycznie
                       czekanie    → aż wszystkie węzły są Ready, etykieta roli „worker”
                            │
④ Test:                sudo k3s kubectl get nodes -o wide  → 4 węzły Ready, snapshot „k3s-dziala”
```

**Co powstało:**

| Gdzie | Co | Po co |
|---|---|---|
| `monitoring` | Ansible (pipx), klucz `~/.ssh/ansible`, repozytorium | centrum sterowania |
| `k3s-master` | k3s server (API na porcie 6443) | „mózg” klastra: decyduje, gdzie działają pody |
| `k3s-worker-1/2/3` | k3s agent | uruchamiają pody |
| repozytorium | `inventory`, `roles/`, `playbooks/` | cała instalacja zapisana jako kod |

Klaster jest pusty – pierwsze własne obiekty tworzysz w ćwiczeniach z kubectl (pliki 05 i 06),
a w Etapie 3 instalujesz na nim monitoring.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-teoria-ansible.md](01-teoria-ansible.md) | teoria Ansible dla początkujących |
| 2 | [02-k3s-przez-ansible.md](02-k3s-przez-ansible.md) | inventory, role, playbooki, instalacja k3s |
| 3 | [03-ansible-vault.md](03-ansible-vault.md) | *(opcjonalnie)* hasło sudo zaszyfrowane w Vault |
| – | [04-k3s-skryptami.md](04-k3s-skryptami.md) | *(wariant)* ta sama instalacja skryptami, bez Ansible |
| 4 | [05-cwiczenia-kubectl.md](05-cwiczenia-kubectl.md) | **ćwiczenia** z kubectl, 8 poziomów – zrób je sam |
| 5 | [06-cwiczenia-kubectl-rozwiazania.md](06-cwiczenia-kubectl-rozwiazania.md) | **rozwiązania** ćwiczeń ze zrzutami – porównaj po wykonaniu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: sudo-rs, ansible-lint, zmienne |

Następny etap: [Etap 3 – monitoring w klastrze](../etap-3-monitoring/README.md).
