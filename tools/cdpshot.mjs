// Zrzut strony przez Edge bez okna (headless), sterowany przez Chrome DevTools Protocol.
// Czeka naprawdę (domyślnie 6 s), więc wykresy Prometheusa zdążą się narysować –
// samo `msedge --screenshot` robi zdjęcie za wcześnie i wykres wychodzi pusty.
//
// Użycie: node tools/cdpshot.mjs <plik.png> <url> [szerokość] [wysokość] [czekaj_ms]
// Przykład: node tools/cdpshot.mjs graf.png "http://192.168.180.51:30090/query?g0.expr=up&g0.tab=graph" 1400 760
// Inna ścieżka do przeglądarki: zmienna EDGE (działa też z Chrome).
// Uwaga: strony z logowaniem (Grafana) wymagają sesji – tym skryptem ich nie zrobisz.
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [out, url, w = '1400', h = '900', wait = '6000'] = process.argv.slice(2);
if (!out || !url) { console.error('Użycie: node tools/cdpshot.mjs <plik.png> <url> [szer] [wys] [czekaj_ms]'); process.exit(2); }

// Ukośniki zwykłe – z odwrotnymi Node na Windowsie gubi ścieżkę przy spawn
const edge = process.env.EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const port = 9300 + Math.floor(Math.random() * 500);
const prof = mkdtempSync(join(tmpdir(), 'edgecdp-'));
const browser = spawn(edge, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`,
  `--user-data-dir=${prof}`, `--window-size=${w},${h}`, 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Czekamy, aż przeglądarka wystawi listę kart na porcie debugowania
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === 'page'); } catch {}
}
if (!target) { console.error('Przeglądarka nie odpowiada – sprawdź ścieżkę EDGE'); browser.kill(); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0; const pending = new Map();
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });

await send('Emulation.setDeviceMetricsOverride', { width: +w, height: +h, deviceScaleFactor: 1, mobile: false });
await send('Page.enable');
await send('Page.navigate', { url });
await sleep(+wait);
const shot = await send('Page.captureScreenshot', { format: 'png' });
const png = Buffer.from(shot.data, 'base64');
writeFileSync(out, png);
console.log(`${out} -> ${png.length} B`);

ws.close(); browser.kill();
try { rmSync(prof, { recursive: true, force: true }); } catch {}
process.exit(0);
