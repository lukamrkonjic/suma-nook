#!/usr/bin/env python3
"""Regenerate gg_material_palette.tres source albedos from the probe LUT.

Every named render target is inverted through the measured tonemap transfer
curve using the light factor of its dominant face orientation (sunlit top,
ambient side, or curved mix). Render targets stay untouched — this only tunes
SOURCE albedos, per the palette-enforcement rule.

Usage: python3 tools/apply_solved_palette.py docs/visual_rework/comparisons/ggday
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SUN_COLOR = (1.0, 0.9451, 0.8235)
SUN_ENERGY = 1.08
AMB_COLOR = (0.8471, 0.7725, 0.6941)
AMB_ENERGY = 0.72
PITCH, YAW = -60.0, -65.0

# name -> (target hex, orientation)
TARGETS = {
    "warm_white": ("FCF4C7", "top"), "ivory_highlight": ("E6D3AF", "top"),
    "stone_light": ("D8C5B1", "top"), "stone_mid_light": ("CDB797", "top"),
    "stone_mid": ("B9A390", "side"), "stone_warm_shadow": ("B69879", "side"),
    "stone_shadow": ("9C9074", "side"), "stone_deep_shadow": ("68614F", "side"),
    "soft_sage_gray": ("879783", "mix"),
    "grass_highlight": ("D0D341", "top"), "grass_sunlit": ("D0C72B", "top"),
    "grass_primary": ("C7BF29", "top"), "grass_secondary": ("BAB321", "top"),
    "grass_vivid_accent": ("C5C703", "top"),
    "moss_bright": ("A3B928", "top"), "moss_primary": ("97A31D", "top"),
    "grass_shade": ("838F15", "top"), "olive_shadow": ("6E6B33", "mix"),
    "deep_grass": ("656F0C", "top"), "earthy_olive": ("8F6C08", "mix"),
    "leaf_bright": ("A3AC43", "mix"), "leaf_soft_sage": ("A7AF7F", "mix"),
    "leaf_medium": ("82833F", "mix"), "leaf_olive": ("6E6B33", "mix"),
    "pine_light": ("838F15", "mix"), "pine_medium": ("656F0C", "mix"),
    "pine_shadow": ("5E5624", "mix"), "pine_deep": ("52460F", "mix"),
    "earth_light": ("BB763C", "side"), "earth_primary": ("AF6F3D", "side"),
    "earth_mid": ("A86635", "side"), "earth_shadow": ("925F3D", "side"),
    "earth_deep": ("854927", "side"),
    "soil_orange": ("985119", "top"), "soil_red_shadow": ("89410A", "side"),
    "soil_deep": ("703116", "side"), "soil_deepest": ("602308", "side"),
    "wood_highlight": ("E3B74F", "top"), "wood_light": ("D8A242", "top"),
    "wood_gold": ("C78831", "top"), "wood_primary": ("B87222", "top"),
    "wood_warm_shadow": ("985119", "side"), "wood_brown": ("7E533A", "side"),
    "wood_deep": ("643E2B", "side"), "wood_dark": ("503017", "side"),
    "warm_near_black": ("3C2413", "side"),
    "terracotta_light": ("CB814C", "mix"), "terracotta_primary": ("C78831", "mix"),
    "terracotta_orange": ("D88204", "mix"), "terracotta_shadow": ("B55106", "side"),
    "burnt_red": ("BE4328", "mix"), "coral": ("DA6144", "mix"), "soft_coral": ("E67B73", "mix"),
    "gold_highlight": ("F9DC2D", "top"), "gold_primary": ("F5C603", "top"),
    "gold_deep": ("E9A707", "mix"), "warm_yellow": ("F4B248", "mix"),
    "skin_light": ("E6B350", "mix"), "skin_mid": ("CB814C", "mix"), "skin_shadow": ("9A725E", "side"),
    "hair_light": ("7E533A", "mix"), "hair_primary": ("503017", "mix"), "hair_deep": ("3C2413", "mix"),
    "cream_fabric": ("E6D3AF", "mix"), "mustard_fabric": ("D8A242", "mix"),
    "brown_fabric": ("925F3D", "mix"), "dark_fabric": ("643E2B", "mix"),
    "uw_sand_light": ("EAE5DC", "top"), "uw_sand_shadow": ("D3D3C8", "side"),
    "uw_rock_light": ("9DA3A4", "top"), "uw_rock_mid": ("798793", "mix"), "uw_rock_shadow": ("5D6B78", "side"),
    "uw_flora_light": ("93C676", "mix"), "uw_flora_mid": ("5F9452", "mix"),
    "uw_flora_dark": ("176346", "side"), "uw_flora_deep": ("114831", "side"),
}

# Colors composed inside the water shader as EMISSION (no lighting applied):
# invert only the tonemap transfer, no light-factor division.
UNSHADED = {
    "background_cream_01": "E7E0CA", "background_cream_02": "E6E1CC", "background_cream_03": "E7E2CF",
    "water_foam": "EAF5F1", "water_shallow_highlight": "82CDCF",
    "water_shallow": "63C1C6", "water_turquoise": "46BCCC", "water_mid": "3CABC2",
    "water_deep_mid": "3699B3", "water_deep": "056A94", "water_abyss": "064B73",
}
# Keys kept at their raw authored values (emissive accents, misc).
RAW = {
    "fire_core": "FCF4C7", "fire_yellow": "F9DC2D", "fire_orange": "D88204", "fire_red": "BE4328",
    "water_caustic": "ACCECD",
    "background_rain": "323B2E", "calib_gray": "9E9E9E", "crystal": "82CDCF", "smoke": "C9BDA0",
    "magic": "B7853B",
}
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
    for key, (hx, face) in TARGETS.items():
        lf = {"top": lf_top, "side": lf_side, "mix": lf_mix}[face]
        req = F_inv(hex01(hx))
        solved[key] = hexstr(lin_to_srgb(np.clip(req / lf, 0, 1)))
    solved.update(RAW)
    for key, hx in UNSHADED.items():
        solved[key] = hexstr(lin_to_srgb(np.clip(F_inv(hex01(hx)), 0, 1)))
    for key, ref in LEGACY.items():
        solved[key] = solved[ref]

    def color(hx):
        r, g, b = (round(int(hx[i:i + 2], 16) / 255.0, 4) for i in (0, 2, 4))
        return f"Color({r}, {g}, {b}, 1)"

    col_lines = [f'"{k}": {color(v)}' for k, v in solved.items()]
    col_lines.append('"ui_panel": Color(0.949, 0.929, 0.871, 0.96)')
    col_lines.append('"ui_panel_dark": Color(0.271, 0.247, 0.196, 1)')
    tgt_lines = [f'"{k}": {color(hx)}' for k, (hx, _f) in TARGETS.items()]
    tgt_lines += [f'"{k}": {color(v)}' for k, v in RAW.items() if not k.startswith(("background_rain", "calib"))]
    tgt_lines += [f'"{k}": {color(v)}' for k, v in UNSHADED.items()]

    tres = """[gd_resource type="Resource" script_class="PaletteDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/palette_definition.gd" id="1"]

[resource]
script = ExtResource("1")
colors = {
%s
}
render_targets = {
%s
}
skin_tones = PackedColorArray(0.949, 0.8, 0.635, 1, 0.902, 0.702, 0.314, 1, 0.769, 0.553, 0.38, 1, 0.545, 0.365, 0.235, 1, 0.392, 0.267, 0.18, 1)
hair_colors = PackedColorArray(0.314, 0.188, 0.09, 1, 0.176, 0.145, 0.11, 1, 0.788, 0.62, 0.31, 1, 0.494, 0.325, 0.227, 1, 0.78, 0.78, 0.741, 1, 0.475, 0.541, 0.353, 1)
outfit_colors = PackedColorArray(0.745, 0.263, 0.157, 1, 0.302, 0.42, 0.365, 1, 0.42, 0.365, 0.541, 1, 0.847, 0.635, 0.259, 1, 0.361, 0.42, 0.549, 1)
""" % (",\n".join(col_lines), ",\n".join(tgt_lines))
    Path("assets/palettes/gg_material_palette.tres").write_text(tres)
    for k in ("grass_primary", "stone_light", "wood_light", "earth_mid", "warm_near_black", "skin_light"):
        print("%-18s -> %s" % (k, solved[k]))
    print("palette regenerated with %d solved + %d raw keys" % (len(TARGETS), len(RAW)))


if __name__ == "__main__":
    main()
