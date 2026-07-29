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
EYE_Z = 0.250
EYE_X = 0.048
EYE_HALF = Vector((0.0145, 0.010, 0.023))
BROW_Z = 0.287
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

PART_EXPORTS = {
    # object name -> (glb file stem, socket name)
    "HairSwoop": ("hair_swoop_brown", "HairSocket"),
    "EyesPair": ("eyes_oval_pair", "EyesSocket"),
    "BrowsPair": ("brows_soft_pair", "BrowsSocket"),
    "NoseRound": ("nose_round", "NoseSocket"),
    "MoustacheWalrus": ("moustache_walrus", "MoustacheSocket"),
    "MouthSmile": ("mouth_smile", "MouthSocket"),
}

IDLE_FPS = 30
IDLE_FRAMES = 156  # 5.2 s loop, closes exactly (all phases are 1x frequency)
IDLE_NAME = "idle_relaxed"


def load_player_pipeline():
    spec = importlib.util.spec_from_file_location(
        "build_player_male",
        REPO / "art_source/player_male/build_player_male.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PIPE = load_player_pipeline()


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

def build_eyes(material: bpy.types.Material) -> bpy.types.Object:
    halves = []
    for sign in (1.0, -1.0):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=20,
            ring_count=12,
            location=(sign * EYE_X, -0.118, EYE_Z),
        )
        eye = bpy.context.object
        eye.name = "EyeHalf"
        eye.scale = EYE_HALF
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        halves.append(eye)
    eyes = join_objects("EyesPair", halves)
    assign_material(eyes, material)
    shade_smooth(eyes)
    return eyes


def build_brows(material: bpy.types.Material) -> bpy.types.Object:
    """Two short, thick, soft bars with rounded ends and a gentle arch."""
    halves = []
    for sign in (1.0, -1.0):
        curve = bpy.data.curves.new("BrowCurve", type="CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 8
        curve.bevel_depth = 0.0105
        curve.bevel_resolution = 4
        curve.use_fill_caps = True
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(2)
        points = [
            (sign * 0.024, -0.1185, BROW_Z - 0.004),
            (sign * 0.047, -0.1225, BROW_Z + 0.004),
            (sign * 0.070, -0.1170, BROW_Z - 0.002),
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


def build_nose(material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=16, location=(0.0, -0.140, NOSE_Z - 0.006)
    )
    nose = bpy.context.object
    nose.name = "NoseRound"
    nose.scale = (0.021, 0.025, 0.020)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(nose, material)
    shade_smooth(nose)
    return nose


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


def build_mouth(material: bpy.types.Material) -> bpy.types.Object:
    curve = bpy.data.curves.new("MouthCurve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 8
    curve.bevel_depth = 0.004
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(2)
    for point, coordinate in zip(
        spline.bezier_points,
        [
            (-0.014, -0.1335, MOUTH_Z + 0.008),
            (0.0, -0.137, MOUTH_Z + 0.003),
            (0.014, -0.1335, MOUTH_Z + 0.008),
        ],
    ):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new("MouthSmile", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mouth = bpy.context.object
    mouth.name = "MouthSmile"
    assign_material(mouth, material)
    shade_smooth(mouth)
    return mouth


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
    ("mixamorigLeftArm", Y, 72.0),          # hang with ~15 deg of clearance
    ("mixamorigRightArm", Y, -72.0),
    ("mixamorigLeftArm", X, -5.0),          # a few degrees forward
    ("mixamorigRightArm", X, -5.0),
    ("mixamorigLeftForeArm", X, -10.0),     # soft elbows
    ("mixamorigRightForeArm", X, -10.0),
    ("mixamorigLeftHand", X, -3.0),
    ("mixamorigRightHand", X, -3.0),
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
    armature.data.pose_position = "POSE"
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


# ---------------------------------------------------------------- exporting

def export_part(obj: bpy.types.Object, stem: str, socket_name: str) -> dict:
    PARTS_DIR.mkdir(parents=True, exist_ok=True)
    socket = Vector(SOCKETS[socket_name])
    duplicate = obj.copy()
    duplicate.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(duplicate)
    duplicate.data.transform(Matrix.Translation(-socket))
    duplicate.location = (0.0, 0.0, 0.0)
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

    materials = {
        "skin": PIPE.make_material(
            "Suma_Skin", srgb_to_linear(PIPE.COLORS["skin"]), 0.68, 0.18
        ),
        "hair": PIPE.make_material(
            "Suma_Hair", srgb_to_linear(PIPE.COLORS["hair"]), 0.72, 0.16
        ),
        "eyes": PIPE.make_material(
            "Suma_Eyes", srgb_to_linear(PIPE.COLORS["eyes"]), 0.24, 0.38
        ),
        "mouth": PIPE.make_material(
            "Suma_Mouth", srgb_to_linear((0.36, 0.215, 0.16, 1.0)), 0.48, 0.20
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
    move_to_collection(export_rig, "RIG")
    move_to_collection(body, "BODY_MALE")

    # Rebuilt default parts, fitted to the measured head.
    parts = {
        "HairSwoop": build_hair(body, materials["hair"]),
        "EyesPair": build_eyes(materials["eyes"]),
        "BrowsPair": build_brows(materials["hair"]),
        "NoseRound": build_nose(materials["skin"]),
        "MoustacheWalrus": build_moustache(materials["hair"]),
        "MouthSmile": build_mouth(materials["mouth"]),
    }
    part_collections = {
        "HairSwoop": "DEFAULT_HAIR",
        "EyesPair": "DEFAULT_EYES",
        "BrowsPair": "DEFAULT_BROWS",
        "NoseRound": "DEFAULT_NOSE",
        "MoustacheWalrus": "DEFAULT_MOUSTACHE",
        "MouthSmile": "DEFAULT_MOUTH",
    }
    for name, obj in parts.items():
        move_to_collection(obj, part_collections[name])
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
    }

    for obj_name, (stem, socket_name) in PART_EXPORTS.items():
        manifest["parts"][stem] = export_part(parts[obj_name], stem, socket_name)
    manifest["mannequin"] = export_mannequin(body, export_rig)

    # Master file keeps everything, including reference and helpers.
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    render_reviews(cameras, export_rig)
    MANIFEST_OUT.write_text(json.dumps(manifest, indent=2))
    print("CHARACTER_MASTER_BUILT", json.dumps(manifest["parts"], indent=2))
    print("MANNEQUIN", manifest["mannequin"])


if __name__ == "__main__":
    main()
