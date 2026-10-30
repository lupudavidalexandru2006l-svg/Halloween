// SERVER: everything that decides something. In Roblox each block below becomes a service in
// ServerScriptService (named in the comment). The client only sends intent through `remotes`
// and plays effects for the events the server emits.
import {
  Config, Analytics, PetDefs, World, tierByName, petByKey, zoneById, upgradeCost, petIncome, mulberry32,
} from './config.js';
import { zoneAt, inHub, inPen, penCenter, meltRate, walkable, dist, iceBridgeCenter } from './world.js';

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
      version: Config.version, coins: 0, pets: [], upgrades: { ray: 1, boots: 1, backpack: 1 },
      found: {}, stats: { frozen: 0, banked: 0, melts: 0, coinsEarned: 0 },
      rarest: { rank: 0, key: null, at: 0 }, week: { id: '', coins: 0 },
      lastSeen: 0, welcome: null, gift: { lastDay: '', streak: 0 }, funnel: {}, forestUnlocked: false,
      createdAt: 0,
    };
  }
  function load() {
    let raw = null;
    try { raw = JSON.parse(localStorage.getItem(Config.saveKey) || 'null'); } catch { raw = null; }
    const d = Object.assign(defaults(), raw || {});
    for (const k of ['upgrades', 'stats', 'rarest', 'week', 'gift']) d[k] = Object.assign(defaults()[k], d[k] || {});
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
  function completedPages(d) {
    let n = 0;
    for (const z of World.zones) if (PetDefs.filter((p) => p.zone === z.id).every((p) => d.found[p.key])) n++;
    return n;
  }
  function incomePerSecond(d = S.player.data) {
    let sum = 0;
    for (const p of d.pets) sum += petIncome(petByKey[p.key], p.pose, p.mut);
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
        d.welcome = { coins: Math.floor(inc * capped * Config.away.rate), awaySeconds: Math.round(away), capped: away > Config.away.capSeconds };
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
    const ready = d.gift.lastDay !== today;
    const nextStreak = Math.min(Config.dailyGift.streakMax, d.gift.streak + 1);
    const base = Math.max(Config.dailyGift.baseCoins, incomePerSecond() * 60 * Config.dailyGift.incomeMinutes);
    const coins = Math.round(base * (1 + Config.dailyGift.streakBonus * (nextStreak - 1)));
    return { ready, streak: d.gift.streak, nextStreak, coins };
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
    let def;
    if (forcedKey) def = petByKey[forcedKey];
    else {
      const tier = rollTier(zone);
      const pool = PetDefs.filter((p) => p.zone === zone && p.tier === tier);
      def = pool[Math.floor(rng() * pool.length)];
    }
    let pos = at && at !== 'near' ? at : null;
    const sp = Config.spawner;
    const near = at === 'near';
    if (near) pos = null;
    for (let i = 0; !pos && i < 30; i++) {
      const z = zoneById[zone];
      const zMin = zone === 1 ? (near ? sp.nearZ[0] : sp.farZMin) : z.zMin + 10;
      const zMax = near ? sp.nearZ[1] : z.zMax - 10;
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
      wanderTo: null, dazedUntil: 0, pose: null, mut: null, offer: false, superUsed: false,
    });
    emit('wildSpawned', { id });
    return id;
  }
  function tickSpawner() {
    for (const z of World.zones) {
      const count = [...S.wild.values()].filter((w) => w.zone === z.id).length;
      if (count < Config.spawner.maxPerZone && S.time >= (S.respawnAt[z.id] ?? 0)) {
        spawnPet(z.id);
        S.respawnAt[z.id] = S.time + Config.spawner.respawnSeconds;
      }
    }
  }
  function tickWild(dt) {
    for (const w of S.wild.values()) {
      if (w.state === 'dazed') {
        if (w.offer && S.player && dist(w, S.player.pos) > Config.monetization.superFreeze.walkAwayStuds) { w.offer = false; emit('offerGone', { id: w.id }); }
        if (S.time >= w.dazedUntil) { w.state = 'wild'; w.offer = false; w.pose = null; emit('offerGone', { id: w.id }); }
        continue;
      }
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
      if (dist(p.pos, iceBridgeCenter()) > Config.player.freezeRange + 2) return;
      p.zap = { target, start: S.time, hold: Config.player.freezeHold };
    } else if (target === 'gift') {
      if (dist(p.pos, World.giftBox) > Config.player.freezeRange) return;
      p.zap = { target, start: S.time, hold: Config.player.interactHold };
    } else {
      const w = S.wild.get(target);
      if (!w || dist(p.pos, w) > Config.player.freezeRange + 1) return;
      if (p.carrying.length >= capacity()) { emit('notYet', { reason: 'Backpack full', at: target }); return; }
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
      if (dist(p.pos, iceBridgeCenter()) > Config.player.freezeRange * 1.5) return;
      const secs = Config.bridge.baseSeconds + Config.upgrades.ray.bridgeBonus * (p.data.upgrades.ray - 1);
      S.iceBridgeUntil = S.time + secs;
      emit('bridge', { until: S.iceBridgeUntil, seconds: secs });
      return;
    }
    if (target === 'gift') { claimGift(); return; }
    const w = S.wild.get(target);
    if (!w || dist(p.pos, w) > Config.player.freezeRange * 1.3 || p.carrying.length >= capacity()) return;
    const def = petByKey[w.key];
    const pose = w.state === 'dazed' ? w.pose : w.action; // the pose at the moment the hold finished
    const mut = w.state === 'dazed' ? w.mut : (S.time < S.chill.until ? 'Frosty' : null);
    const lifeMax = cubeLifeMax(def);
    const cube = {
      uid: 'c' + S.nextId++, key: w.key, zone: w.zone, pose, mut, life: lifeMax, lifeMax,
      superFrozen: false, superUsed: w.superUsed, since: S.time, carriedHome: false,
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
      dazedUntil: S.time + Config.dazedSeconds, pose: c.pose, mut: c.mut, offer: false, superUsed: c.superUsed,
    };
    S.wild.set(id, w);
    p.data.stats.melts++;
    const home = penCenter();
    AnalyticsSvc.event('cube_melted', { pet: c.key, tier: def.tier, zone: c.zone, studsFromHome: Math.round(dist(p.pos, home)) });
    // Super Freeze offer: Rare and up, at most once per run, a small world button, no countdown
    if (rankOf(def.tier) >= rankOf(Config.monetization.superFreeze.minTier) && !c.superUsed) {
      w.offer = true;
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
    const cube = {
      uid: 'c' + S.nextId++, key: w.key, zone: w.zone, pose: w.pose, mut: w.mut, life: 1, lifeMax: 1,
      superFrozen: true, superUsed: true, since: S.time, carriedHome: false,
    };
    S.wild.delete(petId);
    p.carrying.push(cube);
    AnalyticsSvc.event('offer_bought', { offer: 'super_freeze', robux: Config.monetization.superFreeze.robux });
    save('purchase'); // granted and saved before PurchaseGranted
    emit('offerGone', { id: petId });
    emit('frozen', { petId, cube, superFrozen: true, tier: def.tier });
  }

  // ---------- banking (PenService) ----------
  // SERVER
  function bankCubes() {
    const p = S.player, d = p.data;
    const banked = [];
    for (const c of p.carrying) {
      if (d.pets.length >= Config.penSlots) { emit('notYet', { reason: 'Pen full' }); break; }
      const def = petByKey[c.key];
      d.pets.push({ key: c.key, pose: c.pose, mut: c.mut, at: nowMs() });
      const firstTime = !d.found[c.key];
      d.found[c.key] = true;
      d.stats.banked++;
      if (rankOf(def.tier) > d.rarest.rank) d.rarest = { rank: rankOf(def.tier), key: c.key, at: nowMs() };
      AnalyticsSvc.event('pet_banked', { pet: c.key, tier: def.tier, pose: c.pose, zone: c.zone, carrySeconds: Math.round(S.time - c.since) });
      AnalyticsSvc.funnel('first_bank');
      if (rankOf(def.tier) >= 3) AnalyticsSvc.funnel('first_rare_pet');
      banked.push({ cube: c, income: petIncome(def, c.pose, c.mut), firstTime });
    }
    p.carrying = p.carrying.slice(banked.length);
    if (!banked.length) return;
    if (!d.forestUnlocked && d.pets.length >= zoneById[2].gatePets) { d.forestUnlocked = true; emit('zoneUnlocked', { zone: 2 }); }
    save('bank');
    emit('banked', { banked, income: incomePerSecond() });
  }

  // ---------- ShopService ----------
  // SERVER
  function buyUpgrade(id) {
    const p = S.player;
    if (!p || !rateOk() || typeof id !== 'string' || !Config.upgrades[id]) return;
    const lvl = p.data.upgrades[id];
    if (lvl >= Config.upgrades[id].maxLevel) { emit('notYet', { reason: 'Max level', at: id }); return; }
    const cost = upgradeCost(id, lvl + 1);
    if (p.data.coins < cost) { emit('notYet', { reason: `Need ${Math.ceil(cost - p.data.coins)} more`, at: id }); return; }
    p.data.coins -= cost; p.data.upgrades[id] = lvl + 1;
    AnalyticsSvc.funnel('first_coins_spent');
    save('upgrade');
    emit('upgraded', { id, level: lvl + 1, cost });
  }
  function claimGift() {
    const g = giftState(); const d = S.player.data;
    if (!g.ready) { emit('notYet', { reason: 'Next gift tomorrow', at: 'gift' }); return; }
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
  function refreshBoards() {
    S.rivals ||= makeRivals();
    for (const rv of S.rivals) { rv.frozen += Math.floor(rng() * 3); rv.weekCoins += Math.floor(rng() * 400); }
    const d = S.player.data;
    const me = { name: opts.displayName || 'You', me: true, frozen: d.stats.frozen, rarest: d.rarest.rank, rarestAt: d.rarest.at, weekCoins: Math.floor(d.week.coins) };
    const all = [...S.rivals, me];
    const tierName = (rank) => Config.tiers.find((t) => t.rank === rank)?.name ?? '-';
    const build = (id, score, label) => {
      const sorted = [...all].sort((a, b) => score(b) - score(a) || (a.rarestAt - b.rarestAt));
      const rows = sorted.slice(0, Config.leaderboards.size).map((e, i) => ({ rank: i + 1, name: e.name ?? 'A player', score: label(e), me: !!e.me }));
      const myRank = sorted.findIndex((e) => e.me) + 1;
      return { id, rows, me: { rank: myRank, score: label(me) } };
    };
    S.boards = {
      pets_frozen: build('pets_frozen', (e) => e.frozen, (e) => e.frozen.toLocaleString()),
      rarest_pet: build('rarest_pet', (e) => e.rarest * 1e6 - (e.me ? 0 : 0), (e) => tierName(e.rarest)),
      coins_week: build('coins_week', (e) => e.weekCoins, (e) => e.weekCoins.toLocaleString()),
      weekId: weekId(nowMs()),
    };
    S.boardsAt = S.time;
    emit('boards', S.boards);
  }

  // ---------- movement replication + position check ----------
  // SERVER
  function setPosition(x, z, dt) {
    const p = S.player;
    if (!p || typeof x !== 'number' || typeof z !== 'number' || !isFinite(x) || !isFinite(z) || !(dt > 0)) return;
    const maxStep = walkSpeed() * Math.min(dt, 0.25) * 1.6 + 0.6;
    if (Math.hypot(x - p.pos.x, z - p.pos.z) > maxStep || !walkable(x, z, worldState())) {
      emit('correctPosition', { x: p.pos.x, z: p.pos.z });
      return;
    }
    p.pos.x = x; p.pos.z = z;
  }

  function tickPlayerZone() {
    const p = S.player;
    const zone = zoneAt(p.pos.x, p.pos.z);
    if (zone !== p.zone) {
      p.zone = zone;
      AnalyticsSvc.event('zone_entered', { zone: zone === 0 ? 'hub' : zoneById[zone].key });
      if (zone === 2) AnalyticsSvc.funnel('first_new_zone');
    }
    if (p.carrying.length && inHub(p.pos.x, p.pos.z)) AnalyticsSvc.funnel('first_carry_home');
    if (p.carrying.length && inPen(p.pos.x, p.pos.z)) bankCubes();
    p.lastAction = p.zap ? 'zapping' : p.menuOpen ? 'in_menu' : p.carrying.length ? 'carrying' : inPen(p.pos.x, p.pos.z) ? 'in_pen' : 'exploring';
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
      data, pos: { ...World.spawn }, zone: 0, carrying: [], zap: null, lastFreezeAt: -9,
      lastAction: 'exploring', menuOpen: false,
    };
    S.session.start = S.time;
    const w = weekId(nowMs()); if (data.week.id !== w) data.week = { id: w, coins: 0 };
    AnalyticsSvc.funnel('joined');
    // first minute: a fluffy bunny right next to the spawn point
    if (data.stats.frozen === 0) spawnPet(1, { x: World.spawn.x + 4, z: World.spawn.z + Config.spawner.firstPetDistance }, 'snowbun');
    // "a second and third pet are right there"; every other Meadow pet spawns further south
    for (let i = data.pets.length + 1; i < Config.spawner.nearUntilPets; i++) spawnPet(1, 'near');
    for (const z of World.zones) for (let i = 0; i < Config.spawner.maxPerZone - 2; i++) spawnPet(z.id);
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
    if (S.iceBridgeUntil > 0 && S.time >= S.iceBridgeUntil) { S.iceBridgeUntil = -1; emit('bridge', { until: -1 }); }
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
    unlockForest() { if (!S.player.data.forestUnlocked) { S.player.data.forestUnlocked = true; emit('zoneUnlocked', { zone: 2 }); } },
  };

  // what the client is allowed to see (replicated state)
  function view() {
    const p = S.player; if (!p) return null;
    return {
      time: S.time, coins: p.data.coins, income: incomePerSecond(), pos: p.pos, carrying: p.carrying,
      capacity: capacity(), speed: walkSpeed(), upgrades: p.data.upgrades, pets: p.data.pets, found: p.data.found,
      forestUnlocked: p.data.forestUnlocked, iceBridgeActive: S.time < S.iceBridgeUntil, iceBridgeUntil: S.iceBridgeUntil,
      chill: { active: S.time < S.chill.until, until: S.chill.until, next: S.chill.next }, wild: S.wild,
      gift: giftState(), welcome: p.data.welcome, boards: S.boards, stats: p.data.stats, zap: p.zap,
      pages: completedPages(p.data), dropped: S.dropped, zone: p.zone,
    };
  }

  return {
    on, join, leave, tick, view, shownOdds, nowMs, debug, analytics: AnalyticsSvc,
    // RemoteEvents: the only things a client can ask for
    remotes: {
      beginZap, endZap, cancelZap, buyUpgrade, collectWelcome, setPosition, buySuperFreezeMock,
      setMenuOpen(open) { if (S.player && rateOk()) { S.player.menuOpen = !!open; } },
      openShop() { if (S.player && rateOk()) AnalyticsSvc.event('shop_opened'); },
    },
  };
}
