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

- Adresy w klastrze: Prometheus `:30090`, Alertmanager `:30093`, Grafana `:30300` (login `admin`,
  hasło: `grep GRAFANA_ADMIN_PASSWORD ~/k3s-monitoring-lab/lab.env` na masterze).
- Sekrety są w `lab.env` (na maszynach, poza gitem) i w Ansible Vault na `monitoring`.
  **Nigdy nie wpisuj haseł do formularzy logowania** – logowanie robi właściciel, np. w panelu
  przeglądarki obok czatu (poszerz panel do ok. 1200 px, inaczej zrzuty wyjdą malutkie).
- Snapshoty i włączanie maszyn robi właściciel.

## Stan labu (aktualizuj!)

Stan na 31.10.2026:

- ✅ Etap 0 (sieć, maszyny, Packer), 0b (klucze SSH), 1 (przygotowanie systemu),
  2 (k3s przez Ansible + Vault), 3 (kube-prometheus-stack 92.16.1 przez Helm, podinfo, reguły).
- ⚠️ Ćwiczenia z kubectl (Etap 2) i z monitoringu (Etap 3) wykonał Claude ze zrzutami. Właściciel
  ma je przejść sam – kubectl był w trakcie 31.10.
- ⏭️ Następny: **Etap 4** – konto healthchecks.io i prawdziwy `HEALTHCHECKS_URL` (do tego czasu
  świeci `AlertmanagerFailedToSendAlerts`), Grafana i Uptime Kuma na `monitoring`.
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
6. Powtarzalne procedury są w skillach (`.claude/skills/`): `/nowy-etap` – folder etapu
   i wpisy w mapach, `/zamknij-etap` – dokumentacja, „Stan labu”, odnośniki, commit i push.
