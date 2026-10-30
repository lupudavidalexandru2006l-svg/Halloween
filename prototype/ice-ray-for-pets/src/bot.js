// TEST TOOL (CLIENT side): the playtest bot (?bot=1). Plays like a focused kid through the same
// input signals a player uses: nearest pet -> freeze -> carry home -> buy when affordable -> next zone.
// It never buys anything with Robux, so it measures the free player's grind.
import { Config, World, upgradeCost } from './config.js';
import { dist, penCenter } from './world.js';

export function createBot({ server, client, input }) {
  const R = World.river, G = World.gate, BX = (World.mainBridge.xMin + World.mainBridge.xMax) / 2;
  let stuckT = 0, lastPos = null, jiggle = null;
  const side = (z) => (z < R.zMin - 0.5 ? 0 : z < G.z ? 1 : 2);
  function waypoint(me, goal) {
    const a = side(me.z), b = side(goal.z);
    if (a === b) return goal;
    if (a < b) {
      if (a === 0) return Math.abs(me.x - BX) > 2 || me.z < R.zMin - 4 ? { x: BX, z: R.zMin - 3 } : { x: BX, z: R.zMax + 3 };
      return Math.abs(me.x) > 3 ? { x: 0, z: G.z - 4 } : { x: 0, z: G.z + 4 };
    }
    if (a === 2) return Math.abs(me.x) > 3 ? { x: 0, z: G.z + 4 } : { x: 0, z: G.z - 4 };
    return Math.abs(me.x - BX) > 2 || me.z > R.zMax + 4 ? { x: BX, z: R.zMax + 3 } : { x: BX, z: R.zMin - 3 };
  }
  function step(dt) {
    const v = server.view(); if (!v) return;
    const me = client.me;
    if (v.welcome) server.remotes.collectWelcome();
    // buy the cheapest upgrade it can afford (a kid taps Shop when the red "!" shows)
    const opts = ['ray', 'boots', 'backpack'].filter((id) => v.upgrades[id] < Config.upgrades[id].maxLevel)
      .map((id) => ({ id, cost: upgradeCost(id, v.upgrades[id] + 1) })).sort((a, b) => a.cost - b.cost);
    if (opts[0] && v.coins >= opts[0].cost) server.remotes.buyUpgrade(opts[0].id);

    const cubes = v.carrying;
    const low = cubes.some((c) => !c.superFrozen && c.life / c.lifeMax < 0.45);
    let goal = null, wantInteract = false;
    const candidates = [...v.wild.values()].filter((w) => w.zone === 1 || v.forestUnlocked);
    const score = (w) => dist(w, me) - (v.forestUnlocked && w.zone === 2 ? 120 : 0) - (w.state === 'dazed' ? 200 : 0);
    candidates.sort((a, b) => score(a) - score(b));
    const near = candidates[0];
    if (cubes.length && (cubes.length >= v.capacity || low || !near || dist(near, me) > 60)) {
      const p = penCenter(); goal = { x: p.x, z: p.z + 2 };
    } else if (near) {
      goal = near;
      if (dist(near, me) < Config.player.freezeRange - 1.5) { wantInteract = true; goal = null; }
    }
    // keep holding while a zap is in progress
    if (client.hold.target && !client.hold.sent) { wantInteract = true; goal = null; }
    let mv = { x: 0, z: 0 };
    if (goal) {
      const wp = waypoint(me, goal);
      const d = dist(wp, me); if (d > 0.8) mv = { x: (wp.x - me.x) / d, z: (wp.z - me.z) / d };
    }
    // unstick
    if (lastPos && mv.x + mv.z !== 0 && dist(lastPos, me) < 0.02) stuckT += dt; else stuckT = 0;
    if (stuckT > 1.5) { jiggle = { x: Math.random() - 0.5, z: Math.random() - 0.5, t: 0.6 }; stuckT = 0; }
    if (jiggle) { mv = jiggle; jiggle.t -= dt; if (jiggle.t <= 0) jiggle = null; }
    lastPos = { x: me.x, z: me.z };
    input.state.botMove = mv; input.state.botInteract = wantInteract;
  }
  return { step };
}
