#!/usr/bin/env python3
"""Route every tile-kit material that has a Garden Galaxy colour onto the GG path.

The tile kit maps an authoring role to a palette token, but bakes the material
under the name "tilekit_<role>". MaterialLibrary rebinds by that baked name and
only knows names present in the palette's `colors` table, so the mapping is
silently dropped in game: the material keeps its baked albedo and never reaches
the solved Garden Galaxy colour its role points at.

This registers the missing names, preserving the tile kit's own mapping:
  exact["tilekit_<role>"]  = exact[token]   -- the GG-solved albedo
  colors["tilekit_<role>"] = colors[token]  -- so MaterialLibrary rebinds at all

Roles whose token has no GG entry are left alone. Registering those would move
them onto the GG surface shader without any GG colour to show for it.
"""
import json
import re
from pathlib import Path

PALETTE = Path("assets/palettes/gg_material_palette.tres")
GG = Path("data/garden_galaxy_reference_palette.json")
KIT = Path("tools/tile_kit/tile_kit_palette.gd")


def main():
    gg = json.loads(GG.read_text(encoding="utf-8"))
    exact = gg["exact"]
    text = PALETTE.read_text(encoding="utf-8")
    start, end = text.index("\ncolors = {"), text.index("\naliases = {")
    body = text[start:end]
    colors = dict(re.findall(r'"([a-z_0-9]+)":\s*Color\(([^)]*)\)', body))
    pairs = re.findall(r'^\t"([a-z_0-9]+)":\s*"([a-z_0-9]+)",',
                       KIT.read_text(encoding="utf-8"), re.M)

    added_exact, added_color, skipped = 0, [], 0
    for role, token in pairs:
        name = "tilekit_%s" % role
        if name in exact or token not in exact:
            skipped += token not in exact
            continue
        exact[name] = exact[token]
        added_exact += 1
        if name not in colors and token in colors:
            added_color.append((name, colors[token]))

    anchor = text.index('"tilekit_grass_gg_tuft": Color(')
    line_end = text.index("\n", anchor) + 1
    insert = "".join('"%s": Color(%s),\n' % (n, v) for n, v in added_color)
    text = text[:line_end] + insert + text[line_end:]

    PALETTE.write_text(text, encoding="utf-8")
    GG.write_text(json.dumps(gg, indent=2) + "\n", encoding="utf-8")
    print("registered %d materials on the GG path" % added_exact)
    print("added %d palette tokens so MaterialLibrary rebinds them" % len(added_color))
    print("left %d alone (their token has no GG colour)" % skipped)


if __name__ == "__main__":
    main()
