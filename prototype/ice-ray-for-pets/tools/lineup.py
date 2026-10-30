"""Make a zone line-up sheet from pet concept PNGs (Pet Art Recipe step 6).

Row 1: the concepts, Common -> Secret, scaled by size class (S/M/L).
Row 2: inside a light-blue ice cube tint (does the main colour still read?).
Row 3: black silhouettes at 48 px, drawn 2x so they are visible (silhouette test).

Usage: python3 lineup.py <out.png> <title> name:tier:size:file [...]
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

TILE = 300
BG = (220, 235, 245)  # line-up background (zone colours are not in Theme yet)
INK = (27, 20, 51)  # UI Rules ink #1b1433
TIER_COLOURS = {
    "Common": (150, 160, 170),
    "Uncommon": (80, 190, 90),
    "Rare": (60, 140, 235),
    "Epic": (170, 80, 230),
    "Legendary": (250, 175, 30),
    "Mythic": (240, 70, 120),
    "Secret": (30, 30, 30),
}
SIZE_SCALE = {"S": 0.78, "M": 0.9, "L": 1.0}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def cut_out(path: str) -> Image.Image:
    """Remove the white background by flood fill from the border (not a global threshold)."""
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(np.int16)
    whiteness = a[..., :3].min(axis=2)
    near_white = whiteness > 247
    labels, _ = ndimage.label(near_white)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    border.discard(0)
    bg = np.isin(labels, list(border))
    # soften the edge: pixels next to the background fade by how white they are
    edge = ndimage.binary_dilation(bg, iterations=2) & ~bg
    alpha = np.where(bg, 0, 255).astype(np.float32)
    alpha[edge] = np.clip((255 - whiteness[edge]) * 255.0 / 25.0, 0, 255)
    out = a.astype(np.uint8).copy()
    out[..., 3] = alpha.astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    return im.crop(im.getbbox())


def fit(im: Image.Image, box: int) -> Image.Image:
    s = box / max(im.size)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def main() -> None:
    out_path, title, *specs = sys.argv[1:]
    pets = [s.split(":", 3) for s in specs]
    n = len(pets)
    head, label_h, row_cube, row_sil = 70, 64, TILE, 130
    W, H = n * TILE, head + TILE + label_h + row_cube + row_sil
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    f_title, f_name, f_small = ImageFont.truetype(FONT, 34), ImageFont.truetype(FONT, 22), ImageFont.truetype(FONT, 16)
    d.text((20, 16), title, font=f_title, fill=INK)
    for i, (name, tier, size, path) in enumerate(pets):
        x0 = i * TILE
        pet = cut_out(path)
        # row 1: concept, scaled by size class, standing on a shared floor line
        p = fit(pet, int((TILE - 30) * SIZE_SCALE[size]))
        y_floor = head + TILE - 10
        sheet.paste(p, (x0 + (TILE - p.width) // 2, y_floor - p.height), p)
        # labels
        ty = head + TILE
        d.text((x0 + TILE // 2, ty + 4), name, font=f_name, fill=INK, anchor="ma")
        col = TIER_COLOURS[tier]
        tw = d.textlength(f"{tier}  ·  {size}", font=f_small) + 24
        d.rounded_rectangle((x0 + (TILE - tw) / 2, ty + 32, x0 + (TILE + tw) / 2, ty + 56), 10, fill=col)
        d.text((x0 + TILE // 2, ty + 44), f"{tier}  ·  {size}", font=f_small, fill="white", anchor="mm")
        # row 2: inside a light-blue ice cube
        cy = head + TILE + label_h
        cube = Image.new("RGBA", (TILE - 40, TILE - 40), (0, 0, 0, 0))
        q = fit(pet, TILE - 80)
        cube.paste(q, ((cube.width - q.width) // 2, (cube.height - q.height) // 2), q)
        tint = Image.new("RGBA", cube.size, (170, 220, 250, 120))
        cube = Image.alpha_composite(Image.new("RGBA", cube.size, (200, 235, 255, 255)), cube)
        cube = Image.alpha_composite(cube, tint)
        sheet.paste(cube.convert("RGB"), (x0 + 20, cy + 20))
        d.rounded_rectangle((x0 + 20, cy + 20, x0 + TILE - 20, cy + TILE - 20), 14, outline=(120, 190, 235), width=6)
        # row 3: 48 px silhouette, shown at 2x
        sy = cy + row_cube
        sil = fit(pet, 48).split()[3].point(lambda v: 255 if v > 100 else 0)
        black = Image.new("RGB", sil.size, (0, 0, 0))
        sil2 = sil.resize((sil.width * 2, sil.height * 2), Image.NEAREST)
        black2 = black.resize(sil2.size)
        sheet.paste(black2, (x0 + (TILE - sil2.width) // 2, sy + 10 + (96 - sil2.height)), sil2)
    d.text((W - 20, H - 10), "row 2: in an ice-cube tint · row 3: 48 px silhouette, shown 2x", font=f_small, fill=(90, 100, 120), anchor="rd")
    sheet.save(out_path)
    print(out_path, sheet.size)


if __name__ == "__main__":
    main()
