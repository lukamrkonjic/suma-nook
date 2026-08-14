"""Render the open wardrobe with its door geometry highlighted.

Run inside Blender:

    blender --background --factory-startup --python tools/inspect_wardrobe_doors.py -- \
        --source wardrobe-open.glb --output doors.png

The supplied model is one welded mesh of 82 connected components with no door
objects, so which faces belong to which door has to be established by looking
rather than by trusting a heuristic. Numeric guesses at the hinge line from
component bounds gave contradictory answers on panels that sit diagonally, which
is exactly the case here.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

# A door protrudes in front of the cabinet's front face; the body does not.
DOOR_FORWARD_LIMIT = -0.15


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--forward-limit", type=float, default=DOOR_FORWARD_LIMIT)
    parser.add_argument(
        "--doors-only",
        action="store_true",
        help="Hide the body, to check each door is a complete slab.",
    )
    return parser.parse_args(argv)


def components(mesh: bmesh.types.BMesh) -> list[list[bmesh.types.BMFace]]:
    seen: set[int] = set()
    found: list[list[bmesh.types.BMFace]] = []
    for face in mesh.faces:
        if face.index in seen:
            continue
        stack = [face]
        seen.add(face.index)
        group: list[bmesh.types.BMFace] = []
        while stack:
            current = stack.pop()
            group.append(current)
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        seen.add(neighbour.index)
                        stack.append(neighbour)
        found.append(group)
    return found


def flat_material(name: str, color: tuple[float, float, float]):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = next(
        node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"
    )
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = 0.9
    return material


def main() -> None:
    global arguments
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    mesh_object = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mesh = mesh_object.data

    mesh.materials.clear()
    mesh.materials.append(flat_material("Body", (0.78, 0.76, 0.70)))
    mesh.materials.append(flat_material("DoorLeft", (0.85, 0.18, 0.15)))
    mesh.materials.append(flat_material("DoorRight", (0.15, 0.35, 0.85)))

    working = bmesh.new()
    working.from_mesh(mesh)
    working.faces.ensure_lookup_table()
    assignment: dict[int, int] = {}
    for group in components(working):
        points = [vertex.co for face in group for vertex in face.verts]
        forward = min(point.y for point in points) < arguments.forward_limit
        centre_x = sum(point.x for point in points) / len(points)
        slot = 0 if not forward else (1 if centre_x < 0.0 else 2)
        for face in group:
            assignment[face.index] = slot
    working.free()
    for polygon in mesh.polygons:
        polygon.material_index = assignment.get(polygon.index, 0)
    mesh.update()
    if arguments.doors_only:
        strip = bmesh.new()
        strip.from_mesh(mesh)
        strip.faces.ensure_lookup_table()
        body_faces = [f for f in strip.faces if assignment.get(f.index, 0) == 0]
        bmesh.ops.delete(strip, geom=body_faces, context="FACES")
        strip.to_mesh(mesh)
        strip.free()
        mesh.update()
    door_counts = {1: 0, 2: 0}
    for slot in assignment.values():
        if slot in door_counts:
            door_counts[slot] += 1
    print("DOORS left=%d right=%d" % (door_counts[1], door_counts[2]))

    # Three-quarter view from the front, so both doors and the cavity read.
    target = Vector((0.0, 0.0, 0.05))
    camera_data = bpy.data.cameras.new("InspectCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.5
    camera = bpy.data.objects.new("InspectCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = target + Vector((1.1, -1.5, 0.95))
    direction = (target - camera.location).normalized()
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("InspectSun", type="SUN")
    sun_data.energy = 3.4
    sun = bpy.data.objects.new("InspectSun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(58.0), 0.0, math.radians(-38.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.filepath = str(arguments.output)
    bpy.ops.render.render(write_still=True)
    print(f"INSPECT_OUT={arguments.output}")


if __name__ == "__main__":
    main()
