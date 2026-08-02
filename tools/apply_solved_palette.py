#!/usr/bin/env python3
"""Regenerate gg_material_palette.tres source albedos from the probe LUT.

Every named render target is inverted through the measured tonemap transfer
curve using the light factor of its dominant face orientation (sunlit top,
ambient side, or curved mix). Render targets stay untouched — this only tunes
SOURCE albedos, per the palette-enforcement rule.

Usage: python3 tools/apply_solved_palette.py [probe_base] [palette.tres]
       defaults: docs/visual_rework/comparisons/ggday
                 assets/palettes/gg_material_palette.tres
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from palette_io import (
    CANONICAL_PALETTE,
    read_color_block,
    read_color_hexes,
    read_token_specs,
    update_color_block,
)

SUN_COLOR = (1.0, 0.9451, 0.8235)
SUN_ENERGY = 1.08
AMB_COLOR = (0.8471, 0.7725, 0.6941)
AMB_ENERGY = 0.72
PITCH, YAW = -60.0, -65.0

# Dominant face orientation per named surface — decides which light
# factor the solver divides out. Target hexes come from the palette JSON.
FACE = {
    "warm_white": "top", "ivory_highlight": "top", "stone_light": "top", "stone_mid_light": "top",
    "stone_mid": "side", "stone_warm_shadow": "side", "stone_shadow": "side", "stone_deep_shadow": "side",
    "soft_sage_gray": "mix", "grass_highlight": "top", "grass_sunlit": "top", "grass_primary": "top",
    "grass_secondary": "top", "grass_vivid_accent": "top", "moss_bright": "top", "moss_primary": "top",
    "grass_shade": "top", "olive_shadow": "mix", "deep_grass": "top", "earthy_olive": "mix",
    "leaf_bright": "mix", "leaf_soft_sage": "mix", "leaf_medium": "mix", "leaf_olive": "mix",
    "pine_light": "mix", "pine_medium": "mix", "pine_shadow": "mix", "pine_deep": "mix",
    "earth_light": "side", "earth_primary": "side", "earth_mid": "side", "earth_shadow": "side",
    "earth_deep": "side", "soil_orange": "top", "soil_red_shadow": "side", "soil_deep": "side",
    "soil_deepest": "side", "wood_highlight": "top", "wood_light": "top", "wood_gold": "top",
    "wood_primary": "top", "wood_warm_shadow": "side", "wood_brown": "side", "wood_deep": "side",
    "wood_dark": "side", "warm_near_black": "side", "terracotta_light": "mix", "terracotta_primary": "mix",
    "terracotta_orange": "mix", "terracotta_shadow": "side", "burnt_red": "mix", "coral": "mix",
    "soft_coral": "mix", "gold_highlight": "top", "gold_primary": "top", "gold_deep": "mix",
    "warm_yellow": "mix", "skin_light": "mix", "skin_mid": "mix", "skin_shadow": "side",
    "hair_light": "mix", "hair_primary": "mix", "hair_deep": "mix", "cream_fabric": "mix",
    "mustard_fabric": "mix", "brown_fabric": "mix", "dark_fabric": "mix", "uw_sand_light": "top",
    "uw_sand_shadow": "side", "uw_rock_light": "top", "uw_rock_mid": "mix", "uw_rock_shadow": "side",
    "uw_flora_light": "mix", "uw_flora_mid": "mix", "uw_flora_dark": "side", "uw_flora_deep": "side",
}

# Composed inside shaders as EMISSION (no lighting applied): invert only the
# tonemap transfer, no light-factor division.
UNSHADED = [
    "background_cream_01", "background_cream_02", "background_cream_03",
    "water_foam", "water_shallow_highlight", "water_shallow", "water_turquoise",
    "water_mid", "water_deep_mid", "water_deep", "water_abyss",
]
# Authored as-is (emissive accents drive their own energy; misc helpers).
RAW = ["fire_core", "fire_yellow", "fire_orange", "fire_red", "water_caustic",
       "crystal", "smoke", "magic"]
EXTRA = {"background_rain": "323B2E", "calib_gray": "9E9E9E"}
LEGACY = {
    "background_day": "background_cream_01",
    "grass": "grass_primary", "grass_lush": "grass_sunlit", "grass_tuft": "moss_bright",
    "moss": "moss_primary", "dark_foliage": "leaf_olive", "bright_foliage": "leaf_bright",
    "foliage_medium": "leaf_medium", "foliage_deep": "pine_shadow", "pine_dark": "pine_shadow",
    "soil": "soil_orange", "soil_side": "earth_mid", "dark_soil": "soil_deep",
    "wood": "wood_primary", "wood_mid": "wood_brown", "dark_wood": "wood_deep",
    "pale_stone": "stone_light", "dark_stone": "stone_shadow", "stone_highlight": "ivory_highlight",
    "terracotta": "terracotta_light", "terracotta_dark": "terracotta_shadow",
    "water": "water_turquoise", "water_light": "water_shallow",
    "cardboard": "wood_light", "gold": "gold_primary",
    "fabric": "burnt_red", "fabric_accent": "mustard_fabric",
    "metal": "stone_deep_shadow", "warm_charcoal": "warm_near_black", "warm_gray": "stone_mid",
    "skin": "skin_light", "hair": "hair_primary", "eyes": "hair_deep",
    "petal_white": "warm_white", "petal_pink": "soft_coral", "petal_red": "coral",
    "flower_yellow": "gold_primary", "mushroom_red": "coral",
    "ui_accent": "terracotta_light", "ui_good": "leaf_bright", "ui_bad": "coral", "ui_rare": "gold_primary",
}


def srgb_to_lin(v):
    v = np.asarray(v, dtype=float)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(v):
    v = np.asarray(v, dtype=float)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * np.clip(v, 0, None) ** (1 / 2.4) - 0.055)


def hex01(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def hexstr(rgb01):
    return "%02X%02X%02X" % tuple(int(round(c * 255)) for c in np.clip(rgb01, 0, 1))


def main():
    base = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/visual_rework/comparisons/ggday")
    pal_path = Path(sys.argv[2]) if len(sys.argv) > 2 else CANONICAL_PALETTE
    targets = {
        key: value.lstrip("#").upper()
        for key, value in read_color_hexes(pal_path, "render_targets").items()
    }
    img = np.asarray(Image.open(str(base) + "_probe.png").convert("RGB"), float)
    man = json.loads(Path(str(base) + "_probe.json").read_text())
    lin_in, out = [], []
    for s in man["swatches"]:
        i = s["input"]
        if not (abs(i[0] - i[1]) < 1e-6 and abs(i[1] - i[2]) < 1e-6):
            continue
        x, y = int(s["px"][0]), int(s["px"][1])
        patch = np.median(img[y - 8:y + 9, x - 8:x + 9].reshape(-1, 3), axis=0)
        lin_in.append(float(srgb_to_lin(i[0])))
        out.append(float(patch.mean()) / 255.0)
    order = np.argsort(lin_in)
    lin_in = np.array(lin_in)[order]
    out = np.array(out)[order]

    def F_inv(y):
        return np.interp(y, out, lin_in)

    p, yw = np.radians(PITCH), np.radians(YAW)
    dap = np.array([0.0, np.sin(p), -np.cos(p)])
    d = np.array([dap[2] * np.sin(yw), dap[1], dap[2] * np.cos(yw)])
    sun = srgb_to_lin(SUN_COLOR) * SUN_ENERGY
    amb = srgb_to_lin(AMB_COLOR) * AMB_ENERGY
    lf_top = sun * max(0.0, -d[1]) + amb
    lf_side = sun * max(0.0, -d[2]) + amb
    lf_mix = (lf_top + lf_side) / 2.0

    solved = {}
    for key, face in FACE.items():
        if key not in targets:
            continue
        lf = {"top": lf_top, "side": lf_side, "mix": lf_mix}[face]
        req = F_inv(hex01(targets[key]))
        solved[key] = hexstr(lin_to_srgb(np.clip(req / lf, 0, 1)))
    for key in RAW:
        solved[key] = targets[key]
    for key in UNSHADED:
        solved[key] = hexstr(lin_to_srgb(np.clip(F_inv(hex01(targets[key])), 0, 1)))
    solved.update(EXTRA)
    for key, ref in LEGACY.items():
        solved[key] = solved[ref]

    semantic_replacements = {
        key: tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)
        for key, value in solved.items()
    }
    literal_tokens = read_color_block(pal_path, "colors")
    if literal_tokens:
        replacements = {
            token: value
            for token, value in semantic_replacements.items()
            if token in literal_tokens
        }
        update_color_block(pal_path, "colors", replacements)
        destination = "exact semantic colors"
    else:
        token_specs = read_token_specs(pal_path)
        grouped: dict[str, list[tuple[float, float, float, float]]] = {}
        for token, value in semantic_replacements.items():
            spec = token_specs.get(token)
            if spec is None:
                continue
            grouped.setdefault(str(spec["swatch"]), []).append(value)
        replacements = {
            swatch_id: tuple(float(component) for component in np.mean(values, axis=0))
            for swatch_id, values in grouped.items()
        }
        update_color_block(pal_path, "swatches", replacements)
        destination = "shared swatches"
    print("palette: %s" % pal_path)
    for k in ("grass_primary", "pine_medium", "stone_light", "wood_light",
              "earth_mid", "water_turquoise", "background_cream_01"):
        print("  %-20s target #%s  ->  source #%s" % (k, targets[k], solved[k]))
    print(
        "%d targets solved into %d %s; updated %s"
        % (len(solved), len(replacements), destination, pal_path)
    )
    print("PROFILE BACKGROUND -> #%s" % solved["background_cream_01"])


if __name__ == "__main__":
    main()
