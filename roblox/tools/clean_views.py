# clean_views.py: tidy the view images cut by split_turnaround.ps1 for TRELLIS's multi-image mode.
#   blender -b --factory-startup --python clean_views.py -- <view.png> [<view.png> ...]
# Keeps only the pet: every connected piece of non-white pixels that is big (over 3 % of the drawing) and doesn't
# sit at the left or right edge (a sliver of the next view on the sheet; small pieces centred in the outer 20 %). Tiny floating bits (motes, sparkles) and
# edge slivers are painted white. Overwrites each file.
import bpy, sys
import numpy as np

files = sys.argv[sys.argv.index("--") + 1:]
for path in files:
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ink = px[..., :3].min(axis=2) < 0.9
    # label connected pieces at half size (union-find over a 4-neighbour grid)
    s = ink[::2, ::2]
    hh, ww = s.shape
    parent = np.arange(hh * ww)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    idx = np.arange(hh * ww).reshape(hh, ww)
    for a, b in ((idx[:, :-1][s[:, :-1] & s[:, 1:]], idx[:, 1:][s[:, :-1] & s[:, 1:]]),
                 (idx[:-1, :][s[:-1, :] & s[1:, :]], idx[1:, :][s[:-1, :] & s[1:, :]])):
        for i, j in zip(a.tolist(), b.tolist()):
            ri, rj = find(i), find(j)
            if ri != rj:
                parent[max(ri, rj)] = min(ri, rj)
    roots = np.array([find(i) for i in range(hh * ww)]).reshape(hh, ww)
    roots[~s] = -1
    keep = np.zeros_like(s)
    total = s.sum()
    labels, counts = np.unique(roots[s], return_counts=True)
    for lab, n in zip(labels, counts):
        m = roots == lab
        cols = np.nonzero(m.any(axis=0))[0]
        mid = (cols[0] + cols[-1]) / 2
        edge = cols[0] <= 1 or cols[-1] >= ww - 2 or mid < 0.2 * ww or mid > 0.8 * ww
        if n > 0.03 * total and (n > 0.3 * total or not edge):
            keep |= m
    # back to full size, grown by 2 px so soft edges stay
    full = np.repeat(np.repeat(keep, 2, axis=0), 2, axis=1)[:h, :w]
    for _ in range(2):
        g = full.copy()
        g[1:, :] |= full[:-1, :]; g[:-1, :] |= full[1:, :]; g[:, 1:] |= full[:, :-1]; g[:, :-1] |= full[:, 1:]
        full = g
    px[~full, :3] = 1.0
    img.pixels[:] = px.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    print("CLEAN", path.split("/")[-1], "kept", int(keep.sum()), "of", int(total))
