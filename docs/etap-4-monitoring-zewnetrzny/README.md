# Etap 4 – monitoring poza klastrem

Co powstaje: Grafana i Uptime Kuma na maszynie `monitoring`, sygnał „dead man's switch” do healthchecks.io.
Przy okazji Dockera na `monitoring`: własny obraz aplikacji, prywatny rejestr z TLS i wdrożenie
tego obrazu na k3s.

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-monitoring-zewnetrzny.md](01-monitoring-zewnetrzny.md) | dlaczego monitoring poza klastrem i jak go postawić |
| 2 | [02-wlasny-obraz.md](02-wlasny-obraz.md) | jak zbudować własny obraz: Dockerfile, warstwy, tagi, dobry obraz, rejestr z TLS i własnym CA, obraz na k3s, pytania rekrutacyjne |
| 3 | [03-cwiczenia-obraz.md](03-cwiczenia-obraz.md) | ćwiczenia: 8 poziomów od pierwszego kontenera do wdrożenia i wycofania na k3s |
| 4 | [04-cwiczenia-obraz-rozwiazania.md](04-cwiczenia-obraz-rozwiazania.md) | rozwiązania z prawdziwymi wynikami z labu i pełny reset |
| 5 | [05-przebieg-wdrozenia.md](05-przebieg-wdrozenia.md) | **przebieg prawdziwej sesji 05.11**: przywrócenie snapshotu, kopia obrazu `app`, reset, Docker i rejestr od zera, monitoring – polecenia i wyniki z labu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: rejestr bez TLS, `x509 unknown authority`, brak katalogu na workerach, `.dockerignore` |

Pliki do ćwiczeń: [apps/hello-lab/](../../apps/hello-lab/) (aplikacja, `Dockerfile`,
`.dockerignore`, `k3s-registries.yaml`) i [kubernetes/hello-lab/](../../kubernetes/hello-lab/hello-lab.yaml).

Stan na 03.11.2026: Docker jest już zainstalowany na `monitoring` (przy ćwiczeniach z obrazu),
więc `06-setup-monitoring-vm.sh` pominie instalację. Rejestr `192.168.180.54:5000` działa,
a węzły k3s mu ufają. Kroki Grafany i Uptime Kumy w przewodniku zostaną dopisane po przejściu etapu.

Następny etap: [Etap 5 – scenariusze awarii](../etap-5-scenariusze-awarii/README.md).
