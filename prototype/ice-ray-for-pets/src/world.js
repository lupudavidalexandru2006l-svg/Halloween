// SHARED: world rules both sides agree on (ports to ReplicatedStorage/Shared/WorldRules).
import { Config, World, Scenery, zoneById } from './config.js';

export function inHub(x, z) { return z < World.hub.zMax; }

export function inPen(x, z) {
  const p = World.pen;
  return x >= p.xMin && x <= p.xMax && z >= p.zMin && z <= p.zMax;
}

export function penCenter() {
  const p = World.pen;
  return { x: (p.xMin + p.xMax) / 2, z: (p.zMin + p.zMax) / 2 };
}

// 0 = hub, otherwise the zone id
export function zoneAt(x, z) {
  if (inHub(x, z)) return 0;
  for (const zone of World.zones) if (z >= zone.zMin && z <= zone.zMax) return zone.id;
  return z < World.zones[1].zMin ? 1 : 2; // river banks count as the zone before the gate
}

export function heatAt(x, z) {
  const zone = zoneAt(x, z);
  return zone === 0 ? Config.melt.hubHeat : zoneById[zone].heat;
}

// 'shade' | 'sun' | 'open'
export function lightAt(x, z) {
  for (const t of Scenery.trees) if ((x - t.x) ** 2 + (z - t.z) ** 2 < t.r * t.r) return 'shade';
  for (const s of Scenery.sun) if ((x - s.x) ** 2 + (z - s.z) ** 2 < s.r * s.r) return 'sun';
  return 'open';
}

export function meltRate(x, z) {
  const light = lightAt(x, z);
  const f = light === 'shade' ? Config.melt.shade : light === 'sun' ? Config.melt.sun : 1;
  return heatAt(x, z) * f;
}

// Temperature (degrees C) from the same numbers that drive melting, so it can never disagree with the cube.
export function temperatureAt(x, z, { night = false, chill = false } = {}) {
  const T = Config.temperature;
  const melt = chill ? 0 : meltRate(x, z) * (night ? Config.melt.night : 1);
  const c = Math.round(T.atZeroMelt + T.perMelt * melt);
  const band = T.bands.find(([max]) => c < max)[1];
  return { c, f: Math.round((c * 9) / 5 + 32), band, light: chill ? 'chill' : lightAt(x, z), night, melt };
}
export function zoneTemperature(zoneId) {
  const T = Config.temperature;
  const heat = zoneId === 0 ? Config.melt.hubHeat : zoneById[zoneId].heat;
  return Math.round(T.atZeroMelt + T.perMelt * heat);
}

export function onBridge(x, iceBridgeActive) {
  const m = World.mainBridge, i = World.iceBridgeSpot;
  if (x >= m.xMin && x <= m.xMax) return true;
  return iceBridgeActive && x >= i.xMin && x <= i.xMax;
}

// Can a player stand here? Used by client movement and by the server's position check.
export function walkable(x, z, state) {
  const b = World.bounds;
  if (x < b.xMin || x > b.xMax || z < b.zMin || z > b.zMax) return false;
  const r = World.river;
  if (z > r.zMin && z < r.zMax && !onBridge(x, state.iceBridgeActive)) return false;
  const g = World.gate;
  if (!state.forestUnlocked && z > g.z - 1 && z < g.z + 1.5) return false; // closed gate line
  if (state.forestUnlocked && z > g.z - 1 && z < g.z + 1.5 && (x < g.xMin || x > g.xMax)) return false;
  return true;
}

export function iceBridgeCenter() {
  const i = World.iceBridgeSpot;
  return { x: (i.xMin + i.xMax) / 2, z: World.river.zMin - 2 };
}

export function dist(a, b) { return Math.hypot(a.x - b.x, a.z - b.z); }
