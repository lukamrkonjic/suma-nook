#!/usr/bin/env python3
"""Verify that a capture's rendered surfaces land on the palette render targets.

Samples hand-picked flat regions of a GGAssetQualityLab capture and reports
Delta E 2000 against the named targets in the palette JSON. This is the
acceptance test for a palette swap: change the targets, re-solve the source
albedos, capture, and confirm the rendered pixels still land where intended.

Usage:
  python3 tools/verify_palette_render.py docs/visual_rework/comparisons/pnw_full.png \
      [assets/palettes/gg_pnw_mossy_v1.json]
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from compare_reference_render import delta_e2000, srgb_to_lab  # reuse the color math

# region name -> (sample pixel in the 1920x1080 lab capture, palette key, tolerance)
# Sunlit tops of large flat surfaces, sampled away from props and shadows.
REGIONS = {
    "grass top (lit)":      ((770, 330), "grass_primary", 6.0),
    "grass top (lit) b":    ((880, 430), "grass_primary", 6.0),
    "stone paving (lit)":   ((1105, 470), "stone_light", 7.0),
    "soil side wall":       ((700, 620), "earth_mid", 9.0),
    "background":           ((150, 120), "background_cream_01", 3.0),
    "water (shallow)":      ((1180, 700), "water_shallow", 12.0),
    "water (block side)":   ((1130, 800), "water_turquoise", 14.0),
}


def sample(img, xy, radius=6):
    x, y = xy
    patch = img[y - radius:y + radius + 1, x - radius:x + radius + 1]
    return np.median(patch.reshape(-1, 3), axis=0)


def main():
    cap = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/visual_rework/comparisons/pnw_full.png")
    pal_path = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/palettes/gg_pnw_mossy_v1.json")
    img = np.asarray(Image.open(cap).convert("RGB"), dtype=float)
    targets = {k: v.lstrip("#") for k, v in json.loads(pal_path.read_text())["colors"].items()}

    print("capture: %s" % cap)
    print("%-22s %-9s %-9s %6s  %s" % ("region", "measured", "target", "dE00", "status"))
    worst = 0.0
    for name, (xy, key, tol) in REGIONS.items():
        measured = sample(img, xy)
        target = np.array([int(targets[key][i:i + 2], 16) for i in (0, 2, 4)], dtype=float)
        de = float(delta_e2000(srgb_to_lab(measured), srgb_to_lab(target)))
        ok = de <= tol
        worst = max(worst, de - tol)
        print("%-22s #%02X%02X%02X  #%s  %6.1f  %s (tol %.0f)" % (
            name, *(int(round(c)) for c in measured), targets[key], de,
            "PASS" if ok else "FAIL", tol))
    print("\n%s" % ("ALL REGIONS ON TARGET" if worst <= 0 else "OFF TARGET by %.1f dE" % worst))


if __name__ == "__main__":
    main()
