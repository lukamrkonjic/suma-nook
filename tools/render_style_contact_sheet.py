"""Render several GLBs into one neutral side-by-side frame.

Style judgements need the models at the same scale, light, and camera in a
single image -- flipping between separate renders hides exactly the
differences that matter. Each source is imported, grounded, and spaced along
X in the order given, then shot with one wide orthographic camera.

Run headless:
  blender --background --factory-startup --python tools/render_style_contact_sheet.py \
    -- --sources a.glb b.glb --labels before after --output sheet.png
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", nargs="+", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--gap", type=float, default=0.35, help="Spacing as a fraction of slot width.")
    parser.add_argument("--height", type=int, default=760)
    parser.add_argument("--elevation", type=float, default=1.05)
    return parser.parse_args(arguments)


def look_at(item: bpy.types.Object, target: Vector) -> None:
    item.rotation_euler = (target - item.location).to_track_quat("-Z", "Y").to_euler()


def import_grounded(path: Path) -> tuple[list[bpy.types.Object], Vector, Vector]:
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    fresh = [item for item in bpy.context.scene.objects if item not in existing]
    # glTF nests meshes under empties, so only the parentless roots may be
    # moved; shifting a child would double-apply the offset.
    roots = [item for item in fresh if item.parent is None]
    points = [
        item.matrix_world @ vertex.co
        for item in fresh
        if item.type == "MESH"
        for vertex in item.data.vertices
    ]
    minimum = Vector(tuple(min(p[axis] for p in points) for axis in range(3)))
    maximum = Vector(tuple(max(p[axis] for p in points) for axis in range(3)))
    return roots, minimum, maximum


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    imported = []
    for path in arguments.sources:
        if not path.is_file():
            raise SystemExit(f"Missing source: {path}")
        imported.append(import_grounded(path))

    slot = max(
        max(maximum.x - minimum.x, maximum.y - minimum.y)
        for _, minimum, maximum in imported
    )
    tallest = max(maximum.z - minimum.z for _, minimum, maximum in imported)
    step = slot * (1.0 + arguments.gap)
    span = step * len(imported)

    for index, (roots, minimum, maximum) in enumerate(imported):
        centre = (minimum + maximum) * 0.5
        offset = Vector(
            (
                (index - (len(imported) - 1) * 0.5) * step - centre.x,
                -centre.y,
                -minimum.z,
            )
        )
        for item in roots:
            item.location += offset

    bpy.ops.mesh.primitive_plane_add(size=span * 3.0)
    floor = bpy.context.object
    floor.location.z = -0.004
    floor_material = bpy.data.materials.new("SheetFloor")
    floor_material.diffuse_color = (0.78, 0.75, 0.66, 1.0)
    floor.data.materials.append(floor_material)

    focus = Vector((0.0, 0.0, tallest * 0.45))
    camera_data = bpy.data.cameras.new("SheetCamera")
    camera = bpy.data.objects.new("SheetCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = span * 1.04
    reach = max(span, tallest * 3.0)
    camera.location = focus + Vector((0.9, -2.2, arguments.elevation)) * reach
    look_at(camera, focus)

    light_data = bpy.data.lights.new("Key", "AREA")
    light_data.energy = 900.0 * max(span, 1.0) ** 2
    light_data.shape = "DISK"
    light_data.size = span * 1.6
    light = bpy.data.objects.new("Key", light_data)
    bpy.context.collection.objects.link(light)
    light.location = focus + Vector((-1.1, -1.6, 2.4)) * reach
    look_at(light, focus)

    world = bpy.data.worlds.new("SheetWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.75, 0.68, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
    bpy.context.scene.world = world

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_y = arguments.height
    scene.render.resolution_x = int(
        arguments.height * (span / max(tallest * 1.75, span * 0.28))
    )
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(arguments.output.resolve())
    bpy.ops.render.render(write_still=True)
    print(f"CONTACT_SHEET={arguments.output}")


if __name__ == "__main__":
    main()
