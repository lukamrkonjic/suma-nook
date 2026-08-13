"""Split the authored open Worldheart wardrobe into a body and hinged doors.

Run with Blender in background mode. The source export is a single mesh made
from many intentionally disconnected low-poly pieces; spatial separation at
the front of the cabinet is stable and lets us preserve the exact authored
materials while restoring useful animation pivots.
"""

import bpy
import sys
from mathutils import Vector


arguments = sys.argv[sys.argv.index("--") + 1 :]
source_path, output_path = arguments

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source_path)
source = max(
    (item for item in bpy.context.scene.objects if item.type == "MESH"),
    key=lambda item: len(item.data.polygons),
)

bpy.context.view_layer.objects.active = source
source.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
pieces = [item for item in bpy.context.selected_objects if item.type == "MESH"]


def world_bounds(item):
    corners = [item.matrix_world @ Vector(corner) for corner in item.bound_box]
    minimum = Vector(tuple(min(corner[axis] for corner in corners) for axis in range(3)))
    maximum = Vector(tuple(max(corner[axis] for corner in corners) for axis in range(3)))
    return minimum, maximum


groups = {"body": [], "left": [], "right": []}
for piece in pieces:
    minimum, maximum = world_bounds(piece)
    center = (minimum + maximum) * 0.5
    # The cabinet body stops at Y=-0.118. Only the two authored open doors
    # project farther toward the player, so this cleanly retains hinges,
    # windows, handles, and all of their decorative loose pieces.
    if minimum.y < -0.125:
        groups["left" if center.x < 0.0 else "right"].append(piece)
    else:
        groups["body"].append(piece)


def join_group(group_name, object_name):
    bpy.ops.object.select_all(action="DESELECT")
    for item in groups[group_name]:
        item.select_set(True)
    bpy.context.view_layer.objects.active = groups[group_name][0]
    bpy.ops.object.join()
    result = bpy.context.active_object
    result.name = object_name
    result.data.name = object_name + "Mesh"
    return result


body = join_group("body", "WardrobeBody")
left = join_group("left", "WardrobeDoorLeft")
right = join_group("right", "WardrobeDoorRight")

# Preserve the exact open-pose geometry while relocating object origins to the
# physical hinge lines. Godot can now swing each door without deforming it.
for door, hinge in (
    (left, Vector((-0.225, -0.100, 0.0))),
    (right, Vector((0.225, -0.100, 0.0))),
):
    bpy.context.scene.cursor.location = hinge
    bpy.context.view_layer.objects.active = door
    door.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    door.select_set(False)

root = bpy.data.objects.new("WorldheartWardrobeOpen", None)
bpy.context.collection.objects.link(root)
for item in (body, left, right):
    item.parent = root

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
body.select_set(True)
left.select_set(True)
right.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format="GLB",
    use_selection=True,
    export_apply=False,
    export_yup=True,
)

print(
    "HINGED_WARDROBE",
    {name: len(items) for name, items in groups.items()},
    output_path,
)
