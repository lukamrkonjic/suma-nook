#!/usr/bin/env python3
"""Rebuild a tile recipe on the Dirt Ground / Garden Galaxy discipline.

Garden Galaxy's ground tiles are a base plus one scatter layer -- its grass is
literally Grass__Base + Grass__Particles__particle -- and Dirt Ground, the tile
Luka holds up as the reference, is built the same way at 744 triangles. Every
tile that got rejected on art grounds had the opposite shape: relief on the
base, plus dressing, plus tall rooted clusters, running to three and four
thousand triangles.

So this switches off every decorative layer, turns the clutter layer on, and
gives it Dirt Ground's exact scatter numbers with a light/dark pair chosen to
straddle the tile's own top tone -- the relationship GG uses between its grass
top and its field tones.

Usage:
  python tools/gg_match/apply_gg_discipline.py <tile_id> \
      --light <role> --dark <role> [--shapes clay_chip,leaf_litter] \
      [--base top=role,side=role,lower=role,bevel=role]
"""
import argparse
import re
from pathlib import Path

# Dirt Ground's scatter, verbatim. These numbers are the tile's character.
DIRT_SCATTER = {
    "cluster_fraction": "0.12",
    "cluster_radius": "0.28",
    "corner_fraction": "0.2",
    "count": "[20, 24]",
    "diameter": "[0.12, 0.24]",
    "edge_fraction": "0.35",
    "edge_margin": "0.1",
    "height": "[0.006, 0.014]",
    "min_spacing": "0.13",
    "on_dressing_fraction": "0.0",
    "placement_mode": '"clusters"',
    "scale_multiplier": "1.0",
}
DECORATIVE = ["dressing", "grass_clusters", "rooted_meadow", "forest_floor"]


def disable(text, kind):
    pattern = re.compile(r'(kind = "%s"\n)(?!enabled = false)' % kind)
    return pattern.sub(r'\1enabled = false\n', text)


def rewrite_clutter(text, light, dark, shapes):
    block = re.search(r'kind = "clutter"\n(enabled = false\n)?params = \{.*?\n\}\n',
                      text, re.S)
    if block is None:
        raise SystemExit("recipe has no clutter layer to build on")
    params = "".join('"%s": %s,\n' % (k, v) for k, v in sorted(DIRT_SCATTER.items()))
    new = ('kind = "clutter"\nparams = {\n'
           + params
           + '"color_weights": {\n"%s": 50.0,\n"%s": 50.0\n},\n' % (light, dark)
           + '"shapes": [%s]\n}\n' % ", ".join('"%s"' % s for s in shapes))
    return text.replace(block.group(0), new)


def rewrite_base(text, mapping):
    for slot, role in mapping.items():
        text = re.sub(r'"%s_key":\s*"[a-z_0-9]+"' % slot,
                      '"%s_key": "%s"' % (slot, role), text)
    # A flat base is the point; relief is what made the rejected tiles busy.
    text = re.sub(r'"relief_style":\s*"[a-z_]+"', '"relief_style": "none"', text)
    text = re.sub(r'"relief_amplitude":\s*[0-9.]+', '"relief_amplitude": 0.0', text)
    # A flat top does not need a fine grid. Recipes carrying relief kept
    # resolutions up to 32, which is pure triangle cost once the relief is off;
    # Dirt Ground sits at 12.
    text = re.sub(r'"relief_resolution":\s*[0-9]+', '"relief_resolution": 12', text)
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tile_id")
    ap.add_argument("--light", required=True)
    ap.add_argument("--dark", required=True)
    ap.add_argument("--shapes", default="clay_chip")
    ap.add_argument("--base", default="")
    args = ap.parse_args()

    path = Path("tools/tile_kit/library/recipes/%s.tres" % args.tile_id)
    text = path.read_text(encoding="utf-8")
    for kind in DECORATIVE:
        text = disable(text, kind)
    mapping = dict(p.split("=") for p in args.base.split(",")) if args.base else {}
    text = rewrite_base(text, mapping)
    text = rewrite_clutter(text, args.light, args.dark, args.shapes.split(","))
    path.write_text(text, encoding="utf-8")
    print("%s: base + one scatter (%s / %s)" % (args.tile_id, args.light, args.dark))


if __name__ == "__main__":
    main()
