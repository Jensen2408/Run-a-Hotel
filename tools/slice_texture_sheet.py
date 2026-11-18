"""
Slice the generated motel texture sheet (4 x 4 grid) into separate PNGs.

  python tools/slice_texture_sheet.py

Input : assets/textures/motel_sheets.png
Output: assets/textures/<name>.png (rows 1-2, seamless tiles, 512 x 512)
        assets/decals/<name>.png   (rows 3-4, trimmed to their alpha bounds)

Cells are found from the alpha mask (row / column gaps), not fixed pixel
positions, because the generator does not keep an exact grid. Tiles are
cropped a few pixels inside their edge (the generator leaves a yellow
fringe) and the organic ones get an offset cross-fade so they repeat
without visible seams.
"""

import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "textures", "motel_sheets.png")
TEX = os.path.join(ROOT, "assets", "textures")
DEC = os.path.join(ROOT, "assets", "decals")
os.makedirs(DEC, exist_ok=True)

NAMES = [
    ["asphalt", "concrete", "grass", "wood_floor"],
    ["carpet", "checker_tiles", "pool_water", "gravel"],
    ["welcome_mat", "poster_pine_lake", "motel_logo", "menu_board"],
    ["poster_supplies", "pool_rules", "no_smoking", "manhole"],
]
SEAMLESS = {"asphalt", "grass", "pool_water", "gravel"}  # organic: cross-fade the wrap


def bands(profile, min_len=40):
    """Runs of True in a 1-D boolean profile -> [(start, end)]."""
    out, start = [], None
    for i, v in enumerate(profile):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= min_len:
                out.append((start, i))
            start = None
    if start is not None and len(profile) - start >= min_len:
        out.append((start, len(profile)))
    return out


def make_seamless(img):
    """Blend the tile with itself rolled by half: wrap-continuous edges."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    rolled = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    y = np.minimum(np.arange(h), np.arange(h)[::-1]) / (h / 2)
    x = np.minimum(np.arange(w), np.arange(w)[::-1]) / (w / 2)
    m = np.clip(np.minimum.outer(y, x) * 2.2, 0, 1)[..., None]  # 1 in the middle, 0 at the edges
    out = a * m + rolled * (1 - m)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), img.mode)


sheet = Image.open(SRC).convert("RGBA")
alpha = np.asarray(sheet)[:, :, 3] > 40
rows = bands(alpha.any(axis=1))
assert len(rows) == 4, f"expected 4 rows, found {len(rows)}: {rows}"
for r, (y0, y1) in enumerate(rows):
    cols = bands(alpha[y0:y1].any(axis=0))
    assert len(cols) == 4, f"row {r}: expected 4 cells, found {len(cols)}: {cols}"
    for c, (x0, x1) in enumerate(cols):
        name = NAMES[r][c]
        cell = sheet.crop((x0, y0, x1, y1))
        if r < 2:  # tiles
            inset = 10
            cell = cell.crop((inset, inset, cell.width - inset, cell.height - inset)).convert("RGB")
            cell = cell.resize((512, 512), Image.LANCZOS)
            if name in SEAMLESS:
                cell = make_seamless(cell)
            cell.save(os.path.join(TEX, f"{name}.png"))
        else:  # decals: trim to the alpha bounds with a small margin
            bbox = cell.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
            cell = cell.crop((max(0, bbox[0] - 4), max(0, bbox[1] - 4), min(cell.width, bbox[2] + 4), min(cell.height, bbox[3] + 4)))
            cell.save(os.path.join(DEC, f"{name}.png"))
        print(f"{name:18s} {cell.size}")
