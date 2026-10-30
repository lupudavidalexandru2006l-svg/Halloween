// CLIENT: input -> movement, prompts -> intent, and everything you see. In Roblox: StarterPlayerScripts
// (movement is the Humanoid, effects/camera here) and the pet/cube visuals. The client never decides
// a freeze, a melt, a bank or a roll; it asks the server and plays what the server says.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { buildWorld } from './scenery.js';
import { Config, Theme, World, PetDefs, petByKey, SizeHeight, CubeSize, zoneById } from './config.js';
import { walkable, dist, iceBridgeCenter, lightAt, zoneTemperature } from './world.js';

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
  const LOW = Config.graphics.low;
  renderer.setPixelRatio(LOW ? 1 : Math.min(devicePixelRatio, 1.5));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.25;
  renderer.shadowMap.enabled = !LOW; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0xe4f3ff, 150, 460);
  const pmrem = new THREE.PMREMGenerator(renderer);
  if (!LOW) { scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture; scene.environmentIntensity = 0.35; }
  const camera = new THREE.PerspectiveCamera(Config.camera.fov, 1, 0.5, 1600);
  function resize() { renderer.setSize(innerWidth, innerHeight, false); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); }
  addEventListener('resize', resize); resize();

  // light: a warm sun from the top left (it follows the player so shadows stay sharp nearby) + sky fill
  scene.add(new THREE.HemisphereLight(0xe6f4ff, 0xc9d3e2, 1.05));
  const sunLight = new THREE.DirectionalLight(0xfff0d8, 2.4);
  sunLight.castShadow = !LOW; sunLight.shadow.mapSize.set(Config.graphics.shadowMap, Config.graphics.shadowMap);
  Object.assign(sunLight.shadow.camera, { left: -45, right: 45, top: 45, bottom: -45, near: 1, far: 240 });
  sunLight.shadow.bias = -0.0004; sunLight.shadow.normalBias = 0.03; sunLight.shadow.radius = 4;
  scene.add(sunLight, sunLight.target);
  const SUN_OFFSET = new THREE.Vector3(55, 95, -45);

  const W = buildWorld(scene);
  const std = (c, o = {}) => new THREE.MeshStandardMaterial({ color: c, roughness: 0.8, ...o });
  const flat = (c, o = {}) => new THREE.MeshBasicMaterial({ color: c, ...o });

  // ---------- canvas boards (leaderboards, signs) ----------
  const iconImg = {};
  for (const n of ['trophy', 'gift', 'coin']) { const im = new Image(); im.src = `assets/icons/${n}.webp`; iconImg[n] = im; }
  function canvasBoard(w, h, pw, ph) {
    const c = document.createElement('canvas'); c.width = pw; c.height = ph;
    const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 4;
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tex, transparent: true, toneMapped: false }));
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
  function framed(w, h, pw, ph, x, z, postH, color = '#8a5a36') {
    const cb = canvasBoard(w, h, pw, ph);
    const g = new THREE.Group();
    const frame = new THREE.Mesh(new RoundedBoxGeometry(w + 1, h + 1, 0.7, 3, 0.3), std(color)); frame.position.set(0, postH + h / 2, 0.4); frame.castShadow = true; g.add(frame);
    for (const px of [-w / 2 + 1, w / 2 - 1]) { const post = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.4, postH + 1, 8), std(color)); post.position.set(px, (postH + 1) / 2, 0.6); post.castShadow = true; g.add(post); }
    cb.mesh.position.set(0, postH + h / 2, 0); cb.mesh.rotation.y = Math.PI; g.add(cb.mesh);
    g.position.set(x, 0, z); scene.add(g);
    return cb;
  }
  const boards = World.boards.map((b) => framed(12, 15.5, 512, 660, b.x, b.z, 1.2, '#5b3fa8'));
  const zoneSigns = World.zones.map((z) => ({ zone: z, cb: framed(10, 8.2, 512, 420, z.sign.x, z.sign.z, 1.6) }));
  const gateSign = canvasBoard(13, 3.6, 512, 140); gateSign.mesh.position.set(0, 14.2, World.gate.z - 1); gateSign.mesh.rotation.y = Math.PI; scene.add(gateSign.mesh);
  { // the pen sign is painted on the floor: readable from the camera and never between it and the player
    const p = World.pen, sign = canvasBoard(12, 3, 512, 130); sign.draw((c, w, h) => boardText(c, w, h, 'YOUR PEN', '#ff9f1c'));
    sign.mesh.rotation.set(-Math.PI / 2, 0, Math.PI); sign.mesh.position.set(0, 0.42, p.zMin + 3.5); scene.add(sign.mesh);
  }
  // the gift box: rounded, ribboned, bobbing when a gift is waiting
  const giftBox = new THREE.Group();
  {
    const body = new THREE.Mesh(new RoundedBoxGeometry(3, 2.4, 3, 3, 0.3), std('#ff5a8a', { roughness: 0.5 })); body.position.y = 1.2;
    const lid = new THREE.Mesh(new RoundedBoxGeometry(3.4, 0.8, 3.4, 3, 0.3), std('#ff7ca3', { roughness: 0.5 })); lid.position.y = 2.7;
    const gold = std('#ffd34a', { roughness: 0.35, metalness: 0.3 });
    const r1 = new THREE.Mesh(new THREE.BoxGeometry(0.6, 3.25, 3.5), gold); r1.position.y = 1.6; const r2 = r1.clone(); r2.rotation.y = Math.PI / 2;
    const bowL = new THREE.Mesh(new THREE.TorusGeometry(0.6, 0.22, 8, 16), gold); bowL.position.set(-0.55, 3.4, 0); bowL.rotation.y = Math.PI / 2; const bowR = bowL.clone(); bowR.position.x = 0.55;
    [body, lid, r1, r2, bowL, bowR].forEach((m) => { m.castShadow = true; giftBox.add(m); });
    giftBox.position.set(World.giftBox.x, 0, World.giftBox.z); scene.add(giftBox);
  }
  const giftLabel = canvasBoard(6.5, 1.7, 384, 100); giftLabel.mesh.position.set(World.giftBox.x, 5.6, World.giftBox.z); giftLabel.mesh.rotation.y = Math.PI; scene.add(giftLabel.mesh);

  // ---------- player avatar: rounded blocks, a face, and the ice ray ----------
  const avatar = new THREE.Group(), avParts = {};
  {
    const fc = document.createElement('canvas'); fc.width = fc.height = 128; const f = fc.getContext('2d');
    f.fillStyle = '#ffd6a5'; f.fillRect(0, 0, 128, 128); f.fillStyle = '#1b1433';
    f.beginPath(); f.ellipse(44, 56, 8, 11, 0, 0, 7); f.fill(); f.beginPath(); f.ellipse(84, 56, 8, 11, 0, 0, 7); f.fill();
    f.fillStyle = '#fff'; f.beginPath(); f.arc(47, 52, 3, 0, 7); f.fill(); f.beginPath(); f.arc(87, 52, 3, 0, 7); f.fill();
    f.strokeStyle = '#1b1433'; f.lineWidth = 6; f.lineCap = 'round'; f.beginPath(); f.arc(64, 74, 18, 0.2, Math.PI - 0.2); f.stroke();
    const faceTex = new THREE.CanvasTexture(fc); faceTex.colorSpace = THREE.SRGBColorSpace;
    const skin = std('#ffd6a5'), hoodie = std('#3aa8ff', { roughness: 0.7 }), pants = std('#2d3561');
    const add = (name, geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; avatar.add(m); avParts[name] = m; return m; };
    add('torso', new RoundedBoxGeometry(2, 2, 1.1, 3, 0.25), hoodie, 0, 3, 0);
    const head = add('head', new RoundedBoxGeometry(1.45, 1.45, 1.45, 4, 0.35), skin, 0, 4.75, 0);
    const face = new THREE.Mesh(new THREE.PlaneGeometry(1.2, 1.2), new THREE.MeshStandardMaterial({ map: faceTex, roughness: 0.8 })); face.position.set(0, 0, 0.73); head.add(face);
    const hair = new THREE.Mesh(new RoundedBoxGeometry(1.55, 0.5, 1.55, 3, 0.2), std('#f08a22')); hair.position.y = 0.62; head.add(hair);
    const leg = new RoundedBoxGeometry(0.92, 2, 0.95, 3, 0.2); leg.translate(0, -1, 0);
    const arm = new RoundedBoxGeometry(0.82, 2, 0.85, 3, 0.2); arm.translate(0, -0.9, 0);
    add('legL', leg, pants, -0.5, 2, 0); add('legR', leg, pants, 0.5, 2, 0);
    add('armL', arm, hoodie, -1.45, 3.9, 0); const armR = add('armR', arm, hoodie, 1.45, 3.9, 0);
    const gun = new THREE.Group();
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.42, 1.6, 14), std('#e9f6ff', { roughness: 0.35, metalness: 0.2 })); barrel.rotation.x = Math.PI / 2;
    const tip = new THREE.Mesh(new THREE.SphereGeometry(0.38, 14, 10), std('#7fe3ff', { emissive: '#3ad0ff', emissiveIntensity: 1.2 })); tip.position.z = 0.85;
    const tank = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.7, 12), std('#7fe3ff', { emissive: '#2ab0e0', emissiveIntensity: 0.6, transparent: true, opacity: 0.85 })); tank.position.set(0, 0.42, -0.2);
    [barrel, tip, tank].forEach((m) => { m.castShadow = true; gun.add(m); });
    gun.position.set(0, -1.9, 0.5); armR.add(gun); avParts.gunTip = tip;
    scene.add(avatar);
  }
  const shadowTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d'); const g = x.createRadialGradient(32, 32, 2, 32, 32, 32); g.addColorStop(0, 'rgba(27,20,51,0.45)'); g.addColorStop(1, 'rgba(27,20,51,0)'); x.fillStyle = g; x.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c); })();
  const shadowG = new THREE.PlaneGeometry(2, 2), shadowM = new THREE.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false });
  const blob = (r) => { const s = new THREE.Mesh(shadowG, shadowM); s.rotation.x = -Math.PI / 2; s.scale.setScalar(r); s.position.y = 0.09; return s; };

  // ---------- pets: the real 3D model where it exists, otherwise the approved concept as a sprite ----------
  const texLoader = new THREE.TextureLoader();
  const spriteTex = {};
  for (const p of PetDefs) { const t = texLoader.load(`assets/sprites/${p.key}.webp`); t.colorSpace = THREE.SRGBColorSpace; spriteTex[p.key] = t; }
  const models = {};
  const gltf = new GLTFLoader();
  const modelPromises = PetDefs.filter((p) => p.model).map((p) => new Promise((res) => gltf.load(p.model, (g) => { g.scene.traverse((o) => { if (o.isMesh) { o.castShadow = true; } }); models[p.key] = g.scene; res(); }, undefined, () => res())));
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
      const sm = new THREE.SpriteMaterial({ map: spriteTex[key], transparent: true, alphaTest: 0.3, color: opts.tint || 0xffffff, toneMapped: false });
      const s = new THREE.Sprite(sm); s.center.set(0.5, 0.02); s.scale.set(h * 1.2, h * 1.2, 1); body.add(s); root.userData.sprite = s;
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
      case 'idle': y = frozen ? 0 : Math.abs(Math.sin(t * 3)) * 0.05 * h; sy = frozen ? 1 : 1 + Math.sin(t * 6) * 0.02; break;
      case 'yawn': sy = 1 + 0.16 * (frozen ? 1 : Math.min(1, t)); sx = 1 - 0.06; rot = -0.08; break;
      case 'jump': { const u = frozen ? 0.5 : Math.min(1, t / 0.9); y = Math.sin(u * Math.PI) * 0.5 * h; sy = u < 0.15 ? 0.85 : 1.1; sx = u < 0.15 ? 1.12 : 0.94; break; }
      case 'dance': rot = (frozen ? 1 : Math.sin(t * 10)) * 0.28; y = (frozen ? 0.05 : k * 0.12) * h; break;
      case 'sneeze': sy = 0.82; sx = 1.16; rot = 0.14; break;
      case 'dazed': rot = Math.sin(t * 3) * 0.15; break;
    }
    b.position.y = y; b.scale.set(sx, sy, sx);
    if (s) s.material.rotation = rot; else b.rotation.z = rot;
  }

  // ---------- ice cubes: rounded glassy ice with the pet inside ----------
  const cubeGeo = new RoundedBoxGeometry(1, 1, 1, 4, 0.12);
  const frameGeo = new THREE.EdgesGeometry(new THREE.BoxGeometry(0.97, 0.97, 0.97));
  function makeCube(cube) {
    const def = petByKey[cube.key];
    const g = new THREE.Group();
    const size = CubeSize[def.size] * (1 + Config.upgrades.ray.cubeSizeBonus * (view().upgrades.ray - 1));
    const pet = makePetVisual(cube.key, { tint: cube.mut === 'Frosty' ? '#d4f1ff' : null });
    pet.scale.setScalar((size * 0.8) / (pet.userData.h * 1.2)); pet.position.y = -size * 0.42; g.add(pet);
    applyPose(pet, cube.pose, 0, true);
    const iceMat = new THREE.MeshPhysicalMaterial({ color: cube.superFrozen ? '#5f8dff' : '#cdefff', roughness: 0.06, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.05,
      transparent: true, opacity: cube.superFrozen ? 0.55 : 0.4, depthWrite: false, emissive: cube.superFrozen ? '#1a3fb0' : '#4aa8d8', emissiveIntensity: 0.35, envMapIntensity: 2 });
    const ice = new THREE.Mesh(cubeGeo, iceMat); ice.renderOrder = 2; g.add(ice);
    const edges = new THREE.LineSegments(frameGeo, new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55 })); g.add(edges);
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
    function fp(f, a, b) { return f === 0 ? [a, b, 0.51] : f === 1 ? [0.51, a, b] : [a, 0.51, b]; }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3)); return g;
  }

  // ---------- particles (bursts only; phone-safe counts) ----------
  const particles = [];
  const partGeo = new THREE.OctahedronGeometry(0.22, 0);
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
      p.life -= dt; p.v.y -= 18 * dt; p.m.position.addScaledVector(p.v, dt); p.m.rotation.x += dt * 5; p.m.rotation.y += dt * 4;
      p.m.material.opacity = Math.max(0, p.life / p.max);
      if (p.life <= 0) { scene.remove(p.m); p.m.material.dispose(); particles.splice(particles.indexOf(p), 1); }
    }
  }
  // snow during the Big Chill
  const snow = new THREE.Points(new THREE.BufferGeometry(), new THREE.PointsMaterial({ color: 0xffffff, size: 0.7, transparent: true, opacity: 0.95 }));
  { const n = 1200, a = new Float32Array(n * 3); for (let i = 0; i < n; i++) { a[i * 3] = (Math.random() - 0.5) * 140; a[i * 3 + 1] = Math.random() * 40; a[i * 3 + 2] = (Math.random() - 0.5) * 140; } snow.geometry.setAttribute('position', new THREE.BufferAttribute(a, 3)); }
  snow.visible = false; scene.add(snow);

  // ray beam (bright core + soft glow)
  const beam = new THREE.Group();
  const beamCore = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.14, 1, 8, 1, true), flat('#ffffff', { transparent: true, opacity: 0.95 }));
  const beamGlow = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 1, 12, 1, true), flat('#7fe3ff', { transparent: true, opacity: 0.45, depthWrite: false }));
  beam.add(beamCore, beamGlow); beam.visible = false; scene.add(beam);
  // green guide arrow: a chunky chevron with an ink outline, bobbing on the ground
  const arrowG = new THREE.Group();
  {
    const s = new THREE.Shape(); s.moveTo(0, 1.6); s.lineTo(1.4, -0.2); s.lineTo(0.55, -0.2); s.lineTo(0.55, -1.4); s.lineTo(-0.55, -1.4); s.lineTo(-0.55, -0.2); s.lineTo(-1.4, -0.2); s.closePath();
    const geo = new THREE.ExtrudeGeometry(s, { depth: 0.35, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.08, bevelSegments: 2 });
    const m = new THREE.Mesh(geo, std('#3ccf6e', { emissive: '#1f8a45', emissiveIntensity: 0.4, roughness: 0.4 }));
    const outline = new THREE.Mesh(geo, flat('#1b1433', { side: THREE.BackSide })); outline.scale.setScalar(1.12);
    const a = new THREE.Group(); a.add(outline, m); a.rotation.x = -Math.PI / 2; arrowG.add(a); scene.add(arrowG);
  }

  // rarity ring texture (soft glowing ring)
  const ringTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d'); const g = x.createRadialGradient(64, 64, 30, 64, 64, 62); g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.55, 'rgba(255,255,255,1)'); g.addColorStop(0.7, 'rgba(255,255,255,0.6)'); g.addColorStop(1, 'rgba(255,255,255,0)'); x.fillStyle = g; x.fillRect(0, 0, 128, 128); return new THREE.CanvasTexture(c); })();

  // ---------- entity sync from replicated state ----------
  const wildVis = new Map();
  const carriedVis = new Map();
  const penVis = [];
  const RARE = ['Rare', 'Epic', 'Legendary', 'Mythic', 'Secret'];
  function syncWild(v, t) {
    for (const [id, w] of v.wild) {
      let e = wildVis.get(id);
      if (!e) {
        const def = petByKey[w.key];
        const root = makePetVisual(w.key, { tint: w.mut === 'Frosty' ? '#d4f1ff' : null });
        const ring = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: ringTex, color: Theme.tiers[def.tier], transparent: true, depthWrite: false, toneMapped: false }));
        ring.rotation.x = -Math.PI / 2; ring.position.y = 0.12; ring.scale.setScalar(root.userData.h * 1.5);
        const sh = blob(root.userData.h * 0.45);
        const stars = new THREE.Group();
        for (let i = 0; i < 3; i++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.28), std('#ffffff', { emissive: '#bff1ff', emissiveIntensity: 0.8 })); s.position.set(Math.cos(i * 2.1) * 0.9, 0, Math.sin(i * 2.1) * 0.9); stars.add(s); }
        stars.position.y = root.userData.h * 1.3; stars.visible = false;
        const g = new THREE.Group(); g.add(root, ring, sh, stars); scene.add(g);
        e = { g, root, ring, stars, born: t, actionStart: t, action: null, rare: RARE.includes(def.tier), tier: def.tier };
        wildVis.set(id, e);
      }
      e.g.position.set(w.x, 0, w.z);
      if (e.root.userData.model) e.root.rotation.y = Math.atan2(me.x - w.x, me.z - w.z) * 0.4; // models turn a little toward you
      if (w.action !== e.action) { e.action = w.action; e.actionStart = t; if (w.action === 'sneeze') burst(w.x, e.root.userData.h * 0.8, w.z, '#ffffff', 6, 3, 0.4); }
      const dazed = w.state === 'dazed';
      applyPose(e.root, dazed ? 'dazed' : w.action, t - e.actionStart, false);
      e.stars.visible = dazed; e.stars.rotation.y = t * 3;
      e.ring.material.opacity = 0.6 + Math.sin(t * 4) * 0.25; e.ring.rotation.z = t * 0.5;
      if (e.rare && Math.random() < 0.03) burst(w.x + (Math.random() - 0.5) * 2, e.root.userData.h * Math.random(), w.z, Theme.tiers[e.tier], 1, 1.5, 0.6);
      const appear = Math.min(1, (t - e.born) / 0.25); e.g.scale.setScalar(appear < 1 ? appear * 1.08 : 1);
    }
    for (const [id, e] of wildVis) if (!v.wild.has(id)) { scene.remove(e.g); wildVis.delete(id); }
  }
  function syncCarried(v, t) {
    const ids = new Set(v.carrying.map((c) => c.uid));
    for (const [uid, g] of carriedVis) if (!ids.has(uid)) { scene.remove(g); carriedVis.delete(uid); }
    let y = 2.2;
    v.carrying.forEach((c) => {
      let g = carriedVis.get(c.uid);
      if (!g) { g = makeCube(c); scene.add(g); carriedVis.set(c.uid, g); g.userData.born = t; }
      const frac = c.superFrozen ? 1 : Math.max(0, c.life / c.lifeMax);
      const back = 0.62; // carried cubes are smaller so they never hide the player's head
      const s = (0.55 + 0.45 * frac) * back * Math.min(1, (t - g.userData.born) / 0.2 + 0.3);
      const size = g.userData.size * s;
      const behind = -1.4 - size / 2;
      const fx = Math.sin(me.facing), fz = Math.cos(me.facing);
      g.position.set(me.x + fx * behind, y + size / 2 + Math.sin(me.walkPhase * 2) * 0.06, me.z + fz * behind);
      y += size + 0.12;
      g.scale.setScalar(s); g.rotation.y = me.facing;
      g.userData.cracks.visible = frac < 0.35;
      const flash = frac < 0.15 && Math.sin(t * 14) > 0;
      g.userData.iceMat.emissive.set(c.superFrozen ? '#1a3fb0' : flash ? '#8fdcff' : '#4aa8d8');
      g.userData.iceMat.emissiveIntensity = flash ? 0.9 : 0.35;
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
      const g = new THREE.Group(); g.add(root, blob(root.userData.h * 0.42)); g.position.set(x, 0.4, z); scene.add(g);
      penVis.push({ g, root, pose: p.pose, phase: Math.random() * 6, born: t });
    }
    for (const e of penVis) {
      const age = t - e.born;
      applyPose(e.root, age < 1.2 ? 'dance' : e.pose, age < 1.2 ? age : (t + e.phase) % 2.5, age >= 1.2);
      if (age >= 1.2) e.root.userData.body.position.y += Math.abs(Math.sin(t * 2 + e.phase)) * 0.15;
    }
  }

  function drawBoard(cb, def, data) {
    cb.draw((ctx, w, h) => {
      roundRect(ctx, 6, 6, w - 12, h - 12, 26); ctx.fillStyle = '#2b1f5c'; ctx.fill(); ctx.lineWidth = 10; ctx.strokeStyle = Theme.ink; ctx.stroke();
      if (iconImg.trophy.complete) ctx.drawImage(iconImg.trophy, 22, 18, 64, 64);
      ctx.textAlign = 'center'; ctx.font = '700 36px Fredoka, sans-serif'; ctx.fillStyle = '#ffd34a'; ctx.fillText(def.title, w / 2 + 24, 58);
      ctx.font = '600 22px Fredoka, sans-serif'; ctx.fillStyle = '#bfb6ff';
      ctx.fillText(def.kind === 'weekly' ? Config.leaderboards.weeklyResetLabel : 'All time', w / 2 + 24, 90);
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
      // friendly: an exact rank only inside the top 100 (Game Psychology 10: no shaming low scores)
      const rankText = data.me.rank <= 100 ? `You: #${data.me.rank}` : 'You: not in the top 100 yet';
      ctx.fillStyle = '#fff'; ctx.textAlign = 'left'; ctx.font = '700 26px Fredoka, sans-serif'; ctx.fillText(rankText, 34, y + 23);
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
      const tc = zoneTemperature(zs.zone.id), unit = Config.temperature.unit, deg = unit === 'F' ? Math.round((tc * 9) / 5 + 32) : tc;
      ctx.font = '600 22px Fredoka, sans-serif'; ctx.fillStyle = '#5a4f8a'; ctx.fillText(`${deg}°${unit} here  ·  shade is colder, sun is hotter`, w / 2, 88);
      Config.tiers.forEach((t, i) => {
        const y = 128 + i * 40;
        ctx.fillStyle = Theme.tiers[t.name]; ctx.beginPath(); ctx.arc(60, y - 8, 12, 0, Math.PI * 2); ctx.fill(); ctx.lineWidth = 4; ctx.stroke();
        ctx.textAlign = 'left'; ctx.fillStyle = Theme.ink; ctx.font = '600 26px Fredoka, sans-serif'; ctx.fillText(t.name, 86, y);
        const o = odds[t.name]; ctx.textAlign = 'right'; ctx.fillText(o >= 1 ? `${o.toFixed(1)}%` : o >= 0.01 ? `${o.toFixed(2)}%` : `1 in ${Math.round(100 / o).toLocaleString()}`, w - 40, y);
      });
    });
  }
  let lastBoards = null, signAt = -99, lastGate = null, lastGift = null, lastUnit = Config.temperature.unit;

  // ---------- server events -> effects ----------
  server.on('frozen', ({ petId, superFrozen }) => {
    const e = wildVis.get(petId); const x = e ? e.g.position.x : me.x, z = e ? e.g.position.z : me.z;
    burst(x, 2, z, superFrozen ? '#2f6bff' : '#ffffff', 22, 9); burst(x, 2, z, '#9fe8ff', 10, 6);
    audio.play('freeze');
  });
  server.on('banked', ({ banked }) => {
    banked.forEach((b, i) => setTimeout(() => {
      const p = World.pen; burst((p.xMin + p.xMax) / 2, 3, (p.zMin + p.zMax) / 2, '#bfe9ff', 22, 10, 0.8); burst((p.xMin + p.xMax) / 2, 3, (p.zMin + p.zMax) / 2, '#ffd34a', 12, 8, 0.9);
      const tier = petByKey[b.cube.key].tier;
      audio.play(RARE.includes(tier) ? 'reveal_rare' : 'bank');
      hud.floatAt(`+${fmt(b.income)}/s`, worldToScreen(me.x, 6, me.z), '#ffd34a');
    }, i * 250));
  });
  server.on('melted', () => { audio.play('melt'); burst(me.x, 3, me.z, '#bfe9ff', 16, 6); });
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
    const sw = moving ? Math.sin(me.walkPhase) * 0.7 : 0;
    avParts.legL.rotation.x = sw; avParts.legR.rotation.x = -sw; avParts.armL.rotation.x = -sw;
    avParts.armR.rotation.x = hold.target ? -1.45 : sw;
    avParts.torso.position.y = 3 + (moving ? Math.abs(Math.sin(me.walkPhase)) * 0.12 : Math.sin(t * 2) * 0.03);
    avParts.gunTip.material.emissiveIntensity = hold.target ? 2.5 + Math.sin(t * 30) : 1.2;
    // camera: behind and above, looking south toward the next zone
    const want = new THREE.Vector3(me.x, Config.camera.height, me.z - Config.camera.back);
    camPos.lerp(want, 1 - Math.pow(0.001, dt));
    camera.position.copy(camPos); camera.lookAt(me.x, 1, me.z + Config.camera.lookAhead);
    sunLight.position.set(me.x + SUN_OFFSET.x, SUN_OFFSET.y, me.z + 18 + SUN_OFFSET.z); sunLight.target.position.set(me.x, 0, me.z + 18);
    syncWild(v, t); syncCarried(v, t); syncPen(v, t); tickParticles(dt);
    // ray beam while zapping
    if (hold.target && hold.target.kind !== 'gift') {
      const tp = hold.target.kind === 'bridge' ? iceBridgeCenter() : (v.wild.get(hold.target.id) || {});
      if (tp.x !== undefined) {
        const a = new THREE.Vector3(); avParts.gunTip.getWorldPosition(a); const b = new THREE.Vector3(tp.x, 1.4, tp.z);
        beam.visible = true; beam.position.copy(a).add(b).multiplyScalar(0.5); beam.scale.set(1, a.distanceTo(b), 1);
        beam.lookAt(b); beam.rotateX(Math.PI / 2); beamGlow.material.opacity = 0.3 + Math.random() * 0.3; beamGlow.scale.x = beamGlow.scale.z = 0.8 + Math.random() * 0.5;
        if (Math.random() < 0.4) burst(tp.x, 1.5, tp.z, '#dff6ff', 1, 3, 0.4);
      } else beam.visible = false;
    } else beam.visible = false;
    // guide arrow: to a pet when empty-handed in the first minutes, home when carrying
    let goal = null;
    if (v.carrying.length) goal = { x: 0, z: (World.pen.zMin + World.pen.zMax) / 2 };
    else if (v.pets.length < 3) { let bd = 1e9; for (const w of v.wild.values()) { const d = dist(w, me); if (d < bd && w.zone === 1) { bd = d; goal = w; } } }
    arrowG.visible = !!goal && !(goal && dist(goal, me) < 6);
    if (goal) { const ang = Math.atan2(goal.x - me.x, goal.z - me.z); arrowG.position.set(me.x + Math.sin(ang) * 4.5, 0.5 + Math.abs(Math.sin(t * 4)) * 0.35, me.z + Math.cos(ang) * 4.5); arrowG.rotation.y = ang; }
    // world state
    W.update(dt, t); W.clearView({ x: camera.position.x, z: camera.position.z }, me);
    W.iceBridge.visible = v.iceBridgeActive; if (v.iceBridgeActive) W.iceSpot.material.opacity = 0.25;
    if (v.iceBridgeActive) { const left = v.iceBridgeUntil - v.time; W.iceBridge.material.opacity = left < 4 && Math.sin(t * 12) > 0 ? 0.35 : 0.8; }
    W.gateBars.position.y += ((v.forestUnlocked ? -9 : 0) - W.gateBars.position.y) * Math.min(1, dt * 3);
    snow.visible = v.chill.active; if (snow.visible) { snow.position.set(me.x, 0, me.z); const a = snow.geometry.attributes.position; for (let i = 0; i < a.count; i++) { let y = a.getY(i) - dt * 8; if (y < 0) y += 40; a.setY(i, y); } a.needsUpdate = true; }
    scene.fog.color.set(v.chill.active ? 0xf4fbff : 0xe4f3ff);
    giftBox.rotation.y = v.gift.ready ? Math.sin(t * 2) * 0.15 : 0; giftBox.position.y = v.gift.ready ? Math.abs(Math.sin(t * 3)) * 0.6 : 0;
    // boards and signs (redrawn only when their data changes)
    if (v.boards && v.boards !== lastBoards) { lastBoards = v.boards; Config.leaderboards.boards.forEach((b, i) => drawBoard(boards[i], b, v.boards[b.id])); }
    if (t - signAt > 3 || lastUnit !== Config.temperature.unit) { signAt = t; lastUnit = Config.temperature.unit; zoneSigns.forEach(drawZoneSign); }
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
