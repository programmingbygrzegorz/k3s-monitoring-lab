# Etap 2 – klaster k3s przez Ansible

Co powstaje: Ansible na maszynie `monitoring` i klaster k3s (master + 3 workery), opcjonalnie
hasło sudo w Ansible Vault. Na koniec ćwiczysz pracę z klastrem w kubectl.

Polecenia krok po kroku: [przewodnik, kroki 15–25](../00-przewodnik.md#etap-2--klaster-k3s-przez-ansible).

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
