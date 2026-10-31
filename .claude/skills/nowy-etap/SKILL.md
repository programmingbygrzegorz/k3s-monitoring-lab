---
name: nowy-etap
description: Zakłada albo uzupełnia folder etapu labu (docs/etap-N-…/) – README z pigułką, problemy.md, wpisy w mapie przewodnika, w README.md i w problemy-ogolne.md. Użyj, gdy właściciel zaczyna nowy etap (np. „zaczynamy Etap 4”) albo gdy etap ma tylko szkic folderu.
---

# Nowy etap labu

Cel: osoba, która przechodzi lab po raz pierwszy, otwiera `docs/etap-N-…/README.md` i od razu
wie, co powstaje, jak i w jakiej kolejności czytać pliki. Wszystko po polsku.

## 1. Sprawdź, co już jest

- `ls docs/` – czy folder etapu istnieje (Etapy 4 i 5 mają już szkic: `README.md` + `01-…`).
- Przeczytaj w `docs/00-przewodnik.md`: „Mapa etapów” (tabela na górze) i plan etapu (sekcja
  `### Etap N – plan`, jeśli jest).
- Przeczytaj sekcję „Stan labu” w `CLAUDE.md`.

## 2. Folder etapu

Nazwa: `docs/etap-N-krotka-nazwa/` (małe litery, bez polskich znaków, myślniki).
Pliki numerowane w kolejności czytania: `01-…` instrukcja, potem teoria, `0X-cwiczenia-….md`
i `0Y-…-rozwiazania.md`. Zrzuty w `img/` tego folderu.

### `README.md` – wzór (jak w Etapach 0–3)

```markdown
# Etap N – nazwa

Co powstaje: jedno zdanie.

Polecenia krok po kroku: [przewodnik, kroki X–Y](../00-przewodnik.md#etap-n--nazwa).

## Etap N w pigułce – zacznij tutaj

**Jedno zdanie o idei etapu.** Krótkie rozwinięcie.

(schemat ASCII w bloku ```: ① Ty → ② narzędzie → ③ co powstaje → ④ test)

**Co powstało:** tabela (gdzie / co / po co) – prawdziwe nazwy, adresy, porty z labu.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-….md](01-….md) | … |
| – | [problemy.md](problemy.md) | problemy z tego etapu: … |

Następny etap: [Etap N+1 – nazwa](../etap-…/README.md).
```

Pigułkę piszesz **po** przejściu etapu (wtedy są prawdziwe wyniki). Na starcie wystarczy
nagłówek, „Co powstaje” i tabela plików.

### `problemy.md` – wzór

```markdown
# Etap N – nazwa – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Krótki tytuł problemu

- **Objaw:** …
- **Przyczyna:** …
- **Diagnoza:** polecenie, które to pokazało.
- **Rozwiązanie:** …
- **Wniosek:** czego to uczy (przyda się na rozmowie).
```

Wpisuj tylko problemy, które naprawdę wystąpiły.

## 3. Wpisy poza folderem

- `docs/00-przewodnik.md`:
  - „Mapa etapów”: wiersz `| [Etap N – nazwa](#etap-n--nazwa) | co powstaje | kroki | [📁 folder](etap-…/README.md), … |`.
    Ćwiczenia jako osobny wiersz `| ↳ Etap N – ćwiczenia … |`.
  - Sekcja `## Etap N – nazwa` z krokami numerowanymi dalej od ostatniego etapu
    (Etap 3 kończy się na kroku 32). Każde polecenie: 🪟 Windows albo 🐧 maszyna, co robi,
    czego się spodziewać. Snapshoty jako `### Krok X. 📸 Snapshot … – \`nazwa\``.
  - Lista w sekcji `## Dalej`.
- `README.md` (główny): wiersz w tabeli `| Etap | Folder | Teoria | Ćwiczenia |`.
- `docs/problemy-ogolne.md`: wiersz w tabeli „Problemy według etapów” z linkami do kotwic
  w `problemy.md`.

## 4. Sprawdzenie

```bash
node tools/check-links.mjs
```

Musi być `błędów: 0`. Kotwica powstaje z nagłówka: małe litery, bez interpunkcji, spacje → `-`
(np. `## Etap 4 – monitoring` → `#etap-4--monitoring`).

Potem commit i push według skilla `zamknij-etap` (krok 4 i 5).
