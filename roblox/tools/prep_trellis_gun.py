# prep_trellis_gun.py: get a TRELLIS gun model ready for Roblox and render it from four sides.
#   blender -b --factory-startup --python prep_trellis_gun.py -- <raw.glb> <out_dir> <key> <beams>
# Joins the parts, finds the gun's long axis and turns it so the muzzle points +X (the end away from
# the grip, which is the low part), stands it upright (+Z), makes it 1 unit long, trims it to 19,000
# triangles (Roblox allows 20,000 per mesh) and writes <key>.glb, <key>_{front,34,side,back}_render.png
# and <key>.json: the grip and one tip per beam, in Roblox axes (x, y, z) = (blender x, z, -y),
# measured from the model's bounding-box centre (where Roblox puts a MeshPart's origin).
import bpy, json, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
RAW, OUT, KEY, BEAMS = argv[0], argv[1], argv[2], int(argv[3])
MAX_TRIS = 19000

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=RAW)
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
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def points():
    return [obj.matrix_world @ v.co for v in obj.data.vertices]

# the long axis in the ground plane (2D principal axis of the vertices)
pts = points()
n = len(pts)
cx = sum(p.x for p in pts) / n
cy = sum(p.y for p in pts) / n
sxx = sum((p.x - cx) ** 2 for p in pts) / n
syy = sum((p.y - cy) ** 2 for p in pts) / n
sxy = sum((p.x - cx) * (p.y - cy) for p in pts) / n
angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
obj.matrix_world = Matrix.Rotation(-angle, 4, "Z") @ obj.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# the grip is the low part and sits behind the middle: the muzzle is the other end
pts = points()
zs = sorted(p.z for p in pts)
low = zs[int(len(zs) * 0.2)]
xs = [p.x for p in pts]
mid = (min(xs) + max(xs)) / 2
grip_x = sum(p.x for p in pts if p.z <= low) / max(1, sum(1 for p in pts if p.z <= low))
if grip_x > mid:
    obj.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ obj.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
if tris > MAX_TRIS:
    dec = obj.modifiers.new("Reduce", "DECIMATE")
    dec.ratio = MAX_TRIS / tris * 0.98
    bpy.ops.object.modifier_apply(modifier="Reduce")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode="OBJECT")

# 1 unit long, centred on its bounding box
pts = points()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
s = 1.0 / (hi.x - lo.x)
obj.location = (-(lo.x + hi.x) / 2 * s, -(lo.y + hi.y) / 2 * s, -(lo.z + hi.z) / 2 * s)
obj.scale = (s, s, s)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
obj.name = KEY
obj.data.name = KEY

pts = points()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
L = hi.x - lo.x
# grip: the middle of the lower rear part (where the hand closes)
rear = [p for p in pts if p.x < lo.x + 0.55 * L and p.z < lo.z + 0.45 * (hi.z - lo.z)]
grip = sum(rear, Vector()) / max(1, len(rear)) if rear else Vector((0, 0, lo.z))
# tips: the vertices in the front 6% of the length, split into one group per beam (k-means in the y-z plane)
front = [p for p in pts if p.x > hi.x - 0.06 * L]
centres = []
if front:
    fy = sorted(front, key=lambda p: (p.z, p.y))
    centres = [fy[int((i + 0.5) / BEAMS * len(fy))].copy() for i in range(BEAMS)]
    for _ in range(25):
        groups = [[] for _ in centres]
        for p in front:
            j = min(range(len(centres)), key=lambda k: (p.y - centres[k].y) ** 2 + (p.z - centres[k].z) ** 2)
            groups[j].append(p)
        centres = [sum(g, Vector()) / len(g) if g else c for g, c in zip(groups, centres)]
tips = [Vector((hi.x, c.y, c.z)) for c in centres] or [Vector((hi.x, 0, 0))]

def rbx(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]

with open(os.path.join(OUT, KEY + ".json"), "w") as f:
    json.dump({"key": KEY, "size": [abs(c) for c in rbx(hi - lo)], "grip": rbx(grip), "tips": [rbx(t) for t in tips]}, f)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, KEY + ".glb"), use_selection=True, export_format="GLB")

scene = bpy.context.scene
world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = next(nd for nd in world.node_tree.nodes if nd.type == "BACKGROUND")
bg.inputs[0].default_value = (1, 1, 1, 1)
bg.inputs[1].default_value = 1.0
for loc, energy in (((-1.5, -2.5, 2.0), 120), ((0.8, 2.6, 1.8), 90)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    lt = bpy.context.object
    lt.data.energy = energy
    lt.data.size = 3
    lt.rotation_euler = (Vector((0, 0, 0)) - lt.location).to_track_quat("-Z", "Y").to_euler()
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 768
scene.view_settings.view_transform = "Standard"
# side = the painting's view (muzzle to the right), then 3/4, front (down the barrel) and back
for tag, loc in (("side", (0, -2.2, 0.15)), ("34", (1.4, -1.6, 0.5)), ("front", (2.2, 0, 0.2)), ("back", (-1.5, 1.6, 0.4))):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.lens = 50
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, f"{KEY}_{tag}_render.png")
    bpy.ops.render.render(write_still=True)
print("PREP DONE", KEY, tris, "->", sum(len(p.vertices) - 2 for p in obj.data.polygons), "triangles", "tips", len(tips))
