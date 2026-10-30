// CLIENT: input -> movement, prompts -> intent, and everything you see. In Roblox: StarterPlayerScripts
// (movement is the Humanoid, effects/camera here) and the pet/cube visuals. The client never decides
// a freeze, a melt, a bank or a roll; it asks the server and plays what the server says.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { Config, Theme, World, Scenery, PetDefs, petByKey, SizeHeight, CubeSize, zoneById } from './config.js';
import { walkable, dist, iceBridgeCenter, inPen, lightAt } from './world.js';

export function createClient({ server, input, audio, hud, headless }) {
  const view = () => server.view();
  const me = { x: World.spawn.x, z: World.spawn.z, facing: 0, walkPhase: 0 };
  const hold = { target: null, t: 0, need: 1, sent: false };
  let target = null;

  server.on('correctPosition', (p) => { me.x = p.x; me.z = p.z; });

  // ---------------- logic (runs in headless bot mode too) ----------------
  // CLIENT
  function pickTarget(v) {
    let best = null, bestD = Infinity;
    const range = Config.player.freezeRange;
    for (const w of v.wild.values()) {
      const d = Math.hypot(w.x - me.x, w.z - me.z);
      if (d < range && d < bestD) { best = { kind: 'pet', id: w.id, w }; bestD = d; }
    }
    const g = World.giftBox;
    if (v.gift.ready && Math.hypot(g.x - me.x, g.z - me.z) < range && Math.hypot(g.x - me.x, g.z - me.z) < bestD) best = { kind: 'gift', id: 'gift' };
    const ib = iceBridgeCenter();
    if (!v.iceBridgeActive && Math.hypot(ib.x - me.x, ib.z - me.z) < range + 2) best = best || { kind: 'bridge', id: 'bridge' };
    return best;
  }
  // CLIENT
  function step(dt) {
    const v = view(); if (!v) return;
    // movement (in Roblox the Humanoid does this; the server checks speed and position)
    const mv = input.state.move;
    const speed = v.speed;
    const st = { iceBridgeActive: v.iceBridgeActive, forestUnlocked: v.forestUnlocked };
    const busy = hold.target && hold.target.kind !== 'gift' && false;
    if (!busy && (mv.x || mv.z)) {
      const nx = me.x + mv.x * speed * dt, nz = me.z + mv.z * speed * dt;
      if (walkable(nx, nz, st)) { me.x = nx; me.z = nz; }
      else if (walkable(nx, me.z, st)) me.x = nx;
      else if (walkable(me.x, nz, st)) me.z = nz;
      else bumped(v);
      me.facing = Math.atan2(mv.x, mv.z);
      me.walkPhase += dt * speed * 0.6;
    }
    server.remotes.setPosition(me.x, me.z, dt);
    // interaction: hold to freeze (the server times the hold and picks the pose)
    target = pickTarget(v);
    if (hold.target && target && hold.target.id === target.id && target.kind === 'pet') me.facing = Math.atan2(target.w.x - me.x, target.w.z - me.z);
    if (input.state.interact && target) {
      if (!hold.target || hold.target.id !== target.id) {
        if (hold.target) server.remotes.cancelZap();
        hold.target = target; hold.t = 0; hold.sent = false;
        hold.need = target.kind === 'gift' ? Config.player.interactHold
          : target.kind === 'pet' && target.w.state === 'dazed' ? Config.player.refreezeHold : Config.player.freezeHold;
        server.remotes.beginZap(target.id);
        if (target.kind !== 'gift') audio.play('zap');
      }
      hold.t += dt;
      if (hold.t >= hold.need && !hold.sent) { hold.sent = true; server.remotes.endZap(target.id); }
    } else if (hold.target) {
      if (!hold.sent) server.remotes.cancelZap();
      hold.target = null; hold.t = 0;
    }
    if (hold.sent && hold.t > hold.need + 0.2) { hold.target = null; hold.t = 0; } // release-free re-arm
  }
  let bumpAt = -9;
  function bumped(v) {
    const g = World.gate;
    if (!v.forestUnlocked && Math.abs(me.z - g.z) < 4 && v.time - bumpAt > 1.5) {
      bumpAt = v.time;
      const need = zoneById[2].gatePets - v.pets.length;
      hud.notYet(`Need ${need} more ${need === 1 ? 'pet' : 'pets'} in your pen`, worldToScreen(me.x, 4, me.z));
      audio.play('no');
    }
  }

  // ---------------- visuals ----------------
  if (headless) {
    return { step, render() {}, me, get target() { return target; }, hold, worldToScreen: () => null };
  }

  const canvas = document.getElementById('game');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0xdff1ff, 120, 330);
  const camera = new THREE.PerspectiveCamera(Config.camera.fov, 1, 0.5, 1200);
  function resize() { renderer.setSize(innerWidth, innerHeight, false); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); }
  addEventListener('resize', resize); resize();

  scene.add(new THREE.HemisphereLight(0xeaf6ff, 0xb9c7d6, 2.0));
  const sunLight = new THREE.DirectionalLight(0xfff4dc, 1.6); sunLight.position.set(-60, 120, -40); scene.add(sunLight);

  const mat = (c, o = {}) => new THREE.MeshLambertMaterial({ color: c, ...o });
  const flat = (c, o = {}) => new THREE.MeshBasicMaterial({ color: c, ...o });

  // sky dome (layer 1: sky + sun)
  {
    const g = new THREE.SphereGeometry(900, 24, 12);
    const top = new THREE.Color(Theme.sky), bottom = new THREE.Color(Theme.skyHorizon);
    const cols = []; const pos = g.attributes.position;
    for (let i = 0; i < pos.count; i++) { const t = Math.max(0, pos.getY(i) / 900); const c = bottom.clone().lerp(top, Math.pow(t, 0.6)); cols.push(c.r, c.g, c.b); }
    g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
    scene.add(new THREE.Mesh(g, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false })));
    const sun = new THREE.Mesh(new THREE.CircleGeometry(30, 32), flat(Theme.sun, { fog: false }));
    sun.position.set(-260, 300, 500); sun.lookAt(0, 0, 0); scene.add(sun);
  }
  // ground
  function plane(w, d, color, x, z, y = 0) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, d), mat(color)); m.rotation.x = -Math.PI / 2; m.position.set(x, y, z); scene.add(m); return m;
  }
  plane(400, 120, Theme.hub, 0, -60, -0.02);
  plane(400, 172, Theme.snow, 0, 82);
  plane(400, 200, Theme.grass, 0, 285);
  plane(18, 168, Theme.path, 0, 82, 0.02);           // the main path south
  plane(18, 180, '#b6d38f', 0, 280, 0.02);
  { // the river
    const w = plane(400, World.river.zMax - World.river.zMin, Theme.water, 0, (World.river.zMin + World.river.zMax) / 2, -0.3);
    w.material = new THREE.MeshLambertMaterial({ color: Theme.water, emissive: 0x0a3050 });
    plane(400, 3, '#e8f1ff', 0, World.river.zMin - 1, 0.01);
    plane(400, 3, '#9fc979', 0, World.river.zMax + 1, 0.01);
  }
  // main bridge (always there, on the ring route)
  {
    const b = World.mainBridge, cx = (b.xMin + b.xMax) / 2, len = World.river.zMax - World.river.zMin + 6;
    const deck = new THREE.Mesh(new THREE.BoxGeometry(b.xMax - b.xMin, 0.6, len), mat(Theme.wood)); deck.position.set(cx, 0.2, (World.river.zMin + World.river.zMax) / 2); scene.add(deck);
    for (const sx of [b.xMin, b.xMax]) { const r = new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.2, len), mat('#7a4f2e')); r.position.set(sx, 0.9, deck.position.z); scene.add(r); }
  }
  // ice bridge: a glowing freezable spot + the bridge itself
  const iceSpot = new THREE.Mesh(new THREE.CircleGeometry(3.2, 32), flat('#7fe3ff', { transparent: true, opacity: 0.85 }));
  { const c = iceBridgeCenter(); iceSpot.rotation.x = -Math.PI / 2; iceSpot.position.set(c.x, 0.05, c.z); scene.add(iceSpot); }
  const iceBridge = new THREE.Mesh(new THREE.BoxGeometry(World.iceBridgeSpot.xMax - World.iceBridgeSpot.xMin, 0.6, World.river.zMax - World.river.zMin + 6),
    new THREE.MeshLambertMaterial({ color: Theme.ice, transparent: true, opacity: 0.75, emissive: 0x2a6f9a }));
  iceBridge.position.set((World.iceBridgeSpot.xMin + World.iceBridgeSpot.xMax) / 2, 0.2, (World.river.zMin + World.river.zMax) / 2); iceBridge.visible = false; scene.add(iceBridge);

  // the Forest gate: a fence line with an ice gate in the middle
  const gateBars = new THREE.Group();
  {
    const g = World.gate;
    for (let x = World.bounds.xMin; x <= World.bounds.xMax; x += 4) {
      if (x > g.xMin && x < g.xMax) continue;
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.8, 3, 0.8), mat('#8a5a36')); post.position.set(x, 1.5, g.z); scene.add(post);
    }
    const rail = new THREE.Mesh(new THREE.BoxGeometry(World.bounds.xMax - World.bounds.xMin, 0.5, 0.4), mat('#8a5a36')); rail.position.set(0, 2.2, g.z); scene.add(rail);
    for (const x of [g.xMin, g.xMax]) { const p = new THREE.Mesh(new THREE.BoxGeometry(2, 9, 2), mat('#cfefff', { emissive: 0x204060 })); p.position.set(x, 4.5, g.z); scene.add(p); }
    const top = new THREE.Mesh(new THREE.BoxGeometry(g.xMax - g.xMin + 2, 2, 2), mat('#cfefff', { emissive: 0x204060 })); top.position.set(0, 9, g.z); scene.add(top);
    for (let x = g.xMin + 2; x < g.xMax; x += 2.5) { const bar = new THREE.Mesh(new THREE.BoxGeometry(0.7, 7, 0.7), mat('#8fdcff', { emissive: 0x2a7fb0, transparent: true, opacity: 0.9 })); bar.position.set(x, 3.5, g.z); gateBars.add(bar); }
    scene.add(gateBars);
  }
  const gateSign = canvasBoard(14, 5, 512, 180); gateSign.mesh.position.set(0, 12.5, World.gate.z - 0.5); gateSign.mesh.rotation.y = Math.PI; scene.add(gateSign.mesh);

  // trees with shade under them, sun patches
  {
    const trunkG = new THREE.CylinderGeometry(0.5, 0.7, 3, 6), coneG = new THREE.ConeGeometry(1, 1, 7);
    for (const t of Scenery.trees) {
      const grp = new THREE.Group(); grp.position.set(t.x, 0, t.z);
      const trunk = new THREE.Mesh(trunkG, mat('#7a5233')); trunk.position.y = 1.5; grp.add(trunk);
      const h = t.r * 2.2;
      const cols = t.kind === 'snowpine' ? ['#2f6b4f', '#f6fbff'] : ['#2e6a3a', '#3d8a47'];
      for (let i = 0; i < 3; i++) {
        const c = new THREE.Mesh(coneG, mat(cols[i === 2 && t.kind === 'snowpine' ? 1 : 0]));
        const s = t.r * (1 - i * 0.25); c.scale.set(s, h * 0.45, s); c.position.y = 2.5 + i * h * 0.24 + h * 0.2; grp.add(c);
      }
      scene.add(grp);
      const shade = new THREE.Mesh(new THREE.CircleGeometry(t.r, 24), flat(Theme.shade, { transparent: true, opacity: 0.22, depthWrite: false }));
      shade.rotation.x = -Math.PI / 2; shade.position.set(t.x, 0.06, t.z); scene.add(shade);
    }
    for (const s of Scenery.sun) {
      const m = new THREE.Mesh(new THREE.CircleGeometry(s.r, 28), flat('#fff3a0', { transparent: true, opacity: 0.55, depthWrite: false }));
      m.rotation.x = -Math.PI / 2; m.position.set(s.x, 0.07, s.z); m.userData.sun = true; scene.add(m);
    }
  }
  // depth: far scenery (snowy mountains north, dunes and a friendly smoking volcano south)
  {
    const cone = new THREE.ConeGeometry(1, 1, 6);
    const add = (x, z, r, h, c) => { const m = new THREE.Mesh(cone, mat(c)); m.scale.set(r, h, r); m.position.set(x, h / 2 - 2, z); scene.add(m); return m; };
    for (let i = 0; i < 12; i++) add(-260 + i * 48, -190 - (i % 3) * 30, 40 + (i % 4) * 8, 70 + (i % 5) * 18, i % 2 ? '#eef6ff' : '#dce9f7');
    for (let i = 0; i < 14; i++) { add(-150 + (i % 2) * 300, 20 + i * 30, 26, 40 + (i % 3) * 15, i < 7 ? '#e6eff9' : '#7da77a'); }
    for (let i = 0; i < 8; i++) { const d = add(-240 + i * 70, 560 + (i % 2) * 40, 60, 18, '#e8c68a'); d.scale.y = 18; }
    const v = add(120, 720, 90, 150, '#8a5a4a');
    const crater = new THREE.Mesh(new THREE.CylinderGeometry(14, 20, 6, 12), mat('#ff8a3c', { emissive: 0xff5a1a })); crater.position.set(120, 146, 720); scene.add(crater);
    for (let i = 0; i < 5; i++) { const puff = new THREE.Mesh(new THREE.SphereGeometry(14 + i * 4, 10, 8), mat('#f4efe9')); puff.position.set(120 + i * 9, 160 + i * 22, 720 - i * 6); puff.userData.puff = i; scene.add(puff); }
  }
  // drifting clouds (far layer)
  const clouds = [];
  for (let i = 0; i < 10; i++) {
    const c = new THREE.Group();
    for (let j = 0; j < 4; j++) { const s = new THREE.Mesh(new THREE.SphereGeometry(8 + j * 2, 10, 8), mat('#ffffff')); s.position.set(j * 9, (j % 2) * 3, 0); c.add(s); }
    c.position.set(-300 + i * 70, 110 + (i % 3) * 18, -120 + i * 70); scene.add(c); clouds.push(c);
  }

  // hub: pen, spawn pad, gift box, boards, signs
  {
    const p = World.pen;
    plane(p.xMax - p.xMin, p.zMax - p.zMin, '#f7e3b0', (p.xMin + p.xMax) / 2, (p.zMin + p.zMax) / 2, 0.03);
    const postG = new THREE.BoxGeometry(0.7, 2.2, 0.7);
    const fence = (x1, z1, x2, z2) => {
      const n = Math.ceil(Math.hypot(x2 - x1, z2 - z1) / 3);
      for (let i = 0; i <= n; i++) { const m = new THREE.Mesh(postG, mat('#c9874f')); m.position.set(x1 + ((x2 - x1) * i) / n, 1.1, z1 + ((z2 - z1) * i) / n); scene.add(m); }
    };
    fence(p.xMin, p.zMin, p.xMax, p.zMin); fence(p.xMin, p.zMin, p.xMin, p.zMax); fence(p.xMax, p.zMin, p.xMax, p.zMax);
    fence(p.xMin, p.zMax, -5, p.zMax); fence(5, p.zMax, p.xMax, p.zMax); // open front
    // the pen sign is painted on the floor: readable from the camera and never between it and the player
    const sign = canvasBoard(12, 3, 512, 130); sign.draw((c, w, h) => boardText(c, w, h, 'YOUR PEN', '#ff9f1c'));
    sign.mesh.rotation.set(-Math.PI / 2, 0, Math.PI); sign.mesh.position.set(0, 0.06, p.zMin + 3.5); scene.add(sign.mesh);
    const pad = new THREE.Mesh(new THREE.CylinderGeometry(3.5, 3.8, 0.4, 24), mat('#7fd3ff')); pad.position.set(World.spawn.x, 0.2, World.spawn.z); scene.add(pad);
  }
  const giftBox = new THREE.Group();
  {
    const box = new THREE.Mesh(new THREE.BoxGeometry(3, 2.4, 3), mat('#ff5a8a', { emissive: 0x401020 })); box.position.y = 1.2; giftBox.add(box);
    const lid = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.7, 3.4), mat('#ff86a8')); lid.position.y = 2.6; giftBox.add(lid);
    const rib1 = new THREE.Mesh(new THREE.BoxGeometry(0.6, 3.2, 3.5), mat('#ffd34a')); rib1.position.y = 1.5; giftBox.add(rib1);
    const rib2 = new THREE.Mesh(new THREE.BoxGeometry(3.5, 3.2, 0.6), mat('#ffd34a')); rib2.position.y = 1.5; giftBox.add(rib2);
    giftBox.position.set(World.giftBox.x, 0, World.giftBox.z); scene.add(giftBox);
  }
  const giftLabel = canvasBoard(6, 1.6, 384, 100); giftLabel.mesh.position.set(World.giftBox.x, 5.4, World.giftBox.z); giftLabel.mesh.rotation.y = Math.PI; scene.add(giftLabel.mesh);
  const boards = World.boards.map((b) => {
    const cb = canvasBoard(14, 18, 512, 660);
    const frame = new THREE.Mesh(new THREE.BoxGeometry(15, 19, 0.8), mat('#5b3fa8')); frame.position.set(b.x, 10.5, b.z + 0.5);
    const leg = new THREE.Mesh(new THREE.BoxGeometry(1, 2, 1), mat('#5b3fa8')); leg.position.set(b.x, 0.6, b.z + 0.5);
    cb.mesh.position.set(b.x, 10.5, b.z - 0.05); cb.mesh.rotation.y = Math.PI;
    scene.add(frame, leg, cb.mesh); return cb;
  });
  const zoneSigns = World.zones.map((z) => {
    const cb = canvasBoard(11, 9, 512, 420); cb.mesh.position.set(z.sign.x, 6, z.sign.z); cb.mesh.rotation.y = Math.PI;
    const post = new THREE.Mesh(new THREE.BoxGeometry(0.8, 3, 0.8), mat('#8a5a36')); post.position.set(z.sign.x, 0.8, z.sign.z + 0.3);
    scene.add(cb.mesh, post); return { zone: z, cb };
  });

  // player avatar (blocky, Roblox-like) with the ice ray
  const avatar = new THREE.Group();
  const avParts = {};
  {
    const add = (name, w, h, d, c, x, y, z) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(c)); m.position.set(x, y, z); avatar.add(m); avParts[name] = m; return m; };
    add('torso', 2, 2, 1, '#3aa8ff', 0, 3, 0); add('head', 1.3, 1.3, 1.3, '#ffd6a5', 0, 4.7, 0);
    add('legL', 0.9, 2, 0.9, '#2d3561', -0.5, 1, 0); add('legR', 0.9, 2, 0.9, '#2d3561', 0.5, 1, 0);
    add('armL', 0.8, 2, 0.8, '#ffd6a5', -1.4, 3, 0); add('armR', 0.8, 2, 0.8, '#ffd6a5', 1.4, 3, 0);
    const gun = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.45, 1.8, 10), mat('#7fe3ff', { emissive: 0x1d6f9a })); gun.rotation.x = Math.PI / 2; gun.position.set(1.4, 2.4, 0.9); avatar.add(gun); avParts.gun = gun;
    const face = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.5), flat('#1b1433')); face.position.set(0, 4.6, 0.66); avatar.add(face);
    scene.add(avatar);
  }
  const shadowG = new THREE.CircleGeometry(1, 20), shadowM = flat('#1b1433', { transparent: true, opacity: 0.25, depthWrite: false });
  const blob = (r) => { const s = new THREE.Mesh(shadowG, shadowM); s.rotation.x = -Math.PI / 2; s.scale.setScalar(r); s.position.y = 0.08; return s; };
  const avShadow = blob(1.6); scene.add(avShadow);

  // ---------- pets: sprite from the concept, or the real 3D model ----------
  const texLoader = new THREE.TextureLoader();
  const spriteTex = {};
  for (const p of PetDefs) { const t = texLoader.load(`assets/sprites/${p.key}.webp`); t.colorSpace = THREE.SRGBColorSpace; spriteTex[p.key] = t; }
  const models = {};
  const gltf = new GLTFLoader();
  const modelPromises = PetDefs.filter((p) => p.model).map((p) => new Promise((res) => gltf.load(p.model, (g) => { models[p.key] = g.scene; res(); }, undefined, () => res())));
  const ready = Promise.all(modelPromises);

  function makePetVisual(key, opts = {}) {
    const def = petByKey[key], h = SizeHeight[def.size];
    const root = new THREE.Group(); const body = new THREE.Group(); root.add(body);
    if (models[key]) {
      const m = models[key].clone(true);
      const box = new THREE.Box3().setFromObject(m), size = box.getSize(new THREE.Vector3()), c = box.getCenter(new THREE.Vector3());
      m.position.set(-c.x, -box.min.y, -c.z);
      const holder = new THREE.Group(); holder.add(m); holder.scale.setScalar(h / size.y); holder.rotation.y = Math.PI - 0.45;
      body.add(holder); root.userData.model = true;
      if (opts.tint) holder.traverse((o) => { if (o.material) { o.material = o.material.clone(); o.material.color = new THREE.Color(opts.tint); } });
    } else {
      const sm = new THREE.SpriteMaterial({ map: spriteTex[key], transparent: true, alphaTest: 0.25, color: opts.tint || 0xffffff });
      const s = new THREE.Sprite(sm); s.center.set(0.5, 0); s.scale.set(h * 1.15, h * 1.15, 1); body.add(s); root.userData.sprite = s;
    }
    root.userData.h = h; root.userData.body = body;
    return root;
  }
  // a pose as a transform (shared by wild loops and frozen cubes)
  function applyPose(root, pose, t, frozen) {
    const b = root.userData.body, h = root.userData.h, s = root.userData.sprite;
    let y = 0, sx = 1, sy = 1, rot = 0;
    const k = frozen ? 0.5 : (Math.sin(t * Math.PI * 2 / 0.8) + 1) / 2;
    switch (pose) {
      case 'idle': y = frozen ? 0 : Math.sin(t * 4) * 0.06 * h; break;
      case 'yawn': sy = 1 + 0.16 * (frozen ? 1 : Math.min(1, t)); sx = 1 - 0.06; rot = -0.08; break;
      case 'jump': y = (frozen ? 0.35 : Math.sin(Math.min(1, t / 0.9) * Math.PI)) * 0.45 * h; sy = 1.08; sx = 0.95; break;
      case 'dance': rot = (frozen ? 1 : Math.sin(t * 10)) * 0.28; y = (frozen ? 0.05 : k * 0.12) * h; break;
      case 'sneeze': sy = 0.82; sx = 1.16; rot = 0.14; break;
      case 'dazed': rot = Math.sin(t * 3) * 0.15; break;
    }
    b.position.y = y; b.scale.set(sx, sy, 1 * sx);
    if (s) s.material.rotation = rot; else b.rotation.z = rot;
  }

  // ---------- ice cubes ----------
  const cubeGeo = new THREE.BoxGeometry(1, 1, 1);
  const edgeGeo = new THREE.EdgesGeometry(cubeGeo);
  function makeCube(cube) {
    const def = petByKey[cube.key];
    const g = new THREE.Group();
    const size = CubeSize[def.size] * (1 + Config.upgrades.ray.cubeSizeBonus * (view().upgrades.ray - 1));
    const pet = makePetVisual(cube.key, { tint: cube.mut === 'Frosty' ? '#d4f1ff' : null });
    pet.scale.setScalar((size * 0.82) / (pet.userData.h * 1.15)); pet.position.y = -size * 0.42; g.add(pet);
    applyPose(pet, cube.pose, 0, true);
    const iceMat = new THREE.MeshLambertMaterial({ color: cube.superFrozen ? Theme.iceDeep : Theme.ice, transparent: true, opacity: cube.superFrozen ? 0.6 : 0.42, depthWrite: false, emissive: cube.superFrozen ? 0x10308a : 0x2a6f9a });
    const ice = new THREE.Mesh(cubeGeo, iceMat); ice.renderOrder = 2; g.add(ice);
    const edges = new THREE.LineSegments(edgeGeo, new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.9 })); g.add(edges);
    const cracks = new THREE.LineSegments(crackGeo(), new THREE.LineBasicMaterial({ color: 0xffffff })); cracks.visible = false; g.add(cracks);
    ice.scale.setScalar(size); edges.scale.setScalar(size); cracks.scale.setScalar(size * 1.01);
    g.userData = { size, ice, iceMat, cracks, pet, cube };
    return g;
  }
  function crackGeo() {
    const pts = [];
    for (let f = 0; f < 3; f++) for (let i = 0; i < 3; i++) {
      let x = (Math.random() - 0.5) * 0.6, y = (Math.random() - 0.5) * 0.6;
      for (let j = 0; j < 3; j++) { const nx = x + (Math.random() - 0.5) * 0.35, ny = y + (Math.random() - 0.5) * 0.35; pts.push(...fp(f, x, y), ...fp(f, nx, ny)); x = nx; y = ny; }
    }
    function fp(f, a, b) { return f === 0 ? [a, b, 0.5] : f === 1 ? [0.5, a, b] : [a, 0.5, b]; }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3)); return g;
  }

  // ---------- particles ----------
  const particles = [];
  const partGeo = new THREE.BoxGeometry(0.35, 0.35, 0.35);
  function burst(x, y, z, color, n = 14, speed = 8, life = 0.7) {
    for (let i = 0; i < n; i++) {
      const m = new THREE.Mesh(partGeo, flat(color, { transparent: true }));
      m.position.set(x, y, z);
      const v = new THREE.Vector3((Math.random() - 0.5) * 2, Math.random() * 1.5 + 0.3, (Math.random() - 0.5) * 2).normalize().multiplyScalar(speed * (0.5 + Math.random() * 0.5));
      scene.add(m); particles.push({ m, v, life, max: life });
    }
  }
  function tickParticles(dt) {
    for (const p of [...particles]) {
      p.life -= dt; p.v.y -= 18 * dt; p.m.position.addScaledVector(p.v, dt); p.m.rotation.x += dt * 5;
      p.m.material.opacity = Math.max(0, p.life / p.max);
      if (p.life <= 0) { scene.remove(p.m); p.m.material.dispose(); particles.splice(particles.indexOf(p), 1); }
    }
  }
  // snow during the Big Chill
  const snow = new THREE.Points(new THREE.BufferGeometry(), new THREE.PointsMaterial({ color: 0xffffff, size: 0.6, transparent: true, opacity: 0.9 }));
  { const n = 900, a = new Float32Array(n * 3); for (let i = 0; i < n; i++) { a[i * 3] = (Math.random() - 0.5) * 120; a[i * 3 + 1] = Math.random() * 40; a[i * 3 + 2] = (Math.random() - 0.5) * 120; } snow.geometry.setAttribute('position', new THREE.BufferAttribute(a, 3)); }
  snow.visible = false; scene.add(snow);

  // ray beam
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 1, 8, 1, true), flat('#9ff0ff', { transparent: true, opacity: 0.85 }));
  beam.visible = false; scene.add(beam);
  // green guide arrow on the ground
  const arrow = new THREE.Mesh(new THREE.ConeGeometry(1.1, 2.6, 3), flat('#3ccf6e')); arrow.rotation.x = Math.PI / 2; const arrowG = new THREE.Group(); arrowG.add(arrow); scene.add(arrowG);

  // ---------- entity sync from replicated state ----------
  const wildVis = new Map();
  const carriedVis = new Map();
  const penVis = [];
  function syncWild(v, t) {
    for (const [id, w] of v.wild) {
      let e = wildVis.get(id);
      if (!e) {
        const def = petByKey[w.key];
        const root = makePetVisual(w.key, { tint: w.mut === 'Frosty' ? '#d4f1ff' : null });
        const ring = new THREE.Mesh(new THREE.RingGeometry(1.2, 1.6, 28), flat(Theme.tiers[def.tier], { transparent: true, opacity: 0.85, side: THREE.DoubleSide }));
        ring.rotation.x = -Math.PI / 2; ring.position.y = 0.1; ring.scale.setScalar(root.userData.h / 2.4);
        const sh = blob(root.userData.h * 0.42);
        const stars = new THREE.Group();
        for (let i = 0; i < 3; i++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.28), flat('#ffffff')); s.position.set(Math.cos(i * 2.1) * 0.9, 0, Math.sin(i * 2.1) * 0.9); stars.add(s); }
        stars.position.y = root.userData.h * 1.25; stars.visible = false;
        const g = new THREE.Group(); g.add(root, ring, sh, stars); scene.add(g);
        e = { g, root, ring, stars, born: t, actionStart: t, action: null };
        wildVis.set(id, e);
      }
      e.g.position.set(w.x, 0, w.z);
      if (w.action !== e.action) { e.action = w.action; e.actionStart = t; if (w.action === 'sneeze') burst(w.x, e.root.userData.h * 0.8, w.z, '#ffffff', 6, 3, 0.4); }
      const dazed = w.state === 'dazed';
      applyPose(e.root, dazed ? 'dazed' : w.action, t - e.actionStart, false);
      e.stars.visible = dazed; e.stars.rotation.y = t * 3;
      e.ring.material.opacity = 0.55 + Math.sin(t * 4) * 0.3;
      const tier = petByKey[w.key].tier;
      if (['Rare', 'Epic', 'Legendary', 'Mythic', 'Secret'].includes(tier) && Math.random() < 0.02) burst(w.x + (Math.random() - 0.5) * 2, e.root.userData.h * Math.random(), w.z, Theme.tiers[tier], 1, 1.5, 0.6);
      const appear = Math.min(1, (t - e.born) / 0.25); e.g.scale.setScalar(appear < 1 ? appear * 1.08 : 1);
    }
    for (const [id, e] of wildVis) if (!v.wild.has(id)) { scene.remove(e.g); wildVis.delete(id); }
  }
  function syncCarried(v, t) {
    const ids = new Set(v.carrying.map((c) => c.uid));
    for (const [uid, g] of carriedVis) if (!ids.has(uid)) { scene.remove(g); carriedVis.delete(uid); }
    let y = 2.4;
    v.carrying.forEach((c, i) => {
      let g = carriedVis.get(c.uid);
      if (!g) { g = makeCube(c); scene.add(g); carriedVis.set(c.uid, g); g.userData.born = t; }
      const frac = c.superFrozen ? 1 : Math.max(0, c.life / c.lifeMax);
      const back = 0.62; // carried cubes are smaller so they never hide the player's head
      const s = (0.55 + 0.45 * frac) * back;
      const size = g.userData.size * s;
      const behind = -1.6 - size / 2;
      const fx = Math.sin(me.facing), fz = Math.cos(me.facing);
      g.position.set(me.x + fx * behind, y + size / 2, me.z + fz * behind);
      y += size + 0.15;
      g.scale.setScalar(s); g.rotation.y = me.facing;
      g.userData.cracks.visible = frac < 0.35;
      const flash = frac < 0.15 && Math.sin(t * 14) > 0;
      g.userData.iceMat.emissive.setHex(c.superFrozen ? 0x10308a : flash ? 0x5ab8ff : 0x2a6f9a);
      if (!c.superFrozen && frac < 0.6 && Math.random() < 0.08) burst(g.position.x, g.position.y - size / 2, g.position.z, '#bfe9ff', 1, 1, 0.5); // drips
    });
  }
  function syncPen(v, t) {
    const show = v.pets.slice(-30);
    while (penVis.length < show.length) {
      const p = show[penVis.length];
      const root = makePetVisual(p.key, { tint: p.mut === 'Frosty' ? '#d4f1ff' : null });
      const pp = World.pen;
      const x = pp.xMin + 2 + Math.random() * (pp.xMax - pp.xMin - 4), z = pp.zMin + 2 + Math.random() * (pp.zMax - pp.zMin - 6);
      const g = new THREE.Group(); g.add(root, blob(root.userData.h * 0.4)); g.position.set(x, 0, z); scene.add(g);
      penVis.push({ g, root, pose: p.pose, phase: Math.random() * 6, born: t });
    }
    for (const e of penVis) {
      const age = t - e.born;
      applyPose(e.root, age < 1.2 ? 'dance' : e.pose, age < 1.2 ? age : (t + e.phase) % 2.5, age >= 1.2);
      if (age >= 1.2) e.root.userData.body.position.y += Math.abs(Math.sin(t * 2 + e.phase)) * 0.15;
    }
  }

  // ---------- canvas boards (leaderboards, signs) ----------
  function canvasBoard(w, h, pw, ph) {
    const c = document.createElement('canvas'); c.width = pw; c.height = ph;
    const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace;
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tex, transparent: true }));
    return { mesh, draw(fn) { const ctx = c.getContext('2d'); ctx.clearRect(0, 0, pw, ph); fn(ctx, pw, ph); tex.needsUpdate = true; } };
  }
  function roundRect(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
  function boardText(ctx, w, h, text, color) {
    roundRect(ctx, 4, 4, w - 8, h - 8, 22); ctx.fillStyle = color; ctx.fill(); ctx.lineWidth = 8; ctx.strokeStyle = Theme.ink; ctx.stroke();
    let size = Math.floor(h * 0.5);
    ctx.font = `700 ${size}px Fredoka, sans-serif`;
    while (ctx.measureText(text).width > w - 48 && size > 10) { size -= 2; ctx.font = `700 ${size}px Fredoka, sans-serif`; } // shrink to fit
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.lineWidth = 10; ctx.strokeStyle = Theme.ink; ctx.strokeText(text, w / 2, h / 2 + 2); ctx.fillStyle = '#fff'; ctx.fillText(text, w / 2, h / 2 + 2);
  }
  function drawBoard(cb, def, data) {
    cb.draw((ctx, w, h) => {
      roundRect(ctx, 6, 6, w - 12, h - 12, 26); ctx.fillStyle = '#2b1f5c'; ctx.fill(); ctx.lineWidth = 10; ctx.strokeStyle = Theme.ink; ctx.stroke();
      ctx.textAlign = 'center'; ctx.font = '700 38px Fredoka, sans-serif'; ctx.fillStyle = '#ffd34a'; ctx.fillText(def.title, w / 2, 58);
      ctx.font = '600 22px Fredoka, sans-serif'; ctx.fillStyle = '#bfb6ff';
      ctx.fillText(def.kind === 'weekly' ? Config.leaderboards.weeklyResetLabel : 'All time', w / 2, 90);
      if (!data) return;
      data.rows.forEach((r, i) => {
        const y = 132 + i * 42;
        if (r.me) { roundRect(ctx, 22, y - 30, w - 44, 38, 10); ctx.fillStyle = '#3ccf6e'; ctx.fill(); }
        ctx.textAlign = 'left'; ctx.font = '700 26px Fredoka, sans-serif';
        ctx.fillStyle = i < 3 ? ['#ffd34a', '#e6eef9', '#ffb27a'][i] : '#ffffff';
        ctx.fillText(`${r.rank}.`, 34, y); ctx.fillStyle = '#ffffff'; ctx.fillText(r.name.slice(0, 16), 84, y);
        ctx.textAlign = 'right'; ctx.fillText(r.score, w - 34, y);
      });
      const y = 132 + 10 * 42 + 6;
      ctx.strokeStyle = '#6b5fb8'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(30, y - 22); ctx.lineTo(w - 30, y - 22); ctx.stroke();
      roundRect(ctx, 22, y - 8, w - 44, 44, 12); ctx.fillStyle = '#3ccf6e'; ctx.fill();
      ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.font = '700 26px Fredoka, sans-serif'; ctx.fillText(`You: #${data.me.rank}`, 34, y + 23);
      ctx.textAlign = 'right'; ctx.fillText(data.me.score, w - 34, y + 23);
      ctx.textAlign = 'center'; ctx.font = '500 19px Fredoka, sans-serif'; ctx.fillStyle = '#bfb6ff';
      ctx.fillText(def.kind === 'weekly' ? Config.leaderboards.cosmeticReward : 'Updates every minute', w / 2, h - 22);
    });
  }
  function drawZoneSign(zs) {
    const odds = server.shownOdds(zs.zone.id);
    zs.cb.draw((ctx, w, h) => {
      roundRect(ctx, 6, 6, w - 12, h - 12, 26); ctx.fillStyle = '#fff8ec'; ctx.fill(); ctx.lineWidth = 10; ctx.strokeStyle = Theme.ink; ctx.stroke();
      ctx.textAlign = 'center'; ctx.font = '700 40px Fredoka, sans-serif'; ctx.fillStyle = Theme.ink; ctx.fillText(zs.zone.name, w / 2, 56);
      ctx.font = '600 22px Fredoka, sans-serif'; ctx.fillStyle = '#5a4f8a'; ctx.fillText(`Melt speed x${zs.zone.heat}  ·  shade melts slower`, w / 2, 88);
      Config.tiers.forEach((t, i) => {
        const y = 128 + i * 40;
        ctx.fillStyle = Theme.tiers[t.name]; ctx.beginPath(); ctx.arc(60, y - 8, 12, 0, Math.PI * 2); ctx.fill(); ctx.lineWidth = 4; ctx.stroke();
        ctx.textAlign = 'left'; ctx.fillStyle = Theme.ink; ctx.font = '600 26px Fredoka, sans-serif'; ctx.fillText(t.name, 86, y);
        const o = odds[t.name]; ctx.textAlign = 'right'; ctx.fillText(o >= 1 ? `${o.toFixed(1)}%` : o >= 0.01 ? `${o.toFixed(2)}%` : `1 in ${Math.round(100 / o).toLocaleString()}`, w - 40, y);
      });
    });
  }
  let lastBoards = null, signAt = -99, lastGate = null, lastGift = null;

  // ---------- server events -> effects ----------
  server.on('frozen', ({ petId, cube, superFrozen }) => {
    const e = wildVis.get(petId); const x = e ? e.g.position.x : me.x, z = e ? e.g.position.z : me.z;
    burst(x, 2, z, superFrozen ? '#2f6bff' : '#ffffff', 20, 9);
    audio.play('freeze');
  });
  server.on('banked', ({ banked }) => {
    banked.forEach((b, i) => setTimeout(() => {
      const p = World.pen; burst((p.xMin + p.xMax) / 2, 3, (p.zMin + p.zMax) / 2, '#bfe9ff', 22, 10, 0.8);
      const tier = petByKey[b.cube.key].tier;
      audio.play(['Rare', 'Epic', 'Legendary', 'Mythic', 'Secret'].includes(tier) ? 'reveal_rare' : 'bank');
      hud.floatAt(`+${fmt(b.income)}/s`, worldToScreen(me.x, 6, me.z), '#ffd34a');
    }, i * 250));
  });
  server.on('melted', ({ petId }) => { audio.play('melt'); burst(me.x, 3, me.z, '#bfe9ff', 16, 6); });
  server.on('bridge', ({ until }) => { if (until > 0) { audio.play('bridge'); const c = iceBridgeCenter(); burst(c.x, 1, c.z + 8, '#bfe9ff', 30, 10); } });
  server.on('zoneUnlocked', () => { audio.play('unlock'); burst(0, 8, World.gate.z, '#3ccf6e', 40, 14, 1.2); });
  server.on('giftClaimed', () => { audio.play('gift'); burst(World.giftBox.x, 3, World.giftBox.z, '#ffd34a', 30, 10, 1); });

  // ---------- frame ----------
  const camPos = new THREE.Vector3(me.x, Config.camera.height, me.z - Config.camera.back);
  let t = 0;
  function render(dt) {
    const v = view(); if (!v) return;
    t += dt;
    // avatar
    avatar.position.set(me.x, 0, me.z); avatar.rotation.y = me.facing;
    const moving = input.state.move.x || input.state.move.z;
    const sw = moving ? Math.sin(me.walkPhase) * 0.6 : 0;
    avParts.legL.rotation.x = sw; avParts.legR.rotation.x = -sw; avParts.armL.rotation.x = -sw;
    avParts.armR.rotation.x = hold.target ? -1.4 : sw;
    avShadow.position.set(me.x, 0.08, me.z);
    // camera: behind and above, looking south toward the next zone
    const want = new THREE.Vector3(me.x, Config.camera.height, me.z - Config.camera.back);
    camPos.lerp(want, 1 - Math.pow(0.001, dt));
    camera.position.copy(camPos); camera.lookAt(me.x, 1, me.z + Config.camera.lookAhead);
    syncWild(v, t); syncCarried(v, t); syncPen(v, t); tickParticles(dt);
    // ray beam while zapping
    if (hold.target && hold.target.kind !== 'gift') {
      const tp = hold.target.kind === 'bridge' ? iceBridgeCenter() : (v.wild.get(hold.target.id) || {});
      if (tp.x !== undefined) {
        const a = new THREE.Vector3(me.x + Math.sin(me.facing) * 1.4, 2.4, me.z + Math.cos(me.facing) * 1.4), b = new THREE.Vector3(tp.x, 1.4, tp.z);
        beam.visible = true; beam.position.copy(a).add(b).multiplyScalar(0.5); beam.scale.set(1, a.distanceTo(b), 1);
        beam.lookAt(b); beam.rotateX(Math.PI / 2); beam.material.opacity = 0.5 + Math.random() * 0.4;
        if (Math.random() < 0.3) burst(tp.x, 1.5, tp.z, '#dff6ff', 1, 3, 0.4);
      } else beam.visible = false;
    } else beam.visible = false;
    // guide arrow: to a pet when empty-handed in the first minutes, home when carrying
    let goal = null;
    if (v.carrying.length) goal = { x: 0, z: (World.pen.zMin + World.pen.zMax) / 2 };
    else if (v.pets.length < 3) { let bd = 1e9; for (const w of v.wild.values()) { const d = dist(w, me); if (d < bd && w.zone === 1) { bd = d; goal = w; } } }
    arrowG.visible = !!goal && !(goal && dist(goal, me) < 6);
    if (goal) { const ang = Math.atan2(goal.x - me.x, goal.z - me.z); arrowG.position.set(me.x + Math.sin(ang) * 4.5, 0.6 + Math.sin(t * 5) * 0.2, me.z + Math.cos(ang) * 4.5); arrowG.rotation.y = ang; }
    // world state
    iceBridge.visible = v.iceBridgeActive; iceSpot.material.opacity = v.iceBridgeActive ? 0.25 : 0.6 + Math.sin(t * 4) * 0.3;
    if (v.iceBridgeActive) { const left = v.iceBridgeUntil - v.time; iceBridge.material.opacity = left < 4 && Math.sin(t * 12) > 0 ? 0.35 : 0.75; }
    gateBars.position.y += ((v.forestUnlocked ? -8 : 0) - gateBars.position.y) * Math.min(1, dt * 3);
    snow.visible = v.chill.active; if (snow.visible) { snow.position.set(me.x, 0, me.z); const a = snow.geometry.attributes.position; for (let i = 0; i < a.count; i++) { let y = a.getY(i) - dt * 8; if (y < 0) y += 40; a.setY(i, y); } a.needsUpdate = true; }
    scene.fog.color.set(v.chill.active ? 0xf2fbff : 0xdff1ff);
    clouds.forEach((c, i) => { c.position.x += dt * (0.8 + (i % 3) * 0.3); if (c.position.x > 340) c.position.x = -340; });
    giftBox.rotation.y = v.gift.ready ? Math.sin(t * 2) * 0.15 : 0; giftBox.position.y = v.gift.ready ? Math.abs(Math.sin(t * 3)) * 0.6 : 0;
    // boards and signs (redrawn only when their data changes)
    if (v.boards && v.boards !== lastBoards) { lastBoards = v.boards; Config.leaderboards.boards.forEach((b, i) => drawBoard(boards[i], b, v.boards[b.id])); }
    if (t - signAt > 3) { signAt = t; zoneSigns.forEach(drawZoneSign); }
    const gateKey = v.forestUnlocked ? 'open' : v.pets.length;
    if (gateKey !== lastGate) { lastGate = gateKey; gateSign.draw((c, w, h) => boardText(c, w, h, v.forestUnlocked ? 'PINE FOREST' : `${v.pets.length} / ${zoneById[2].gatePets} pets in pen`, v.forestUnlocked ? '#3ccf6e' : '#3aa8ff')); }
    const giftKey = v.gift.ready ? 'ready' : 'later';
    if (giftKey !== lastGift) { lastGift = giftKey; giftLabel.draw((c, w, h) => boardText(c, w, h, v.gift.ready ? 'DAILY GIFT' : 'NEXT GIFT TOMORROW', v.gift.ready ? '#ff5a8a' : '#9aa5b1')); }
    renderer.render(scene, camera);
  }

  const tmpV = new THREE.Vector3();
  function worldToScreen(x, y, z) {
    tmpV.set(x, y, z).project(camera);
    if (tmpV.z > 1) return null;
    return { x: (tmpV.x * 0.5 + 0.5) * innerWidth, y: (-tmpV.y * 0.5 + 0.5) * innerHeight };
  }
  const fmt = (n) => (n >= 100 ? Math.round(n).toLocaleString() : (Math.round(n * 10) / 10).toString());
  return { step, render, me, get target() { return target; }, hold, worldToScreen, ready, lightAtPlayer: () => lightAt(me.x, me.z) };
}
