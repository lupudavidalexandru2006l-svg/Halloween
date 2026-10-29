// Make a Rodin GLB Roblox-ready: under the triangle budget (Pet Rules: < 8,000)
// and textures at most 1024 px (Roblox's texture limit). UV seams are kept.
//
// Usage: node optimize.mjs <in.glb> <out.glb> [maxTris=7500] [maxTexture=1024]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, textureCompress, prune, dedup } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const [inPath, outPath, maxTrisArg = '7500', maxTexArg = '1024'] = process.argv.slice(2);
const maxTris = Number(maxTrisArg), maxTex = Number(maxTexArg);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

function countTris(doc) {
  let t = 0;
  for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) {
    const idx = p.getIndices();
    t += idx ? idx.getCount() / 3 : p.getAttribute('POSITION').getCount() / 3;
  }
  return t;
}

await MeshoptSimplifier.ready;
const original = await io.readBinary(await io.writeBinary(await io.read(inPath)));
const before = countTris(original);
let ratio = Math.min(1, maxTris / before);
let doc, after;
for (let i = 0; i < 6; i++) {
  doc = await io.readBinary(await io.writeBinary(original));
  if (ratio < 1) {
    await doc.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.01 }));
  }
  after = countTris(doc);
  if (after <= maxTris) break;
  ratio *= (maxTris / after) * 0.97; // the simplifier stops early on detailed areas; push a bit harder
}
await doc.transform(
  textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [maxTex, maxTex], quality: 88 }),
  dedup(),
  prune(),
);
await io.write(outPath, doc);
console.log(`${inPath.split('/').pop()}: ${before} -> ${after} triangles, textures <= ${maxTex}px -> ${outPath.split('/').pop()}`);
