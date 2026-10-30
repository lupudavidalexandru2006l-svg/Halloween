// CLIENT: the static world (World Rules: bright, deep, easy to read). Built once; returns handles the
// client animates. Shade/sun areas come from the shared Scenery list, so what you see is what melts.
// In Roblox this is the map built in Studio (WorldService's blockout is the stand-in).
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Config, World, Scenery, Theme, mulberry32 } from './config.js';

const C = (hex) => new THREE.Color(hex);
const std = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0, ...o });

// smooth value noise (cheap, deterministic)
function hash(x, z) { const s = Math.sin(x * 127.1 + z * 311.7) * 43758.5453; return s - Math.floor(s); }
function vnoise(x, z) {
  const xi = Math.floor(x), zi = Math.floor(z), xf = x - xi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = zf * zf * (3 - 2 * zf);
  const a = hash(xi, zi), b = hash(xi + 1, zi), c = hash(xi, zi + 1), d = hash(xi + 1, zi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
const fbm = (x, z) => vnoise(x, z) * 0.6 + vnoise(x * 2.1, z * 2.1) * 0.3 + vnoise(x * 4.3, z * 4.3) * 0.1;

// vertex-coloured part for merged props
function part(geo, color, m) { const g0 = geo.clone(), g = g0.index ? g0.toNonIndexed() : g0; if (m) g.applyMatrix4(m); const c = C(color); const n = g.attributes.position.count; const a = new Float32Array(n * 3); for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; } g.setAttribute('color', new THREE.BufferAttribute(a, 3)); g.deleteAttribute('uv'); return g; }
const M = (x, y, z, sx = 1, sy = 1, sz = 1, ry = 0) => new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(sx, sy, sz));

function instanced(scene, geo, list, { mat, cast = true, receive = false } = {}) {
  const mesh = new THREE.InstancedMesh(geo, mat || std(0xffffff, { vertexColors: true }), list.length);
  list.forEach((t, i) => mesh.setMatrixAt(i, M(t.x, t.y || 0, t.z, t.s, t.sy ?? t.s, t.s, t.ry || 0)));
  mesh.castShadow = cast; mesh.receiveShadow = receive; mesh.instanceMatrix.needsUpdate = true;
  mesh.userData.list = list; mesh.userData.hidden = new Set();
  scene.add(mesh); return mesh;
}
// World Rules 3: foreground never covers the player. Instances standing between the camera and the
// player sink into the ground while they're in the way, then grow back.
function clearCorridor(mesh, cam, me) {
  const { list, hidden } = mesh.userData; let dirty = false;
  const zA = Math.min(cam.z, me.z) - 2, zB = Math.max(cam.z, me.z) - 3;
  for (let i = 0; i < list.length; i++) {
    const t = list[i];
    const inWay = t.z > zA && t.z < zB && Math.abs(t.x - (cam.x + ((me.x - cam.x) * (t.z - cam.z)) / ((me.z - cam.z) || 1))) < 3 + (t.s || 1) * 2;
    if (inWay !== hidden.has(i)) {
      if (inWay) hidden.add(i); else hidden.delete(i);
      mesh.setMatrixAt(i, inWay ? M(t.x, -50, t.z, 0.001) : M(t.x, t.y || 0, t.z, t.s, t.sy ?? t.s, t.s, t.ry || 0)); dirty = true;
    }
  }
  if (dirty) mesh.instanceMatrix.needsUpdate = true;
}

// a blocker {obj, x, z, r} fades to see-through while it stands between the camera and the player
function fadeBlocker(b, cam, me, dt) {
  const zA = Math.min(cam.z, me.z) - b.r, zB = Math.max(cam.z, me.z) + 1;
  const lineX = cam.x + ((me.x - cam.x) * (b.z - cam.z)) / ((me.z - cam.z) || 1);
  const inWay = b.z > zA && b.z < zB && Math.abs(b.x - lineX) < b.r + 2.5;
  const want = inWay ? 0.18 : 1;
  b.fade = b.fade ?? 1; if (Math.abs(b.fade - want) < 0.01) return;
  b.fade += (want - b.fade) * Math.min(1, dt * 8);
  if (!b.mats) { b.mats = []; b.obj.traverse((o) => { if (o.material) { o.material = o.material.clone(); o.material.userData.baseOpacity = o.material.opacity; b.mats.push(o.material); } }); }
  for (const m of b.mats) { m.transparent = true; m.opacity = m.userData.baseOpacity * b.fade; m.depthWrite = b.fade > 0.95; }
}

function radialTexture(inner, outer) {
  const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d');
  const g = x.createRadialGradient(64, 64, 4, 64, 64, 64); g.addColorStop(0, inner); g.addColorStop(1, outer);
  x.fillStyle = g; x.fillRect(0, 0, 128, 128); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

export function buildWorld(scene) {
  const R = World.river, B = World.bounds, rng = mulberry32(77);
  const handles = { clouds: [], puffs: [], sunPatches: [], lanterns: [], blockers: [], update: null };

  // ---------- sky ----------
  {
    const g = new THREE.SphereGeometry(900, 32, 16), top = C('#4fa8ff'), mid = C('#a6d8ff'), bottom = C('#eaf7ff');
    const cols = [], pos = g.attributes.position;
    for (let i = 0; i < pos.count; i++) { const t = Math.max(0, pos.getY(i) / 900); const c = t < 0.25 ? bottom.clone().lerp(mid, t / 0.25) : mid.clone().lerp(top, Math.min(1, (t - 0.25) / 0.5)); cols.push(c.r, c.g, c.b); }
    g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
    scene.add(new THREE.Mesh(g, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false })));
    const sun = new THREE.Mesh(new THREE.CircleGeometry(36, 32), new THREE.MeshBasicMaterial({ map: radialTexture('rgba(255,250,220,1)', 'rgba(255,240,180,0)'), transparent: true, fog: false, depthWrite: false }));
    sun.position.set(-300, 320, 560); sun.lookAt(0, 0, 0); sun.scale.setScalar(2.2); scene.add(sun);
  }

  // ---------- terrain: snow meadow, river bed, grassy forest, natural hill edges ----------
  {
    const W = 460, D = 560, cx = 0, cz = 150, sx = 150, sz = 190;
    const g = new THREE.PlaneGeometry(W, D, sx, sz); g.rotateX(-Math.PI / 2);
    const pos = g.attributes.position, cols = new Float32Array(pos.count * 3);
    const snowA = C('#f7fbff'), snowB = C('#cfdff3'), pathSnow = C('#d3e0ef'), grassA = C('#86c35c'), grassB = C('#5f9f45'), dirt = C('#c7a273'), bank = C('#e9f2ff'), rock = C('#a9b6c9'), forestHill = C('#4d8a4a');
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i) + cx, z = pos.getZ(i) + cz;
      pos.setX(i, x); pos.setZ(i, z);
      const n = fbm(x * 0.05, z * 0.05);
      let h = (n - 0.5) * 0.25;
      const edgeX = Math.max(0, Math.abs(x) - (B.xMax + 4)), edgeN = Math.max(0, B.zMin + 4 - z), edgeS = Math.max(0, z - (B.zMax - 4));
      const edge = Math.max(edgeX, edgeN, edgeS);
      if (edge > 0) h += Math.min(34, Math.pow(edge / 14, 1.6) * 6) + n * edge * 0.25;
      const inRiver = z > R.zMin && z < R.zMax;
      if (inRiver) { const d = Math.min(z - R.zMin, R.zMax - z); h = -Math.min(3, d * 0.8) - 0.4; }
      if (Math.abs(x) < 10 && !inRiver && edge === 0) h *= 0.2;
      pos.setY(i, h);
      // colour
      let c;
      const forest = z > R.zMax;
      const pathW = Math.abs(x) - 8.5;
      if (inRiver) c = C('#7c9fbf');
      else if (forest) {
        c = grassA.clone().lerp(grassB, fbm(x * 0.08 + 9, z * 0.08));
        if (pathW < 0 && z > R.zMax + 1) c = dirt.clone().lerp(C('#b48f5c'), n);
        else if (pathW < 2 && z > R.zMax + 1) c.lerp(dirt, 1 - pathW / 2);
        if (edge > 0) c.lerp(forestHill, Math.min(1, edge / 20));
      } else {
        c = snowA.clone().lerp(snowB, Math.pow(fbm(x * 0.06, z * 0.06), 1.3));
        c.lerp(C('#bcd3ee'), Math.max(0, fbm(x * 0.21 + 3, z * 0.04) - 0.62) * 1.6); // wind ripples in the snow
        if (pathW < 2 && z > -2) c.lerp(pathSnow, Math.min(1, 1 - pathW / 2));
        if (z > R.zMin - 3) c.lerp(bank, 0.6);
        if (edge > 0) c.lerp(edge > 22 ? snowA : rock, Math.min(0.35, edge / 40));
      }
      cols[i * 3] = c.r; cols[i * 3 + 1] = c.g; cols[i * 3 + 2] = c.b;
    }
    g.setAttribute('color', new THREE.BufferAttribute(cols, 3)); g.computeVertexNormals();
    const ground = new THREE.Mesh(g, std(0xffffff, { vertexColors: true, roughness: 1 }));
    ground.receiveShadow = true; scene.add(ground);
  }

  // ---------- river water (shimmering) ----------
  {
    const c = document.createElement('canvas'); c.width = c.height = 256; const x = c.getContext('2d');
    x.fillStyle = '#3d9ce0'; x.fillRect(0, 0, 256, 256); x.strokeStyle = 'rgba(255,255,255,0.35)'; x.lineWidth = 3;
    for (let i = 0; i < 26; i++) { const yy = (i * 41) % 256, xx = (i * 97) % 256; x.beginPath(); x.moveTo(xx, yy); x.quadraticCurveTo(xx + 14, yy - 5, xx + 30, yy); x.stroke(); }
    const tex = new THREE.CanvasTexture(c); tex.wrapS = tex.wrapT = THREE.RepeatWrapping; tex.repeat.set(30, 1.2); tex.colorSpace = THREE.SRGBColorSpace;
    const water = new THREE.Mesh(new THREE.PlaneGeometry(460, R.zMax - R.zMin + 2), std(0xffffff, { map: tex, roughness: 0.25, metalness: 0.1, transparent: true, opacity: 0.92 }));
    water.rotation.x = -Math.PI / 2; water.position.set(0, -0.7, (R.zMin + R.zMax) / 2); water.receiveShadow = true; scene.add(water);
    handles.water = tex;
    const stones = [];
    for (let i = 0; i < 90; i++) { const side = i % 2 ? R.zMin - 0.5 : R.zMax + 0.5; stones.push({ x: -150 + rng() * 300, z: side + (rng() - 0.5) * 1.5, y: -0.1, s: 0.6 + rng() * 0.9, sy: 0.5, ry: rng() * 6 }); }
    instanced(scene, part(new THREE.DodecahedronGeometry(1, 0), '#9aa9bd'), stones, { receive: true });
  }

  // ---------- main bridge (planks + rails) and the ice bridge ----------
  {
    const b = World.mainBridge, cx = (b.xMin + b.xMax) / 2, len = R.zMax - R.zMin + 6, z0 = R.zMin - 3;
    const planks = [];
    for (let i = 0; i < len / 1.1; i++) planks.push({ x: cx, z: z0 + i * 1.1 + 0.5, y: 0.15, s: 1, ry: (rng() - 0.5) * 0.03 });
    instanced(scene, part(new RoundedBoxGeometry(b.xMax - b.xMin + 1, 0.45, 0.95, 2, 0.12), '#b07a4a'), planks, { receive: true });
    const posts = [];
    for (let i = 0; i <= 4; i++) for (const x of [b.xMin, b.xMax]) posts.push({ x, z: z0 + (i * len) / 4, y: 0, s: 1 });
    instanced(scene, part(new THREE.CylinderGeometry(0.35, 0.4, 3, 8), '#8a5a36', M(0, 1.5, 0)), posts);
    for (const x of [b.xMin, b.xMax]) { const r = new THREE.Mesh(new RoundedBoxGeometry(0.4, 0.4, len, 2, 0.15), std('#9a6b43')); r.position.set(x, 2.4, z0 + len / 2); r.castShadow = true; scene.add(r); }
  }
  {
    const i = World.iceBridgeSpot, len = R.zMax - R.zMin + 6;
    const ice = new THREE.Mesh(new RoundedBoxGeometry(i.xMax - i.xMin, 0.8, len, 3, 0.3), new THREE.MeshPhysicalMaterial({ color: '#bfe9ff', roughness: 0.1, transmission: 0, transparent: true, opacity: 0.8, clearcoat: 1, emissive: '#2a6f9a', emissiveIntensity: 0.35 }));
    ice.position.set((i.xMin + i.xMax) / 2, 0.1, (R.zMin + R.zMax) / 2); ice.visible = false; ice.receiveShadow = true; scene.add(ice);
    // a glowing freeze spot on each bank, so the bridge can be made going out and coming home
    const spotMat = new THREE.MeshBasicMaterial({ map: radialTexture('rgba(150,240,255,1)', 'rgba(150,240,255,0)'), transparent: true, depthWrite: false });
    const crysMat = std('#9fe8ff', { emissive: '#3ab0e0', emissiveIntensity: 0.5, roughness: 0.2 }), crysGeo = new THREE.OctahedronGeometry(0.6, 0);
    let spot = null;
    for (const sz of [R.zMin - 2, R.zMax + 2]) {
      const sp = new THREE.Mesh(new THREE.CircleGeometry(3.4, 40), spotMat);
      sp.rotation.x = -Math.PI / 2; sp.position.set((i.xMin + i.xMax) / 2, 0.08, sz); scene.add(sp); spot ||= sp;
      const crystals = new THREE.Group();
      for (let k = 0; k < 5; k++) { const cr = new THREE.Mesh(crysGeo, crysMat); cr.scale.y = 2.2; const a = (k / 5) * Math.PI * 2; cr.position.set(Math.cos(a) * 3.6, 0.9, Math.sin(a) * 3.6); crystals.add(cr); }
      crystals.position.copy(sp.position); scene.add(crystals);
    }
    handles.iceBridge = ice; handles.iceSpot = spot; // both spots share one material
  }

  // ---------- the Forest gate: fence, wooden arch with ice crystals, ice bars ----------
  {
    const g = World.gate;
    const posts = [], rails = [];
    for (let x = B.xMin; x <= B.xMax; x += 4) { if (x > g.xMin - 1 && x < g.xMax + 1) continue; posts.push({ x, z: g.z, s: 1 }); }
    instanced(scene, part(new THREE.CylinderGeometry(0.4, 0.45, 3.2, 8), '#8a5a36', M(0, 1.6, 0)), posts);
    for (const [a, b] of [[B.xMin, g.xMin - 1], [g.xMax + 1, B.xMax]]) for (const y of [1.2, 2.4]) { const r = new THREE.Mesh(new RoundedBoxGeometry(b - a, 0.35, 0.3, 2, 0.1), std('#9a6b43')); r.position.set((a + b) / 2, y, g.z); r.castShadow = true; scene.add(r); }
    for (const x of [g.xMin, g.xMax]) { const p = new THREE.Mesh(new THREE.CylinderGeometry(1, 1.15, 10, 12), std('#8a5a36')); p.position.set(x, 5, g.z); p.castShadow = true; scene.add(p); }
    const arch = new THREE.Mesh(new THREE.TorusGeometry((g.xMax - g.xMin) / 2, 0.9, 10, 32, Math.PI), std('#9a6b43')); arch.position.set(0, 10, g.z); arch.castShadow = true; scene.add(arch);
    for (let k = 0; k < 7; k++) { const cr = new THREE.Mesh(new THREE.OctahedronGeometry(0.9, 0), std('#bff1ff', { emissive: '#48b8e8', emissiveIntensity: 0.45, roughness: 0.15 })); cr.scale.y = 1.8; const a = Math.PI * (k / 6); cr.position.set(Math.cos(a) * 10.5, 10 + Math.sin(a) * 10.5, g.z); cr.rotation.z = a - Math.PI / 2; scene.add(cr); }
    const bars = new THREE.Group();
    for (let x = g.xMin + 2; x < g.xMax; x += 2.5) { const bar = new THREE.Mesh(new RoundedBoxGeometry(0.8, 8, 0.8, 2, 0.3), std('#9fe3ff', { emissive: '#2a7fb0', emissiveIntensity: 0.5, transparent: true, opacity: 0.88, roughness: 0.2 })); bar.position.set(x, 4, g.z); bars.add(bar); }
    scene.add(bars); handles.gateBars = bars;
  }

  // ---------- Sunny Beach gate (closed in the prototype): a fence with sandy posts ----------
  {
    const z = World.beachGate.z + 1, posts = [];
    for (let x = B.xMin; x <= B.xMax; x += 3.5) posts.push({ x, z, s: 1 });
    instanced(scene, part(new THREE.CylinderGeometry(0.4, 0.45, 3.2, 8), '#d9b26a', M(0, 1.6, 0)), posts);
    for (const y of [1.2, 2.4]) { const r = new THREE.Mesh(new RoundedBoxGeometry(B.xMax - B.xMin, 0.35, 0.3, 2, 0.1), std('#e8c27a')); r.position.set(0, y, z); r.castShadow = true; scene.add(r); }
  }

  // ---------- trees (instanced, shade under each), decorative hill trees for depth ----------
  {
    const cone = (r, h, y, color) => part(new THREE.ConeGeometry(r, h, 12, 1), color, M(0, y, 0));
    const trunk = part(new THREE.CylinderGeometry(0.35, 0.5, 2.4, 8), '#7a5233', M(0, 1.2, 0));
    const snowPine = mergeGeometries([trunk, cone(2.1, 2.6, 2.6, '#2f6b4f'), cone(1.75, 2.3, 3.9, '#357a57'), cone(1.35, 2.0, 5.1, '#3d8560'), cone(0.9, 1.8, 6.2, '#45906a'),
      cone(1.3, 0.9, 3.2, '#f6fbff'), cone(1.0, 0.8, 4.4, '#f6fbff'), cone(0.7, 0.7, 5.5, '#f6fbff'), cone(0.45, 0.8, 6.8, '#ffffff')]);
    const pine = mergeGeometries([trunk, cone(2.2, 2.7, 2.6, '#2e6a3a'), cone(1.8, 2.4, 3.9, '#357a42'), cone(1.4, 2.1, 5.1, '#3d8a47'), cone(0.95, 1.9, 6.2, '#46964f')]);
    const sn = [], pn = [];
    for (const t of Scenery.trees) (t.kind === 'snowpine' ? sn : pn).push({ x: t.x, z: t.z, s: t.r / 2.4, ry: hash(t.x, t.z) * 6 });
    for (let i = 0; i < 160; i++) { // hills beyond the play area (scenery only)
      const side = i % 2 ? 1 : -1, x = side * (B.xMax + 10 + rng() * 60), z = -60 + rng() * 440;
      if (z > R.zMin - 4 && z < R.zMax + 4) continue;
      const hgt = Math.min(30, Math.pow((Math.abs(x) - B.xMax - 4) / 14, 1.6) * 6);
      (z < R.zMin ? sn : pn).push({ x, z, y: hgt * 0.8, s: 1.2 + rng() * 1.2, ry: rng() * 6 });
    }
    handles.trees = [instanced(scene, snowPine, sn), instanced(scene, pine, pn)];
    const shadeMat = new THREE.MeshBasicMaterial({ map: radialTexture('rgba(40,60,120,0.32)', 'rgba(40,60,120,0)'), transparent: true, depthWrite: false });
    for (const t of Scenery.trees) { const d = new THREE.Mesh(new THREE.CircleGeometry(t.r * 1.15, 24), shadeMat); d.rotation.x = -Math.PI / 2; d.position.set(t.x, 0.06, t.z); scene.add(d); }
    const sunMat = new THREE.MeshBasicMaterial({ map: radialTexture('rgba(255,236,140,0.75)', 'rgba(255,236,140,0)'), transparent: true, depthWrite: false });
    for (const s of Scenery.sun) { const d = new THREE.Mesh(new THREE.CircleGeometry(s.r * 1.2, 32), sunMat.clone()); d.rotation.x = -Math.PI / 2; d.position.set(s.x, 0.07, s.z); scene.add(d); handles.sunPatches.push(d); }
  }

  // ---------- props: snow mounds, rocks, ice crystals (meadow); mushrooms, bushes, logs, lanterns (forest) ----------
  {
    const clear = (x, z) => Math.abs(x) < 11 || (z > R.zMin - 5 && z < World.gate.z + 4) || z < 0 || Scenery.trees.some((t) => (t.x - x) ** 2 + (t.z - z) ** 2 < 16);
    const pick = (n, zMin, zMax) => { const out = []; for (let i = 0; i < n * 3 && out.length < n; i++) { const x = -74 + rng() * 148, z = zMin + rng() * (zMax - zMin); if (!clear(x, z)) out.push({ x, z }); } return out; };
    instanced(scene, part(new THREE.SphereGeometry(1, 16, 10), '#f4f9ff'), pick(40, 10, 160).map((p) => ({ ...p, y: -0.3, s: 1.4 + rng() * 2, sy: 0.5 + rng() * 0.3 })), { receive: true });
    const rockG = mergeGeometries([part(new THREE.DodecahedronGeometry(1, 1), '#93a2b8'), part(new THREE.SphereGeometry(0.85, 12, 6, 0, Math.PI * 2, 0, Math.PI / 3), '#ffffff', M(0, 0.25, 0))]);
    instanced(scene, rockG, pick(22, 10, 160).map((p) => ({ ...p, y: 0.2, s: 0.8 + rng() * 1.2, sy: 0.7, ry: rng() * 6 })), { receive: true });
    const crystalG = mergeGeometries([0, 1, 2].map((k) => part(new THREE.OctahedronGeometry(0.5, 0), '#a8ecff', M(Math.cos(k * 2.1) * 0.5, 0.8, Math.sin(k * 2.1) * 0.5, 1, 2.2 + k * 0.4, 1))));
    instanced(scene, crystalG, pick(14, 15, 155).map((p) => ({ ...p, s: 0.8 + rng() * 0.6, ry: rng() * 6 })), { mat: std(0xffffff, { vertexColors: true, emissive: '#3ab0e0', emissiveIntensity: 0.35, roughness: 0.2 }) });
    const mushroomG = mergeGeometries([part(new THREE.CylinderGeometry(0.35, 0.45, 1.2, 10), '#fff1dc', M(0, 0.6, 0)), part(new THREE.SphereGeometry(1, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), '#e2453f', M(0, 1.1, 0, 1, 0.75, 1)),
      ...[0, 1, 2, 3].map((k) => part(new THREE.SphereGeometry(0.16, 8, 6), '#ffffff', M(Math.cos(k * 1.6) * 0.6, 1.65, Math.sin(k * 1.6) * 0.6)))]);
    instanced(scene, mushroomG, pick(40, 200, 365).map((p) => ({ ...p, s: 0.8 + rng() * 1.1, ry: rng() * 6 })));
    instanced(scene, part(new THREE.SphereGeometry(1, 12, 8), '#3f8c46'), pick(50, 200, 365).map((p) => ({ ...p, y: 0.4, s: 1 + rng() * 1.3, sy: 0.75 })), { receive: true });
    const logG = part(new THREE.CylinderGeometry(0.6, 0.6, 4, 12), '#8a5a36', new THREE.Matrix4().makeRotationZ(Math.PI / 2).setPosition(0, 0.6, 0));
    instanced(scene, logG, pick(10, 205, 360).map((p) => ({ ...p, s: 1, ry: rng() * 6 })));
    // lanterns along the forest path
    const lanternPosts = [], lanternGlow = [];
    for (let z = 204; z < 365; z += 18) for (const x of [-10.5, 10.5]) { lanternPosts.push({ x, z, s: 1 }); lanternGlow.push({ x, z, y: 3.2, s: 1 }); }
    instanced(scene, part(new THREE.CylinderGeometry(0.15, 0.2, 3.2, 6), '#5d3b22', M(0, 1.6, 0)), lanternPosts);
    handles.lanterns.push(instanced(scene, new THREE.SphereGeometry(0.45, 12, 8), lanternGlow, { mat: std('#ffd47a', { emissive: '#ffb23a', emissiveIntensity: 1.2 }), cast: false }));
  }

  // ---------- landmarks: an ice-crystal statue (hub), a giant snowman (meadow), a giant mushroom (forest) ----------
  {
    const statue = new THREE.Group();
    const base = new THREE.Mesh(new THREE.CylinderGeometry(4.5, 5, 1.6, 24), std('#dbe8f7')); base.position.y = 0.8; statue.add(base);
    const crys = std('#bff1ff', { emissive: '#48b8e8', emissiveIntensity: 0.55, roughness: 0.12, transparent: true, opacity: 0.92 });
    [[0, 9, 0, 2.2], [2, 6, 1, 1.5], [-2, 6.5, -0.5, 1.6], [0.8, 5, -2, 1.2], [-1.2, 4.6, 2, 1.1]].forEach(([x, h, z, r]) => { const c = new THREE.Mesh(new THREE.OctahedronGeometry(r, 0), crys); c.scale.y = h / r / 1.6; c.position.set(x, 1.6 + h / 2, z); c.castShadow = true; statue.add(c); });
    statue.position.set(-36, 0, -34); scene.add(statue); handles.statue = statue;
    const snowman = new THREE.Group(); const white = std('#fbfdff');
    [[0, 4, 4], [0, 10, 3], [0, 14.6, 2.2]].forEach(([x, y, r]) => { const s = new THREE.Mesh(new THREE.SphereGeometry(r, 24, 16), white); s.position.set(x, y, 0); s.castShadow = true; snowman.add(s); });
    const nose = new THREE.Mesh(new THREE.ConeGeometry(0.45, 2.2, 10), std('#ff8a2a')); nose.rotation.x = -Math.PI / 2; nose.position.set(0, 14.6, -2.9); snowman.add(nose);
    for (const x of [-0.8, 0.8]) { const e = new THREE.Mesh(new THREE.SphereGeometry(0.3, 10, 8), std('#1b1433')); e.position.set(x, 15.3, -2); snowman.add(e); }
    const scarf = new THREE.Mesh(new THREE.TorusGeometry(2.4, 0.55, 10, 24), std('#e8414a')); scarf.rotation.x = Math.PI / 2; scarf.position.y = 12.6; snowman.add(scarf);
    const hat = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 1.6, 2.4, 20), std('#2d3561')); hat.position.y = 17.6; snowman.add(hat);
    snowman.position.set(46, 0, 112); snowman.rotation.y = 0.3; scene.add(snowman);
    handles.blockers.push({ obj: statue, x: -36, z: -34, r: 5 }, { obj: snowman, x: 46, z: 112, r: 4.5 });
    const shroom = new THREE.Group();
    const stem = new THREE.Mesh(new THREE.CylinderGeometry(2.2, 3, 14, 20), std('#fff1dc')); stem.position.y = 7; stem.castShadow = true; shroom.add(stem);
    const cap = new THREE.Mesh(new THREE.SphereGeometry(9, 28, 14, 0, Math.PI * 2, 0, Math.PI / 2), std('#e2453f')); cap.scale.y = 0.6; cap.position.y = 13.5; cap.castShadow = true; shroom.add(cap);
    for (let k = 0; k < 9; k++) { const d = new THREE.Mesh(new THREE.SphereGeometry(1.1, 10, 8), std('#ffffff')); const a = k * 0.7, rr = 4 + (k % 3) * 1.5; d.position.set(Math.cos(a) * rr, 13.5 + Math.sqrt(Math.max(0, 81 - rr * rr)) * 0.6 - 0.3, Math.sin(a) * rr); shroom.add(d); }
    shroom.position.set(-44, 0, 296); scene.add(shroom);
    handles.blockers.push({ obj: shroom, x: -44, z: 296, r: 9 });
  }

  // ---------- far scenery: snowy peaks north, green hills, dunes and a friendly volcano south ----------
  {
    const peak = (x, z, r, h, snowLine = 0.55, low = '#b7c7dc') => {
      const g = new THREE.ConeGeometry(r, h, 18, 6); const p = g.attributes.position; const cols = [];
      for (let i = 0; i < p.count; i++) { const t = (p.getY(i) + h / 2) / h; const c = t > snowLine ? C('#fbfdff') : C(low).lerp(C('#dfe9f6'), t / snowLine); cols.push(c.r, c.g, c.b); }
      g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3)); g.computeVertexNormals();
      const m = new THREE.Mesh(g, std(0xffffff, { vertexColors: true, roughness: 1 })); m.position.set(x, h / 2 - 4, z); scene.add(m); return m;
    };
    for (let i = 0; i < 13; i++) peak(-300 + i * 50, -200 - (i % 3) * 40, 46 + (i % 4) * 10, 90 + (i % 5) * 22, 0.5);
    for (let i = 0; i < 8; i++) peak(i % 2 ? 230 : -230, 40 + i * 50, 60, 60 + (i % 3) * 20, i < 4 ? 0.55 : 1.1, i < 4 ? '#b7c7dc' : '#6f9a68');
    const dune = std('#efcf94', { roughness: 1 });
    for (let i = 0; i < 9; i++) { const d = new THREE.Mesh(new THREE.SphereGeometry(60, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2), dune); d.scale.y = 0.28; d.position.set(-260 + i * 65, -3, 600 + (i % 2) * 50); scene.add(d); }
    const v = peak(130, 760, 110, 170, 2, '#8a5a4a');
    const lava = new THREE.Mesh(new THREE.CylinderGeometry(16, 22, 6, 18), std('#ff8a3c', { emissive: '#ff5a1a', emissiveIntensity: 1 })); lava.position.set(130, v.position.y + 82, 760); scene.add(lava);
    for (let i = 0; i < 6; i++) { const p = new THREE.Mesh(new THREE.SphereGeometry(16 + i * 4, 14, 10), std('#f6f1ec', { roughness: 1 })); p.position.set(130 + i * 9, v.position.y + 95 + i * 22, 760 - i * 6); scene.add(p); handles.puffs.push(p); }
  }

  // ---------- clouds ----------
  {
    const cm = std('#ffffff', { emissive: '#ffffff', emissiveIntensity: 0.25, roughness: 1 });
    for (let i = 0; i < 12; i++) {
      const c = new THREE.Group();
      for (let j = 0; j < 7; j++) { const s = new THREE.Mesh(new THREE.SphereGeometry(6 + rng() * 6, 14, 10), cm); s.position.set(j * 7 - 21 + rng() * 4, rng() * 4, rng() * 6); s.scale.y = 0.7; c.add(s); }
      c.position.set(-320 + i * 60, 95 + (i % 3) * 20, -160 + i * 80); scene.add(c); handles.clouds.push(c);
    }
  }

  // ---------- hub: plaza, pen (straw + wooden fence), spawn pad, lamps, benches ----------
  {
    const c = document.createElement('canvas'); c.width = c.height = 256; const x = c.getContext('2d');
    x.fillStyle = '#e3eefb'; x.fillRect(0, 0, 256, 256); x.strokeStyle = '#c6d6ea'; x.lineWidth = 4;
    for (let i = 0; i <= 4; i++) { x.beginPath(); x.moveTo(i * 64, 0); x.lineTo(i * 64, 256); x.stroke(); x.beginPath(); x.moveTo(0, i * 64); x.lineTo(256, i * 64); x.stroke(); }
    const tex = new THREE.CanvasTexture(c); tex.wrapS = tex.wrapT = THREE.RepeatWrapping; tex.repeat.set(9, 9); tex.colorSpace = THREE.SRGBColorSpace;
    const plaza = new THREE.Mesh(new THREE.CylinderGeometry(38, 38.5, 0.4, 64), std(0xffffff, { map: tex, roughness: 0.6 })); plaza.position.set(0, 0.02, -28); plaza.receiveShadow = true; scene.add(plaza);
    const p = World.pen;
    const sc = document.createElement('canvas'); sc.width = sc.height = 128; const sx = sc.getContext('2d'); sx.fillStyle = '#f2d17e'; sx.fillRect(0, 0, 128, 128);
    for (let i = 0; i < 260; i++) { sx.strokeStyle = i % 2 ? 'rgba(200,150,60,0.5)' : 'rgba(255,240,170,0.6)'; sx.lineWidth = 2; const a = rng() * 128, b = rng() * 128, ang = rng() * 3; sx.beginPath(); sx.moveTo(a, b); sx.lineTo(a + Math.cos(ang) * 9, b + Math.sin(ang) * 9); sx.stroke(); }
    const straw = new THREE.CanvasTexture(sc); straw.wrapS = straw.wrapT = THREE.RepeatWrapping; straw.repeat.set(4, 3); straw.colorSpace = THREE.SRGBColorSpace;
    const floor = new THREE.Mesh(new RoundedBoxGeometry(p.xMax - p.xMin, 0.4, p.zMax - p.zMin, 2, 0.15), std(0xffffff, { map: straw, roughness: 1 })); floor.position.set(0, 0.2, (p.zMin + p.zMax) / 2); floor.receiveShadow = true; scene.add(floor);
    const posts = [], railsSpec = [];
    const fenceLine = (x1, z1, x2, z2) => { const n = Math.max(1, Math.round(Math.hypot(x2 - x1, z2 - z1) / 3.2)); for (let i = 0; i <= n; i++) posts.push({ x: x1 + ((x2 - x1) * i) / n, z: z1 + ((z2 - z1) * i) / n, s: 1 }); railsSpec.push([x1, z1, x2, z2]); };
    fenceLine(p.xMin, p.zMin, p.xMax, p.zMin); fenceLine(p.xMin, p.zMin, p.xMin, p.zMax); fenceLine(p.xMax, p.zMin, p.xMax, p.zMax); fenceLine(p.xMin, p.zMax, -5, p.zMax); fenceLine(5, p.zMax, p.xMax, p.zMax);
    instanced(scene, part(new RoundedBoxGeometry(0.6, 2.4, 0.6, 2, 0.15), '#b77b48', M(0, 1.2, 0)), posts);
    for (const [x1, z1, x2, z2] of railsSpec) for (const y of [0.9, 1.8]) { const len = Math.hypot(x2 - x1, z2 - z1); const r = new THREE.Mesh(new RoundedBoxGeometry(len, 0.28, 0.22, 2, 0.08), std('#c98f58')); r.position.set((x1 + x2) / 2, y, (z1 + z2) / 2); r.rotation.y = -Math.atan2(z2 - z1, x2 - x1); r.castShadow = true; scene.add(r); }
    const pad = new THREE.Mesh(new THREE.CylinderGeometry(3.6, 3.9, 0.35, 32), std('#9fdcff', { emissive: '#3ab0e0', emissiveIntensity: 0.2 })); pad.position.set(World.spawn.x, 0.18, World.spawn.z); pad.receiveShadow = true; scene.add(pad);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(3.7, 0.18, 8, 40), std('#ffffff', { emissive: '#bff1ff', emissiveIntensity: 0.6 })); ring.rotation.x = Math.PI / 2; ring.position.set(World.spawn.x, 0.4, World.spawn.z); scene.add(ring);
    const lampPosts = [], lampGlows = [];
    for (const [lx, lz] of [[-20, -6], [20, -6], [-30, -48], [30, -48]]) { lampPosts.push({ x: lx, z: lz, s: 1 }); lampGlows.push({ x: lx, z: lz, y: 6.4, s: 1 }); }
    instanced(scene, part(new THREE.CylinderGeometry(0.22, 0.3, 6.2, 8), '#3a3f63', M(0, 3.1, 0)), lampPosts);
    handles.lanterns.push(instanced(scene, new THREE.SphereGeometry(0.75, 14, 10), lampGlows, { mat: std('#fff1c4', { emissive: '#ffd47a', emissiveIntensity: 1.1 }), cast: false }));
    const benchG = mergeGeometries([part(new RoundedBoxGeometry(4, 0.35, 1.2, 2, 0.12), '#c98f58', M(0, 1, 0)), part(new RoundedBoxGeometry(4, 1, 0.3, 2, 0.1), '#c98f58', M(0, 1.6, 0.55)),
      part(new THREE.BoxGeometry(0.3, 1, 1), '#5d3b22', M(-1.6, 0.5, 0)), part(new THREE.BoxGeometry(0.3, 1, 1), '#5d3b22', M(1.6, 0.5, 0))]);
    instanced(scene, benchG, [{ x: -36, z: -22, s: 1, ry: Math.PI }, { x: -28, z: -44, s: 1, ry: 0.6 }, { x: -44, z: -44, s: 1, ry: -0.6 }]);
  }

  // per-frame ambient motion (only gentle things move: World Rules / Animation Rules)
  handles.clearView = (cam, me, dt = 0.016) => {
    for (const m of handles.trees) clearCorridor(m, cam, me);
    for (const b of handles.blockers) fadeBlocker(b, cam, me, dt);
  };
  handles.update = (dt, t) => {
    handles.water.offset.x = (handles.water.offset.x + dt * 0.02) % 1; handles.water.offset.y = Math.sin(t * 0.3) * 0.02;
    handles.clouds.forEach((c, i) => { c.position.x += dt * (0.8 + (i % 3) * 0.3); if (c.position.x > 380) c.position.x = -380; });
    handles.puffs.forEach((p, i) => { p.position.y += Math.sin(t * 0.4 + i) * dt * 0.8; });
    handles.sunPatches.forEach((d, i) => { d.material.opacity = 0.85 + Math.sin(t * 1.5 + i) * 0.15; });
    handles.iceSpot.material.opacity = 0.6 + Math.sin(t * 4) * 0.35;
    if (!Config.motion.reduced) handles.statue.rotation.y = Math.sin(t * 0.2) * 0.05;
  };
  return handles;
}
