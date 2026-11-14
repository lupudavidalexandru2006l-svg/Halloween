# grid_views.py: side and front pictures of a prepped pet with a 0.1-height grid, to read off where to cut its parts
# for split_pet.py.
#   blender -b --factory-startup --python grid_views.py -- <key>.glb <out.png>
# Coordinates are in pet heights: z from 0 (feet) to 1 (top); x and y from the pet's centre, front = -y.
# Left picture: side view (front to the left, so -y runs left). Right picture: front view, +x to the right, which
# is the pet's own left (Roblox -X after export). Each picture spans -0.6..0.6 across and -0.1..1.1 up; lines
# every 0.1, thick every 0.5, red at 0.
import bpy, sys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=SRC)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
H = hi.z - lo.z
cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
print("GRID bbox in heights x %.2f..%.2f y %.2f..%.2f" % ((lo.x - cx) / H, (hi.x - cx) / H, (lo.y - cy) / H, (hi.y - cy) / H))

sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = 600
sc.render.film_transparent = False
try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    sc.render.engine = "BLENDER_EEVEE"
world = bpy.data.worlds.new("w"); sc.world = world
world.color = (1, 1, 1)
light = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(light)
light.data.energy = 4
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.2 * H
sc.camera = cam
SPAN = 1.2  # picture width in heights
pics = []
for view in ("side", "front"):
    if view == "side":  # camera on +x looking -x: -y (front) shows on the left
        cam.location = (cx + 5 * H, cy, lo.z + H / 2); cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    else:  # camera in front (-y) looking +y: +x shows on the right
        cam.location = (cx, cy - 5 * H, lo.z + H / 2); cam.rotation_euler = (math.pi / 2, 0, 0)
    light.rotation_euler = cam.rotation_euler
    path = OUT + "." + view + ".png"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(600, 600, 4)  # row 0 = bottom
    for k in range(-6, 7):
        t = k / 10
        col = (1, 0, 0) if k == 0 else (0.1, 0.4, 1)
        w = 2 if k % 5 == 0 else 1
        p = int(round((t / SPAN + 0.5) * 600))
        if 0 <= p < 600:
            px[:, p:p + w, :3] = col  # vertical lines: horizontal coordinate t
    for k in range(-1, 12):
        z = k / 10  # height above the feet
        p = int(round(((z - 0.5) / SPAN + 0.5) * 600))
        if 0 <= p < 600:
            px[p:p + (2 if k % 5 == 0 else 1), :, :3] = (1, 0, 0) if k == 0 else (0.1, 0.4, 1)
    pics.append(px)
both = np.concatenate(pics, axis=1)
out = bpy.data.images.new("grid", 1200, 600)
out.pixels[:] = both.ravel()
out.filepath_raw = OUT; out.file_format = "PNG"; out.save()
print("GRID saved", OUT)
