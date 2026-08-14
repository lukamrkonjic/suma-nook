"""Split the open wardrobe's doors into hinged nodes the presenter can swing.

Run inside Blender:

    blender --background --factory-startup --python tools/build_wardrobe_hinged.py -- \
        --source wardrobe-open.glb \
        --output assets/3d/reworked/worldheart_wardrobe_hinged.glb

WorldheartPresenter animates the wardrobe by rotating two nodes it looks up by
name, `WardrobeDoorLeft` and `WardrobeDoorRight`, about their own Y axis:
rotation 0 is fully open and LEFT/RIGHT_DOOR_CLOSED_YAW is shut. The supplied
model is a single welded mesh with no door objects and no animation, so the doors
have to be separated and given origins on their hinge lines, otherwise they would
rotate about the model centre and swing through the cabinet.

Doors are identified by protruding in front of the body: measured on this model
the cabinet front sits at y -0.085 and every door component reaches past -0.15,
while nothing else does. Raising that limit to -0.09 pulled 21 faces of the
plinth into the left door, so the gap is real but not large.

The hinge edge is whichever of a door's two vertical extreme edges sits nearest
the cabinet's front plane, because a hinge lives in the door opening while the
free edge swings out in front of it. Two other rules were tried and rejected:
the door's own outermost edge in x is ambiguous when the panel is modelled at an
angle, and nearest-the-body's-front-corner picked opposite edges on the two
doors -- asymmetric, which cannot be right for a symmetric cabinet.

Prints the closed yaw for each door, which is what the presenter's constants must
be set to.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

import glb_export  # noqa: E402

DOOR_FORWARD_LIMIT = -0.15
ROOT_NAME = "WorldheartWardrobeHinged"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--forward-limit", type=float, default=DOOR_FORWARD_LIMIT)
    return parser.parse_args(argv)


def face_components(mesh: bmesh.types.BMesh) -> list[list[bmesh.types.BMFace]]:
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


def classify(mesh: bpy.types.Mesh, forward_limit: float) -> dict[int, str]:
    working = bmesh.new()
    working.from_mesh(mesh)
    working.faces.ensure_lookup_table()
    roles: dict[int, str] = {}
    for group in face_components(working):
        points = [vertex.co for face in group for vertex in face.verts]
        forward = min(point.y for point in points) < forward_limit
        centre_x = sum(point.x for point in points) / len(points)
        role = "body"
        if forward:
            role = "left" if centre_x < 0.0 else "right"
        for face in group:
            roles[face.index] = role
    working.free()
    return roles


def separate(source: bpy.types.Object, wanted: set[int], name: str):
    """A new object holding only the given faces of the source."""
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


def vertical_edge_lines(points: list[Vector]) -> tuple[Vector, Vector]:
    """The two vertical extreme edges of a door slab, as XY points.

    A door is a thin slab standing upright, so projecting to XY collapses it to a
    line segment whose ends are the hinge and free edges.
    """
    projected = [Vector((point.x, point.y)) for point in points]
    best_pair = (projected[0], projected[0])
    best_distance = -1.0
    for index, first in enumerate(projected):
        for second in projected[index + 1 :]:
            distance = (first - second).length_squared
            if distance > best_distance:
                best_distance = distance
                best_pair = (first, second)
    return best_pair


def panel_normal(points: list[Vector]) -> Vector:
    """The XY normal of a thin upright slab: its least-spread footprint axis.

    Averaging face normals cannot work here -- a slab's two faces point opposite
    ways and cancel -- so this uses the spread of the footprint instead. For a
    2x2 covariance the minor axis is available in closed form.
    """
    centre_x = sum(point.x for point in points) / len(points)
    centre_y = sum(point.y for point in points) / len(points)
    xx = sum((point.x - centre_x) ** 2 for point in points)
    yy = sum((point.y - centre_y) ** 2 for point in points)
    xy = sum((point.x - centre_x) * (point.y - centre_y) for point in points)
    # Smaller eigenvalue of [[xx, xy], [xy, yy]], and its eigenvector.
    middle = (xx + yy) * 0.5
    spread = math.sqrt(maxf(0.0, ((xx - yy) * 0.5) ** 2 + xy * xy))
    minor = middle - spread
    if abs(xy) > 1.0e-9:
        axis = Vector((minor - yy, xy))
    else:
        axis = Vector((1.0, 0.0)) if xx <= yy else Vector((0.0, 1.0))
    return axis.normalized()


def maxf(a: float, b: float) -> float:
    return a if a > b else b


def _render(output: Path) -> None:
    target = Vector((0.0, 0.0, 0.05))
    camera_data = bpy.data.cameras.new("VerifyCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.4
    camera = bpy.data.objects.new("VerifyCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = target + Vector((1.1, -1.5, 0.95))
    camera.rotation_euler = (
        (target - camera.location).normalized().to_track_quat("-Z", "Y").to_euler()
    )
    bpy.context.scene.camera = camera
    sun_data = bpy.data.lights.new("VerifySun", type="SUN")
    sun_data.energy = 3.4
    sun = bpy.data.objects.new("VerifySun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(58.0), 0.0, math.radians(-38.0))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    print(f"VERIFY_OUT={output}")


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    write_normals = glb_export.scene_authors_normals()
    source = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mesh = source.data
    roles = classify(mesh, arguments.forward_limit)

    grouped: dict[str, set[int]] = {"body": set(), "left": set(), "right": set()}
    for face_index, role in roles.items():
        grouped[role].add(face_index)
    print(
        "SPLIT body=%d left=%d right=%d"
        % (len(grouped["body"]), len(grouped["left"]), len(grouped["right"]))
    )
    if not grouped["left"] or not grouped["right"]:
        raise RuntimeError("Both doors must be found before splitting")

    body_points = [
        mesh.vertices[index].co
        for face_index in grouped["body"]
        for index in mesh.polygons[face_index].vertices
    ]
    body_front = min(point.y for point in body_points)
    body_left = min(point.x for point in body_points)
    body_right = max(point.x for point in body_points)

    root = bpy.data.objects.new(ROOT_NAME, None)
    bpy.context.scene.collection.objects.link(root)

    body = separate(source, grouped["body"], "WardrobeBody")
    body.parent = root

    closed_yaw: dict[str, float] = {}
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
        first, second = vertical_edge_lines(points)
        hinge, free = (
            (first, second)
            if abs(first.y - body_front) <= abs(second.y - body_front)
            else (second, first)
        )
        # Origin on the hinge line, so rotating the node swings the panel.
        offset = Vector((hinge.x, hinge.y, 0.0))
        working = bmesh.new()
        working.from_mesh(door.data)
        bmesh.ops.translate(working, verts=working.verts[:], vec=-offset)
        working.to_mesh(door.data)
        working.free()
        door.data.update()
        door.location = offset
        door.parent = root

        # The shut angle comes from the panel's PLANE, not from the hinge-to-free
        # direction. That direction is only defined up to which end you call the
        # hinge, and picking wrong silently leaves the door open -- which it did,
        # twice, in both possible orientations.
        #
        # A door is a thin slab, so the least-spread axis of its footprint is the
        # panel normal. Shut means that normal faces the front, -Y.
        normal = panel_normal(points)
        outward = Vector((hinge.x, hinge.y)) - Vector((0.0, body_front))
        if normal.dot(outward) < 0.0:
            normal = -normal
        open_angle = math.atan2(normal.y, normal.x)
        shut_angle = -math.pi * 0.5
        # Blender Z-up becomes Godot Y-up on export, and glTF's axis conversion
        # flips the sign of that rotation.
        delta = math.atan2(
            math.sin(shut_angle - open_angle), math.cos(shut_angle - open_angle)
        )
        closed_yaw[side] = -math.degrees(delta)
        print(
            "%s hinge=(%.3f,%.3f) normal=%.1f shut=%.1f closed_yaw=%.1f"
            % (
                node_name,
                hinge.x,
                hinge.y,
                math.degrees(open_angle),
                math.degrees(shut_angle),
                closed_yaw[side],
            )
        )

    bpy.data.objects.remove(source, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    glb_export.export_selected(arguments.output, write_normals=write_normals)
    print(
        "CLOSED_YAW left=%.1f right=%.1f"
        % (closed_yaw["left"], closed_yaw["right"])
    )
    print(f"HINGED_OUT={arguments.output}")


if __name__ == "__main__":
    main()
