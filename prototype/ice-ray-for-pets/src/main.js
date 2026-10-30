// Wires the prototype together: server (SERVER), client + HUD (CLIENT), and the test tools.
// URL: ?bot=1 playtest bot, &speed=5 game speed, &seed=N, &fresh=1 wipe save first,
//      &headless=1 run the sim without drawing (fast bot timing), &until=600 stop the bot at N game seconds,
//      &debug=1 show the test-panel button on touch screens.
import { Config, Analytics, PetDefs } from './config.js';
import { createServer } from './server.js';
import { createClient } from './client.js';
import { createHud } from './hud.js';
import { createInput } from './input.js';
import { createAudio } from './audio.js';
import { createBot } from './bot.js';

const q = new URLSearchParams(location.search);
const BOT = q.get('bot') === '1', HEADLESS = q.get('headless') === '1';
const SPEED = Math.min(20, Math.max(1, +(q.get('speed') || (BOT ? 5 : 1))));
const UNTIL = +(q.get('until') || 0);
try { Config.graphics.low = q.get('low') === '1' || localStorage.getItem('iceray.lowGfx') === '1'; } catch { Config.graphics.low = q.get('low') === '1'; }
if (q.get('fresh') === '1') { try { localStorage.removeItem(Config.saveKey); } catch { /* ignore */ } }

// the analytics list, printed once so it can be checked before wiring it up in Roblox
console.log('[analytics] funnel steps:', Analytics.funnel.map((s) => `${s.step}. ${s.name}`).join(', '));
console.log('[analytics] events:', Object.entries(Analytics.events).map(([k, f]) => `${k}(${f.join(', ')})`).join('; '));

const audio = createAudio();
const input = createInput();
const server = createServer({ seed: q.get('seed') ? +q.get('seed') : undefined, displayName: 'You' });
const hud = createHud({ server, input, audio });
// ---------- timer panel (T): the grind budget in numbers (listening before join, so "joined" is counted) ----------
const marks = {}; const counts = { upgrades: 0 };
const T = () => server.view()?.time ?? 0;
server.on('analytics', (a) => {
  if (a.kind === 'funnel' && !(a.name in marks)) { marks[a.name] = T(); if (BOT) console.log(`[bot] ${a.name} at ${T().toFixed(1)}s game time`); }
});
server.on('banked', () => { const n = server.view().pets.length; for (const k of [8, 12, 15, 20, 25, 30]) if (n >= k && !(`pets_${k}` in marks)) { marks[`pets_${k}`] = T(); if (BOT) console.log(`[bot] ${k} pets at ${T().toFixed(1)}s`); } });
server.on('upgraded', ({ id, level }) => { counts.upgrades++; if (BOT) console.log(`[bot] upgrade ${id} -> ${level} at ${T().toFixed(1)}s`); });
server.on('zoneUnlocked', () => { marks.forest_unlocked = T(); if (BOT) console.log(`[bot] Pine Forest unlocked at ${T().toFixed(1)}s`); });
server.join();
if (q.get('fresh') === '1') history.replaceState(null, '', location.pathname + location.search.replace(/([?&])fresh=1&?/, '$1').replace(/[?&]$/, '')); // a later refresh keeps your progress
const client = createClient({ server, input, audio, hud, headless: HEADLESS });
hud.setClient(client);
const bot = BOT ? createBot({ server, client, input, hud }) : null;
const panel = document.getElementById('panel');
const kid = (s) => (s === undefined ? '-' : `${s.toFixed(0)}s bot = ~${((s * 2.5) / 60).toFixed(1)} min kid`);
// the buttons are built once; only the text above them is redrawn, so a click never lands on a stale button
panel.innerHTML = `<div class="ptext"></div><button data-a="away">Skip 2 h (away)</button><button data-a="day">Skip 1 day</button><button data-a="chill">Big Chill soon</button>
<button data-a="coins">+1,000 coins</button><button data-a="rare">Epic pet here</button><button data-a="melt">Melt my cubes</button>
<button data-a="exploit">Exploit test</button><button data-a="reset">Reset save</button>`;
const ptext = panel.querySelector('.ptext');
function drawPanel() {
  if (!panel.classList.contains('on')) return;
  const v = server.view(); if (!v) return;
  ptext.innerHTML = `<b>Timer panel</b> (T) ${BOT ? `bot x${SPEED}` : ''}<br>
game time ${v.time.toFixed(0)}s · coins ${Math.floor(v.coins)} · +${v.income.toFixed(1)}/s<br>
first freeze: ${kid(marks.first_freeze)}<br>first bank: ${kid(marks.first_bank)}<br>
first upgrade: ${kid(marks.first_coins_spent)}<br>Forest open: ${kid(marks.forest_unlocked)}<br>
Forest reached: ${kid(marks.first_new_zone)}<br>
pets in pen ${v.pets.length} · frozen ${v.stats.frozen} · melts ${v.stats.melts} · upgrades ${counts.upgrades}<br>
ray ${v.upgrades.ray} · boots ${v.upgrades.boots} · backpack ${v.upgrades.backpack} · pages ${v.pages}<br>
remote calls dropped: ${v.dropped}<br>`;
}
panel.addEventListener('click', (e) => {
  const a = e.target.dataset?.a; if (!a) return;
  if (a === 'away') { server.leave(); server.debug.skipTime(2 * 3600); }
  if (a === 'day') { server.leave(); server.debug.skipTime(24 * 3600); }
  if (a === 'chill') server.debug.bigChillSoon();
  if (a === 'coins') server.debug.grantCoins(1000);
  if (a === 'rare') server.debug.spawnNear('Epic');
  if (a === 'melt') server.debug.meltSoon();
  if (a === 'exploit') console.log(exploitTest());
  if (a === 'reset') { server.debug.wipe(); location.search = '?fresh=1'; }
  drawPanel();
});
const togglePanel = () => { panel.classList.toggle('on'); drawPanel(); };
input.onPanel(togglePanel);
const dbgBtn = document.getElementById('dbg-btn');
if (q.get('debug') === '1') dbgBtn.style.display = 'block';
dbgBtn.addEventListener('click', togglePanel);

// ---------- exploit test: fake and spammed remote calls must change nothing ----------
function exploitTest() {
  const r = server.remotes, before = JSON.stringify({ c: server.view().coins, u: server.view().upgrades, p: server.view().pets.length, k: server.view().carrying.length });
  const checks = [];
  const same = (name) => { const now = JSON.stringify({ c: server.view().coins, u: server.view().upgrades, p: server.view().pets.length, k: server.view().carrying.length }); checks.push([name, now === before]); };
  r.buyUpgrade('coins'); r.buyUpgrade({ id: 'ray' }); r.buyUpgrade(null); same('buyUpgrade with junk ids');
  r.beginZap('p999999'); r.endZap('p999999'); same('freeze a pet that does not exist');
  const far = [...server.view().wild.values()].find((w) => Math.hypot(w.x - client.me.x, w.z - client.me.z) > 30);
  if (far) { r.beginZap(far.id); r.endZap(far.id); same('freeze a pet 30+ studs away'); }
  r.endZap('bridge'); same('finish a zap that never started');
  const pos = { ...client.me }; r.setPosition(pos.x, pos.z + 500, 0.016); checks.push(['teleport 500 studs', Math.abs(server.view().pos.z - pos.z) < 1]);
  for (let i = 1; i <= 100; i++) r.setPosition(pos.x, pos.z + i * 0.5, 9); checks.push(['100 small steps in one tick (speed hack)', Math.abs(server.view().pos.z - pos.z) < 12]);
  r.buyUpgrade('constructor'); r.buyUpgrade('__proto__'); r.buyUpgrade('toString'); same('buyUpgrade with object built-in names');
  r.setPosition(NaN, Infinity, 0.016); checks.push(['NaN position', isFinite(server.view().pos.x)]);
  for (let i = 0; i < 200; i++) r.collectWelcome(); same('spam collectWelcome 200x');
  for (let i = 0; i < 200; i++) r.buySuperFreezeMock('p1'); same('spam Super Freeze on a pet with no offer');
  const fails = checks.filter((c) => !c[1]);
  return `[exploit test] ${checks.length} checks, ${fails.length} FAIL ${fails.map((f) => f[0]).join(', ')}`;
}
window.__exploitTest = exploitTest;

// ---------- main loop ----------
addEventListener('pointerdown', () => audio.unlock(), { once: true });
addEventListener('keydown', () => audio.unlock(), { once: true });
addEventListener('pagehide', () => server.leave());
const STEP = 1 / 30;
let last = performance.now(), panelAt = 0, done = false;
function frame(now) {
  const real = Math.min(0.1, (now - last) / 1000); last = now;
  let budget = HEADLESS ? 2000 : Math.ceil((real * SPEED) / STEP); // headless: as many game steps as fit
  const t0 = performance.now();
  while (budget-- > 0 && !done) {
    input.update(); bot?.step(STEP); client.step(STEP); server.tick(STEP);
    if (UNTIL && T() >= UNTIL) finish();
    if (HEADLESS && performance.now() - t0 > 30) break;
  }
  client.render(real * SPEED);
  hud.update(server.view());
  if (now - panelAt > 250) { panelAt = now; drawPanel(); }
  requestAnimationFrame(frame);
}
function finish() {
  done = true;
  const v = server.view();
  window.__botReport = { marks, counts, time: v.time, coins: Math.floor(v.coins), pets: v.pets.length, frozen: v.stats.frozen, melts: v.stats.melts, upgrades: v.upgrades, dropped: v.dropped, income: v.income };
  console.log('[bot] report', JSON.stringify(window.__botReport));
}
(client.ready || Promise.resolve()).then(() => {
  document.getElementById('loading').remove();
  if (BOT) panel.classList.add('on');
  requestAnimationFrame(frame);
});
window.__game = { server, client, Config, PetDefs };
