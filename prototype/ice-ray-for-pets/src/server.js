// SERVER: everything that decides something. In Roblox each block below becomes a service in
// ServerScriptService (named in the comment). The client only sends intent through `remotes`
// and plays effects for the events the server emits.
import {
  Config, Analytics, PetDefs, World, tierByName, petByKey, zoneById, upgradeCost, petIncome, mulberry32, isRegular,
} from './config.js';
import { zoneAt, inHub, inPen, penCenter, meltRate, walkable, pathWalkable, dist, iceBridgeCenter, nearestBank, onBridge } from './world.js';

const TIER_ORDER = Config.tiers.map((t) => t.name);
const rankOf = (tier) => tierByName[tier].rank;

export function createServer(opts = {}) {
  const rng = mulberry32(opts.seed ?? (Date.now() & 0xffffffff));
  const listeners = {};
  const S = {
    time: 0,                 // game seconds (sped up for the bot)
    clockOffsetMs: 0,        // debug "skip time"
    player: null,
    wild: new Map(),         // id -> wild or dazed pet
    nextId: 1,
    pity: {},                // zone -> { tier -> misses }
    respawnAt: {},           // zone -> game time of next spawn
    chill: { next: Config.bigChill.everySeconds, warned: false, until: -1 },
    iceBridgeUntil: -1,
    boards: null, boardsAt: -1e9,
    rivals: null,
    wiping: false,
    lastSaveAt: 0,
    rate: { calls: [] },
    dropped: 0,
    session: { start: 0 },
  };

  // ---------- events to the client (RemoteEvents FireClient) ----------
  function emit(name, data) { (listeners[name] || []).forEach((fn) => fn(data)); (listeners['*'] || []).forEach((fn) => fn(name, data)); }
  function on(name, fn) { (listeners[name] ||= []).push(fn); }
  const nowMs = () => Date.now() + S.clockOffsetMs;

  // ---------- Analytics wrapper (AnalyticsService, one module, server only) ----------
  // SERVER
  const AnalyticsSvc = {
    funnel(name) {
      const d = S.player?.data; if (!d) return;
      const step = Analytics.funnel.find((s) => s.name === name);
      if (!step || d.funnel[name]) return;
      d.funnel[name] = true;
      console.log(`[analytics] funnel step ${step.step} ${name}`);
      emit('analytics', { kind: 'funnel', name, step: step.step });
    },
    event(name, fields = {}) {
      const allowed = Analytics.events[name];
      if (!allowed) return; // unknown names never reach AnalyticsService
      const clean = {};
      for (const k of allowed) if (k in fields) clean[k] = fields[k];
      console.log(`[analytics] event ${name}`, JSON.stringify(clean));
      emit('analytics', { kind: 'event', name, fields: clean });
    },
  };

  // ---------- DataService (pcall + retries in Roblox; localStorage here) ----------
  // SERVER
  function defaults() {
    return {
      version: Config.version, coins: 0, pets: [], nextPetId: 1, upgrades: { ray: 1, boots: 1, backpack: 1, pen: 1 },
      found: {}, stats: { frozen: 0, banked: 0, melts: 0, coinsEarned: 0 },
      rarest: { rank: 0, key: null, at: 0 }, week: { id: '', coins: 0 },
      lastSeen: 0, welcome: null, gift: { lastDay: '', streak: 0 }, funnel: {}, forestUnlocked: false,
      createdAt: 0,
      superCubes: [], // bought Super Freeze cubes not yet banked: saved with the purchase, back on your back after a rejoin
      lastBest: null, // the best pet you banked last session, shown in the welcome back (end on a high, on the return)
    };
  }
  // every field is type- and range-checked on load, so a damaged or edited save can't crash the join
  // or carry impossible values (the Roblox DataService does the same before the player earns anything)
  const num = (v, lo, hi, dflt = lo) => (typeof v === 'number' && isFinite(v) ? Math.min(hi, Math.max(lo, v)) : dflt);
  const int = (v, lo, hi, dflt = lo) => Math.floor(num(v, lo, hi, dflt));
  const str = (v, max, dflt = '') => (typeof v === 'string' && v.length <= max ? v : dflt);
  const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
  const knownPose = (v) => (typeof v === 'string' && Object.hasOwn(Config.poses, v) && v !== 'loop' ? v : 'idle');
  const knownMut = (v) => (typeof v === 'string' && Object.hasOwn(Config.mutations, v) ? v : null);
  function sanitize(raw) {
    const r = obj(raw), d = defaults();
    d.coins = num(r.coins, 0, 1e15);
    for (const id of Object.keys(d.upgrades)) d.upgrades[id] = int(obj(r.upgrades)[id], 1, Config.upgrades[id].maxLevel, 1);
    // pets: every one has an id and an "in the pen" flag; never more in the pen than it has slots
    d.nextPetId = int(r.nextPetId, 1, 1e9, 1);
    const seen = new Set();
    d.pets = (Array.isArray(r.pets) ? r.pets : []).filter((x) => x && Object.hasOwn(petByKey, x.key)).slice(0, Config.pen.storageMax).map((x) => {
      let id = typeof x.id === 'string' && x.id.length <= 12 && !seen.has(x.id) ? x.id : null;
      if (!id) id = 'q' + d.nextPetId++;
      seen.add(id);
      return { id, key: x.key, pose: knownPose(x.pose), mut: knownMut(x.mut), at: num(x.at, 0, 1e15), eq: x.eq === true };
    });
    if (!d.pets.some((x) => x.eq)) equipBestIn(d); // an older save had no flags: the best pets go in the pen
    let room = penSlots(d); for (const x of d.pets) if (x.eq && room-- <= 0) x.eq = false;
    for (const [k, v] of Object.entries(obj(r.found))) if (Object.hasOwn(petByKey, k) && v === true) d.found[k] = true;
    for (const k of Object.keys(d.stats)) d.stats[k] = num(obj(r.stats)[k], 0, 1e15);
    const ra = obj(r.rarest); d.rarest = { rank: int(ra.rank, 0, 7), key: Object.hasOwn(petByKey, ra.key) ? ra.key : null, at: num(ra.at, 0, 1e15) };
    const wk = obj(r.week); d.week = { id: str(wk.id, 10), coins: num(wk.coins, 0, Config.leaderboards.limits.weekCoins) };
    d.lastSeen = num(r.lastSeen, 0, 1e15);
    const wb = r.welcome && typeof r.welcome === 'object' ? r.welcome : null;
    d.welcome = wb ? { coins: Math.floor(num(wb.coins, 0, 1e15)), awaySeconds: num(wb.awaySeconds, 0, 1e9), capped: wb.capped === true, best: typeof wb.best === 'string' && Object.hasOwn(petByKey, wb.best) ? wb.best : null } : null;
    const g = obj(r.gift); d.gift = { lastDay: str(g.lastDay, 10), streak: int(g.streak, 0, Config.dailyGift.streakMax) };
    for (const st of Analytics.funnel) if (obj(r.funnel)[st.name] === true) d.funnel[st.name] = true;
    d.forestUnlocked = r.forestUnlocked === true;
    d.createdAt = num(r.createdAt, 0, 1e15);
    d.lastBest = typeof r.lastBest === 'string' && Object.hasOwn(petByKey, r.lastBest) ? r.lastBest : null;
    d.superCubes = (Array.isArray(r.superCubes) ? r.superCubes : []).filter((c) => c && Object.hasOwn(petByKey, c.key)).slice(0, 5)
      .map((c) => ({ key: c.key, zone: petByKey[c.key].zone, pose: knownPose(c.pose), mut: knownMut(c.mut) }));
    return d;
  }
  function load() {
    let raw = null;
    try { raw = JSON.parse(localStorage.getItem(Config.saveKey) || 'null'); } catch { raw = null; }
    const d = sanitize(raw);
    if (!raw) d.createdAt = nowMs();
    return { data: d, isNew: !raw };
  }
  function save(reason) {
    if (S.wiping || !S.player) return;
    try { localStorage.setItem(Config.saveKey, JSON.stringify(S.player.data)); } catch { /* storage blocked: play on */ }
    S.lastSaveAt = S.time;
    if (reason) emit('saved', reason);
  }

  // ---------- calendar helpers ----------
  function dayId(ms) { return new Date(ms).toISOString().slice(0, 10); }
  function weekId(ms) {
    const d = new Date(ms); const day = (d.getUTCDay() + 7 - Config.leaderboards.weeklyResetDay) % 7;
    const start = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - day);
    return new Date(start).toISOString().slice(0, 10);
  }

  // ---------- PenService ----------
  // SERVER
  function penSlots(d = S.player.data) { return Config.pen.baseSlots + Config.upgrades.pen.slotsPerLevel * (d.upgrades.pen - 1); }
  const petEarn = (x) => petIncome(petByKey[x.key], x.pose, x.mut);
  function equippedCount(d = S.player.data) { let n = 0; for (const x of d.pets) if (x.eq) n++; return n; }
  function equipBestIn(d) {
    const best = new Set([...d.pets].sort((a, b) => petEarn(b) - petEarn(a)).slice(0, penSlots(d)));
    for (const x of d.pets) x.eq = best.has(x);
  }
  function fillEmptySlots(d) { // new slots (Pen upgrade) take the best pets from Storage; your own picks stay
    let room = penSlots(d) - equippedCount(d); if (room <= 0) return;
    for (const x of [...d.pets].filter((y) => !y.eq).sort((a, b) => petEarn(b) - petEarn(a))) { if (room-- <= 0) break; x.eq = true; }
  }
  function completedPages(d) {
    let n = 0;
    for (const z of World.zones) if (PetDefs.filter((p) => p.zone === z.id && isRegular(p)).every((p) => d.found[p.key])) n++;
    return n;
  }
  function incomePerSecond(d = S.player.data) {
    let sum = 0;
    for (const p of d.pets) if (p.eq) sum += petIncome(petByKey[p.key], p.pose, p.mut); // only the pen's pets earn
    return sum * (1 + 0.1 * completedPages(d));
  }
  function addCoins(n) {
    const d = S.player.data;
    d.coins += n; d.stats.coinsEarned += n;
    const w = weekId(nowMs());
    if (d.week.id !== w) d.week = { id: w, coins: 0 }; // calendar reset, nothing else is lost
    d.week.coins += n;
  }
  function checkWelcomeBack() {
    // the grant and the claim stamp are written in one save, so a quick rejoin can't pay twice
    const d = S.player.data, now = nowMs();
    if (!d.welcome && d.lastSeen > 0) {
      const away = (now - d.lastSeen) / 1000;
      const inc = incomePerSecond(d);
      if (away >= Config.away.minSeconds && inc > 0) {
        const capped = Math.min(away, Config.away.capSeconds);
        d.welcome = { coins: Math.floor(inc * capped * Config.away.rate), awaySeconds: Math.round(away), capped: away > Config.away.capSeconds, best: d.lastBest };
      }
    }
    d.lastSeen = now;
    save('welcome-stamp');
    if (d.welcome) emit('welcomeBack', d.welcome);
  }

  // ---------- daily gift (waits for you; streak pauses, never drops) ----------
  // SERVER
  function giftState() {
    const d = S.player.data; const today = dayId(nowMs());
    const locked = d.stats.banked === 0; // the first minute is about the core loop; the gift box opens after your first bank
    const ready = !locked && d.gift.lastDay < today;
    const nextStreak = Math.min(Config.dailyGift.streakMax, d.gift.streak + 1);
    const base = Math.max(Config.dailyGift.baseCoins, incomePerSecond() * 60 * Config.dailyGift.incomeMinutes);
    const coins = Math.round(base * (1 + Config.dailyGift.streakBonus * (nextStreak - 1)));
    return { ready, locked, streak: d.gift.streak, nextStreak, coins };
  }

  // ---------- WildPetSpawner (spawn rolls, pity, respawn) ----------
  // SERVER
  function shownOdds(zone) {
    const p = S.pity[zone] ||= {};
    const pc = Config.spawner.pity;
    const w = Config.tiers.map((t) => {
      let boost = 1;
      if (t.rank >= 3) {
        const grace = (100 / t.odds) * pc.graceFactor;
        boost = Math.min(pc.maxBoost, 1 + Math.max(0, (p[t.name] || 0) - grace) * pc.perMiss * (100 / t.odds) / 100);
      }
      return t.odds * boost;
    });
    const total = w.reduce((a, b) => a + b, 0);
    return Object.fromEntries(Config.tiers.map((t, i) => [t.name, (w[i] / total) * 100]));
  }
  function rollTier(zone) {
    const odds = shownOdds(zone);
    let r = rng() * 100, tier = 'Common';
    for (const t of TIER_ORDER) { if (r < odds[t]) { tier = t; break; } r -= odds[t]; }
    const p = S.pity[zone];
    for (const t of Config.tiers) if (t.rank >= 3) p[t.name] = rankOf(tier) >= t.rank ? 0 : (p[t.name] || 0) + 1;
    return tier;
  }
  function spawnPet(zone, at, forcedKey) {
    const sp = Config.spawner, near = at === 'near';
    let def;
    if (forcedKey) def = petByKey[forcedKey];
    else if (near) {
      // near-band keepers are Commons or Uncommons (60:25), and they don't touch pity
      const tier = rng() < 60 / 85 ? 'Common' : 'Uncommon';
      const pool = PetDefs.filter((p) => p.zone === zone && p.tier === tier);
      def = pool[Math.floor(rng() * pool.length)];
    } else {
      const tier = rollTier(zone);
      const pool = PetDefs.filter((p) => p.zone === zone && p.tier === tier);
      def = pool[Math.floor(rng() * pool.length)];
    }
    let pos = at && !near ? at : null;
    const z = zoneById[zone], rare = rankOf(def.tier) >= 3;
    for (let i = 0; !pos && i < 30; i++) {
      const zMax = near ? sp.near[zone][1] : z.zMax - 10;
      // Rare and up only in the far half, so the pets worth most have the longest run home
      const zMin = near ? sp.near[zone][0] : rare ? Math.max(sp.farZMin[zone], (z.zMin + z.zMax) / 2) : sp.farZMin[zone];
      const xSpan = near ? 30 : (World.bounds.xMax - World.bounds.xMin - 12);
      const c = { x: near ? -15 + rng() * xSpan : World.bounds.xMin + 6 + rng() * xSpan, z: zMin + rng() * (zMax - zMin) };
      if (walkable(c.x, c.z, { iceBridgeActive: false, forestUnlocked: true }) && (!S.player || dist(c, S.player.pos) > 8)) pos = c;
    }
    if (!pos) return null;
    const id = 'p' + S.nextId++;
    const loopIdx = Math.floor(rng() * Config.poses.loop.length);
    const action = Config.poses.loop[loopIdx];
    S.wild.set(id, {
      id, key: def.key, zone, x: pos.x, z: pos.z, state: 'wild',
      loopIdx, action, actionEnd: S.time + rng() * Config.poses[action].seconds,
      wanderTo: null, dazedUntil: 0, pose: null, mut: null, offer: false, offered: false, superUsed: false, near,
    });
    emit('wildSpawned', { id });
    return id;
  }
  function nearCount(zone) {
    const [a, b] = Config.spawner.near[zone]; let n = 0;
    for (const w of S.wild.values()) if (w.zone === zone && w.state === 'wild' && w.z >= a && w.z <= b) n++;
    return n;
  }
  function tickSpawner() {
    for (const z of World.zones) {
      const count = [...S.wild.values()].filter((w) => w.zone === z.id).length;
      if (count < Config.spawner.maxPerZone && S.time >= (S.respawnAt[z.id] ?? 0)) {
        spawnPet(z.id, nearCount(z.id) < Config.spawner.nearCount ? 'near' : undefined);
        S.respawnAt[z.id] = S.time + Config.spawner.respawnSeconds;
      }
    }
  }
  function tickWild(dt) {
    for (const w of S.wild.values()) {
      if (w.state === 'dazed') {
        // no hidden timer on a paid offer (Game Plan 15): it only goes when you walk off or zap the pet
        if (w.offer && S.player && dist(w, S.player.pos) > Config.monetization.superFreeze.walkAwayStuds) { w.offer = false; w.dazedUntil = Math.max(w.dazedUntil, S.time); emit('offerGone', { id: w.id }); }
        if (!w.offer && S.time >= w.dazedUntil) { w.state = 'wild'; w.pose = null; }
        continue;
      }
      if (S.player?.zap?.target === w.id) w.actionEnd += dt * (1 - Config.poses.zapSlowdown); // half speed while held
      if (S.time >= w.actionEnd) {
        const P = Config.poses;
        let next;
        if (rng() < P.sneezeChance) next = 'sneeze';
        else { w.loopIdx = (w.loopIdx + 1) % P.loop.length; next = P.loop[w.loopIdx]; }
        w.action = next; w.actionEnd = S.time + P[next].seconds;
        if (next === 'idle' && rng() < 0.5) {
          const t = { x: w.x + (rng() - 0.5) * 10, z: w.z + (rng() - 0.5) * 10 };
          if (walkable(t.x, t.z, { forestUnlocked: true }) && zoneAt(t.x, t.z) === w.zone) w.wanderTo = t;
        }
      }
      if (w.wanderTo && w.action === 'idle') {
        const d = dist(w, w.wanderTo); const step = 2 * dt;
        if (d < step) w.wanderTo = null; else { w.x += ((w.wanderTo.x - w.x) / d) * step; w.z += ((w.wanderTo.z - w.z) / d) * step; }
      }
    }
  }

  // ---------- player state helpers ----------
  function capacity() { return Config.upgrades.backpack && S.player.data.upgrades.backpack; }
  function walkSpeed() {
    const d = S.player.data;
    const boots = 1 + Config.upgrades.boots.speedBonus * (d.upgrades.boots - 1);
    const extra = Math.max(0, S.player.carrying.length - 1);
    return Config.player.walkSpeed * boots * Math.max(0.5, 1 - Config.upgrades.backpack.slowPerExtraCube * extra);
  }
  function zoneOpen(zone) { return zone !== 2 || S.player.data.forestUnlocked; }
  function worldState() { return { iceBridgeActive: S.time < S.iceBridgeUntil, forestUnlocked: S.player.data.forestUnlocked }; }
  function cubeLifeMax(def) {
    return tierByName[def.tier].cubeLife * (1 + Config.upgrades.ray.lifeBonus * (S.player.data.upgrades.ray - 1));
  }
  function rateOk() {
    const t = S.time * 1000; // game time, so a sped-up bot is limited like a real player
    S.rate.calls = S.rate.calls.filter((c) => t - c < 1000);
    if (S.rate.calls.length >= Config.player.rateLimitPerSecond) { S.dropped++; return false; }
    S.rate.calls.push(t); return true;
  }

  // ---------- FreezeService (prompt validation, pose capture) ----------
  // SERVER
  function beginZap(target) {
    if (!S.player || !rateOk() || typeof target !== 'string' || target.length > 16) return;
    const p = S.player;
    if (S.time - p.lastFreezeAt < Config.player.freezeCooldown) return;
    if (target === 'bridge') {
      if (dist(p.pos, iceBridgeCenter(p.pos)) > Config.player.freezeRange + 2) return;
      p.zap = { target, start: S.time, hold: Config.player.freezeHold };
    } else if (target === 'gift') {
      if (dist(p.pos, World.giftBox) > Config.player.freezeRange) return;
      p.zap = { target, start: S.time, hold: Config.player.interactHold };
    } else if (target === 'gate') {
      if (p.data.forestUnlocked || dist(p.pos, gatePoint()) > Config.player.freezeRange) return;
      p.zap = { target, start: S.time, hold: Config.player.interactHold };
    } else {
      const w = S.wild.get(target);
      if (!w || dist(p.pos, w) > Config.player.freezeRange + 1 || !zoneOpen(w.zone)) return;
      if (p.carrying.length >= capacity()) { notYet('Backpack full', target); return; }
      p.zap = { target, start: S.time, hold: w.state === 'dazed' ? Config.player.refreezeHold : Config.player.freezeHold };
      AnalyticsSvc.funnel('first_zap');
    }
    emit('zapStarted', { target, hold: p.zap.hold });
  }
  function cancelZap() { if (S.player?.zap) { emit('zapCancelled', { target: S.player.zap.target }); S.player.zap = null; } }
  function endZap(target) {
    const p = S.player;
    if (!p || !rateOk() || !p.zap || p.zap.target !== target) return;
    if (S.time - p.zap.start < p.zap.hold - 0.1) return; // held too short: the client is early or lying
    p.zap = null; p.lastFreezeAt = S.time;
    if (target === 'bridge') {
      if (dist(p.pos, iceBridgeCenter(p.pos)) > Config.player.freezeRange * 1.5) return;
      const secs = Config.bridge.baseSeconds + Config.upgrades.ray.bridgeBonus * (p.data.upgrades.ray - 1);
      S.iceBridgeUntil = S.time + secs;
      emit('bridge', { until: S.iceBridgeUntil, seconds: secs });
      return;
    }
    if (target === 'gift') { claimGift(); return; }
    if (target === 'gate') { if (dist(p.pos, gatePoint()) <= Config.player.freezeRange * 1.3) unlockForest(); return; }
    const w = S.wild.get(target);
    if (!w || dist(p.pos, w) > Config.player.freezeRange * 1.3 || p.carrying.length >= capacity() || !zoneOpen(w.zone)) return;
    const def = petByKey[w.key];
    const pose = w.state === 'dazed' ? w.pose : w.action; // the pose at the moment the hold finished
    const mut = w.state === 'dazed' ? w.mut : (S.time < S.chill.until ? 'Frosty' : null);
    const lifeMax = cubeLifeMax(def);
    const cube = {
      uid: 'c' + S.nextId++, key: w.key, zone: w.zone, pose, mut, life: lifeMax, lifeMax,
      superFrozen: false, superUsed: w.superUsed, offered: !!w.offered, since: S.time, leftHub: false,
    };
    S.wild.delete(target);
    if (w.offer) emit('offerGone', { id: target });
    p.carrying.push(cube);
    p.data.stats.frozen++;
    AnalyticsSvc.funnel('first_freeze');
    emit('frozen', { petId: target, cube });
  }

  // ---------- CarryService (melt ticking on the server, shade, Super Freeze) ----------
  // SERVER
  function tickCarry(dt) {
    const p = S.player; if (!p.carrying.length) return;
    const chill = S.time < S.chill.until;
    const rate = meltRate(p.pos.x, p.pos.z);
    for (const c of [...p.carrying]) {
      if (c.superFrozen || chill) continue;
      c.life -= rate * dt;
      if (c.life <= 0) melt(c);
    }
  }
  function melt(c) {
    const p = S.player;
    p.carrying = p.carrying.filter((x) => x !== c);
    const id = 'p' + S.nextId++;
    const def = petByKey[c.key];
    const a = rng() * Math.PI * 2;
    const w = {
      id, key: c.key, zone: c.zone, x: p.pos.x + Math.cos(a) * 3, z: p.pos.z + Math.sin(a) * 3, state: 'dazed',
      loopIdx: 0, action: 'idle', actionEnd: S.time + 1, wanderTo: null,
      dazedUntil: S.time + Config.dazedSeconds, pose: c.pose, mut: c.mut, offer: false, offered: c.offered, superUsed: c.superUsed,
    };
    S.wild.set(id, w);
    p.data.stats.melts++;
    const home = penCenter();
    AnalyticsSvc.event('cube_melted', { pet: c.key, tier: def.tier, zone: c.zone, studsFromHome: Math.round(dist(p.pos, home)) });
    // Super Freeze offer: Rare and up, at most once per run, a small world button, no countdown
    if (rankOf(def.tier) >= rankOf(Config.monetization.superFreeze.minTier) && !c.superUsed && !c.offered) {
      w.offer = true; w.offered = true; // at most once per run: the flag rides along through a free re-freeze
      AnalyticsSvc.event('offer_shown', { offer: 'super_freeze', pet: c.key, tier: def.tier });
    }
    emit('melted', { cubeUid: c.uid, petId: id, offer: w.offer });
  }
  // MonetizationService: in Roblox this is ProcessReceipt for the Super Freeze developer product.
  // SERVER
  function buySuperFreezeMock(petId) {
    const p = S.player;
    if (!p || !rateOk() || typeof petId !== 'string') return;
    const w = S.wild.get(petId);
    if (!w || w.state !== 'dazed' || !w.offer || dist(p.pos, w) > Config.monetization.superFreeze.walkAwayStuds) return;
    if (p.carrying.length >= capacity()) return;
    const def = petByKey[w.key];
    const cube = superCube({ key: w.key, zone: w.zone, pose: w.pose, mut: w.mut });
    S.wild.delete(petId);
    p.carrying.push(cube);
    p.data.superCubes.push({ key: cube.key, zone: cube.zone, pose: cube.pose, mut: cube.mut });
    AnalyticsSvc.event('offer_bought', { offer: 'super_freeze', robux: Config.monetization.superFreeze.robux });
    save('purchase'); // the paid cube is in the save before PurchaseGranted, so leaving or a crash never loses it
    emit('offerGone', { id: petId });
    emit('frozen', { petId, cube, superFrozen: true, tier: def.tier });
  }

  function superCube(r) {
    return { uid: 'c' + S.nextId++, key: r.key, zone: r.zone, pose: r.pose, mut: r.mut, life: 1, lifeMax: 1,
      superFrozen: true, superUsed: true, offered: true, since: S.time, leftHub: true };
  }

  // ---------- banking (PenService) ----------
  // SERVER
  function bankCubes() {
    const p = S.player, d = p.data;
    const banked = [];
    for (const c of p.carrying) {
      if (d.pets.length >= Config.pen.storageMax) { notYet('Storage full'); break; }
      const def = petByKey[c.key];
      if (c.superFrozen) { const i = d.superCubes.findIndex((r) => r.key === c.key && r.pose === c.pose && r.mut === c.mut); if (i >= 0) d.superCubes.splice(i, 1); }
      const eq = equippedCount(d) < penSlots(d); // a free pen slot: it starts earning; otherwise it waits in Storage
      d.pets.push({ id: 'q' + d.nextPetId++, key: c.key, pose: c.pose, mut: c.mut, at: nowMs(), eq });
      const firstTime = !d.found[c.key];
      d.found[c.key] = true;
      d.stats.banked++;
      if (rankOf(def.tier) > d.rarest.rank) d.rarest = { rank: rankOf(def.tier), key: c.key, at: nowMs() };
      if (rankOf(def.tier) >= (p.bestRank || 0)) { p.bestRank = rankOf(def.tier); d.lastBest = c.key; } // this session's best so far
      AnalyticsSvc.event('pet_banked', { pet: c.key, tier: def.tier, pose: c.pose, zone: c.zone, carrySeconds: Math.round(S.time - c.since) });
      AnalyticsSvc.funnel('first_carry_home'); // a cube frozen right by the hub still counts as carried home, before the bank
      AnalyticsSvc.funnel('first_bank');
      if (rankOf(def.tier) >= 3) AnalyticsSvc.funnel('first_rare_pet');
      banked.push({ cube: c, income: petIncome(def, c.pose, c.mut), firstTime, stored: !eq });
    }
    p.carrying = p.carrying.slice(banked.length);
    if (!banked.length) return;
    save('bank');
    emit('banked', { banked, income: incomePerSecond() });
  }

  // equip by hand, or Equip best (the server checks the pet is yours and the pen has room)
  function equipPet(id, on) {
    const p = S.player; if (!p || !rateOk() || typeof id !== 'string' || id.length > 12) return;
    const x = p.data.pets.find((y) => y.id === id); if (!x) return;
    if (on === true && !x.eq) { if (equippedCount() >= penSlots()) { notYet('Pen full: put one in Storage first', 'pets'); return; } x.eq = true; }
    else if (on === false && x.eq) x.eq = false;
    else return;
    save('equip'); emit('petsChanged', { income: incomePerSecond() });
  }
  function equipBest() {
    const p = S.player; if (!p || !rateOk()) return;
    equipBestIn(p.data); save('equip'); emit('petsChanged', { income: incomePerSecond() });
  }
  // the Forest gate opens with coins (owner 2026-10-30); hold the prompt at the gate
  function gatePoint() { return { x: 0, z: World.gate.z - 2.5 }; }
  function unlockForest() {
    const p = S.player, d = p.data, price = zoneById[2].gateCoins;
    if (d.forestUnlocked) return;
    if (d.coins < price) { notYet(`Need ${Math.ceil(price - d.coins)} more coins`, 'gate'); return; }
    d.coins -= price; d.forestUnlocked = true;
    AnalyticsSvc.funnel('first_coins_spent');
    save('unlock'); // paid and opened in the same save
    emit('zoneUnlocked', { zone: 2, price });
  }

  // ---------- ShopService ----------
  // SERVER
  function buyUpgrade(id) {
    const p = S.player;
    if (!p || !rateOk() || typeof id !== 'string' || !Object.hasOwn(Config.upgrades, id)) return;
    const lvl = p.data.upgrades[id];
    if (lvl >= Config.upgrades[id].maxLevel) { notYet('Max level', id); return; }
    const cost = upgradeCost(id, lvl + 1);
    if (p.data.coins < cost) { emit('notYet', { reason: `Need ${Math.ceil(cost - p.data.coins)} more`, at: id }); return; } // a button press: always answered
    p.data.coins -= cost; p.data.upgrades[id] = lvl + 1;
    if (id === 'pen') fillEmptySlots(p.data);
    AnalyticsSvc.funnel('first_coins_spent');
    save('upgrade');
    emit('upgraded', { id, level: lvl + 1, cost });
  }
  function claimGift() {
    const g = giftState(); const d = S.player.data;
    if (!g.ready) { notYet(g.locked ? 'Bank a pet first' : 'Next gift tomorrow', 'gift'); return; }
    d.gift = { lastDay: dayId(nowMs()), streak: g.nextStreak };
    addCoins(g.coins);
    save('gift'); // grant and claim stamp in the same save
    emit('giftClaimed', { coins: g.coins, streak: g.nextStreak });
  }
  function collectWelcome() {
    const d = S.player?.data; if (!d || !d.welcome || !rateOk()) return;
    const coins = d.welcome.coins;
    addCoins(coins); d.welcome = null;
    save('welcome-collect'); // grant and clear in the same save
    emit('welcomeCollected', { coins });
  }

  // ---------- EventService (Big Chill) ----------
  // SERVER
  function tickChill() {
    const c = S.chill, B = Config.bigChill;
    if (!c.warned && S.time >= c.next - B.warnSeconds) { c.warned = true; emit('chillWarn', { inSeconds: Math.max(0, c.next - S.time) }); }
    if (S.time >= c.next) {
      c.until = S.time + B.durationSeconds; c.next = S.time + B.everySeconds; c.warned = false;
      emit('chillStart', { seconds: B.durationSeconds });
    }
    if (c.until > 0 && S.time >= c.until) { c.until = -1; emit('chillEnd', {}); }
  }

  // ---------- LeaderboardService (OrderedDataStore in Roblox; fake rivals here) ----------
  // SERVER
  const RIVAL_NAMES = ['SnowySam', 'PixelPanda', 'MiloTheBrave', 'LunaSkies', 'BlockyBen', 'FrostByte', 'CocoaCat',
    'JellyJam', 'RocketRae', 'MochiBun', 'SkyDiver22', 'PebblesPlays', 'NovaNinja', 'BubbleTeaTom', 'ChillPenguin',
    'Maple_Max', 'StarlightSue', 'TurboTurtle', 'WaffleWes', 'ZiggyZoom'];
  function makeRivals() {
    const r = mulberry32(99);
    return RIVAL_NAMES.map((name, i) => ({
      name: i === 7 ? null : name, // one player hidden by privacy settings: shown without a name
      frozen: Math.floor(20 + r() * 900), rarest: [3, 3, 4, 4, 4, 5, 3, 2, 4, 5, 3, 4, 6, 3, 4, 2, 4, 5, 3, 4][i],
      rarestAt: i, weekCoins: Math.floor(500 + r() * 60000),
    }));
  }
  // a score is written only after it's clamped to what is possible (OrderedDataStore needs an integer
  // under 2^63 anyway): non-numbers become 0, and nobody freezes more than 1 pet a second since joining
  function boardScore(v, max) { return typeof v === 'number' && isFinite(v) && v > 0 ? Math.floor(Math.min(v, max)) : 0; }
  function refreshBoards() {
    const wk = weekId(nowMs());
    if (!S.rivals || S.rivalsWeek !== wk) { S.rivals = makeRivals(); S.rivalsWeek = wk; } // every board week starts fresh
    for (const rv of S.rivals) { rv.frozen += Math.floor(rng() * 3); rv.weekCoins += Math.floor(rng() * 400); }
    const d = S.player.data, L = Config.leaderboards.limits;
    const ageSeconds = Math.max(0, (nowMs() - (d.createdAt || nowMs())) / 1000);
    const me = {
      name: opts.displayName || 'You', me: true,
      frozen: boardScore(d.stats.frozen, Math.min(L.frozen, Math.ceil(ageSeconds * L.freezesPerSecond) + 1)),
      rarest: boardScore(d.rarest.rank, 7), rarestAt: d.rarest.at,
      weekCoins: d.week.id === wk ? boardScore(d.week.coins, L.weekCoins) : 0,
    };
    const all = [...S.rivals, me];
    const tierName = (rank) => Config.tiers.find((t) => t.rank === rank)?.name ?? '-';
    const build = (id, score, label) => {
      const sorted = [...all].sort((a, b) => score(b) - score(a) || (a.rarestAt - b.rarestAt));
      const rows = sorted.slice(0, Config.leaderboards.size).map((e, i) => ({ rank: i + 1, name: e.name ?? 'A player', score: label(e), me: !!e.me }));
      const myRank = sorted.findIndex((e) => e.me) + 1;
      return { id, rows, me: { rank: myRank, score: score(me) > 0 ? label(me) : '' } };
    };
    S.boards = {
      pets_frozen: build('pets_frozen', (e) => e.frozen, (e) => e.frozen.toLocaleString()),
      rarest_pet: build('rarest_pet', (e) => e.rarest * 1e6 - (e.me ? 0 : 0), (e) => tierName(e.rarest)),
      coins_week: build('coins_week', (e) => e.weekCoins, (e) => e.weekCoins.toLocaleString()),
      weekId: wk,
    };
    S.boardsAt = S.time;
    emit('boards', S.boards);
  }

  // ---------- movement replication + position check ----------
  // SERVER
  function setPosition(x, z) {
    const p = S.player;
    if (!p || typeof x !== 'number' || typeof z !== 'number' || !isFinite(x) || !isFinite(z)) return;
    // the budget refills with server time only, so sending more often or claiming a big time step gains nothing
    const speed = walkSpeed(), elapsed = Math.max(0, S.time - p.posAt); p.posAt = S.time;
    p.moveBudget = Math.min(speed * 0.5, p.moveBudget + speed * elapsed * 1.25);
    const d = Math.hypot(x - p.pos.x, z - p.pos.z);
    if (d > p.moveBudget + 0.05 || !pathWalkable(p.pos.x, p.pos.z, x, z, worldState())) {
      emit('correctPosition', { x: p.pos.x, z: p.pos.z });
      return;
    }
    p.moveBudget -= d; p.pos.x = x; p.pos.z = z;
  }

  function tickPlayerZone() {
    const p = S.player;
    const zone = zoneAt(p.pos.x, p.pos.z);
    if (zone !== p.zone) {
      p.zone = zone;
      AnalyticsSvc.event('zone_entered', { zone: zone === 0 ? 'hub' : zoneById[zone].key });
      if (zone === 2) AnalyticsSvc.funnel('first_new_zone');
    }
    const hub = inHub(p.pos.x, p.pos.z);
    const outside = p.pos.z > World.hub.zMax + Config.carryHomeMinStuds; // a real trip out, not a step over the hub line
    for (const c of p.carrying) { if (outside) c.leftHub = true; else if (hub && c.leftHub) AnalyticsSvc.funnel('first_carry_home'); }
    if (p.carrying.length && inPen(p.pos.x, p.pos.z)) bankCubes();
    p.lastAction = p.zap ? 'zapping' : p.menuOpen ? 'in_menu' : p.carrying.length ? 'carrying' : inPen(p.pos.x, p.pos.z) ? 'in_pen' : 'exploring';
  }

  const notYetAt = {};
  function notYet(reason, at) {
    if (S.time - (notYetAt[reason] ?? -1e9) < Config.notYetCooldown) return; // standing in a full pen doesn't spam
    notYetAt[reason] = S.time; emit('notYet', { reason, at });
  }

  let incomeCarry = 0;
  function tickIncome(dt) {
    incomeCarry += incomePerSecond() * dt;
    if (incomeCarry >= 1) { const n = Math.floor(incomeCarry); incomeCarry -= n; addCoins(n); }
  }

  // ---------- PlayerAdded / PlayerRemoving ----------
  // SERVER
  function join() {
    const { data, isNew } = load();
    S.player = {
      data, pos: { ...World.spawn }, zone: 0, carrying: data.superCubes.map(superCube), zap: null, lastFreezeAt: -9,
      lastAction: 'exploring', menuOpen: false, posAt: S.time, moveBudget: 2,
    };
    S.session.start = S.time;
    const w = weekId(nowMs()); if (data.week.id !== w) data.week = { id: w, coins: 0 };
    AnalyticsSvc.funnel('joined');
    // first minute: a fluffy bunny right next to the spawn point
    if (data.stats.frozen === 0) spawnPet(1, { x: World.spawn.x + 4, z: World.spawn.z + Config.spawner.firstPetDistance }, 'snowbun');
    // "a second and third pet are right there": every zone keeps a few in its near band from the start
    for (const z of World.zones) {
      while (nearCount(z.id) < Config.spawner.nearCount) if (!spawnPet(z.id, 'near')) break;
      for (let i = 0; i < Config.spawner.maxPerZone - 2 - Config.spawner.nearCount; i++) spawnPet(z.id);
    }
    checkWelcomeBack();
    refreshBoards();
    emit('joined', { isNew });
  }
  function leave() {
    const p = S.player; if (!p) return;
    AnalyticsSvc.event('session_end', {
      sessionSeconds: Math.round(S.time - S.session.start),
      zone: p.zone === 0 ? 'hub' : zoneById[p.zone].key,
      lastAction: p.lastAction, carryingCube: p.carrying.length > 0,
    });
    p.data.lastSeen = nowMs();
    save('leave');
  }

  // ---------- main tick ----------
  function tick(dt) {
    if (!S.player) return;
    S.time += dt;
    tickWild(dt); tickSpawner(); tickCarry(dt); tickPlayerZone(); tickIncome(dt); tickChill();
    if (S.iceBridgeUntil > 0 && S.time >= S.iceBridgeUntil) {
      S.iceBridgeUntil = -1; emit('bridge', { until: -1 });
      const p = S.player, bank = !onBridge(p.pos.x, false) && nearestBank(p.pos.x, p.pos.z);
      if (bank) { p.pos.x = bank.x; p.pos.z = bank.z; emit('correctPosition', { x: bank.x, z: bank.z, splash: true }); } // never stuck in the river
    }
    if (S.time - S.boardsAt >= Config.leaderboards.refreshSeconds) refreshBoards();
    if (S.time - S.lastSaveAt >= 10) { S.player.data.lastSeen = nowMs(); save(); }
  }

  // ---------- debug (dev commands; locked out of live servers in Roblox) ----------
  const debug = {
    skipTime(seconds) {
      // simulates being away: the save's last-seen time moves back, then the rejoin checks run
      const d = S.player.data;
      S.clockOffsetMs += seconds * 1000;
      d.lastSeen -= 0; // lastSeen stays at the real "left" moment; the clock jumps ahead
      checkWelcomeBack();
      emit('gift', giftState());
      refreshBoards();
    },
    bigChillSoon() { S.chill.next = S.time + Config.bigChill.warnSeconds; S.chill.warned = false; },
    wipe() { S.wiping = true; try { localStorage.removeItem(Config.saveKey); } catch { /* ignore */ } },
    grantCoins(n) { addCoins(n); },
    spawnNear(tier = 'Epic') {
      const p = S.player.pos, zone = zoneAt(p.x, p.z) || 1;
      const def = PetDefs.find((d) => d.zone === zone && d.tier === tier) || PetDefs.find((d) => d.tier === tier);
      return spawnPet(def.zone, { x: p.x + 5, z: p.z + 5 }, def.key);
    },
    meltSoon() { for (const c of S.player.carrying) if (!c.superFrozen) c.life = Math.min(c.life, 1); },
    teleport(x, z) { S.player.pos.x = x; S.player.pos.z = z; },
    // owner decision 2026-10-30: give the Forest a hotter zone's heat to test a tense run home and Super Freeze
    setUpgrade(id, level) { if (Object.hasOwn(Config.upgrades, id)) { S.player.data.upgrades[id] = Math.max(1, Math.min(Config.upgrades[id].maxLevel, Math.floor(level))); emit('upgraded', { id, level: S.player.data.upgrades[id], cost: 0 }); } },
    setHeat(zone, heat) { const z = zoneById[zone]; if (z && typeof heat === 'number' && heat > 0 && heat < 5) { z.baseHeat ??= z.heat; z.heat = heat; emit('heat', { zone, heat }); } },
    unlockForest() { if (!S.player.data.forestUnlocked) { S.player.data.forestUnlocked = true; emit('zoneUnlocked', { zone: 2 }); } },
  };

  // what the client is allowed to see (replicated state)
  function view() {
    const p = S.player; if (!p) return null;
    const wild = new Map(); for (const [id, w] of S.wild) wild.set(id, { ...w });
    return {
      time: S.time, coins: p.data.coins, income: incomePerSecond(), pos: { ...p.pos }, carrying: p.carrying.map((c) => ({ ...c })),
      capacity: capacity(), speed: walkSpeed(), upgrades: { ...p.data.upgrades }, pets: p.data.pets.map((x) => ({ ...x })), found: { ...p.data.found },
      penSlots: penSlots(), gateCoins: zoneById[2].gateCoins,
      forestUnlocked: p.data.forestUnlocked, iceBridgeActive: S.time < S.iceBridgeUntil, iceBridgeUntil: S.iceBridgeUntil,
      chill: { active: S.time < S.chill.until, until: S.chill.until, next: S.chill.next }, wild,
      gift: giftState(), welcome: p.data.welcome && { ...p.data.welcome }, boards: S.boards, stats: { ...p.data.stats }, zap: p.zap && { ...p.zap },
      pages: completedPages(p.data), dropped: S.dropped, zone: p.zone,
    };
  }

  return {
    on, join, leave, tick, view, shownOdds, nowMs, debug, analytics: AnalyticsSvc,
    // RemoteEvents: the only things a client can ask for
    remotes: {
      beginZap, endZap, cancelZap, buyUpgrade, collectWelcome, setPosition, buySuperFreezeMock, equipPet, equipBest,
      setMenuOpen(open) { if (S.player && rateOk()) { S.player.menuOpen = !!open; } },
      openShop() { if (S.player && rateOk()) AnalyticsSvc.event('shop_opened'); },
    },
  };
}
