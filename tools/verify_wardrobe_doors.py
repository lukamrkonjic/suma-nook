"""Render the hinged wardrobe at a given door yaw, to check it shuts flush.

Run inside Blender:

    blender --background --factory-startup --python tools/verify_wardrobe_doors.py -- \
        --asset worldheart_wardrobe_hinged.glb --yaw-left -123.2 --yaw-right 86.8 \
        --output shut.png

Deliberately a separate pass over the EXPORTED file rather than a flag on the
builder. Rotating the doors inside the builder before export both risked baking
the rotation into the shipped asset and made it impossible to tell whether a
render reflected the rotation at all -- two consecutive runs with different
angles produced identical images, and the ambiguity was the reason the angles
could not be trusted.

Loading the glb back means what is measured is exactly what the game loads,
including glTF's axis conversion.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--yaw-left", type=float, default=0.0)
    parser.add_argument("--yaw-right", type=float, default=0.0)
    parser.add_argument(
        "--solve",
        action="store_true",
        help="Sweep each door's yaw and report the angle that shuts it.",
    )
    return parser.parse_args(argv)


def world_bounds(item) -> tuple[Vector, Vector]:
    corners = [item.matrix_world @ Vector(corner) for corner in item.bound_box]
    return (
        Vector((
            min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)
        )),
        Vector((
            max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)
        )),
    )


def set_yaw(node, degrees: float) -> None:
    """Assigns a Z rotation, in a mode where the assignment is not ignored.

    The glTF importer leaves every node in QUATERNION rotation mode, and in that
    mode writing rotation_euler does nothing at all -- silently. That is why the
    solver kept reporting zero: it was sweeping 360 angles and measuring the same
    pose every time.
    """
    node.rotation_mode = "XYZ"
    node.rotation_euler.z = math.radians(degrees)


def solve_shut_yaw(door, low: float, high: float) -> float:
    """The yaw that lays a door flat across the cabinet front.

    Solved rather than derived. Every attempt to compute this from geometry --
    hinge-to-free direction, then the panel's plane normal -- got the sign or the
    reference direction wrong in a way that stayed invisible until rendered.

    A shut door has one unambiguous property: it is THIN in depth. Open, its
    footprint is a long diagonal; shut, it collapses to its own thickness. So the
    objective is the door's depth extent, searched within the half-turn that puts
    it on its own side of the cabinet -- the two flat solutions are 180 apart, and
    the far one folds the panel into the opposite half.

    Each door needs its own angle: they are modelled open by different amounts,
    about 47 degrees on the left and 88 on the right, so a single value leaves a
    wedge-shaped gap between them.

    An earlier objective, "stops sticking out past the body", found nothing: the
    cabinet's cornice is wider and deeper than the doors ever reach, so every
    angle scored zero.
    """
    best_yaw = low
    best_score = float("inf")
    steps = int((high - low) * 4.0)
    for step in range(steps + 1):
        candidate = low + float(step) * 0.25
        set_yaw(door, candidate)
        bpy.context.view_layer.update()
        minimum, maximum = world_bounds(door)
        depth = maximum.y - minimum.y
        if depth < best_score:
            best_score = depth
            best_yaw = candidate
    set_yaw(door, 0.0)
    bpy.context.view_layer.update()
    return best_yaw


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.asset))

    # The glTF importer converts Y-up back to Blender's Z-up, so the presenter's
    # rotation.y about Godot's vertical is a rotation about Blender's Z here.
    # Driving Y instead tipped each door onto its side, which read as "the angle
    # is wrong" when the axis was.
    if arguments.solve:
        solved: dict[str, float] = {}
        for node_name in ("WardrobeDoorLeft", "WardrobeDoorRight"):
            door = bpy.data.objects.get(node_name)
            if door is None:
                raise RuntimeError("%s is missing" % node_name)
            window = (40.0, 140.0) if node_name.endswith("Left") else (220.0, 320.0)
            solved[node_name] = solve_shut_yaw(door, window[0], window[1])
            print("SOLVED %s blender_z=%.1f" % (node_name, solved[node_name]))
        # Godot's rotation.y runs opposite to Blender's Z through the glTF axis
        # conversion, so the presenter constant is the negation.
        print(
            "PRESENTER_YAW left=%.1f right=%.1f"
            % (
                -solved["WardrobeDoorLeft"],
                -solved["WardrobeDoorRight"],
            )
        )
        arguments.yaw_left = solved["WardrobeDoorLeft"]
        arguments.yaw_right = solved["WardrobeDoorRight"]

    applied: list[str] = []
    for node_name, yaw in (
        ("WardrobeDoorLeft", arguments.yaw_left),
        ("WardrobeDoorRight", arguments.yaw_right),
    ):
        node = bpy.data.objects.get(node_name)
        if node is None:
            raise RuntimeError(
                "%s is missing; found %s"
                % (node_name, sorted(o.name for o in bpy.data.objects))
            )
        set_yaw(node, yaw)
        applied.append("%s=%.1f" % (node_name, yaw))
    # matrix_world is cached, so bounds read before this reflect the rest pose
    # no matter what was just assigned -- which is how two different angles
    # produced identical measurements.
    bpy.context.view_layer.update()
    print("APPLIED %s" % " ".join(applied))

    points: list[Vector] = []
    for item in bpy.context.scene.objects:
        if item.type == "MESH":
            for corner in item.bound_box:
                points.append(item.matrix_world @ Vector(corner))
    centre = sum(points, Vector()) / max(1, len(points))
    span = max(
        max(point.x for point in points) - min(point.x for point in points),
        max(point.y for point in points) - min(point.y for point in points),
        max(point.z for point in points) - min(point.z for point in points),
    )
    print(
        "BOUNDS x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]"
        % (
            min(p.x for p in points), max(p.x for p in points),
            min(p.y for p in points), max(p.y for p in points),
            min(p.z for p in points), max(p.z for p in points),
        )
    )

    # Z-up, matching what the glTF importer produces. An earlier Y-up camera
    # placement looked at the model from underneath and rendered almost black.
    camera_data = bpy.data.cameras.new("VerifyCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = span * 1.6
    camera = bpy.data.objects.new("VerifyCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = centre + Vector((span * 1.1, -span * 1.5, span * 0.95))
    camera.rotation_euler = (
        (centre - camera.location).normalized().to_track_quat("-Z", "Y").to_euler()
    )
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("VerifySun", type="SUN")
    sun_data.energy = 3.6
    sun = bpy.data.objects.new("VerifySun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(58.0), 0.0, math.radians(-38.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.filepath = str(arguments.output)
    bpy.ops.render.render(write_still=True)
    print(f"VERIFY_OUT={arguments.output}")


if __name__ == "__main__":
    main()
