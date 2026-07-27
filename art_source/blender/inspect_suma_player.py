"""Inspect and render the supplied Suma player GLB without modifying it."""

import json
import math
import os
import sys

import bpy
from mathutils import Vector


def cli_value(flag: str, default: str = "") -> str:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if flag not in args:
        return default
    index = args.index(flag)
    return args[index + 1] if index + 1 < len(args) else default


source_path = os.path.abspath(cli_value("--source"))
render_path = os.path.abspath(cli_value("--render"))
if not source_path or not os.path.isfile(source_path):
    raise RuntimeError(f"Missing source GLB: {source_path}")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source_path)

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
animations = sorted(action.name for action in bpy.data.actions)

minimum = Vector((math.inf, math.inf, math.inf))
maximum = Vector((-math.inf, -math.inf, -math.inf))
triangles = 0
vertices = 0
for obj in meshes:
    vertices += len(obj.data.vertices)
    triangles += sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    for corner in obj.bound_box:
        point = obj.matrix_world @ Vector(corner)
        minimum.x = min(minimum.x, point.x)
        minimum.y = min(minimum.y, point.y)
        minimum.z = min(minimum.z, point.z)
        maximum.x = max(maximum.x, point.x)
        maximum.y = max(maximum.y, point.y)
        maximum.z = max(maximum.z, point.z)

report = {
    "source": source_path,
    "objects": [
        {
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else "",
            "location": list(obj.location),
            "rotation": list(obj.rotation_euler),
            "scale": list(obj.scale),
            "vertices": len(obj.data.vertices) if obj.type == "MESH" else 0,
            "polygons": len(obj.data.polygons) if obj.type == "MESH" else 0,
            "materials": [slot.material.name if slot.material else "" for slot in obj.material_slots],
        }
        for obj in bpy.context.scene.objects
        if obj.type in {"MESH", "ARMATURE", "EMPTY"}
    ],
    "mesh_count": len(meshes),
    "armature_count": len(armatures),
    "animations": animations,
    "vertices": vertices,
    "triangles": triangles,
    "bounds_min": list(minimum),
    "bounds_max": list(maximum),
    "dimensions": list(maximum - minimum),
}
components = []
for obj in meshes:
    adjacency = {vertex.index: [] for vertex in obj.data.vertices}
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    unvisited = set(adjacency)
    while unvisited:
        seed = unvisited.pop()
        pending = [seed]
        indices = [seed]
        while pending:
            current = pending.pop()
            for neighbor in adjacency[current]:
                if neighbor in unvisited:
                    unvisited.remove(neighbor)
                    pending.append(neighbor)
                    indices.append(neighbor)
        points = [obj.matrix_world @ obj.data.vertices[index].co for index in indices]
        comp_min = Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        )
        comp_max = Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        )
        components.append(
            {
                "mesh": obj.name,
                "vertices": len(indices),
                "min": list(comp_min),
                "max": list(comp_max),
                "center": list((comp_min + comp_max) * 0.5),
            }
        )
report["components"] = sorted(components, key=lambda item: item["vertices"], reverse=True)
print("SUMA_PLAYER_REPORT=" + json.dumps(report, separators=(",", ":")))

# Neutral studio render for visual inspection.
world = bpy.context.scene.world or bpy.data.worlds.new("World")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.79, 0.80, 0.80, 1.0)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8

center = (minimum + maximum) * 0.5
dimensions = maximum - minimum
size = max(dimensions.x, dimensions.y, dimensions.z)

camera_data = bpy.data.cameras.new("InspectionCamera")
camera = bpy.data.objects.new("InspectionCamera", camera_data)
bpy.context.scene.collection.objects.link(camera)
bpy.context.scene.camera = camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = max(size * 1.35, 1.0)
camera.location = center + Vector((size * 2.2, -size * 2.8, size * 1.8))
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()

key_data = bpy.data.lights.new("Key", "AREA")
key_data.energy = 950.0
key_data.shape = "DISK"
key_data.size = size * 2.0
key = bpy.data.objects.new("Key", key_data)
bpy.context.scene.collection.objects.link(key)
key.location = center + Vector((-size * 2.0, -size * 2.0, size * 3.0))
key.rotation_euler = (center - key.location).to_track_quat("-Z", "Y").to_euler()

fill_data = bpy.data.lights.new("Fill", "AREA")
fill_data.energy = 500.0
fill_data.size = size * 2.5
fill = bpy.data.objects.new("Fill", fill_data)
bpy.context.scene.collection.objects.link(fill)
fill.location = center + Vector((size * 2.5, size * 1.5, size * 1.8))
fill.rotation_euler = (center - fill.location).to_track_quat("-Z", "Y").to_euler()

bpy.context.scene.render.engine = "BLENDER_EEVEE"
bpy.context.scene.render.resolution_x = 700
bpy.context.scene.render.resolution_y = 700
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.image_settings.file_format = "PNG"
bpy.context.scene.render.film_transparent = False
bpy.context.scene.render.filepath = render_path
bpy.context.scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(render_path)[0] + "_inspection.blend")
bpy.ops.render.render(write_still=True)
