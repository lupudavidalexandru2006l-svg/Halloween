# parts_view.py: check a split pet (split_pet.py output): each part in its own flat colour, from the side,
# the front, 3/4 back and the textured 3/4 front, side by side in one PNG.
#   blender -b --factory-startup --python parts_view.py -- <split.glb> <out.png>
import bpy, sys, math, colorsys
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=SRC)
parts = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"], key=lambda o: o.name)
textured = [o.data.materials[0] if o.data.materials else None for o in parts]
flats = []
for i, o in enumerate(parts):
    m = bpy.data.materials.new("flat" + o.name)
    r, g, b = colorsys.hsv_to_rgb((i * 0.618) % 1, 0.75, 0.95)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs[0].default_value = (r, g, b, 1)
    flats.append(m)
    print("PARTCOLOUR %s #%02x%02x%02x" % (o.name, int(r * 255), int(g * 255), int(b * 255)))
sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = 400
try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    sc.render.engine = "BLENDER_EEVEE"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (1, 1, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun); sun.data.energy = 4
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.4
sc.camera = cam
pics = []
# glTF import: Blender z up again, front -y
for name, yaw, flat in (("side", 90, True), ("front", 0, True), ("back34", 145, True), ("tex34", 35, False)):
    for o, f, t in zip(parts, flats, textured):
        o.data.materials.clear(); o.data.materials.append(f if flat else t)
    a = math.radians(yaw)
    d = 5
    cam.location = (d * math.sin(a), -d * math.cos(a), 0.5 + d * math.tan(math.radians(15)))  # aims at z 0.5
    cam.rotation_euler = (math.radians(75), 0, a)
    sun.rotation_euler = (math.radians(50), 0, a + 0.4)
    p = OUT + "." + name + ".png"
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    pics.append(np.array(bpy.data.images.load(p).pixels[:], dtype=np.float32).reshape(400, 400, 4))
both = np.concatenate(pics, axis=1)
out = bpy.data.images.new("parts", 1600, 400)
out.pixels[:] = both.ravel()
out.filepath_raw = OUT; out.file_format = "PNG"; out.save()
print("PARTS saved", OUT)
