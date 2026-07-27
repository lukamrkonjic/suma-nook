"""Rig and animate the temporary default keeper with Blender Rigify.

This deliberately leaves the supplied GLB untouched. It fits Rigify's basic
human metarig to the stylized proportions, generates the full Rigify control /
mechanism / deform rig, applies conservative smooth-by-angle shading, assigns
the source's disconnected low-poly patches to Rigify DEF bones, authors the
gameplay animation contract on Rigify FK controls, and exports only the mesh
and generated rig.
"""

import math
import os
import sys

import bpy
from mathutils import Vector


TARGET_HEIGHT = 1.487
FPS = 24
SMOOTH_ANGLE = math.radians(52.0)


def cli_value(flag: str, default: str = "") -> str:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if flag not in args:
        return default
    index = args.index(flag)
    return args[index + 1] if index + 1 < len(args) else default


def world_bounds(objects):
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                minimum[axis] = min(minimum[axis], point[axis])
                maximum[axis] = max(maximum[axis], point[axis])
    return minimum, maximum


def fit_bone(edit_bones, name, head, tail):
    bone = edit_bones[name]
    bone.head = Vector(head)
    bone.tail = Vector(tail)


def create_fitted_rigify_rig():
    bpy.ops.preferences.addon_enable(module="rigify")
    bpy.ops.object.armature_basic_human_metarig_add()
    metarig = bpy.context.object
    metarig.name = "SumaKeeperMetarig"
    bpy.context.view_layer.objects.active = metarig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = metarig.data.edit_bones

    spine_points = [
        (0, 0, 0.36),
        (0, 0, 0.50),
        (0, 0, 0.63),
        (0, 0, 0.76),
        (0, 0, 0.92),
        (0, 0, 1.01),
        (0, 0, 1.09),
        (0, 0, 1.42),
    ]
    for index, name in enumerate(
        ["spine", "spine.001", "spine.002", "spine.003", "spine.004", "spine.005", "spine.006"]
    ):
        fit_bone(bones, name, spine_points[index], spine_points[index + 1])

    for side, sign in (("L", 1.0), ("R", -1.0)):
        fit_bone(bones, f"shoulder.{side}", (0.16 * sign, 0, 0.92), (0.35 * sign, 0, 0.93))
        fit_bone(bones, f"upper_arm.{side}", (0.35 * sign, 0, 0.93), (0.60 * sign, 0, 0.90))
        fit_bone(bones, f"forearm.{side}", (0.60 * sign, 0, 0.90), (0.79 * sign, 0, 0.87))
        fit_bone(bones, f"hand.{side}", (0.79 * sign, 0, 0.87), (0.86 * sign, 0, 0.86))
        fit_bone(bones, f"breast.{side}", (0.10 * sign, -0.02, 0.78), (0.10 * sign, -0.12, 0.78))
        fit_bone(bones, f"pelvis.{side}", (0, 0, 0.38), (0.18 * sign, -0.03, 0.43))
        fit_bone(bones, f"thigh.{side}", (0.18 * sign, 0, 0.41), (0.19 * sign, 0, 0.23))
        fit_bone(bones, f"shin.{side}", (0.19 * sign, 0, 0.23), (0.19 * sign, 0, 0.075))
        fit_bone(bones, f"foot.{side}", (0.19 * sign, 0, 0.075), (0.19 * sign, -0.14, 0.045))
        fit_bone(bones, f"toe.{side}", (0.19 * sign, -0.14, 0.045), (0.19 * sign, -0.20, 0.045))
        fit_bone(bones, f"heel.02.{side}", (0.14 * sign, 0.06, 0.025), (0.24 * sign, 0.06, 0.025))

    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.objects.active = metarig
    metarig.select_set(True)
    bpy.ops.pose.rigify_generate()
    rig = bpy.context.object
    rig.name = "SumaKeeperRig"
    rig["rig_system"] = "Rigify basic human"
    rig["default_character"] = True
    metarig.hide_render = True
    metarig.hide_set(True)
    return metarig, rig


def connected_components(mesh):
    adjacency = {vertex.index: [] for vertex in mesh.data.vertices}
    for edge in mesh.data.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    unvisited = set(adjacency)
    result = []
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
        result.append(indices)
    return result


def distance_to_segment(point, head, tail):
    segment = tail - head
    if segment.length_squared == 0:
        return (point - head).length
    t = max(0.0, min(1.0, (point - head).dot(segment) / segment.length_squared))
    return (point - (head + segment * t)).length


def component_target_bone(mesh, rig, indices):
    points = [mesh.data.vertices[index].co for index in indices]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    center = (minimum + maximum) * 0.5
    side = "L" if center.x > 0 else "R"
    horizontal_extent = max(abs(minimum.x), abs(maximum.x))

    if center.z >= 0.95:
        candidates = ["DEF-spine.005", "DEF-spine.006"]
    elif horizontal_extent >= 0.32 and minimum.z >= 0.50:
        candidates = [
            f"DEF-shoulder.{side}",
            f"DEF-upper_arm.{side}",
            f"DEF-upper_arm.{side}.001",
            f"DEF-forearm.{side}",
            f"DEF-forearm.{side}.001",
            f"DEF-hand.{side}",
        ]
    elif center.z <= 0.46:
        candidates = [
            f"DEF-thigh.{side}",
            f"DEF-thigh.{side}.001",
            f"DEF-shin.{side}",
            f"DEF-shin.{side}.001",
            f"DEF-foot.{side}",
            f"DEF-toe.{side}",
        ]
    else:
        candidates = [
            "DEF-spine",
            "DEF-spine.001",
            "DEF-spine.002",
            "DEF-spine.003",
            "DEF-spine.004",
        ]
    candidates = [name for name in candidates if rig.data.bones.get(name) is not None]
    return min(
        candidates,
        key=lambda name: distance_to_segment(
            center,
            rig.data.bones[name].head_local,
            rig.data.bones[name].tail_local,
        ),
    )


def bind_to_rigify(mesh, rig):
    for group in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(group)
    groups = {
        bone.name: mesh.vertex_groups.new(name=bone.name)
        for bone in rig.data.bones
        if bone.use_deform
    }
    counts = {}
    for indices in connected_components(mesh):
        bone_name = component_target_bone(mesh, rig, indices)
        groups[bone_name].add(indices, 1.0, "REPLACE")
        counts[bone_name] = counts.get(bone_name, 0) + len(indices)
    mesh.parent = rig
    mesh.matrix_parent_inverse = rig.matrix_world.inverted()
    modifier = mesh.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = False
    if sum(counts.values()) != len(mesh.data.vertices):
        raise RuntimeError("Rigify binding did not cover every source vertex")
    return counts


def bind_automatic_rigify(mesh, rig):
    for group in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(group)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.vertex_group_clean(
        group_select_mode="ALL", limit=0.001, keep_single=True
    )
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(
        group_select_mode="ALL", lock_active=False
    )
    weighted = sum(
        1
        for vertex in mesh.data.vertices
        if any(element.weight > 0.0001 for element in vertex.groups)
    )
    if weighted != len(mesh.data.vertices):
        raise RuntimeError(
            f"Rigify automatic weights covered {weighted}/{len(mesh.data.vertices)} vertices"
        )
    return {
        group.name: sum(
            1
            for vertex in mesh.data.vertices
            for element in vertex.groups
            if element.group == group.index and element.weight > 0.0001
        )
        for group in mesh.vertex_groups
        if group.name.startswith("DEF-")
    }


CONTROL_BONES = [
    "root",
    "torso",
    "chest",
    "head",
    "upper_arm_fk.L",
    "forearm_fk.L",
    "hand_fk.L",
    "upper_arm_fk.R",
    "forearm_fk.R",
    "hand_fk.R",
    "thigh_fk.L",
    "shin_fk.L",
    "foot_fk.L",
    "thigh_fk.R",
    "shin_fk.R",
    "foot_fk.R",
]


def reset_controls(rig):
    for name in CONTROL_BONES:
        pose_bone = rig.pose.bones.get(name)
        if pose_bone is None:
            continue
        pose_bone.location = Vector((0, 0, 0))
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion.identity()
        pose_bone.scale = Vector((1, 1, 1))
    for name in ("upper_arm_parent.L", "upper_arm_parent.R", "thigh_parent.L", "thigh_parent.R"):
        if rig.pose.bones.get(name) is not None:
            rig.pose.bones[name]["IK_FK"] = 1.0


def point_control(rig, name, direction):
    pose_bone = rig.pose.bones[name]
    rest_orientation = rig.data.bones[name].matrix_local.to_quaternion()
    desired_orientation = Vector(direction).normalized().to_track_quat("Y", "Z")
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = rest_orientation.inverted() @ desired_orientation


def key_pose(
    rig,
    frame,
    *,
    arms=(0.0, 0.0),
    legs=(0.0, 0.0),
    lift=0.0,
    torso=(0.0, 0.0, 0.0),
    right_arm=None,
    left_arm=None,
):
    reset_controls(rig)
    # This broad, chibi torso physically occupies the space used by a straight
    # vertical arm. A relaxed A-stance keeps the source arm volume visible and
    # prevents the arm from being pressed through the shirt in the neutral pose.
    point_control(rig, "upper_arm_fk.L", left_arm or (0.24, arms[0], -0.97))
    point_control(rig, "upper_arm_fk.R", right_arm or (-0.24, arms[1], -0.97))
    point_control(rig, "thigh_fk.L", (0.015, legs[0], -1.0))
    point_control(rig, "thigh_fk.R", (-0.015, legs[1], -1.0))
    rig.pose.bones["root"].location.z = lift
    rig.pose.bones["torso"].rotation_mode = "XYZ"
    rig.pose.bones["torso"].rotation_euler = Vector(torso)
    for name in CONTROL_BONES:
        pose_bone = rig.pose.bones.get(name)
        if pose_bone is None:
            continue
        pose_bone.keyframe_insert("location", frame=frame)
        if pose_bone.rotation_mode == "QUATERNION":
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        else:
            pose_bone.keyframe_insert("rotation_euler", frame=frame)
        pose_bone.keyframe_insert("scale", frame=frame)


def create_action(rig, name, duration, loop, poses):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = round(duration * FPS)
    action["looping"] = loop
    rig.animation_data_create()
    rig.animation_data.action = action
    for seconds, values in poses:
        key_pose(rig, round(seconds * FPS), **values)
    return action


def create_animations(rig):
    specs = {
        "idle": (2.4, True, [
            (0.0, {"lift": 0.0}),
            (1.2, {"lift": 0.010}),
            (2.4, {"lift": 0.0}),
        ]),
        "walk": (0.84, True, [
            (0.0, {"arms": (0.34, -0.34), "legs": (-0.30, 0.30)}),
            (0.21, {"lift": 0.035}),
            (0.42, {"arms": (-0.34, 0.34), "legs": (0.30, -0.30)}),
            (0.63, {"lift": 0.035}),
            (0.84, {"arms": (0.34, -0.34), "legs": (-0.30, 0.30)}),
        ]),
        "fish_cast": (0.38, False, [
            (0.0, {}),
            (0.22, {"right_arm": (-0.10, 0.45, 0.60), "torso": (0, 0, -0.08)}),
            (0.38, {"right_arm": (-0.08, -0.72, -0.38)}),
        ]),
        "fish_wait": (1.3, True, [
            (0.0, {"right_arm": (-0.08, -0.72, -0.42)}),
            (0.65, {"right_arm": (-0.08, -0.66, -0.48), "lift": 0.008}),
            (1.3, {"right_arm": (-0.08, -0.72, -0.42)}),
        ]),
        "fish_catch": (0.69, False, [
            (0.0, {"right_arm": (-0.08, -0.72, -0.42)}),
            (0.14, {"right_arm": (-0.10, 0.48, 0.58), "torso": (-0.10, 0, 0)}),
            (0.49, {"right_arm": (-0.08, 0.18, -0.70)}),
            (0.69, {}),
        ]),
        "chop": (0.52, False, [
            (0.0, {}),
            (0.28, {"right_arm": (-0.08, 0.52, 0.60), "torso": (0, 0.12, -0.07)}),
            (0.38, {"right_arm": (-0.08, -0.72, -0.34), "torso": (0.10, -0.08, 0.05)}),
            (0.52, {}),
        ]),
        "attack": (0.38, False, [
            (0.0, {}),
            (0.12, {"right_arm": (-0.10, 0.58, 0.54), "torso": (0, 0.10, 0)}),
            (0.22, {"right_arm": (-0.08, -0.80, -0.28), "torso": (0, -0.10, 0)}),
            (0.38, {}),
        ]),
        "dodge": (0.30, False, [
            (0.0, {}),
            (0.10, {"lift": 0.08, "torso": (0.30, 0, 0)}),
            (0.30, {}),
        ]),
        "hit": (0.18, False, [
            (0.0, {}),
            (0.05, {"torso": (-0.12, 0, 0.08)}),
            (0.10, {"torso": (0.08, 0, -0.06)}),
            (0.18, {}),
        ]),
        "celebrate": (0.70, False, [
            (0.0, {}),
            (0.20, {
                "left_arm": (0.24, 0.02, 1.0),
                "right_arm": (-0.24, 0.02, 1.0),
                "lift": 0.16,
            }),
            (0.40, {
                "left_arm": (0.35, 0.02, 0.95),
                "right_arm": (-0.35, 0.02, 0.95),
                "lift": 0.02,
            }),
            (0.70, {}),
        ]),
    }
    for name, (duration, loop, poses) in specs.items():
        create_action(rig, name, duration, loop, poses)
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(round(0.6 * FPS))


def add_studio(center, size):
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.79, 0.78, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = size * 1.35
    camera.location = center + Vector((size * 2.2, -size * 2.8, size * 1.7))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    for name, energy, offset, area_size in (
        ("Key", 900.0, (-2.2, -2.4, 3.1), 2.0),
        ("Fill", 430.0, (2.6, 1.5, 2.0), 2.6),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size * area_size
        light = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(light)
        light.location = center + Vector(offset) * size
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()


def render(path, rig, action, seconds):
    rig.animation_data.action = bpy.data.actions[action]
    bpy.context.scene.frame_set(round(seconds * FPS))
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


source_path = os.path.abspath(cli_value("--source"))
output_glb = os.path.abspath(cli_value("--output"))
blend_path = os.path.abspath(cli_value("--blend"))
preview_dir = os.path.abspath(cli_value("--preview-dir"))
if not os.path.isfile(source_path):
    raise RuntimeError(f"Missing source GLB: {source_path}")
for directory in (os.path.dirname(output_glb), os.path.dirname(blend_path), preview_dir):
    os.makedirs(directory, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source_path)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError(f"Expected one source mesh, found {len(meshes)}")
mesh = meshes[0]
minimum, maximum = world_bounds([mesh])
source_height = maximum.z - minimum.z
mesh.parent = None
mesh.matrix_world = mesh.matrix_world
mesh.scale *= TARGET_HEIGHT / source_height
bpy.context.view_layer.update()
minimum, maximum = world_bounds([mesh])
mesh.location += Vector((-(minimum.x + maximum.x) * 0.5, -(minimum.y + maximum.y) * 0.5, -minimum.z))
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh.name = "SumaKeeper"
mesh.data.name = "SumaKeeperMesh"
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.00001, use_unselected=False)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_smooth_by_angle(angle=SMOOTH_ANGLE, keep_sharp_edges=True)
for obj in list(bpy.context.scene.objects):
    if obj.type == "EMPTY":
        bpy.data.objects.remove(obj, do_unlink=True)

metarig, rig = create_fitted_rigify_rig()
weight_counts = bind_automatic_rigify(mesh, rig)
create_animations(rig)
bpy.ops.wm.save_as_mainfile(filepath=blend_path)

# Rigify control widgets are useful in the editable .blend but are not runtime
# geometry. Clear the object references before glTF dependency collection.
for pose_bone in rig.pose.bones:
    pose_bone.custom_shape = None
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj != mesh:
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=output_glb,
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_def_bones=True,
    export_skins=True,
    export_materials="EXPORT",
)

minimum, maximum = world_bounds([mesh])
center = (minimum + maximum) * 0.5
size = max(maximum - minimum)
add_studio(center, size)
bpy.context.scene.render.engine = "BLENDER_EEVEE"
bpy.context.scene.render.resolution_x = 700
bpy.context.scene.render.resolution_y = 700
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.image_settings.file_format = "PNG"
bpy.context.scene.view_settings.look = "AgX - Medium High Contrast"
render(os.path.join(preview_dir, "suma_player_idle.png"), rig, "idle", 0.6)
render(os.path.join(preview_dir, "suma_player_walk.png"), rig, "walk", 0.21)

triangles = sum(len(poly.vertices) - 2 for poly in mesh.data.polygons)
print(
    "SUMA_PLAYER_RIGIFY_EXPORT "
    f"source_height={source_height:.6f} target_height={TARGET_HEIGHT:.3f} "
    f"vertices={len(mesh.data.vertices)} triangles={triangles} "
    f"deform_groups={len(weight_counts)} animations={len(bpy.data.actions)}"
)
