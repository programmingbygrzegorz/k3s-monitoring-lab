# Etap 6 – zarządzanie przez GUI

Co powstaje: panele WWW do labu – Headlamp (klaster k3s), Portainer (Docker na `monitoring`),
Semaphore UI (playbooki Ansible). Plan etapu: [przewodnik](../00-przewodnik.md#etapy-6-i-7--plan).

**Stan na 03.11.2026:** Headlamp zainstalowany (właściciel). Portainer i Semaphore – do zrobienia.

| Co | Gdzie | Adres |
|---|---|---|
| Headlamp 0.46.0 | namespace `headlamp`, chart `headlamp/headlamp` | `http://192.168.180.51:30400`, logowanie tokenem |

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-headlamp.md](01-headlamp.md) | Headlamp: instalacja Helmem, NodePort, token i jego ważność, ostrzeżenie readiness przy starcie, bezpieczeństwo, pytania rekrutacyjne |
| – | [problemy.md](problemy.md) | problemy z tego etapu |

Następny etap: Etap 7 – CI/CD i GitOps ([plan](../00-przewodnik.md#etapy-6-i-7--plan)).
