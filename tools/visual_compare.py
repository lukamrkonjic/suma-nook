#!/usr/bin/env python3
"""Visual comparison sheets for the GG rework.

Produces per-pass artifacts in docs/visual_rework/comparisons/:
  - side-by-side montage of the given images
  - grayscale silhouette strip (shape/readability without color)
  - saturation heatmaps (detects lime/fluorescent drift)
  - edge-density maps (detects razor-edge/noisy-clutter regressions)
  - palette sheet: render targets vs solved source albedos

Usage:
  python3 tools/visual_compare.py --label final \
      --images docs/visual_rework/regressed.png docs/visual_rework/comparisons/gameplay_final.png \
      --names "regressed" "reworked"
"""

import argparse
import colorsys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path("docs/visual_rework/comparisons")


def load(path, height=420):
    im = Image.open(path).convert("RGB")
    return im.resize((int(im.width * height / im.height), height), Image.LANCZOS)


def montage(images, names, out, height=420):
    total_w = sum(im.width for im in images) + 8 * (len(images) - 1)
    canvas = Image.new("RGB", (total_w, height + 26), (32, 30, 28))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    x = 0
    for im, name in zip(images, names):
        canvas.paste(im, (x, 26))
        draw.text((x + 6, 7), name, fill=(235, 230, 218), font=font)
        x += im.width + 8
    canvas.save(out)


def saturation_map(im):
    arr = np.asarray(im, dtype=float) / 255.0
    mx = arr.max(axis=-1)
    mn = arr.min(axis=-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    heat = np.zeros((*sat.shape, 3), dtype=np.uint8)
    heat[..., 0] = (np.clip(sat * 1.6, 0, 1) * 255).astype(np.uint8)
    heat[..., 1] = (np.clip(1.2 - abs(sat - 0.45) * 2.6, 0, 1) * 200).astype(np.uint8)
    heat[..., 2] = ((1 - np.clip(sat * 1.6, 0, 1)) * 220).astype(np.uint8)
    return Image.fromarray(heat)


def edge_density(im):
    g = np.asarray(im.convert("L"), dtype=float)
    gx = np.abs(np.diff(g, axis=1, prepend=g[:, :1]))
    gy = np.abs(np.diff(g, axis=0, prepend=g[:1]))
    mag = np.clip((gx + gy) * 2.2, 0, 255).astype(np.uint8)
    return Image.fromarray(255 - mag)


def palette_sheet(out):
    import re
    text = Path("assets/palettes/gg_material_palette.tres").read_text()

    def block(name):
        m = re.search(name + r" = \{(.*?)\n\}", text, re.S)
        pairs = re.findall(r'"([a-z0-9_]+)": Color\(([0-9.]+), ([0-9.]+), ([0-9.]+)', m.group(1))
        return {k: tuple(int(float(v) * 255) for v in rgb) for k, *rgb in [(p[0], p[1], p[2], p[3]) for p in pairs]}

    colors = block("colors")
    targets = block("render_targets")
    rows = [k for k in targets if k in colors]
    row_h, sw = 22, 120
    img = Image.new("RGB", (480, row_h * (len(rows) + 1) + 16), (245, 243, 236))
    draw = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    draw.text((8, 4), "name / render target / source albedo", fill=(60, 55, 45), font=font)
    for i, key in enumerate(rows):
        y = 16 + row_h * (i + 1) - row_h + 8
        draw.text((8, y + 5), key[:24], fill=(40, 38, 32), font=font)
        draw.rectangle([215, y + 1, 215 + sw, y + row_h - 3], fill=targets[key])
        draw.rectangle([220 + sw, y + 1, 220 + 2 * sw, y + row_h - 3], fill=colors[key])
    img.save(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="compare")
    parser.add_argument("--images", nargs="+", required=True)
    parser.add_argument("--names", nargs="+", required=True)
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    images, names = [], []
    for path, name in zip(args.images, args.names):
        if Path(path).exists():
            images.append(load(path))
            names.append(name)
        else:
            ph = Image.new("RGB", (740, 420), (60, 57, 52))
            ImageDraw.Draw(ph).text((20, 200), "missing:\n" + path, fill=(220, 215, 205))
            images.append(ph)
            names.append(name + " (missing)")

    montage(images, names, OUT_DIR / f"{args.label}_side_by_side.png")
    montage([im.convert("L").convert("RGB") for im in images], names, OUT_DIR / f"{args.label}_silhouette.png")
    montage([saturation_map(im) for im in images], names, OUT_DIR / f"{args.label}_saturation.png")
    montage([edge_density(im) for im in images], names, OUT_DIR / f"{args.label}_edges.png")
    palette_sheet(OUT_DIR / "palette_sheet.png")
    print("comparison sheets written to", OUT_DIR)


if __name__ == "__main__":
    main()
