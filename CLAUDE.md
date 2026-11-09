# CLAUDE.md – kontekst projektu dla Claude Code

Ten plik Claude Code czyta automatycznie na początku każdej sesji. Dzięki niemu na nowym komputerze
praca rusza od razu: po `git clone` i uruchomieniu Claude w katalogu repozytorium.
**Sekcję „Stan labu” aktualizuj po każdym zakończonym etapie.**

## Czym jest projekt

Domowe laboratorium do nauki administracji Linux/Kubernetes i portfolio do szukania pracy
(junior DevOps / administrator). Klaster k3s na maszynach VMware, monitoring (Prometheus,
Alertmanager, Grafana), automatyzacja (Ansible, Packer), dalej CI/CD, AIOps i bezpieczeństwo.
Repozytorium jest **publiczne**: https://github.com/programmingbygrzegorz/k3s-monitoring-lab

Właściciel uczy się od zera: pierwszy raz z Kubernetesem i Helmem. Robi wszystko **ręcznie,
krok po kroku**, a każde polecenie ma być wyjaśnione. Komunikacja **po polsku**.

## Środowisko

- Host: Windows 11, VMware Workstation, 64 GB RAM, i7-14700KF. Sieć VMnet8 (NAT) `192.168.180.0/24`.
- Maszyny (Ubuntu 26.04, logowanie kluczem `~/.ssh/k3s-lab`, aliasy w `~/.ssh/config` na Windowsie):

  | Maszyna | IP | Rola |
  |---|---|---|
  | k3s-master | .51 | control plane (taint NoSchedule) |
  | k3s-worker-1 / -2 / -3 | .52 / .53 / .55 | workery (worker-3 zbudowany Packerem) |
  | monitoring | .54 | węzeł sterujący Ansible, w Etapie 4 – Grafana i Uptime Kuma w Dockerze |
  | gitlab / security / kali | .56 / .57 / .58 | planowane (Etapy 7, 9b, 9c) |

- Adresy w klastrze: Prometheus `:30090`, Alertmanager `:30093`, Headlamp `:30400` (token), Grafana `:30300` (login `admin`,
  hasło: `grep GRAFANA_ADMIN_PASSWORD ~/k3s-monitoring-lab/lab.env` na masterze).
- Sekrety są w `lab.env` (na maszynach, poza gitem) i w Ansible Vault na `monitoring`.
  **Nigdy nie wpisuj haseł do formularzy logowania** – logowanie robi właściciel, np. w panelu
  przeglądarki obok czatu (poszerz panel do ok. 1200 px, inaczej zrzuty wyjdą malutkie).
- Snapshoty i włączanie maszyn robi właściciel.

## Stan labu (aktualizuj!)

Stan na 05.11.2026:

- ✅ Etap 0 (sieć, maszyny, Packer), 0b (klucze SSH), 1 (przygotowanie systemu),
  2 (k3s przez Ansible + Vault), 3 (kube-prometheus-stack 92.16.1 przez Helm, podinfo, reguły).
- ⚠️ Ćwiczenia z kubectl (Etap 2) i z monitoringu (Etap 3) wykonał Claude ze zrzutami. Właściciel
  ma je przejść sam – kubectl był w trakcie 31.10.
- ⚠️ GitHub Actions (`.github/workflows/lint.yml`) **nie uruchamia się od 28.10** – „account is
  locked due to a billing issue”. Wszystkie przebiegi czerwone bez wykonania kroku. Właściciel
  musi to wyjaśnić w GitHub → Settings → Billing. 2.11 wyłączenie limitu budżetu Actions NIE pomogło
  (przebieg b304583 nadal zablokowany) – następny krok: zgłoszenie na support.github.com. Do tego czasu ShellCheck, yamllint
  i ansible-lint nie są sprawdzane automatycznie.
- 🧱 03.11 – rozdziały „własny obraz” (Etap 4: `02-wlasny-obraz.md`, ćwiczenia 03/04) i „typowe
  awarie Kubernetesa” (Etap 5: `02-…`, manifest `kubernetes/awarie/zepsute.yaml`).
  `insecure-registries` jest zablokowane przez tryb auto (osłabienie TLS) – stąd własne CA.
- 🐳 05.11 – **Pełny reset zrobiony, właściciel postawił wszystko sam** (opis z wynikami:
  `docs/etap-4-monitoring-zewnetrzny/05-przebieg-wdrozenia.md`): snapshot `monitoring` przywrócony,
  Docker od nowa (grupa `docker`), obraz `hello-lab:1.0` bez roota (`~/hello-lab` na `monitoring`),
  nowe CA labu w `~/rejestr-certs` (poza gitem), rejestr `registry:3` z TLS na `192.168.180.54:5000`
  (wolumen `rejestr-dane`; do kontenera **tylko** `registry.crt` + `registry.key`, nie `ca.key`),
  `ca.crt` w `/etc/docker/certs.d/…`, na 4 węzłach `/etc/rancher/k3s/lab-ca.crt` + `registries.yaml`.
  W rejestrze `app:1.0.0` (z kopii `~/kopia-app-1.0.0.tar`, digest `159255640ed6…` = pod `default/app`)
  i `hello-lab:1.0` (`f0d8d97…`). Namespace `hello-lab` wdrożony (2 pody, NodePort 30880).
  Ćwiczenia z obrazu: zrobione poziomy 0, 1, 3, 5, 6, 7; **pominięte 2, 4, 8**.
- 💾 03.11 – trwałe dyski `local-path` **wdrożone** (właściciel, helm rewizja 2): PVC Prometheusa
  (10Gi) na worker-2, Grafany (2Gi) i Alertmanagera (1Gi) na worker-1 – te pody startują już tylko
  na tych węzłach. Test z kroku 7 (`08-trwale-dane.md`) wykonał Claude: wszystkie dane przetrwały.
- 🔦 03.11 – **Headlamp 0.46.0 zainstalowany przez właściciela** (Etap 6 rozpoczęty wcześniej): namespace
  `headlamp`, NodePort `:30400`, logowanie tokenem `kubectl create token headlamp -n headlamp --duration=…`
  (konto z `cluster-admin`). Ustawienia przez `--set`, bez pliku values. Opis: `docs/etap-6-gui/01-headlamp.md`.
- 💓 05.11 – **healthchecks.io podpięte**: konto właściciela, check `My First Check` (e-mail), prawdziwy
  `HEALTHCHECKS_URL` w `lab.env` na masterze i na `monitoring`, `helm upgrade` → rewizja 3. Period 2 min / Grace
  5 min ustawione dopiero **09.11** (wcześniej domyślne 1 dzień / 1 h); pingi potwierdzone zrzutem 09.11.
  Snapshoty wszystkich 5 maszyn: „2026-11-05 Etap4 rejestr+healthchecks”.
- 📊 05.11 wieczorem – **Grafana 11.4 i Uptime Kuma 2 w Dockerze na `monitoring`** (właściciel; `.env` 600,
  baza Kumy SQLite, monitor hello-lab). Grafana bez dashboardów. Monitor TCP 6443 czerwony – rola `common` otwiera
  6443 tylko dla `admin_cidr`; na masterze ręcznie `ufw allow from 192.168.180.54 to any port 6443` (drift!).
  Potem zawiesił się host (RCU stall na masterze, twarde wyłączenie PC), worker-3 nie startował przez stare
  blokady `*.lck` – przeniesione do `stare-lck-2026-11-05`. 06.11: wszystkie 5 maszyn działa, reguła 6443 przetrwała, wszystkie adresy monitorów Kumy odpowiadają z `monitoring`. 09.11: w Kumie 6 monitorów, wszystkie zielone (zrzut w przebiegu).
- 🔥 06.11 – **reguła 6443 dla `monitoring` w roli `common`** (właściciel, commit `c903998`, `loop` z `admin_cidr`
  i `192.168.180.54` na sztywno; wariant z inwentarza opisany w kroku 9 przebiegu). Przebieg na masterze
  (`--start-at-task`) `--check` i naprawdę: `changed=0` – drift usunięty.
- ⏭️ Następny: powiadomienia e-mail w Kumie, dashboard 1860 w Grafanie, test awarii (wyłączenie worker-1,
  potem całego klastra → e-mail z healthchecks.io po ~7 min), zamknięcie Etapu 4.
  Zawieszenie hosta: 8 razy w 30 dni, mikrokod 0x129 – właściciel aktualizuje BIOS MSI (problemy Etapu 0). Prowadź krok po kroku: podajesz polecenie,
  właściciel wykonuje i wkleja wynik; plików konfiguracyjnych w repo nie edytujesz.
- Potem: Etap 5 (scenariusze awarii; po nim właściciel zaczyna wysyłać CV), 6 (GUI: Headlamp,
  Portainer, Semaphore), 7 (GitLab, Trivy, Argo CD), 8 (AIOps), 9/9b/9c (kube-bench, Falco,
  Kyverno, Wazuh, ataki z Kali tylko na maszyny labu .51–.58).

## Układ dokumentacji

- `docs/00-przewodnik.md` – główna ścieżka: wszystkie kroki po kolei, mapa etapów, plany.
- `docs/etap-N-nazwa/` – **wszystko o danym etapie w jego folderze**: `README.md` (spis
  i kolejność czytania), pliki `01-…`, `02-…` (instrukcja, teoria, ćwiczenia, rozwiązania)
  i `problemy.md`. Zrzuty w `img/` folderu etapu.
- `docs/problemy-ogolne.md` – metoda diagnozowania i spis problemów według etapów.
- Ćwiczenia: osobno zadania (`0X-cwiczenia-….md`: cel, kroki, „Co powinieneś zobaczyć”,
  „Sprawdź się”) i rozwiązania (`0Y-…-rozwiazania.md`: wykonanie ze zrzutami i odpowiedzi).

## Zasady pracy

1. **Dokumentuj na bieżąco i wypychaj bez pytania.** Po każdym kroku labu, który wnosi coś nowego
   (pojęcie, polecenie, prawdziwy wynik, problem), dopisz to do folderu właściwego etapu – razem
   z pytaniami rekrutacyjnymi – i zrób commit + push na `main`.
2. **Nowa wiedza trafia do etapu, w którym się pojawia** (Ansible przy Ansible, Packer przy
   Etapie 0), nie do osobnych plików na końcu. Nowy etap = nowy folder z `README.md`
   i `problemy.md`; zaktualizuj też mapę w przewodniku i tabelę w `README.md`.
3. **Pliki prywatne nigdy w gicie:** `docs/dziennik-wdrozenia.md` (dziennik) i
   `docs/rozmowa-po-angielsku.md` (pytania po angielsku). Są wykluczone w `.git/info/exclude`
   – ten plik nie przechodzi przez `git clone`, więc na nowym komputerze najpierw dopisz do niego
   obie ścieżki. Pliki dodawaj do commita **po nazwie**, nigdy `git add -A` ani `git add docs/`.
4. Wyjaśniaj każde polecenie: co robi, gdzie je wpisać (🪟 Windows / 🐧 maszyna), czego się
   spodziewać. Prawdziwe wyniki z labu wpisuj do dokumentacji.
5. Po zmianach w dokumentacji uruchom `node tools/check-links.mjs` (martwe odnośniki i kotwice).
   Zrzuty do ćwiczeń: `tools/cdpshot.mjs` (strony) i `tools/terminal-shot.sh` (terminal) – opis
   w `tools/README.md`.
6. **Autorem commitów jest tylko właściciel.** Nie dopisuj `Co-Authored-By` ani innych oznaczeń
   Claude/AI w commitach i opisach PR (decyzja 05.11.2026).
7. Powtarzalne procedury są w skillach (`.claude/skills/`): `/nowy-etap` – folder etapu
   i wpisy w mapach, `/zamknij-etap` – dokumentacja, „Stan labu”, odnośniki, commit i push.
