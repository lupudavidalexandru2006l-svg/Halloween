// SHARED: Config, Theme, PetDefs, world layout and the Analytics list.
// Ports to ReplicatedStorage/Shared/{Config, Theme, PetDefs}. Every number lives here.

export const Theme = {
  ink: '#1b1433',
  go: '#3ccf6e', no: '#ff5a5f', coin: '#ffc93c', info: '#3aa8ff',
  ice: '#bfe9ff', iceDeep: '#2f6bff', iceEdge: '#ffffff',
  snow: '#f4f8ff', snowFar: '#dfe9f6', grass: '#7fbf5a', grassFar: '#a9cf95',
  forest: '#4d8a4a', forestFar: '#8db58a', water: '#4aa3e0', wood: '#9a6b43',
  sky: '#9fd6ff', skyHorizon: '#e8f6ff', sun: '#fff1a8', shade: '#1b1433',
  hub: '#e9f2ff', path: '#cfdcec',
  tiers: {
    Common: '#9aa5b1', Uncommon: '#4cc35a', Rare: '#3c8cf0', Epic: '#aa50e6',
    Legendary: '#fab01e', Mythic: '#f04678', Secret: '#2a2a2a',
  },
  tiles: { pets: '#ff6fa5', shop: '#ff9f1c', index: '#3aa8ff', settings: '#8f7cff' },
};

export const Config = {
  version: 1,
  saveKey: 'iceray.save.v1',

  player: {
    walkSpeed: 16,          // studs per second (Roblox default)
    freezeRange: 10,        // studs from the pet
    freezeHold: 1.0,        // seconds to hold Freeze on a wild pet
    refreezeHold: 0.35,     // one quick zap on a dazed pet (free, always)
    interactHold: 0.4,      // gift box
    freezeCooldown: 0.3,
    rateLimitPerSecond: 12, // remote calls per player per second before they are dropped
  },

  tiers: [
    // odds are percentages; cubeLife in seconds before heat; income is coins per second in zone 1
    { name: 'Common',    odds: 59.995, cubeLife: 90, income: 1,   rank: 1 }, // 60% minus the Secret's share, so odds add to 100
    { name: 'Uncommon',  odds: 25,    cubeLife: 70, income: 3,    rank: 2 },
    { name: 'Rare',      odds: 10,    cubeLife: 50, income: 10,   rank: 3 },
    { name: 'Epic',      odds: 4,     cubeLife: 40, income: 30,   rank: 4 },
    { name: 'Legendary', odds: 0.9,   cubeLife: 30, income: 100,  rank: 5 },
    { name: 'Mythic',    odds: 0.1,   cubeLife: 25, income: 400,  rank: 6 },
    { name: 'Secret',    odds: 0.005, cubeLife: 20, income: 1500, rank: 7 }, // 1 in 20,000, every zone
  ],
  incomeZoneMultiplier: 4,  // a zone-2 pet earns 4x its zone-1 tier income

  poses: {
    // the pose when the Freeze hold finishes is the pose you keep
    idle:   { label: 'Normal', bonus: 1.0, seconds: 2.4 },
    yawn:   { label: 'Yawn',   bonus: 1.2, seconds: 1.3 },
    jump:   { label: 'Jump',   bonus: 1.2, seconds: 0.9 },
    dance:  { label: 'Dance',  bonus: 1.5, seconds: 1.6 },
    sneeze: { label: 'Mid-Sneeze', bonus: 2.0, seconds: 0.7 },
    loop: ['idle', 'yawn', 'idle', 'jump', 'idle', 'dance'],
    sneezeChance: 0.08,     // chance that the next action is a sneeze instead
    zapSlowdown: 0.5,       // while you hold Freeze on a pet it acts at half speed, so a pose can be caught on purpose
  },
  mutations: {
    Frosty: { bonus: 1.5 }, // caught during the Big Chill
  },

  upgrades: {
    // each step costs x1.5 the last (Game Plan 11); baseCost = the price of level 2
    // cube size: +12% a level for the first 4 levels (an upgrade you can see), then +2%
    ray:      { name: 'Ice Ray',  baseCost: 40,  costGrowth: 1.5, maxLevel: 20, lifeBonus: 0.20, bridgeBonus: 4, cubeSize: { early: 0.12, earlyLevels: 4, late: 0.02 } },
    boots:    { name: 'Boots',    baseCost: 64,  costGrowth: 1.5, maxLevel: 15, speedBonus: 0.08 },
    backpack: { name: 'Backpack', baseCost: 750, costGrowth: 1.5, maxLevel: 5, slowPerExtraCube: 0.08 },
    pen:      { name: 'Pen',      baseCost: 150, costGrowth: 1.5, maxLevel: 19, slotsPerLevel: 5 }, // Game Plan 11: +5 earning slots
  },
  upgradeIds: ['ray', 'boots', 'backpack', 'pen'],
  carryHomeMinStuds: 4,     // funnel step 4 counts a cube carried at least this far out of the hub and back
  beachGateCoins: 500,      // Game Plan 4: Sunny Beach opens at 500 coins (the zone itself is not in the prototype)
  // Pen and Storage (owner decision 2026-10-30): the pen's pets earn; every other banked pet waits in
  // Storage (kept forever, in the Index, earns nothing). You equip pets by hand or press Equip best.
  pen: { baseSlots: 10, storageMax: 500 },

  melt: {
    shade: 0.5,             // trees, cliffs, tunnels
    sun: 1.5,               // sun patches
    night: 0.6,             // Game Plan 12 (night itself is not in the prototype yet)
    hubHeat: 0.3,           // the hub is the cold north end
  },
  // Temperature: a readable version of the melt speed (owner request 2026-10-30). It never changes
  // the melt maths in the Game Plan; it is worked out from it, so zone, shade, sun, night and the
  // Big Chill all move it. degrees C = atZeroMelt + perMelt x melt speed (Big Chill = no melting = coldest).
  temperature: { unit: 'C', atZeroMelt: -20, perMelt: 30, bands: [ [0, 'cold'], [15, 'cool'], [35, 'warm'], [999, 'hot'] ] },
  dazedSeconds: 8,          // a melted pet stands dazed this long, then wanders off (it was never yours)

  spawner: {
    maxPerZone: 9,          // cap on visible wild pets per zone (phone performance)
    respawnSeconds: 1.5,
    firstPetDistance: 12,   // the first-minute bunny spawns this close to the spawn point
    // "always one within about 3 seconds of walking" (Game Plan 4): each zone keeps 2 Commons or
    // Uncommons in its near band; other Commons spawn from farZMin; Rare and up only in the far half
    near: { 1: [8, 34], 2: [204, 236] },
    nearCount: 2,
    farZMin: { 1: 60, 2: 204 },
    pity: { graceFactor: 1.0, perMiss: 0.0015, maxBoost: 3 }, // soft pity per zone, Rare and up
  },

  bridge: { baseSeconds: 20 },

  bigChill: { everySeconds: 600, warnSeconds: 30, durationSeconds: 60 },

  away: {
    minSeconds: 60,         // shorter absences show no welcome-back
    capSeconds: 8 * 3600,   // pen earnings while away are capped at 8 hours
    rate: 0.25,             // share of normal pen income earned while away (owner 2026-10-30: 25%, so a night away never skips a zone)
  },
  dailyGift: {
    baseCoins: 50,
    incomeMinutes: 10,      // the gift is also worth 10 minutes of your pen's income, whichever is bigger
    streakBonus: 0.1,       // +10% per streak day
    streakMax: 7,           // the streak never drops; missing a day just pauses it
  },

  leaderboards: {
    size: 10,
    refreshSeconds: 60,     // boards update on an interval, not on every event
    weeklyResetDay: 1,      // 1 = Monday (UTC), a fixed calendar day shown on the board
    weeklyResetLabel: 'Resets every Monday',
    // scores come from the server's own counters and are still clamped (no impossible numbers on a board)
    limits: { frozen: 10000000, weekCoins: 1e13, freezesPerSecond: 1 },
    boards: [
      { id: 'pets_frozen', title: 'Most pets frozen', kind: 'alltime' },
      { id: 'rarest_pet', title: 'Rarest pet found', kind: 'alltime' },
      { id: 'coins_week', title: 'Coins earned this week', kind: 'weekly' },
    ],
    cosmeticReward: 'Top 3 each week get a glowing name',
  },

  monetization: {
    // mock only: no real money in the prototype
    superFreeze: { robux: 15, minTier: 'Rare', walkAwayStuds: 18 },
  },

  camera: { height: 15, back: 21, lookAhead: 14, fov: 55, carry: { height: 24, back: 13, lookAhead: 4 } }, // carrying: higher and more top-down, so home is in view
  graphics: { low: false, shadowMap: 1024 }, // Low graphics (World Rules 7): no shadows or reflections, lower resolution // low enough that the next zone and the far volcano are in view
  motion: { reduced: false, bob: 1.6 },
  look: { wildPetScale: 1.15 },  // wild pets a little bigger than in the pen, so they stand out on snow
  sounds: { music: 0.45, sfx: 0.8, streakReset: 1.5, bankStreakReset: 20, maxSame: 3 },
  notYetCooldown: 2,        // seconds between two of the same "not yet" messages

  ui: {
    tiles: [
      { id: 'pets', label: 'Pets' },
      { id: 'shop', label: 'Shop' },
      { id: 'index', label: 'Index' },
      { id: 'settings', label: 'Settings' },
    ],
  },
};

// Analytics: the one list of funnel steps and events (ports to Config.Analytics).
// Every name the game logs comes from here; nothing else invents event names.
export const Analytics = {
  funnel: [
    { step: 1, name: 'joined' },
    { step: 2, name: 'first_zap' },
    { step: 3, name: 'first_freeze' },
    { step: 4, name: 'first_carry_home' },
    { step: 5, name: 'first_bank' },
    { step: 6, name: 'first_coins_spent' },
    { step: 7, name: 'first_rare_pet' },     // first Rare-or-better pet banked
    { step: 8, name: 'first_new_zone' },     // first time inside Pine Forest
  ],
  events: {
    cube_melted: ['pet', 'tier', 'zone', 'studsFromHome'],
    pet_banked: ['pet', 'tier', 'pose', 'zone', 'carrySeconds'],
    zone_entered: ['zone'],
    shop_opened: [],
    offer_shown: ['offer', 'pet', 'tier'],
    offer_bought: ['offer', 'robux'],
    session_end: ['sessionSeconds', 'zone', 'lastAction', 'carryingCube'],
  },
  lastActions: ['zapping', 'carrying', 'in_pen', 'in_menu', 'exploring'],
};

// PetDefs: one entry per pet. Prototype uses the concept as a sprite, or the real 3D model.
export const PetDefs = [
  // Snowy Meadow (zone 1)
  { key: 'snowbun',         name: 'Snowbun',         zone: 1, tier: 'Common',    rig: 'Quadruped', size: 'S', color: '#e9507f', model: 'assets/models/snowbun.gltf.json' },
  { key: 'waddles',         name: 'Waddles',         zone: 1, tier: 'Common',    rig: 'Biped',     size: 'S', color: '#1d2756' },
  { key: 'mittenkit',       name: 'Mittenkit',       zone: 1, tier: 'Uncommon',  rig: 'Quadruped', size: 'S', color: '#f08a22' },
  { key: 'pupcicle',        name: 'Pupcicle',        zone: 1, tier: 'Rare',      rig: 'Quadruped', size: 'M', color: '#f2d81c' },
  { key: 'frostfox',        name: 'Frostfox',        zone: 1, tier: 'Epic',      rig: 'Quadruped', size: 'M', color: '#1f7f95', model: 'assets/models/frostfox.gltf.json' },
  { key: 'blizzard_yeti',   name: 'Blizzard Yeti',   zone: 1, tier: 'Legendary', rig: 'Biped',     size: 'L', color: '#8d6ad6' },
  { key: 'aurora_owl',      name: 'Aurora Owl',      zone: 1, tier: 'Mythic',    rig: 'Bird',      size: 'M', color: '#178a63' },
  { key: 'snowglobe_drake', name: 'Snowglobe Drake', zone: 1, tier: 'Secret',    rig: 'Custom',    size: 'M', color: '#c8202f' },
  // Pine Forest (zone 2)
  { key: 'conehog',            name: 'Conehog',            zone: 2, tier: 'Common',    rig: 'Quadruped', size: 'S', color: '#8a4b2a' },
  { key: 'hopsprout',          name: 'Hopsprout',          zone: 2, tier: 'Common',    rig: 'Quadruped', size: 'S', color: '#e7b528' },
  { key: 'capmouse',           name: 'Capmouse',           zone: 2, tier: 'Uncommon',  rig: 'Quadruped', size: 'S', color: '#6b2f8f' },
  { key: 'mossfawn',           name: 'Mossfawn',           zone: 2, tier: 'Rare',      rig: 'Quadruped', size: 'M', color: '#2f6a30' },
  { key: 'lanternbug',         name: 'Lanternbug',         zone: 2, tier: 'Epic',      rig: 'Bird',      size: 'S', color: '#36318c' },
  { key: 'mapleguard_bear',    name: 'Mapleguard Bear',    zone: 2, tier: 'Legendary', rig: 'Quadruped', size: 'L', color: '#b51f2c' },
  { key: 'bloomhorn_stag',     name: 'Bloomhorn Stag',     zone: 2, tier: 'Mythic',    rig: 'Custom',    size: 'M', color: '#d6286f' },
  { key: 'glowshroom_mammoth', name: 'Glowshroom Mammoth', zone: 2, tier: 'Secret',    rig: 'Custom',    size: 'M', color: '#1f5a6a' },
];
export const SizeHeight = { S: 2.2, M: 3, L: 4 };   // studs (Pet Rules: S ~2, M ~3, L ~4)
export const CubeSize = { S: 3.0, M: 3.8, L: 4.8 };

// World layout (studs). North (hub) is -z, the zones run south (+z). Shared by server and client.
export const World = {
  bounds: { xMin: -78, xMax: 78, zMin: -62, zMax: 372 },
  spawn: { x: 0, z: -6 },
  pen: { xMin: -13, xMax: 13, zMin: -34, zMax: -16 },      // your pen: walk in to bank
  hub: { zMax: -2 },                                       // everything north of this is the hub
  giftBox: { x: -24, z: -10 },
  boards: [ { x: -38, z: -3 }, { x: -53, z: -3 }, { x: -68, z: -3 } ], // hub edge, screen-right (the menu tiles are on the left)
  zones: [
    { id: 1, key: 'meadow', name: 'Snowy Meadow', heat: 0.5, zMin: -2, zMax: 166, gateCoins: 0,
      sign: { x: -16, z: 4 }, ground: Theme.snow },
    { id: 2, key: 'forest', name: 'Pine Forest', heat: 0.8, zMin: 194, zMax: 372, gateCoins: 1000, // starts at the gate; opens with coins (owner 2026-10-30): 1000 lands at ~5.5 min kid time (bot x 2.5)
      sign: { x: -16, z: 202 }, ground: Theme.grass },
  ],
  river: { zMin: 168, zMax: 182 },
  mainBridge: { xMin: -74, xMax: -62 },                    // the free bridge is the long way round
  iceBridgeSpot: { xMin: -6, xMax: 6 },                    // the ice bridge sits on the straight line from the gate to your pen
  gate: { z: 194, xMin: -10, xMax: 10 },                   // the Forest gate opening
  beachGate: { z: 368 },                                   // Sunny Beach: closed in the prototype (a sign, not an invisible wall)
};

// Deterministic scenery so the server (shade/sun) and the client (drawing) agree.
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function buildScenery() {
  const r = mulberry32(1234);
  const trees = [], sun = [];
  const clear = (x, z) => Math.abs(x) < 9 || (z > 160 && z < 200); // keep the main path and river banks open
  // Meadow: a few snowy pines with shade under them, and open sunny patches
  for (let i = 0; i < 26; i++) {
    const x = -72 + r() * 144, z = 14 + r() * 146;
    if (clear(x, z)) continue;
    trees.push({ x, z, r: 4 + r() * 2.5, kind: 'snowpine' });
  }
  for (let i = 0; i < 7; i++) sun.push({ x: -60 + r() * 120, z: 30 + r() * 120, r: 7 + r() * 5 });
  // Forest: lots of shade
  for (let i = 0; i < 70; i++) {
    const x = -74 + r() * 148, z = 204 + r() * 164;
    if (clear(x, z)) continue;
    trees.push({ x, z, r: 4.5 + r() * 3, kind: 'pine' });
  }
  for (let i = 0; i < 4; i++) sun.push({ x: -55 + r() * 110, z: 215 + r() * 140, r: 6 + r() * 4 });
  return { trees, sun };
}
export const Scenery = buildScenery();

export const tierByName = Object.fromEntries(Config.tiers.map((t) => [t.name, t]));
export const petByKey = Object.fromEntries(PetDefs.map((p) => [p.key, p]));
export const zoneById = Object.fromEntries(World.zones.map((z) => [z.id, z]));
export function upgradeCost(id, level) {
  const u = Config.upgrades[id];
  return Math.round(u.baseCost * Math.pow(u.costGrowth, level - 2)); // level 2 costs baseCost
}
export function cubeSizeFactor(rayLevel) {
  const c = Config.upgrades.ray.cubeSize, n = rayLevel - 1;
  return 1 + c.early * Math.min(n, c.earlyLevels) + c.late * Math.max(0, n - c.earlyLevels);
}
export const isRegular = (def) => def.tier !== 'Secret'; // an Index page is the 7 regular pets; the Secret is a bonus slot
export function petIncome(def, pose, mutation) {
  const t = tierByName[def.tier];
  const zoneMult = Math.pow(Config.incomeZoneMultiplier, def.zone - 1);
  const p = Config.poses[pose]?.bonus ?? 1;
  const m = mutation ? Config.mutations[mutation].bonus : 1;
  return t.income * zoneMult * p * m;
}
export { mulberry32 };
