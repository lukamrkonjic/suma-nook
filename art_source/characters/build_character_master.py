"""Build the canonical Suma character master file and its runtime exports.

Creates art_source/characters/suma_character_master.blend containing the
canonical male mannequin (built by the same pipeline as build_player_male.py),
the rebuilt reference-fitted default face/hair parts, inspection cameras, and
the authored idle_relaxed clip. Exports:

- assets/3d/reworked/player_male_mannequin.glb  (body + rig + idle_relaxed)
- assets/characters/parts/<part>.glb            (rigid parts, origin at socket)
- art_source/characters/review/*.png            (validation renders)
- art_source/characters/character_manifest.json (sockets + part stats)

The reference image lives only in the REFERENCE_ONLY collection and is never
exported.

Run with Blender 5.x:
    blender --background --factory-startup --python build_character_master.py
"""

from __future__ import annotations

import importlib.util
import json
from math import cos, pi, radians, sin
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = Path(r"C:\Dev\suma-nook")
CHAR_DIR = REPO / "art_source/characters"
BLEND_OUT = CHAR_DIR / "suma_character_master.blend"
MANNEQUIN_GLB = REPO / "assets/3d/reworked/player_male_mannequin.glb"
PARTS_DIR = REPO / "assets/characters/parts"
REVIEW_DIR = CHAR_DIR / "review"
MANIFEST_OUT = CHAR_DIR / "character_manifest.json"
REFERENCE_IMAGE = CHAR_DIR / "reference/male_default_reference.png"

# ---------------------------------------------------------------- reference
# Measured from body_inspection.json (model space, ground at z = -0.435 before
# the glTF ground shift; here everything uses the build space of
# build_player_male.py where the ground plane sits at z = -0.435).
GROUND_Z = -0.435
HEAD_BOTTOM = 0.100
HEAD_TOP = 0.408
HEAD_HEIGHT = HEAD_TOP - HEAD_BOTTOM
SKULL_HALF_WIDTH = 0.131

# Reference-derived facial layout (see docs in character_manifest.json).
# ACNH-style eyes: big solid near-black vertical ovals, height ~2x width,
# ~20% of head height, mid-face with a generous forehead. The eye/mouth decal
# geometry itself lives in face_catalog.py.
EYE_Z = 0.246
EYE_X = 0.048
BROW_Z = 0.292
NOSE_Z = 0.217
MOUSTACHE_Z = 0.186
MOUTH_Z = 0.150

SOCKETS = {
    "FaceRoot": (0.0, 0.0, 0.254),
    "EyesSocket": (0.0, -0.118, EYE_Z),
    "BrowsSocket": (0.0, -0.120, BROW_Z),
    "NoseSocket": (0.0, -0.132, NOSE_Z),
    "MoustacheSocket": (0.0, -0.138, MOUSTACHE_Z),
    "MouthSocket": (0.0, -0.134, MOUTH_Z),
    "HairSocket": (0.0, 0.003, 0.360),
    "HatSocket": (0.0, 0.003, 0.410),
    "BeardSocket": (0.0, -0.120, 0.120),
}

# Master-built parts (the face catalog module exports its own parts on top).
PART_EXPORTS = {
    # object name -> (glb file stem, socket name)
    "HairSwoop": ("hair_swoop_brown", "HairSocket"),
    "BrowsPair": ("brows_soft_pair", "BrowsSocket"),
    "MoustacheWalrus": ("moustache_walrus", "MoustacheSocket"),
}

IDLE_FPS = 30
IDLE_FRAMES = 156  # 5.2 s loop, closes exactly (all phases are 1x frequency)
IDLE_NAME = "idle_relaxed"
# The extracted walk/action clips follow the Mixamo convention: the hips ride
# a ground-relative baseline (~0.246 above the model origin) instead of the
# centered rest. The idle must share that baseline or the runtime ground
# offset (measured from the idle) makes the character float during locomotion.
# 0.381 lifts the rest hips (-0.135) to the walk clip's standing key (0.246).
IDLE_HIPS_LIFT = 0.381


def load_player_pipeline():
    spec = importlib.util.spec_from_file_location(
        "build_player_male",
        REPO / "art_source/player_male/build_player_male.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_face_catalog():
    spec = importlib.util.spec_from_file_location(
        "face_catalog", CHAR_DIR / "face_catalog.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PIPE = load_player_pipeline()
FACES = load_face_catalog()


def srgb_to_linear(color: tuple) -> tuple:
    """Palette colors are sRGB hex values; Principled Base Color wants linear."""
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (channel(color[0]), channel(color[1]), channel(color[2]), color[3])


# ---------------------------------------------------------------- utilities

def collection(name: str) -> bpy.types.Collection:
    existing = bpy.data.collections.get(name)
    if existing is None:
        existing = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(existing)
    return existing


def move_to_collection(obj: bpy.types.Object, name: str) -> None:
    for parent in list(obj.users_collection):
        parent.objects.unlink(obj)
    collection(name).objects.link(obj)


def shade_smooth(obj: bpy.types.Object) -> None:
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def metaball_object(
    name: str, elements: list[tuple[float, float, float, float]]
) -> bpy.types.Object:
    """Convert a metaball chain into one smooth clay mesh."""
    mball = bpy.data.metaballs.new(f"{name}Ball")
    mball.resolution = 0.008
    mball.render_resolution = 0.008
    obj = bpy.data.objects.new(name, mball)
    bpy.context.scene.collection.objects.link(obj)
    for x, y, z, r in elements:
        element = mball.elements.new()
        element.co = (x, y, z)
        element.radius = r
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    converted = bpy.context.object
    converted.name = name
    shade_smooth(converted)
    return converted


def remesh_smooth(
    obj: bpy.types.Object,
    voxel: float,
    smooth_factor: float,
    smooth_iterations: int,
    target_triangles: int,
) -> None:
    remesh = obj.modifiers.new("Unify", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = voxel
    remesh.use_smooth_shade = True
    apply_modifier(obj, remesh)
    smooth = obj.modifiers.new("Relax", "SMOOTH")
    smooth.factor = smooth_factor
    smooth.iterations = smooth_iterations
    apply_modifier(obj, smooth)
    triangles = triangle_count(obj)
    if triangles > target_triangles:
        decimate = obj.modifiers.new("Budget", "DECIMATE")
        decimate.ratio = target_triangles / triangles
        apply_modifier(obj, decimate)
    shade_smooth(obj)


def join_objects(name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = parts[0]
    joined.name = name
    joined.data.name = f"{name}Mesh"
    return joined


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def mirrored(
    elements: list[tuple[float, float, float, float]]
) -> list[tuple[float, float, float, float]]:
    return [(-x, y, z, r) for x, y, z, r in elements]


# ---------------------------------------------------------------- face parts
# Eyes, mouths, and noses are authored by face_catalog.py as flat ACNH-style
# decals (eyes/mouths) and small 3D shapes (noses); only the brows, moustache,
# and the default swoop hairstyle remain master-built.

def build_brows(material: bpy.types.Material) -> bpy.types.Object:
    """Two small, soft lines that support the eyes without dominating them."""
    halves = []
    for sign in (1.0, -1.0):
        curve = bpy.data.curves.new("BrowCurve", type="CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 8
        curve.bevel_depth = 0.0048
        curve.bevel_resolution = 4
        curve.use_fill_caps = True
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(2)
        points = [
            (sign * 0.028, -0.1165, BROW_Z - 0.002),
            (sign * 0.047, -0.1200, BROW_Z + 0.003),
            (sign * 0.066, -0.1155, BROW_Z - 0.001),
        ]
        for point, coordinate in zip(spline.bezier_points, points):
            point.co = coordinate
            point.handle_left_type = "AUTO"
            point.handle_right_type = "AUTO"
        obj = bpy.data.objects.new("BrowHalf", curve)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.convert(target="MESH")
        shade_smooth(bpy.context.object)
        halves.append(bpy.context.object)
    brows = join_objects("BrowsPair", halves)
    assign_material(brows, material)
    return brows


def build_moustache(material: bpy.types.Material) -> bpy.types.Object:
    """Two mirrored rounded lobes, small central meet, softly upturned tips."""
    lobe = [
        (0.006, -0.146, MOUSTACHE_Z + 0.004, 0.026),
        (0.028, -0.150, MOUSTACHE_Z - 0.001, 0.030),
        (0.052, -0.146, MOUSTACHE_Z, 0.025),
        (0.070, -0.137, MOUSTACHE_Z + 0.010, 0.016),
    ]
    moustache = metaball_object("MoustacheWalrus", lobe + mirrored(lobe))
    remesh_smooth(moustache, 0.006, 0.35, 3, 1100)
    assign_material(moustache, material)
    return moustache


def hairline_z(face_center: Vector) -> float:
    """Scalp boundary: high on the forehead, above the ears, low at the nape."""
    y = face_center.y
    if y < -0.055:
        return 0.332
    if y <= 0.03:
        return 0.332 - (y + 0.055) * 0.96
    return max(0.25 - (y - 0.03) * 0.55, 0.205)


def build_hair(body: bpy.types.Object, material: bpy.types.Material) -> bpy.types.Object:
    import bmesh

    # 1. Scalp cap duplicated from the real skull surface so it always hugs it.
    scalp = body.copy()
    scalp.data = body.data.copy()
    scalp.name = "HairScalpShell"
    bpy.context.scene.collection.objects.link(scalp)
    mesh = bmesh.new()
    mesh.from_mesh(scalp.data)
    doomed = [
        face
        for face in mesh.faces
        if face.calc_center_median().z < hairline_z(face.calc_center_median())
    ]
    bmesh.ops.delete(mesh, geom=doomed, context="FACES")
    mesh.to_mesh(scalp.data)
    mesh.free()
    solidify = scalp.modifiers.new("CapThickness", "SOLIDIFY")
    solidify.thickness = 0.022
    solidify.offset = 1.0
    apply_modifier(scalp, solidify)

    # 2. Broad soft swoop rising from the viewer-left hairline and peaking at
    #    viewer-right (+X is the character's left = the viewer's right in a
    #    front render), matching the reference quiff direction.
    quiff = metaball_object(
        "HairQuiff",
        [
            (-0.058, -0.075, 0.345, 0.040),
            (-0.075, -0.058, 0.356, 0.052),
            (-0.038, -0.086, 0.396, 0.066),
            (0.002, -0.094, 0.424, 0.066),
            (0.046, -0.084, 0.442, 0.058),
            (0.080, -0.054, 0.444, 0.048),
            (0.112, -0.016, 0.430, 0.026),
            (0.0, -0.042, 0.382, 0.068),
        ],
    )

    # 3. Crown rounding plus soft temple masses framing the upper face; the
    #    ears (z 0.16-0.26, |x| > 0.125) stay uncovered.
    crown = metaball_object(
        "HairCrown",
        [
            (0.0, 0.012, 0.392, 0.072),
            (0.0, 0.052, 0.368, 0.068),
            (0.105, -0.048, 0.318, 0.030),
            (-0.105, -0.048, 0.318, 0.030),
        ],
    )

    hair = join_objects("HairSwoop", [scalp, quiff, crown])
    remesh_smooth(hair, 0.0085, 0.42, 4, 3800)
    assign_material(hair, material)
    return hair


# ---------------------------------------------------------------- regions

# Mirrors PlayerArmorRegions.REGION_IDS (scripts/player/player_armor_regions.gd).
REGION_IDS = {
    "head": 0, "neck": 1, "chest": 2, "abdomen": 3, "hips": 4,
    "shoulder_l": 5, "upper_arm_l": 6, "forearm_l": 7, "hand_l": 8,
    "shoulder_r": 9, "upper_arm_r": 10, "forearm_r": 11, "hand_r": 12,
    "thigh_l": 13, "knee_l": 14, "shin_l": 15, "foot_l": 16,
    "thigh_r": 17, "knee_r": 18, "shin_r": 19, "foot_r": 20,
    "clavicle_l": 21, "shoulder_cap_l": 22, "armpit_l": 23,
    "upper_chest_l": 24, "upper_arm_inner_l": 25,
    "clavicle_r": 26, "shoulder_cap_r": 27, "armpit_r": 28,
    "upper_chest_r": 29, "upper_arm_inner_r": 30,
}

def _region_for(center: Vector, dominant_group: str = "") -> str:
    """Semantic body region for a triangle center, in model space (ground at
    z=-0.435, +x = character left). Thresholds follow the measured skeleton
    landmarks (EXPORT_BONES); head/neck/clavicle separation follows the
    transferred deformation weights so facial triangles can never be hidden
    by clothing coverage."""
    x, z = center.x, center.z
    side = "l" if x >= 0.0 else "r"
    ax = abs(x)
    # The rounded head overlaps the neck/shoulder height bands in model space.
    # Bone ownership is the stable anatomical boundary; height-only slicing
    # classified the jaw as neck and clavicle, making clothing masks eat the
    # lower face.
    if dominant_group == "mixamorigHead":
        return "head"
    if dominant_group == "mixamorigNeck":
        return "neck"
    # Arm chain: shoulder 0.13, elbow 0.205, wrist 0.27 (bone landmarks).
    # The arm band lives between z 0 and 0.15; the head's sides and ears sit
    # above it and must never match the arm/shoulder rules.
    # Keep a short wrist band with the hand region so the forearm/hand mask
    # transition stays buried beneath garment cuffs.  Cutting at the wrist
    # landmark itself exposes the low-poly triangle ring as a visible notch.
    if ax > 0.245 and z < 0.15:
        return f"hand_{side}"
    if ax > 0.205 and -0.02 < z < 0.15:
        return f"forearm_{side}"
    if ax > 0.135 and 0.0 < z < 0.15:
        if z < 0.07:
            return f"upper_arm_inner_{side}"
        return f"upper_arm_{side}"
    if ax > 0.105 and 0.03 < z < 0.085:
        return f"armpit_{side}"
    if ax > 0.10 and 0.085 <= z <= 0.15:
        if z > 0.115:
            return f"shoulder_cap_{side}"
        return f"shoulder_{side}"
    if z > 0.165:
        return "head"
    if dominant_group in (
        "mixamorigLeftShoulder",
        "mixamorigRightShoulder",
    ):
        weighted_side = (
            "l" if dominant_group == "mixamorigLeftShoulder" else "r"
        )
        if z > 0.120:
            return f"shoulder_cap_{weighted_side}"
        if z > 0.075:
            return f"clavicle_{weighted_side}"
        return f"upper_chest_{weighted_side}"
    if z > 0.085:
        return f"upper_chest_{side}"
    if z > 0.04:
        return f"upper_chest_{side}"
    if z > -0.03:
        return "chest"
    if z > -0.085:
        return "abdomen"
    if z > -0.148:
        return "hips"
    if z > -0.225:
        return f"thigh_{side}"
    if z > -0.265:
        return f"knee_{side}"
    if z > -0.375:
        return f"shin_{side}"
    return f"foot_{side}"


def bake_armor_regions(body: bpy.types.Object) -> dict:
    """One semantic region id per triangle in UV2.x (TEXCOORD_1) — the
    contract player_character.gdshader's hide_mask relies on. The voxel
    remesh destroys any inherited attributes, so the bake must happen here,
    after the body reaches final model space."""
    mesh = body.data
    while len(mesh.uv_layers) < 2:
        mesh.uv_layers.new(name=f"UVMap{len(mesh.uv_layers)}")
    layer = mesh.uv_layers[1]
    group_names = {group.index: group.name for group in body.vertex_groups}
    counts: dict[str, int] = {}
    for polygon in mesh.polygons:
        group_weights: dict[str, float] = {}
        for vertex_index in polygon.vertices:
            for membership in mesh.vertices[vertex_index].groups:
                group_name = group_names[membership.group]
                group_weights[group_name] = (
                    group_weights.get(group_name, 0.0)
                    + membership.weight
                )
        dominant_group = (
            max(group_weights, key=group_weights.get)
            if group_weights
            else ""
        )
        region = _region_for(polygon.center, dominant_group)
        counts[region] = counts.get(region, 0) + 1
        region_id = float(REGION_IDS[region])
        for loop_index in polygon.loop_indices:
            layer.data[loop_index].uv = (region_id, 0.0)
    return counts


# ---------------------------------------------------------------- idle clip

def _axis_local(pose_bone: bpy.types.PoseBone, world_axis: Vector) -> Vector:
    rotation = (
        bpy.context.object.matrix_world @ pose_bone.matrix
    ).to_quaternion()
    return rotation.inverted() @ world_axis


def _rotate_bone_world(
    armature: bpy.types.Object,
    bone_name: str,
    world_axis: Vector,
    degrees: float,
) -> None:
    pose_bone = armature.pose.bones[bone_name]
    pivot = pose_bone.matrix.translation.copy()
    rotation = Matrix.Rotation(radians(degrees), 4, world_axis)
    pose_bone.matrix = (
        Matrix.Translation(pivot)
        @ rotation
        @ Matrix.Translation(-pivot)
        @ pose_bone.matrix
    )
    bpy.context.view_layer.update()


X = Vector((1.0, 0.0, 0.0))
Y = Vector((0.0, 1.0, 0.0))
Z = Vector((0.0, 0.0, 1.0))

# (bone, world axis, degrees) applied in chain order. Front is -Y, up is +Z,
# +X is the character's left. Rest pose is a strict T-pose and stays untouched;
# this pose exists only inside the idle_relaxed action.
IDLE_BASE_POSE = [
    ("mixamorigSpine1", X, -2.0),           # open chest, not puffed
    ("mixamorigNeck", X, 1.2),              # neutral friendly head
    ("mixamorigLeftShoulder", Y, 4.0),      # relax shoulders down
    ("mixamorigRightShoulder", Y, -4.0),
    ("mixamorigLeftShoulder", Z, 2.0),      # slightly open, not collapsed
    ("mixamorigRightShoulder", Z, -2.0),
    ("mixamorigLeftArm", Y, 64.0),          # hang with ~26 deg of clearance
    ("mixamorigRightArm", Y, -64.0),
    ("mixamorigLeftArm", X, -6.0),          # a few degrees forward
    ("mixamorigRightArm", X, -6.0),
    ("mixamorigLeftForeArm", X, -12.0),     # soft elbows
    ("mixamorigRightForeArm", X, -12.0),
    ("mixamorigLeftHand", X, -4.0),
    ("mixamorigRightHand", X, -4.0),
    ("mixamorigLeftUpLeg", Y, -1.5),        # natural stance width
    ("mixamorigRightUpLeg", Y, 1.5),
    ("mixamorigLeftUpLeg", Z, 2.0),         # toes slightly out
    ("mixamorigRightUpLeg", Z, -4.0),       # right foot a touch more (asym)
    ("mixamorigLeftUpLeg", X, -1.5),        # relaxed knees, feet stay planted
    ("mixamorigRightUpLeg", X, -1.5),
    ("mixamorigLeftLeg", X, 3.0),
    ("mixamorigRightLeg", X, 3.0),
    ("mixamorigLeftFoot", X, -1.5),
    ("mixamorigRightFoot", X, -1.5),
]

# (bone, world axis, amplitude degrees, phase radians). One base frequency so
# a 5.2 s loop closes exactly; phase lags give the settle its follow-through.
IDLE_MOTION = [
    ("mixamorigSpine1", X, 1.05, 0.0),      # breathing
    ("mixamorigSpine2", X, 0.85, 0.35),
    ("mixamorigSpine", Z, 0.40, 1.7),       # restrained weight shift
    ("mixamorigLeftShoulder", Y, -0.65, 0.55),
    ("mixamorigRightShoulder", Y, 0.55, 0.85),
    ("mixamorigNeck", X, 0.50, 0.95),       # tiny head settling
    ("mixamorigHead", Z, 0.30, 1.35),
    ("mixamorigLeftArm", Y, 0.55, 0.75),    # restrained hand follow-through
    ("mixamorigRightArm", Y, -0.45, 1.05),
    ("mixamorigLeftForeArm", X, -0.35, 1.25),
    ("mixamorigRightForeArm", X, -0.30, 1.55),
]


def author_idle(armature: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.fps = IDLE_FPS
    scene.frame_start = 0
    scene.frame_end = IDLE_FRAMES

    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    if armature.animation_data is None:
        armature.animation_data_create()
    action = bpy.data.actions.new(IDLE_NAME)
    armature.animation_data.action = action
    slot = action.slots.new(id_type="OBJECT", name=armature.name)
    armature.animation_data.action_slot = slot

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()

    for bone_name, axis, degrees in IDLE_BASE_POSE:
        _rotate_bone_world(armature, bone_name, axis, degrees)

    hips = armature.pose.bones["mixamorigHips"]
    hips_matrix = hips.matrix.copy()
    hips_matrix.translation = hips_matrix.translation + Vector(
        (0.0, 0.0, IDLE_HIPS_LIFT)
    )
    hips.matrix = hips_matrix
    bpy.context.view_layer.update()

    base_rotation: dict[str, Quaternion] = {}
    motion_axes: dict[tuple[str, tuple], Vector] = {}
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        base_rotation[pose_bone.name] = pose_bone.rotation_quaternion.copy()
    for bone_name, axis, _amplitude, _phase in IDLE_MOTION:
        motion_axes[(bone_name, tuple(axis))] = _axis_local(
            armature.pose.bones[bone_name], axis
        )

    motion_by_bone: dict[str, list] = {}
    for bone_name, axis, amplitude, phase in IDLE_MOTION:
        motion_by_bone.setdefault(bone_name, []).append(
            (motion_axes[(bone_name, tuple(axis))], amplitude, phase)
        )

    keyed_bones = sorted(
        {name for name, _axis, _deg in IDLE_BASE_POSE}
        | set(motion_by_bone)
        | {"mixamorigHips"}
    )
    omega = 2.0 * pi / (IDLE_FRAMES / IDLE_FPS)
    for frame in range(0, IDLE_FRAMES + 1, 3):
        time = frame / IDLE_FPS
        scene.frame_set(frame)
        for bone_name in keyed_bones:
            pose_bone = armature.pose.bones[bone_name]
            rotation = base_rotation[bone_name].copy()
            for axis_local, amplitude, phase in motion_by_bone.get(bone_name, []):
                angle = radians(amplitude) * sin(omega * time + phase)
                rotation = rotation @ Quaternion(axis_local, angle)
            pose_bone.rotation_quaternion = rotation
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
            if bone_name == "mixamorigHips":
                pose_bone.keyframe_insert("location", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- cameras

def add_camera(
    name: str,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    ortho_scale: float | None,
) -> bpy.types.Object:
    bpy.ops.object.camera_add(location=location)
    camera = bpy.context.object
    camera.name = name
    if ortho_scale is not None:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    else:
        camera.data.type = "PERSP"
        camera.data.sensor_fit = "VERTICAL"
        camera.data.angle_y = radians(15.0)
        camera.data.clip_end = 200.0
    PIPE.look_at(camera, Vector(target))
    move_to_collection(camera, "CAMERAS")
    return camera


def build_review_stage() -> dict[str, bpy.types.Object]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "AgX - Medium High Contrast"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.color = (0.09, 0.085, 0.08)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, GROUND_Z))
    ground = bpy.context.object
    ground.name = "ReviewGround"
    ground.data.materials.append(
        PIPE.make_material("ReviewIvory", (0.82, 0.79, 0.69, 1.0), 0.92, 0.1)
    )
    move_to_collection(ground, "CAMERAS")

    for name, location, energy, size, color in [
        ("ReviewKey", (-1.8, -2.2, 2.4), 120.0, 2.4, (1.0, 0.93, 0.82)),
        ("ReviewFill", (1.9, -1.2, 1.0), 45.0, 3.0, (0.82, 0.88, 1.0)),
        ("ReviewRim", (0.4, 2.2, 1.6), 60.0, 1.8, (1.0, 0.85, 0.66)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        PIPE.look_at(light, Vector((0.0, 0.0, 0.1)))
        move_to_collection(light, "CAMERAS")

    cameras = {
        "front": add_camera(
            "CAM_FRONT_ORTHO", (0.0, -3.0, 0.02), (0.0, 0.0, 0.02), 1.08
        ),
        "front_head": add_camera(
            "CAM_FRONT_HEAD", (0.0, -3.0, 0.25), (0.0, 0.0, 0.25), 0.52
        ),
        "three_quarter": add_camera(
            "CAM_THREE_QUARTER", (1.55, -1.75, 0.62), (0.0, 0.0, 0.02), 1.18
        ),
        "side": add_camera(
            "CAM_SIDE_ORTHO", (3.0, 0.0, 0.02), (0.0, 0.0, 0.02), 1.08
        ),
        "game": add_camera(
            "CAM_GAME_APPROX", (2.85, -2.85, 2.95), (0.0, 0.0, -0.05), None
        ),
    }
    return cameras


def add_reference_empty() -> None:
    if not REFERENCE_IMAGE.exists():
        raise RuntimeError(f"Reference image missing: {REFERENCE_IMAGE}")
    image = bpy.data.images.load(str(REFERENCE_IMAGE))
    bpy.ops.object.empty_add(type="IMAGE", location=(0.0, 0.9, 0.03))
    empty = bpy.context.object
    empty.name = "REF_MaleDefault"
    empty.data = image
    empty.rotation_euler = (radians(90.0), 0.0, radians(180.0))
    empty.empty_display_size = 1.26
    empty.empty_image_offset = (-0.5, -0.5)
    move_to_collection(empty, "REFERENCE_ONLY")


def add_socket_helpers() -> None:
    for socket_name, position in SOCKETS.items():
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=position)
        empty = bpy.context.object
        empty.name = f"HELPER_{socket_name}"
        empty.empty_display_size = 0.02
        move_to_collection(empty, "EXPORT_HELPERS")


# ---------------------------------------------------------------- rendering

def render(camera: bpy.types.Object, path: Path) -> None:
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_reviews(cameras: dict, armature: bpy.types.Object) -> None:
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene

    # T-pose stills.
    armature.data.pose_position = "REST"
    for view in ("front", "front_head", "three_quarter", "side"):
        render(cameras[view], REVIEW_DIR / f"tpose_{view}.png")

    # Idle stills at the frame where the base pose is unmodified (frame 0).
    # The idle carries the Mixamo-convention hips lift; the runtime ground
    # offset compensates in-game, so compensate here the same way.
    armature.data.pose_position = "POSE"
    armature.location.z -= IDLE_HIPS_LIFT
    scene.frame_set(0)
    for view in ("front", "front_head", "three_quarter", "side", "game"):
        render(cameras[view], REVIEW_DIR / f"idle_{view}.png")

    # Eight-step turntable in idle.
    pivot_camera = cameras["three_quarter"]
    original = pivot_camera.location.copy()
    radius = Vector((original.x, original.y)).length
    for step in range(8):
        angle = radians(step * 45.0)
        pivot_camera.location = Vector(
            (radius * sin(angle + radians(41.5)),
             -radius * cos(angle + radians(41.5)),
             original.z)
        )
        PIPE.look_at(pivot_camera, Vector((0.0, 0.0, 0.02)))
        render(pivot_camera, REVIEW_DIR / f"turntable_{step}.png")
    pivot_camera.location = original
    PIPE.look_at(pivot_camera, Vector((0.0, 0.0, 0.02)))
    armature.location.z += IDLE_HIPS_LIFT


def render_catalog(
    cameras: dict,
    master_parts: dict,
    catalog: dict,
    armature: bpy.types.Object,
) -> None:
    """One head close-up per catalog option (hair also gets a three-quarter
    view), each rendered with the default face around it so styles are judged
    in context."""
    out_dir = REVIEW_DIR / "catalog"
    out_dir.mkdir(parents=True, exist_ok=True)
    armature.data.pose_position = "REST"
    defaults = {
        "HAIR": master_parts["HairSwoop"],
        "BROWS": master_parts["BrowsPair"],
        "EYES": catalog["eyes_oval_pair"]["object"],
        "MOUTH": catalog["mouth_smile"]["object"],
        "NOSE": catalog["nose_round"]["object"],
    }
    face_objects = set(defaults.values())
    face_objects.update(entry["object"] for entry in catalog.values())
    previous_state = {obj: obj.hide_render for obj in face_objects}
    for stem, entry in catalog.items():
        slot = entry["slot"]
        visible = {defaults[s] for s in defaults if s != slot}
        visible.add(entry["object"])
        for obj in face_objects:
            obj.hide_render = obj not in visible
        render(cameras["front_head"], out_dir / f"{stem}.png")
        if slot == "HAIR":
            render(
                cameras["three_quarter"], out_dir / f"{stem}_three_quarter.png"
            )
    for obj, state in previous_state.items():
        obj.hide_render = state


# ---------------------------------------------------------------- exporting

def export_part(obj: bpy.types.Object, stem: str, socket_name: str) -> dict:
    PARTS_DIR.mkdir(parents=True, exist_ok=True)
    socket = Vector(SOCKETS[socket_name])
    duplicate = obj.copy()
    duplicate.data = obj.data.copy()
    # Optional parts may be hidden in the authoring master, but exports must
    # always contain their selected mesh.
    duplicate.hide_render = False
    duplicate.hide_viewport = False
    bpy.context.scene.collection.objects.link(duplicate)
    # Bake the full object transform into the mesh first (primitives and
    # joined objects keep non-zero object locations), then rebase the data so
    # the part's origin is exactly its socket.
    duplicate.data.transform(duplicate.matrix_world)
    duplicate.matrix_world = Matrix.Identity(4)
    duplicate.data.transform(Matrix.Translation(-socket))
    bpy.ops.object.select_all(action="DESELECT")
    duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicate
    path = PARTS_DIR / f"{stem}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_yup=True,
    )
    stats = {
        "glb": str(path.relative_to(REPO)),
        "socket": socket_name,
        "triangles": triangle_count(duplicate),
        "vertices": len(duplicate.data.vertices),
    }
    bpy.data.objects.remove(duplicate)
    return stats


def export_mannequin(
    body: bpy.types.Object, armature: bpy.types.Object
) -> dict:
    armature.data.pose_position = "POSE"
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(MANNEQUIN_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )
    return {
        "glb": str(MANNEQUIN_GLB.relative_to(REPO)),
        "triangles": triangle_count(body),
        "vertices": len(body.data.vertices),
        "animations": [IDLE_NAME],
    }


# ---------------------------------------------------------------- main

def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    # Materials whose name contains "NoTint" are excluded from runtime color
    # channels by CharacterAssembler (eye highlights stay white when the eye
    # color changes).
    materials = {
        "skin": PIPE.make_material(
            "Suma_Skin", srgb_to_linear(PIPE.COLORS["skin"]), 0.68, 0.18
        ),
        "hair": PIPE.make_material(
            "Suma_Hair", srgb_to_linear(PIPE.COLORS["hair"]), 0.72, 0.16
        ),
        "eyes": PIPE.make_material(
            "Suma_Eyes", srgb_to_linear((0.141, 0.102, 0.078, 1.0)), 0.55, 0.2
        ),
        "mouth": PIPE.make_material(
            "Suma_Mouth", srgb_to_linear((0.36, 0.215, 0.16, 1.0)), 0.48, 0.20
        ),
        "eye_white": PIPE.make_material(
            "Suma_EyeWhite_NoTint",
            srgb_to_linear((0.965, 0.957, 0.94, 1.0)),
            0.55,
            0.12,
        ),
        "highlight": PIPE.make_material(
            "Suma_Highlight_NoTint",
            srgb_to_linear((0.99, 0.985, 0.975, 1.0)),
            0.45,
            0.15,
        ),
        "mouth_inner": PIPE.make_material(
            "Suma_MouthInner_NoTint",
            srgb_to_linear((0.318, 0.153, 0.125, 1.0)),
            0.55,
            0.1,
        ),
        "tongue": PIPE.make_material(
            "Suma_Tongue_NoTint",
            srgb_to_linear((0.875, 0.478, 0.435, 1.0)),
            0.5,
            0.12,
        ),
        "tooth": PIPE.make_material(
            "Suma_Tooth_NoTint",
            srgb_to_linear((0.97, 0.965, 0.95, 1.0)),
            0.5,
            0.12,
        ),
    }

    # Canonical mannequin: identical pipeline to the production build.
    export_rig = PIPE.load_contract_rig()
    PIPE.fit_export_rig(export_rig)
    body = PIPE.import_source()
    PIPE.smooth_source(body)
    body.name = "PlayerMaleBody"
    body.data.name = "PlayerMaleBodyMesh"
    assign_material(body, materials["skin"])
    PIPE.apply_model_scale(body)
    PIPE.parent_with_weights(body, export_rig)
    region_counts = bake_armor_regions(body)
    print("ARMOR_REGIONS_BAKED", json.dumps(region_counts))
    move_to_collection(export_rig, "RIG")
    move_to_collection(body, "BODY_MALE")

    # Master-built parts plus the cozy life-sim face catalog. Face decals are
    # authored in body rest space because their runtime sockets are measured
    # in that same space. Projecting against the current pose puts the decals
    # several centimeters inside the rest-pose head.
    parts = {
        "HairSwoop": build_hair(body, materials["hair"]),
        "BrowsPair": build_brows(materials["hair"]),
        "MoustacheWalrus": build_moustache(materials["hair"]),
    }
    part_collections = {
        "HairSwoop": "DEFAULT_HAIR",
        "BrowsPair": "DEFAULT_BROWS",
        "MoustacheWalrus": "DEFAULT_MOUSTACHE",
    }
    for name, obj in parts.items():
        move_to_collection(obj, part_collections[name])

    export_rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    catalog = FACES.build_catalog(
        {
            "body": body,
            "materials": materials,
            "metaball_object": metaball_object,
            "remesh_smooth": remesh_smooth,
            "join_objects": join_objects,
            "assign_material": assign_material,
            "shade_smooth": shade_smooth,
            "apply_modifier": apply_modifier,
            "hairline_z": hairline_z,
        }
    )
    export_rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    default_catalog_stems = {"eyes_oval_pair", "mouth_smile", "nose_round"}
    default_collections = {
        "EYES": "DEFAULT_EYES",
        "MOUTH": "DEFAULT_MOUTH",
        "NOSE": "DEFAULT_NOSE",
    }
    for stem, entry in catalog.items():
        if stem in default_catalog_stems:
            move_to_collection(entry["object"], default_collections[entry["slot"]])
        else:
            move_to_collection(entry["object"], f"CATALOG_{entry['slot']}")
            # Only the default face renders in the standard review set; the
            # catalog render pass toggles these per style.
            entry["object"].hide_render = True
    # Facial hair remains a reusable authored part, but it is no longer part
    # of the clean default face and must not cover the mouth catalog.
    parts["MoustacheWalrus"].hide_render = True
    parts["MoustacheWalrus"].hide_viewport = True
    collection("OPTIONAL_BEARD")

    author_idle(export_rig)

    cameras = build_review_stage()
    add_reference_empty()
    add_socket_helpers()

    manifest = {
        "space": "model space, ground at z = -0.435, front = -Y, +X = character left",
        "head": {
            "bottom_z": HEAD_BOTTOM,
            "top_z": HEAD_TOP,
            "skull_half_width": SKULL_HALF_WIDTH,
        },
        "sockets_model_space": {k: list(v) for k, v in SOCKETS.items()},
        "idle": {
            "name": IDLE_NAME,
            "fps": IDLE_FPS,
            "frames": IDLE_FRAMES,
            "seconds": IDLE_FRAMES / IDLE_FPS,
        },
        "parts": {},
        # Player-facing option order per slot; the first entry is the default.
        # tools/generate_character_resources.gd turns this into part
        # definitions and the selectable part catalog.
        "catalog": {},
    }

    catalog_manifest: dict[str, list] = {
        "HAIR": [{"stem": "hair_swoop_brown", "display": "Swoop"}]
    }
    for stem, entry in catalog.items():
        catalog_manifest.setdefault(entry["slot"], []).append(
            {"stem": stem, "display": entry["display"]}
        )
    manifest["catalog"] = catalog_manifest

    for obj_name, (stem, socket_name) in PART_EXPORTS.items():
        manifest["parts"][stem] = export_part(parts[obj_name], stem, socket_name)
    for stem, entry in catalog.items():
        manifest["parts"][stem] = export_part(
            entry["object"], stem, entry["socket"]
        )
    manifest["mannequin"] = export_mannequin(body, export_rig)

    # Master file keeps everything, including reference and helpers. Hide the
    # non-default catalog styles in the viewport so opening the file shows the
    # clean default face; the catalog render pass drives hide_render itself.
    for stem, entry in catalog.items():
        if stem not in default_catalog_stems:
            entry["object"].hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    render_reviews(cameras, export_rig)
    render_catalog(cameras, parts, catalog, export_rig)
    MANIFEST_OUT.write_text(json.dumps(manifest, indent=2))
    print("CHARACTER_MASTER_BUILT", json.dumps(manifest["parts"], indent=2))
    print("MANNEQUIN", manifest["mannequin"])


if __name__ == "__main__":
    main()
