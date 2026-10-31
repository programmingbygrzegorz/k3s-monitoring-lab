---
name: zamknij-etap
description: Zamyka krok albo cały etap labu – dopisuje wyniki, problemy i pytania rekrutacyjne do folderu etapu, aktualizuje „Stan labu” w CLAUDE.md, sprawdza odnośniki, robi commit i push na main. Użyj po każdym kroku labu, który wniósł coś nowego, i na końcu etapu.
---

# Zamknięcie kroku albo etapu

Właściciel zgodził się na commit i push bez pytania. Wszystko po polsku.

## 1. Dokumentacja w folderze etapu

Wszystko trafia do `docs/etap-N-…/` – nigdy do osobnych plików na końcu `docs/`.

- **Prawdziwe wyniki** z labu (wynik polecenia, nazwy podów, adresy, wersje) – w pliku
  instrukcji, przy kroku, którego dotyczą. Sprawdź je na maszynie (`ssh k3s-master …`),
  nie pisz z pamięci.
- **Nowe pojęcie** – w pliku teorii etapu.
- **Problem**, który wystąpił – w `problemy.md` (objaw, przyczyna, diagnoza, rozwiązanie,
  wniosek) i wiersz w `docs/problemy-ogolne.md`.
- **Pytanie rekrutacyjne** – przy teorii, której dotyczy: pytanie + krótka odpowiedź.
- **Ćwiczenia**: zadania i rozwiązania osobno, zrzuty przez `tools/cdpshot.mjs`
  i `tools/terminal-shot.sh` (opis w `tools/README.md`).

## 2. Koniec etapu – dodatkowo

- Sekcja „Etap N w pigułce – zacznij tutaj” w `README.md` etapu (wzór: Etap 3 i skill
  `nowy-etap`) – z prawdziwymi wynikami.
- W `README.md` etapu usuń dopiski typu „zostaną dopisane po przejściu etapu”.
- Mapa etapów w `docs/00-przewodnik.md` i tabela w głównym `README.md` – aktualne linki.

## 3. Stan labu w `CLAUDE.md`

Zaktualizuj sekcję „Stan labu (aktualizuj!)”: datę, ✅ zakończone etapy (z wersjami),
⚠️ rzeczy do zrobienia przez właściciela, ⏭️ następny krok. Krótko – to ma czytać nowa sesja.

## 4. Sprawdzenie

```bash
node tools/check-links.mjs
git status --short
```

- Odnośniki: musi być `błędów: 0`.
- W `git status` **nie może** być `docs/dziennik-wdrozenia.md` ani `docs/rozmowa-po-angielsku.md`.
  Jeśli są – dopisz obie ścieżki do `.git/info/exclude` (nie do `.gitignore`).
- Żadnych haseł, tokenów ani `lab.env` w zmianach (`git diff` przed commitem).

## 5. Commit i push

Pliki dodawaj **po nazwie** – nigdy `git add -A`, `git add .` ani `git add docs/`.

```bash
git add docs/etap-N-…/plik.md CLAUDE.md
git commit -m "Etap N: co się zmieniło – krótko, po polsku"
git push
```

Skrypty `.sh` nowe w repozytorium: `git update-index --chmod=+x ścieżka` przed commitem.

Na koniec powiedz właścicielowi w 2–3 zdaniach, co dopisano, i przypomnij o snapshocie,
jeśli etap się zakończył.
