#!/usr/bin/env python3
"""Move palette tokens toward their Garden Galaxy screen targets.

The renderer's albedo -> screen transfer runs through lighting and the PPv2
grade's Neutral tonemap, which compresses hard; there is no closed form worth
trusting. So this corrects in linear light from what was actually measured --
new = old * (target_linear / measured_linear) -- and is meant to be run in a
loop with a fresh capture each round. The tonemap makes the first step
overshoot toward dark; two or three rounds settle it.

Usage: python tools/gg_match/correct_palette.py measured.json [--damp 0.85]
"""
import json
import re
import sys
from pathlib import Path

import numpy as np

PALETTE = Path("assets/palettes/gg_material_palette.tres")

# measured face -> palette token it is driven by
DRIVEN_BY = {
    "top": "tilekit_grass_gg_top",
    "side": "tilekit_grass_gg_side",
    "fleck light": "grass_field_surface_light",
    "fleck deep": "tilekit_grass_gg_tuft",
}
# tokens with no directly visible face; they follow the mean correction so the
# family keeps its internal relationships
FOLLOWERS = ["tilekit_grass_gg_lower"]


def s2l(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hex_srgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], float)


def read_tokens(text, names):
    out = {}
    for name in names:
        m = re.search(r'"%s":\s*Color\(([^)]*)\)' % re.escape(name), text)
        if m:
            out[name] = np.array([float(x) for x in m.group(1).split(",")[:3]])
    return out


def write_token(text, name, rgb):
    return re.sub(
        r'("%s":\s*Color\()[^)]*(\))' % re.escape(name),
        lambda m: "%s%.4f, %.4f, %.4f, 1.0%s" % (m.group(1), *rgb, m.group(2)),
        text,
        count=1,
    )


def main():
    measured = json.loads(Path(sys.argv[1]).read_text())
    damp = 0.85
    if "--damp" in sys.argv:
        damp = float(sys.argv[sys.argv.index("--damp") + 1])
    text = PALETTE.read_text(encoding="utf-8")
    names = list(DRIVEN_BY.values()) + FOLLOWERS
    tokens = read_tokens(text, names)
    ratios = []
    for face, token in DRIVEN_BY.items():
        if face not in measured or token not in tokens:
            continue
        got = s2l(hex_srgb(measured[face]["ours"]))
        want = s2l(hex_srgb(measured[face]["gg"]))
        ratio = np.clip(want / np.maximum(got, 1e-4), 0.25, 4.0)
        ratio = 1.0 + (ratio - 1.0) * damp
        ratios.append(ratio)
        new = np.clip(tokens[token] * ratio, 0.0, 1.0)
        print("  %-30s %s -> %s   (x%.2f, %.2f, %.2f)" % (
            token,
            np.round(tokens[token], 3), np.round(new, 3), *ratio))
        text = write_token(text, token, new)
    if ratios:
        mean = np.mean(ratios, axis=0)
        for token in FOLLOWERS:
            if token not in tokens:
                continue
            new = np.clip(tokens[token] * mean, 0.0, 1.0)
            print("  %-30s %s -> %s   (mean)" % (
                token, np.round(tokens[token], 3), np.round(new, 3)))
            text = write_token(text, token, new)
    PALETTE.write_text(text, encoding="utf-8")
    print("palette updated")


if __name__ == "__main__":
    main()
