// Play the HTML prototype in headless Chromium: serve the folder, open a URL, collect the console,
// take screenshots, and (for bot runs) wait for window.__botReport.
// Usage: node play.mjs "<query>" <outPrefix> [waitSeconds=20] [width=1280] [height=720] [shots=1]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [query = '', outPrefix = '/tmp/shot', wait = '20', w = '1280', h = '720', shots = '1'] = process.argv.slice(2);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.webp': 'image/webp', '.png': 'image/png', '.glb': 'model/gltf-binary', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const f = path.join(root, url === '/' ? 'index.html' : url);
  if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.statusCode = 404; return res.end(); }
  res.setHeader('Content-Type', types[path.extname(f)] || 'application/octet-stream');
  fs.createReadStream(f).pipe(res);
}).listen(0);
const port = server.address().port;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: +w, height: +h }, hasTouch: query.includes('touch=1') });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.goto(`http://127.0.0.1:${port}/?${query}`);
const n = +shots;
for (let i = 1; i <= n; i++) {
  await page.waitForTimeout((+wait * 1000) / n);
  await page.screenshot({ path: `${outPrefix}-${i}.png` });
}
const report = await page.evaluate(() => window.__botReport || null);
fs.writeFileSync(`${outPrefix}-console.txt`, logs.join('\n'));
console.log(JSON.stringify({ report, errors: logs.filter((l) => l.includes('error')).slice(0, 10), lines: logs.length }, null, 1));
await browser.close();
server.close();
