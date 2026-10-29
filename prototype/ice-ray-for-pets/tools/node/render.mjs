// Render GLB pets with three.js in headless Chromium, for side-by-side checks
// against the concept (Pet Rules 5: judge every 3D model next to its concept).
//
// Usage: node render.mjs <out.png> <model.glb> [yawDeg=-35] [size=1024]
// The pet is framed like the concepts: centred, plain white, light from the top left.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const [out, model, yaw = '-35', size = '1024'] = process.argv.slice(2);

const page = `<!doctype html><html><body style="margin:0;background:#fff">
<script type="importmap">{"imports":{"three":"/node_modules/three/build/three.module.js","three/addons/":"/node_modules/three/examples/jsm/"}}</script>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
const S = ${Number(size)};
const r = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
r.setSize(S, S); r.setClearColor(0xffffff, 1);
r.outputColorSpace = THREE.SRGBColorSpace; r.toneMapping = THREE.NoToneMapping;
document.body.appendChild(r.domElement);
const scene = new THREE.Scene();
scene.add(new THREE.HemisphereLight(0xffffff, 0xd8d0c8, 1.6));
const key = new THREE.DirectionalLight(0xffffff, 1.5); key.position.set(-3, 5, 4); scene.add(key);
const fill = new THREE.DirectionalLight(0xffffff, 0.5); fill.position.set(3, 1, 3); scene.add(fill);
new GLTFLoader().load('/model.glb', (g) => {
  const pet = g.scene;
  pet.rotation.y = THREE.MathUtils.degToRad(${Number(yaw)});
  const box = new THREE.Box3().setFromObject(pet);
  const c = box.getCenter(new THREE.Vector3()), s = box.getSize(new THREE.Vector3());
  pet.position.sub(c);
  scene.add(pet);
  const cam = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
  const dist = Math.max(s.x, s.y, s.z) * 2.3;
  cam.position.set(0, s.y * 0.25, dist); cam.lookAt(0, 0, 0);
  r.render(scene, cam);
  window.done = true;
});
</script></body></html>`;

const server = http.createServer((req, res) => {
  if (req.url === '/') return res.end(page);
  if (req.url === '/model.glb') return fs.createReadStream(model).pipe(res);
  const f = path.join(here, decodeURIComponent(req.url));
  if (!f.startsWith(here) || !fs.existsSync(f)) { res.statusCode = 404; return res.end(); }
  res.setHeader('Content-Type', f.endsWith('.js') ? 'text/javascript' : 'application/octet-stream');
  fs.createReadStream(f).pipe(res);
}).listen(0);
const port = server.address().port;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await browser.newPage({ viewport: { width: Number(size), height: Number(size) } });
p.on('pageerror', (e) => console.error('page error:', e.message));
await p.goto(`http://127.0.0.1:${port}/`);
await p.waitForFunction('window.done === true', null, { timeout: 120000 });
await p.locator('canvas').screenshot({ path: out });
await browser.close();
server.close();
console.log('rendered', out);
