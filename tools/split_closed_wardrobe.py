"""Split the CLOSED wardrobe's doors into hinged nodes, rest pose shut.

Run inside Blender:

    blender --background --factory-startup --python tools/split_closed_wardrobe.py -- \
        --source assets/3d/reworked/worldheart_wardrobe_closed.glb \
        --output assets/3d/reworked/prop_gift_wardrobe.glb [--preview out.png]

One model for both states, doors carved from the closed pose (rest = shut,
animate to open), replacing the old two-model swap and its top-of-door gap.

The open-model splitter keyed on doors protruding forward of the cabinet, which
closed doors do not, and connectivity is useless here anyway: this mesh arrives
fragmented into 998 components, most a single face. So the doors are selected by
REGION -- a box in mesh-local coordinates -- and the box was tuned by rendering
the selection until it contained exactly the doors. Front is -y; z is vertical
in mesh-local space (the grounding offset lives on the object transform).

Each door keeps its own geometry re-centred on its hinge line (outer edge, at
the frame stile) so a plain rotation.y swings it. --preview renders the split
tinted, doors part-open, for eyeball verification.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

# Tuned against renders; see module docstring. Mesh-local coordinates.
# -0.04, not the -0.09 first tried: the door slabs' BACK faces sit near -0.07,
# and excluding them exported doors with no backs -- hollow frames when open.
DOOR_FRONT_Y = 0.04
DOOR_X = (-0.263, 0.263)
# In BAKED coordinates (object transform applied to the mesh), which include the
# +0.5 grounding lift: the same door slab that spanned -0.365..0.418 mesh-local.
DOOR_Z = (0.135, 0.918)
SPLIT_X = 0.0
ROOT_NAME = "PropGiftWardrobe"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--front-y", type=float, default=DOOR_FRONT_Y)
    parser.add_argument("--x", type=float, nargs=2, default=list(DOOR_X))
    parser.add_argument("--z", type=float, nargs=2, default=list(DOOR_Z))
    parser.add_argument("--preview-yaw", type=float, default=55.0)
    return parser.parse_args(argv)


def face_role(mesh: bpy.types.Mesh, polygon, arguments) -> str:
    points = [mesh.vertices[index].co for index in polygon.vertices]
    if any(point.y < arguments.front_y for point in points):
        return "body"
    if any(
        point.x < arguments.x[0] or point.x > arguments.x[1] for point in points
    ):
        return "body"
    if any(
        point.z < arguments.z[0] or point.z > arguments.z[1] for point in points
    ):
        return "body"
    centre_x = sum(point.x for point in points) / len(points)
    return "left" if centre_x < SPLIT_X else "right"


def separate(source: bpy.types.Object, wanted: set[int], name: str):
    copy = source.copy()
    copy.data = source.data.copy()
    copy.name = name
    copy.data.name = name + "Mesh"
    bpy.context.scene.collection.objects.link(copy)
    working = bmesh.new()
    working.from_mesh(copy.data)
    working.faces.ensure_lookup_table()
    doomed = [face for face in working.faces if face.index not in wanted]
    bmesh.ops.delete(working, geom=doomed, context="FACES")
    working.to_mesh(copy.data)
    working.free()
    copy.data.update()
    return copy


def recentre_on_hinge(door: bpy.types.Object, hinge_x: float, hinge_y: float) -> None:
    offset = Vector((hinge_x, hinge_y, 0.0))
    working = bmesh.new()
    working.from_mesh(door.data)
    bmesh.ops.translate(working, verts=working.verts[:], vec=-offset)
    working.to_mesh(door.data)
    working.free()
    door.data.update()
    door.location = door.location + offset


def tint(objects, name: str, color) -> None:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = next(
        node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"
    )
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    for item in objects:
        item.data.materials.clear()
        item.data.materials.append(material)


def render_preview(output: Path) -> None:
    points: list[Vector] = []
    bpy.context.view_layer.update()
    for item in bpy.context.scene.objects:
        if item.type == "MESH":
            points += [item.matrix_world @ Vector(c) for c in item.bound_box]
    centre = sum(points, Vector()) / max(1, len(points))
    span = max(
        max(p.x for p in points) - min(p.x for p in points),
        max(p.y for p in points) - min(p.y for p in points),
        max(p.z for p in points) - min(p.z for p in points),
    )
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = span * 1.6
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = centre + Vector((span * 1.1, -span * 1.5, span * 0.95))
    camera.rotation_euler = (
        (centre - camera.location).normalized().to_track_quat("-Z", "Y").to_euler()
    )
    bpy.context.scene.camera = camera
    sun_data = bpy.data.lights.new("PreviewSun", type="SUN")
    sun_data.energy = 3.4
    sun = bpy.data.objects.new("PreviewSun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(58.0), 0.0, math.radians(-38.0))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    print(f"PREVIEW_OUT={output}")


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    source = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    # Bake the object transform into the vertices so every exported node carries
    # an IDENTITY rotation. Composing the source's matrix onto the door nodes
    # kept the glTF importer's axis-conversion rotation on them, and after the
    # round trip Godot saw doors whose local Y was horizontal: rotation.y folded
    # them over the top of the cabinet instead of swinging them.
    bpy.context.view_layer.update()
    # Order matters: capture the world matrix, unparent, THEN bake. Baking while
    # still parented and deleting the parent afterwards left the orphan with the
    # basis that had compensated for the parent -- reintroducing the very
    # rotation the bake removed, and the whole cabinet lay on its back in Godot.
    world_matrix = source.matrix_world.copy()
    source.parent = None
    source.matrix_basis.identity()
    source.data.transform(world_matrix)
    # And a half turn about vertical: with the transforms baked, the cabinet's
    # front (Blender -y) lands on glTF +Z, which is BACKWARD -- in game it faced
    # away from the camera, doors opening on the far side. The unbaked originals
    # faced -Z through the importer's node conversion.
    from mathutils import Matrix
    source.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    for other in list(bpy.context.scene.objects):
        if other is not source and other.type == "EMPTY":
            bpy.data.objects.remove(other, do_unlink=True)
    bpy.context.view_layer.update()
    mesh = source.data

    grouped: dict[str, set[int]] = {"body": set(), "left": set(), "right": set()}
    for polygon in mesh.polygons:
        grouped[face_role(mesh, polygon, arguments)].add(polygon.index)
    print(
        "SPLIT body=%d left=%d right=%d"
        % (len(grouped["body"]), len(grouped["left"]), len(grouped["right"]))
    )
    if not grouped["left"] or not grouped["right"]:
        raise RuntimeError("Both doors must be found before splitting")

    root = bpy.data.objects.new(ROOT_NAME, None)
    bpy.context.scene.collection.objects.link(root)
    body = separate(source, grouped["body"], "WardrobeBody")
    body.parent = root
    body.matrix_parent_inverse.identity()

    doors = []
    for side, node_name in (
        ("left", "WardrobeDoorLeft"),
        ("right", "WardrobeDoorRight"),
    ):
        door = separate(source, grouped[side], node_name)
        points = [
            mesh.vertices[index].co
            for face_index in grouped[side]
            for index in mesh.polygons[face_index].vertices
        ]
        # Hinge on the door's OUTER edge (at the frame stile), on its front
        # plane, so opening swings the free edge outward past the cabinet.
        hinge_x = (
            min(point.x for point in points)
            if side == "left"
            else max(point.x for point in points)
        )
        hinge_y = max(point.y for point in points)
        recentre_on_hinge(door, hinge_x, hinge_y)
        door.parent = root
        door.matrix_parent_inverse.identity()
        doors.append(door)
        print(
            "%s faces=%d hinge=(%.3f,%.3f)"
            % (node_name, len(grouped[side]), hinge_x, hinge_y)
        )

    bpy.data.objects.remove(source, do_unlink=True)

    if arguments.preview is not None:
        tint([body], "PreviewBody", (0.78, 0.76, 0.70))
        tint([doors[0]], "PreviewLeft", (0.85, 0.18, 0.15))
        tint([doors[1]], "PreviewRight", (0.15, 0.35, 0.85))
        # Part-open, so hinge placement errors are visible in the render.
        doors[0].rotation_mode = "XYZ"
        doors[1].rotation_mode = "XYZ"
        doors[0].rotation_euler.z = math.radians(-arguments.preview_yaw)
        doors[1].rotation_euler.z = math.radians(arguments.preview_yaw)
        render_preview(arguments.preview)
        return

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
    )
    print(f"SPLIT_OUT={arguments.output}")


if __name__ == "__main__":
    main()
