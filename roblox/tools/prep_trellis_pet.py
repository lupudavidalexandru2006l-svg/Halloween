# prep_trellis_pet.py: get a TRELLIS model ready for Roblox and render it from four sides.
#   blender -b --factory-startup --python prep_trellis_pet.py -- <raw.glb> <out_dir> <key> [turn_degrees] [max_tris]
# Centres it, stands it on the ground, turns it so its face looks at -Y (Blender front = Roblox -Z after
# export), trims to 19,000 triangles (Roblox allows 20,000 per mesh), writes <key>.glb and
# <key>_{front,34,side,back}_render.png.
import bpy, math, os, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
RAW, OUT, KEY = argv[0], argv[1], argv[2]
TURN = float(argv[3]) if len(argv) > 3 else 0.0
MAX_TRIS = int(argv[4]) if len(argv) > 4 else 19000  # Pet Rules target: under 8,000

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
# merge_vertices: glTF arrives split along every texture seam, and trimming pulls those split
# edges apart into see-through cracks (Capcrown Badger, 2026-11-09); welded, the seams hold
bpy.ops.import_scene.gltf(filepath=RAW, merge_vertices=True)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for o in list(bpy.context.scene.objects):
    if o != obj:
        bpy.data.objects.remove(o)
# glTF imports use quaternion rotation, so turn the matrix, not rotation_euler
from mathutils import Matrix
obj.matrix_world = Matrix.Rotation(math.radians(TURN), 4, "Z") @ obj.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Optional fixes after the numbers: fill (close holes), hue=<deg>, sat=<x>, val=<x> (texture colour
# shift when TRELLIS drifts from the painting's colour, e.g. magenta coming out red),
# only=<lo>-<hi> (limit that shift to one hue range in degrees, e.g. Shimmerfrog's teal body
# without turning its yellow belly green).
OPTS = dict((a.split("=") + [""])[:2] for a in argv[5:])
if "fill" in OPTS:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.select_all(action="DESELECT")
    import bmesh
    ebm = bmesh.from_edit_mesh(obj.data)
    new = bmesh.ops.holes_fill(ebm, edges=[e for e in ebm.edges if e.is_boundary], sides=0)["faces"]
    new = bmesh.ops.poke(ebm, faces=new)["faces"]  # a centre point per hole, so it can be relaxed
    for f in new:
        f.select_set(True)
    bmesh.update_edit_mesh(obj.data)
    print("FILL holes filled with", len(new), "faces")
    # smooth the patch: add inner points and relax them, so it isn't a crumpled fan
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.subdivide(number_cuts=3)
    bpy.ops.mesh.select_less()
    bpy.ops.mesh.vertices_smooth(factor=1.0, repeat=30)
    bpy.ops.mesh.select_more()
    bpy.ops.object.mode_set(mode="OBJECT")
    patch_faces = [p.index for p in obj.data.polygons if p.select]
    print("FILL patch faces", len(patch_faces))
    if patch_faces:
        import bmesh
        import numpy as np
        img = next(n.image for m in obj.data.materials if m and m.use_nodes
                   for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
        W, H = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
        bm = bmesh.new(); bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        uv = bm.loops.layers.uv.active
        patch = set(patch_faces)
        # body colour = the most common colour under the other faces' centres
        cols = []
        for f in bm.faces:
            if f.index in patch: continue
            u = sum((l[uv].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
            cols.append(px[min(H - 1, int(u.y * H)), min(W - 1, int(u.x * W)), :3])
        cols = np.array(cols)
        q = np.round(cols * 12)
        keys, counts = np.unique(q, axis=0, return_counts=True)
        body = cols[(q == keys[counts.argmax()]).all(1)].mean(0)
        # TRELLIS packs the texture full, so squeeze it 6% in height (and every UV with it) to
        # free a 64-pixel strip at the top, and paint the patch there
        B = 64
        keep = H - B
        src = np.linspace(0, H - 1, keep)
        lo_r = np.floor(src).astype(int); hi_r = np.minimum(lo_r + 1, H - 1); t = (src - lo_r)[:, None, None]
        squeezed = px[lo_r] * (1 - t) + px[hi_r] * t
        px[:keep] = squeezed
        for f in bm.faces:
            if f.index in patch: continue
            for l in f.loops:
                l[uv].uv.y = (l[uv].uv.y * (H - 1)) / (H - 1) * keep / H
        x0, y0 = 0, keep
        # split the patch into connected pieces; the biggest one is the mouth and gets the smile
        pieces, seen = [], set()
        for i in patch_faces:
            if i in seen: continue
            stack, piece = [i], []
            seen.add(i)
            while stack:
                f = bm.faces[stack.pop()]; piece.append(f)
                for e in f.edges:
                    for g in e.link_faces:
                        if g.index in patch and g.index not in seen:
                            seen.add(g.index); stack.append(g.index)
            pieces.append(piece)
        pieces.sort(key=len, reverse=True)
        px[y0:y0 + B, x0:x0 + B, :3] = body
        px[y0:y0 + B, x0:x0 + B, 3] = 1
        mouth = pieces[0]
        # smoothing leaves a dent: put the patch's inner points back on the sphere that fits the
        # surface round it (pets are round, so this follows the body's curve)
        inner = {v for f in mouth for v in f.verts}
        rim = {v for v in inner if any(g.index not in patch for g in v.link_faces)}
        ring = set(rim)
        for _ in range(2):
            ring |= {w for v in ring for e in v.link_edges for w in e.verts}
        ring = [v for v in ring if v not in inner or v in rim]
        A = np.array([[2 * v.co.x, 2 * v.co.y, 2 * v.co.z, 1] for v in ring])
        bvec = np.array([v.co.length_squared for v in ring])
        a, b_, c, dd = np.linalg.lstsq(A, bvec, rcond=None)[0]
        ctr = Vector((a, b_, c)); rad = math.sqrt(dd + ctr.length_squared)
        for v in inner - rim:
            v.co = ctr + (v.co - ctr).normalized() * rad
        bm.normal_update()
        # the faces round the patch still show the old mouth's dark edge: paint two rings of them
        # from the clean block too, except the eyes (near black), and match the block's colour
        # to the body colour right there so no circle shows
        def tex(g):
            u = sum((l[uv].uv for l in g.loops), Vector((0, 0))) / len(g.loops)
            return px[min(H - 1, int(u.y * H)), min(W - 1, int(u.x * W)), :3]
        near, edge = set(), set(rim)
        for _ in range(2):
            grow = set()
            for v in edge:
                for g in v.link_faces:
                    if g.index in patch or g in near: continue
                    if tex(g).mean() > body.mean() * 0.25:
                        near.add(g); grow |= set(g.verts)
            edge = grow
        outer = {g for v in edge for g in v.link_faces
                 if g.index not in patch and g not in near and tex(g).mean() > body.mean() * 0.6}
        if outer:
            body = np.median(np.array([tex(g) for g in outer]), axis=0)
            px[y0:y0 + B, x0:x0 + B, :3] = body
        mouth = mouth + list(near)
        nrm = sum((f.normal for f in mouth), Vector()).normalized()
        up = Vector((0, 0, 1))
        side = up.cross(nrm).normalized(); up = nrm.cross(side).normalized()
        pts = [v.co for f in mouth for v in f.verts]
        su = [p.dot(side) for p in pts]; sv = [p.dot(up) for p in pts]
        cu, cv = (min(su) + max(su)) / 2, (min(sv) + max(sv)) / 2
        r = max(max(su) - min(su), max(sv) - min(sv)) / 2 * 1.15
        for f in mouth:
            for l in f.loops:
                p = l.vert.co
                a = (p.dot(side) - cu) / r * 0.5 + 0.5
                b = (p.dot(up) - cv) / r * 0.5 + 0.5
                l[uv].uv = ((x0 + 2 + a * (B - 4)) / W, (y0 + 2 + b * (B - 4)) / H)
        for piece in pieces[1:]:
            for f in piece:
                for l in f.loops:
                    l[uv].uv = ((x0 + 4) / W, (y0 + 4) / H)
        # the smile: the bottom of a circle, like the painting's small closed smile
        yy, xx = np.mgrid[0:B, 0:B] / (B - 1.0)
        d = np.hypot(xx - 0.5, yy - 0.6)
        ang = np.arctan2(yy - 0.6, xx - 0.5)
        smile = (np.abs(d - 0.2) < 0.022) & (ang < -0.6) & (ang > -2.54)
        blk = px[y0:y0 + B, x0:x0 + B, :3]
        blk[smile] = body * 0.25
        img.pixels[:] = px.ravel()
        img.pack()
        bm.to_mesh(obj.data); bm.free()
if any(k in OPTS for k in ("hue", "sat", "val")):
    import colorsys
    import numpy as np
    dh = float(OPTS.get("hue", 0)) / 360.0
    ks, kv = float(OPTS.get("sat", 1)), float(OPTS.get("val", 1))
    for img in {n.image for m in obj.data.materials if m and m.use_nodes
                for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}:
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        rgb = px[:, :3]
        mx, mn = rgb.max(1), rgb.min(1)
        d = mx - mn
        h = np.zeros_like(mx)
        m = d > 1e-6
        r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
        i = m & (mx == r); h[i] = ((g[i] - b[i]) / d[i]) % 6
        i = m & (mx == g); h[i] = (b[i] - r[i]) / d[i] + 2
        i = m & (mx == b); h[i] = (r[i] - g[i]) / d[i] + 4
        h = (h / 6 + dh) % 1.0
        s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0) * ks
        v = mx * kv
        s, v = np.clip(s, 0, 1), np.clip(v, 0, 1)
        k = (np.arange(3)[None, :] * 0 + np.array([5, 3, 1])[None, :] + h[:, None] * 6) % 6
        rgb2 = v[:, None] - v[:, None] * s[:, None] * np.clip(np.minimum(k, 4 - k), 0, 1)
        if "only" in OPTS:  # only=<lo>-<hi>: change just the colours whose hue (degrees) is in range
            lo, hi = (float(x) / 360.0 for x in OPTS["only"].split("-"))
            h0 = (h - dh) % 1.0
            rgb2 = np.where(((h0 >= lo) & (h0 <= hi))[:, None], rgb2, rgb)
        px[:, :3] = rgb2
        img.pixels[:] = px.ravel()
        img.pack()

tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
if tris > MAX_TRIS:
    dec = obj.modifiers.new("Reduce", "DECIMATE")
    dec.ratio = MAX_TRIS / tris * 0.98
    bpy.ops.object.modifier_apply(modifier="Reduce")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode="OBJECT")
# TRELLIS meshes arrive flat-shaded (every triangle shows as a facet): smooth them like clay
if obj.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
bpy.ops.object.shade_smooth()

# 1 unit tall, centred on X/Y, feet on the ground (the game rescales it anyway)
pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
s = 1.0 / (hi.z - lo.z)
obj.location = (-(lo.x + hi.x) / 2 * s, -(lo.y + hi.y) / 2 * s, -lo.z * s)
obj.scale = (s, s, s)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
obj.name = KEY
obj.data.name = KEY
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, KEY + ".glb"), use_selection=True, export_format="GLB")

scene = bpy.context.scene
world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (1, 1, 1, 1)
bg.inputs[1].default_value = 1.0
for loc, energy in (((-1.5, -2.5, 2.5), 120), ((0.8, 2.6, 2.2), 90)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lt = bpy.context.object
    lt.data.energy = energy
    lt.data.size = 3
    lt.rotation_euler = (Vector((0, 0, 0.5)) - lt.location).to_track_quat("-Z", "Y").to_euler()
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 768
scene.view_settings.view_transform = "Standard"
for tag, loc in (("front", (0, -2.1, 0.5)), ("34", (1.35, -1.65, 0.75)), ("side", (2.2, 0.0, 0.6)), ("back", (-0.5, 2.0, 0.7))):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.lens = 50
    cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, f"{KEY}_{tag}_render.png")
    bpy.ops.render.render(write_still=True)
print("PREP DONE", KEY, tris, "->", sum(len(p.vertices) - 2 for p in obj.data.polygons), "triangles")
