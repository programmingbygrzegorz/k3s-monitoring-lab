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
| 6 | [06-certyfikaty-gdzie-jaki-klucz.md](06-certyfikaty-gdzie-jaki-klucz.md) | certyfikaty z diagramami: który plik jest czym, gdzie leży, kto go używa, co się dzieje przy `docker push`, porównanie z prawdziwym urzędem (Certum by Asseco), pytania rekrutacyjne |
| 7 | [07-diagnoza-wezla-journalctl.md](07-diagnoza-wezla-journalctl.md) | diagnoza padniętego węzła krok po kroku i `journalctl` w praktyce: lista uruchomień, czyste wyłączenie a awaria, logi k3s, błędy, śledztwo z obrazem Headlampa, ćwiczenia |
| – | [problemy.md](problemy.md) | problemy z tego etapu: rejestr bez TLS, `x509 unknown authority`, brak katalogu na workerach, `.dockerignore` |

Pliki do ćwiczeń: [apps/hello-lab/](../../apps/hello-lab/) (aplikacja, `Dockerfile`,
`.dockerignore`, `k3s-registries.yaml`) i [kubernetes/hello-lab/](../../kubernetes/hello-lab/hello-lab.yaml).

Stan na 05.11.2026: po pełnym resecie Docker, CA labu, rejestr `192.168.180.54:5000` z TLS
i zaufanie węzłów k3s są postawione od zera ([przebieg](05-przebieg-wdrozenia.md)). Docker jest
już na `monitoring`, więc `06-setup-monitoring-vm.sh` pominie instalację. Kroki Grafany i Uptime Kumy w przewodniku zostaną dopisane po przejściu etapu.

Następny etap: [Etap 5 – scenariusze awarii](../etap-5-scenariusze-awarii/README.md).
