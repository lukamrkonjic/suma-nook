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
      --archetype particles|bits|cushion|patches \
      --light <role> --dark <role> [--shapes clay_chip,leaf_litter] \
      [--base top=role,side=role,lower=role,bevel=role]
"""
import argparse
import re
from pathlib import Path

# Garden Galaxy separates its ground tiles by STRUCTURE, not just colour. Its
# own mesh names give the vocabulary:
#
#   Base + Particles   grass, moss, chip_floor     loose scatter
#   Base + Bits        soil_ground, stone_ground   fewer, larger, embedded
#   Base only          sand_02, sand_ground        nothing at all
#   Base + Blocks      cobblestone, stone_paving   modular units
#   Base + Top         snow                        a separate cap layer
#
# Building every tile as Particles is what makes a library read as one tile in
# several colours. Pick the archetype that suits the material and the tiles
# separate on silhouette before colour is even considered.
ARCHETYPES = {
    # Dirt Ground's numbers, verbatim: many small flat flecks.
    "particles": {
        "count": "[20, 24]", "diameter": "[0.12, 0.24]",
        "height": "[0.006, 0.014]", "min_spacing": "0.13",
        "cluster_fraction": "0.12", "cluster_radius": "0.28",
        "edge_fraction": "0.35", "corner_fraction": "0.2",
    },
    # Garden Galaxy's own ground scatter, measured from its shipped meshes:
    # "Soil Bits square" is 80 single-triangle pieces, each ~0.15 wide and
    # ~0.09 tall, and that is the entire scatter layer of a soil tile. Many
    # tiny shards rather than few sculpted chunks is what reads as minimal.
    "gg": {
        "count": "[62, 78]", "diameter": "[0.11, 0.19]",
        "height": "[0.055, 0.105]", "min_spacing": "0.055",
        "cluster_fraction": "0.45", "cluster_radius": "0.30",
        "edge_fraction": "0.22", "corner_fraction": "0.12",
    },
    # Sparser, chunkier, sitting in the surface rather than on it.
    "bits": {
        "count": "[5, 7]", "diameter": "[0.22, 0.36]",
        "height": "[0.016, 0.032]", "min_spacing": "0.24",
        "cluster_fraction": "0.35", "cluster_radius": "0.34",
        "edge_fraction": "0.2", "corner_fraction": "0.1",
    },
    # Moss reads as a carpet of overlapping pads rather than loose flecks:
    # wider, several times taller, packed tighter. Measured shape costs force
    # this to stay on clay_chip -- the rounded primitives (nub, dot, oval,
    # bud) cost ~300 triangles each against clay_chip's ~10, which caps a
    # rounded scatter at four or five pieces, far too sparse for a carpet.
    "cushion": {
        "count": "[16, 20]", "diameter": "[0.16, 0.28]",
        "height": "[0.020, 0.040]", "min_spacing": "0.17",
        "cluster_fraction": "0.55", "cluster_radius": "0.30",
        "edge_fraction": "0.25", "corner_fraction": "0.15",
    },
}

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
DECORATIVE = ["dressing", "grass_clusters", "rooted_meadow", "forest_floor",
              "pavers"]

# The one archetype that is not a scatter. The dressing builder grows merged,
# overlapping blobs rather than discrete pieces, which is what separates a moss
# carpet from "dirt with a green top": the surface is made of soft joined
# mounds instead of countable flecks.
PATCHES = {
    "allow_overlap": "true",
    "edge_softness": "0.75",
    # Real moss clings to the surface -- it is a flat irregular skin with a
    # soft edge, not a field of standing domes. Tall mounds that all touch
    # read as bubbles or as a lumpy custard; keeping the profile low and the
    # patches apart leaves clean ground between them, which is what makes the
    # growth look like growth.
    "height_scale": "0.42",
    # A cushion patch is a dome, roughly 200 triangles each, so the patch
    # count is what the triangle budget actually buys here.
    "large_count": "[1, 2]",
    "medium_count": "[2, 2]",
    "small_count": "[2, 3]",
    "large_radius": "[0.20, 0.30]",
    "medium_radius": "[0.13, 0.19]",
    "small_radius": "[0.07, 0.11]",
    "patch_profile": '"cushion"',
    "region_count": "[3, 4]",
    "scale_multiplier": "1.0",
}


def disable(text, kind):
    pattern = re.compile(r'(kind = "%s"\n)(?!enabled = false)' % kind)
    return pattern.sub(r'\1enabled = false\n', text)


def _layer_block(text, kind):
    """Span of one layer's `kind`/`params` block, matched by brace depth.

    A regex ending at the first `\\n}\\n` stops early once params contains a
    nested dict such as color_weights, which leaves the real closing brace
    behind and produces an unparseable resource.
    """
    head = re.search(r'kind = "%s"\n(enabled = false\n)?params = \{' % kind, text)
    if head is None:
        return None
    depth, i = 0, head.end() - 1
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return head.start(), i + 2  # include the trailing newline
        i += 1
    return None


def _parse_overrides(raw):
    """--set count=[26, 34] --set diameter=[0.07, 0.13]"""
    out = {}
    for item in raw or []:
        if not item:
            continue
        key, _, value = item.partition("=")
        out[key.strip()] = value.strip()
    return out


def _replace_layer(text, kind, body):
    span = _layer_block(text, kind)
    if span is None:
        raise SystemExit("recipe has no %s layer to build on" % kind)
    return text[:span[0]] + body + text[span[1]:]


def rewrite_dressing(text, light, dark):
    params = "".join('"%s": %s,\n' % (k, v) for k, v in sorted(PATCHES.items()))
    body = ('kind = "dressing"\nparams = {\n' + params
            + '"color_weights": {\n"%s": 55.0,\n"%s": 45.0\n}\n}\n' % (light, dark))
    return _replace_layer(text, "dressing", body)


def rewrite_clutter(text, light, dark, shapes, archetype="particles",
                    placement="clusters", overrides=None):
    # Dirt Ground's scatter is the baseline; the archetype overrides the counts
    # and dimensions on top of it. Losing this merge silently reduced every
    # archetype to the baseline, so bits/cushion/gg differed only by shape.
    values = dict(DIRT_SCATTER)
    values.update(ARCHETYPES[archetype])
    values["placement_mode"] = '"%s"' % placement
    values.update(overrides or {})
    params = "".join('"%s": %s,\n' % (k, v) for k, v in sorted(values.items()))
    body = ('kind = "clutter"\nparams = {\n' + params
            + '"color_weights": {\n"%s": 50.0,\n"%s": 50.0\n},\n' % (light, dark)
            + '"shapes": [%s]\n}\n' % ", ".join('"%s"' % s for s in shapes))
    return _replace_layer(text, "clutter", body)


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
    ap.add_argument("--placement", default="clusters",
                    choices=["clusters", "drift"])
    # Per-tile tweaks on top of an archetype, e.g. --set count=[26, 34]
    ap.add_argument("--set", dest="overrides", default=[], action="append")
    ap.add_argument("--archetype", default="particles",
                    choices=sorted(list(ARCHETYPES) + ["patches"]))
    args = ap.parse_args()

    path = Path("tools/tile_kit/library/recipes/%s.tres" % args.tile_id)
    text = path.read_text(encoding="utf-8")
    for kind in DECORATIVE:
        text = disable(text, kind)
    mapping = dict(p.split("=") for p in args.base.split(",")) if args.base else {}
    text = rewrite_base(text, mapping)
    if args.archetype == "patches":
        text = rewrite_dressing(text, args.light, args.dark)
    else:
        text = rewrite_clutter(text, args.light, args.dark, args.shapes.split(","),
                               args.archetype, args.placement,
                               _parse_overrides(args.overrides))
    path.write_text(text, encoding="utf-8")
    print("%s: base + %s (%s / %s)"
          % (args.tile_id, args.archetype, args.light, args.dark))


if __name__ == "__main__":
    main()
