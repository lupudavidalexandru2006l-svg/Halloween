"""Paint loose floating bits (snowflakes, light motes, sparkles) out of a concept
so image-to-3D sees one solid pet. Keeps the main body and anything big attached
to it; turns small separate specks white. The original concept is never changed.

Usage: python3 clean_3d_input.py <concept.png> <out.png> [min_share=0.02]
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    min_share = float(sys.argv[3]) if len(sys.argv) > 3 else 0.02
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.int16)
    # "not background": anything noticeably away from white
    ink = a.min(axis=2) < 238
    ink = ndimage.binary_closing(ink, iterations=2)
    labels, n = ndimage.label(ink)
    sizes = ndimage.sum(ink, labels, range(1, n + 1))
    biggest = sizes.max()
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= biggest * min_share
    mask = keep[labels]
    mask = ndimage.binary_dilation(mask, iterations=3)
    clean = np.where(mask[..., None], a, 255).astype(np.uint8)
    Image.fromarray(clean).save(out)
    print(f"{out}: kept {int(keep.sum())} of {n} parts, removed {n - int(keep.sum())}")


if __name__ == "__main__":
    main()
