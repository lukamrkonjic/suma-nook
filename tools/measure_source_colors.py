"""Report the distinct colours a source GLB is actually painted with.

Run inside Blender. The importer matches colour per connected component, which
scatters one source colour across several palette slots and collapses different
source colours into one. Deciding that properly needs the source's real colour
clusters first, so this measures them: every face's sampled colour, merged into
groups that a viewer would read as "the same colour".

    blender --background --factory-startup --python tools/measure_source_colors.py \
        -- --source model.glb [--clusters 8]
"""

from __future__ import annotations

import argparse
import colorsys
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

import prepare_model_import as P  # noqa: E402


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--clusters", type=int, default=8)
    # A wide window merges the shaded half of a surface with its lit half,
    # which is exactly the distinction that has to survive. 7 degrees of hue
    # keeps orange wood apart from gold fittings.
    parser.add_argument("--hue-window", type=float, default=0.02)
    parser.add_argument("--lum-window", type=float, default=0.12)
    parser.add_argument("--report", type=Path)
    return parser.parse_args(argv)


def face_colors(mesh_object) -> list[tuple[int, Vector]]:
    """One sampled colour per face, with its area."""
    mesh = mesh_object.data
    samples = P.sampled_materials(mesh_object)
    out = []
    for polygon in mesh.polygons:
        color = P.average_component_color(mesh, [polygon.index], samples)
        out.append((polygon.index, color, polygon.area))
    return out


def _srgb(color) -> tuple[float, float, float]:
    return tuple(P._srgb_channel(max(0.0, float(c))) for c in color)


def cluster(entries, target: int, hue_window: float, lum_window: float):
    """Merge faces into perceptual colour groups, largest-area first.

    Plain k-means on RGB splits a single painted surface into its lit and shaded
    halves, which is the failure the importer already has. Merging by distance
    in hue/saturation/value keeps a surface together while still separating two
    genuinely different paints.
    """
    groups: list[dict] = []
    for _, color, area in entries:
        srgb = _srgb(color)
        hue, lum, sat = colorsys.rgb_to_hls(*srgb)
        placed = False
        for group in groups:
            ghue, glum, gsat = group["hls"]
            hue_gap = abs(hue - ghue)
            hue_gap = min(hue_gap, 1.0 - hue_gap)
            # A near-grey has a meaningless hue, so compare it on value alone.
            chromatic = sat > 0.18 and gsat > 0.18
            if chromatic:
                same = hue_gap < hue_window and abs(lum - glum) < lum_window
            else:
                same = (
                    sat <= 0.18
                    and gsat <= 0.18
                    and abs(lum - glum) < lum_window
                )
            if same:
                group["faces"] += 1
                group["area"] += area
                weight = area / max(1.0e-9, group["area"])
                group["hls"] = tuple(
                    g + (n - g) * weight for g, n in zip(group["hls"], (hue, lum, sat))
                )
                group["rgb"] = tuple(
                    g + (n - g) * weight for g, n in zip(group["rgb"], srgb)
                )
                placed = True
                break
        if not placed:
            groups.append(
                {
                    "faces": 1,
                    "area": area,
                    "hls": (hue, lum, sat),
                    "rgb": srgb,
                }
            )
    groups.sort(key=lambda g: -g["faces"])
    return groups[:target]


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    mesh_object = next(
        o for o in bpy.context.scene.objects if o.type == "MESH"
    )
    entries = face_colors(mesh_object)
    groups = cluster(
        entries, arguments.clusters, arguments.hue_window, arguments.lum_window
    )
    total = sum(g["faces"] for g in groups)
    print(f"SOURCE {arguments.source.name}: {len(entries)} faces")
    payload = []
    for group in groups:
        red, green, blue = group["rgb"]
        hue, lum, sat = group["hls"]
        share = group["faces"] / max(1, len(entries))
        print(
            f"  faces={group['faces']:4} ({share:5.1%})  "
            f"sRGB=({red:.2f},{green:.2f},{blue:.2f})  "
            f"hue={hue * 360:5.1f} sat={sat:.2f} lum={lum:.2f}"
        )
        payload.append(
            {
                "faces": group["faces"],
                "share": share,
                "srgb": [red, green, blue],
                "hue": hue * 360.0,
                "saturation": sat,
                "luminance": lum,
            }
        )
    print(f"  ({total}/{len(entries)} faces in the reported groups)")
    if arguments.report:
        arguments.report.write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
