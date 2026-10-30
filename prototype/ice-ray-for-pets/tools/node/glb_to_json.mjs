// Convert a GLB to a self-contained glTF JSON (buffers + textures as data URIs), for hosts that
// don't serve .glb (claude.ai artifacts). GLTFLoader reads either.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import fs from 'node:fs';
const [inPath, outPath] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inPath);
const { json, resources } = await io.writeJSON(doc);
const mime = (u) => (u.endsWith('.png') ? 'image/png' : u.endsWith('.jpg') || u.endsWith('.jpeg') ? 'image/jpeg' : 'application/octet-stream');
for (const b of json.buffers || []) if (b.uri && resources[b.uri]) b.uri = `data:application/octet-stream;base64,${Buffer.from(resources[b.uri]).toString('base64')}`;
for (const im of json.images || []) if (im.uri && resources[im.uri]) im.uri = `data:${mime(im.uri)};base64,${Buffer.from(resources[im.uri]).toString('base64')}`;
fs.writeFileSync(outPath, JSON.stringify(json));
console.log(outPath, (fs.statSync(outPath).size / 1024).toFixed(0) + ' KB');
