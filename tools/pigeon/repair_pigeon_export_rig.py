"""Build a clean game-deformation skeleton from the Rigify bird source.

The generated Rigify DEF chains for this particular imported mascot contain
several pivots far outside the mesh (notably the wings and every toe chain).
They display correctly in the bind pose, but any rotation produces enormous
arcs and collapses the skinned body.  Keep the Rigify control rig in the .blend
for authoring and bind the game mesh to a clean, deform-only export skeleton
whose joints sit on the mascot's actual anatomy.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    argv = []
    if "--" in __import__("sys").argv:
        argv = __import__("sys").argv[__import__("sys").argv.index("--") + 1 :]
    return parser.parse_args(argv)


def _source_rig() -> bpy.types.Object:
    for name in ("PigeonRigControls", "PigeonRig"):
        candidate = bpy.data.objects.get(name)
        if candidate is not None and candidate.type == "ARMATURE":
            return candidate
    raise RuntimeError("Pigeon Rigify control armature was not found")


def _nearest_export_parent(
    source_bone: bpy.types.Bone,
    export_names: set[str],
) -> str | None:
    parent = source_bone.parent
    while parent is not None:
        if parent.name in export_names:
            return parent.name
        parent = parent.parent
    return None


def _set_chain(
    bones: bpy.types.ArmatureEditBones,
    names: tuple[str, ...],
    points: tuple[tuple[float, float, float], ...],
    roll_axis: Vector,
) -> None:
    for index, name in enumerate(names):
        bone = bones.get(name)
        if bone is None:
            continue
        bone.head = points[index]
        bone.tail = points[index + 1]
        bone.align_roll(roll_axis)
        if index > 0 and bones.get(names[index - 1]) is not None:
            bone.parent = bones[names[index - 1]]
            bone.use_connect = True


def _repair_wings(bones: bpy.types.ArmatureEditBones) -> None:
    for side, sign in (("L", 1.0), ("R", -1.0)):
        names = (
            f"DEF-Wing.{side}",
            f"DEF-Wing.001.{side}",
            f"DEF-Wing.002.{side}",
        )
        points = tuple(
            (sign * x, 0.0, z)
            for x, z in (
                (0.075, 0.055),
                (0.225, 0.050),
                (0.365, 0.035),
                (0.495, 0.015),
            )
        )
        _set_chain(bones, names, points, Vector((0.0, 0.0, 1.0)))
        root = bones.get(names[0])
        if root is not None:
            root.parent = None
            root.use_connect = False

        # Rigify's separate feather deformers must inherit the repaired wing,
        # otherwise the feather cards remain behind while the main wing moves.
        for feather_index in range(1, 5):
            feather = bones.get(f"DEF-w_feather.{feather_index:03d}.{side}")
            if feather is None:
                continue
            absolute_x = abs(feather.head.x)
            if absolute_x >= 0.29:
                feather.parent = bones.get(names[2])
            elif absolute_x >= 0.18:
                feather.parent = bones.get(names[1])
            else:
                feather.parent = bones.get(names[0])
            feather.use_connect = False


def _repair_legs(bones: bpy.types.ArmatureEditBones) -> None:
    for side, sign in (("L", 1.0), ("R", -1.0)):
        x = sign * 0.070
        leg_names = (
            f"DEF-thigh.{side}",
            f"DEF-thigh.{side}.001",
            f"DEF-shin.{side}",
            f"DEF-shin.{side}.001",
        )
        leg_points = (
            (x, 0.005, -0.145),
            (x, 0.005, -0.205),
            (x, 0.003, -0.250),
            (x, 0.000, -0.285),
            (x, -0.005, -0.310),
        )
        _set_chain(
            bones,
            leg_names,
            leg_points,
            Vector((0.0, -1.0, 0.0)),
        )
        thigh = bones.get(leg_names[0])
        torso_parent = bones.get("DEF-spine.004")
        if thigh is not None:
            thigh.parent = torso_parent
            thigh.use_connect = False

        foot_names = (f"DEF-foot.{side}", f"DEF-foot.{side}.001")
        foot_points = (
            (x, -0.005, -0.310),
            (x, -0.045, -0.320),
            (x, -0.075, -0.322),
        )
        _set_chain(
            bones,
            foot_names,
            foot_points,
            Vector((sign, 0.0, 0.0)),
        )
        foot = bones.get(foot_names[0])
        shin_end = bones.get(leg_names[-1])
        if foot is not None:
            foot.parent = shin_end
            foot.use_connect = True

        toe = bones.get(f"DEF-toe.{side}")
        if toe is not None:
            toe.head = foot_points[-1]
            toe.tail = (x, -0.145, -0.322)
            toe.align_roll(Vector((sign, 0.0, 0.0)))
            toe.parent = bones.get(foot_names[-1])
            toe.use_connect = True

        toe_layout = {
            "index": (sign * 0.052, -0.070, sign * 0.040, -0.145),
            "middle": (sign * 0.070, -0.072, sign * 0.070, -0.155),
            "ring": (sign * 0.087, -0.070, sign * 0.103, -0.145),
            "thumb": (sign * 0.060, -0.050, sign * 0.045, 0.015),
        }
        for digit, (start_x, start_y, end_x, end_y) in toe_layout.items():
            count = 2 if digit == "thumb" else 3
            names = tuple(
                f"DEF-t_{digit}.{segment:03d}.{side}"
                for segment in range(1, count + 1)
            )
            points = tuple(
                (
                    start_x + (end_x - start_x) * step / count,
                    start_y + (end_y - start_y) * step / count,
                    -0.322,
                )
                for step in range(count + 1)
            )
            _set_chain(bones, names, points, Vector((0.0, 0.0, 1.0)))
            digit_root = bones.get(names[0])
            if digit_root is not None:
                digit_root.parent = toe
                digit_root.use_connect = False


def _build_export_rig(
    source_rig: bpy.types.Object,
    body: bpy.types.Object,
) -> bpy.types.Object:
    for existing_name in ("PigeonRigExport", "PigeonRig"):
        existing = bpy.data.objects.get(existing_name)
        if existing is not None and existing != source_rig:
            bpy.data.objects.remove(existing, do_unlink=True)

    export_names = {
        group.name
        for group in body.vertex_groups
        if source_rig.data.bones.get(group.name) is not None
    }
    armature = bpy.data.armatures.new("PigeonRigExportSkeleton")
    # Keep the runtime node name stable; the Godot wrapper and face attachment
    # intentionally target Model/PigeonRig/Skeleton3D.
    export_rig = bpy.data.objects.new("PigeonRig", armature)
    bpy.context.scene.collection.objects.link(export_rig)
    export_rig.matrix_world = source_rig.matrix_world.copy()

    bpy.context.view_layer.objects.active = export_rig
    export_rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name in sorted(export_names):
        source_bone = source_rig.data.bones[name]
        edit_bone = armature.edit_bones.new(name)
        edit_bone.matrix = source_bone.matrix_local
        edit_bone.length = max(source_bone.length, 0.002)
        edit_bone.use_deform = True
    for name in sorted(export_names):
        parent_name = _nearest_export_parent(source_rig.data.bones[name], export_names)
        if parent_name is not None:
            armature.edit_bones[name].parent = armature.edit_bones[parent_name]
            armature.edit_bones[name].use_connect = False

    _repair_wings(armature.edit_bones)
    _repair_legs(armature.edit_bones)
    bpy.ops.object.mode_set(mode="OBJECT")
    return export_rig


def _bind_body(body: bpy.types.Object, export_rig: bpy.types.Object) -> None:
    for modifier in list(body.modifiers):
        if modifier.type == "ARMATURE":
            body.modifiers.remove(modifier)
    modifier = body.modifiers.new("Pigeon Game Rig", "ARMATURE")
    modifier.object = export_rig
    modifier.use_vertex_groups = True
    world_matrix = body.matrix_world.copy()
    body.parent = export_rig
    body.matrix_world = world_matrix


def _export(body: bpy.types.Object, export_rig: bpy.types.Object, output: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    export_rig.select_set(True)
    bpy.context.view_layer.objects.active = export_rig
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_morph=False,
        export_yup=True,
        export_apply=False,
    )


def main() -> None:
    args = _arguments()
    source_path = Path(args.source).resolve()
    output_path = Path(args.output).resolve()
    if Path(bpy.data.filepath).resolve() != source_path:
        bpy.ops.wm.open_mainfile(filepath=str(source_path))

    body = bpy.data.objects.get("PigeonBody")
    if body is None or body.type != "MESH":
        raise RuntimeError("PigeonBody mesh was not found")
    source_rig = _source_rig()
    if source_rig.name == "PigeonRig":
        source_rig.name = "PigeonRigControls"
    source_rig.hide_set(True)
    source_rig.hide_render = True

    export_rig = _build_export_rig(source_rig, body)
    _bind_body(body, export_rig)
    bpy.context.view_layer.objects.active = export_rig
    export_rig.hide_set(False)
    export_rig.hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    _export(body, export_rig, output_path)
    print(
        "PIGEON_RIG_REPAIR_OK",
        f"bones={len(export_rig.data.bones)}",
        f"output={output_path}",
    )


if __name__ == "__main__":
    main()
