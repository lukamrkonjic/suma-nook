#!/usr/bin/env python3
"""Measure a rendered tile against the Garden Galaxy screen targets.

Faces are separated geometrically, not by luminance: the island is one slab
seen isometrically, so its top face is everything above the lower silhouette
edges and its side faces are the bottom band. Luminance banding cannot do
this -- the scatter on the top face overlaps the side face in brightness.

Usage: python tools/gg_match/measure_tile.py [capture.png]
"""
import sys, colorsys
from collections import Counter
import numpy as np
from PIL import Image

GG_TARGETS = {
    "top":         "#586C49",
    "side":        "#465C42",
    "fleck light": "#687A56",
    "fleck deep":  "#43563A",
}


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def to_hex(c):
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)


def hsv(c):
    h, s, v = colorsys.rgb_to_hsv(*(np.asarray(c, float) / 255))
    return h * 360, s, v


def segment(path):
    a = np.asarray(Image.open(path).convert("RGB"), float)
    h, w, _ = a.shape
    flat = a.reshape(-1, 3).astype(int)
    backdrop = np.array(Counter(map(tuple, flat)).most_common(1)[0][0], float)
    dist = np.linalg.norm(a - backdrop, axis=2)
    # Ignore the HUD, which lives in the bottom-right corner.
    mask = dist > 30
    mask[int(h * 0.78):, int(w * 0.72):] = False
    ys, xs = np.nonzero(mask)
    y0, y1 = ys.min(), ys.max()
    # The slab's vertical faces are the band beneath the diamond's side
    # vertices; that silhouette bottom sits ~78% down the island's extent.
    cut = y0 + int((y1 - y0) * 0.80)
    top = a[mask & (np.arange(h)[:, None] < cut)]
    side = a[mask & (np.arange(h)[:, None] >= cut)]
    return backdrop, top, side


def dominant(px, tol=16):
    """Base tone of a face: the tight cluster around its median."""
    med = np.median(px, axis=0)
    keep = px[np.linalg.norm(px - med, axis=1) < tol]
    return np.median(keep, axis=0), len(keep) / len(px)


def scatter_tones(px, base, tol=16):
    """The two scatter tones: brightest and darkest off-base clusters.

    Restricted to green pixels. The well stands on the tile, inside the top
    face, and its lit tan shell is both off-base and the brightest thing
    there -- without this filter the "light scatter" reading is the well.
    """
    px = px[(px[:, 1] >= px[:, 0]) & (px[:, 1] > px[:, 2] + 10)]
    off = px[np.linalg.norm(px - base, axis=1) >= tol]
    if len(off) < 200:
        return None, None
    luma = off @ np.array([0.2126, 0.7152, 0.0722])
    order = np.argsort(luma)
    o = off[order]
    return np.median(o[-len(o) // 5:], axis=0), np.median(o[:len(o) // 5], axis=0)


def report(path):
    backdrop, top, side = segment(path)
    base, share = dominant(top)
    light, deep = scatter_tones(top, base)
    side_base, _ = dominant(side)
    rows = [("top", base), ("side", side_base)]
    if light is not None:
        rows += [("fleck light", light), ("fleck deep", deep)]
    print(f"backdrop {to_hex(backdrop)}   top pixels {len(top)}  side pixels {len(side)}")
    print(f"base covers {share * 100:.0f}% of the top face")
    print()
    print(f"  {'':13} {'ours':9} {'GG':9}   delta")
    for label, c in rows:
        tgt = hex_rgb(GG_TARGETS[label])
        oh, os_, ov = hsv(c)
        th, ts, tv = hsv(tgt)
        dh = (oh - th + 180) % 360 - 180
        print(f"  {label:13} {to_hex(c)}   {GG_TARGETS[label]}   "
              f"hue {dh:+6.1f}  sat {os_ - ts:+.2f}  val {ov - tv:+.2f}")
    return {k: v for k, v in rows}


if __name__ == "__main__":
    report(sys.argv[1] if len(sys.argv) > 1 else "artifacts/gg_match/world.png")
