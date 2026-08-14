"""Merge the wardrobe's two state models into a single asset.

Run inside Blender:

    blender --background --factory-startup --python tools/merge_wardrobe_states.py -- \
        --closed assets/3d/reworked/worldheart_wardrobe_closed.glb \
        --open   assets/3d/reworked/worldheart_wardrobe_hinged.glb \
        --output assets/3d/reworked/prop_gift_wardrobe.glb

Two separate assets meant two Asset Studio entries, two things to keep in visual
sync, and a presenter that instantiated both and swapped instances mid-swing.
One asset with both states as sub-hierarchies fixes the packaging without
touching the geometry:

    PropGiftWardrobe
      StateClosed/...                 shown while shut
      StateOpen/...                   shown while opening and open
        WardrobeDoorLeft, WardrobeDoorRight

The game shows one state group at a time and animates the doors inside
StateOpen, which is what it already did -- only now it toggles child nodes of
one instance instead of juggling two.

Deliberately copies each import's hierarchy AS IS. An earlier attempt to carve
doors out of the closed model baked object transforms to get tidy nodes, and
that reintroduced rotations, moved the geometry out from under its own selection
bounds, and left the cabinet facing backwards in game. Nothing here re-derives a
hinge or a facing: both models already import correctly on their own, so they
are re-parented untouched.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

ROOT_NAME = "PropGiftWardrobe"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--closed", required=True, type=Path)
    parser.add_argument("--open", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def import_state(path: Path, state_name: str) -> list[bpy.types.Object]:
    """Imports a glb and returns its objects, with the top level renamed."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    added = [o for o in bpy.context.scene.objects if o not in before]
    tops = [o for o in added if o.parent is None]
    if not tops:
        raise RuntimeError("%s imported nothing" % path.name)
    # The hinged model imports as TWO roots -- glTF's own "world" node plus the
    # root the splitter added -- so gather them under one holder rather than
    # assuming a single top level.
    holder = bpy.data.objects.new(state_name, None)
    bpy.context.scene.collection.objects.link(holder)
    for top in tops:
        top.parent = holder
        top.matrix_parent_inverse.identity()
    return added + [holder]


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    closed_objects = import_state(arguments.closed, "StateClosed")
    open_objects = import_state(arguments.open, "StateOpen")

    for name in ("WardrobeDoorLeft", "WardrobeDoorRight"):
        if bpy.data.objects.get(name) is None:
            raise RuntimeError(
                "%s is missing from the open model; the swing depends on it"
                % name
            )

    root = bpy.data.objects.new(ROOT_NAME, None)
    bpy.context.scene.collection.objects.link(root)
    for state_name in ("StateClosed", "StateOpen"):
        state_root = bpy.data.objects[state_name]
        state_root.parent = root
        # Root sits at the origin, so no compensation is needed and none is
        # applied -- leaving each state exactly where its own import put it.
        state_root.matrix_parent_inverse.identity()

    bpy.context.view_layer.update()
    print(
        "MERGED closed_objects=%d open_objects=%d"
        % (len(closed_objects), len(open_objects))
    )
    for item in bpy.context.scene.objects:
        print(
            "NODE %-24s %-7s parent=%s"
            % (item.name, item.type, item.parent.name if item.parent else "-")
        )

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
    )
    print(f"MERGE_OUT={arguments.output}")


if __name__ == "__main__":
    main()
