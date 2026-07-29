"""Build the smooth, palette-matched, Rigify-authored Imota player.

The supplied GLB is one connected 1,800-triangle surface with positions only.
This pipeline keeps its silhouette, applies offline Catmull-Clark smoothing,
adds material-separated facial features from the admitted reference, skins it
to the game's stable deformation contract, generates a fitted Rigify control
rig, saves the animator source .blend, exports the runtime GLB, and renders
quality-gate views.

Run with Blender 4.5 LTS:
    blender --background --factory-startup --python build_player_male.py
"""

from __future__ import annotations

from math import radians
from pathlib import Path

import bpy
from mathutils import Vector


REPO = Path(r"C:\Dev\suma-nook")
SOURCE = Path(r"C:\Users\Luka\Downloads\player_male.glb")
CONTRACT_MODEL = REPO / "assets/3d/reworked/suma_player.glb"
OUT_DIR = REPO / "art_source/player_male"
BLEND_OUT = OUT_DIR / "player_male_rigify.blend"
GLB_OUT = REPO / "assets/3d/reworked/player_male_rigged.glb"
CAPTURE_DIR = OUT_DIR / "captures"

MODEL_SCALE = 0.434
FRONT_Y = -1.0

COLORS = {
    # gg_render_target_palette / gg_pnw_mossy_v1
    "skin": (0.8784, 0.6902, 0.4235, 1.0),  # skin_light / #E0B06C
    "hair": (0.3294, 0.2196, 0.1490, 1.0),  # hair_primary / #543826
    "eyes": (0.2196, 0.1412, 0.0980, 1.0),  # hair_deep / #382419
    "mouth": (0.5882, 0.4510, 0.3882, 1.0),  # skin_shadow / #967363
}

EXPORT_BONES = {
    "mixamorigHips": ((0.0, 0.018, -0.135), (0.0, 0.020, -0.080)),
    "mixamorigSpine": ((0.0, 0.020, -0.080), (0.0, 0.022, -0.025)),
    "mixamorigSpine1": ((0.0, 0.022, -0.025), (0.0, 0.024, 0.045)),
    "mixamorigSpine2": ((0.0, 0.024, 0.045), (0.0, 0.026, 0.120)),
    "mixamorigNeck": ((0.0, 0.026, 0.120), (0.0, 0.018, 0.165)),
    "mixamorigHead": ((0.0, 0.018, 0.165), (0.0, 0.012, 0.335)),
    "mixamorigLeftShoulder": ((0.045, 0.024, 0.105), (0.130, 0.024, 0.100)),
    "mixamorigLeftArm": ((0.130, 0.024, 0.100), (0.205, 0.020, 0.095)),
    "mixamorigLeftForeArm": ((0.205, 0.020, 0.095), (0.270, 0.016, 0.092)),
    "mixamorigLeftHand": ((0.270, 0.016, 0.092), (0.302, 0.010, 0.090)),
    "mixamorigRightShoulder": ((-0.045, 0.024, 0.105), (-0.130, 0.024, 0.100)),
    "mixamorigRightArm": ((-0.130, 0.024, 0.100), (-0.205, 0.020, 0.095)),
    "mixamorigRightForeArm": ((-0.205, 0.020, 0.095), (-0.270, 0.016, 0.092)),
    "mixamorigRightHand": ((-0.270, 0.016, 0.092), (-0.302, 0.010, 0.090)),
    "mixamorigLeftUpLeg": ((0.060, 0.012, -0.135), (0.062, 0.018, -0.245)),
    "mixamorigLeftLeg": ((0.062, 0.018, -0.245), (0.064, 0.024, -0.370)),
    "mixamorigLeftFoot": ((0.064, 0.024, -0.370), (0.062, -0.048, -0.418)),
    "mixamorigLeftToeBase": ((0.062, -0.048, -0.418), (0.060, -0.108, -0.420)),
    "mixamorigRightUpLeg": ((-0.060, 0.012, -0.135), (-0.062, 0.018, -0.245)),
    "mixamorigRightLeg": ((-0.062, 0.018, -0.245), (-0.064, 0.024, -0.370)),
    "mixamorigRightFoot": ((-0.064, 0.024, -0.370), (-0.062, -0.048, -0.418)),
    "mixamorigRightToeBase": ((-0.062, -0.048, -0.418), (-0.060, -0.108, -0.420)),
}


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="rigify")
    CAPTURE_DIR.mkdir(parents=True, exist_ok=True)
    GLB_OUT.parent.mkdir(parents=True, exist_ok=True)


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
    specular_ior_level: float,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Specular IOR Level"].default_value = specular_ior_level
    return material


def load_contract_rig() -> bpy.types.Object:
    bpy.ops.import_scene.gltf(filepath=str(CONTRACT_MODEL))
    armatures = [
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    ]
    if len(armatures) != 1:
        raise RuntimeError(
            f"Expected one contract armature, found {len(armatures)}"
        )
    armature = armatures[0]
    armature.name = "GameExportRig"
    armature.data.name = "GameExportSkeleton"

    # Delete only the old player's geometry. Keep the armature and imported
    # idle action so the replacement honors the established animation contract.
    old_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in old_meshes:
        obj.select_set(True)
    bpy.ops.object.delete()
    return armature


def import_source() -> bpy.types.Object:
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    imported = [
        obj
        for obj in bpy.context.scene.objects
        if obj not in existing and obj.type == "MESH"
    ]
    if len(imported) != 1:
        raise RuntimeError(f"Expected one supplied mesh, found {len(imported)}")
    mesh = imported[0]
    mesh.name = "PlayerMaleBody"
    mesh.data.name = "PlayerMaleSmoothMesh"
    return mesh


def add_uv_feature(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    segments: int = 16,
    rings: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def add_curve_feature(
    name: str,
    points: list[tuple[float, float, float]],
    bevel_depth: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    curve_data = bpy.data.curves.new(f"{name}Curve", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.resolution_u = 2
    curve_data.bevel_depth = bevel_depth
    curve_data.bevel_resolution = 1
    spline = curve_data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def classify_source_hair(
    mesh: bpy.types.Object,
    skin: bpy.types.Material,
    hair: bpy.types.Material,
) -> None:
    mesh.data.materials.clear()
    mesh.data.materials.append(skin)
    mesh.data.materials.append(hair)
    mesh.data.update()
    # The source has no material IDs. Its crown/quiff are nevertheless modeled
    # as distinct silhouette relief, so use conservative spatial regions that
    # avoid painting the forehead while preserving the authored hair outline.
    for polygon in mesh.data.polygons:
        center = polygon.center
        crown = center.z > 0.775
        side_lock = (
            center.z > 0.52
            and abs(center.x) > 0.245
            and center.y < 0.16
        )
        rear_cap = center.z > 0.59 and center.y > 0.16
        polygon.material_index = 1 if crown or side_lock or rear_cap else 0
        polygon.use_smooth = True


def build_facial_features(materials: dict[str, bpy.types.Material]) -> list[bpy.types.Object]:
    # Front is -Y. Features overlap the supplied relief by a few millimeters
    # after scale, preventing z-fighting while retaining the source silhouette.
    objects = [
        add_uv_feature(
            "EyeL",
            (0.122, -0.348, 0.500),
            (0.050, 0.026, 0.078),
            materials["eyes"],
        ),
        add_uv_feature(
            "EyeR",
            (-0.122, -0.348, 0.500),
            (0.050, 0.026, 0.078),
            materials["eyes"],
        ),
        add_uv_feature(
            "MoustacheL",
            (0.060, -0.352, 0.307),
            (0.096, 0.023, 0.043),
            materials["hair"],
            rotation=(0.0, radians(-7.0), radians(-8.0)),
        ),
        add_uv_feature(
            "MoustacheR",
            (-0.060, -0.352, 0.307),
            (0.096, 0.023, 0.043),
            materials["hair"],
            rotation=(0.0, radians(7.0), radians(8.0)),
        ),
        add_curve_feature(
            "BrowL",
            [
                (0.065, -0.366, 0.620),
                (0.122, -0.376, 0.642),
                (0.182, -0.357, 0.620),
            ],
            0.021,
            materials["hair"],
        ),
        add_curve_feature(
            "BrowR",
            [
                (-0.065, -0.366, 0.620),
                (-0.122, -0.376, 0.642),
                (-0.182, -0.357, 0.620),
            ],
            0.021,
            materials["hair"],
        ),
        add_curve_feature(
            "Mouth",
            [
                (-0.040, -0.374, 0.248),
                (0.000, -0.383, 0.236),
                (0.040, -0.374, 0.248),
            ],
            0.012,
            materials["mouth"],
        ),
    ]
    return objects


def join_module(
    name: str,
    parts: list[bpy.types.Object],
    material: bpy.types.Material,
) -> bpy.types.Object:
    if not parts:
        raise RuntimeError(f"Module {name} has no geometry")
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    module = parts[0]
    module.name = name
    module.data.name = f"{name}Mesh"
    module.data.materials.clear()
    module.data.materials.append(material)
    for polygon in module.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
    return module


def build_modular_head(
    materials: dict[str, bpy.types.Material],
) -> list[bpy.types.Object]:
    modules = [
        add_uv_feature(
            "EyeL",
            (0.122, -0.325, 0.500),
            (0.050, 0.024, 0.078),
            materials["eyes"],
        ),
        add_uv_feature(
            "EyeR",
            (-0.122, -0.325, 0.500),
            (0.050, 0.024, 0.078),
            materials["eyes"],
        ),
        add_uv_feature(
            "Nose",
            (0.000, -0.370, 0.395),
            (0.072, 0.055, 0.070),
            materials["skin"],
            segments=20,
            rings=10,
        ),
        join_module(
            "Brows",
            [
                add_curve_feature(
                    "BrowLPart",
                    [
                        (0.065, -0.338, 0.620),
                        (0.122, -0.347, 0.642),
                        (0.182, -0.334, 0.620),
                    ],
                    0.021,
                    materials["hair"],
                ),
                add_curve_feature(
                    "BrowRPart",
                    [
                        (-0.065, -0.338, 0.620),
                        (-0.122, -0.347, 0.642),
                        (-0.182, -0.334, 0.620),
                    ],
                    0.021,
                    materials["hair"],
                ),
            ],
            materials["hair"],
        ),
        join_module(
            "Moustache",
            [
                add_uv_feature(
                    "MoustacheLPart",
                    (0.060, -0.337, 0.307),
                    (0.096, 0.022, 0.043),
                    materials["hair"],
                    rotation=(0.0, radians(-7.0), radians(-8.0)),
                ),
                add_uv_feature(
                    "MoustacheRPart",
                    (-0.060, -0.337, 0.307),
                    (0.096, 0.022, 0.043),
                    materials["hair"],
                    rotation=(0.0, radians(7.0), radians(8.0)),
                ),
            ],
            materials["hair"],
        ),
        add_curve_feature(
            "Mouth",
            [
                (-0.040, -0.337, 0.248),
                (0.000, -0.346, 0.236),
                (0.040, -0.337, 0.248),
            ],
            0.012,
            materials["mouth"],
        ),
    ]

    # Four stable hairstyle nodes match PlayerProfile.hair_style 0..3. Each
    # style is one head-weighted mesh, so inactive styles cost no draw call.
    hair_00 = join_module(
        "Hair00",
        [
            add_uv_feature(
                "Hair00Cap",
                (0.0, 0.020, 0.735),
                (0.385, 0.355, 0.305),
                materials["hair"],
                segments=20,
                rings=10,
            ),
            add_uv_feature(
                "Hair00SideL",
                (0.265, 0.020, 0.625),
                (0.105, 0.220, 0.215),
                materials["hair"],
            ),
            add_uv_feature(
                "Hair00SideR",
                (-0.265, 0.020, 0.625),
                (0.105, 0.220, 0.215),
                materials["hair"],
            ),
            add_uv_feature(
                "Hair00Quiff",
                (0.035, -0.180, 0.875),
                (0.275, 0.165, 0.145),
                materials["hair"],
                rotation=(radians(4.0), radians(-11.0), radians(-8.0)),
                segments=20,
                rings=10,
            ),
            add_uv_feature(
                "Hair00Tip",
                (-0.105, -0.150, 0.965),
                (0.085, 0.105, 0.115),
                materials["hair"],
                rotation=(radians(-12.0), radians(8.0), radians(-18.0)),
            ),
        ],
        materials["hair"],
    )
    hair_01 = join_module(
        "Hair01",
        [
            add_uv_feature(
                "Hair01Cap",
                (0.0, 0.020, 0.755),
                (0.380, 0.350, 0.285),
                materials["hair"],
                segments=20,
                rings=10,
            ),
            add_uv_feature(
                "Hair01Tuft",
                (-0.095, -0.195, 0.845),
                (0.105, 0.105, 0.095),
                materials["hair"],
                rotation=(0.0, radians(15.0), radians(-22.0)),
            ),
        ],
        materials["hair"],
    )
    hair_02 = join_module(
        "Hair02",
        [
            add_uv_feature(
                "Hair02Cap",
                (0.0, 0.020, 0.735),
                (0.385, 0.355, 0.300),
                materials["hair"],
                segments=20,
                rings=10,
            ),
            add_uv_feature(
                "Hair02Bun",
                (0.0, 0.285, 0.785),
                (0.175, 0.165, 0.175),
                materials["hair"],
                segments=20,
                rings=10,
            ),
        ],
        materials["hair"],
    )
    hair_03 = join_module(
        "Hair03",
        [
            add_uv_feature(
                "Hair03Cap",
                (0.0, 0.020, 0.735),
                (0.385, 0.355, 0.300),
                materials["hair"],
                segments=20,
                rings=10,
            ),
            add_uv_feature(
                "Hair03Fall",
                (0.0, 0.215, 0.485),
                (0.300, 0.155, 0.390),
                materials["hair"],
                segments=20,
                rings=10,
            ),
        ],
        materials["hair"],
    )
    modules.extend([hair_00, hair_01, hair_02, hair_03])
    return modules


def smooth_source(mesh: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    # The source joins limbs through very small low-poly necks. Plain
    # Catmull-Clark shrinks those junctions until shoulders and hips visibly
    # separate. A one-time voxel remesh makes the surface watertight first,
    # then a restrained smooth pass removes the voxel cadence.
    remesh = mesh.modifiers.new("WatertightOfflineSmooth", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.022
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth = mesh.modifiers.new("ClaySurfaceRelax", "SMOOTH")
    smooth.factor = 0.38
    smooth.iterations = 6
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    for polygon in mesh.data.polygons:
        polygon.use_smooth = True


def join_character_mesh(
    body: bpy.types.Object,
    features: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    canonical = [
        materials["skin"],
        materials["hair"],
        materials["eyes"],
        materials["mouth"],
    ]

    bpy.ops.object.select_all(action="DESELECT")
    for obj in [body, *features]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "PlayerMale"
    body.data.name = "PlayerMaleSmoothMesh"

    # The source GLB supplies no materials or part IDs, and Blender's join
    # operator can collapse each feature object's local slot zero. Rebuild the
    # four stable palette surfaces from the admitted front-view landmarks.
    body.data.materials.clear()
    for material in canonical:
        body.data.materials.append(material)
    body.data.update()
    for polygon in body.data.polygons:
        center = polygon.center
        material_index = 0
        crown = center.z > (
            0.70 + 0.10 * max(0.0, 1.0 - abs(center.x) / 0.30)
        )
        side_lock = (
            center.z > 0.48
            and abs(center.x) > 0.205
            and center.y < 0.22
        )
        rear_cap = center.z > 0.51 and center.y > 0.02
        brow = (
            0.575 < center.z < 0.685
            and 0.035 < abs(center.x) < 0.215
            and center.y < -0.32
        )
        moustache = (
            0.245 < center.z < 0.365
            and abs(center.x) < 0.195
            and center.y < -0.325
        )
        eye = (
            0.405 < center.z < 0.585
            and 0.050 < abs(center.x) < 0.205
            and center.y < -0.315
        )
        mouth = (
            0.205 < center.z < 0.275
            and abs(center.x) < 0.070
            and center.y < -0.335
        )
        if crown or side_lock or rear_cap or brow or moustache:
            material_index = 1
        if eye:
            material_index = 2
        if mouth:
            material_index = 3
        polygon.material_index = material_index

    body.scale = Vector((MODEL_SCALE, MODEL_SCALE, MODEL_SCALE))
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return body


def fit_export_rig(armature: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = armature.data.edit_bones
    for name, (head, tail) in EXPORT_BONES.items():
        if name not in bones:
            raise RuntimeError(f"Contract rig is missing required bone {name}")
        bones[name].head = head
        bones[name].tail = tail

    # Compress the two simple finger chains into the rounded hand volume while
    # retaining all stable bone names needed by existing authored animations.
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        hand = EXPORT_BONES[f"mixamorig{side}Hand"][0]
        finger_names = [
            f"mixamorig{side}HandThumb1",
            f"mixamorig{side}HandThumb2",
            f"mixamorig{side}HandThumb3",
            f"mixamorig{side}HandIndex1",
            f"mixamorig{side}HandIndex2",
            f"mixamorig{side}HandIndex3",
        ]
        for index, name in enumerate(finger_names):
            if name not in bones:
                continue
            chain_index = index % 3
            lane = -0.008 if index < 3 else 0.008
            start_x = abs(hand[0]) + 0.008 + chain_index * 0.008
            end_x = start_x + 0.010
            bones[name].head = (
                sign * start_x,
                hand[1] + lane,
                hand[2] - (0.006 if index < 3 else 0.0),
            )
            bones[name].tail = (
                sign * end_x,
                hand[1] + lane,
                hand[2] - (0.008 if index < 3 else 0.0),
            )
    bpy.ops.object.mode_set(mode="OBJECT")


def parent_with_weights(
    mesh: bpy.types.Object, armature: bpy.types.Object
) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    result = bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    if "FINISHED" not in result:
        raise RuntimeError(f"Automatic armature parenting failed: {result}")

    # Facial features and hair must move as a calm rigid head surface. Bone
    # heat may leak toward shoulder bones on a chibi head, so explicitly lock
    # all upper-head vertices to the head bone.
    head_group = mesh.vertex_groups.get("mixamorigHead")
    if head_group is None:
        head_group = mesh.vertex_groups.new(name="mixamorigHead")
    head_vertices = [
        vertex.index for vertex in mesh.data.vertices if vertex.co.z > 0.155
    ]
    for group in mesh.vertex_groups:
        if group.name == "mixamorigHead":
            continue
        group.remove(head_vertices)
    head_group.add(head_vertices, 1.0, "REPLACE")

    if not any(modifier.type == "ARMATURE" for modifier in mesh.modifiers):
        modifier = mesh.modifiers.new("GameExportRig", "ARMATURE")
        modifier.object = armature


def apply_model_scale(obj: bpy.types.Object) -> None:
    obj.location *= MODEL_SCALE
    obj.scale = Vector((MODEL_SCALE, MODEL_SCALE, MODEL_SCALE))
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def attach_head_module(
    module: bpy.types.Object, armature: bpy.types.Object
) -> None:
    """Mark a rigid module for Godot's live head-socket binder.

    Blender/glTF bone parenting does not preserve parent-inverse transforms
    consistently. Exporting the reviewed modules in model space lets Godot
    preserve their exact fit while reparenting them to a BoneAttachment3D
    before the first animation frame. The body remains the sole skinned mesh.
    """
    apply_model_scale(module)
    module["imota_socket"] = "head"


def fit_rigify_metarig(export_rig: bpy.types.Object) -> bpy.types.Object:
    bpy.ops.object.armature_basic_human_metarig_add()
    metarig = bpy.context.object
    metarig.name = "PlayerMale_RigifyMeta"
    metarig.data.name = "PlayerMale_RigifyMeta"

    # Metarig spine segmentation follows the compact stylized body, while the
    # limb joint locations match the game export skeleton exactly.
    fitted = {
        "spine": ((0.0, 0.018, -0.150), (0.0, 0.020, -0.095)),
        "spine.001": ((0.0, 0.020, -0.095), (0.0, 0.022, -0.035)),
        "spine.002": ((0.0, 0.022, -0.035), (0.0, 0.024, 0.045)),
        "spine.003": ((0.0, 0.024, 0.045), (0.0, 0.026, 0.120)),
        "spine.004": ((0.0, 0.026, 0.120), (0.0, 0.018, 0.165)),
        "spine.005": ((0.0, 0.018, 0.165), (0.0, 0.012, 0.225)),
        "spine.006": ((0.0, 0.012, 0.225), (0.0, 0.006, 0.375)),
        "shoulder.L": EXPORT_BONES["mixamorigLeftShoulder"],
        "upper_arm.L": EXPORT_BONES["mixamorigLeftArm"],
        "forearm.L": EXPORT_BONES["mixamorigLeftForeArm"],
        "hand.L": EXPORT_BONES["mixamorigLeftHand"],
        "shoulder.R": EXPORT_BONES["mixamorigRightShoulder"],
        "upper_arm.R": EXPORT_BONES["mixamorigRightArm"],
        "forearm.R": EXPORT_BONES["mixamorigRightForeArm"],
        "hand.R": EXPORT_BONES["mixamorigRightHand"],
        "thigh.L": EXPORT_BONES["mixamorigLeftUpLeg"],
        "shin.L": EXPORT_BONES["mixamorigLeftLeg"],
        "foot.L": EXPORT_BONES["mixamorigLeftFoot"],
        "toe.L": EXPORT_BONES["mixamorigLeftToeBase"],
        "thigh.R": EXPORT_BONES["mixamorigRightUpLeg"],
        "shin.R": EXPORT_BONES["mixamorigRightLeg"],
        "foot.R": EXPORT_BONES["mixamorigRightFoot"],
        "toe.R": EXPORT_BONES["mixamorigRightToeBase"],
        "pelvis.L": ((0.0, 0.018, -0.150), (0.065, -0.010, -0.125)),
        "pelvis.R": ((0.0, 0.018, -0.150), (-0.065, -0.010, -0.125)),
        "breast.L": ((0.045, 0.020, 0.055), (0.045, -0.035, 0.055)),
        "breast.R": ((-0.045, 0.020, 0.055), (-0.045, -0.035, 0.055)),
        "heel.02.L": ((0.040, 0.045, -0.425), (0.085, 0.045, -0.425)),
        "heel.02.R": ((-0.040, 0.045, -0.425), (-0.085, 0.045, -0.425)),
    }
    bpy.context.view_layer.objects.active = metarig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail) in fitted.items():
        bone = metarig.data.edit_bones.get(name)
        if bone is None:
            raise RuntimeError(f"Rigify metarig missing bone {name}")
        bone.head = head
        bone.tail = tail
    bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    metarig.select_set(True)
    bpy.context.view_layer.objects.active = metarig
    bpy.ops.pose.rigify_generate()
    generated = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "ARMATURE"
        and obj not in {metarig, export_rig}
        and obj.name.startswith("RIG-")
    ]
    if len(generated) != 1:
        raise RuntimeError(
            f"Expected one generated Rigify rig, found {[obj.name for obj in generated]}"
        )
    control_rig = generated[0]
    control_rig.name = "PlayerMale_Rigify"
    control_rig.data.name = "PlayerMale_Rigify"
    return control_rig


def connect_rigify_to_export(
    control_rig: bpy.types.Object, export_rig: bpy.types.Object
) -> None:
    mapping = {
        "mixamorigHips": "DEF-spine",
        "mixamorigSpine": "DEF-spine.001",
        "mixamorigSpine1": "DEF-spine.002",
        "mixamorigSpine2": "DEF-spine.003",
        "mixamorigNeck": "DEF-spine.004",
        "mixamorigHead": "DEF-spine.006",
        "mixamorigLeftShoulder": "DEF-shoulder.L",
        "mixamorigLeftArm": "DEF-upper_arm.L",
        "mixamorigLeftForeArm": "DEF-forearm.L",
        "mixamorigLeftHand": "DEF-hand.L",
        "mixamorigRightShoulder": "DEF-shoulder.R",
        "mixamorigRightArm": "DEF-upper_arm.R",
        "mixamorigRightForeArm": "DEF-forearm.R",
        "mixamorigRightHand": "DEF-hand.R",
        "mixamorigLeftUpLeg": "DEF-thigh.L",
        "mixamorigLeftLeg": "DEF-shin.L",
        "mixamorigLeftFoot": "DEF-foot.L",
        "mixamorigLeftToeBase": "DEF-toe.L",
        "mixamorigRightUpLeg": "DEF-thigh.R",
        "mixamorigRightLeg": "DEF-shin.R",
        "mixamorigRightFoot": "DEF-foot.R",
        "mixamorigRightToeBase": "DEF-toe.R",
    }
    available = {bone.name for bone in control_rig.pose.bones}
    for export_name, rigify_name in mapping.items():
        if rigify_name not in available:
            deform_names = sorted(
                name for name in available if name.startswith("DEF-")
            )
            raise RuntimeError(
                f"Generated Rigify rig missing {rigify_name}; "
                f"available deform bones: {deform_names}"
            )
        bone = export_rig.pose.bones.get(export_name)
        if bone is None:
            raise RuntimeError(f"Export rig missing {export_name}")
        constraint = bone.constraints.new("COPY_TRANSFORMS")
        constraint.name = "RigifyAuthoringDriver"
        constraint.target = control_rig
        constraint.subtarget = rigify_name
        constraint.target_space = "WORLD"
        constraint.owner_space = "WORLD"


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def prepare_review_scene(
    mesh: bpy.types.Object,
    modules: list[bpy.types.Object],
    metarig: bpy.types.Object,
    control_rig: bpy.types.Object,
    export_rig: bpy.types.Object,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    metarig.hide_render = True
    control_rig.hide_render = True
    export_rig.hide_render = True
    for module in modules:
        module.hide_render = (
            module.name.startswith("Hair") and module.name != "Hair00"
        )
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.0
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.color = (0.035, 0.028, 0.022)

    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0.0, 0.0, -0.435))
    ground = bpy.context.object
    ground.name = "ReviewGround"
    ground_material = make_material(
        "ReviewWarmIvory", (0.82, 0.79, 0.69, 1.0), 0.92, 0.12
    )
    ground.data.materials.append(ground_material)

    bpy.ops.object.light_add(
        type="AREA", location=(-1.8, -2.2, 2.4)
    )
    key = bpy.context.object
    key.name = "ReviewKey"
    key.data.energy = 95.0
    key.data.shape = "DISK"
    key.data.size = 2.2
    key.data.color = (1.0, 0.82, 0.64)
    look_at(key, Vector((0.0, 0.0, 0.0)))

    bpy.ops.object.light_add(type="AREA", location=(1.8, -0.8, 1.0))
    fill = bpy.context.object
    fill.name = "ReviewFill"
    fill.data.energy = 36.0
    fill.data.size = 2.8
    fill.data.color = (0.70, 0.82, 1.0)
    look_at(fill, Vector((0.0, 0.0, 0.0)))

    bpy.ops.object.light_add(type="AREA", location=(0.4, 2.0, 1.5))
    rim = bpy.context.object
    rim.name = "ReviewRim"
    rim.data.energy = 55.0
    rim.data.size = 1.6
    rim.data.color = (1.0, 0.72, 0.45)
    look_at(rim, Vector((0.0, 0.0, 0.1)))

    bpy.ops.object.camera_add(location=(0.0, -2.2, 0.05))
    camera = bpy.context.object
    camera.name = "ReviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.15
    scene.camera = camera
    return ground, camera


def render_views(camera: bpy.types.Object) -> None:
    scene = bpy.context.scene
    views = {
        "front": ((0.0, -2.2, 0.05), (0.0, 0.0, 0.0), 1.15),
        "back": ((0.0, 2.2, 0.05), (0.0, 0.0, 0.0), 1.15),
        "side": ((2.2, 0.0, 0.05), (0.0, 0.0, 0.0), 1.15),
        "three-quarter": ((1.55, -1.75, 0.70), (0.0, 0.0, 0.0), 1.22),
        "isometric": ((1.35, -1.70, 1.30), (0.0, 0.0, -0.02), 1.30),
    }
    for view_name, (location, target, scale) in views.items():
        camera.location = location
        camera.data.ortho_scale = scale
        look_at(camera, Vector(target))
        scene.render.filepath = str(CAPTURE_DIR / f"{view_name}.png")
        bpy.ops.render.render(write_still=True)


def remove_authoring_constraints(export_rig: bpy.types.Object) -> None:
    for bone in export_rig.pose.bones:
        for constraint in list(bone.constraints):
            if constraint.name == "RigifyAuthoringDriver":
                bone.constraints.remove(constraint)


def export_runtime(
    mesh: bpy.types.Object,
    modules: list[bpy.types.Object],
    export_rig: bpy.types.Object,
    review_objects: list[bpy.types.Object],
) -> None:
    for obj in review_objects:
        obj.hide_viewport = True
        obj.hide_render = True
    remove_authoring_constraints(export_rig)
    export_rig.data.pose_position = "POSE"
    export_rig.hide_render = False
    export_rig.hide_viewport = False
    mesh.hide_render = False
    mesh.hide_viewport = False
    for module in modules:
        module.hide_render = False
        module.hide_viewport = False

    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    for module in modules:
        module.select_set(True)
    export_rig.select_set(True)
    bpy.context.view_layer.objects.active = export_rig
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )


def validate_build(
    mesh: bpy.types.Object,
    modules: list[bpy.types.Object],
    export_rig: bpy.types.Object,
    control_rig: bpy.types.Object,
) -> None:
    objects = [mesh, *modules]
    triangles = sum(
        len(polygon.vertices) - 2
        for obj in objects
        for polygon in obj.data.polygons
    )
    if not 10000 <= triangles <= 50000:
        raise RuntimeError(f"Unexpected total triangle count: {triangles}")
    if len(mesh.data.materials) != 1:
        raise RuntimeError(
            f"Body should have one skin material, got {len(mesh.data.materials)}"
        )
    required_modules = {
        "EyeL",
        "EyeR",
        "Nose",
        "Brows",
        "Moustache",
        "Mouth",
        "Hair00",
        "Hair01",
        "Hair02",
        "Hair03",
    }
    actual_modules = {module.name for module in modules}
    if actual_modules != required_modules:
        raise RuntimeError(
            "Modular head contract mismatch: "
            f"missing={sorted(required_modules - actual_modules)} "
            f"extra={sorted(actual_modules - required_modules)}"
        )
    required_groups = set(EXPORT_BONES)
    actual_groups = {group.name for group in mesh.vertex_groups}
    missing_groups = required_groups - actual_groups
    if missing_groups:
        raise RuntimeError(
            f"Skinned mesh is missing required groups: {sorted(missing_groups)}"
        )
    if len(control_rig.data.bones) < 50:
        raise RuntimeError("Rigify control rig was not generated completely")
    if export_rig.animation_data is None:
        raise RuntimeError("Export rig lost its embedded idle action")
    for module in modules:
        if module.parent is not None:
            raise RuntimeError(
                f"Head module {module.name} must export in reviewed model space"
            )
        if any(modifier.type == "ARMATURE" for modifier in module.modifiers):
            raise RuntimeError(
                f"Rigid head module {module.name} unexpectedly has a skin"
            )
    print(
        "PLAYER_BUILD",
        {
            "bodyVertices": len(mesh.data.vertices),
            "totalVertices": sum(len(obj.data.vertices) for obj in objects),
            "totalTriangles": triangles,
            "bodyMaterial": mesh.data.materials[0].name,
            "modules": sorted(actual_modules),
            "deformBones": len(export_rig.data.bones),
            "rigifyBones": len(control_rig.data.bones),
            "blend": str(BLEND_OUT),
            "glb": str(GLB_OUT),
        },
    )


def main() -> None:
    reset_scene()
    materials = {
        "skin": make_material("Imota_Skin", COLORS["skin"], 0.68, 0.18),
        "hair": make_material("Imota_Hair", COLORS["hair"], 0.72, 0.16),
        "eyes": make_material("Imota_Eyes", COLORS["eyes"], 0.24, 0.38),
        "mouth": make_material("Imota_Mouth", COLORS["mouth"], 0.48, 0.20),
    }
    export_rig = load_contract_rig()
    fit_export_rig(export_rig)
    source_mesh = import_source()
    smooth_source(source_mesh)
    source_mesh.name = "PlayerMaleBody"
    source_mesh.data.name = "PlayerMaleBodyMesh"
    source_mesh.data.materials.clear()
    source_mesh.data.materials.append(materials["skin"])
    apply_model_scale(source_mesh)
    player_mesh = source_mesh
    parent_with_weights(player_mesh, export_rig)
    modules = build_modular_head(materials)
    for module in modules:
        attach_head_module(module, export_rig)

    control_rig = fit_rigify_metarig(export_rig)
    metarig = bpy.data.objects.get("PlayerMale_RigifyMeta")
    if metarig is None:
        raise RuntimeError("Rigify metarig disappeared during generation")
    connect_rigify_to_export(control_rig, export_rig)
    validate_build(player_mesh, modules, export_rig, control_rig)

    ground, camera = prepare_review_scene(
        player_mesh, modules, metarig, control_rig, export_rig
    )
    # Preserve the complete Rigify authoring setup. The review and runtime GLB
    # use the clean export rig without authoring constraints.
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    remove_authoring_constraints(export_rig)
    export_rig.data.pose_position = "REST"
    render_views(camera)

    review_objects = [
        ground,
        camera,
        *[
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "LIGHT"
        ],
        metarig,
        control_rig,
    ]
    export_runtime(player_mesh, modules, export_rig, review_objects)
    print("PLAYER_BUILD_COMPLETE")


if __name__ == "__main__":
    main()
