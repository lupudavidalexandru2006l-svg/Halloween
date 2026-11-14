# split_pet.py: cut a prepped pet (<key>.glb from prep_trellis_pet.py) into named parts for the rig, one GLB.
#   blender -b --factory-startup --python split_pet.py -- <key>.glb <out.glb> <spec.json>
# spec.json: {"parts": [["Head", "<rule>"], ["EarL", "<rule>"], ...], "scale": {"FrillL": [1.15, [0, 0, 0.6], 0.2, 0.42]}}
# Each face goes to the first part whose rule is true at the face's centre; the rest is "Body". A rule is a
# Python expression over x, y, z in pet heights (z 0 at the feet to 1 at the top; x, y from the centre; front is
# -y; the pet's own left is +x, which becomes Roblox -X; as in grid_views.py) and h, s, v: the texture colour there (hue in degrees, 0-1).
# Read the numbers off grid_views.py's pictures. "scale" grows a part in x and z round a point (e.g. a bigger
# frill). The output is 1 tall (1 stud in Roblox), every part a separate mesh sharing the one material.
import bpy, sys, json, colorsys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SPEC = argv[0], argv[1], json.load(open(argv[2]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=SRC, merge_vertices=True)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data
co = np.array([v.co[:] for v in me.vertices])
lo, hi = co.min(0), co.max(0)
H = hi[2] - lo[2]
ctr = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
# normalise: 1 tall, centred in x/y, feet at z 0
for v in me.vertices:
    v.co = Vector(((np.array(v.co[:]) - ctr) / H).tolist())

img = next(n.image for m in me.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
W, Hh = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(Hh, W, 4)
uv = me.uv_layers.active.data
rules = [(name, compile(rule, name, "eval")) for name, rule in SPEC["parts"]]
assign = []
for p in me.polygons:
    x, y, z = p.center
    u = sum((uv[i].uv for i in p.loop_indices), Vector((0, 0))) / p.loop_total
    r, g, b = px[min(Hh - 1, max(0, int(u.y * Hh))), min(W - 1, max(0, int(u.x * W))), :3]
    h, s, v = colorsys.rgb_to_hsv(float(r), float(g), float(b))
    h *= 360
    name = next((n for n, c in rules if eval(c)), "Body")
    assign.append(name)

names = ["Body"] + [n for n, _ in rules]
counts = {n: assign.count(n) for n in names}
print("SPLIT faces", counts)
# one object per part: duplicate, delete the other faces
import bmesh
made = []
for n in names:
    if counts[n] == 0:
        continue
    o = obj.copy(); o.data = obj.data.copy(); o.name = n; o.data.name = n
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if assign[f.index] != n], context="FACES")
    if n in SPEC.get("scale", {}):
        # [k, [x, y, z], r0, r1]: grow by k at r1 and beyond from the point (in x/z), not at all inside r0, so
        # the piece stays joined where it meets the body (a frill round the head)
        k, (sx, sy, sz), r0, r1 = SPEC["scale"][n]
        for v in bm.verts:
            r = math.hypot(v.co.x - sx, v.co.z - sz)
            f = 1 + (k - 1) * min(1, max(0, (r - r0) / (r1 - r0)))
            v.co.x = sx + (v.co.x - sx) * f
            v.co.z = sz + (v.co.z - sz) * f
    bm.to_mesh(o.data); bm.free()
    made.append(o)
    print("PART", n, len(o.data.polygons), "tris~", sum(len(p.vertices) - 2 for p in o.data.polygons))
bpy.data.objects.remove(obj)
bpy.ops.object.select_all(action="DESELECT")
for o in made:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB")
print("SPLIT saved", OUT)
