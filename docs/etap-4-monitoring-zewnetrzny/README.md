# Etap 4 – monitoring poza klastrem

Co powstaje: Grafana i Uptime Kuma na maszynie `monitoring`, sygnał „dead man's switch” do healthchecks.io.
Przy okazji Dockera na `monitoring`: własny obraz aplikacji, prywatny rejestr z TLS i wdrożenie
tego obrazu na k3s.

## Etap 4 w pigułce – zacznij tutaj

**Monitoring, który przeżyje awarię klastra.** Prometheus w k3s nie zgłosi własnej śmierci – dlatego część
nadzoru stoi **poza klastrem**: na maszynie `monitoring` i w internecie.

```
☸️ k3s:        Prometheus ── alert Watchdog (zawsze aktywny) ──▶ Alertmanager ──┬─ co 1 min ping ──▶ ☁️ healthchecks.io
                                                                                └─ critical ──▶ 📧 e-mail (Gmail SMTP)
🐳 monitoring: Uptime Kuma ── co 60 s sprawdza z zewnątrz ──▶ hello-lab, Prometheus, API k3s :6443 … ──▶ 📧 e-mail
               Grafana     ── dashboard 1860 (Node Exporter Full) z Prometheusa w k3s
               rejestr     ── registry:3 z TLS (własne CA labu) ──▶ węzły k3s pobierają obraz hello-lab
```

Klaster padł → pingi ustają → **healthchecks.io** po Period 2 min + Grace 5 min wysyła e-mail „DOWN”.
Tego nie da się zrobić od środka – „strażnik” alarmuje o **ciszy** (*dead man's switch*).

**Co działa (sprawdzone 26.11.2026):**

| Element | Gdzie | Stan |
|---|---|---|
| Grafana 11.4 | `monitoring` `:3000` (Docker, wolumen `monitoring-vm_grafana-data`) | ✅ `/api/health` 200, dashboard 1860 |
| Uptime Kuma 2 | `monitoring` `:3001` (SQLite w wolumenie) | ✅ healthy, 6 monitorów, e-mail |
| rejestr `registry:3` | `192.168.180.54:5000`, TLS z CA labu (`~/rejestr-certs`, poza gitem) | ✅ obrazy `app`, `hello-lab` |
| healthchecks.io | check z Period 2 min / Grace 5 min, ping od Alertmanagera | ✅ e-mail `DOWN` w teście awarii B |
| e-mail z Alertmanagera | tylko `severity=critical`, helm rewizja 4 | ✅ FIRING i RESOLVED (`NodeDiskCritical`, Etap 5) |
| `hello-lab` w k3s | 2 pody, NodePort `30880`, obraz z własnego rejestru | ✅ od 26.11 obraz `d6b0d4f6` z pipeline'u (Etap 7) |

**Czego się nauczyłem** – najważniejsze wnioski z testów:

- **Test A (worker-3 wyłączony):** NotReady po ~70 s, burza ~9 alertów po 15 min – a wszystkie szły do odbiorcy
  `null`, więc nikt by się nie dowiedział. Stąd e-mail tylko dla `critical` (krok 13).
- **Test B (worker-1 wyłączony):** Alertmanager i Grafana w klastrze padły razem z węzłem (dyski `local-path`
  przypięte do worker-1); zadziałał tylko zewnętrzny strażnik – e-mail z healthchecks.io. Monitoring poza
  klastrem nie jest dodatkiem.
- **Drift:** reguła `ufw` dodana ręcznie na serwerze zniknęłaby przy następnym Ansible – przeniesiona do roli
  `common` (`changed=0`).
- **Własny obraz i CA:** obraz bez roota, rejestr z TLS zamiast `insecure-registries`, do kontenera rejestru
  tylko `registry.crt` + `registry.key` (nigdy `ca.key`).

**Wyłączanie labu** (póki nie ma skryptu): healthchecks.io → check → **Pause**, potem *Shut Down Guest*:
workery → master → `monitoring`. Check wznawia się sam przy pierwszym pingu.

**Etap zamknięty 26.11.2026.** Świadomie pominięte / na później: poziomy ćwiczeń z obrazu 2, 4, 8; skrypt
„wyłącz lab” z pauzą healthchecks.io przez API; e-mail `UP` z healthchecks.io po teście B – niepotwierdzony.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-monitoring-zewnetrzny.md](01-monitoring-zewnetrzny.md) | dlaczego monitoring poza klastrem i jak go postawić |
| 2 | [02-wlasny-obraz.md](02-wlasny-obraz.md) | jak zbudować własny obraz: Dockerfile, warstwy, tagi, dobry obraz, rejestr z TLS i własnym CA, obraz na k3s, pytania rekrutacyjne |
| 3 | [03-cwiczenia-obraz.md](03-cwiczenia-obraz.md) | ćwiczenia: 8 poziomów od pierwszego kontenera do wdrożenia i wycofania na k3s |
| 4 | [04-cwiczenia-obraz-rozwiazania.md](04-cwiczenia-obraz-rozwiazania.md) | rozwiązania z prawdziwymi wynikami z labu i pełny reset |
| 5 | [05-przebieg-wdrozenia.md](05-przebieg-wdrozenia.md) | **przebieg prawdziwej sesji 05.11**: przywrócenie snapshotu, kopia obrazu `app`, reset, Docker i rejestr od zera, monitoring – polecenia i wyniki z labu |
| 6 | [06-certyfikaty-gdzie-jaki-klucz.md](06-certyfikaty-gdzie-jaki-klucz.md) | certyfikaty z diagramami: który plik jest czym, gdzie leży, kto go używa, co się dzieje przy `docker push`, porównanie z prawdziwym urzędem (Certum by Asseco), pytania rekrutacyjne |
| 7 | [07-diagnoza-wezla-journalctl.md](07-diagnoza-wezla-journalctl.md) | diagnoza padniętego węzła krok po kroku i `journalctl` w praktyce: lista uruchomień, czyste wyłączenie a awaria, logi k3s, błędy, śledztwo z obrazem Headlampa, ćwiczenia |
| – | [problemy.md](problemy.md) | problemy z tego etapu: rejestr bez TLS, `x509 unknown authority`, brak katalogu na workerach, `.dockerignore` |

Pliki do ćwiczeń: [apps/hello-lab/](../../apps/hello-lab/) (aplikacja, `Dockerfile`,
`.dockerignore`, `k3s-registries.yaml`) i [kubernetes/hello-lab/](../../kubernetes/hello-lab/hello-lab.yaml).

Cały przebieg etapu – od resetu 05.11 po e-mail z Alertmanagera 23.11 – z poleceniami i wynikami z labu:
[05-przebieg-wdrozenia.md](05-przebieg-wdrozenia.md) (kroki 1–13). Kroki w skrócie: [przewodnik](../00-przewodnik.md#etap-4--monitoring-poza-klastrem).

Następny etap: [Etap 5 – scenariusze awarii](../etap-5-scenariusze-awarii/README.md).
