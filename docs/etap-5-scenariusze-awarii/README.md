# Etap 5 – scenariusze awarii

Co powstaje: awarie węzłów i aplikacji wywoływane celowo, diagnoza w terminalu i w monitoringu,
własna reguła alertu.

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-scenariusze-awarii.md](01-scenariusze-awarii.md) | scenariusze awarii i ćwiczenie z własną regułą alertu |
| 2 | [02-typowe-awarie-kubernetesa.md](02-typowe-awarie-kubernetesa.md) | typowe problemy Kubernetesa: metoda diagnozy, mapa statusów i kodów wyjścia, 17 problemów (pytanie, polecenia, prawdziwy wynik, naprawa), ściągawka poleceń, pytania rekrutacyjne |
| – | [problemy.md](problemy.md) | problemy z tego etapu: literówka w poleceniu, brak `-n`, brak metryk poda w CrashLoopBackOff |

**Stan na 10.11.2026:** awaria węzła zrobiona w Etapie 4 ([test A i B](../etap-4-monitoring-zewnetrzny/05-przebieg-wdrozenia.md));
OOMKilled przerobiony i naprawiony ([przebieg](01-scenariusze-awarii.md#przebieg-w-labie-10112026)).
Dalej: CrashLoopBackOff, ImagePullBackOff, CPU, błędne wdrożenie, własna reguła alertu, `zepsute.yaml`.

Ćwiczenie z diagnozy: [kubernetes/awarie/zepsute.yaml](../../kubernetes/awarie/zepsute.yaml) –
11 celowo zepsutych obiektów do znalezienia i naprawienia.

Problemy i kroki w przewodniku zostaną dopisane po przejściu etapu.

Plany kolejnych etapów (6–9): [przewodnik](../00-przewodnik.md#mapa-etapów).
