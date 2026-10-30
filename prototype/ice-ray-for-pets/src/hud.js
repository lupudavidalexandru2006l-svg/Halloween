// CLIENT: the Screen owner. Only this module places HUD elements (UI Rules: one owner).
// HUD cap of 5: coins, menu tiles, goal bar, contextual banner (+ prompts that live on world objects).
import { Config, Theme, PetDefs, World, petByKey, upgradeCost, zoneById } from './config.js';
import { iceBridgeCenter } from './world.js';

const ICONS = {
  shop: '<svg viewBox="0 0 40 40"><path d="M9 14h22l-2 20H11z" fill="#ffd34a" stroke="#1b1433" stroke-width="3" stroke-linejoin="round"/><path d="M14 15v-3a6 6 0 0 1 12 0v3" fill="none" stroke="#1b1433" stroke-width="3"/><path d="M13 18h3" stroke="#fff6c8" stroke-width="3" stroke-linecap="round"/></svg>',
  index: '<svg viewBox="0 0 40 40"><rect x="8" y="7" width="24" height="27" rx="3" fill="#fff" stroke="#1b1433" stroke-width="3"/><rect x="8" y="7" width="7" height="27" rx="2" fill="#ff5a8a" stroke="#1b1433" stroke-width="3"/><circle cx="24" cy="18" r="4.5" fill="#3aa8ff" stroke="#1b1433" stroke-width="2.5"/><path d="M19 27h10" stroke="#1b1433" stroke-width="3" stroke-linecap="round"/></svg>',
  settings: '<svg viewBox="0 0 40 40"><g transform="translate(20 20)"><path d="M-3-15h6l1 5 4 2 4-3 4 4-3 4 2 4 5 1v6l-5 1-2 4 3 4-4 4-4-3-4 2-1 5h-6l-1-5-4-2-4 3-4-4 3-4-2-4-5-1v-6l5-1 2-4-3-4 4-4 4 3 4-2z" fill="#e6e1ff" stroke="#1b1433" stroke-width="2.5" stroke-linejoin="round" transform="scale(.82)"/><circle r="5" fill="#8f7cff" stroke="#1b1433" stroke-width="2.5"/></g></svg>',
};
const COIN = '<svg viewBox="0 0 40 40"><circle cx="20" cy="21" r="16" fill="#c98a0c" stroke="#1b1433" stroke-width="3"/><circle cx="20" cy="18.5" r="14" fill="#ffd34a" stroke="#1b1433" stroke-width="3"/><circle cx="20" cy="18.5" r="8.5" fill="none" stroke="#e8a714" stroke-width="3"/></svg>';
const ROBUX = '<svg viewBox="0 0 40 40"><path d="M20 3l15 8.5v17L20 37 5 28.5v-17z" fill="#fff" stroke="#1b1433" stroke-width="3"/><rect x="13" y="13" width="14" height="14" rx="2" fill="none" stroke="#1b1433" stroke-width="3.5"/></svg>';
const fmt = (n) => (n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e4 ? (n / 1e3).toFixed(1) + 'K' : Math.floor(n).toLocaleString());
const rate = (n) => (n >= 100 ? fmt(n) : (Math.round(n * 10) / 10).toString());

export function createHud({ server, input, audio }) {
  const $ = (s) => document.querySelector(s);
  const coinsEl = $('#coins'), coinN = coinsEl.querySelector('.n'), coinR = coinsEl.querySelector('.rate');
  const goal = $('#goal'), goalT = goal.querySelector('.t'), goalFill = goal.querySelector('.fill');
  const banner = $('#banner'), prompts = $('#prompts');
  const wrap = $('#popup-wrap'), pop = $('#popup');
  const tiles = $('#tiles');
  let client = null;
  const seenFound = new Set(Object.keys(server.view()?.found || {}));

  // menu tiles
  for (const t of Config.ui.tiles) {
    const b = document.createElement('button');
    b.className = 'block press tile txt'; b.style.setProperty('--face', Theme.tiles[t.id]); b.style.setProperty('--lip-c', 'rgba(27,20,51,.45)');
    b.innerHTML = `${ICONS[t.id]}<span class="lbl">${t.label}</span><span class="badge">!</span>`;
    b.addEventListener('click', () => { audio.unlock(); audio.play('click'); open(t.id); });
    b.dataset.id = t.id; tiles.appendChild(b);
  }

  // ---------------- popups (one at a time, queued) ----------------
  const queue = []; let current = null;
  function open(name, data) {
    if (current) { if (current.name !== name) queue.push({ name, data }); return; }
    current = { name, data }; render(); wrap.classList.add('on');
    server.remotes.setMenuOpen(true);
    if (name === 'shop') server.remotes.openShop();
  }
  function close() {
    wrap.classList.remove('on'); current = null; server.remotes.setMenuOpen(false);
    const n = queue.shift(); if (n) setTimeout(() => open(n.name, n.data), 150);
  }
  wrap.addEventListener('pointerdown', (e) => { if (e.target === wrap) close(); });
  let idxPage = 1;
  function render() {
    const v = server.view(); if (!current || !v) return;
    const head = (title, color) => `<button class="block press close txt" aria-label="Close">X</button><h2 class="txt" style="color:#fff">${title}</h2>`;
    if (current.name === 'shop') {
      pop.innerHTML = head('Shop') + '<div class="cards">' + ['ray', 'boots', 'backpack'].map((id) => {
        const u = Config.upgrades[id], lvl = v.upgrades[id], max = lvl >= u.maxLevel, cost = max ? 0 : upgradeCost(id, lvl + 1);
        const effect = id === 'ray' ? `Bigger cubes, melt ${Math.round(u.lifeBonus * 100)}% slower, ice bridges +${u.bridgeBonus}s`
          : id === 'boots' ? `Run ${Math.round(u.speedBonus * 100)}% faster` : `Carry ${lvl + 1} cubes at once`;
        return `<div class="block card2"><h3>${u.name}</h3><div>Level ${lvl}</div><p>${effect}</p>
          <button class="block press buy txt ${!max && v.coins < cost ? 'cant' : ''}" data-buy="${id}">${max ? 'MAX' : COIN + fmt(cost)}</button></div>`;
      }).join('') + '</div>';
    } else if (current.name === 'index') {
      const pets = PetDefs.filter((p) => p.zone === idxPage);
      const found = pets.filter((p) => v.found[p.key]).length;
      pop.innerHTML = head('Index') + `<div class="idx-tabs">${World.zones.map((z) => `<button class="block press ${z.id === idxPage ? 'on' : ''}" data-page="${z.id}">${z.name}</button>`).join('')}</div>
        <div class="center" style="margin-bottom:8px">${found} / ${pets.length} found ${found === pets.length ? ' - page complete: +10% coins' : ' - complete the page for +10% coins forever'}</div>
        <div class="idx-grid">${pets.map((p) => `<div class="idx-cell ${v.found[p.key] ? '' : 'miss'}"><span class="tr" style="background:${Theme.tiers[p.tier]}"></span><img src="assets/sprites/${p.key}.webp" alt=""><span class="nm">${v.found[p.key] ? p.name : '???'}</span></div>`).join('')}</div>`;
      pets.forEach((p) => v.found[p.key] && seenFound.add(p.key));
    } else if (current.name === 'settings') {
      pop.innerHTML = head('Settings') + `
        <div class="settings-row"><span>Music</span><div class="toggle ${audio.music ? 'on' : ''}" data-tog="music"></div></div>
        <div class="settings-row"><span>Sound</span><div class="toggle ${audio.sfx ? 'on' : ''}" data-tog="sfx"></div></div>
        <div class="settings-row"><span>Reduced motion</span><div class="toggle ${Config.motion.reduced ? 'on' : ''}" data-tog="motion"></div></div>`;
    } else if (current.name === 'welcome') {
      const w = current.data;
      pop.innerHTML = `<h2 class="txt">Welcome back!</h2><div class="center">Your pets earned</div><div class="big txt">${COIN.replace('<svg', '<svg style="width:34px;height:34px;vertical-align:-6px"')} ${fmt(w.coins)}</div>
        <div class="center" style="margin:4px 0 10px">while you were away${w.capped ? ' (pens hold up to 8 hours of coins)' : ''}</div>
        <button class="block press buy txt" data-collect="1">Collect</button>`;
    } else if (current.name === 'gift') {
      const g = current.data;
      pop.innerHTML = `<h2 class="txt">Daily gift</h2><div class="big txt">${COIN.replace('<svg', '<svg style="width:34px;height:34px;vertical-align:-6px"')} ${fmt(g.coins)}</div>
        <div class="center" style="margin:4px 0 10px">Day ${g.streak} streak. It waits for you: miss a day and the streak just pauses.</div>
        <button class="block press buy txt" data-ok="1">Yay!</button>`;
    } else if (current.name === 'superfreeze') {
      pop.innerHTML = head('Super Freeze') + `<div class="center" style="margin-bottom:10px">A deep-blue cube that never melts until you reach your pen.<br>Prototype only: no real purchase happens.</div>
        <button class="block press buy txt" data-sf="${current.data.id}" style="--face:#4e7dff;--lip-c:#2440a6">${ROBUX} ${Config.monetization.superFreeze.robux} (mock buy)</button>
        <div class="center" style="margin-top:8px;font-size:14px;color:#4a4270">Or zap it again for free.</div>`;
    }
    pop.querySelector('.close')?.addEventListener('click', () => { audio.play('click'); close(); });
    pop.querySelectorAll('[data-buy]').forEach((b) => b.addEventListener('click', () => { audio.play('click'); server.remotes.buyUpgrade(b.dataset.buy); }));
    pop.querySelectorAll('[data-page]').forEach((b) => b.addEventListener('click', () => { idxPage = +b.dataset.page; render(); }));
    pop.querySelectorAll('[data-tog]').forEach((b) => b.addEventListener('click', () => {
      const k = b.dataset.tog;
      if (k === 'music') audio.setMusic(!audio.music); else if (k === 'sfx') audio.setSfx(!audio.sfx); else Config.motion.reduced = !Config.motion.reduced;
      audio.play('click'); render();
    }));
    pop.querySelector('[data-collect]')?.addEventListener('click', () => { server.remotes.collectWelcome(); close(); });
    pop.querySelector('[data-ok]')?.addEventListener('click', () => close());
    pop.querySelector('[data-sf]')?.addEventListener('click', (e) => { server.remotes.buySuperFreezeMock(e.currentTarget.dataset.sf); close(); });
  }
  server.on('upgraded', ({ id }) => { audio.play('buy'); if (current?.name === 'shop') render(); });
  server.on('welcomeBack', (w) => open('welcome', w));
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
  function place(el, pos) {
    let x = pos.x, y = pos.y;
    const r = el.getBoundingClientRect(), w = r.width || 160, h = r.height || 90;
    // world prompts never sit on a HUD item: push right of the tiles/coins, below the goal bar
    for (const [kind, e] of [['side', tiles], ['side', coinsEl], ['top', goal]]) {
      const hr = e.getBoundingClientRect();
      const box = { l: x - w / 2, r: x + w / 2, t: y - h, b: y };
      if (box.r > hr.left && box.l < hr.right && box.b > hr.top && box.t < hr.bottom) {
        if (kind === 'top') y = hr.bottom + h + 8; else x = hr.right + w / 2 + 10;
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
    else { const c = iceBridgeCenter(); text = 'Freeze an ice bridge'; sub = 'Glowing spot'; pos = client.worldToScreen(c.x, 3, c.z); }
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
        el.innerHTML = `<button class="block press txt">${ROBUX} ${Config.monetization.superFreeze.robux} Super Freeze</button>`;
        el.querySelector('button').addEventListener('click', () => { audio.play('click'); open('superfreeze', { id: w.id }); });
        prompts.appendChild(el); offerEls.set(w.id, el);
      }
    }
    for (const [id, el] of offerEls) {
      const w = v.wild.get(id);
      if (!w || !w.offer) { el.remove(); offerEls.delete(id); continue; }
      const p = client.worldToScreen(w.x + 3, 2.5, w.z);
      if (p) { el.style.display = 'block'; place(el, p); } else el.style.display = 'none';
    }
  }

  // ---------------- goal bar (three goals: short, medium, long) ----------------
  function goalFor(v) {
    const need = zoneById[2].gatePets;
    if (!v.forestUnlocked) return { text: `Unlock Pine Forest: ${v.pets.length} / ${need} pets in your pen`, frac: v.pets.length / need };
    for (const z of World.zones) {
      const pets = PetDefs.filter((p) => p.zone === z.id), found = pets.filter((p) => v.found[p.key]).length;
      if (found < pets.length) return { text: `Fill the ${z.name} page: ${found} / ${pets.length} (+10% coins)`, frac: found / pets.length };
    }
    return { text: 'Every page full! Sunny Beach is next', frac: 1 };
  }

  function update(v) {
    if (!v) return;
    if (Math.floor(v.coins) !== lastCoins) { if (v.coins > lastCoins) { coinsEl.classList.remove('pop'); void coinsEl.offsetWidth; coinsEl.classList.add('pop'); } lastCoins = Math.floor(v.coins); }
    coinN.textContent = fmt(v.coins); coinR.textContent = `+${rate(v.income)}/s`;
    const g = goalFor(v); goalT.textContent = g.text; goalFill.style.width = Math.max(6, g.frac * 100) + '%'; // never starts empty
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
