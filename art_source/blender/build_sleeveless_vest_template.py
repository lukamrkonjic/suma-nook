"""Build a reusable, thick sleeveless-vest wardrobe template for Suma.

This generator is deliberately character-replaceable:

- the mannequin path, object names, and skeleton names come from
  ``wardrobe_standard.json``;
- body/torso dimensions are measured from the supplied skinned mesh;
- every authored distance is normalized against character height;
- exported components use semantic names and a shared skeleton.

The previous AI-generated vest is only a preserved design reference. The
production candidate is new procedural topology with physical thickness,
armholes, shoulder bridges, raised lapels, trim, and pockets.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Iterable

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STANDARD_PATH = ROOT / "art_source" / "blender" / "wardrobe" / "wardrobe_standard.json"
CANDIDATE_DIR = ROOT / "art_source" / "blender" / "wardrobe" / "candidates"
OUTPUT_GLB = CANDIDATE_DIR / "cowboy_vest_template_candidate.glb"
OUTPUT_BLEND = CANDIDATE_DIR / "sleeveless_vest_template_candidate.blend"
OUTPUT_REPORT = CANDIDATE_DIR / "sleeveless_vest_template_candidate.json"
PREVIEW_DIR = CANDIDATE_DIR / "reviews"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_standard() -> dict:
    return json.loads(STANDARD_PATH.read_text(encoding="utf-8"))


def activate_only(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def create_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color
    material.metallic = 0.0
    material.roughness = roughness
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["IOR"].default_value = 1.45
    return material


def weighted_points(
    body: bpy.types.Object,
    bone_names: Iterable[str],
    minimum_weight: float = 0.12,
) -> list[Vector]:
    group_indices = {
        body.vertex_groups[name].index
        for name in bone_names
        if body.vertex_groups.get(name) is not None
    }
    result = []
    for vertex in body.data.vertices:
        total = sum(
            membership.weight
            for membership in vertex.groups
            if membership.group in group_indices
        )
        if total >= minimum_weight:
            result.append(body.matrix_world @ vertex.co)
    if not result:
        raise RuntimeError("Semantic torso bones selected no mannequin vertices")
    return result


def measure_mannequin(
    body: bpy.types.Object,
    bones: dict[str, str],
) -> dict:
    all_points = [
        body.matrix_world @ vertex.co for vertex in body.data.vertices
    ]
    torso_points = weighted_points(
        body,
        [
            bones["hips"],
            bones["abdomen"],
            bones["chest"],
            bones["shoulder_l"],
            bones["shoulder_r"],
        ],
    )
    minimum = Vector(
        min(point[axis] for point in all_points) for axis in range(3)
    )
    maximum = Vector(
        max(point[axis] for point in all_points) for axis in range(3)
    )
    torso_minimum = Vector(
        min(point[axis] for point in torso_points) for axis in range(3)
    )
    torso_maximum = Vector(
        max(point[axis] for point in torso_points) for axis in range(3)
    )
    return {
        "body_minimum": minimum,
        "body_maximum": maximum,
        "body_center": (minimum + maximum) * 0.5,
        "character_height": maximum.z - minimum.z,
        "torso_minimum": torso_minimum,
        "torso_maximum": torso_maximum,
        "torso_center": (torso_minimum + torso_maximum) * 0.5,
    }


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def apply_geometry_finish(
    obj: bpy.types.Object,
    thickness: float,
    bevel: float,
) -> None:
    activate_only(obj)
    solidify = obj.modifiers.new("GarmentThickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = 0.0
    solidify.use_even_offset = True
    solidify.use_quality_normals = True
    bpy.ops.object.modifier_apply(modifier=solidify.name)

    bevel_modifier = obj.modifiers.new("SoftGarmentEdges", "BEVEL")
    bevel_modifier.width = bevel
    bevel_modifier.segments = 2
    bevel_modifier.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(58.0),
        keep_sharp_edges=True,
    )


def create_shell(
    calibration: dict,
    settings: dict,
    material: bpy.types.Material,
) -> tuple[bpy.types.Object, dict]:
    height = calibration["character_height"]
    torso_minimum = calibration["torso_minimum"]
    torso_maximum = calibration["torso_maximum"]
    torso_height = torso_maximum.z - torso_minimum.z
    center = calibration["torso_center"]
    clearance = height * settings["body_clearance_height_ratio"]
    half_width = (
        max(abs(torso_minimum.x - center.x), abs(torso_maximum.x - center.x))
        * settings["shell_half_width_ratio"]
        + clearance * 0.35
    )
    half_depth = (
        max(abs(torso_minimum.y - center.y), abs(torso_maximum.y - center.y))
        + clearance
    )
    bottom = (
        torso_minimum.z
        + torso_height * settings["torso_bottom_ratio"]
    )
    top = torso_maximum.z - height * 0.022
    underarm = bottom + (top - bottom) * settings["underarm_height_ratio"]
    opening_half_width = half_width * settings["front_opening_width_ratio"]
    opening_angle = math.asin(
        min(0.75, max(0.10, opening_half_width / half_width))
    )

    columns = 20
    rows = 7
    angles = [
        -math.pi + opening_angle
        + (2.0 * (math.pi - opening_angle)) * index / (columns - 1)
        for index in range(columns)
    ]
    vertices = []
    for row in range(rows):
        vertical = row / (rows - 1)
        for angle in angles:
            side_factor = abs(math.sin(angle))
            top_here = top - (top - underarm) * side_factor**2.25
            z = bottom + (top_here - bottom) * vertical
            waist_taper = 1.0 - 0.055 * math.sin(vertical * math.pi)
            x = center.x + math.sin(angle) * half_width * waist_taper
            y = center.y + math.cos(angle) * half_depth
            vertices.append((x, y, z))
    faces = []
    for row in range(rows - 1):
        for column in range(columns - 1):
            first = row * columns + column
            faces.append(
                (
                    first,
                    first + 1,
                    first + columns + 1,
                    first + columns,
                )
            )
    shell = mesh_object("VestShell", vertices, faces, material)
    apply_geometry_finish(
        shell,
        height * settings["thickness_height_ratio"],
        height * settings["bevel_height_ratio"],
    )
    return shell, {
        "center": center,
        "half_width": half_width,
        "half_depth": half_depth,
        "bottom": bottom,
        "top": top,
        "underarm": underarm,
        "opening_half_width": opening_half_width,
        "angles": angles,
    }


def create_shoulder_bridge(
    side: int,
    shape: dict,
    calibration: dict,
    settings: dict,
    material: bpy.types.Material,
) -> bpy.types.Object:
    height = calibration["character_height"]
    center = shape["center"]
    inner_x = shape["half_width"] * 0.40
    outer_x = shape["half_width"] * 0.68
    y_values = [
        -shape["half_depth"] * 0.90,
        -shape["half_depth"] * 0.60,
        -shape["half_depth"] * 0.30,
        0.0,
        shape["half_depth"] * 0.30,
        shape["half_depth"] * 0.60,
        shape["half_depth"] * 0.90,
    ]
    vertices = []
    for y in y_values:
        arch = 1.0 - (abs(y) / shape["half_depth"]) ** 1.65
        for width_index in range(5):
            width = width_index / 4.0
            x = center.x + side * (
                inner_x + (outer_x - inner_x) * width
            )
            z = (
                shape["top"]
                - height * 0.036 * width**1.35
                + height * 0.028 * arch
            )
            vertices.append((x, center.y + y, z))
    faces = []
    columns = 5
    for row in range(len(y_values) - 1):
        for column in range(columns - 1):
            first = row * columns + column
            faces.append(
                (
                    first,
                    first + 1,
                    first + columns + 1,
                    first + columns,
                )
            )
    suffix = "L" if side > 0 else "R"
    bridge = mesh_object(
        "VestShoulder" + suffix, vertices, faces, material
    )
    apply_geometry_finish(
        bridge,
        height * settings["thickness_height_ratio"] * 1.08,
        height * settings["bevel_height_ratio"],
    )
    return bridge


def create_lapel(
    side: int,
    shape: dict,
    calibration: dict,
    settings: dict,
    material: bpy.types.Material,
) -> bpy.types.Object:
    height = calibration["character_height"]
    center = shape["center"]
    inner = shape["opening_half_width"]
    outer = shape["half_width"] * 0.70
    y = center.y - shape["half_depth"] - height * 0.010
    vertices = [
        (
            center.x + side * inner,
            y,
            shape["bottom"] + height * 0.11,
        ),
        (
            center.x + side * (inner * 1.12),
            y - height * 0.004,
            shape["top"] - height * 0.015,
        ),
        (
            center.x + side * outer,
            y,
            shape["top"] - height * 0.035,
        ),
        (
            center.x + side * (shape["half_width"] * 0.55),
            y - height * 0.006,
            shape["bottom"] + height * 0.20,
        ),
    ]
    suffix = "L" if side > 0 else "R"
    lapel = mesh_object(
        "VestLapel" + suffix,
        vertices,
        [(0, 1, 2, 3)],
        material,
    )
    apply_geometry_finish(
        lapel,
        height * settings["thickness_height_ratio"] * 0.82,
        height * settings["bevel_height_ratio"] * 0.72,
    )
    return lapel


def create_rounded_box(
    name: str,
    location: Vector,
    dimensions: Vector,
    bevel: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.dimensions = dimensions
    activate_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    bevel_modifier = obj.modifiers.new("SoftGarmentEdges", "BEVEL")
    bevel_modifier.width = bevel
    bevel_modifier.segments = 3
    bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)
    bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(58.0),
        keep_sharp_edges=True,
    )
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def create_curve_mesh(
    name: str,
    points: list[Vector],
    radius: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.resolution_u = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bezier_point, point in zip(spline.bezier_points, points):
        bezier_point.co = point
        bezier_point.handle_left_type = "AUTO"
        bezier_point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    activate_only(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def create_trim_and_pockets(
    shape: dict,
    calibration: dict,
    settings: dict,
    leather: bpy.types.Material,
    trim: bpy.types.Material,
) -> list[bpy.types.Object]:
    height = calibration["character_height"]
    center = shape["center"]
    trim_radius = height * settings["trim_radius_height_ratio"]
    points = [
        Vector(
            (
                center.x + math.sin(angle) * shape["half_width"],
                center.y + math.cos(angle) * shape["half_depth"],
                shape["bottom"],
            )
        )
        for angle in shape["angles"]
    ]
    components = [
        create_curve_mesh("VestHemTrim", points, trim_radius, trim)
    ]
    for side in (-1, 1):
        suffix = "L" if side > 0 else "R"
        front_x = center.x + side * shape["opening_half_width"]
        front_y = center.y - shape["half_depth"] - height * 0.008
        components.append(
            create_curve_mesh(
                "VestFrontTrim" + suffix,
                [
                    Vector((front_x, front_y, shape["bottom"])),
                    Vector(
                        (
                            front_x * 1.03,
                            front_y,
                            shape["bottom"] + height * 0.18,
                        )
                    ),
                    Vector(
                        (
                            front_x * 1.05,
                            front_y,
                            shape["top"] - height * 0.018,
                        )
                    ),
                ],
                trim_radius * 0.82,
                trim,
            )
        )
        arm_points = []
        for step in range(9):
            ratio = step / 8.0
            y = -shape["half_depth"] * 0.93 + shape["half_depth"] * 1.86 * ratio
            arch = abs(2.0 * ratio - 1.0) ** 1.55
            z = shape["underarm"] + (
                shape["top"] - height * 0.015 - shape["underarm"]
            ) * arch
            bridge_outer = shape["half_width"] * 0.68
            underarm_outer = shape["half_width"] * 0.93
            x_distance = bridge_outer + (
                underarm_outer - bridge_outer
            ) * (1.0 - arch)
            x = center.x + side * x_distance
            arm_points.append(Vector((x, center.y + y, z)))
        components.append(
            create_curve_mesh(
                "VestArmholeTrim" + suffix,
                arm_points,
                trim_radius * 0.66,
                trim,
            )
        )

        pocket_x = center.x + side * shape["half_width"] * 0.53
        pocket_y = center.y - shape["half_depth"] - height * 0.019
        pocket_z = shape["bottom"] + height * 0.105
        components.append(
            create_rounded_box(
                "VestPocket" + suffix,
                Vector((pocket_x, pocket_y, pocket_z)),
                Vector(
                    (
                        shape["half_width"] * 0.66,
                        height * 0.022,
                        height * 0.090,
                    )
                ),
                height * settings["bevel_height_ratio"],
                leather,
            )
        )
        components.append(
            create_rounded_box(
                "VestPocketFlap" + suffix,
                Vector(
                    (
                        pocket_x,
                        pocket_y - height * 0.014,
                        pocket_z + height * 0.054,
                    )
                ),
                Vector(
                    (
                        shape["half_width"] * 0.72,
                        height * 0.018,
                        height * 0.032,
                    )
                ),
                height * settings["bevel_height_ratio"] * 0.80,
                trim,
            )
        )
    return components


def evaluated_rest_reference(
    body: bpy.types.Object,
) -> bpy.types.Object:
    reference = body.copy()
    reference.data = body.data.copy()
    reference.name = "WardrobeWeightReference"
    reference.data.name = "WardrobeWeightReferenceMesh"
    bpy.context.scene.collection.objects.link(reference)
    armature_modifier = next(
        (
            modifier
            for modifier in reference.modifiers
            if modifier.type == "ARMATURE"
        ),
        None,
    )
    if armature_modifier is not None:
        activate_only(reference)
        bpy.ops.object.modifier_apply(modifier=armature_modifier.name)
    world = reference.matrix_world.copy()
    reference.parent = None
    reference.matrix_world = world
    reference.hide_render = True
    reference.hide_set(True)
    return reference


def clean_and_limit_weights(obj: bpy.types.Object) -> dict:
    activate_only(obj)
    bpy.ops.object.vertex_group_clean(
        group_select_mode="ALL",
        limit=0.0001,
        keep_single=True,
    )
    bpy.ops.object.vertex_group_limit_total(
        group_select_mode="ALL",
        limit=4,
    )
    bpy.ops.object.vertex_group_normalize_all(
        group_select_mode="ALL",
        lock_active=False,
    )
    totals = [
        sum(membership.weight for membership in vertex.groups)
        for vertex in obj.data.vertices
    ]
    return {
        "unweighted": sum(total <= 0.00001 for total in totals),
        "minimum_total": min(totals),
        "maximum_total": max(totals),
        "maximum_influences": max(
            len(vertex.groups) for vertex in obj.data.vertices
        ),
    }


def transfer_weights(
    source: bpy.types.Object,
    obj: bpy.types.Object,
    armature: bpy.types.Object,
) -> dict:
    for group in source.vertex_groups:
        if obj.vertex_groups.get(group.name) is None:
            obj.vertex_groups.new(name=group.name)
    activate_only(obj)
    transfer = obj.modifiers.new("WardrobeWeightTransfer", "DATA_TRANSFER")
    transfer.object = source
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    transfer.mix_mode = "REPLACE"
    bpy.ops.object.modifier_apply(modifier=transfer.name)
    report = clean_and_limit_weights(obj)
    if report["unweighted"]:
        raise RuntimeError(
            f"{obj.name} has {report['unweighted']} unweighted vertices"
        )
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    modifier = obj.modifiers.new("WardrobeArmature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    return report


def replace_weights(
    obj: bpy.types.Object,
    weighted_bones: list[tuple[str, float]],
) -> None:
    for vertex in obj.data.vertices:
        for membership in list(vertex.groups):
            obj.vertex_groups[membership.group].remove([vertex.index])
        for bone_name, weight in weighted_bones:
            group = obj.vertex_groups.get(bone_name)
            if group is None:
                raise RuntimeError(
                    f"{obj.name} cannot target absent bone '{bone_name}'"
                )
            group.add([vertex.index], weight, "REPLACE")
    clean_and_limit_weights(obj)


def manually_correct_weights(
    components: list[bpy.types.Object],
    bones: dict[str, str],
) -> dict[str, str]:
    corrections = {}
    for obj in components:
        if obj.name.startswith("VestShoulderL"):
            replace_weights(
                obj,
                [
                    (bones["chest"], 0.34),
                    (bones["shoulder_l"], 0.54),
                    (bones["upper_arm_l"], 0.12),
                ],
            )
            corrections[obj.name] = "chest/left shoulder/left arm"
        elif obj.name.startswith("VestShoulderR"):
            replace_weights(
                obj,
                [
                    (bones["chest"], 0.34),
                    (bones["shoulder_r"], 0.54),
                    (bones["upper_arm_r"], 0.12),
                ],
            )
            corrections[obj.name] = "chest/right shoulder/right arm"
        elif obj.name.startswith("VestLapel"):
            replace_weights(
                obj,
                [(bones["chest"], 0.82), (bones["abdomen"], 0.18)],
            )
            corrections[obj.name] = "stable chest lapel"
        elif obj.name.startswith("VestPocket"):
            replace_weights(
                obj,
                [
                    (bones["abdomen"], 0.72),
                    (bones["hips"], 0.28),
                ],
            )
            corrections[obj.name] = "stable abdomen/hips pocket"
    return corrections


def make_exposed_body(
    body: bpy.types.Object,
    shape: dict,
    calibration: dict,
) -> tuple[bpy.types.Object, list[int]]:
    exposed = body.copy()
    exposed.data = body.data.copy()
    exposed.name = "BodyExposedForCowboyVest"
    exposed.data.name = "BodyExposedForCowboyVestMesh"
    exposed["coverage_template"] = "sleeveless_vest_v1"
    bpy.context.scene.collection.objects.link(exposed)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated_object = body.evaluated_get(depsgraph)
    evaluated_mesh = evaluated_object.to_mesh()
    hidden_faces = []
    character_height = calibration["character_height"]
    for polygon in evaluated_mesh.polygons:
        points = [
            body.matrix_world @ evaluated_mesh.vertices[index].co
            for index in polygon.vertices
        ]
        center = sum(points, Vector()) / len(points)
        within_height = (
            shape["bottom"] + character_height * 0.018
            <= center.z
            <= shape["top"] - character_height * 0.012
        )
        back_panel = (
            center.y >= shape["center"].y + character_height * 0.010
            and abs(center.x - shape["center"].x)
            <= shape["half_width"] * 0.96
        )
        side_panel = (
            abs(center.x - shape["center"].x)
            >= shape["half_width"] * 0.56
            and abs(center.x - shape["center"].x)
            <= shape["half_width"] * 1.02
            and center.z <= shape["underarm"] + character_height * 0.030
        )
        front_panel = (
            center.y <= shape["center"].y - character_height * 0.010
            and abs(center.x - shape["center"].x)
            >= shape["opening_half_width"] * 1.18
            and abs(center.x - shape["center"].x)
            <= shape["half_width"] * 0.96
        )
        shoulder_underlay = (
            center.z >= shape["underarm"] + character_height * 0.035
            and abs(center.x - shape["center"].x)
            >= shape["half_width"] * 0.40
            and abs(center.x - shape["center"].x)
            <= shape["half_width"] * 0.72
            and abs(center.y - shape["center"].y)
            <= shape["half_depth"] * 0.78
        )
        if within_height and (
            back_panel or side_panel or front_panel or shoulder_underlay
        ):
            hidden_faces.append(polygon.index)
    evaluated_object.to_mesh_clear()

    hidden_set = set(hidden_faces)
    activate_only(exposed)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for polygon in exposed.data.polygons:
        polygon.select = polygon.index in hidden_set
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    if not hidden_faces:
        raise RuntimeError("Exact vest coverage removed no body faces")
    return exposed, hidden_faces


def object_stats(obj: bpy.types.Object) -> dict:
    obj.data.calc_loop_triangles()
    return {
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
        "triangles": len(obj.data.loop_triangles),
        "uv_layers": [layer.name for layer in obj.data.uv_layers],
        "materials": [
            material.name
            for material in obj.data.materials
            if material is not None
        ],
        "vertex_groups": len(obj.vertex_groups),
    }


def add_review_stage(calibration: dict) -> bpy.types.Object:
    height = calibration["character_height"]
    center = calibration["body_center"] + Vector((0.0, 0.0, height * 0.02))
    bpy.ops.object.camera_add(
        location=(height * 1.25, -height * 2.15, height * 0.78)
    )
    camera = bpy.context.object
    camera.name = "WardrobeReviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = height * 1.22
    camera.rotation_euler = (
        center - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for name, location, energy, size in [
        (
            "WardrobeKey",
            (height * 1.5, -height * 1.7, height * 2.0),
            780.0,
            height * 2.8,
        ),
        (
            "WardrobeFill",
            (-height * 1.0, height * 0.9, height * 1.0),
            330.0,
            height * 2.5,
        ),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (
            center - light.location
        ).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("WardrobeReviewWorld")
    world.color = (0.035, 0.035, 0.035)
    bpy.context.scene.world = world
    return camera


def render_review(
    path: Path,
    camera: bpy.types.Object,
    location: Vector,
    target: Vector,
    ortho_scale: float,
) -> None:
    camera.location = location
    camera.rotation_euler = (
        target - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = ortho_scale
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    standard = load_standard()
    mannequin_path = ROOT / standard["mannequin"]
    if not mannequin_path.is_file():
        raise FileNotFoundError(f"Missing wardrobe mannequin: {mannequin_path}")
    CANDIDATE_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(mannequin_path))
    body = bpy.data.objects[standard["body_object"]]
    armature = bpy.data.objects[standard["armature_object"]]
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    bones = standard["semantic_bones"]
    settings = standard["sleeveless_vest"]
    calibration = measure_mannequin(body, bones)
    height = calibration["character_height"]

    leather = create_material(
        "VestLeather",
        (0.285, 0.060, 0.010, 1.0),
        0.62,
    )
    trim = create_material(
        "VestDarkLeather",
        (0.070, 0.010, 0.003, 1.0),
        0.56,
    )
    lining = create_material(
        "VestInnerLining",
        (0.11, 0.022, 0.010, 1.0),
        0.78,
    )

    shell, shape = create_shell(calibration, settings, leather)
    shell.data.materials.append(lining)
    shoulder_l = create_shoulder_bridge(
        1, shape, calibration, settings, trim
    )
    shoulder_r = create_shoulder_bridge(
        -1, shape, calibration, settings, trim
    )
    lapel_l = create_lapel(1, shape, calibration, settings, trim)
    lapel_r = create_lapel(-1, shape, calibration, settings, trim)
    details = create_trim_and_pockets(
        shape, calibration, settings, leather, trim
    )
    garment_components = [
        shell,
        shoulder_l,
        shoulder_r,
        lapel_l,
        lapel_r,
        *details,
    ]

    weight_reference = evaluated_rest_reference(body)
    weight_reports = {}
    for component in garment_components:
        weight_reports[component.name] = transfer_weights(
            weight_reference, component, armature
        )
    corrections = manually_correct_weights(garment_components, bones)
    exposed, hidden_faces = make_exposed_body(body, shape, calibration)

    body.hide_render = True
    body.hide_set(True)
    weight_reference.hide_render = True
    weight_reference.hide_set(True)
    exposed.hide_render = False
    exposed.hide_set(False)

    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in [armature, exposed, *garment_components]:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_skins=True,
        export_def_bones=True,
        export_materials="EXPORT",
        export_tangents=True,
        export_lights=False,
        export_cameras=False,
    )

    camera = add_review_stage(calibration)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    target = calibration["body_center"]
    render_review(
        PREVIEW_DIR / "template_rest_front.png",
        camera,
        Vector((0.0, -height * 2.4, height * 0.45)),
        target,
        height * 1.12,
    )
    render_review(
        PREVIEW_DIR / "template_rest_orbit.png",
        camera,
        Vector((height * 1.55, -height * 2.0, height * 0.70)),
        target,
        height * 1.16,
    )
    render_review(
        PREVIEW_DIR / "template_rest_side.png",
        camera,
        Vector((height * 2.5, 0.0, height * 0.42)),
        target,
        height * 1.12,
    )
    render_review(
        PREVIEW_DIR / "template_rest_back.png",
        camera,
        Vector((0.0, height * 2.4, height * 0.45)),
        target,
        height * 1.12,
    )

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    report = {
        "standard": str(STANDARD_PATH.relative_to(ROOT)),
        "standard_version": standard["version"],
        "mannequin": str(mannequin_path.relative_to(ROOT)),
        "mannequin_sha256": sha256(mannequin_path),
        "candidate_glb": str(OUTPUT_GLB.relative_to(ROOT)),
        "candidate_glb_sha256": sha256(OUTPUT_GLB),
        "candidate_blend": str(OUTPUT_BLEND.relative_to(ROOT)),
        "calibration": {
            key: list(value) if isinstance(value, Vector) else value
            for key, value in calibration.items()
        },
        "fit": {
            key: list(value) if isinstance(value, Vector) else value
            for key, value in shape.items()
            if key != "angles"
        },
        "coverage": {
            "hidden_faces": len(hidden_faces),
            "template": "sleeveless_vest_v1",
        },
        "manual_weight_corrections": corrections,
        "weights": weight_reports,
        "components": {
            component.name: object_stats(component)
            for component in garment_components
        },
        "exposed_body": object_stats(exposed),
        "previews": [
            str((PREVIEW_DIR / filename).relative_to(ROOT))
            for filename in [
                "template_rest_front.png",
                "template_rest_orbit.png",
                "template_rest_side.png",
                "template_rest_back.png",
            ]
        ],
    }
    OUTPUT_REPORT.write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    print("SLEEVELESS_VEST_TEMPLATE_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
