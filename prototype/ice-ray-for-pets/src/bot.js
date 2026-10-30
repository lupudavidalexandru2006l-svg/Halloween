// TEST TOOL (CLIENT side): the playtest bot (?bot=1). Plays like a focused kid through the same
// input signals a player uses: nearest pet -> freeze -> carry home -> buy when affordable -> next zone.
// It never buys anything with Robux, so it measures the free player's grind.
import { Config, World, upgradeCost, petByKey, tierByName } from './config.js';
import { dist, penCenter } from './world.js';

// &raycap=N: the bot stops buying Ice Ray at level N (to test a hot run with a weak ray)
const RAY_CAP = +(new URLSearchParams(location.search).get('raycap') || 99);
export function createBot({ server, client, input, hud }) {
  const R = World.river, G = World.gate, BX = (World.mainBridge.xMin + World.mainBridge.xMax) / 2;
  const IX = (World.iceBridgeSpot.xMin + World.iceBridgeSpot.xMax) / 2;
  let crossX = BX, skipIceUntil = -1, lastEquip = -99;
  let stuckT = 0, lastPos = null, jiggle = null;
  const side = (z) => (z < R.zMin - 0.5 ? 0 : z < G.z ? 1 : 2);
  function waypoint(me, goal) {
    const a = side(me.z), b = side(goal.z);
    if (a === b) return goal;
    if (a < b) {
      if (a === 0) return Math.abs(me.x - crossX) > 2 || me.z < R.zMin - 4 ? { x: crossX, z: R.zMin - 3 } : { x: crossX, z: R.zMax + 3 };
      return Math.abs(me.x) > 3 ? { x: 0, z: G.z - 4 } : { x: 0, z: G.z + 4 };
    }
    if (a === 2) return Math.abs(me.x) > 3 ? { x: 0, z: G.z + 4 } : { x: 0, z: G.z - 4 };
    return Math.abs(me.x - crossX) > 2 || me.z > R.zMax + 4 ? { x: crossX, z: R.zMax + 3 } : { x: crossX, z: R.zMin - 3 };
  }
  function step(dt) {
    const v = server.view(); if (!v) return;
    const me = client.me;
    if (hud?.popupOpen) hud.close(); // a kid taps Yay / Collect / X
    // a kid presses Equip best when the Pets tile shows its "!" (a stored pet earns more than one in the pen)
    if (v.time - lastEquip > 5 && v.pets.some((x) => !x.eq)) { lastEquip = v.time; server.remotes.equipBest(); }
    // cross on the ice bridge when it's up (or freeze it from the spot on this bank), else the long way
    crossX = v.iceBridgeActive ? IX : BX;
    if (v.welcome) server.remotes.collectWelcome();
    // buy the cheapest upgrade it can afford (a kid taps Shop when the red "!" shows)
    // while the Forest is shut a kid saves for it (the goal bar shows it) but still buys the cheap early upgrades
    const opts = Config.upgradeIds.filter((id) => v.upgrades[id] < Config.upgrades[id].maxLevel && !(id === 'ray' && v.upgrades.ray >= RAY_CAP))
      .map((id) => ({ id, cost: upgradeCost(id, v.upgrades[id] + 1) })).sort((a, b) => a.cost - b.cost);
    const saving = !v.forestUnlocked ? v.gateCoins : 0;
    if (opts[0] && v.coins >= opts[0].cost && (opts[0].cost <= saving * 0.25 || v.coins - opts[0].cost >= saving)) server.remotes.buyUpgrade(opts[0].id);

    // enough coins for the Forest: walk to the gate and hold the prompt
    if (!v.forestUnlocked && v.coins >= v.gateCoins && !v.carrying.length) {
      const gate = { x: 0, z: World.gate.z - 2.5 };
      if (client.target?.kind === 'gate') { input.state.botMove = { x: 0, z: 0 }; input.state.botInteract = true; return; }
      const wp = waypoint(me, gate), d = dist(wp, me);
      input.state.botMove = d > 0.8 ? { x: (wp.x - me.x) / d, z: (wp.z - me.z) / d } : { x: 0, z: 0 }; input.state.botInteract = false; return;
    }
    const cubes = v.carrying;
    const low = cubes.some((c) => !c.superFrozen && c.life / c.lifeMax < 0.35); // a kid heads home when the cube shows cracks (35%)
    let goal = null, wantInteract = false;
    const candidates = [...v.wild.values()].filter((w) => w.zone === 1 || v.forestUnlocked);
      // once the Forest is open a kid goes there (new pets, 4x income); and a kid goes for the glow: each tier above Common is worth 45 studs of extra walking
    const score = (w) => dist(w, me) - (v.forestUnlocked && w.zone === 2 ? 400 : 0) - (w.state === 'dazed' ? 200 : 0) - 45 * (tierByName[petByKey[w.key].tier].rank - 1);
    candidates.sort((a, b) => score(a) - score(b));
    // a kid who sees a Rare-or-better glow within ~150 studs goes for it (the rarest first)
    const rk = (w) => tierByName[petByKey[w.key].tier].rank;
    const glow = candidates.filter((w) => rk(w) >= 3 && w.state === 'wild' && dist(w, me) < 150).sort((a, b) => rk(b) - rk(a) || dist(a, me) - dist(b, me))[0];
    const near = glow || candidates[0];
    if (cubes.length && (cubes.length >= v.capacity || low || !near || dist(near, me) > 60)) {
      const p = penCenter(); goal = { x: p.x, z: p.z + 2 };
    } else if (near) {
      goal = near;
      if (dist(near, me) < Config.player.freezeRange - 1.5) { wantInteract = true; goal = null; }
    }
    // crossing the river with the bridge down: freeze it from the spot on this bank when that's on the way
    if (goal && !v.iceBridgeActive && v.time > skipIceUntil && side(me.z) !== side(goal.z) && (side(me.z) === 0 || side(goal.z) === 0)) {
      const spot = me.z < R.zMin ? { x: IX, z: R.zMin - 2 } : { x: IX, z: R.zMax + 2 };
      if (client.target?.kind === 'bridge') { wantInteract = true; goal = null; }
      else if (dist(spot, me) < 2.5) skipIceUntil = v.time + 15; // a pet is in the way of the prompt: take the long way this time
      else if (dist(spot, me) < dist({ x: BX, z: spot.z }, me)) goal = spot;
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
