// Print triangle count, bounds, materials and texture sizes of a GLB.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { getBounds } from '@gltf-transform/functions';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const f of process.argv.slice(2)) {
  const doc = await io.read(f);
  const root = doc.getRoot();
  let tris = 0;
  for (const m of root.listMeshes()) for (const p of m.listPrimitives()) {
    const idx = p.getIndices();
    tris += idx ? idx.getCount() / 3 : p.getAttribute('POSITION').getCount() / 3;
  }
  const b = getBounds(root.listScenes()[0]);
  const size = b.max.map((v, i) => +(v - b.min[i]).toFixed(3));
  const tex = root.listTextures().map(t => `${t.getName() || '?'} ${t.getMimeType()} ${t.getSize()?.join('x')}`);
  console.log(f.split('/').pop(), { tris, meshes: root.listMeshes().length, materials: root.listMaterials().map(m => m.getName()), size, tex });
}
