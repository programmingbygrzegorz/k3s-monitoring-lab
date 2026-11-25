# Etap 7 – CI/CD: GitLab, Runner, pipeline (i 7b – AppSec)

Co powstaje: własny GitLab CE na maszynie `gitlab`, GitLab Runner i pipeline, który buduje obraz
`hello-lab`, a w Etapie 7b sprawdza go narzędziami bezpieczeństwa (gitleaks, Semgrep, Trivy, OWASP ZAP).
Plan etapu: [przewodnik](../00-przewodnik.md#etapy-6-i-7--plan).

**Stan na 25.11.2026:** maszyna `gitlab` zbudowana Packerem, SSH działa, snapshot zrobiony,
instalacja GitLab CE w toku.

```
① Ty (Windows) ── packer build ──▶ ② VM gitlab (.56) ── apt install gitlab-ce ──▶ ③ GitLab w przeglądarce
                                                                                        │
          ⑥ obraz w rejestrze, wdrożenie na k3s ◀── ⑤ pipeline (.gitlab-ci.yml) ◀── ④ Runner na monitoring
```

| Co | Gdzie | Adres |
|---|---|---|
| maszyna `gitlab` | VMware, 4 CPU, 8 GB RAM, 60 GB dysku, Ubuntu 26.04 | `192.168.180.56`, `ssh gitlab` |
| GitLab CE | pakiet Omnibus `gitlab-ce` | `http://192.168.180.56` |

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-maszyna-gitlab.md](01-maszyna-gitlab.md) | maszyna `gitlab` z Packera (nowy plik parametrów, `packer init`, `validate`, `build`), dodanie do VMware, alias SSH, snapshot, repozytorium pakietów GitLaba, instalacja `gitlab-ce` |
| – | [problemy.md](problemy.md) | problemy z tego etapu: brak pluginu Packera, `Permission denied (publickey)` przy nowym aliasie |

Następny etap: Etap 8 – AIOps ([plan](../00-przewodnik.md#etap-8--plan)).
