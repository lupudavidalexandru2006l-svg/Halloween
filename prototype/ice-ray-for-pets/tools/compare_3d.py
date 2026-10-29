"""Concept vs 3D sheet (Pet Rules 5: judge every 3D model side by side with its concept).

Panels: concept | 3D (Roblox-ready mesh) 3/4 front | 3D back 3/4, with triangle counts.
Usage: python3 compare_3d.py <out.png> <name> <concept.png> <roblox.glb> [<raw.glb>]
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
NODE = os.path.join(HERE, "node")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
INK = (27, 20, 51)
P = 640


def render(glb: str, yaw: int, out: str) -> Image.Image:
    subprocess.run(["node", "render.mjs", out, os.path.abspath(glb), str(yaw), str(P)], cwd=NODE, check=True, capture_output=True)
    return Image.open(out).convert("RGB")


def tris(glb: str) -> int:
    r = subprocess.run(["node", "inspect.mjs", os.path.abspath(glb)], cwd=NODE, check=True, capture_output=True, text=True)
    return int(r.stdout.split("tris:")[1].split(",")[0])


def main() -> None:
    out, name, concept, roblox = sys.argv[1:5]
    raw = sys.argv[5] if len(sys.argv) > 5 else None
    tmp = tempfile.mkdtemp()
    front = render(roblox, -35, f"{tmp}/f.png")
    back = render(roblox, 145, f"{tmp}/b.png")
    c = Image.open(concept).convert("RGBA")
    bg = Image.new("RGBA", c.size, "white")
    c = Image.alpha_composite(bg, c).convert("RGB").resize((P, P))
    head = 60
    sheet = Image.new("RGB", (P * 3, P + head), "white")
    for i, im in enumerate([c, front, back]):
        sheet.paste(im, (i * P, head))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT, 26)
    t = tris(roblox)
    raw_t = f" (from {tris(raw):,})" if raw else ""
    labels = ["concept", f"3D, {t:,} triangles{raw_t}", "3D, back"]
    for i, lab in enumerate(labels):
        d.text((i * P + P // 2, 16), f"{name}: {lab}" if i == 0 else lab, font=f, fill=INK, anchor="ma")
    for i in (1, 2):
        d.line((i * P, head, i * P, P + head), fill=(220, 225, 235), width=3)
    sheet.save(out)
    print(json.dumps({"out": out, "tris": t}))


if __name__ == "__main__":
    main()
