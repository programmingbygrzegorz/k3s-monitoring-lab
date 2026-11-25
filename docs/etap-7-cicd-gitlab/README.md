# Etap 7 – CI/CD: GitLab, Runner, pipeline (i 7b – AppSec)

Co powstaje: własny GitLab CE na maszynie `gitlab`, GitLab Runner i pipeline, który buduje obraz
`hello-lab`, a w Etapie 7b sprawdza go narzędziami bezpieczeństwa (gitleaks, Semgrep, Trivy, OWASP ZAP).
Plan etapu: [przewodnik](../00-przewodnik.md#etapy-6-i-7--plan).

**Stan na 25.11.2026:** maszyna `gitlab` zbudowana Packerem, GitLab CE 19.6.1 zainstalowany i zabezpieczony,
konto `grzegorz`, projekt `lab/hello-lab` z kodem aplikacji. Następny krok: GitLab Runner na `monitoring`.

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
| 1 | [01-maszyna-gitlab.md](01-maszyna-gitlab.md) | maszyna `gitlab` z Packera, alias SSH, snapshot, instalacja `gitlab-ce`, zabezpieczenie po instalacji (rejestracja, Web IDE, hasło roota), konto `grzegorz`, osobny klucz SSH do gita, kod `hello-lab` w GitLabie, Auto DevOps |
| – | [problemy.md](problemy.md) | problemy z tego etapu: brak pluginu Packera, `Permission denied (publickey)` przy nowym aliasie |

Następny etap: Etap 8 – AIOps ([plan](../00-przewodnik.md#etap-8--plan)).
