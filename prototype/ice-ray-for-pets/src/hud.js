// CLIENT: the Screen owner. Only this module places HUD elements (UI Rules: one owner).
// HUD cap of 5: coins, menu tiles, goal bar, contextual banner (+ prompts that live on world objects).
import { Config, Theme, PetDefs, World, petByKey, upgradeCost, zoneById, isRegular } from './config.js';
import { iceBridgeCenter, temperatureAt, zoneAt } from './world.js';

const ICONS = { // the approved painted icons (UI Rules > Icons)
  shop: '<img src="assets/icons/bag.webp" alt="">',
  index: '<img src="assets/icons/book.webp" alt="">',
  settings: '<img src="assets/icons/gear.webp" alt="">',
};
const COIN = '<img class="coinimg" src="assets/icons/coin.webp" alt="">'; // one coin image everywhere
const ROBUX = '<svg viewBox="0 0 40 40"><path d="M20 3l15 8.5v17L20 37 5 28.5v-17z" fill="#fff" stroke="#1b1433" stroke-width="3"/><rect x="13" y="13" width="14" height="14" rx="2" fill="none" stroke="#1b1433" stroke-width="3.5"/></svg>';
const fmt = (n) => (n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e4 ? (n / 1e3).toFixed(1) + 'K' : Math.floor(n).toLocaleString());
const rate = (n) => (n >= 100 ? fmt(n) : (Math.round(n * 10) / 10).toString());

export function createHud({ server, input, audio }) {
  // per-viewer settings (in Roblox these are saved with the player's data)
  function saveSettings() { try { localStorage.setItem('iceray.settings', JSON.stringify({ music: audio.music, sfx: audio.sfx, reduced: Config.motion.reduced, unit: Config.temperature.unit })); } catch { /* storage blocked */ } }
  try {
    const st = JSON.parse(localStorage.getItem('iceray.settings') || 'null');
    if (st) { audio.setMusic(st.music !== false); audio.setSfx(st.sfx !== false); Config.motion.reduced = !!st.reduced; Config.temperature.unit = st.unit === 'F' ? 'F' : 'C'; }
  } catch { /* storage blocked: defaults */ }
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) Config.motion.reduced = true; // on by default if the device asks
  document.documentElement.classList.toggle('reduced', Config.motion.reduced);
  const $ = (s) => document.querySelector(s);
  const coinsEl = $('#coins'), coinN = coinsEl.querySelector('.n'), coinR = coinsEl.querySelector('.rate');
  const goal = $('#goal'), goalT = goal.querySelector('.t'), goalFill = goal.querySelector('.fill');
  const tempEl = $('#temp'), tempDeg = tempEl.querySelector('.deg'), tempWhy = tempEl.querySelector('.why'), merc = tempEl.querySelector('.merc');
  const banner = $('#banner'), prompts = $('#prompts');
  const wrap = $('#popup-wrap'), pop = $('#popup');
  const tiles = $('#tiles');
  let client = null;
  const seenFound = new Set(Object.keys(server.view()?.found || {}));

  // menu tiles
  for (const t of Config.ui.tiles) {
    const b = document.createElement('button');
    b.className = 'block press tile txt'; b.style.setProperty('--face', Theme.tiles[t.id]);
    b.innerHTML = `${ICONS[t.id]}<span class="lbl">${t.label}</span><span class="badge">!</span>`;
    b.addEventListener('click', () => { audio.unlock(); audio.play('click'); open(t.id); });
    b.dataset.id = t.id; tiles.appendChild(b);
  }

  // ---------------- popups (one at a time, queued) ----------------
  const queue = []; let current = null;
  function open(name, data) {
    if (current) { if (current.name !== name) queue.push({ name, data }); return; }
    current = { name, data }; openedAt = performance.now(); sel = -1; render(); wrap.classList.add('on');
    server.remotes.setMenuOpen(true);
    if (name === 'shop') server.remotes.openShop();
  }
  function close() {
    wrap.classList.remove('on'); current = null; server.remotes.setMenuOpen(false);
    const n = queue.shift(); if (n) setTimeout(() => open(n.name, n.data), 150);
  }
  let openedAt = 0;
  wrap.addEventListener('pointerdown', (e) => { if (e.target === wrap && performance.now() - openedAt > 400) close(); }); // a double-click doesn't open and shut it
  addEventListener('keydown', (e) => { if (e.code === 'Escape' && current) { audio.play('click'); close(); } });
  let idxPage = 1;
  function render() {
    const v = server.view(); if (!current || !v) return;
    const head = (title, color) => `<button class="block press close txt" aria-label="Close">X</button><h2 class="txt" style="color:#fff">${title}</h2>`;
    if (current.name === 'shop') {
      pop.innerHTML = head('Shop') + '<div class="cards">' + ['ray', 'boots', 'backpack'].map((id) => {
        const u = Config.upgrades[id], lvl = v.upgrades[id], max = lvl >= u.maxLevel, cost = max ? 0 : upgradeCost(id, lvl + 1);
        const effect = id === 'ray' ? 'Bigger cubes that last longer' : id === 'boots' ? 'Run faster' : `Carry ${lvl + 1} cubes`;
        return `<div class="block card2"><h3>${u.name}</h3><div>Level ${lvl}</div><p>${effect}</p>
          <button class="block press buy txt ${!max && v.coins < cost ? 'cant' : ''}" data-buy="${id}">${max ? 'MAX' : COIN + fmt(cost)}</button></div>`;
      }).join('') + '</div>';
    } else if (current.name === 'index') {
      const pets = PetDefs.filter((p) => p.zone === idxPage), regular = pets.filter(isRegular);
      const found = regular.filter((p) => v.found[p.key]).length;
      pop.innerHTML = head('Index') + `<div class="idx-tabs">${World.zones.map((z) => `<button class="block press ${z.id === idxPage ? 'on' : ''}" data-page="${z.id}">${z.name}</button>`).join('')}</div>
        <div class="center" style="margin-bottom:8px">${found} / ${regular.length} found${found === regular.length ? ': +10% coins!' : ' · find all for +10% coins'}</div>
        <div class="idx-grid">${pets.map((p) => `<div class="idx-cell ${v.found[p.key] ? '' : 'miss'} ${isRegular(p) ? '' : 'bonus'}"><span class="tr" style="background:${Theme.tiers[p.tier]}"></span><img src="assets/sprites/${p.key}.webp" alt=""><span class="nm">${v.found[p.key] ? p.name : isRegular(p) ? '???' : 'Bonus'}</span></div>`).join('')}</div>`;
      pets.forEach((p) => v.found[p.key] && seenFound.add(p.key));
    } else if (current.name === 'settings') {
      pop.innerHTML = head('Settings') + `<div class="settings-grid">
        <div class="settings-row"><span>Music</span><button class="toggle ${audio.music ? 'on' : ''}" data-tog="music" aria-label="Music"></button></div>
        <div class="settings-row"><span>Sound</span><button class="toggle ${audio.sfx ? 'on' : ''}" data-tog="sfx" aria-label="Sound"></button></div>
        <div class="settings-row"><span>Mute everything</span><button class="toggle ${!audio.music && !audio.sfx ? 'on' : ''}" data-tog="mute" aria-label="Mute everything"></button></div>
        <div class="settings-row"><span>Reduced motion</span><button class="toggle ${Config.motion.reduced ? 'on' : ''}" data-tog="motion" aria-label="Reduced motion"></button></div>
        <div class="settings-row"><span>Low graphics</span><button class="toggle ${Config.graphics.low ? 'on' : ''}" data-tog="gfx" aria-label="Low graphics"></button></div>
        <div class="settings-row"><span>Temperature in °F</span><button class="toggle ${Config.temperature.unit === 'F' ? 'on' : ''}" data-tog="unit" aria-label="Temperature in F"></button></div></div>`;
    } else if (current.name === 'welcome') {
      const w = current.data;
      pop.innerHTML = `<h2 class="txt">Welcome back!</h2><div class="center">Your pets earned</div><div class="big txt">${COIN.replace('class="coinimg"', 'class="coinimg" style="width:40px;height:40px;vertical-align:-8px"')} ${fmt(w.coins)}</div>
        <div class="center" style="margin:4px 0 10px">while you were away${w.capped ? ' (pens hold up to 8 hours of coins)' : ''}</div>
        ${w.best ? `<div class="best"><img src="assets/sprites/${w.best}.webp" alt=""><span>Your best last time:<br><b>${petByKey[w.best].name}</b></span></div>` : ''}
        <button class="block press buy txt" data-collect="1">Collect</button>`;
    } else if (current.name === 'gift') {
      const g = current.data;
      pop.innerHTML = `<h2 class="txt">Daily gift</h2><div class="big txt">${COIN.replace('class="coinimg"', 'class="coinimg" style="width:40px;height:40px;vertical-align:-8px"')} ${fmt(g.coins)}</div>
        <div class="center" style="margin:4px 0 10px">Day ${g.streak} streak</div>
        <button class="block press buy txt" data-ok="1">Yay!</button>`;
    } else if (current.name === 'superfreeze') {
      pop.innerHTML = head('Super Freeze') + `<div class="center" style="margin-bottom:10px">Never melts until your pen.</div>
        <button class="block press buy txt" data-sf="${current.data.id}" style="--face:#4e7dff;--lip-c:#2440a6">${ROBUX} ${Config.monetization.superFreeze.robux} (mock buy)</button>
        <div class="center" style="margin-top:8px;font-size:14px;color:#4a4270">Zapping it again is always free</div>`;
    }
    pop.querySelector('.close')?.addEventListener('click', () => { audio.play('click'); close(); });
    pop.querySelectorAll('[data-buy]').forEach((b) => b.addEventListener('click', () => { audio.play('click'); server.remotes.buyUpgrade(b.dataset.buy); }));
    pop.querySelectorAll('[data-page]').forEach((b) => b.addEventListener('click', () => { idxPage = +b.dataset.page; render(); }));
    pop.querySelectorAll('[data-tog]').forEach((b) => b.addEventListener('click', () => {
      const k = b.dataset.tog;
      if (k === 'music') audio.setMusic(!audio.music); else if (k === 'sfx') audio.setSfx(!audio.sfx);
      else if (k === 'mute') { const on = !audio.music && !audio.sfx; audio.setMusic(on); audio.setSfx(on); }
      else if (k === 'gfx') { try { localStorage.setItem('iceray.lowGfx', Config.graphics.low ? '0' : '1'); } catch { /* storage blocked */ } location.reload(); return; }
      else if (k === 'unit') Config.temperature.unit = Config.temperature.unit === 'F' ? 'C' : 'F';
      else { Config.motion.reduced = !Config.motion.reduced; document.documentElement.classList.toggle('reduced', Config.motion.reduced); }
      saveSettings(); audio.play('click'); render();
    }));
    pop.querySelector('[data-collect]')?.addEventListener('click', () => { server.remotes.collectWelcome(); close(); });
    pop.querySelector('[data-ok]')?.addEventListener('click', () => close());
    pop.querySelector('[data-sf]')?.addEventListener('click', (e) => { server.remotes.buySuperFreezeMock(e.currentTarget.dataset.sf); close(); });
    if (sel >= 0) highlight(); // keep the gamepad selection after a redraw
    requestAnimationFrame(moreHint);
  }
  // a hint when the popup has more below (the phone Index page scrolls)
  function moreHint() { pop.classList.toggle('more', pop.scrollHeight > pop.clientHeight + 4 && pop.scrollTop + pop.clientHeight < pop.scrollHeight - 4); }
  pop.addEventListener('scroll', moreHint);

  // ---------------- gamepad (and keyboard) menus: the d-pad moves, A presses, B closes ----------------
  let sel = -1, tileSel = -1;
  const focusables = () => [...pop.querySelectorAll('button')].filter((b) => b.offsetParent !== null);
  function highlight() {
    document.querySelectorAll('.gp-sel').forEach((e) => e.classList.remove('gp-sel'));
    if (current) { const f = focusables(); if (f.length) { sel = Math.max(0, Math.min(f.length - 1, sel)); f[sel].classList.add('gp-sel'); f[sel].scrollIntoView({ block: 'nearest' }); } }
    else if (tileSel >= 0) tiles.children[tileSel]?.classList.add('gp-sel');
  }
  input.onPad((btn) => {
    audio.unlock();
    const offer = [...offerEls.values()].find((el) => el.style.display !== 'none');
    if (current) {
      const f = focusables();
      if (btn === 'b') { audio.play('click'); close(); }
      else if (btn === 'a') { if (sel < 0) { sel = Math.max(0, f.findIndex((b) => b.matches('.buy, [data-collect], [data-ok]'))); highlight(); } else f[sel]?.click(); }
      else if (btn === 'down' || btn === 'right') { sel = sel < 0 ? 0 : (sel + 1) % f.length; highlight(); }
      else if (btn === 'up' || btn === 'left') { sel = sel < 0 ? 0 : (sel - 1 + f.length) % f.length; highlight(); }
    } else if (tileSel >= 0) {
      const n = tiles.children.length;
      if (btn === 'b' || btn === 'menu') { tileSel = -1; highlight(); }
      else if (btn === 'a') { const id = tiles.children[tileSel].dataset.id; tileSel = -1; highlight(); audio.play('click'); open(id); }
      else if (['down', 'right'].includes(btn)) { tileSel = (tileSel + 1) % n; highlight(); }
      else if (['up', 'left'].includes(btn)) { tileSel = (tileSel - 1 + n) % n; highlight(); }
    } else if (btn === 'menu') { tileSel = 0; highlight(); } // Start (or Select) picks a menu tile
    else if (btn === 'y' && offer) offer.querySelector('button').click(); // Y presses the Super Freeze button by the pet
  });
  server.on('upgraded', ({ id }) => { audio.play('buy'); if (current?.name === 'shop') render(); });
  server.on('welcomeBack', (w) => open('welcome', w));
  server.on('gift', () => { if (current?.name === 'gift') render(); });
  server.on('welcomeCollected', ({ coins }) => { audio.play('gift'); floatAt(`+${fmt(coins)}`, centerOf(coinsEl), '#ffd34a'); });
  server.on('giftClaimed', (g) => open('gift', g));

  // ---------------- banner, floats, not-yet ----------------
  let bannerTimer = null;
  function showBanner(text, kind = '', seconds = 3) {
    banner.textContent = text; banner.className = 'block txt on ' + kind;
    clearTimeout(bannerTimer); bannerTimer = setTimeout(() => banner.classList.remove('on'), seconds * 1000);
  }
  function floatAt(text, pos, color = '#fff') {
    if (!pos) return;
    const el = document.createElement('div'); el.className = 'float txt'; el.style.left = pos.x + 'px'; el.style.top = pos.y + 'px'; el.style.color = color; el.textContent = text;
    document.getElementById('hud').appendChild(el); setTimeout(() => el.remove(), 1200);
  }
  function notYet(text, pos) {
    floatAt(text, pos || { x: innerWidth / 2, y: innerHeight * 0.45 }, '#ffb3b5');
    if (current) pop.querySelector('.buy.cant')?.classList.add('shake');
  }
  const centerOf = (el) => { const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2 + 40, y: r.top }; };
  server.on('notYet', ({ reason }) => { audio.play('no'); notYet(reason, current ? centerOf(pop) : null); });
  server.on('chillWarn', ({ inSeconds }) => showBanner(`Big Chill in ${Math.round(inSeconds)} seconds!`, 'chill', 4));
  server.on('chillStart', () => { audio.play('chill'); showBanner('BIG CHILL! Nothing melts, Frosty pets!', 'chill', 6); });
  server.on('chillEnd', () => showBanner('The Big Chill is over', 'chill', 3));
  server.on('zoneUnlocked', () => showBanner('Pine Forest is open!', '', 5));
  server.on('melted', ({ offer }) => showBanner(offer ? 'It melted! Zap it again for free' : 'It melted! Zap it again', '', 3));
  server.on('bridge', ({ until, seconds }) => { if (until > 0) showBanner(`Ice bridge for ${seconds} seconds`, 'chill', 3); });
  let lastCoins = 0, shopSig = '';

  // ---------------- prompts on world objects ----------------
  const promptEl = document.createElement('div'); promptEl.className = 'prompt'; promptEl.style.display = 'none';
  promptEl.innerHTML = '<svg class="ring" viewBox="0 0 46 46"><circle cx="23" cy="23" r="19" fill="rgba(27,20,51,.35)" stroke="#fff" stroke-width="4"/><circle class="arc" cx="23" cy="23" r="19" fill="none" stroke="#7fe3ff" stroke-width="6" stroke-dasharray="119.4" stroke-dashoffset="119.4" transform="rotate(-90 23 23)"/></svg><div class="block card"></div>';
  prompts.appendChild(promptEl); input.bindHoldButton(promptEl);
  const offerEls = new Map();
  function place(el, pos, extra = []) {
    let x = pos.x, y = pos.y;
    const r = el.getBoundingClientRect(), w = r.width || 160, h = r.height || 90;
    // world prompts never sit on a HUD item: push right of the tiles/coins, below the goal bar and banner
    for (const [kind, e] of [['side', tiles], ['side', coinsEl], ['top', goal], ['top', tempEl], ['top', banner], ...extra]) {
      const hr = e.getBoundingClientRect(); if (!hr.width) continue;
      const box = { l: x - w / 2, r: x + w / 2, t: y - h, b: y };
      if (box.r > hr.left && box.l < hr.right && box.b > hr.top && box.t < hr.bottom) {
        if (kind === 'top') y = hr.bottom + h + 8; else if (kind === 'below') y = hr.bottom + h + 10; else x = hr.right + w / 2 + 10;
      }
    }
    x = Math.max(w / 2 + 6, Math.min(innerWidth - w / 2 - 6, x)); y = Math.max(h + 6, Math.min(innerHeight - 6, y));
    el.style.left = x + 'px'; el.style.top = y + 'px';
  }
  function keyHint() { return input.state.touch ? 'Hold' : navigator.getGamepads?.()[0] ? 'A' : 'E'; }
  function updatePrompt(v) {
    const t = client.target;
    if (!t || current) { promptEl.style.display = 'none'; return; }
    let text, sub = '', tierChip = '', pos;
    if (t.kind === 'pet') {
      const w = v.wild.get(t.id); if (!w) { promptEl.style.display = 'none'; return; }
      const def = petByKey[w.key];
      if (w.state === 'dazed') { text = 'Zap to refreeze'; sub = `${Config.poses[w.pose].label} kept`; }
      else { text = `Freeze ${def.name}`; const ps = Config.poses[w.action]; sub = `${ps.label}${ps.bonus > 1 ? ` x${ps.bonus}` : ''}`; }
      tierChip = `<span class="tier txt" style="background:${Theme.tiers[def.tier]}">${def.tier}</span>`;
      pos = client.worldToScreen(w.x, 3.5 + (def.size === 'L' ? 1.5 : 0), w.z);
    } else if (t.kind === 'gift') { text = 'Open gift'; pos = client.worldToScreen(World.giftBox.x, 6, World.giftBox.z); }
    else { const c = iceBridgeCenter(client.me); text = 'Freeze an ice bridge'; sub = ''; pos = client.worldToScreen(c.x, 3, c.z); }
    if (!pos) { promptEl.style.display = 'none'; return; }
    promptEl.style.display = 'flex';
    promptEl.querySelector('.card').innerHTML = `${tierChip}<div><span class="k">${keyHint()}</span>${text}</div>${sub ? `<span class="pose">${sub}</span>` : ''}`;
    const prog = client.hold.target && client.hold.target.id === t.id ? Math.min(1, client.hold.t / client.hold.need) : 0;
    promptEl.querySelector('.arc').style.strokeDashoffset = String(119.4 * (1 - prog));
    place(promptEl, pos);
  }
  function updateOffers(v) {
    for (const w of v.wild.values()) {
      if (w.state === 'dazed' && w.offer && !offerEls.has(w.id)) {
        const el = document.createElement('div'); el.className = 'offer';
        el.innerHTML = `<button class="block press txt"><span class="k">Y</span>${ROBUX} ${Config.monetization.superFreeze.robux} Super Freeze</button>`;
        el.querySelector('button').addEventListener('click', () => { audio.play('click'); open('superfreeze', { id: w.id }); });
        prompts.appendChild(el); offerEls.set(w.id, el);
      }
    }
    for (const [id, el] of offerEls) {
      const w = v.wild.get(id);
      if (!w || !w.offer) { el.remove(); offerEls.delete(id); continue; }
      const p = client.worldToScreen(w.x + 3, 2.5, w.z);
      // the paid button gets its own slot below the free "Zap to refreeze" prompt, never touching it
      if (p) { el.style.display = 'block'; place(el, p, promptEl.style.display !== 'none' ? [['below', promptEl]] : []); } else el.style.display = 'none';
      el.querySelector('.k').style.display = navigator.getGamepads?.()[0] ? '' : 'none';
    }
  }

  // ---------------- goal bar (three goals: short, medium, long) ----------------
  function goalFor(v) {
    const need = zoneById[2].gatePets;
    if (!v.forestUnlocked) return { text: `Unlock Pine Forest: ${v.pets.length} / ${need} pets in your pen`, frac: v.pets.length / need };
    const beach = Config.beachGateCoins;
    if (v.coins < beach && !beachSeen) return { text: `Unlock Sunny Beach: ${fmt(v.coins)} / ${fmt(beach)}`, frac: v.coins / beach };
    beachSeen = true; // the prototype stops at the Forest; after 500 coins the Index pages are the goal
    for (const z of World.zones) {
      const pets = PetDefs.filter((p) => p.zone === z.id && isRegular(p)), found = pets.filter((p) => v.found[p.key]).length;
      if (found < pets.length) return { text: `Fill the ${z.name} page: ${found} / ${pets.length}`, frac: found / pets.length };
    }
    return { text: 'Every page full! Sunny Beach is next', frac: 1 };
  }

  let beachSeen = false, lastZone = -1, layoutKey = '';
  // Screen layout: the tile grid is centred, but moves up (and the coins drop a little) so the two
  // never touch on a short phone screen (UI Rules: nothing overlaps at 844x390)
  function layout() {
    const key = `${innerWidth}x${innerHeight}:${getComputedStyle(document.documentElement).getPropertyValue('--touch-lift')}:${coinsEl.offsetHeight}`; // the coins grow when the +N/s line appears
    if (key === layoutKey) return; layoutKey = key;
    tiles.style.top = ''; tiles.style.transform = ''; coinsEl.style.bottom = '';
    const safeTop = 52, gap = 12;
    let t = tiles.getBoundingClientRect(), c = coinsEl.getBoundingClientRect();
    if (t.bottom + gap > c.top) {
      const top = Math.max(safeTop + 6, c.top - gap - t.height);
      tiles.style.top = top + 'px'; tiles.style.transform = 'scale(var(--ui))'; tiles.style.transformOrigin = 'left top';
      t = tiles.getBoundingClientRect();
      if (t.bottom + gap > c.top) coinsEl.style.bottom = Math.max(8, innerHeight - c.bottom - (t.bottom + gap - c.top)) + 'px';
    }
  }
  function update(v) {
    if (!v) return;
    layout();
    const zoneNow = zoneAt(v.pos.x, v.pos.z); if (zoneNow !== lastZone) { lastZone = zoneNow; audio.setZone?.(zoneNow); }
    if (Math.floor(v.coins) !== lastCoins) { if (v.coins > lastCoins) { coinsEl.classList.remove('pop'); void coinsEl.offsetWidth; coinsEl.classList.add('pop'); } lastCoins = Math.floor(v.coins); }
    coinN.textContent = fmt(v.coins); coinR.textContent = v.income > 0 ? `+${rate(v.income)}/s` : ''; // never a "+0"
    coinR.style.display = v.income > 0 ? '' : 'none';
    const g = goalFor(v); goalT.textContent = g.text; goalFill.style.width = g.frac * 100 + '%';
    goal.classList.toggle('hidden', v.pets.length === 0); // shows up with your first pet, so it starts at a real 1 / 8
    // temperature where you stand (worked out from the same numbers as melting)
    const tp = temperatureAt(v.pos.x, v.pos.z, { chill: v.chill.active, night: false });
    const zoneId = zoneAt(v.pos.x, v.pos.z);
    const place = zoneId === 0 ? 'Hub' : zoneById[zoneId].name;
    const deg = Config.temperature.unit === 'F' ? tp.f : tp.c;
    tempDeg.textContent = `${deg}°${Config.temperature.unit}`;
    tempWhy.textContent = tp.light === 'chill' ? 'Big Chill' : tp.light === 'shade' ? `${place} · shade` : tp.light === 'sun' ? `${place} · sun` : place;
    tempEl.className = `block txt ${tp.light === 'chill' ? 'chill' : tp.band}`;
    const h = Math.max(2, Math.min(14, 7 + tp.c / 5)); merc.setAttribute('y', String(24 - h)); merc.setAttribute('height', String(h));
    const affordable = ['ray', 'boots', 'backpack'].some((id) => v.upgrades[id] < Config.upgrades[id].maxLevel && v.coins >= upgradeCost(id, v.upgrades[id] + 1));
    tiles.querySelector('[data-id="shop"] .badge').classList.toggle('on', affordable);
    const newFound = Object.keys(v.found).some((k) => !seenFound.has(k));
    tiles.querySelector('[data-id="index"] .badge').classList.toggle('on', newFound);
    if (client) { updatePrompt(v); updateOffers(v); }
    if (current?.name === 'shop') {
      // redraw only when what you can afford changes, so a button never vanishes under a finger
      const sig = ['ray', 'boots', 'backpack'].map((id) => `${v.upgrades[id]}:${v.coins >= upgradeCost(id, v.upgrades[id] + 1)}`).join('|');
      if (sig !== shopSig) { shopSig = sig; render(); }
    }
  }
  return { update, open, close, showBanner, floatAt, notYet, setClient(c) { client = c; }, get popupOpen() { return !!current; } };
}
