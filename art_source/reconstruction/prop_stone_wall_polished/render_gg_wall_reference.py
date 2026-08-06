"""Render the audited Garden Galaxy dry-stone mesh as design evidence.

The source GLB is read from the private technical-audit export and is never
copied into Suma's runtime assets.  This neutral render records the observed
course rhythm, irregular silhouette, and thickness used by the procedural
reconstruction contract.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 2:
        raise SystemExit("usage: blender --python render_gg_wall_reference.py -- INPUT.glb OUTPUT.png")
    source = Path(args[0]).resolve()
    output = Path(args[1]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [
        obj for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.name != "Cube"
    ]
    if not meshes:
        raise RuntimeError(f"No evidence mesh found in {source}")

    stone = bpy.data.materials.new("GG evidence stone")
    stone.diffuse_color = (0.70, 0.65, 0.55, 1.0)
    stone.roughness = 0.82
    for obj in meshes:
        obj.data.materials.clear()
        obj.data.materials.append(stone)
        obj.rotation_euler.z = -math.pi * 0.5

    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    center = (lower + upper) * 0.5
    for obj in meshes:
        obj.location -= Vector((center.x, center.y, lower.z))

    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.color = (0.055, 0.06, 0.055)

    bpy.ops.object.light_add(type="AREA", location=(-2.5, -3.0, 4.2))
    key = bpy.context.object
    key.data.energy = 700.0
    key.data.shape = "DISK"
    key.data.size = 4.0
    _look_at(key, Vector((0.0, 0.0, 0.45)))

    bpy.ops.object.light_add(type="AREA", location=(3.0, 1.5, 2.0))
    fill = bpy.context.object
    fill.data.energy = 260.0
    fill.data.size = 3.0
    _look_at(fill, Vector((0.0, 0.0, 0.45)))

    bpy.ops.object.camera_add(location=(2.25, -3.4, 1.85))
    camera = bpy.context.object
    camera.data.lens = 58.0
    _look_at(camera, Vector((0.0, 0.0, 0.43)))
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    # A transparent field lets the intake gate isolate the exact wall
    # silhouette instead of mistaking a full-frame floor plane for subject.
    scene.render.film_transparent = True
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    print(f"GG_WALL_REFERENCE={output}")


if __name__ == "__main__":
    main()
