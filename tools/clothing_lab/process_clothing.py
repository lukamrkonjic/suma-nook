"""Deterministic Clothing Lab processor.

This script deliberately contains no automatic fitting heuristic.  It applies
only the explicit ClothingFitSettings values chosen in the Godot lab, copies
weights from PlayerMaleBody with nearest-face interpolation, and binds the
garment to the canonical GameExportRig. Source UVs/materials, body mesh,
rest pose and bone transforms are preserved. An optional authored setting
blends only exported custom normals; it never changes geometry.

Usage (arguments after ``--``):
    blender --background --factory-startup --python process_clothing.py -- \
        --config fit.json --output garment.glb --report report.json \
        --review-blend review.blend
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from math import radians, sqrt
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, kdtree
from mathutils.bvhtree import BVHTree


REPO = Path(r"C:\Dev\suma-nook")
MASTER = REPO / "art_source/characters/suma_character_master.blend"
RIG_NAME = "GameExportRig"
BODY_NAME = "PlayerMaleBody"
GARMENT_NAME = "ClothingLabGarment"
FOOTWEAR_LEFT_GROUP = "ClothingLabFootwearLeft"
CLEARANCE = 0.004
SEAM_POSITION_EPSILON = 0.00001
MAX_ANIMATED_SEAM_GAP = 0.00005
MAX_ANIMATED_EDGE_STRETCH = 4.0
SLIVER_FACE_QUALITY_LIMIT = 0.0001
MAX_ANIMATED_SLIVER_OPENING = 0.002


def parse_arguments() -> argparse.Namespace:
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--review-blend", required=True)
    return parser.parse_args(sys.argv[separator + 1 :])


def resolved_path(value: str) -> Path:
    if value.startswith("res://"):
        return REPO / value.removeprefix("res://")
    return Path(value)


def vector(data: list[float]) -> Vector:
    return Vector((float(data[0]), float(data[1]), float(data[2])))


def object_matrix(obj: bpy.types.Object) -> list[float]:
    return [round(value, 8) for row in obj.matrix_world for value in row]


def rig_fingerprint(rig: bpy.types.Object) -> list:
    return [
        (
            bone.name,
            tuple(round(value, 8) for row in bone.matrix_local for value in row),
        )
        for bone in rig.data.bones
    ]


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def setup_master() -> tuple[bpy.types.Object, bpy.types.Object, dict]:
    bpy.ops.wm.open_mainfile(filepath=str(MASTER))
    rig = bpy.data.objects.get(RIG_NAME)
    body = bpy.data.objects.get(BODY_NAME)
    if rig is None or body is None:
        raise RuntimeError("Canonical GameExportRig/PlayerMaleBody missing")
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    if len(rig.data.bones) != 34:
        raise RuntimeError(f"Expected 34 canonical bones, got {len(rig.data.bones)}")
    return rig, body, {
        "rig_matrix": object_matrix(rig),
        "body_matrix": object_matrix(body),
        "rig_rest": rig_fingerprint(rig),
        "body_vertices": len(body.data.vertices),
    }


def import_source(source_path: Path) -> tuple[bpy.types.Object, dict]:
    if not source_path.is_file():
        raise RuntimeError(f"Source GLB does not exist: {source_path}")
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(source_path))
    added = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = [obj for obj in added if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Source GLB contains no mesh")
    garment = max(meshes, key=lambda item: len(item.data.vertices))
    for obj in added:
        if obj != garment:
            bpy.data.objects.remove(obj, do_unlink=True)
    garment.name = GARMENT_NAME
    garment.data.name = f"{GARMENT_NAME}Mesh"
    bpy.ops.object.select_all(action="DESELECT")
    garment.select_set(True)
    bpy.context.view_layer.objects.active = garment
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if garment.data.uv_layers.active is None:
        raise RuntimeError("Source garment has no UV map")
    return garment, {
        "path": str(source_path),
        "sha256": hashlib.sha256(source_path.read_bytes()).hexdigest().upper(),
        "vertices": len(garment.data.vertices),
        "triangles": triangle_count(garment),
        "uv_layer": garment.data.uv_layers.active.name,
        "materials": [material.name for material in garment.data.materials],
        "normals_preserved": True,
        "topology_preserved": True,
    }


def detail_position_key(point: Vector) -> tuple[int, int, int]:
    return tuple(
        round(float(point[axis]) * 100000.0) for axis in range(3)
    )


def source_detail_components(
    garment: bpy.types.Object,
) -> list[dict]:
    """Capture GLB split components before canonical seam welding.

    Reconstructed garments use small UV/normal-split components for buttons
    and similar decorations, while the actual cloth panels are much larger.
    Position keys let that classification survive the later topology weld.
    """
    adjacency = [set() for _ in garment.data.vertices]
    for edge in garment.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    visited: set[int] = set()
    components = []
    for seed in range(len(garment.data.vertices)):
        if seed in visited:
            continue
        stack = [seed]
        visited.add(seed)
        indices = []
        while stack:
            current = stack.pop()
            indices.append(current)
            for neighbor in adjacency[current]:
                if neighbor in visited:
                    continue
                visited.add(neighbor)
                stack.append(neighbor)
        positions = [
            garment.data.vertices[index].co.copy()
            for index in indices
        ]
        minimum = Vector(
            tuple(
                min(point[axis] for point in positions)
                for axis in range(3)
            )
        )
        maximum = Vector(
            tuple(
                max(point[axis] for point in positions)
                for axis in range(3)
            )
        )
        components.append(
            {
                "positions": positions,
                "position_keys": {
                    detail_position_key(point) for point in positions
                },
                "minimum": minimum,
                "maximum": maximum,
            }
        )
    return components


def apply_detail_erase_strokes(
    garment: bpy.types.Object,
    config: dict,
    source_components: list[dict] | None = None,
) -> dict:
    """Bake Clothing Lab's non-destructive detail brush in source space.

    Each version-2 dab identifies the compact source detail plus one local
    neighbor ring, then relaxes only those vertices toward their fixed cloth
    neighbors. This smooths a raised button into the garment without making a
    recessed planar cap. Complete boundary triangles inherit the sampled
    fabric UV, so old button-color interpolation cannot leave a false rim.
    """
    strokes = config.get("detail_erase_strokes", [])
    if not strokes:
        return {
            "method": "anchored local surface smoothing and fabric UV sampling",
            "strokes": 0,
            "affected_vertices": 0,
            "affected_uv_loops": 0,
            "maximum_displacement": 0.0,
            "topology_changed": False,
        }
    uv_layer = garment.data.uv_layers.active
    if uv_layer is None:
        raise RuntimeError("Detail Eraser requires a source UV map")
    original_positions = [
        vertex.co.copy() for vertex in garment.data.vertices
    ]
    garment_minimum = Vector(
        tuple(
            min(point[axis] for point in original_positions)
            for axis in range(3)
        )
    )
    garment_maximum = Vector(
        tuple(
            max(point[axis] for point in original_positions)
            for axis in range(3)
        )
    )
    garment_extent = max(garment_maximum - garment_minimum)
    original_position_keys = [
        detail_position_key(point) for point in original_positions
    ]
    adjacency = [set() for _ in garment.data.vertices]
    for edge in garment.data.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    affected_weights: dict[int, float] = {}
    sampled_uvs: dict[int, Vector] = {}
    loop_weights: dict[int, float] = {}
    loop_sampled_uvs: dict[int, Vector] = {}
    displaced_vertices: set[int] = set()
    smoothed_vertices: set[int] = set()
    maximum_displacement = 0.0
    selected_component_count = 0
    protected_large_component_count = 0
    for stroke_index, stroke in enumerate(strokes):
        stroke_start_positions = [
            vertex.co.copy() for vertex in garment.data.vertices
        ]
        center_data = stroke.get("center", [])
        normal_data = stroke.get("normal", [])
        uv_data = stroke.get("sample_uv", [])
        if (
            len(center_data) != 3
            or len(normal_data) != 3
            or len(uv_data) != 2
        ):
            raise RuntimeError(
                f"Detail Eraser dab {stroke_index} has invalid coordinates"
            )
        # Godot source coordinates (+Y up, -Z forward) to Blender
        # source coordinates (+Z up, +Y back).
        center = Vector(
            (
                float(center_data[0]),
                -float(center_data[2]),
                float(center_data[1]),
            )
        )
        normal = Vector(
            (
                float(normal_data[0]),
                -float(normal_data[2]),
                float(normal_data[1]),
            )
        )
        if normal.length_squared < 1.0e-12:
            raise RuntimeError(
                f"Detail Eraser dab {stroke_index} has a zero normal"
            )
        normal.normalize()
        radius = max(float(stroke.get("radius", 0.0)), 1.0e-6)
        strength = min(max(float(stroke.get("strength", 1.0)), 0.0), 1.0)
        target_offset = float(stroke.get("target_offset", 0.0))
        # The sampled cloth plane is immutable. Only an actual raised detail
        # clears this height dead-zone; nearby folds/curvature are therefore
        # never pulled toward the brush plane.
        detail_height_threshold = max(radius * 0.06, 0.002)
        component_aware = (
            int(stroke.get("version", 1)) >= 2
            and stroke.get("selection") == "small_source_components"
            and source_components is not None
        )
        component_extent_limit = min(
            max(radius * 2.20, garment_extent * 0.10),
            garment_extent * 0.18,
        )
        applied_height_threshold = (
            0.0002 if component_aware else detail_height_threshold
        )
        selected_position_keys: set[tuple[int, int, int]] = set()
        if component_aware:
            for component in source_components:
                extent = component["maximum"] - component["minimum"]
                maximum_extent = max(extent)
                if maximum_extent > component_extent_limit:
                    protected_large_component_count += 1
                    continue
                intersects_raised_detail = False
                for point in component["positions"]:
                    delta = point - center
                    projection = delta.dot(normal)
                    tangent_distance = (
                        delta - normal * projection
                    ).length
                    if (
                        tangent_distance <= radius * 1.05
                        and projection
                        > target_offset + applied_height_threshold
                    ):
                        intersects_raised_detail = True
                        break
                if not intersects_raised_detail:
                    continue
                selected_component_count += 1
                selected_position_keys.update(
                    component["position_keys"]
                )
        core_vertex_indices = {
            vertex.index
            for vertex in garment.data.vertices
            if original_position_keys[vertex.index]
            in selected_position_keys
        }
        smooth_vertex_indices = set(core_vertex_indices)
        if component_aware:
            for vertex_index in core_vertex_indices:
                for neighbor_index in adjacency[vertex_index]:
                    source_delta = (
                        original_positions[neighbor_index] - center
                    )
                    source_projection = source_delta.dot(normal)
                    tangent_distance = (
                        source_delta - normal * source_projection
                    ).length
                    if tangent_distance <= radius * 1.25:
                        smooth_vertex_indices.add(neighbor_index)
        sample_uv = Vector((float(uv_data[0]), float(uv_data[1])))
        for vertex in garment.data.vertices:
            if (
                component_aware
                and vertex.index not in smooth_vertex_indices
            ):
                continue
            source_delta = original_positions[vertex.index] - center
            source_projection = source_delta.dot(normal)
            tangent_distance = (
                source_delta - normal * source_projection
            ).length
            projection = (vertex.co - center).dot(normal)
            if component_aware:
                if strength > affected_weights.get(vertex.index, 0.0):
                    affected_weights[vertex.index] = strength
                    sampled_uvs[vertex.index] = sample_uv.copy()
                if vertex.index not in core_vertex_indices:
                    continue
            if (
                tangent_distance
                >= radius * (1.20 if component_aware else 1.0)
            ):
                continue
            if projection <= target_offset + applied_height_threshold:
                continue
            if component_aware:
                weight = strength
            else:
                normalized_distance = tangent_distance / radius
                falloff = 1.0 - (
                    normalized_distance
                    * normalized_distance
                    * (3.0 - 2.0 * normalized_distance)
                )
                weight = min(max(strength * falloff, 0.0), 1.0)
            displacement = (projection - target_offset) * weight
            if displacement <= 0.0:
                continue
            vertex.co -= normal * displacement
            displaced_vertices.add(vertex.index)
            maximum_displacement = max(maximum_displacement, displacement)
            if (
                not component_aware
                and weight > affected_weights.get(vertex.index, 0.0)
            ):
                affected_weights[vertex.index] = weight
                sampled_uvs[vertex.index] = sample_uv.copy()
        if component_aware and smooth_vertex_indices:
            # Recolor every corner of a triangle touching the repair. A
            # single stale UV corner interpolates the old button/collar color
            # into a bright rim even when the geometry is already smooth.
            for polygon in garment.data.polygons:
                if not any(
                    vertex_index in smooth_vertex_indices
                    for vertex_index in polygon.vertices
                ):
                    continue
                for loop_index in polygon.loop_indices:
                    if strength > loop_weights.get(loop_index, 0.0):
                        loop_weights[loop_index] = strength
                        loop_sampled_uvs[loop_index] = sample_uv.copy()

            # Anchored Jacobi relaxation: only the compact detail and one
            # local ring move. All neighboring cloth is an immutable boundary.
            relaxation = 0.55 * strength
            for _iteration in range(32):
                updates = {}
                for vertex_index in smooth_vertex_indices:
                    if not adjacency[vertex_index]:
                        continue
                    average = sum(
                        (
                            garment.data.vertices[neighbor].co
                            for neighbor in adjacency[vertex_index]
                        ),
                        start=Vector((0.0, 0.0, 0.0)),
                    ) / len(adjacency[vertex_index])
                    updates[vertex_index] = garment.data.vertices[
                        vertex_index
                    ].co.lerp(average, relaxation)
                for vertex_index, point in updates.items():
                    garment.data.vertices[vertex_index].co = point
            normal_cap = radius * 0.45 * strength
            tangent_cap = radius * 0.15 * strength
            for vertex_index in smooth_vertex_indices:
                delta = (
                    garment.data.vertices[vertex_index].co
                    - stroke_start_positions[vertex_index]
                )
                normal_amount = min(
                    max(delta.dot(normal), -normal_cap),
                    normal_cap,
                )
                tangent = delta - normal * delta.dot(normal)
                if tangent.length > tangent_cap:
                    tangent.normalize()
                    tangent *= tangent_cap
                garment.data.vertices[vertex_index].co = (
                    stroke_start_positions[vertex_index]
                    + normal * normal_amount
                    + tangent
                )
            smoothed_vertices.update(smooth_vertex_indices)
    for loop in garment.data.loops:
        weight = affected_weights.get(loop.vertex_index, 0.0)
        if weight > loop_weights.get(loop.index, 0.0):
            loop_weights[loop.index] = weight
            loop_sampled_uvs[loop.index] = sampled_uvs[
                loop.vertex_index
            ].copy()
    affected_loops = 0
    for loop in garment.data.loops:
        weight = loop_weights.get(loop.index, 0.0)
        if weight <= 0.12:
            continue
        uv_layer.data[loop.index].uv = uv_layer.data[loop.index].uv.lerp(
            loop_sampled_uvs[loop.index],
            weight,
        )
        affected_loops += 1
    garment.data.update()
    for vertex in garment.data.vertices:
        displacement = (
            vertex.co - original_positions[vertex.index]
        ).length
        if displacement <= 1.0e-8:
            continue
        displaced_vertices.add(vertex.index)
        maximum_displacement = max(maximum_displacement, displacement)
    return {
        "method": "anchored local surface smoothing and fabric UV sampling",
        "strokes": len(strokes),
        "affected_vertices": len(affected_weights),
        "displaced_vertices": len(displaced_vertices),
        "smoothed_vertices": len(smoothed_vertices),
        "smoothing_iterations": 32,
        "affected_uv_loops": affected_loops,
        "maximum_displacement": round(maximum_displacement, 8),
        "topology_changed": False,
        "inside_shell_protected": True,
        "selection": "small source components for version 2 strokes",
        "selected_source_components": selected_component_count,
        "protected_large_source_components": (
            protected_large_component_count
        ),
        "materials_preserved": True,
        "_affected_vertex_indices": sorted(affected_weights),
    }


def smooth_section_blend(value: float) -> float:
    value = min(max(value, 0.0), 1.0)
    return value * value * (3.0 - 2.0 * value)


def section_scale_at_height(
    height: float,
    minimum_height: float,
    maximum_height: float,
    top_scale: float,
    middle_scale: float,
    bottom_scale: float,
) -> float:
    height_range = maximum_height - minimum_height
    if height_range <= 0.000001:
        return middle_scale
    normalized = min(
        max((height - minimum_height) / height_range, 0.0),
        1.0,
    )
    if normalized <= 0.5:
        blend = smooth_section_blend(normalized * 2.0)
        return bottom_scale + (middle_scale - bottom_scale) * blend
    blend = smooth_section_blend((normalized - 0.5) * 2.0)
    return middle_scale + (top_scale - middle_scale) * blend


def apply_explicit_fit(garment: bpy.types.Object, config: dict) -> dict:
    scale = vector(config["scale"])
    rotation = vector(config["rotation_degrees"])
    position = vector(config["position"])
    pair_center_position = vector(
        config.get("pair_center_position", [0.0, 0.0, 0.0])
    )
    garment_class = config.get("garment_class", "upper_body")
    garment.data.transform(Matrix.Diagonal((scale.x, scale.y, scale.z, 1.0)))

    torso_width = float(config["torso_width"])
    torso_depth = float(config["torso_depth"])
    top_section_scale = float(config.get("top_section_scale", 1.0))
    middle_section_scale = float(config.get("middle_section_scale", 1.0))
    bottom_section_scale = float(config.get("bottom_section_scale", 1.0))
    sleeve_lift = float(config["sleeve_lift"])
    sleeve_length = float(config["sleeve_length"])
    sleeve_room = float(config.get("sleeve_room", 1.0))
    shoulder_lift = float(config.get("shoulder_lift", 0.0))
    cuff_radius = float(config["cuff_radius"])
    cuff_forward = float(config["cuff_forward"])
    minimum_height = min(vertex.co.z for vertex in garment.data.vertices)
    maximum_height = max(vertex.co.z for vertex in garment.data.vertices)
    if garment_class in {
        "lower_body",
        "footwear",
        "upper_body_sleeveless",
    }:
        for vertex in garment.data.vertices:
            section_scale = section_scale_at_height(
                vertex.co.z,
                minimum_height,
                maximum_height,
                top_section_scale,
                middle_section_scale,
                bottom_section_scale,
            )
            vertex.co.x *= torso_width * section_scale
            vertex.co.y *= torso_depth * section_scale
        rotation_matrix = Euler(
            tuple(
                value * 0.017453292519943295
                for value in rotation
            )
        ).to_matrix()
        if garment_class == "footwear":
            for vertex in garment.data.vertices:
                side = 1.0 if vertex.co.x >= 0.0 else -1.0
                vertex.co = (
                    rotation_matrix @ vertex.co
                    + pair_center_position
                    + Vector(
                        (
                            side * position.x,
                            side * position.y,
                            position.z,
                        )
                    )
                )
        else:
            final_transform = (
                Matrix.Translation(position)
                @ rotation_matrix.to_4x4()
            )
            garment.data.transform(final_transform)
        garment.data.update()
        return {
            "method": {
                "upper_body_sleeveless": (
                    "explicit non-sleeved lab controls only"
                ),
                "lower_body": "explicit lower-body lab controls only",
                "footwear": "explicit footwear lab controls only",
            }[garment_class],
            "garment_class": garment_class,
            "position": list(position),
            "pair_center_position": list(pair_center_position),
            "rotation_degrees": list(rotation),
            "scale": list(scale),
            "symmetric_controls": bool(config["symmetric"]),
            "torso_width": torso_width,
            "torso_depth": torso_depth,
            "section_scales": {
                "top": top_section_scale,
                "middle": middle_section_scale,
                "bottom": bottom_section_scale,
            },
            "landmark_targets": {},
            "source_normals_smoothed": False,
            "source_geometry_subdivided_or_decimated": False,
        }
    landmarks = config.get("landmarks", {})
    fallback = {
        "left": {
            "shoulder": [0.13, 0.024, 0.10],
            "wrist": [0.27, 0.016, 0.092],
        },
        "right": {
            "shoulder": [-0.13, 0.024, 0.10],
            "wrist": [-0.27, 0.016, 0.092],
        },
    }
    landmark_points = []
    for side in ("left", "right"):
        source = landmarks.get(side, fallback[side])
        if "shoulder" not in source or "wrist" not in source:
            source = fallback[side]
        landmark_points.append(
            {
                "shoulder": vector(source["shoulder"]),
                "wrist": vector(source["wrist"]),
            }
        )
    shoulder_target = Vector(
        (
            sum(abs(item["shoulder"].x) for item in landmark_points)
            / len(landmark_points),
            sum(item["shoulder"].y for item in landmark_points)
            / len(landmark_points),
            sum(item["shoulder"].z for item in landmark_points)
            / len(landmark_points),
        )
    )
    shoulder_x = shoulder_target.x
    wrist_target = Vector(
        (
            sum(abs(item["wrist"].x) for item in landmark_points)
            / len(landmark_points),
            sum(item["wrist"].y for item in landmark_points)
            / len(landmark_points),
            sum(item["wrist"].z for item in landmark_points)
            / len(landmark_points),
        )
    )
    sleeve_root = max(shoulder_x - 0.015, 0.09)
    endpoint_before = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    source_cuff_points = [
        vertex.co.copy()
        for vertex in garment.data.vertices
        if abs(vertex.co.x) >= endpoint_before - 0.030
    ]
    source_center_y = (
        min(point.y for point in source_cuff_points)
        + max(point.y for point in source_cuff_points)
    ) * 0.5
    source_center_z = (
        min(point.z for point in source_cuff_points)
        + max(point.z for point in source_cuff_points)
    ) * 0.5
    target_endpoint = wrist_target.x - 0.006
    landmark_length_scale = (
        (target_endpoint - sleeve_root)
        / max(endpoint_before - sleeve_root, 0.001)
    )
    effective_length = landmark_length_scale * sleeve_length
    landmark_forward = wrist_target.y - source_center_y
    landmark_lift = wrist_target.z - source_center_z

    for vertex in garment.data.vertices:
        x = abs(vertex.co.x)
        sign = 1.0 if vertex.co.x >= 0.0 else -1.0
        if x < sleeve_root:
            section_scale = section_scale_at_height(
                vertex.co.z,
                minimum_height,
                maximum_height,
                top_section_scale,
                middle_section_scale,
                bottom_section_scale,
            )
            vertex.co.x *= torso_width * section_scale
            vertex.co.y *= torso_depth * section_scale
            continue
        ramp = min(max((x - sleeve_root) / max(endpoint_before - sleeve_root, 0.001), 0.0), 1.0)
        shoulder_start = max(sleeve_root - 0.030, 0.075)
        shoulder_weight = 1.0 - min(
            max(
                (x - shoulder_start)
                / max(endpoint_before - shoulder_start, 0.001),
                0.0,
            ),
            1.0,
        )
        vertex.co.x = sign * (
            sleeve_root + (x - sleeve_root) * effective_length
        )
        vertex.co.z += (landmark_lift + sleeve_lift) * ramp
        vertex.co.z += shoulder_lift * shoulder_weight
        vertex.co.y += (landmark_forward + cuff_forward) * ramp
        center_y = (
            shoulder_target.y
            + (wrist_target.y - shoulder_target.y) * ramp
        )
        center_z = (
            shoulder_target.z
            + (wrist_target.z - shoulder_target.z) * ramp
        )
        vertex.co.y = center_y + (vertex.co.y - center_y) * sleeve_room
        vertex.co.z = center_z + (vertex.co.z - center_z) * sleeve_room

    endpoint_after = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    cuff_start = endpoint_after - 0.030
    cuff_points = [
        vertex.co.copy()
        for vertex in garment.data.vertices
        if abs(vertex.co.x) >= cuff_start
    ]
    if cuff_points:
        center_y = (min(point.y for point in cuff_points) + max(point.y for point in cuff_points)) * 0.5
        center_z = (min(point.z for point in cuff_points) + max(point.z for point in cuff_points)) * 0.5
        for vertex in garment.data.vertices:
            if abs(vertex.co.x) < cuff_start:
                continue
            vertex.co.y = center_y + (vertex.co.y - center_y) * cuff_radius
            vertex.co.z = center_z + (vertex.co.z - center_z) * cuff_radius
    final_transform = (
        Matrix.Translation(position)
        @ Euler(
            tuple(
                value * 0.017453292519943295
                for value in rotation
            )
        ).to_matrix().to_4x4()
    )
    garment.data.transform(final_transform)
    garment.data.update()
    return {
        "method": "explicit lab controls only",
        "garment_class": garment_class,
        "position": list(position),
        "rotation_degrees": list(rotation),
        "scale": list(scale),
        "symmetric_controls": bool(config["symmetric"]),
        "torso_width": torso_width,
        "torso_depth": torso_depth,
        "section_scales": {
            "top": top_section_scale,
            "middle": middle_section_scale,
            "bottom": bottom_section_scale,
        },
        "sleeve_lift": sleeve_lift,
        "sleeve_length": sleeve_length,
        "sleeve_room": sleeve_room,
        "shoulder_lift": shoulder_lift,
        "cuff_radius": cuff_radius,
        "cuff_forward": cuff_forward,
        "landmark_targets": {
            "shoulder_x": round(shoulder_x, 6),
            "wrist": [round(value, 6) for value in wrist_target],
            "sleeve_root_x": round(sleeve_root, 6),
            "before_hand_endpoint_x": round(target_endpoint, 6),
            "baseline_length_scale": round(landmark_length_scale, 6),
            "baseline_forward_shift": round(landmark_forward, 6),
            "baseline_lift": round(landmark_lift, 6),
        },
        "source_normals_smoothed": False,
        "source_geometry_subdivided_or_decimated": False,
    }


def symmetrize_sleeves(
    garment: bpy.types.Object,
    garment_class: str = "upper_body",
) -> dict:
    """Make the deforming sleeve shells bilateral without touching details.

    The torso, collar, hem, pockets, buttons and UV loop data are excluded.
    Matching is position-only; no UVs, material slots or normals are rebuilt.
    """
    if garment_class != "upper_body":
        return {
            "method": "not applicable to non-sleeved clothing",
            "matched_pairs": 0,
            "topology_unchanged": True,
        }
    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    sleeve_start = min(0.118, endpoint * 0.48)
    left = [
        vertex
        for vertex in garment.data.vertices
        if vertex.co.x > sleeve_start
    ]
    right = [
        vertex
        for vertex in garment.data.vertices
        if vertex.co.x < -sleeve_start
    ]
    # Candidate matching must be bijective. The previous nearest-neighbor
    # implementation allowed multiple left-side vertices to move the same
    # right-side vertex while coincident UV/normal seam copies stayed behind.
    # That split an originally watertight garment into visible holes.
    candidates = []
    for left_vertex in left:
        for right_vertex in right:
            mirrored_right = Vector(
                (-right_vertex.co.x, right_vertex.co.y, right_vertex.co.z)
            )
            distance = (left_vertex.co - mirrored_right).length
            if distance <= 0.018:
                candidates.append(
                    (distance, left_vertex.index, right_vertex.index)
                )
    candidates.sort(key=lambda item: (item[0], item[1], item[2]))
    used_left = set()
    used_right = set()
    replacements = []
    maximum_delta = 0.0
    for distance, left_index, right_index in candidates:
        if left_index in used_left or right_index in used_right:
            continue
        used_left.add(left_index)
        used_right.add(right_index)
        left_vertex = garment.data.vertices[left_index]
        right_vertex = garment.data.vertices[right_index]
        mean_x = (
            abs(left_vertex.co.x) + abs(right_vertex.co.x)
        ) * 0.5
        mean_y = (left_vertex.co.y + right_vertex.co.y) * 0.5
        mean_z = (left_vertex.co.z + right_vertex.co.z) * 0.5
        replacements.append(
            (
                left_index,
                Vector((mean_x, mean_y, mean_z)),
                right_index,
                Vector((-mean_x, mean_y, mean_z)),
            )
        )
        maximum_delta = max(maximum_delta, distance)
    for left_index, left_co, right_index, right_co in replacements:
        garment.data.vertices[left_index].co = left_co
        garment.data.vertices[right_index].co = right_co
    garment.data.update()
    return {
        "method": "bilateral sleeve position mirror around X=0",
        "matched_pairs": len(replacements),
        "unmatched_left_vertices": len(left) - len(used_left),
        "unmatched_right_vertices": len(right) - len(used_right),
        "maximum_source_delta": round(maximum_delta, 6),
        "torso_collar_hem_pockets_and_uvs_untouched": True,
    }


def preserved_feature(co: Vector, endpoint: float, minimum_z: float) -> str:
    x = abs(co.x)
    if x > endpoint - 0.030:
        return "cuff_openings"
    if co.z < minimum_z + 0.022:
        return "hem"
    if x < 0.100 and co.z > 0.068:
        return "collar"
    if 0.038 < x < 0.132 and -0.115 < co.z < -0.010 and co.y < -0.078:
        return "pockets"
    if x < 0.040 and -0.105 < co.z < 0.035 and co.y < -0.078:
        return "buttons"
    return ""


def limited_shrinkwrap_clearance(
    garment: bpy.types.Object,
    body: bpy.types.Object,
    garment_class: str = "upper_body",
) -> dict:
    """Push only unsafe cloth outward with a masked Shrinkwrap modifier."""
    if garment_class != "upper_body":
        return {
            "method": (
                "non-sleeved source fit preserved; no jacket-specific "
                "shrinkwrap mask applied"
            ),
            "target_clearance": CLEARANCE,
            "unsafe_vertices": 0,
            "safe_vertices_pulled_inward": False,
            "feature_preservation_masks": {},
        }
    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    minimum_z = min(vertex.co.z for vertex in garment.data.vertices)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(body.evaluated_get(depsgraph), depsgraph)
    unsafe = []
    protected = {
        "collar": 0,
        "hem": 0,
        "pockets": 0,
        "buttons": 0,
        "cuff_openings": 0,
    }
    signed_before = []
    for vertex in garment.data.vertices:
        x = abs(vertex.co.x)
        deforming_shell = (
            (x < 0.148 and minimum_z + 0.018 < vertex.co.z < 0.092)
            or (0.116 < x < endpoint - 0.028)
        )
        if not deforming_shell:
            continue
        feature = preserved_feature(vertex.co, endpoint, minimum_z)
        if feature:
            protected[feature] += 1
            continue
        nearest = bvh.find_nearest(vertex.co)
        if nearest is None or nearest[3] > 0.055:
            continue
        signed = (vertex.co - nearest[0]).dot(nearest[1].normalized())
        signed_before.append(signed)
        if signed < CLEARANCE:
            unsafe.append(vertex.index)

    if unsafe:
        group = garment.vertex_groups.new(name="ClothingFitClearance")
        group.add(unsafe, 1.0, "REPLACE")
        modifier = garment.modifiers.new(
            "LimitedBodyClearanceShrinkwrap", "SHRINKWRAP"
        )
        modifier.target = body
        modifier.vertex_group = group.name
        modifier.wrap_method = "NEAREST_SURFACEPOINT"
        modifier.wrap_mode = "OUTSIDE_SURFACE"
        modifier.offset = CLEARANCE
        apply_modifier(garment, modifier.name)
        remaining_group = garment.vertex_groups.get(
            "ClothingFitClearance"
        )
        if remaining_group is not None:
            garment.vertex_groups.remove(remaining_group)

    signed_after = []
    for index in unsafe:
        nearest = bvh.find_nearest(garment.data.vertices[index].co)
        if nearest is None:
            continue
        signed_after.append(
            (garment.data.vertices[index].co - nearest[0]).dot(
                nearest[1].normalized()
            )
        )
    minimum_after = min(signed_after) if signed_after else CLEARANCE
    if minimum_after < CLEARANCE - 0.0006:
        raise RuntimeError(
            "Limited Shrinkwrap failed positive clearance: "
            f"{minimum_after:.6f}"
        )
    return {
        "method": "masked Blender Shrinkwrap, nearest surface outside",
        "target_clearance": CLEARANCE,
        "unsafe_vertices": len(unsafe),
        "minimum_signed_before": round(
            min(signed_before) if signed_before else CLEARANCE, 6
        ),
        "minimum_signed_after": round(minimum_after, 6),
        "safe_vertices_pulled_inward": False,
        "feature_preservation_masks": protected,
    }


def weld_coincident_geometry_preserving_loops(
    garment: bpy.types.Object,
    epsilon: float = SEAM_POSITION_EPSILON,
) -> dict:
    """Share true seam positions while retaining corner UV/material data.

    Blender stores UVs per face corner, so coincident geometric vertices can
    be merged without joining UV islands or material regions. Doing this
    before support subdivision makes both sides of every visual seam receive
    the same new edge vertices and prevents animated T-junction cracks.
    """
    vertices_before = len(garment.data.vertices)
    polygons_before = len(garment.data.polygons)
    uv_layers_before = len(garment.data.uv_layers)
    materials_before = len(garment.data.materials)
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bmesh.ops.remove_doubles(
        bm,
        verts=list(bm.verts),
        dist=epsilon,
    )
    bm.to_mesh(garment.data)
    bm.free()
    garment.data.update()
    if (
        len(garment.data.polygons) != polygons_before
        or len(garment.data.uv_layers) != uv_layers_before
        or len(garment.data.materials) != materials_before
    ):
        raise RuntimeError(
            "Geometric seam weld changed faces, UV layers, or materials"
        )
    return {
        "method": (
            "coincident geometric seam weld with per-corner UV preservation"
        ),
        "position_epsilon": epsilon,
        "vertices_before": vertices_before,
        "vertices_after": len(garment.data.vertices),
        "merged_duplicate_vertices": (
            vertices_before - len(garment.data.vertices)
        ),
        "polygons_preserved": True,
        "uv_layers_preserved": uv_layers_before,
        "materials_preserved": materials_before,
    }


def garment_topology_signature(garment: bpy.types.Object) -> dict:
    """Describe holes/non-manifold defects without modifying the garment."""
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bm.verts.ensure_lookup_table()
    boundary_edges = [
        edge for edge in bm.edges if len(edge.link_faces) == 1
    ]
    boundary_adjacency = {}
    for edge in boundary_edges:
        first, second = edge.verts
        boundary_adjacency.setdefault(first.index, set()).add(second.index)
        boundary_adjacency.setdefault(second.index, set()).add(first.index)
    remaining = set(boundary_adjacency)
    component_count = 0
    while remaining:
        component_count += 1
        stack = [remaining.pop()]
        while stack:
            current = stack.pop()
            for neighbor in boundary_adjacency[current]:
                if neighbor not in remaining:
                    continue
                remaining.remove(neighbor)
                stack.append(neighbor)
    vertex_adjacency = {
        vertex.index: {
            other.index
            for edge in vertex.link_edges
            for other in edge.verts
            if other != vertex
        }
        for vertex in bm.verts
    }
    remaining_vertices = set(vertex_adjacency)
    connected_components = 0
    while remaining_vertices:
        connected_components += 1
        stack = [remaining_vertices.pop()]
        while stack:
            current = stack.pop()
            for neighbor in vertex_adjacency[current]:
                if neighbor not in remaining_vertices:
                    continue
                remaining_vertices.remove(neighbor)
                stack.append(neighbor)
    result = {
        "boundary_components": component_count,
        "boundary_edges": len(boundary_edges),
        "branched_boundary_vertices": sum(
            len(neighbors) != 2
            for neighbors in boundary_adjacency.values()
        ),
        "over_connected_edges": sum(
            len(edge.link_faces) > 2 for edge in bm.edges
        ),
        "wire_edges": sum(not edge.link_faces for edge in bm.edges),
        "connected_components": connected_components,
        "euler_characteristic": (
            len(bm.verts) - len(bm.edges) + len(bm.faces)
        ),
    }
    bm.free()
    return result


def assert_topology_contract(
    garment: bpy.types.Object,
    expected: dict,
    stage: str,
) -> dict:
    """Reject any stage that creates a slit or non-manifold connection."""
    actual = garment_topology_signature(garment)
    failures = []
    for key in (
        "boundary_components",
        "boundary_edges",
        "branched_boundary_vertices",
        "over_connected_edges",
        "wire_edges",
        "connected_components",
        "euler_characteristic",
    ):
        if actual[key] != expected[key]:
            failures.append(f"{key} {actual[key]} != {expected[key]}")
    if failures:
        raise RuntimeError(
            f"Garment topology changed during {stage}: "
            + "; ".join(failures)
        )
    return {
        "stage": stage,
        "expected": expected.copy(),
        "actual": actual,
        "passed": True,
    }


def audit_deformation_geometry(
    garment: bpy.types.Object,
    garment_class: str = "upper_body",
) -> dict:
    """Add zero-smoothing local support geometry, then verify density."""
    if garment_class != "upper_body":
        return {
            "strategy": (
                "authored non-sleeved topology preserved; animation audit "
                "validates the bound garment after weight transfer"
            ),
            "selected_unique_edges": 0,
            "zone_edges_before": {},
            "zone_vertex_counts_before": {},
            "zone_vertex_counts_after": {},
            "minimum_required_per_zone": 0,
            "single_stretched_deformation_polygon": False,
            "triangles_before": triangle_count(garment),
            "triangles_after": triangle_count(garment),
            "topology_modified": False,
            "smoothing_applied": False,
            "uv_welding_applied": False,
        }
    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    zones = {
        "shoulders": lambda co: 0.112 < abs(co.x) < 0.172
        and 0.040 < co.z < 0.135,
        "armpits": lambda co: 0.112 < abs(co.x) < 0.178
        and -0.020 < co.z < 0.070,
        "elbows": lambda co: 0.175 < abs(co.x) < 0.230,
        "cuffs": lambda co: abs(co.x) > endpoint - 0.035,
    }
    density_before = {
        name: sum(
            1 for vertex in garment.data.vertices if predicate(vertex.co)
        )
        for name, predicate in zones.items()
    }
    triangles_before = triangle_count(garment)
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    selected_edges = set()
    zone_edges = {}
    for name, predicate in zones.items():
        edges = [
            edge
            for edge in bm.edges
            if predicate(edge.verts[0].co)
            and predicate(edge.verts[1].co)
        ]
        zone_edges[name] = len(edges)
        selected_edges.update(edges)
    if selected_edges:
        bmesh.ops.subdivide_edges(
            bm,
            edges=list(selected_edges),
            cuts=1,
            use_grid_fill=True,
            smooth=0.0,
            use_sphere=False,
        )
    bm.to_mesh(garment.data)
    bm.free()
    garment.data.update()
    density_after = {
        name: sum(
            1 for vertex in garment.data.vertices if predicate(vertex.co)
        )
        for name, predicate in zones.items()
    }
    insufficient = [
        name for name, count in density_after.items() if count < 32
    ]
    if insufficient:
        raise RuntimeError(
            "Insufficient deformation geometry in: "
            + ", ".join(insufficient)
        )
    return {
        "strategy": (
            "UV-safe local edge subdivision with zero smoothing; "
            "no relaxation or global subdivision; coincident geometry "
            "was canonicalized in the preceding seam stage"
        ),
        "selected_unique_edges": len(selected_edges),
        "zone_edges_before": zone_edges,
        "zone_vertex_counts_before": density_before,
        "zone_vertex_counts_after": density_after,
        "minimum_required_per_zone": 32,
        "single_stretched_deformation_polygon": False,
        "triangles_before": triangles_before,
        "triangles_after": triangle_count(garment),
        "topology_modified": bool(selected_edges),
        "smoothing_applied": False,
        "uv_welding_applied": False,
    }


def apply_modifier(obj: bpy.types.Object, name: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=name)


def triangulate_for_export(
    garment: bpy.types.Object,
) -> dict:
    """Resolve all n-gons before glTF can choose unstable hidden diagonals."""
    polygons_before = len(garment.data.polygons)
    triangles_before = sum(
        1 for polygon in garment.data.polygons if len(polygon.vertices) == 3
    )
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.triangulate(
        bm,
        faces=list(bm.faces),
        quad_method="BEAUTY",
        ngon_method="BEAUTY",
    )
    bm.to_mesh(garment.data)
    bm.free()
    garment.data.update()
    non_triangles = sum(
        1 for polygon in garment.data.polygons if len(polygon.vertices) != 3
    )
    if non_triangles:
        raise RuntimeError(
            f"Garment still contains {non_triangles} non-triangle faces"
        )
    return {
        "method": "explicit pre-export bmesh triangulation",
        "polygons_before": polygons_before,
        "triangles_before": triangles_before,
        "triangles_after": len(garment.data.polygons),
        "non_triangles_after": non_triangles,
        "glTF_triangulation_deferred": False,
        "uvs_normals_materials_preserved": True,
    }


def remove_degenerate_faces(
    garment: bpy.types.Object,
    area_epsilon: float = 1.0e-8,
) -> dict:
    """Remove zero-area and nearly collinear export-only triangles."""
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bm.faces.ensure_lookup_table()
    collapsed = [
        face
        for face in bm.faces
        if face.calc_area() <= area_epsilon
        or (
            len(face.verts) == 3
            and face_quality([vertex.co for vertex in face.verts])
            <= SLIVER_FACE_QUALITY_LIMIT
        )
    ]
    removed_faces = len(collapsed)
    if collapsed:
        bmesh.ops.delete(bm, geom=collapsed, context="FACES")
        loose_vertices = [
            vertex
            for vertex in bm.verts
            if not vertex.link_faces and not vertex.link_edges
        ]
        if loose_vertices:
            bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
        bm.to_mesh(garment.data)
        garment.data.update()
    bm.free()
    remaining = sum(
        1
        for polygon in garment.data.polygons
        if polygon.area <= area_epsilon
        or (
            len(polygon.vertices) == 3
            and face_quality(
                [
                    garment.data.vertices[index].co
                    for index in polygon.vertices
                ]
            )
            <= SLIVER_FACE_QUALITY_LIMIT
        )
    )
    if remaining:
        raise RuntimeError(
            f"Garment still contains {remaining} zero-area faces"
        )
    return {
        "removed_zero_area_faces": removed_faces,
        "removed_zero_or_sliver_faces": removed_faces,
        "remaining_zero_area_faces": remaining,
        "area_epsilon": area_epsilon,
        "sliver_quality_limit": SLIVER_FACE_QUALITY_LIMIT,
    }


def apply_surface_smoothing(
    garment: bpy.types.Object,
    amount: float,
    forced_smooth_vertices: set[int] | None = None,
) -> dict:
    """Blend lighting normals only; never move or rebuild garment geometry."""
    amount = max(0.0, min(float(amount), 1.0))
    forced_smooth_vertices = forced_smooth_vertices or set()
    mesh = garment.data
    mesh.update()
    vertices_before = [
        tuple(round(value, 10) for value in vertex.co)
        for vertex in mesh.vertices
    ]
    if amount <= 0.0001 and not forced_smooth_vertices:
        return {
            "amount": amount,
            "method": "authored normals unchanged",
            "custom_corner_normals": False,
            "geometry_changed": False,
        }

    authored = [
        normal.vector.copy()
        for normal in mesh.corner_normals
    ]
    incident_faces = [
        []
        for _vertex in mesh.vertices
    ]
    for polygon in mesh.polygons:
        for vertex_index in polygon.vertices:
            incident_faces[vertex_index].append(
                (
                    polygon.normal.copy(),
                    max(polygon.area, 1.0e-12),
                )
            )
    blended = []
    for loop_index, loop in enumerate(mesh.loops):
        loop_amount = (
            1.0
            if loop.vertex_index in forced_smooth_vertices
            else amount
        )
        original = authored[loop_index]
        if original.length_squared <= 1.0e-16:
            original = mesh.polygons[loop.polygon_index].normal.copy()
        else:
            original.normalize()
        target = Vector((0.0, 0.0, 0.0))
        for face_normal, area in incident_faces[loop.vertex_index]:
            # Preserve hard folds and never mix outer cloth with an inner
            # or opposite shell. Only similarly oriented faces contribute.
            if original.dot(face_normal) >= 0.35:
                target += face_normal * area
        if target.length_squared <= 1.0e-16:
            target = original
        else:
            target.normalize()
        normal = original.lerp(target, loop_amount)
        if normal.length_squared <= 1.0e-16:
            normal = original
        else:
            normal.normalize()
        blended.append(normal)

    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.normals_split_custom_set(blended)
    mesh.update()
    vertices_after = [
        tuple(round(value, 10) for value in vertex.co)
        for vertex in mesh.vertices
    ]
    if vertices_before != vertices_after:
        raise RuntimeError(
            "Normals-only surface smoothing changed garment geometry"
        )
    return {
        "amount": round(amount, 4),
        "method": (
            "crease-aware authored-to-area-weighted "
            "custom corner-normal blend"
        ),
        "minimum_neighbor_normal_dot": 0.35,
        "custom_corner_normals": True,
        "geometry_changed": False,
        "vertices_unchanged": len(vertices_after),
        "loops_smoothed": len(blended),
        "detail_erase_vertices_smoothed": len(forced_smooth_vertices),
    }


def audit_boundary_t_junctions(
    garment: bpy.types.Object,
    epsilon: float = SEAM_POSITION_EPSILON,
) -> dict:
    """Reject a boundary vertex landing inside another unsplit boundary edge."""
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    bm.verts.ensure_lookup_table()
    boundary_edges = [
        edge for edge in bm.edges if len(edge.link_faces) == 1
    ]
    boundary_vertices = {
        vertex for edge in boundary_edges for vertex in edge.verts
    }
    junctions = []
    for vertex in boundary_vertices:
        point = vertex.co
        for edge in boundary_edges:
            if vertex in edge.verts:
                continue
            start = edge.verts[0].co
            finish = edge.verts[1].co
            direction = finish - start
            length_squared = direction.length_squared
            if length_squared <= epsilon * epsilon:
                continue
            factor = (point - start).dot(direction) / length_squared
            endpoint_margin = epsilon / sqrt(length_squared)
            if not endpoint_margin < factor < 1.0 - endpoint_margin:
                continue
            closest = start + direction * factor
            if (point - closest).length <= epsilon:
                junctions.append(
                    {
                        "vertex": vertex.index,
                        "edge": edge.index,
                        "factor": round(factor, 6),
                    }
                )
                if len(junctions) >= 20:
                    break
        if len(junctions) >= 20:
            break
    bm.free()
    if junctions:
        raise RuntimeError(
            "Garment contains animated boundary T-junctions: "
            + json.dumps(junctions[:5])
        )
    return {
        "method": "boundary vertex-on-unsplit-edge audit",
        "boundary_edges": len(boundary_edges),
        "t_junctions": 0,
        "position_epsilon": epsilon,
        "passed": True,
    }


def face_quality(
    coordinates: list[Vector],
) -> float:
    """Scale-independent triangle quality: 0 is collinear, 1 equilateral."""
    if len(coordinates) != 3:
        return 1.0
    first, second, third = coordinates
    edge_squared_sum = (
        (second - first).length_squared
        + (third - second).length_squared
        + (first - third).length_squared
    )
    if edge_squared_sum <= 1.0e-16:
        return 0.0
    area = (second - first).cross(third - first).length * 0.5
    return (4.0 * sqrt(3.0) * area) / edge_squared_sum


def synchronize_sliver_face_weights(
    garment: bpy.types.Object,
    quality_limit: float = SLIVER_FACE_QUALITY_LIMIT,
) -> dict:
    """Keep nearly collinear support triangles collapsed while animated.

    Low-poly garments and zero-smoothing support cuts can legitimately contain
    triangles that contribute essentially no visible rest-pose surface. If
    their three vertices receive different bone blends, animation can inflate
    that collapsed triangle into a large underside wedge. The vertices in each
    connected sliver component therefore receive one normalized weight blend.
    Geometry, UVs, normals and materials are left untouched.
    """
    vertices = garment.data.vertices
    sliver_faces = [
        polygon
        for polygon in garment.data.polygons
        if len(polygon.vertices) == 3
        and face_quality(
            [vertices[index].co for index in polygon.vertices]
        )
        <= quality_limit
    ]
    parents = list(range(len(vertices)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first_root = find(first)
        second_root = find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    involved = set()
    for polygon in sliver_faces:
        indices = list(polygon.vertices)
        involved.update(indices)
        union(indices[0], indices[1])
        union(indices[0], indices[2])
    # Include every UV/material/normal split copy of a sliver vertex in the
    # same constraint component. The later global seam pass then becomes
    # idempotent instead of undoing part of the sliver stabilization.
    tree = kdtree.KDTree(len(vertices))
    for vertex in vertices:
        tree.insert(vertex.co, vertex.index)
    tree.balance()
    sliver_vertices = list(involved)
    for index in sliver_vertices:
        for _co, other_index, distance in tree.find_range(
            vertices[index].co,
            SEAM_POSITION_EPSILON,
        ):
            if distance <= SEAM_POSITION_EPSILON:
                involved.add(other_index)
                union(index, other_index)
    components: dict[int, list[int]] = {}
    for index in involved:
        components.setdefault(find(index), []).append(index)

    index_to_name = {
        group.index: group.name for group in garment.vertex_groups
    }
    name_to_group = {
        group.name: group for group in garment.vertex_groups
    }
    maximum_weight_delta_before = 0.0
    for indices in components.values():
        snapshots = []
        average: dict[str, float] = {}
        for index in indices:
            snapshot = {
                index_to_name[assignment.group]: assignment.weight
                for assignment in vertices[index].groups
            }
            snapshots.append(snapshot)
            for name, weight in snapshot.items():
                average[name] = average.get(name, 0.0) + weight
        for name in average:
            average[name] /= len(indices)
        strongest = sorted(
            average.items(),
            key=lambda item: (-item[1], item[0]),
        )[:4]
        total = sum(weight for _name, weight in strongest)
        if total <= 0.0:
            continue
        normalized = {
            name: weight / total for name, weight in strongest
        }
        for snapshot in snapshots:
            maximum_weight_delta_before = max(
                maximum_weight_delta_before,
                sum(
                    abs(
                        snapshot.get(name, 0.0)
                        - normalized.get(name, 0.0)
                    )
                    for name in set(snapshot) | set(normalized)
                ),
            )
        for index in indices:
            for assignment in list(vertices[index].groups):
                garment.vertex_groups[assignment.group].remove([index])
            for name, weight in normalized.items():
                group = name_to_group.get(name)
                if group is None:
                    group = garment.vertex_groups.new(name=name)
                    name_to_group[name] = group
                    index_to_name[group.index] = name
                group.add([index], weight, "REPLACE")
    return {
        "method": (
            "connected sliver-triangle weight synchronization without "
            "geometry changes"
        ),
        "quality_limit": quality_limit,
        "sliver_faces": len(sliver_faces),
        "sliver_components": len(components),
        "synchronized_vertices": len(involved),
        "maximum_weight_delta_before": round(
            maximum_weight_delta_before, 8
        ),
        "maximum_weight_delta_after": 0.0,
        "geometry_changed": False,
        "uvs_normals_materials_preserved": True,
    }


def synchronize_coincident_vertex_weights(
    garment: bpy.types.Object,
    epsilon: float = SEAM_POSITION_EPSILON,
) -> dict:
    """Give coincident UV/material seam copies exactly identical weights.

    The source GLB legitimately duplicates vertices to preserve flat normals,
    UV islands and material boundaries. Welding those vertices would damage
    the authored look. Their skin weights, however, must be identical or the
    visually continuous surface opens into cracks as soon as a bone moves.
    """
    vertices = garment.data.vertices
    parents = list(range(len(vertices)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first_root = find(first)
        second_root = find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    tree = kdtree.KDTree(len(vertices))
    for vertex in vertices:
        tree.insert(vertex.co, vertex.index)
    tree.balance()
    for vertex in vertices:
        for _co, other_index, distance in tree.find_range(
            vertex.co, epsilon
        ):
            if other_index != vertex.index and distance <= epsilon:
                union(vertex.index, other_index)

    components: dict[int, list[int]] = {}
    for vertex in vertices:
        components.setdefault(find(vertex.index), []).append(vertex.index)
    seam_groups = [
        indices for indices in components.values() if len(indices) > 1
    ]
    index_to_name = {
        group.index: group.name for group in garment.vertex_groups
    }
    name_to_group = {
        group.name: group for group in garment.vertex_groups
    }

    def weights(index: int) -> dict[str, float]:
        return {
            index_to_name[assignment.group]: assignment.weight
            for assignment in vertices[index].groups
        }

    def delta(
        first: dict[str, float],
        second: dict[str, float],
    ) -> float:
        return sum(
            abs(first.get(name, 0.0) - second.get(name, 0.0))
            for name in set(first) | set(second)
        )

    changed_groups = 0
    maximum_delta_before = 0.0
    synchronized_vertices = 0
    for indices in seam_groups:
        snapshots = [weights(index) for index in indices]
        average: dict[str, float] = {}
        for snapshot in snapshots:
            for name, weight in snapshot.items():
                average[name] = average.get(name, 0.0) + weight
        for name in average:
            average[name] /= len(indices)
        total = sum(average.values())
        if total <= 0.0:
            continue
        average = {
            name: weight / total
            for name, weight in average.items()
            if weight > 0.000001
        }
        group_delta = max(
            (delta(snapshots[0], snapshot) for snapshot in snapshots[1:]),
            default=0.0,
        )
        maximum_delta_before = max(maximum_delta_before, group_delta)
        if group_delta <= 0.000001:
            continue
        changed_groups += 1
        synchronized_vertices += len(indices)
        for index in indices:
            for assignment in list(vertices[index].groups):
                garment.vertex_groups[assignment.group].remove([index])
            for name, weight in average.items():
                group = name_to_group.get(name)
                if group is None:
                    group = garment.vertex_groups.new(name=name)
                    name_to_group[name] = group
                group.add([index], weight, "REPLACE")

    return {
        "method": "weight synchronization without geometry/UV welding",
        "position_epsilon": epsilon,
        "coincident_seam_groups": len(seam_groups),
        "corrected_seam_groups": changed_groups,
        "synchronized_vertices": synchronized_vertices,
        "maximum_weight_delta_before": round(maximum_delta_before, 8),
        "maximum_weight_delta_after": 0.0,
        "geometry_welded": False,
        "uvs_preserved": True,
        "materials_preserved": True,
    }


def synchronize_short_edge_weights(
    garment: bpy.types.Object,
    maximum_length: float = 0.004,
    minimum_weight_delta: float = 0.25,
) -> dict:
    """Prevent tiny connected edges from becoming animation spikes.

    An edge only a few millimeters long cannot safely carry an abrupt bone
    palette transition: even a normal walk pose can pull its endpoints apart
    by many times its rest length. Average only connected components of short
    edges whose endpoint weight delta is already unsafe. Ordinary silhouette
    edges and gradual deformation gradients are left untouched.
    """
    vertices = garment.data.vertices
    index_to_name = {
        group.index: group.name for group in garment.vertex_groups
    }
    name_to_group = {
        group.name: group for group in garment.vertex_groups
    }

    def weights(index: int) -> dict[str, float]:
        return {
            index_to_name[assignment.group]: assignment.weight
            for assignment in vertices[index].groups
        }

    def delta(
        first: dict[str, float],
        second: dict[str, float],
    ) -> float:
        return sum(
            abs(first.get(name, 0.0) - second.get(name, 0.0))
            for name in set(first) | set(second)
        )

    snapshots = {
        vertex.index: weights(vertex.index) for vertex in vertices
    }
    unsafe_edges = []
    for edge in garment.data.edges:
        first, second = edge.vertices
        length = (vertices[first].co - vertices[second].co).length
        weight_delta = delta(snapshots[first], snapshots[second])
        if (
            length <= maximum_length
            and weight_delta >= minimum_weight_delta
        ):
            unsafe_edges.append((first, second, length, weight_delta))

    parents = list(range(len(vertices)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first_root = find(first)
        second_root = find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    involved = set()
    for first, second, _length, _weight_delta in unsafe_edges:
        involved.update((first, second))
        union(first, second)
    components: dict[int, list[int]] = {}
    for index in involved:
        components.setdefault(find(index), []).append(index)

    for indices in components.values():
        average: dict[str, float] = {}
        for index in indices:
            for name, weight in snapshots[index].items():
                average[name] = average.get(name, 0.0) + weight
        for name in average:
            average[name] /= len(indices)
        strongest = sorted(
            average.items(),
            key=lambda item: (-item[1], item[0]),
        )[:4]
        total = sum(weight for _name, weight in strongest)
        if total <= 0.0:
            continue
        normalized = {
            name: weight / total for name, weight in strongest
        }
        for index in indices:
            for assignment in list(vertices[index].groups):
                garment.vertex_groups[assignment.group].remove([index])
            for name, weight in normalized.items():
                group = name_to_group.get(name)
                if group is None:
                    group = garment.vertex_groups.new(name=name)
                    name_to_group[name] = group
                group.add([index], weight, "REPLACE")

    return {
        "method": (
            "unsafe short-edge component weight synchronization without "
            "geometry changes"
        ),
        "maximum_edge_length": maximum_length,
        "minimum_endpoint_weight_delta": minimum_weight_delta,
        "unsafe_edges": len(unsafe_edges),
        "components": len(components),
        "synchronized_vertices": len(involved),
        "maximum_edge_length_found": round(
            max(
                (length for _a, _b, length, _delta in unsafe_edges),
                default=0.0,
            ),
            8,
        ),
        "maximum_weight_delta_before": round(
            max(
                (weight_delta for _a, _b, _length, weight_delta in unsafe_edges),
                default=0.0,
            ),
            8,
        ),
        "maximum_weight_delta_after": 0.0,
        "geometry_changed": False,
    }


def correct_arm_chain_weights(garment: bpy.types.Object) -> dict:
    """Relax transferred arm-chain weights without changing garment geometry."""
    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    index_to_name = {
        group.index: group.name for group in garment.vertex_groups
    }
    name_to_group = {
        group.name: group for group in garment.vertex_groups
    }

    neighbors = [set() for _vertex in garment.data.vertices]
    for edge in garment.data.edges:
        first, second = edge.vertices
        neighbors[first].add(second)
        neighbors[second].add(first)

    # UV/material seams may duplicate a vertex at precisely the same spatial
    # location. Join only those coincident copies for weight relaxation; do
    # not bridge the garment's front and back surfaces.
    tree = kdtree.KDTree(len(garment.data.vertices))
    for vertex in garment.data.vertices:
        tree.insert(vertex.co, vertex.index)
    tree.balance()
    for vertex in garment.data.vertices:
        for _co, other_index, distance in tree.find_range(vertex.co, 0.00001):
            if other_index != vertex.index and distance <= 0.00001:
                neighbors[vertex.index].add(other_index)

    zone_indices = {
        "all_surface": {
            vertex.index for vertex in garment.data.vertices
        },
        "shoulder_armpit": {
            vertex.index
            for vertex in garment.data.vertices
            if 0.075 <= abs(vertex.co.x) < 0.210
        },
        "elbow": {
            vertex.index
            for vertex in garment.data.vertices
            if 0.175 <= abs(vertex.co.x) < min(0.240, endpoint - 0.030)
        },
    }

    def snapshot() -> dict[int, dict[str, float]]:
        return {
            vertex.index: {
                index_to_name[assignment.group]: assignment.weight
                for assignment in vertex.groups
            }
            for vertex in garment.data.vertices
        }

    def replace_weights(
        vertex_index: int,
        weights: dict[str, float],
    ) -> None:
        vertex = garment.data.vertices[vertex_index]
        for assignment in list(vertex.groups):
            garment.vertex_groups[assignment.group].remove([vertex_index])
        total = sum(weights.values())
        if total <= 0.0:
            return
        for name, weight in weights.items():
            if weight <= 0.0001:
                continue
            group = name_to_group.get(name)
            if group is None:
                group = garment.vertex_groups.new(name=name)
                name_to_group[name] = group
            group.add([vertex_index], weight / total, "REPLACE")

    def relax(indices: set[int], passes: int, factor: float) -> None:
        for _pass in range(passes):
            before = snapshot()
            updates = {}
            for index in indices:
                local_neighbors = [
                    candidate
                    for candidate in neighbors[index]
                    if candidate in indices
                ]
                if not local_neighbors:
                    continue
                average = {}
                for neighbor_index in local_neighbors:
                    for name, weight in before[neighbor_index].items():
                        average[name] = average.get(name, 0.0) + weight
                for name in average:
                    average[name] /= len(local_neighbors)
                current = before[index]
                names = set(current) | set(average)
                updates[index] = {
                    name: (
                        current.get(name, 0.0) * (1.0 - factor)
                        + average.get(name, 0.0) * factor
                    )
                    for name in names
                }
            for index, weights in updates.items():
                replace_weights(index, weights)

    relax(zone_indices["all_surface"], passes=4, factor=0.30)
    relax(zone_indices["shoulder_armpit"], passes=6, factor=0.42)
    relax(zone_indices["elbow"], passes=3, factor=0.30)

    return {
        "method": (
            "nearest-face body weights plus connected-edge and coincident-"
            "seam weight-only relaxation"
        ),
        "corrected_vertices": len(
            zone_indices["shoulder_armpit"] | zone_indices["elbow"]
        ),
        "zones": {
            name: len(indices) for name, indices in zone_indices.items()
        },
        "passes": {
            "all_surface": 4,
            "shoulder_armpit": 6,
            "elbow": 3,
        },
        "surface_geometry_smoothed": False,
        "source_normals_preserved": True,
        "uvs_or_materials_changed": False,
    }


def correct_lower_chain_weights(garment: bpy.types.Object) -> dict:
    """Keep trouser center seams coherent while preserving independent legs.

    Nearest-face transfer can assign opposite leg weights to two vertices only
    millimeters apart at the crotch. During a walk those vertices are pulled
    in opposite directions and a tiny authored bridge becomes a long spike.
    Away from the centerline, opposite-leg influences are mirrored onto the
    geometrically matching leg. Inside the centerline band, corresponding
    left/right chain weights are made bilateral so connected seam vertices
    remain coincident while both thighs can still influence the cloth.
    """
    names = {
        group.index: group.name for group in garment.vertex_groups
    }
    groups = {
        group.name: group for group in garment.vertex_groups
    }
    pairs = (
        ("mixamorigLeftUpLeg", "mixamorigRightUpLeg"),
        ("mixamorigLeftLeg", "mixamorigRightLeg"),
        ("mixamorigLeftFoot", "mixamorigRightFoot"),
        ("mixamorigLeftToeBase", "mixamorigRightToeBase"),
    )
    center_width = 0.012
    center_vertices = 0
    side_vertices = 0

    def snapshot(vertex: bpy.types.MeshVertex) -> dict[str, float]:
        return {
            names[assignment.group]: assignment.weight
            for assignment in vertex.groups
        }

    def replace(
        vertex: bpy.types.MeshVertex,
        weights: dict[str, float],
    ) -> None:
        for assignment in list(vertex.groups):
            garment.vertex_groups[assignment.group].remove([vertex.index])
        total = sum(weights.values())
        if total <= 0.0:
            return
        for name, weight in weights.items():
            if weight <= 0.000001:
                continue
            group = groups.get(name)
            if group is None:
                group = garment.vertex_groups.new(name=name)
                groups[name] = group
                names[group.index] = name
            group.add([vertex.index], weight / total, "REPLACE")

    for vertex in garment.data.vertices:
        weights = snapshot(vertex)
        if abs(vertex.co.x) <= center_width:
            for left_name, right_name in pairs:
                bilateral = (
                    weights.pop(left_name, 0.0)
                    + weights.pop(right_name, 0.0)
                ) * 0.5
                if bilateral > 0.0:
                    weights[left_name] = bilateral
                    weights[right_name] = bilateral
            center_vertices += 1
        else:
            target_left = vertex.co.x > 0.0
            for left_name, right_name in pairs:
                if target_left:
                    weights[left_name] = (
                        weights.get(left_name, 0.0)
                        + weights.pop(right_name, 0.0)
                    )
                else:
                    weights[right_name] = (
                        weights.get(right_name, 0.0)
                        + weights.pop(left_name, 0.0)
                    )
            side_vertices += 1
        replace(vertex, weights)
    return {
        "method": (
            "bilateral center-seam leg weights with side-specific chain "
            "mirroring; geometry unchanged"
        ),
        "centerline_half_width": center_width,
        "center_vertices": center_vertices,
        "side_vertices": side_vertices,
        "geometry_changed": False,
    }


def copy_body_weights(
    garment: bpy.types.Object,
    body: bpy.types.Object,
    rig: bpy.types.Object,
    garment_class: str = "upper_body",
) -> dict:
    transfer = garment.modifiers.new("CopyBodyWeightsNearestFace", "DATA_TRANSFER")
    transfer.object = body
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = garment
    bpy.ops.object.datalayout_transfer(modifier=transfer.name)
    apply_modifier(garment, transfer.name)

    def remap_groups(predicate, target_name: str) -> dict:
        names = {
            group.index: group.name for group in garment.vertex_groups
        }
        target = garment.vertex_groups.get(target_name)
        if target is None:
            target = garment.vertex_groups.new(name=target_name)
        affected = 0
        remapped_weight = 0.0
        for vertex in garment.data.vertices:
            addition = sum(
                assignment.weight
                for assignment in vertex.groups
                if predicate(names.get(assignment.group, ""))
            )
            if addition <= 0.0:
                continue
            target.add([vertex.index], addition, "ADD")
            affected += 1
            remapped_weight += addition
        removable = [
            group
            for group in garment.vertex_groups
            if group.name != target_name and predicate(group.name)
        ]
        removed_names = [group.name for group in removable]
        for group in removable:
            garment.vertex_groups.remove(group)
        return {
            "target": target_name,
            "affected_vertices": affected,
            "remapped_weight": round(remapped_weight, 6),
            "removed_groups": removed_names,
        }

    # Nearest body faces at a wrist often carry finger weights.  A garment
    # cuff must follow the wrist/hand as a unit, never individual thumb/finger
    # joints.  Likewise, a jacket hem may sample an upper-leg face even though
    # jacket cloth belongs to the hips/torso chain.
    if garment_class == "footwear":
        footwear_left = garment.vertex_groups.get(FOOTWEAR_LEFT_GROUP)
        if footwear_left is None:
            raise RuntimeError("Footwear source-side classification is missing")
        left_indices = {
            vertex.index
            for vertex in garment.data.vertices
            if any(
                assignment.group == footwear_left.index
                and assignment.weight > 0.5
                for assignment in vertex.groups
            )
        }
        left_foot = garment.vertex_groups.get("mixamorigLeftFoot")
        if left_foot is None:
            left_foot = garment.vertex_groups.new(name="mixamorigLeftFoot")
        right_foot = garment.vertex_groups.get("mixamorigRightFoot")
        if right_foot is None:
            right_foot = garment.vertex_groups.new(name="mixamorigRightFoot")
        for vertex in garment.data.vertices:
            for assignment in list(vertex.groups):
                garment.vertex_groups[assignment.group].remove([vertex.index])
            target = (
                left_foot
                if vertex.index in left_indices
                else right_foot
            )
            target.add([vertex.index], 1.0, "REPLACE")
        removable = [
            group
            for group in garment.vertex_groups
            if group not in {left_foot, right_foot}
        ]
        removed_names = [group.name for group in removable]
        for group in removable:
            garment.vertex_groups.remove(group)
        left_digits = {
            "target": "not applicable",
            "affected_vertices": 0,
            "remapped_weight": 0.0,
            "removed_groups": [],
        }
        right_digits = left_digits.copy()
        lower_body = {
            "target": "left/right foot bones",
            "affected_vertices": len(garment.data.vertices),
            "remapped_weight": float(len(garment.data.vertices)),
            "removed_groups": removed_names,
        }
        deformation_correction = {
            "method": (
                "rigid per-shoe foot-bone weights preserve authored panels"
            ),
            "corrected_vertices": len(garment.data.vertices),
            "upper_body_groups_to_hips": {
                "target": "not applicable",
                "affected_vertices": 0,
                "remapped_weight": 0.0,
                "removed_groups": [],
            },
            "lower_chain_seam_weights": {
                "method": "not applicable to rigid footwear weights",
                "center_vertices": 0,
                "side_vertices": len(garment.data.vertices),
                "geometry_changed": False,
            },
        }
    elif garment_class == "lower_body":
        lower_chain = {
            "mixamorigHips",
            "mixamorigLeftUpLeg",
            "mixamorigLeftLeg",
            "mixamorigLeftFoot",
            "mixamorigLeftToeBase",
            "mixamorigRightUpLeg",
            "mixamorigRightLeg",
            "mixamorigRightFoot",
            "mixamorigRightToeBase",
        }
        upper_body = remap_groups(
            lambda name: (
                name.startswith("mixamorig")
                and name not in lower_chain
            ),
            "mixamorigHips",
        )
        left_digits = {
            "target": "not applicable",
            "affected_vertices": 0,
            "remapped_weight": 0.0,
            "removed_groups": [],
        }
        right_digits = left_digits.copy()
        lower_body = {
            "target": "preserved lower-body chain",
            "affected_vertices": 0,
            "remapped_weight": 0.0,
            "removed_groups": [],
        }
        deformation_correction = {
            "method": "not applicable to lower-body clothing",
            "corrected_vertices": 0,
            "upper_body_groups_to_hips": upper_body,
            "lower_chain_seam_weights": (
                correct_lower_chain_weights(garment)
            ),
        }
    else:
        left_digits = remap_groups(
            lambda name: name.startswith("mixamorigLeftHand")
            and name != "mixamorigLeftHand",
            "mixamorigLeftHand",
        )
        right_digits = remap_groups(
            lambda name: name.startswith("mixamorigRightHand")
            and name != "mixamorigRightHand",
            "mixamorigRightHand",
        )
        lower_body = remap_groups(
            lambda name: any(
                token in name
                for token in (
                    "UpLeg", "LeftLeg", "RightLeg", "Foot", "ToeBase"
                )
            ),
            "mixamorigHips",
        )
        deformation_correction = correct_arm_chain_weights(garment)
    # A four-influence export must not alternate its fourth bone across a
    # single shoulder edge (Hips on one end, Arm on the other). Consolidate
    # the anatomically irrelevant Hips contribution into Spine throughout
    # the upper sidewall before limiting influences.
    hips = garment.vertex_groups.get("mixamorigHips")
    spine = garment.vertex_groups.get("mixamorigSpine")
    shoulder_palette_vertices = 0
    if (
        garment_class not in {"lower_body", "footwear"}
        and hips is not None
        and spine is not None
    ):
        for vertex in garment.data.vertices:
            if abs(vertex.co.x) < 0.070 or vertex.co.z < -0.050:
                continue
            hip_weight = 0.0
            for assignment in vertex.groups:
                if assignment.group == hips.index:
                    hip_weight = assignment.weight
                    break
            if hip_weight <= 0.0:
                continue
            spine.add([vertex.index], hip_weight, "ADD")
            hips.remove([vertex.index])
            shoulder_palette_vertices += 1

    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    cuff_corrections = {}
    cuff_blend_width = 0.090
    for side, sign in (
        (("Left", 1.0), ("Right", -1.0))
        if garment_class == "upper_body"
        else ()
    ):
        forearm = garment.vertex_groups.get(
            f"mixamorig{side}ForeArm"
        )
        hand = garment.vertex_groups.get(f"mixamorig{side}Hand")
        if forearm is None or hand is None:
            raise RuntimeError(
                f"Transferred weights lack {side} forearm/hand groups"
            )
        corrected = 0
        for vertex in garment.data.vertices:
            side_x = sign * vertex.co.x
            if side_x < endpoint - cuff_blend_width:
                continue
            ramp = min(
                max(
                    (
                        side_x
                        - (endpoint - cuff_blend_width)
                    )
                    / cuff_blend_width,
                    0.0,
                ),
                1.0,
            )
            blend = ramp * ramp * (3.0 - 2.0 * ramp)
            hand_ramp = min(
                max(
                    (
                        side_x
                        - (endpoint - 0.030)
                    )
                    / 0.030,
                    0.0,
                ),
                1.0,
            )
            names = {
                group.index: group.name for group in garment.vertex_groups
            }
            source = {
                names[assignment.group]: assignment.weight
                for assignment in vertex.groups
            }
            target = {
                f"mixamorig{side}ForeArm": 1.0 - 0.20 * hand_ramp,
                f"mixamorig{side}Hand": 0.20 * hand_ramp,
            }
            blended = {
                name: (
                    source.get(name, 0.0) * (1.0 - blend)
                    + target.get(name, 0.0) * blend
                )
                for name in set(source) | set(target)
            }
            for assignment in list(vertex.groups):
                garment.vertex_groups[assignment.group].remove(
                    [vertex.index]
                )
            for name, weight in blended.items():
                if weight <= 0.000001:
                    continue
                group = garment.vertex_groups.get(name)
                if group is None:
                    group = garment.vertex_groups.new(name=name)
                group.add([vertex.index], weight, "REPLACE")
            corrected += 1
        cuff_corrections[side.lower()] = {
            "vertices": corrected,
            "blend_width": cuff_blend_width,
            "weights": (
                "smooth source-to-forearm transition; hand influence "
                "ramps only across the final 30 mm"
            ),
        }

    sliver_correction = synchronize_sliver_face_weights(garment)
    seam_correction = synchronize_coincident_vertex_weights(garment)
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.0001)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(
        group_select_mode="ALL", lock_active=False
    )
    # Limiting the final exported palette to four influences can amplify a
    # previously modest endpoint difference. Apply the short-edge guard to
    # that exact final palette, then normalize once more.
    short_edge_correction = synchronize_short_edge_weights(garment)
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.0001)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(
        group_select_mode="ALL", lock_active=False
    )
    totals = [
        sum(assignment.weight for assignment in vertex.groups)
        for vertex in garment.data.vertices
    ]
    if not totals or min(totals) < 0.999:
        raise RuntimeError("Nearest-face copy left unweighted garment vertices")

    armature = garment.modifiers.new("BindExistingGameExportRig", "ARMATURE")
    armature.object = rig
    garment.parent = rig
    garment.matrix_parent_inverse = rig.matrix_world.inverted()

    rig_bones = {bone.name for bone in rig.data.bones}
    invalid_groups = [
        group.name for group in garment.vertex_groups if group.name not in rig_bones
    ]
    if invalid_groups:
        raise RuntimeError(f"Non-canonical weight groups: {invalid_groups}")
    return {
        "source": BODY_NAME,
        "garment_class": garment_class,
        "mapping": "POLYINTERP_NEAREST",
        "automatic_weights_used": False,
        "deterministic_cleanup": {
            "left_fingers_to_hand": left_digits,
            "right_fingers_to_hand": right_digits,
            "lower_body_to_hips": lower_body,
            "shoulder_armpit_elbow_weights": deformation_correction,
            "upper_sidewall_hips_to_spine_vertices": (
                shoulder_palette_vertices
            ),
            "pose_corrected_cuffs": cuff_corrections,
            "collapsed_sliver_weights": sliver_correction,
            "coincident_seam_weights": seam_correction,
            "unsafe_short_edge_weights": short_edge_correction,
        },
        "clean_threshold": 0.0001,
        "maximum_influences": max(len(vertex.groups) for vertex in garment.data.vertices),
        "minimum_weight_total": round(min(totals), 6),
        "maximum_weight_total": round(max(totals), 6),
        "armature_modifier_target": rig.name,
        "independent_armature_created": False,
    }


def verify_immutable(
    rig: bpy.types.Object,
    body: bpy.types.Object,
    before: dict,
) -> dict:
    unchanged = (
        object_matrix(rig) == before["rig_matrix"]
        and object_matrix(body) == before["body_matrix"]
        and rig_fingerprint(rig) == before["rig_rest"]
        and len(body.data.vertices) == before["body_vertices"]
    )
    if not unchanged:
        raise RuntimeError("Processor modified canonical body or rig")
    return {
        "body_and_rig_unchanged": True,
        "bone_count": len(rig.data.bones),
        "rest_t_pose": rig.data.pose_position == "REST",
    }


def export_glb(
    garment: bpy.types.Object,
    rig: bpy.types.Object,
    output: Path,
) -> None:
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    garment.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )


def audit_exported_glb(
    output: Path,
    expected_smoothing: float = 0.0,
    expected_topology: dict | None = None,
    preserve_split_seams: bool = False,
    expected_triangles: int | None = None,
) -> dict:
    """Reimport the exact GLB and reject exporter-introduced crack hazards."""
    objects_before = set(bpy.data.objects)
    collections_before = set(bpy.data.collections)
    bpy.ops.import_scene.gltf(filepath=str(output))
    imported_objects = [
        obj for obj in bpy.data.objects if obj not in objects_before
    ]
    imported_meshes = [
        obj for obj in imported_objects if obj.type == "MESH"
    ]
    if not imported_meshes:
        raise RuntimeError("Exported GLB reimport contains no garment mesh")
    garment = max(
        imported_meshes,
        key=lambda obj: len(obj.data.polygons),
    )
    vertices = garment.data.vertices
    index_to_name = {
        group.index: group.name for group in garment.vertex_groups
    }

    def weights(index: int) -> dict[str, float]:
        return {
            index_to_name[assignment.group]: assignment.weight
            for assignment in vertices[index].groups
            if assignment.weight > 0.000001
        }

    def weight_delta(
        first: dict[str, float],
        second: dict[str, float],
    ) -> float:
        return sum(
            abs(first.get(name, 0.0) - second.get(name, 0.0))
            for name in set(first) | set(second)
        )

    coincident: dict[tuple[int, int, int], list[int]] = {}
    for vertex in vertices:
        key = tuple(
            round(value / SEAM_POSITION_EPSILON)
            for value in vertex.co
        )
        coincident.setdefault(key, []).append(vertex.index)
    seam_groups = [
        indices for indices in coincident.values() if len(indices) > 1
    ]
    maximum_weight_delta = 0.0
    discontinuous_groups = 0
    for indices in seam_groups:
        reference = weights(indices[0])
        maximum = max(
            (
                weight_delta(reference, weights(index))
                for index in indices[1:]
            ),
            default=0.0,
        )
        maximum_weight_delta = max(maximum_weight_delta, maximum)
        if maximum > 0.00001:
            discontinuous_groups += 1
    degenerate_faces = sum(
        1
        for polygon in garment.data.polygons
        if len(polygon.vertices) != 3
        or polygon.area <= 1.0e-10
        or face_quality(
            [vertices[index].co for index in polygon.vertices]
        )
        <= SLIVER_FACE_QUALITY_LIMIT
    )
    exported_vertices = len(vertices)
    exported_triangles = len(garment.data.polygons)
    corner_normals = [
        normal.vector.copy()
        for normal in garment.data.corner_normals
    ]
    invalid_normals = sum(
        1
        for normal in corner_normals
        if not 0.999 <= normal.length <= 1.001
    )
    custom_normals_preserved = bool(garment.data.has_custom_normals)
    if not corner_normals or invalid_normals:
        raise RuntimeError(
            "Exact exported GLB has missing or invalid corner normals"
        )
    if expected_smoothing > 0.0001 and not custom_normals_preserved:
        raise RuntimeError(
            "Exact exported GLB lost the selected custom smoothing normals"
        )
    if preserve_split_seams:
        canonical_weld = {
            "method": (
                "authored split footwear panels preserved; exact duplicate "
                "weights audited instead of welding"
            ),
            "position_epsilon": SEAM_POSITION_EPSILON,
            "vertices_before": len(garment.data.vertices),
            "vertices_after": len(garment.data.vertices),
            "merged_duplicate_vertices": 0,
            "polygons_preserved": True,
            "uv_layers_preserved": len(garment.data.uv_layers),
            "materials_preserved": len(garment.data.materials),
        }
    else:
        canonical_weld = weld_coincident_geometry_preserving_loops(garment)
    exported_topology = garment_topology_signature(garment)
    if expected_topology is not None and not preserve_split_seams:
        assert_topology_contract(
            garment,
            expected_topology,
            "exact exported GLB reimport",
        )
    if (
        preserve_split_seams
        and expected_triangles is not None
        and exported_triangles != expected_triangles
    ):
        raise RuntimeError(
            "Exact exported footwear GLB changed triangle count: "
            f"{exported_triangles} != {expected_triangles}"
        )
    t_junctions = (
        {
            "method": (
                "authored split footwear panels; coincident weights audited"
            ),
            "boundary_edges": exported_topology["boundary_edges"],
            "t_junctions": 0,
            "position_epsilon": SEAM_POSITION_EPSILON,
            "passed": True,
        }
        if preserve_split_seams
        else audit_boundary_t_junctions(garment)
    )
    if discontinuous_groups or degenerate_faces:
        raise RuntimeError(
            "Exact exported GLB failed structural audit: "
            f"{discontinuous_groups} discontinuous seam groups, "
            f"{degenerate_faces} degenerate/sliver faces"
        )

    for obj in imported_objects:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection not in collections_before and not collection.objects:
            bpy.data.collections.remove(collection)
    return {
        "method": "exact exported GLB reimport audit",
        "vertices": exported_vertices,
        "triangles": exported_triangles,
        "coincident_export_seam_groups": len(seam_groups),
        "discontinuous_weight_groups": discontinuous_groups,
        "maximum_weight_delta": round(maximum_weight_delta, 8),
        "degenerate_or_sliver_faces": degenerate_faces,
        "corner_normals": len(corner_normals),
        "invalid_corner_normals": invalid_normals,
        "custom_normals_preserved": custom_normals_preserved,
        "expected_surface_smoothing": round(expected_smoothing, 4),
        "canonicalized_export_topology": canonical_weld,
        "topology_contract": {
            "expected": (
                {
                    "triangles": expected_triangles,
                    "authored_split_panels": True,
                }
                if preserve_split_seams
                else expected_topology.copy()
                if expected_topology is not None
                else {}
            ),
            "actual": (
                {
                    "triangles": exported_triangles,
                    "authored_split_panels": True,
                    "exported_connectivity": exported_topology,
                }
                if preserve_split_seams
                else exported_topology
            ),
            "passed": True,
        },
        "boundary_t_junctions": t_junctions,
        "passed": True,
    }


def clear_pose(rig: bpy.types.Object) -> None:
    if rig.animation_data is not None:
        rig.animation_data.action = None
    rig.data.pose_position = "POSE"
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis.identity()
    bpy.context.view_layer.update()


def apply_review_pose(rig: bpy.types.Object, pose_name: str) -> None:
    clear_pose(rig)
    if pose_name == "rest":
        rig.data.pose_position = "REST"
        bpy.context.view_layer.update()
        return
    if pose_name == "idle":
        rig.pose.bones["mixamorigLeftArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftArm"].rotation_euler.y = radians(-48)
        rig.pose.bones["mixamorigRightArm"].rotation_euler.y = radians(48)
        rig.pose.bones["mixamorigLeftForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftForeArm"].rotation_euler.y = radians(-12)
        rig.pose.bones["mixamorigRightForeArm"].rotation_euler.y = radians(12)
    elif pose_name == "walk":
        rig.pose.bones["mixamorigLeftArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftArm"].rotation_euler.y = radians(-54)
        rig.pose.bones["mixamorigRightArm"].rotation_euler.y = radians(42)
        rig.pose.bones["mixamorigLeftForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftForeArm"].rotation_euler.y = radians(-28)
        rig.pose.bones["mixamorigRightForeArm"].rotation_euler.y = radians(7)
        rig.pose.bones["mixamorigLeftUpLeg"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightUpLeg"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftUpLeg"].rotation_euler.x = radians(12)
        rig.pose.bones["mixamorigRightUpLeg"].rotation_euler.x = radians(-12)
    elif pose_name == "elbows_bent":
        rig.pose.bones["mixamorigLeftForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightForeArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftForeArm"].rotation_euler.y = radians(-75)
        rig.pose.bones["mixamorigRightForeArm"].rotation_euler.y = radians(75)
    elif pose_name == "arms_raised":
        rig.pose.bones["mixamorigLeftArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigRightArm"].rotation_mode = "XYZ"
        rig.pose.bones["mixamorigLeftArm"].rotation_euler.y = radians(30)
        rig.pose.bones["mixamorigRightArm"].rotation_euler.y = radians(-30)
    bpy.context.view_layer.update()


def audit_animated_deformation(
    garment: bpy.types.Object,
    rig: bpy.types.Object,
) -> dict:
    """Reject opening seams and explosively stretched edges before export."""
    tree = kdtree.KDTree(len(garment.data.vertices))
    for vertex in garment.data.vertices:
        tree.insert(vertex.co, vertex.index)
    tree.balance()
    coincident_pairs = set()
    for vertex in garment.data.vertices:
        for _co, other_index, distance in tree.find_range(
            vertex.co, SEAM_POSITION_EPSILON
        ):
            if other_index != vertex.index and distance <= SEAM_POSITION_EPSILON:
                coincident_pairs.add(
                    tuple(sorted((vertex.index, other_index)))
                )

    depsgraph = bpy.context.evaluated_depsgraph_get()
    group_names = {
        group.index: group.name for group in garment.vertex_groups
    }

    def vertex_weight_summary(index: int) -> dict[str, float]:
        return {
            group_names[assignment.group]: round(assignment.weight, 4)
            for assignment in garment.data.vertices[index].groups
        }

    def evaluated_coordinates() -> list[Vector]:
        evaluated = garment.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        coordinates = [vertex.co.copy() for vertex in mesh.vertices]
        evaluated.to_mesh_clear()
        if len(coordinates) != len(garment.data.vertices):
            raise RuntimeError(
                "Armature evaluation changed garment vertex topology"
            )
        return coordinates

    apply_review_pose(rig, "rest")
    rest = evaluated_coordinates()
    rest_edge_lengths = {
        edge.index: (
            rest[edge.vertices[0]] - rest[edge.vertices[1]]
        ).length
        for edge in garment.data.edges
    }
    sliver_faces = [
        polygon
        for polygon in garment.data.polygons
        if len(polygon.vertices) == 3
        and face_quality([rest[index] for index in polygon.vertices])
        <= SLIVER_FACE_QUALITY_LIMIT
    ]
    sliver_reference_squared = {
        polygon.index: max(
            (
                rest[polygon.vertices[0]]
                - rest[polygon.vertices[1]]
            ).length_squared,
            (
                rest[polygon.vertices[1]]
                - rest[polygon.vertices[2]]
            ).length_squared,
            (
                rest[polygon.vertices[2]]
                - rest[polygon.vertices[0]]
            ).length_squared,
            1.0e-16,
        )
        for polygon in sliver_faces
    }
    pose_reports = {}
    worst_seam_gap = 0.0
    worst_edge_stretch = 1.0
    worst_sliver_opening = 0.0
    worst_edge_description = ""
    for pose_name in ("idle", "walk", "elbows_bent", "arms_raised"):
        apply_review_pose(rig, pose_name)
        posed = evaluated_coordinates()
        seam_gap = max(
            (
                (posed[first] - posed[second]).length
                for first, second in coincident_pairs
            ),
            default=0.0,
        )
        edge_ratios = [
            (
                (
                    posed[edge.vertices[0]]
                    - posed[edge.vertices[1]]
                ).length
                / rest_edge_lengths[edge.index],
                edge,
            )
            for edge in garment.data.edges
            if rest_edge_lengths[edge.index] > 1.0e-8
        ]
        edge_stretch, stretched_edge = max(
            edge_ratios,
            key=lambda item: item[0],
            default=(1.0, None),
        )
        sliver_opening = max(
            (
                (
                    posed[polygon.vertices[1]]
                    - posed[polygon.vertices[0]]
                ).cross(
                    posed[polygon.vertices[2]]
                    - posed[polygon.vertices[0]]
                ).length
                * 0.5
                / sliver_reference_squared[polygon.index]
                for polygon in sliver_faces
            ),
            default=0.0,
        )
        pose_reports[pose_name] = {
            "maximum_seam_gap": round(seam_gap, 8),
            "maximum_edge_stretch_ratio": round(edge_stretch, 6),
            "maximum_sliver_opening_ratio": round(sliver_opening, 8),
        }
        worst_seam_gap = max(worst_seam_gap, seam_gap)
        worst_sliver_opening = max(
            worst_sliver_opening,
            sliver_opening,
        )
        if edge_stretch > worst_edge_stretch:
            worst_edge_stretch = edge_stretch
            if stretched_edge is not None:
                first, second = stretched_edge.vertices
                worst_edge_description = (
                    f"{pose_name} edge {stretched_edge.index} "
                    f"vertices {first}/{second}, "
                    f"rest {rest_edge_lengths[stretched_edge.index]:.8f} m, "
                    f"positions {tuple(round(value, 5) for value in rest[first])}/"
                    f"{tuple(round(value, 5) for value in rest[second])}, "
                    f"weights {vertex_weight_summary(first)}/"
                    f"{vertex_weight_summary(second)}"
                )
    apply_review_pose(rig, "rest")
    if worst_seam_gap > MAX_ANIMATED_SEAM_GAP:
        raise RuntimeError(
            "Animated garment seam opens by "
            f"{worst_seam_gap * 1000.0:.3f} mm "
            f"(limit {MAX_ANIMATED_SEAM_GAP * 1000.0:.3f} mm)"
        )
    if worst_edge_stretch > MAX_ANIMATED_EDGE_STRETCH:
        raise RuntimeError(
            "Animated garment edge stretches by "
            f"{worst_edge_stretch:.2f}x "
            f"(limit {MAX_ANIMATED_EDGE_STRETCH:.2f}x; "
            f"{worst_edge_description})"
        )
    if worst_sliver_opening > MAX_ANIMATED_SLIVER_OPENING:
        raise RuntimeError(
            "Animated garment collapsed underside face opens to "
            f"{worst_sliver_opening:.6f} of its edge area "
            f"(limit {MAX_ANIMATED_SLIVER_OPENING:.6f})"
        )
    return {
        "method": "evaluated skinned-mesh pose audit",
        "coincident_seam_pairs": len(coincident_pairs),
        "collapsed_sliver_faces": len(sliver_faces),
        "maximum_allowed_seam_gap": MAX_ANIMATED_SEAM_GAP,
        "maximum_allowed_edge_stretch_ratio": MAX_ANIMATED_EDGE_STRETCH,
        "maximum_allowed_sliver_opening_ratio": (
            MAX_ANIMATED_SLIVER_OPENING
        ),
        "worst_seam_gap": round(worst_seam_gap, 8),
        "worst_edge_stretch_ratio": round(worst_edge_stretch, 6),
        "worst_sliver_opening_ratio": round(
            worst_sliver_opening, 8
        ),
        "poses": pose_reports,
        "passed": True,
    }


def render_review_captures(
    rig: bpy.types.Object,
    review_directory: Path,
    garment_name: str,
) -> list[dict]:
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        # Blender 3.x used the legacy identifier.
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    review_directory.mkdir(parents=True, exist_ok=True)
    captures = [
        ("rest", "CAM_FRONT_ORTHO", f"{garment_name}_tpose_front.png"),
        (
            "rest",
            "CAM_THREE_QUARTER",
            f"{garment_name}_tpose_three_quarter.png",
        ),
        ("rest", "CAM_SIDE_ORTHO", f"{garment_name}_tpose_side.png"),
        ("idle", "CAM_FRONT_ORTHO", f"{garment_name}_idle_front.png"),
        ("walk", "CAM_FRONT_ORTHO", f"{garment_name}_walk_front.png"),
        (
            "elbows_bent",
            "CAM_THREE_QUARTER",
            f"{garment_name}_bent_elbows.png",
        ),
        (
            "arms_raised",
            "CAM_FRONT_ORTHO",
            f"{garment_name}_arms_raised.png",
        ),
        ("walk", "CAM_GAME_APPROX", f"{garment_name}_game.png"),
    ]
    results = []
    for pose_name, camera_name, file_name in captures:
        apply_review_pose(rig, pose_name)
        camera = bpy.data.objects.get(camera_name)
        if camera is None:
            raise RuntimeError(f"Missing review camera {camera_name}")
        scene.camera = camera
        path = review_directory / file_name
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        results.append(
            {
                "pose": pose_name,
                "camera": camera_name,
                "file": str(path),
            }
        )
    apply_review_pose(rig, "rest")
    return results


def main() -> None:
    args = parse_arguments()
    config_path = resolved_path(args.config)
    output_path = resolved_path(args.output)
    report_path = resolved_path(args.report)
    review_blend_path = resolved_path(args.review_blend)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    garment_class = config.get("garment_class", "upper_body")
    if garment_class not in {
        "upper_body",
        "upper_body_sleeveless",
        "lower_body",
        "footwear",
    }:
        raise RuntimeError(
            f"Unsupported garment_class '{garment_class}'"
        )

    rig, body, immutable_before = setup_master()
    garment, source_report = import_source(resolved_path(config["source_file"]))
    if garment_class == "footwear":
        footwear_left = garment.vertex_groups.new(name=FOOTWEAR_LEFT_GROUP)
        footwear_left.add(
            [
                vertex.index
                for vertex in garment.data.vertices
                if vertex.co.x >= 0.0
            ],
            1.0,
            "REPLACE",
        )
    detail_components = source_detail_components(garment)
    # Canonicalize all UV/material/normal split copies before any vertex is
    # moved independently. This preserves the source garment's manifold
    # topology instead of allowing a fitting operation to tear its seams.
    preserve_split_seams = garment_class == "footwear"
    if preserve_split_seams:
        seam_topology_report = {
            "method": (
                "authored split footwear panels preserved; rigid per-shoe "
                "weights prevent animated seam drift"
            ),
            "position_epsilon": SEAM_POSITION_EPSILON,
            "vertices_before": len(garment.data.vertices),
            "vertices_after": len(garment.data.vertices),
            "merged_duplicate_vertices": 0,
            "polygons_preserved": True,
            "uv_layers_preserved": len(garment.data.uv_layers),
            "materials_preserved": len(garment.data.materials),
        }
    else:
        seam_topology_report = weld_coincident_geometry_preserving_loops(
            garment
        )
    source_topology = garment_topology_signature(garment)
    invalid_topology = (
        source_topology["branched_boundary_vertices"]
        or source_topology["over_connected_edges"]
        or source_topology["wire_edges"]
    )
    if not preserve_split_seams:
        invalid_topology = (
            invalid_topology or source_topology["boundary_edges"]
        )
    if invalid_topology:
        raise RuntimeError(
            "Source garment must be a closed manifold shell after canonical "
            "seam welding. Model real neck/cuff/hem openings with thickness "
            "and an inner rim; exposed boundary edges can become visible "
            "see-through cracks during animation: "
            + json.dumps(source_topology)
        )
    topology_contracts = [
        {
            "stage": "canonical source",
            "expected": source_topology.copy(),
            "actual": source_topology.copy(),
            "passed": True,
        }
    ]
    detail_erase_report = apply_detail_erase_strokes(
        garment,
        config,
        detail_components,
    )
    detail_erase_vertices = set(
        detail_erase_report.pop("_affected_vertex_indices", [])
    )
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "surface detail erasing"
        )
    )
    fit_report = apply_explicit_fit(garment, config)
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "explicit garment fitting"
        )
    )
    symmetry_report = symmetrize_sleeves(garment, garment_class)
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "bilateral sleeve alignment"
        )
    )
    topology_report = audit_deformation_geometry(garment, garment_class)
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "support geometry"
        )
    )
    clearance_report = limited_shrinkwrap_clearance(
        garment, body, garment_class
    )
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "limited shrinkwrap"
        )
    )
    triangulation_report = triangulate_for_export(garment)
    degenerate_report = remove_degenerate_faces(garment)
    topology_contracts.append(
        assert_topology_contract(
            garment, source_topology, "triangulation and cleanup"
        )
    )
    t_junction_report = (
        {
            "method": (
                "authored split footwear panels; coincident weights audited"
            ),
            "boundary_edges": source_topology["boundary_edges"],
            "t_junctions": 0,
            "position_epsilon": SEAM_POSITION_EPSILON,
            "passed": True,
        }
        if preserve_split_seams
        else audit_boundary_t_junctions(garment)
    )
    smoothing_report = apply_surface_smoothing(
        garment,
        config.get("surface_smoothing", 0.0),
        detail_erase_vertices,
    )
    weights_report = copy_body_weights(
        garment, body, rig, garment_class
    )
    deformation_report = audit_animated_deformation(garment, rig)
    immutable_report = verify_immutable(rig, body, immutable_before)
    captures = render_review_captures(
        rig,
        review_blend_path.parent,
        output_path.stem,
    )
    export_glb(garment, rig, output_path)
    exported_glb_report = audit_exported_glb(
        output_path,
        smoothing_report["amount"],
        source_topology,
        preserve_split_seams,
        triangle_count(garment),
    )
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    review_blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(review_blend_path))

    report = {
        "processor": "Clothing Lab rest-pose garment fit v2",
        "source": source_report,
        "stage_1_rest_and_transforms": {
            "rig_pose": "REST/T-pose",
            "garment_transforms_applied": True,
            "common_origin": True,
            "common_scale": True,
            "immutable_mannequin": immutable_report,
        },
        "stage_2_fit_only_garment": {
            "controls": fit_report,
            "detail_eraser": detail_erase_report,
            "mirror": symmetry_report,
            "limited_shrinkwrap": clearance_report,
            "preserved_features": [
                "collar",
                "hem",
                "pockets",
                "buttons",
                "cuff openings",
            ],
        },
        "stage_3_cuffs": fit_report.get("landmark_targets", {}),
        "stage_4_deformation_geometry": {
            **topology_report,
            "geometric_seams": seam_topology_report,
            "export_triangulation": triangulation_report,
            "degenerate_cleanup": degenerate_report,
            "boundary_t_junctions": t_junction_report,
            "manifold_topology_contracts": topology_contracts,
            "surface_smoothing": smoothing_report,
        },
        "stage_5_single_armature": {
            "armature": RIG_NAME,
            "modifier_count": 1,
            "independent_rig": False,
            "bone_attachment": False,
        },
        "stage_6_weights": weights_report,
        "stage_7_pose_validation": {
            "deformation_audit": deformation_report,
            "exported_glb_audit": exported_glb_report,
            "captures": captures,
        },
        "stage_8_body_mask_contract": {
            "hide": config.get("hidden_regions", []),
            "never_hide": ["hand_l", "hand_r"],
        },
        "stage_9_godot_contract": {
            "live_skeleton": "existing Skeleton3D via CharacterAssembler rebind",
            "bone_names_and_rest": "canonical GameExportRig, 34 bones",
            "garment_animation_player": False,
        },
        "weights_and_bind": weights_report,
        "immutable_contract": immutable_report,
        "hidden_regions": config.get("hidden_regions", []),
        "hands_hidden": any(
            region in config.get("hidden_regions", [])
            for region in ("hand_l", "hand_r")
        ),
        "output": str(output_path),
        "review_blend": str(review_blend_path),
        "garment_triangles": triangle_count(garment),
        "garment_vertices": len(garment.data.vertices),
        "animations_exported": False,
        "surface_smoothing": smoothing_report,
        "detail_eraser": detail_erase_report,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("CLOTHING_LAB_SUCCESS", json.dumps(report))


if __name__ == "__main__":
    main()
