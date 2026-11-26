# Etap 7 – CI/CD: GitLab, Runner, pipeline (i 7b – AppSec)

Co powstaje: własny GitLab CE na maszynie `gitlab`, GitLab Runner i pipeline, który buduje obraz
`hello-lab`, a w Etapie 7b sprawdza go narzędziami bezpieczeństwa (gitleaks, Semgrep, Trivy, OWASP ZAP).
Plan etapu: [przewodnik](../00-przewodnik.md#etapy-6-i-7--plan).

**Stan na 26.11.2026:** maszyna `gitlab` zbudowana Packerem, GitLab CE 19.6.1 zainstalowany i zabezpieczony,
konto `grzegorz`, projekt `lab/hello-lab` z kodem aplikacji, GitLab Runner 19.6.1 (executor `docker`) na `monitoring`
pipeline: test → build (obraz z każdego commita w rejestrze labu) → security (gitleaks, Semgrep, Trivy jako security gate).
Obraz `hello-lab:8480121a` – 0 podatności HIGH/CRITICAL. Następny krok: wdrożenie nowego obrazu w k3s (CD).

```
① Ty (Windows) ── packer build ──▶ ② VM gitlab (.56) ── apt install gitlab-ce ──▶ ③ GitLab w przeglądarce
                                                                                        │
          ⑥ obraz w rejestrze, wdrożenie na k3s ◀── ⑤ pipeline (.gitlab-ci.yml) ◀── ④ Runner na monitoring
```

| Co | Gdzie | Adres |
|---|---|---|
| maszyna `gitlab` | VMware, 4 CPU, 8 GB RAM, 60 GB dysku, Ubuntu 26.04 | `192.168.180.56`, `ssh gitlab` |
| GitLab CE | pakiet Omnibus `gitlab-ce` | `http://192.168.180.56` |
| GitLab Runner `monitoring-docker` | pakiet `gitlab-runner` na `monitoring`, executor `docker` | `192.168.180.54` |

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-maszyna-gitlab.md](01-maszyna-gitlab.md) | maszyna `gitlab` z Packera, alias SSH, snapshot, instalacja `gitlab-ce`, zabezpieczenie po instalacji (rejestracja, Web IDE, hasło roota), konto `grzegorz`, osobny klucz SSH do gita, kod `hello-lab` w GitLabie, Auto DevOps |
| 2 | [02-gitlab-runner.md](02-gitlab-runner.md) | repozytorium pakietów Runnera (co robi skrypt), instalacja, utworzenie Runnera w GitLabie (token `glrt-`), rejestracja z `sudo`, `config.toml`, pierwszy `.gitlab-ci.yml` |
| 3 | [03-skanery-bezpieczenstwa.md](03-skanery-bezpieczenstwa.md) | **Etap 7b:** gitleaks (sekrety w historii gita), Semgrep (SAST), Trivy – skanery w pipeline |
| 4 | [04-budowanie-obrazu-i-security-gate.md](04-budowanie-obrazu-i-security-gate.md) | `docker.sock` dla Runnera (i ryzyko), zadanie `build` – obraz z każdego commita w rejestrze labu, Etap 4 a Etap 7, triage Trivy, prawa 666 przez `umask 0000`, łatki w `Dockerfile` (0 podatności), `docker history`, security gate `--exit-code 1` |
| – | [problemy.md](problemy.md) | problemy z tego etapu: brak pluginu Packera, `Permission denied (publickey)` przy nowym aliasie |

Następny etap: Etap 8 – AIOps ([plan](../00-przewodnik.md#etap-8--plan)).
