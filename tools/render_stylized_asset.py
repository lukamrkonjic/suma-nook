"""Render a neutral review turntable frame for a prepared GLB."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(arguments)


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source.resolve()))
    meshes = [item for item in bpy.context.scene.objects if item.type == "MESH"]
    minimum = Vector(
        tuple(
            min((item.matrix_world @ vertex.co)[axis] for item in meshes for vertex in item.data.vertices)
            for axis in range(3)
        )
    )
    maximum = Vector(
        tuple(
            max((item.matrix_world @ vertex.co)[axis] for item in meshes for vertex in item.data.vertices)
            for axis in range(3)
        )
    )
    center = (minimum + maximum) * 0.5
    size = maximum - minimum

    bpy.ops.mesh.primitive_plane_add(size=max(size.x, size.y) * 4.5)
    floor = bpy.context.object
    floor.location.z = minimum.z - 0.006
    floor_material = bpy.data.materials.new("ReviewFloor")
    floor_material.diffuse_color = (0.78, 0.75, 0.66, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(size.x, size.y, size.z) * 1.45
    camera.location = center + Vector((1.45, -1.75, 1.22)) * max(size.length, 1.0)
    look_at(camera, center + Vector((0.0, 0.0, size.z * 0.04)))

    light_data = bpy.data.lights.new("Key", "AREA")
    light_data.energy = 800.0
    light_data.shape = "DISK"
    light_data.size = max(size.length, 1.0) * 2.2
    light = bpy.data.objects.new("Key", light_data)
    bpy.context.collection.objects.link(light)
    light.location = center + Vector((-1.6, -2.0, 3.0)) * max(size.length, 1.0)
    look_at(light, center)

    world = bpy.data.worlds.new("ReviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.78,
        0.75,
        0.68,
        1.0,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
    bpy.context.scene.world = world

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(arguments.output.resolve())
    scene.view_settings.look = "AgX - Medium High Contrast"
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("Rendered", arguments.output)


if __name__ == "__main__":
    main()
