#!/usr/bin/env python3
"""Invert the measured tonemap chain to solve raw inputs for screen targets.

Reads the Match Lab probe (<base>_probe.png/.json), fits the linear->output
transfer curve, then solves:
  - background/gradient author colors (unshaded path) for exact screen targets;
  - raw albedos for sunlit top faces and ambient-lit side faces.

Usage: python3 tools/solve_albedos.py docs/visual_match/captures/day
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SAT = 0.93  # environment adjustment_saturation (applied post-tonemap)

# Lighting model inputs — keep in sync with garden_galaxy_day.tres.
SUN_COLOR = (1.0, 0.9451, 0.8235)
SUN_ENERGY = 1.25
AMB_COLOR = (0.8471, 0.8157, 0.749)
AMB_ENERGY = 0.74
SUN_DIR = None  # computed from pitch/yaw below
PITCH, YAW = -58.0, -85.0
TOP_TINT = (1.04, 1.03, 0.98)
SIDE_TINT = (0.96, 0.94, 0.91)
SHADOW_OPACITY = 0.88

LUMA = np.array([0.2126, 0.7152, 0.0722])


def srgb_to_lin(v):
    v = np.asarray(v, dtype=float)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(v):
    v = np.asarray(v, dtype=float)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * v ** (1 / 2.4) - 0.055)


def hex_to_rgb01(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def rgb01_to_hex(rgb):
    return "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in np.clip(rgb, 0, 1))


def main():
    base = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/visual_match/captures/day")
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
    lin_in = np.array(lin_in)
    out = np.array(out)
    order = np.argsort(lin_in)
    lin_in, out = lin_in[order], out[order]

    def F(x):        # linear pre-tonemap -> output 0..1 (per channel, pre-saturation)
        return np.interp(x, lin_in, out)

    def F_inv(y):
        return np.interp(y, out, lin_in)

    def invert_screen_target(target01):
        """Full inverse: screen sRGB target -> required pre-tonemap linear."""
        L = float(target01 @ LUMA)
        g = (np.asarray(target01) - (1 - SAT) * L) / SAT
        return F_inv(np.clip(g, 0, 1))

    # Sun direction from Euler pitch/yaw (Godot YXZ).
    p, yw = np.radians(PITCH), np.radians(YAW)
    d_after_pitch = np.array([0.0, np.sin(p), -np.cos(p)])
    d = np.array([
        d_after_pitch[2] * np.sin(yw),
        d_after_pitch[1],
        d_after_pitch[2] * np.cos(yw),
    ])
    sun_lin = srgb_to_lin(SUN_COLOR) * SUN_ENERGY
    amb_lin = srgb_to_lin(AMB_COLOR) * AMB_ENERGY

    def light_factor(normal, tint):
        ndotl = max(0.0, -float(np.dot(normal, d)))
        return (sun_lin * ndotl + amb_lin) * np.array(tint)

    LF_TOP = light_factor((0, 1, 0), TOP_TINT)
    LF_SIDE = light_factor((0, 0, 1), SIDE_TINT)
    LF_SHADOW = (amb_lin + srgb_to_lin(SUN_COLOR) * SUN_ENERGY
                 * max(0.0, -float(np.dot((0, 1, 0), d))) * (1 - SHADOW_OPACITY)) * np.array(TOP_TINT)

    print("sun dir:", np.round(d, 4), " NdotL top:", round(-float(np.dot((0, 1, 0), d)), 4))
    print("LF top:", np.round(LF_TOP, 4), " LF side:", np.round(LF_SIDE, 4))
    print()
    print("== Backgrounds (unshaded path) — author these values ==")
    for name, target in [
        ("day_background -> #E9E2CF", "E9E2CF"),
        ("mist_top -> #B4C6C5", "B4C6C5"),
        ("mist_mid -> #B9CCC6", "B9CCC6"),
        ("mist_bottom -> #BBD0CA", "BBD0CA"),
    ]:
        req_lin = invert_screen_target(hex_to_rgb01(target))
        print("  %-26s author %s" % (name, rgb01_to_hex(lin_to_srgb(req_lin))))
    print()
    print("== Raw albedos for sunlit TOP faces ==")
    for name, target in [
        ("grass (#CCC224)", "CCC224"),
        ("grass bright (#D5CE39)", "D5CE39"),
        ("stone pale (#D7CCBB)", "D7CCBB"),
        ("stone mid (#CBB899)", "CBB899"),
        ("wood honey (#E4BB4E)", "E4BB4E"),
        ("cardboard (#D5A84D scr)", "D5A84D"),
        ("terracotta top (#CA702D)", "CA702D"),
        ("soil top (#965B16)", "965B16"),
    ]:
        req_lin = invert_screen_target(hex_to_rgb01(target))
        albedo_lin = req_lin / LF_TOP
        print("  %-26s albedo %s" % (name, rgb01_to_hex(lin_to_srgb(albedo_lin))))
    print()
    print("== Raw albedos for ambient-lit SIDE faces ==")
    for name, target in [
        ("soil_side (#965B16)", "965B16"),
        ("charcoal (#3B312A)", "3B312A"),
        ("terracotta side (#CA702D)", "CA702D"),
    ]:
        req_lin = invert_screen_target(hex_to_rgb01(target))
        albedo_lin = req_lin / LF_SIDE
        print("  %-26s albedo %s" % (name, rgb01_to_hex(lin_to_srgb(albedo_lin))))
    print()
    print("== Sanity: grass shadow prediction ==")
    grass_alb = srgb_to_lin(hex_to_rgb01("CCC224")) / LF_TOP * srgb_to_lin(1.0)
    shadow_out = F(np.clip(srgb_to_lin(lin_to_srgb(grass_alb)) * LF_SHADOW, 0, 1))
    L = float(shadow_out @ LUMA)
    shadow_px = SAT * shadow_out + (1 - SAT) * L
    print("  grass-in-shadow renders ~%s (target #90871A)" % rgb01_to_hex(shadow_px))


if __name__ == "__main__":
    main()
