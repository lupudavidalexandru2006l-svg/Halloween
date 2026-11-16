# dots_to_beads.py: turn a split pet's scattered glow pieces (e.g. WingGlowL from a colour rule) into round beads.
#   blender -b --factory-startup --python dots_to_beads.py -- <rig.glb> <out.glb> <part,part,...> [radius=0.018] [gap=0.035] [min=2] [base=<uncut rig.glb>]
# base=: split once with the glow rules (<rig.glb>) and once without them (<uncut rig.glb>); the beads go onto the uncut one.
# A colour rule cuts a painted spot pattern into slivers of triangles, which look like confetti as Neon. This
# groups each part's triangles into clusters (centres closer than gap), drops clusters with fewer than min
# triangles, and replaces the part's mesh with one small sphere per cluster, set out along the surface normal.
# Mirage Manta 2026-11-16: the wing dots.
import bpy, bmesh, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NAMES = argv[0], argv[1], argv[2].split(",")
OPTS = dict(a.split("=") for a in argv[3:])
RAD, GAP, MIN = float(OPTS.get("radius", 0.018)), float(OPTS.get("gap", 0.035)), int(OPTS.get("min", 2))
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=SRC)
for o in [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name in NAMES]:
    mw = o.matrix_world
    faces = [(mw @ p.center, (mw.to_3x3() @ p.normal).normalized()) for p in o.data.polygons]
    left = list(range(len(faces))); clusters = []
    while left:
        grp = [left.pop()]; i = 0
        while i < len(grp):
            c = faces[grp[i]][0]
            near = [j for j in left if (faces[j][0] - c).length < GAP]
            for j in near: left.remove(j)
            grp += near; i += 1
        if len(grp) >= MIN: clusters.append(grp)
    bm = bmesh.new()
    inv = mw.inverted()
    for g in clusters:
        c = sum((faces[j][0] for j in g), Vector()) / len(g)
        n = sum((faces[j][1] for j in g), Vector()).normalized()
        r = RAD * min(1.6, 0.8 + 0.05 * len(g))
        m = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        bmesh.ops.translate(bm, verts=m["verts"], vec=inv @ (c + n * r * 0.35))
    bm.to_mesh(o.data); bm.free()
    for p in o.data.polygons: p.use_smooth = True
    print("BEADS", o.name, len(clusters), "from", len(faces), "triangles")
if "base" in OPTS:  # keep only the beads, and add them to the uncut rig (no holes where the dots were)
    for o in [o for o in bpy.context.scene.objects if o.name not in NAMES]:
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=OPTS["base"])
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print("BEADS saved", OUT)
