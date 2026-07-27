#!/usr/bin/env python3
"""Measure a visual acceptance capture against the reference targets.

Usage:
    python3 tools/compare_reference_render.py docs/visual_match/captures/day \
        [--label day] [--old docs/style_comparisons/final_gameplay_day.png] \
        [--reference docs/style_reference/garden_galaxy/garden_galaxy_day_reference_01.png]

Expects <base>.png, <base>_post.png and <base>.json from a capture run. Produces
a Delta E 2000 report
(markdown + JSON), a swatch comparison card, a side-by-side image, and — when a
reference screenshot is available on disk — a per-pixel difference heatmap.
All colors are screen-space rendered values, compared in CIE Lab (D65).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ------------------------------------------------------------------ targets
# Screen-space rendered color targets sampled from the supplied Garden Galaxy
# references. Each region accepts a small family; the report scores the nearest.
TARGETS = {
    "background": (["E9E2CF"], 2.5),
    "grass_lit": (["CCC224", "D4D041", "D5CE39"], 5.0),
    "grass_lit_b": (["CCC224", "D4D041", "D5CE39"], 5.0),
    "grass_shadow": (["90871A"], 7.0),
    "stone_lit": (["D7CCBB", "CBB899", "E8E1D6"], 8.0),
    "stone_clearing": (["D7CCBB", "CBB899", "A89779"], 6.0),
    "soil_side": (["965B16", "C18134"], 11.0),
    "wood": (["E4BB4E", "DFBA5B", "C18134"], 6.0),
    "water": (["7D9285", "6F877E", "8AA393"], 6.0),
    "water_open": (["7D9285", "6F877E", "8AA393"], 6.0),
    "pine": (["4F5B0C", "343E13", "777D13"], 7.0),
    "bush": (["9EB42A", "858716", "777D13"], 7.0),
    "terracotta": (["CA702D", "C18134"], 11.0),
    "charcoal": (["3B312A", "2A1F1A", "827565"], 5.0),
    "cardboard": (["D5A84D", "E4BB4E"], 8.0),
}
INFORMATIONAL = {"cardboard", "stone_clearing", "grass_lit_b", "water_open", "grass_shadow"}

SHADOW_TARGET_ANGLE_DEG = 14.0     # right and slightly downward
SHADOW_ANGLE_TOL_DEG = 10.0
SHADOW_LEN_RANGE_TILES = (0.40, 0.55)
SHADOW_DARKEN_RANGE = (0.08, 0.32)  # cast-shadow luminance drop vs lit
CONTACT_DARKEN_RANGE = (0.04, 0.50)
FRAME_WIDTH_RANGE = (0.60, 0.70)
FRAME_HEIGHT_RANGE = (0.55, 0.65)


# ------------------------------------------------------------------ color math
def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


def srgb_to_lab(rgb):
    """rgb: (..., 3) in 0..255 → CIE Lab (D65)."""
    c = np.asarray(rgb, dtype=float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ])
    xyz = c @ m.T
    white = np.array([0.95047, 1.0, 1.08883])
    v = xyz / white
    f = np.where(v > 0.008856, np.cbrt(v), 7.787 * v + 16.0 / 116.0)
    L = 116.0 * f[..., 1] - 16.0
    a = 500.0 * (f[..., 0] - f[..., 1])
    b = 200.0 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


def delta_e2000(lab1, lab2):
    """CIEDE2000, vectorized over leading dims."""
    L1, a1, b1 = np.moveaxis(np.asarray(lab1, dtype=float), -1, 0)
    L2, a2, b2 = np.moveaxis(np.asarray(lab2, dtype=float), -1, 0)
    C1 = np.hypot(a1, b1)
    C2 = np.hypot(a2, b2)
    Cbar = (C1 + C2) / 2.0
    G = 0.5 * (1 - np.sqrt(Cbar ** 7 / (Cbar ** 7 + 25.0 ** 7)))
    a1p = (1 + G) * a1
    a2p = (1 + G) * a2
    C1p = np.hypot(a1p, b1)
    C2p = np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp = L2 - L1
    dCp = C2p - C1p
    dhp = h2p - h1p
    dhp = np.where(dhp > 180, dhp - 360, dhp)
    dhp = np.where(dhp < -180, dhp + 360, dhp)
    dhp = np.where((C1p * C2p) == 0, 0.0, dhp)
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp) / 2.0)
    Lbp = (L1 + L2) / 2.0
    Cbp = (C1p + C2p) / 2.0
    hsum = h1p + h2p
    hbp = np.where(
        (C1p * C2p) == 0, hsum,
        np.where(np.abs(h1p - h2p) <= 180, hsum / 2.0,
                 np.where(hsum < 360, (hsum + 360) / 2.0, (hsum - 360) / 2.0)),
    )
    T = (1 - 0.17 * np.cos(np.radians(hbp - 30)) + 0.24 * np.cos(np.radians(2 * hbp))
         + 0.32 * np.cos(np.radians(3 * hbp + 6)) - 0.20 * np.cos(np.radians(4 * hbp - 63)))
    dtheta = 30 * np.exp(-(((hbp - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25.0 ** 7))
    Sl = 1 + (0.015 * (Lbp - 50) ** 2) / np.sqrt(20 + (Lbp - 50) ** 2)
    Sc = 1 + 0.045 * Cbp
    Sh = 1 + 0.015 * Cbp * T
    Rt = -np.sin(np.radians(2 * dtheta)) * Rc
    return np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2
                   + Rt * (dCp / Sc) * (dHp / Sh))


def rgb_to_hex(rgb):
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in np.clip(rgb, 0, 255))


def luminance(img):
    return img[..., 0] * 0.2126 + img[..., 1] * 0.7152 + img[..., 2] * 0.0722


# ------------------------------------------------------------------ sampling
def sample_patch(img, xy, radius=7):
    h, w = img.shape[:2]
    x = int(round(np.clip(xy[0], radius, w - radius - 1)))
    y = int(round(np.clip(xy[1], radius, h - radius - 1)))
    patch = img[y - radius:y + radius + 1, x - radius:x + radius + 1]
    return np.median(patch.reshape(-1, 3), axis=0)


def score_region(name, measured_rgb):
    hexes, tol = TARGETS[name]
    labs = srgb_to_lab(np.array([hex_to_rgb(h) for h in hexes]))
    measured_lab = srgb_to_lab(measured_rgb)
    des = [float(delta_e2000(measured_lab, lab)) for lab in labs]
    idx = int(np.argmin(des))
    return {
        "region": name,
        "measured": rgb_to_hex(measured_rgb),
        "target": "#" + hexes[idx],
        "delta_e": round(des[idx], 2),
        "tolerance": tol,
        "pass": des[idx] <= tol,
        "informational": name in INFORMATIONAL,
    }


# ------------------------------------------------------------------ shadow
def analyze_shadow(base, post, manifest):
    lb = luminance(base)
    lp = luminance(post)
    darkened = (lb - lp) > 8.0
    r, g, b = post[..., 0], post[..., 1], post[..., 2]
    magenta = (r > 130) & (b > 120) & (g < 110) & (r - g > 60) & (b - g > 40)
    # Dilate the post silhouette a few px so AA edges don't pollute the mask.
    for _ in range(3):
        magenta = (magenta
                   | np.roll(magenta, 1, 0) | np.roll(magenta, -1, 0)
                   | np.roll(magenta, 1, 1) | np.roll(magenta, -1, 1))
    base_px = np.array(manifest["post"]["base_px"], dtype=float)
    tile_px = manifest["tile_px"]
    yy, xx = np.mgrid[0:base.shape[0], 0:base.shape[1]]
    near = (np.hypot(xx - base_px[0], yy - base_px[1]) < tile_px * 2.5)
    mask = darkened & ~magenta & near
    n = int(mask.sum())
    if n < 50:
        return {"ok": False, "reason": "shadow mask too small (%d px)" % n}

    pys, pxs = np.nonzero(mask)
    weights = (lb - lp)[pys, pxs]
    vx = np.average(pxs - base_px[0], weights=weights)
    vy = np.average(pys - base_px[1], weights=weights)
    angle = math.degrees(math.atan2(vy, vx))  # y-down screen space
    direction = np.array([vx, vy])
    direction /= (np.linalg.norm(direction) + 1e-9)
    proj = (pxs - base_px[0]) * direction[0] + (pys - base_px[1]) * direction[1]
    length_px = float(np.percentile(proj, 96))
    length_tiles = length_px / tile_px

    # Core darkening: top-quartile of the added shadow, so the wide penumbra
    # doesn't dilute the reading.
    drops = (lb - lp)[pys, pxs]
    core = drops >= np.percentile(drops, 75)
    ratio = 1.0 - float(lp[pys, pxs][core].mean() / max(lb[pys, pxs][core].mean(), 1e-6))

    # Penumbra: luminance transition width across the shadow edge, averaged
    # over several parallel scanlines so turf-bump noise doesn't inflate it.
    perp = np.array([-direction[1], direction[0]])
    ts = np.arange(-30, 31)
    profiles = []
    for frac in (0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7):
        mid = base_px + direction * length_px * frac
        xs = np.clip((mid[0] + perp[0] * ts).astype(int), 0, base.shape[1] - 1)
        ys = np.clip((mid[1] + perp[1] * ts).astype(int), 0, base.shape[0] - 1)
        profiles.append(lp[ys, xs].astype(float))
    profile = np.mean(profiles, axis=0)
    profile = np.convolve(profile, np.ones(3) / 3.0, mode="same")
    lo, hi = profile.min(), profile.max()
    if hi - lo < 6:
        penumbra_px = float("nan")
    else:
        norm = (profile - lo) / (hi - lo)
        inside = np.nonzero(norm < 0.2)[0]
        outside = np.nonzero(norm > 0.8)[0]
        penumbra_px = float(abs(ts[outside[0]] - ts[inside[-1]])) if len(inside) and len(outside) else float("nan")

    shadow_rgb = np.median(post[pys, pxs], axis=0)
    grass_shadow = score_region("grass_shadow", shadow_rgb)
    angle_err = abs(angle - SHADOW_TARGET_ANGLE_DEG)
    return {
        "ok": True,
        "angle_deg": round(angle, 1),
        "angle_target": SHADOW_TARGET_ANGLE_DEG,
        "angle_pass": angle_err <= SHADOW_ANGLE_TOL_DEG,
        "length_tiles": round(length_tiles, 3),
        "length_pass": SHADOW_LEN_RANGE_TILES[0] <= length_tiles <= SHADOW_LEN_RANGE_TILES[1],
        "darken_ratio": round(ratio, 3),
        "darken_pass": SHADOW_DARKEN_RANGE[0] <= ratio <= SHADOW_DARKEN_RANGE[1],
        "penumbra_px": penumbra_px,
        "shadow_color": grass_shadow,
        "mask_px": n,
    }


# ------------------------------------------------------------------ reports
def build_swatch_card(rows, out_path):
    row_h, sw, pad = 34, 90, 8
    width = 560
    img = Image.new("RGB", (width, row_h * (len(rows) + 1) + pad * 2), (245, 243, 236))
    draw = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    draw.text((pad, pad), "region", fill=(60, 55, 45), font=font)
    draw.text((200, pad), "target", fill=(60, 55, 45), font=font)
    draw.text((200 + sw + 30, pad), "measured", fill=(60, 55, 45), font=font)
    draw.text((440, pad), "dE00", fill=(60, 55, 45), font=font)
    for i, row in enumerate(rows):
        y = pad + row_h * (i + 1)
        draw.text((pad, y + 9), row["region"], fill=(40, 38, 32), font=font)
        draw.rectangle([200, y + 2, 200 + sw, y + row_h - 6], fill=row["target"])
        draw.rectangle([200 + sw + 30, y + 2, 200 + 2 * sw + 30, y + row_h - 6], fill=row["measured"])
        status = "PASS" if row["pass"] else ("info" if row["informational"] else "FAIL")
        draw.text((440, y + 9), "%.1f %s" % (row["delta_e"], status), fill=(40, 90, 40) if row["pass"] else (140, 50, 40), font=font)
    img.save(out_path)


def build_side_by_side(panels, labels, out_path, height=540):
    imgs = []
    for p in panels:
        im = Image.open(p).convert("RGB")
        im = im.resize((int(im.width * height / im.height), height), Image.LANCZOS)
        imgs.append(im)
    total_w = sum(im.width for im in imgs) + 10 * (len(imgs) - 1)
    canvas = Image.new("RGB", (total_w, height + 28), (30, 28, 26))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    x = 0
    for im, label in zip(imgs, labels):
        canvas.paste(im, (x, 28))
        draw.text((x + 6, 8), label, fill=(230, 226, 214), font=font)
        x += im.width + 10
    canvas.save(out_path)


def build_heatmap(capture, reference_path, out_path):
    ref = Image.open(reference_path).convert("RGB")
    cap_img = Image.fromarray(capture.astype(np.uint8))
    ref = np.asarray(ref.resize(cap_img.size, Image.LANCZOS), dtype=float)
    de = delta_e2000(srgb_to_lab(capture), srgb_to_lab(ref))
    norm = np.clip(de / 30.0, 0, 1)
    heat = np.zeros((*norm.shape, 3), dtype=np.uint8)
    heat[..., 0] = (norm * 255).astype(np.uint8)
    heat[..., 2] = ((1 - norm) * 255).astype(np.uint8)
    heat[..., 1] = (np.clip(1 - np.abs(norm - 0.5) * 2, 0, 1) * 160).astype(np.uint8)
    Image.fromarray(heat).save(out_path)
    return float(np.mean(de))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", help="capture base path (without .png)")
    parser.add_argument("--label", default=None)
    parser.add_argument("--old", default=None, help="previous render for side-by-side")
    parser.add_argument("--reference", default=None, help="Garden Galaxy reference screenshot")
    args = parser.parse_args()

    base_path = Path(args.base)
    label = args.label or base_path.name
    img_path = base_path.with_suffix(".png")
    post_path = base_path.parent / (base_path.name + "_post.png")
    manifest_path = base_path.with_suffix(".json")
    for p in (img_path, post_path, manifest_path):
        if not p.exists():
            sys.exit("missing %s — run the Match Lab capture first" % p)

    capture = np.asarray(Image.open(img_path).convert("RGB"), dtype=float)
    post = np.asarray(Image.open(post_path).convert("RGB"), dtype=float)
    manifest = json.loads(manifest_path.read_text())
    h, w = capture.shape[:2]

    rows = []
    # Background from the two top corners (empty sky in the lab framing).
    bg = np.mean([sample_patch(capture, (w * 0.04, h * 0.05), 12),
                  sample_patch(capture, (w * 0.96, h * 0.05), 12)], axis=0)
    rows.append(score_region("background", bg))
    for name, xy in manifest["markers"].items():
        if name in TARGETS:
            rows.append(score_region(name, sample_patch(capture, xy)))

    shadow = analyze_shadow(capture, post, manifest)
    if shadow.get("ok"):
        rows.append(shadow["shadow_color"])

    # Contact shadow: darkest direction of an annulus around the pot base
    # (the grounding ring is direction-dependent), vs open lit grass.
    lit = sample_patch(capture, manifest["markers"]["grass_lit"])
    lit_luma = max(luminance(lit[None, None])[0, 0], 1e-6)
    lum_img = luminance(capture)
    ppm = manifest["px_per_meter"]
    ccx, ccy = manifest["markers"].get("contact_center", manifest["markers"]["contact_shadow"])
    contact_ratio = 0.0
    for ang in np.linspace(0, 2 * math.pi, 48, endpoint=False):
        vals = []
        for rr in (0.26, 0.30, 0.34):
            x = int(ccx + math.cos(ang) * rr * ppm)
            y = int(ccy + math.sin(ang) * rr * ppm * 0.56)
            if 2 <= x < capture.shape[1] - 2 and 2 <= y < capture.shape[0] - 2:
                vals.append(float(np.median(lum_img[y - 2:y + 3, x - 2:x + 3])))
        if vals:
            contact_ratio = max(contact_ratio, 1.0 - min(vals) / lit_luma)
    contact_pass = CONTACT_DARKEN_RANGE[0] <= contact_ratio <= CONTACT_DARKEN_RANGE[1]

    # Framing.
    corners = np.array(manifest["world_corners"])
    width_frac = (corners[:, 0].max() - corners[:, 0].min()) / w
    height_frac = (corners[:, 1].max() - corners[:, 1].min()) / h
    width_pass = FRAME_WIDTH_RANGE[0] <= width_frac <= FRAME_WIDTH_RANGE[1]
    height_pass = FRAME_HEIGHT_RANGE[0] <= height_frac <= FRAME_HEIGHT_RANGE[1]

    # Clipping.
    lum = luminance(capture)
    black_floor = float(np.percentile(lum, 0.2))
    white_frac = float(np.mean(np.min(capture, axis=-1) >= 253))
    neutral = srgb_to_lab(sample_patch(capture, manifest["markers"]["calib_sphere_top"]))

    out_dir = Path("docs/visual_match/reports")
    out_dir.mkdir(parents=True, exist_ok=True)
    build_swatch_card(rows, out_dir / ("%s_swatches.png" % label))

    panels, labels = [str(img_path)], ["new: %s" % label]
    if args.old and Path(args.old).exists():
        panels.insert(0, args.old)
        labels.insert(0, "old")
    if args.reference and Path(args.reference).exists():
        panels.insert(0, args.reference)
        labels.insert(0, "reference")
    build_side_by_side(panels, labels, out_dir / ("%s_side_by_side.png" % label))

    mean_de = None
    if args.reference and Path(args.reference).exists():
        mean_de = build_heatmap(capture, args.reference, out_dir / ("%s_heatmap.png" % label))

    hard_rows = [r for r in rows if not r["informational"]]
    all_pass = (all(r["pass"] for r in hard_rows)
                and shadow.get("ok", False) and shadow.get("angle_pass") and shadow.get("length_pass")
                and shadow.get("darken_pass") and contact_pass and width_pass and height_pass
                and black_floor > 10 and white_frac < 0.001)

    report = {
        "label": label,
        "profile": manifest.get("profile"),
        "regions": rows,
        "shadow": shadow,
        "contact_shadow": {"darken_ratio": round(contact_ratio, 3), "pass": contact_pass},
        "framing": {
            "width_frac": round(float(width_frac), 3), "width_pass": width_pass,
            "height_frac": round(float(height_frac), 3), "height_pass": height_pass,
        },
        "black_floor_luma": round(black_floor, 1),
        "white_clip_frac": white_frac,
        "neutral_lab": [round(float(v), 1) for v in neutral],
        "reference_mean_delta_e": mean_de,
        "all_pass": bool(all_pass),
    }
    def _jsonable(o):
        if isinstance(o, (np.bool_,)):
            return bool(o)
        if isinstance(o, (np.floating, np.integer)):
            return float(o)
        raise TypeError(repr(o))

    (out_dir / ("%s_report.json" % label)).write_text(json.dumps(report, indent=2, default=_jsonable))

    lines = ["# Garden Galaxy match report — %s" % label, ""]
    lines.append("| region | measured | target | dE00 | tol | status |")
    lines.append("|---|---|---|---|---|---|")
    for r in rows:
        status = "PASS" if r["pass"] else ("info" if r["informational"] else "FAIL")
        lines.append("| %s | %s | %s | %.1f | %.1f | %s |" % (
            r["region"], r["measured"], r["target"], r["delta_e"], r["tolerance"], status))
    lines.append("")
    if shadow.get("ok"):
        lines.append("Shadow: angle %.1f deg (target %.0f±%.0f, %s), length %.2f tiles (%s), "
                     "darkening %.0f%% (%s), penumbra %s px" % (
                         shadow["angle_deg"], SHADOW_TARGET_ANGLE_DEG, SHADOW_ANGLE_TOL_DEG,
                         "PASS" if shadow["angle_pass"] else "FAIL",
                         shadow["length_tiles"], "PASS" if shadow["length_pass"] else "FAIL",
                         shadow["darken_ratio"] * 100, "PASS" if shadow["darken_pass"] else "FAIL",
                         "%.0f" % shadow["penumbra_px"] if shadow["penumbra_px"] == shadow["penumbra_px"] else "n/a"))
    else:
        lines.append("Shadow: measurement failed — %s" % shadow.get("reason"))
    lines.append("Contact shadow: %.0f%% darker (%s)" % (contact_ratio * 100, "PASS" if contact_pass else "FAIL"))
    lines.append("Framing: %.0f%% width (%s), %.0f%% height (%s)" % (
        width_frac * 100, "PASS" if width_pass else "FAIL",
        height_frac * 100, "PASS" if height_pass else "FAIL"))
    lines.append("Black floor luma: %.1f (>10 required). White clip: %.4f%%" % (black_floor, white_frac * 100))
    lines.append("Neutral sphere Lab: L %.0f a %.1f b %.1f (warm cast expected: small +a/+b)" % tuple(report["neutral_lab"]))
    if mean_de is not None:
        lines.append("Reference mean dE00 (layout differs — trend only): %.1f" % mean_de)
    lines.append("")
    lines.append("OVERALL: %s" % ("ALL PASS" if all_pass else "NOT PASSING YET"))
    (out_dir / ("%s_report.md" % label)).write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
