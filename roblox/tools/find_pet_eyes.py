# find_pet_eyes.py: find a pet's two painted eyes for PetEyes.luau.
#   blender -b --factory-startup --python find_pet_eyes.py -- <pet.glb> <render.png> [aspect=1.6] [dark=0.2] [px=x,y,r;x,y,r]
# aspect: allow taller eye blobs (Glowfin 2.4); px: give the eye pixels by hand when they touch dark fur (Beacon Orca)
# Renders the pet straight from the front (orthographic, flat texture colours), takes the two biggest
# round near-black blobs, ray casts each onto the mesh and prints them in Roblox model space
# (Roblox x = -Blender x, y = Blender z, z = Blender y, from the bounding-box centre; 1 = pet height).
import bpy, sys, math
import numpy as np
from mathutils import Vector

GLB, OUT = sys.argv[sys.argv.index("--") + 1:][:2]
OPTS = dict(a.split("=", 1) for a in sys.argv[sys.argv.index("--") + 3:])
DARK = float(OPTS.get("dark", 0.2)); ASPECT = float(OPTS.get("aspect", 1.6))
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=GLB)
o = [x for x in bpy.context.scene.objects if x.type == "MESH"][0]
vs = [o.matrix_world @ v.co for v in o.data.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
c = (lo + hi) / 2
H = hi.z - lo.z

sc = bpy.context.scene
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"
SPAN = max(hi.x - lo.x, H) * 1.1
cam_data.ortho_scale = SPAN
cam = bpy.data.objects.new("cam", cam_data); sc.collection.objects.link(cam)
cam.location = (c.x, lo.y - 5, c.z); cam.rotation_euler = (math.pi / 2, 0, 0)
sc.camera = cam
N = 600
sc.render.resolution_x = sc.render.resolution_y = N
try:
    sc.render.engine = "BLENDER_WORKBENCH"
except TypeError:
    pass
sh = sc.display.shading
sh.light = "FLAT"; sh.color_type = "TEXTURE"
sc.view_settings.view_transform = "Standard"
sc.render.film_transparent = True
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
img = bpy.data.images.load(OUT)
px = np.array(img.pixels[:], dtype=np.float32).reshape(N, N, 4)[::-1]  # row 0 = top
rgb, alpha = px[..., :3], px[..., 3]
dark = (rgb.max(axis=2) < DARK) & (alpha > 0.5)

# connected blobs of dark pixels
lab = np.zeros((N, N), dtype=np.int32); blobs = []
for sy, sx in zip(*np.nonzero(dark)):
    if lab[sy, sx]: continue
    n = len(blobs) + 1; lab[sy, sx] = n; stack = [(sy, sx)]; pts = []
    while stack:
        y, x = stack.pop(); pts.append((y, x))
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= yy < N and 0 <= xx < N and dark[yy, xx] and not lab[yy, xx]:
                lab[yy, xx] = n; stack.append((yy, xx))
    a = np.array(pts)
    h, w = np.ptp(a[:, 0]) + 1, np.ptp(a[:, 1]) + 1
    blobs.append(dict(n=n, area=len(pts), cy=a[:, 0].mean(), cx=a[:, 1].mean(), h=h, w=w))
cands = [b for b in blobs if 40 < b["area"] < 0.02 * N * N and b["h"] < ASPECT * b["w"] and b["w"] < 1.8 * b["h"]
         and b["area"] > 0.45 * b["h"] * b["w"]]
cands.sort(key=lambda b: -b["area"])
eyes = sorted(cands[:2], key=lambda b: b["cx"])
if "px" in OPTS:  # eyes given by hand: x,y,r;x,y,r in render pixels
    eyes = [dict(cx=float(a), cy=float(b_), area=math.pi * float(r) ** 2) for a, b_, r in (e.split(",") for e in OPTS["px"].split(";"))]
print("RESULT blobs", [(round(b["cx"]), round(b["cy"]), b["area"]) for b in cands[:5]])

dg = bpy.context.evaluated_depsgraph_get()
pix = SPAN / N
for b in eyes:
    wx = c.x + (b["cx"] + 0.5 - N / 2) * pix
    wz = c.z - (b["cy"] + 0.5 - N / 2) * pix
    hit, loc, nrm, *_ = sc.ray_cast(dg, Vector((wx, lo.y - 5, wz)), Vector((0, 1, 0)))
    r = math.sqrt(b["area"] / math.pi) * pix * 1.1
    # lid colour: the ring just outside the eye
    yy, xx = np.ogrid[:N, :N]
    d = np.sqrt((yy - b["cy"]) ** 2 + (xx - b["cx"]) ** 2)
    rp = math.sqrt(b["area"] / math.pi)
    ring = (d > rp * 1.5) & (d < rp * 2.3) & (alpha > 0.5) & ~dark
    col = np.median(rgb[ring], axis=0) if ring.any() else np.array([0.5, 0.5, 0.5])
    col = (col * 0.9 * 255).astype(int)  # a little deeper than the texture shows
    rel = (loc - c) / H
    print("RESULT eye(%.4f, %.4f, %.4f, %.3f, %.3f, %.3f, %.4f) lid %s hit %s" % (
        -rel.x, rel.z, rel.y, -nrm.x, nrm.z, nrm.y, r / H, tuple(col), hit))
