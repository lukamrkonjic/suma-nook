"""Deterministic tuft sprite builder for the Tile Kit sprite-card carpet.

Produces original white-on-transparent tuft sprites in the audited reference
TECHNIQUE (soft alpha silhouette, baked top-to-base value gradient, tinted at
runtime by a palette material) while every silhouette here is authored fresh
for Suma: lobe counts, proportions, asymmetry, and gradient values are our
own picks. No reference image data is read or copied by this script.

Technique notes (from the clean-room audit, measurements only):
- tuft sprites are near-white; the material tint supplies ALL hue;
- a vertical luminance gradient (~1.00 top -> ~0.84 base) bakes the soft
  "lit from above" form so no per-card lighting tricks are needed;
- alpha is a solid silhouette with a short soft falloff (anti-aliased edge),
  not a hard cutout and not a broad fade.

Output: assets/textures/tile_kit/tuft_sprout.png (128x128 RGBA)

Run:  python art_source/sprites/build_tuft_sprites.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "textures" / "tile_kit"

SS = 4          # supersample factor: draw at 512, ship 128
SIZE = 128
CANVAS = SIZE * SS

# Value gradient across the sprite CONTENT (not the padded canvas).
GRADIENT_TOP = 1.00
GRADIENT_BASE = 0.81


def lobe_circles(draw: ImageDraw.ImageDraw, base: tuple, tip: tuple,
                 r_max: float, steps: int = 34) -> None:
    """One blunt egg-shaped leaf: overlapping circles swept base->tip.

    The radius follows an egg profile — narrow attachment, wide belly at
    ~55% of the run, and a blunt rounded tip — which is what keeps leaves
    reading as separate clay pieces instead of one fused fan.
    """
    for step in range(steps + 1):
        t = step / steps
        # Slight outward bow so leaves read as leaning away from the centre.
        x = base[0] + (tip[0] - base[0]) * t
        y = base[1] + (tip[1] - base[1]) * (t ** 0.94)
        belly = math.sin(math.pi * min(1.0, t / 0.5) * 0.5) if t < 0.5 \
            else math.cos(math.pi * (t - 0.5) / 0.5 * 0.5)
        r = r_max * (0.55 + 0.45 * belly)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=255)


def build_sprout() -> Image.Image:
    """Suma's sprout rosette: five blunt leaves, deliberately asymmetric.

    Original composition — centre leaf leans 1.5% right, the mid-right leaf
    is the tallest sibling, the outer-left leaf sits lowest. Content fills
    ~84% of the card height so the quad carries almost no dead margin.
    """
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(mask)
    cx = CANVAS / 2.0

    scale = CANVAS / 512.0
    # (base_dx, base_y, tip_dx, tip_y, r_max) in 512-space. Bases cluster at
    # a narrow crown so the leaves separate for most of their length. The
    # whole rosette is deliberately SQUAT — content height ~0.72 of width —
    # so a carpet of these reads as ground-hugging sprouts, never celery.
    lobes = [
        # outer left — lowest, roundest
        (-26.0, 468.0, -202.0, 322.0, 45.0),
        # outer right — a touch higher than outer left
        (26.0, 470.0, 206.0, 310.0, 46.0),
        # mid left
        (-16.0, 470.0, -118.0, 214.0, 52.0),
        # mid right — the tallest supporting leaf (asymmetry signature)
        (16.0, 470.0, 126.0, 206.0, 54.0),
        # centre — dominant, slight right lean
        (0.0, 470.0, 2.0, 158.0, 58.0),
    ]
    for base_dx, base_y, tip_dx, tip_y, r_max in lobes:
        lobe_circles(
            draw,
            (cx + base_dx * scale, base_y * scale),
            (cx + tip_dx * scale, tip_y * scale),
            r_max * scale,
        )
    # The shared palm mass: the reference tuft is a FAT fused body whose
    # leaves separate only in the upper half — shallow finger notches in one
    # clay piece, never five loose leaves. The palm reaches high enough to
    # fuse every lobe's lower run and wide enough to swallow their bases.
    draw.ellipse([cx - 115.0 * scale, 380.0 * scale,
                  cx + 115.0 * scale, 500.0 * scale], fill=255)
    return mask


def shade(mask_small: Image.Image) -> Image.Image:
    """Apply the baked vertical value gradient inside the silhouette."""
    width, height = mask_small.size
    alpha = mask_small.load()
    # Content bounds drive the gradient so padding does not dilute it.
    bbox = mask_small.getbbox()
    top = bbox[1] if bbox else 0
    bottom = bbox[3] if bbox else height
    output = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    px = output.load()
    for y in range(height):
        t = 0.0 if bottom == top else (y - top) / float(bottom - top)
        t = min(1.0, max(0.0, t))
        value = GRADIENT_TOP + (GRADIENT_BASE - GRADIENT_TOP) * t
        tone = round(255.0 * value)
        for x in range(width):
            a = alpha[x, y]
            if a:
                px[x, y] = (tone, tone, tone, a)
    return output


def report(name: str, image: Image.Image) -> None:
    width, height = image.size
    px = image.load()
    solid = sum(
        1 for y in range(height) for x in range(width) if px[x, y][3] > 250
    )
    soft = sum(
        1 for y in range(height) for x in range(width)
        if 4 < px[x, y][3] <= 250
    )
    bbox = image.getbbox()
    print(f"{name}: {width}x{height} content={bbox} "
          f"solid={solid} softedge={soft} "
          f"gradient={GRADIENT_TOP:.2f}->{GRADIENT_BASE:.2f}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mask = build_sprout().resize((SIZE, SIZE), Image.LANCZOS)
    sprite = shade(mask)
    path = OUT_DIR / "tuft_sprout.png"
    sprite.save(path)
    report("tuft_sprout", sprite)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
