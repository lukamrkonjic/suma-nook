"""Give the imported hand lantern a lit interior, and put its frame on metal.

Run AFTER import_meshy_asset.py has palette-mapped the source:

    blender --background --factory-startup --python tools/build_glowing_lantern.py -- \
        --asset assets/3d/reworked/prop_hand_lantern.glb

Two corrections, both measured rather than guessed.

THE GLOW cannot come from the colour clustering. The lantern's glass panels and
its frame ribs land in the same cluster at every merge distance from 0.10 down
to 0.03 -- `wood_mid` holds 561 faces either way -- so there is no colour that
selects the panes. Rendering each slot in a vivid hue showed why the obvious
guess was wrong too: `sand_shadow` is the carry HANDLE, not the glass.

What does separate cleanly is geometry. Measuring side-facing faces across the
housing band gives two shells: the outer frame at radius 0.20-0.25, and an
inner shell at 0.17-0.19 -- the inside of the lantern, seen through the gaps
between the ribs. That inner shell is where a flame would sit, so it takes
`fire_yellow`, which MaterialLibrary.EMISSIVE already drives at energy 3.0. The
frame in front of it stays opaque and palette-correct, and the glow reads out
through the openings exactly as a real lantern does.

THE FRAME is neutral in the source -- its dominant cluster samples saturation
0.04, which is grey metal -- but hue is weighted hardest when matching, and hue
is meaningless noise at that saturation, so it resolved to the brown `wood_mid`.
The same trap put salmon inside the air conditioner. It is remapped to `metal`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

import glb_export  # noqa: E402

PALETTE = REPOSITORY_ROOT / "data" / "garden_galaxy_reference_palette.json"

## The housing band and the inner shell, as measured on this model. Faces
## outside these bounds are the cap, the base and the outer frame.
BAND_LOW = 0.32
BAND_HIGH = 0.68
INNER_RADIUS = 0.195
## A face this close to horizontal is a shelf inside the housing, not a wall.
SIDE_FACING = 0.55

GLOW_SLOT = "fire_yellow"
FRAME_FROM = "wood_mid"
FRAME_TO = "metal"


def palette_colour(token: str) -> tuple[float, float, float]:
    exact = json.loads(PALETTE.read_text(encoding="utf-8"))["exact"]
    value = exact[token].lstrip("#")
    srgb = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # Blender material colours are linear; the palette records sRGB.
    return tuple(
        c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", required=True)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    asset = Path(arguments.asset)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(asset))
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mesh = obj.data

    for material in mesh.materials:
        if material.name == FRAME_FROM:
            material.name = FRAME_TO
            material.diffuse_color = (*palette_colour(FRAME_TO), 1.0)
            if material.use_nodes:
                bsdf = material.node_tree.nodes.get("Principled BSDF")
                if bsdf is not None:
                    bsdf.inputs["Base Color"].default_value = (
                        *palette_colour(FRAME_TO), 1.0
                    )

    glow = bpy.data.materials.new(GLOW_SLOT)
    glow.use_nodes = True
    colour = palette_colour(GLOW_SLOT)
    glow.diffuse_color = (*colour, 1.0)
    bsdf = glow.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    # The offline render has no EMISSIVE table, so give it the same look the
    # game will produce; otherwise the review shows a dull yellow interior.
    bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 3.0
    mesh.materials.append(glow)
    glow_index = len(mesh.materials) - 1

    zmax = max((obj.matrix_world @ v.co).z for v in mesh.vertices)
    lit = 0
    for polygon in mesh.polygons:
        centre = obj.matrix_world @ polygon.center
        normal = (obj.matrix_world.to_3x3() @ polygon.normal).normalized()
        if not (BAND_LOW * zmax <= centre.z <= BAND_HIGH * zmax):
            continue
        if abs(normal.z) >= SIDE_FACING:
            continue
        if centre.xy.length > INNER_RADIUS:
            continue
        polygon.material_index = glow_index
        lit += 1
    mesh.update()

    glb_export.flatten_shading([obj])
    for scene_object in bpy.context.scene.objects:
        scene_object.select_set(True)
    glb_export.export_selected(asset)
    print("LANTERN %d faces now glow; frame remapped %s -> %s"
          % (lit, FRAME_FROM, FRAME_TO))


if __name__ == "__main__":
    main()
