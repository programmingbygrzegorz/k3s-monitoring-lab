# Narzędzia pomocnicze

Skrypty, którymi sprawdzana jest dokumentacja i robione są zrzuty do ćwiczeń. Uruchamiaj je
z **katalogu repozytorium**, w Git Bash na Windowsie. Potrzebne: Node.js 22+ (wbudowany
`fetch` i `WebSocket`) i Microsoft Edge. Skrypty z `monitoring/` potrzebują jeszcze
`ssh k3s-master` działającego kluczem.

| Skrypt | Do czego | Przykład |
|---|---|---|
| [check-links.mjs](check-links.mjs) | szuka martwych odnośników i kotwic we wszystkich plikach `.md`; kod wyjścia 1 przy błędach | `node tools/check-links.mjs` |
| [cdpshot.mjs](cdpshot.mjs) | zrzut strony przez Edge bez okna; czeka, aż wykresy się narysują | `node tools/cdpshot.mjs up.png "http://192.168.180.51:30090/query?g0.expr=up&g0.tab=graph"` |
| [terminal-shot.sh](terminal-shot.sh) | zamienia wynik poleceń (plik `.txt`) na obrazek okna terminala | `tools/terminal-shot.sh wezly.png "Węzły" nodes.txt` |
| [monitoring/alert-lifecycle.sh](monitoring/alert-lifecycle.sh) | poziom 6 ćwiczeń z monitoringu: podinfo → 0 replik, alert pending → firing, zrzuty | `tools/monitoring/alert-lifecycle.sh` |
| [monitoring/silence-demo.sh](monitoring/silence-demo.sh) | poziom 7: wyciszenie przez API Alertmanagera, zrzuty, przywrócenie podinfo | `tools/monitoring/silence-demo.sh` |

Symulator ServiceMonitor (strona do nauki, otwierasz w przeglądarce) jest przy Etapie 3:
[docs/etap-3-monitoring/07-symulator-servicemonitor.html](../docs/etap-3-monitoring/07-symulator-servicemonitor.html).

## Dlaczego DevTools Protocol, a nie `msedge --screenshot`

`msedge --headless --screenshot=plik.png <url>` wystarcza dla stron, które rysują się od razu
(tabele). Wykresy Prometheusa pojawiają się dopiero po pobraniu danych, a `--screenshot` robi
zdjęcie za wcześnie – wykres jest pusty. Nowsze wersje Edge (stan na 31.10.2026) w ogóle kończą
`--screenshot` od razu i nic nie zapisują, dlatego `terminal-shot.sh` też korzysta z
`cdpshot.mjs`. `cdpshot.mjs` uruchamia Edge z portem debugowania,
otwiera stronę, czeka kilka sekund naprawdę i dopiero wtedy prosi o zrzut. Na tym samym
mechanizmie działają Playwright i Puppeteer – narzędzia do testów przez przeglądarkę w CI/CD.

Strony z logowaniem (Grafana) nie przejdą przez te skrypty – zrzuty Grafany w Etapie 3 powstały
w przeglądarce, w której właściciel labu był zalogowany.

## Kiedy uruchamiać check-links

Po każdej zmianie nazw plików, przeniesieniu dokumentu albo zmianie nagłówka (kotwica `#…`
powstaje z treści nagłówka). Skrypt pomija bloki kodu, więc `](…)` w poleceniach nie jest
brany za odnośnik.
