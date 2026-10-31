# Etap 1 – przygotowanie systemu

Co powstaje: `/etc/hosts`, aktualizacje, wyłączony swap, SSH tylko kluczem i firewall na każdej maszynie.

Polecenia krok po kroku: [przewodnik, kroki 9–14](../00-przewodnik.md#etap-1--przygotowanie-systemu).
Skrypt: [scripts/00-prepare-node.sh](../../scripts/00-prepare-node.sh).

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-skrypt-prepare-node.md](01-skrypt-prepare-node.md) | co robi każda część skryptu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: sshd, uprawnienia, duplikaty |

Następny etap: [Etap 2 – klaster k3s przez Ansible](../etap-2-k3s-ansible/README.md).
