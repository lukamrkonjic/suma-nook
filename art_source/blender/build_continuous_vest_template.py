"""Build a continuous, character-calibrated sleeveless vest candidate.

Unlike the rejected panel prototype, this workflow preserves the supplied
vest's recognizable, organically connected shell and details. It measures the
active mannequin, fits the design by normalized torso proportions, increases
the closed shell's physical thickness along its normals, transfers continuous
skin weights, smooths those weights, and exports one deforming garment plus an
exact exposed-body derivative.
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
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "cowboy_vest"
    / "cowboy_vest_source.glb"
)
EXPECTED_SOURCE_SHA256 = (
    "145180369651319798d510b38a01a8127a9f97aecb4abd12ac38f3041cdac024"
)
CANDIDATE_DIR = ROOT / "art_source" / "blender" / "wardrobe" / "continuous_candidate"
OUTPUT_GLB = CANDIDATE_DIR / "cowboy_vest_continuous_candidate.glb"
OUTPUT_BLEND = CANDIDATE_DIR / "sleeveless_vest_continuous_candidate.blend"
OUTPUT_REPORT = CANDIDATE_DIR / "sleeveless_vest_continuous_candidate.json"
PREVIEW_DIR = CANDIDATE_DIR / "reviews"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def activate_only(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def weighted_points(
    body: bpy.types.Object,
    bone_names: Iterable[str],
    minimum_weight: float = 0.12,
) -> list[Vector]:
    indices = {
        body.vertex_groups[name].index
        for name in bone_names
        if body.vertex_groups.get(name) is not None
    }
    result = []
    for vertex in body.data.vertices:
        weight = sum(
            membership.weight
            for membership in vertex.groups
            if membership.group in indices
        )
        if weight >= minimum_weight:
            result.append(body.matrix_world @ vertex.co)
    if not result:
        raise RuntimeError("Semantic torso calibration selected no vertices")
    return result


def measure(
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
    body_min = Vector(
        min(point[axis] for point in all_points) for axis in range(3)
    )
    body_max = Vector(
        max(point[axis] for point in all_points) for axis in range(3)
    )
    torso_min = Vector(
        min(point[axis] for point in torso_points) for axis in range(3)
    )
    torso_max = Vector(
        max(point[axis] for point in torso_points) for axis in range(3)
    )
    return {
        "body_min": body_min,
        "body_max": body_max,
        "body_center": (body_min + body_max) * 0.5,
        "character_height": body_max.z - body_min.z,
        "torso_min": torso_min,
        "torso_max": torso_max,
        "torso_center": (torso_min + torso_max) * 0.5,
    }


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    minimum = Vector(
        min(point[axis] for point in points) for axis in range(3)
    )
    maximum = Vector(
        max(point[axis] for point in points) for axis in range(3)
    )
    return minimum, maximum


def import_design(path: Path) -> bpy.types.Object:
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [
        obj
        for obj in bpy.context.scene.objects
        if obj not in existing and obj.type == "MESH"
    ]
    if not meshes:
        raise RuntimeError(f"No mesh imported from {path}")
    vest = max(meshes, key=lambda obj: len(obj.data.polygons))
    world = vest.matrix_world.copy()
    vest.parent = None
    vest.matrix_world = world
    activate_only(vest)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return vest


def fit_design(
    vest: bpy.types.Object,
    calibration: dict,
) -> dict:
    source_min, source_max = world_bounds(vest)
    source_size = source_max - source_min
    torso_size = calibration["torso_max"] - calibration["torso_min"]
    height = calibration["character_height"]
    target_size = Vector(
        (
            torso_size.x * 1.085,
            torso_size.y * 1.075,
            torso_size.z * 0.760,
        )
    )
    scale = Vector(
        target_size[axis] / source_size[axis] for axis in range(3)
    )
    vest.scale = scale
    activate_only(vest)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    fitted_min, fitted_max = world_bounds(vest)
    fitted_center = (fitted_min + fitted_max) * 0.5
    target_center = Vector(
        (
            calibration["torso_center"].x,
            calibration["torso_center"].y - height * 0.017,
            calibration["torso_max"].z - target_size.z * 0.50,
        )
    )
    vest.location += target_center - fitted_center
    activate_only(vest)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    return {
        "source_size": source_size,
        "target_size": target_size,
        "scale": scale,
        "target_center": target_center,
    }


def finish_continuous_shell(
    vest: bpy.types.Object,
    calibration: dict,
) -> dict:
    height = calibration["character_height"]
    activate_only(vest)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00001, use_unselected=False)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    subdivision = vest.modifiers.new("ContinuousGarmentSubdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1
    subdivision.show_only_control_edges = True
    bpy.ops.object.modifier_apply(modifier=subdivision.name)

    vest.data.update()
    base_expansion = height * 0.0062
    shoulder_extra = height * 0.0040
    adjusted = 0
    for vertex in vest.data.vertices:
        shoulder_factor = max(
            0.0,
            min(
                1.0,
                (vertex.co.z - calibration["torso_center"].z)
                / (height * 0.22),
            ),
        )
        displacement = base_expansion + shoulder_extra * shoulder_factor
        vertex.co += vertex.normal * displacement
        adjusted += 1
    vest.data.update()

    bevel = vest.modifiers.new("ContinuousGarmentEdgeSoftening", "BEVEL")
    bevel.width = height * 0.0018
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    activate_only(vest)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(58.0),
        keep_sharp_edges=True,
    )
    for material in vest.data.materials:
        if material is None or not material.use_nodes:
            continue
        principled = material.node_tree.nodes.get("Principled BSDF")
        if principled is not None:
            principled.inputs["Roughness"].default_value = max(
                0.64,
                principled.inputs["Roughness"].default_value,
            )
    triangulate = vest.modifiers.new("ContinuousGarmentTriangulation", "TRIANGULATE")
    triangulate.keep_custom_normals = True
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    return {
        "expanded_vertices": adjusted,
        "base_normal_expansion": base_expansion,
        "shoulder_extra_expansion": shoulder_extra,
        "bevel": height * 0.0018,
    }


def evaluated_rest_reference(
    body: bpy.types.Object,
) -> bpy.types.Object:
    reference = body.copy()
    reference.data = body.data.copy()
    reference.name = "WardrobeWeightReference"
    reference.data.name = "WardrobeWeightReferenceMesh"
    bpy.context.scene.collection.objects.link(reference)
    modifier = next(
        (
            item
            for item in reference.modifiers
            if item.type == "ARMATURE"
        ),
        None,
    )
    if modifier is not None:
        activate_only(reference)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    world = reference.matrix_world.copy()
    reference.parent = None
    reference.matrix_world = world
    reference.hide_set(True)
    reference.hide_render = True
    return reference


def read_vertex_weights(
    obj: bpy.types.Object,
) -> list[dict[str, float]]:
    group_names = {
        group.index: group.name for group in obj.vertex_groups
    }
    return [
        {
            group_names[membership.group]: membership.weight
            for membership in vertex.groups
            if membership.weight > 0.0
        }
        for vertex in obj.data.vertices
    ]


def write_vertex_weights(
    obj: bpy.types.Object,
    weights: list[dict[str, float]],
) -> None:
    vertex_indices = list(range(len(obj.data.vertices)))
    for group in obj.vertex_groups:
        group.remove(vertex_indices)
    for vertex_index, memberships in enumerate(weights):
        for group_name, weight in memberships.items():
            group = obj.vertex_groups.get(group_name)
            if group is None:
                group = obj.vertex_groups.new(name=group_name)
            group.add([vertex_index], weight, "REPLACE")


def smooth_vertex_weights(
    obj: bpy.types.Object,
    factor: float,
    passes: int,
) -> None:
    """Smooth skin weights without Blender UI/context-dependent operators."""
    adjacency = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    weights = read_vertex_weights(obj)
    for _pass in range(passes):
        smoothed = []
        for vertex_index, current in enumerate(weights):
            neighbors = adjacency[vertex_index]
            if not neighbors:
                smoothed.append(dict(current))
                continue
            relevant_groups = set(current)
            for neighbor_index in neighbors:
                relevant_groups.update(weights[neighbor_index])
            result = {}
            for group_name in relevant_groups:
                neighbor_average = sum(
                    weights[neighbor_index].get(group_name, 0.0)
                    for neighbor_index in neighbors
                ) / len(neighbors)
                value = (
                    current.get(group_name, 0.0) * (1.0 - factor)
                    + neighbor_average * factor
                )
                if value > 0.00001:
                    result[group_name] = value
            total = sum(result.values())
            if total > 0.0:
                result = {
                    group_name: value / total
                    for group_name, value in result.items()
                }
            smoothed.append(result)
        weights = smoothed
    write_vertex_weights(obj, weights)


def clean_limit_and_normalize_weights(
    obj: bpy.types.Object,
    limit: int,
) -> list[dict[str, float]]:
    cleaned = []
    for memberships in read_vertex_weights(obj):
        strongest = sorted(
            (
                (group_name, weight)
                for group_name, weight in memberships.items()
                if weight >= 0.0001
            ),
            key=lambda item: item[1],
            reverse=True,
        )[:limit]
        total = sum(weight for _group_name, weight in strongest)
        cleaned.append(
            {
                group_name: weight / total
                for group_name, weight in strongest
            }
            if total > 0.0
            else {}
        )
    write_vertex_weights(obj, cleaned)
    return cleaned


def project_weights_to_sleeveless_torso(
    vest: bpy.types.Object,
    bones: dict[str, str],
) -> dict:
    """Keep a sleeveless shell stable by excluding limb/head influences."""
    minimum, maximum = world_bounds(vest)
    height = maximum.z - minimum.z
    half_width = max(
        abs(minimum.x),
        abs(maximum.x),
        0.0001,
    )
    projected = []
    maximum_shoulder_weight = 0.0
    for vertex in vest.data.vertices:
        vertical = max(
            0.0,
            min(1.0, (vertex.co.z - minimum.z) / height),
        )
        outer = max(
            0.0,
            min(
                1.0,
                (abs(vertex.co.x) / half_width - 0.54) / 0.46,
            ),
        )
        upper = max(
            0.0,
            min(1.0, (vertical - 0.68) / 0.32),
        )
        shoulder_weight = min(0.055, outer * upper * 0.055)
        maximum_shoulder_weight = max(
            maximum_shoulder_weight,
            shoulder_weight,
        )

        # Every shell vertex receives the same core torso blend. This keeps
        # garment volume stable under exaggerated game animations instead of
        # stretching the hem and collar between independently moving bones.
        basis = {
            bones["hips"]: 0.04,
            bones["waist"]: 0.14,
            bones["abdomen"]: 0.34,
            bones["chest"]: 0.48,
        }
        base_total = sum(basis.values())
        memberships = {
            group_name: weight / base_total * (1.0 - shoulder_weight)
            for group_name, weight in basis.items()
            if weight > 0.0
        }
        if shoulder_weight > 0.0:
            shoulder_name = bones[
                "shoulder_l" if vertex.co.x >= 0.0 else "shoulder_r"
            ]
            memberships[shoulder_name] = shoulder_weight
        projected.append(memberships)
    write_vertex_weights(vest, projected)
    return {
        "profile": "semantic_semi_rigid_sleeveless_torso_v2",
        "allowed_semantics": [
            "hips",
            "waist",
            "abdomen",
            "chest",
            "shoulder_l",
            "shoulder_r",
        ],
        "maximum_shoulder_weight": maximum_shoulder_weight,
        "excluded_limb_influences": True,
    }


def transfer_and_smooth_weights(
    source: bpy.types.Object,
    vest: bpy.types.Object,
    armature: bpy.types.Object,
    bones: dict[str, str],
    calibration: dict,
) -> dict:
    for group in source.vertex_groups:
        vest.vertex_groups.new(name=group.name)
    activate_only(vest)
    transfer = vest.modifiers.new("ContinuousWeightTransfer", "DATA_TRANSFER")
    transfer.object = source
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    transfer.mix_mode = "REPLACE"
    bpy.ops.object.modifier_apply(modifier=transfer.name)

    smooth_vertex_weights(vest, factor=0.28, passes=2)

    semantic_projection = project_weights_to_sleeveless_torso(vest, bones)

    final_weights = clean_limit_and_normalize_weights(vest, limit=4)
    totals = [sum(memberships.values()) for memberships in final_weights]
    unweighted = sum(total <= 0.00001 for total in totals)
    if unweighted:
        raise RuntimeError(f"Vest has {unweighted} unweighted vertices")
    vest.parent = armature
    vest.matrix_parent_inverse = armature.matrix_world.inverted()
    armature_modifier = vest.modifiers.new(
        "ContinuousWardrobeArmature",
        "ARMATURE",
    )
    armature_modifier.object = armature
    armature_modifier.use_vertex_groups = True
    return {
        "mapping": "POLYINTERP_NEAREST",
        "smoothing_factor": 0.28,
        "smoothing_passes": 2,
        "semantic_projection": semantic_projection,
        "unweighted": unweighted,
        "minimum_total": min(totals),
        "maximum_total": max(totals),
        "maximum_influences": max(map(len, final_weights)),
    }


def make_exposed_body(
    body: bpy.types.Object,
    calibration: dict,
    fit: dict,
    armature: bpy.types.Object,
) -> tuple[bpy.types.Object, list[int]]:
    exposed = body.copy()
    exposed.data = body.data.copy()
    exposed.name = "BodyExposedForCowboyVest"
    exposed.data.name = "BodyExposedForCowboyVestMesh"
    exposed["coverage_template"] = "continuous_sleeveless_vest_v1"
    bpy.context.scene.collection.objects.link(exposed)

    target_size = fit["target_size"]
    target_center = fit["target_center"]
    height = calibration["character_height"]
    bottom = target_center.z - target_size.z * 0.48
    top = target_center.z + target_size.z * 0.43
    half_width = target_size.x * 0.47
    center_opening = target_size.x * 0.13
    underarm = target_center.z + target_size.z * 0.10

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated_object = body.evaluated_get(depsgraph)
    evaluated_mesh = evaluated_object.to_mesh()
    hidden_faces = []
    for polygon in evaluated_mesh.polygons:
        points = [
            body.matrix_world @ evaluated_mesh.vertices[index].co
            for index in polygon.vertices
        ]
        center = sum(points, Vector()) / len(points)
        within_height = bottom <= center.z <= top
        back = (
            center.y >= target_center.y + height * 0.012
            and abs(center.x - target_center.x) <= half_width
        )
        front = (
            center.y <= target_center.y - height * 0.020
            and center_opening
            <= abs(center.x - target_center.x)
            <= half_width
        )
        side = (
            abs(center.x - target_center.x) >= half_width * 0.63
            and abs(center.x - target_center.x) <= half_width * 1.03
            and center.z <= underarm
        )
        safe_upper = (
            center.z >= underarm
            and center.z <= top
            and half_width * 0.34
            <= abs(center.x - target_center.x)
            <= half_width * 0.70
            and abs(center.y - target_center.y)
            <= target_size.y * 0.32
        )
        if within_height and (back or front or side or safe_upper):
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
        raise RuntimeError("Continuous vest coverage removed no faces")
    if not any(
        modifier.type == "ARMATURE" for modifier in exposed.modifiers
    ):
        modifier = exposed.modifiers.new("WardrobeArmature", "ARMATURE")
        modifier.object = armature
    return exposed, hidden_faces


def stats(obj: bpy.types.Object) -> dict:
    obj.data.calc_loop_triangles()
    return {
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
        "triangles": len(obj.data.loop_triangles),
        "uv_layers": [layer.name for layer in obj.data.uv_layers],
        "vertex_groups": len(obj.vertex_groups),
        "materials": [
            material.name
            for material in obj.data.materials
            if material is not None
        ],
    }


def add_review_stage(calibration: dict) -> bpy.types.Object:
    height = calibration["character_height"]
    target = calibration["body_center"]
    bpy.ops.object.camera_add(
        location=(0.0, -height * 2.4, height * 0.45)
    )
    camera = bpy.context.object
    camera.name = "ContinuousVestReviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = height * 1.12
    camera.rotation_euler = (
        target - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for name, location, energy, size in [
        (
            "ContinuousVestKey",
            (height * 1.6, -height * 1.8, height * 2.0),
            650.0,
            height * 3.0,
        ),
        (
            "ContinuousVestFill",
            (-height, height, height),
            260.0,
            height * 2.8,
        ),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (
            target - light.location
        ).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("ContinuousVestReviewWorld")
    world.color = (0.045, 0.045, 0.045)
    bpy.context.scene.world = world
    return camera


def render(
    path: Path,
    camera: bpy.types.Object,
    location: Vector,
    target: Vector,
    scale: float,
) -> None:
    camera.location = location
    camera.rotation_euler = (
        target - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = scale
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    standard = json.loads(STANDARD_PATH.read_text(encoding="utf-8"))
    mannequin = ROOT / standard["mannequin"]
    if sha256(SOURCE) != EXPECTED_SOURCE_SHA256:
        raise RuntimeError("Preserved cowboy vest design source changed")
    CANDIDATE_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(mannequin))
    body = bpy.data.objects[standard["body_object"]]
    armature = bpy.data.objects[standard["armature_object"]]
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    bones = standard["semantic_bones"]
    calibration = measure(body, bones)

    vest = import_design(SOURCE)
    vest.name = "CowboyVest"
    vest.data.name = "CowboyVestContinuousMesh"
    fit = fit_design(vest, calibration)
    finish = finish_continuous_shell(vest, calibration)
    reference = evaluated_rest_reference(body)
    weight_report = transfer_and_smooth_weights(
        reference,
        vest,
        armature,
        bones,
        calibration,
    )
    exposed, hidden_faces = make_exposed_body(
        body,
        calibration,
        fit,
        armature,
    )

    body.hide_set(True)
    body.hide_render = True
    reference.hide_set(True)
    reference.hide_render = True
    exposed.hide_set(False)
    exposed.hide_render = False

    bpy.ops.object.select_all(action="DESELECT")
    for obj in [armature, exposed, vest]:
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
    height = calibration["character_height"]
    target = calibration["body_center"]
    renders = [
        (
            "continuous_rest_front.png",
            Vector((0.0, -height * 2.4, height * 0.45)),
        ),
        (
            "continuous_rest_orbit.png",
            Vector((height * 1.55, -height * 2.0, height * 0.68)),
        ),
        (
            "continuous_rest_side.png",
            Vector((height * 2.5, 0.0, height * 0.44)),
        ),
        (
            "continuous_rest_back.png",
            Vector((0.0, height * 2.4, height * 0.45)),
        ),
    ]
    for filename, location in renders:
        render(
            PREVIEW_DIR / filename,
            camera,
            location,
            target,
            height * 1.14,
        )

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    report = {
        "standard": str(STANDARD_PATH.relative_to(ROOT)),
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": sha256(SOURCE),
        "mannequin": str(mannequin.relative_to(ROOT)),
        "output_glb": str(OUTPUT_GLB.relative_to(ROOT)),
        "output_glb_sha256": sha256(OUTPUT_GLB),
        "output_blend": str(OUTPUT_BLEND.relative_to(ROOT)),
        "calibration": {
            key: list(value) if isinstance(value, Vector) else value
            for key, value in calibration.items()
        },
        "fit": {
            key: list(value) if isinstance(value, Vector) else value
            for key, value in fit.items()
        },
        "continuous_shell": finish,
        "weights": weight_report,
        "coverage": {
            "hidden_faces": len(hidden_faces),
            "template": "continuous_sleeveless_vest_v1",
        },
        "garment": stats(vest),
        "exposed_body": stats(exposed),
        "reviews": [
            str((PREVIEW_DIR / filename).relative_to(ROOT))
            for filename, _location in renders
        ],
    }
    OUTPUT_REPORT.write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    print("CONTINUOUS_VEST_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
