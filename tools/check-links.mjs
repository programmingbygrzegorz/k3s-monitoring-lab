// Sprawdza odnośniki względne i kotwice nagłówków we wszystkich plikach .md repozytorium.
// Użycie (z katalogu repozytorium): node tools/check-links.mjs
// Kod wyjścia 1, gdy jest choć jeden martwy odnośnik – nadaje się do CI.
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const P = path.posix;
// Kotwica jak na GitHubie: małe litery, bez znaków interpunkcyjnych, spacje -> myślniki
const slug = (t) => t.trim().toLowerCase().replace(/[^\p{L}\p{N} _-]/gu, '').replace(/ /g, '-');

// Pliki śledzone i nowe (bez ignorowanych) + prywatne pliki, jeśli istnieją lokalnie
const files = execSync('git ls-files -co --exclude-standard').toString().split('\n')
  .filter((f) => f.endsWith('.md') && fs.existsSync(f));
for (const f of ['docs/dziennik-wdrozenia.md', 'docs/rozmowa-po-angielsku.md']) if (fs.existsSync(f)) files.push(f);

// Linie poza blokami kodu ``` (także w punktach listy: "1. ```bash") – w kodzie ](...) to nie odnośnik
const fence = /^\s*(?:(?:\d+\.|[-*])\s+)?```/;
const proseLines = (f) => {
  let inCode = false;
  return fs.readFileSync(f, 'utf8').split(/\r?\n/).filter((l) => {
    if (fence.test(l)) { inCode = !inCode; return false; }
    return !inCode;
  });
};
// Kod w linii (`...`) też nie zawiera odnośników
const stripInlineCode = (l) => l.replace(/`[^`]*`/g, '');

const anchorCache = new Map();
const anchors = (f) => {
  if (anchorCache.has(f)) return anchorCache.get(f);
  const set = new Set(); const seen = {};
  for (const l of proseLines(f)) {
    const m = l.match(/^#{1,6} (.*)/);
    if (!m) continue;
    let s = slug(m[1]);
    if (seen[s] !== undefined) { seen[s]++; s = `${s}-${seen[s]}`; } else seen[s] = 0;
    set.add(s);
  }
  anchorCache.set(f, set);
  return set;
};

let bad = 0;
for (const f of files) {
  for (const line of proseLines(f)) {
    for (const m of stripInlineCode(line).matchAll(/\]\(([^)\s]+)\)/g)) {
      const t = m[1];
      if (/^(https?:|mailto:)/.test(t)) continue;
      const [p, a] = t.split('#');
      const target = p ? P.normalize(P.join(P.dirname(f), decodeURIComponent(p))) : f;
      if (!fs.existsSync(target)) { console.log(`BRAK PLIKU  ${f}: ${t}`); bad++; continue; }
      if (a && target.endsWith('.md') && !anchors(target).has(decodeURIComponent(a))) {
        console.log(`BRAK KOTWICY  ${f}: ${t}`); bad++;
      }
    }
  }
}
console.log(`Sprawdzono plików: ${files.length}, błędów: ${bad}`);
process.exit(bad ? 1 : 0);
