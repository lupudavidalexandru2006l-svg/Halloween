// Scripted visual tour of the prototype for QA screenshots (every screen and state).
// Usage: node tour.mjs <outDir> [width=1280] [height=720] [touch=0]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [out = '/tmp/tour', w = '1280', h = '720', touch = '0'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.webp': 'image/webp', '.png': 'image/png', '.glb': 'model/gltf-binary' };
const server = http.createServer((req, res) => {
  const f = path.join(root, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.statusCode = 404; return res.end(); }
  res.setHeader('Content-Type', types[path.extname(f)] || 'application/octet-stream'); fs.createReadStream(f).pipe(res);
}).listen(0);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: +w, height: +h }, hasTouch: touch === '1', isMobile: touch === '1' });
const logs = [];
page.on('console', (m) => logs.push(m.text())); page.on('pageerror', (e) => logs.push('PAGEERROR ' + e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/?fresh=1&seed=5`);
await page.waitForFunction(() => !document.getElementById('loading'), null, { timeout: 60000 });
const G = (fn, arg) => page.evaluate(fn, arg);
const shot = async (name, ms = 600) => { await page.waitForTimeout(ms); await page.screenshot({ path: `${out}/${name}.png` }); console.log('shot', name); };
const tp = (x, z) => G(([x, z]) => { const g = window.__game; g.server.debug.teleport(x, z); g.client.me.x = x; g.client.me.z = z; }, [x, z]);
const nearestPet = () => G(() => { const g = window.__game, v = g.server.view(), m = g.client.me; let b = null, bd = 1e9; for (const p of v.wild.values()) { const d = Math.hypot(p.x - m.x, p.z - m.z); if (p.zone === 1 && d < bd) { bd = d; b = p; } } return b && { x: b.x, z: b.z, id: b.id }; });
const holdE = async (ms) => { await page.keyboard.down('KeyE'); await page.waitForTimeout(ms); await page.keyboard.up('KeyE'); };

await shot('01-hub-start', 1500);
let p = await nearestPet(); await tp(p.x - 4, p.z - 4);
await page.keyboard.down('KeyE'); await shot('02-zapping', 500); await page.waitForTimeout(2200); await page.keyboard.up('KeyE');
await shot('03-carrying', 400);
await tp(0, 20); await shot('04-carry-run-home', 400);
await tp(0, -24); await shot('05-banked-in-pen', 900);
await G(() => window.__game.server.debug.grantCoins(1000));
await page.click('#tiles [data-id="shop"]'); await shot('06-shop', 500);
await page.click('#popup .close'); await page.click('#tiles [data-id="index"]'); await shot('07-index', 500);
await page.click('#popup .close');
await tp(10, 80); await G(() => window.__game.server.debug.spawnNear('Epic')); await page.waitForTimeout(300);
p = await G(() => { const g = window.__game, v = g.server.view(); for (const w of v.wild.values()) if (w.key === 'frostfox') return { x: w.x, z: w.z }; return null; });
if (p) { await tp(p.x - 4, p.z - 4); await holdE(2600); }
await shot('08-carrying-epic', 300);
await G(() => window.__game.server.debug.meltSoon()); await shot('09-melted-superfreeze-offer', 1800);
const offer = await page.$('.offer button'); if (offer) { await offer.click(); await shot('10-superfreeze-popup', 500); await page.click('#popup .close'); }
await tp(30, -14); await shot("11-leaderboards", 1200);
await G(() => window.__game.client.me.z = -32);
await tp(-30, 160); await shot('12-river-bridges-gate', 900);
await tp(24, 160); await shot('13-ice-bridge-spot', 500); await holdE(2600); await tp(24, 175); await shot('14-ice-bridge-active', 600);
await G(() => window.__game.server.debug.unlockForest()); await tp(0, 188); await shot('15-forest-gate-open', 1500);
await tp(0, 240); await shot('16-pine-forest', 800);
await G(() => window.__game.server.debug.bigChillSoon()); await G(() => { window.__game.server.tick(30.1); }); await shot('17-big-chill', 1200);
await tp(-24, -16); await shot("18-gift-box", 600); await holdE(1400); await shot('19-gift-claimed', 700);
await page.click('#popup [data-ok]').catch(() => {});
await G(() => { const g = window.__game; g.server.leave(); g.server.debug.skipTime(3 * 3600); }); await shot('20-welcome-back', 800);
await page.click('#popup [data-collect]').catch(() => {});
await page.keyboard.press('KeyT'); await shot('21-timer-panel', 500);
const ex = await G(() => window.__exploitTest()); console.log(ex);
fs.writeFileSync(`${out}/console.txt`, logs.join('\n'));
console.log('errors:', logs.filter((l) => /PAGEERROR|error/i.test(l)).slice(0, 8));
await browser.close(); server.close();
