"""Move a glb so its lowest point sits at the origin, and re-export.

Run inside Blender:

    blender --background --factory-startup --python tools/ground_asset.py -- \
        --source in.glb --output out.glb

Everything that comes through prepare_model_import.py is grounded by
ground_under_root, so a model that skips that path arrives centre-origined and
sinks through whatever it stands on -- and needs a hand-tuned hoist constant in
whatever places it. This does the same for assets that are prepared by other
means, such as the wardrobe's hinged split.

Only top-level objects move. Translating each mesh instead would break a
hierarchy whose children carry meaningful origins, which is exactly what the
wardrobe's door nodes are.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def lowest_point() -> float:
    lowest = None
    for item in bpy.context.scene.objects:
        if item.type != "MESH":
            continue
        for vertex in item.data.vertices:
            height = (item.matrix_world @ vertex.co).z
            lowest = height if lowest is None else min(lowest, height)
    if lowest is None:
        raise RuntimeError("No mesh geometry to ground")
    return lowest


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    bpy.context.view_layer.update()

    before = lowest_point()
    for item in bpy.context.scene.objects:
        if item.parent is None:
            item.location.z -= before
    bpy.context.view_layer.update()
    after = lowest_point()
    print("GROUNDED %s min_z %.4f -> %.4f" % (arguments.source.name, before, after))

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
    )
    print(f"GROUND_OUT={arguments.output}")


if __name__ == "__main__":
    main()
