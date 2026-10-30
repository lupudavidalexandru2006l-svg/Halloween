"""Cut-out pet sprites for the HTML prototype (stand-ins until every pet has 3D).
Usage: python3 make_sprites.py <out_dir> key=concept.png [...]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lineup import cut_out
from PIL import Image
out = sys.argv[1]
for spec in sys.argv[2:]:
    key, path = spec.split("=", 1)
    im = cut_out(path)
    s = 320 / max(im.size)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    canvas = Image.new("RGBA", (320, 320), (0, 0, 0, 0))
    canvas.paste(im, ((320 - im.width) // 2, 320 - im.height), im)  # feet on the bottom edge
    canvas.save(f"{out}/{key}.webp", quality=88, method=6)
    print(key, im.size)
