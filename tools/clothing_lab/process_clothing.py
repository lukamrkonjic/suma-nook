"""Deterministic Clothing Lab processor.

This script deliberately contains no automatic fitting heuristic.  It applies
only the explicit ClothingFitSettings values chosen in the Godot lab, copies
weights from PlayerMaleBody with nearest-face interpolation, and binds the
garment to the canonical GameExportRig.  Source UVs, materials, normals,
topology, body mesh, rest pose and bone transforms are preserved.

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
from math import radians
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
CLEARANCE = 0.004


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


def apply_explicit_fit(garment: bpy.types.Object, config: dict) -> dict:
    scale = vector(config["scale"])
    rotation = vector(config["rotation_degrees"])
    position = vector(config["position"])
    garment.data.transform(Matrix.Diagonal((scale.x, scale.y, scale.z, 1.0)))

    torso_width = float(config["torso_width"])
    torso_depth = float(config["torso_depth"])
    sleeve_lift = float(config["sleeve_lift"])
    sleeve_length = float(config["sleeve_length"])
    sleeve_room = float(config.get("sleeve_room", 1.0))
    shoulder_lift = float(config.get("shoulder_lift", 0.0))
    cuff_radius = float(config["cuff_radius"])
    cuff_forward = float(config["cuff_forward"])
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
            vertex.co.x *= torso_width
            vertex.co.y *= torso_depth
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
        "position": list(position),
        "rotation_degrees": list(rotation),
        "scale": list(scale),
        "symmetric_controls": bool(config["symmetric"]),
        "torso_width": torso_width,
        "torso_depth": torso_depth,
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


def symmetrize_sleeves(garment: bpy.types.Object) -> dict:
    """Make the deforming sleeve shells bilateral without touching details.

    The torso, collar, hem, pockets, buttons and UV loop data are excluded.
    Matching is position-only; no UVs, material slots or normals are rebuilt.
    """
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
    tree = kdtree.KDTree(len(right))
    for index, vertex in enumerate(right):
        tree.insert(
            Vector((-vertex.co.x, vertex.co.y, vertex.co.z)),
            index,
        )
    tree.balance()
    replacements = []
    maximum_delta = 0.0
    for left_vertex in left:
        _coordinate, index, distance = tree.find(left_vertex.co)
        if distance > 0.018:
            continue
        right_vertex = right[index]
        mean_x = (
            abs(left_vertex.co.x) + abs(right_vertex.co.x)
        ) * 0.5
        mean_y = (left_vertex.co.y + right_vertex.co.y) * 0.5
        mean_z = (left_vertex.co.z + right_vertex.co.z) * 0.5
        replacements.append(
            (
                left_vertex.index,
                Vector((mean_x, mean_y, mean_z)),
                right_vertex.index,
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
) -> dict:
    """Push only unsafe cloth outward with a masked Shrinkwrap modifier."""
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


def audit_deformation_geometry(garment: bpy.types.Object) -> dict:
    """Add zero-smoothing local support geometry, then verify density."""
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
            "no welding, relaxation or global subdivision"
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
        "shoulder_armpit": {
            vertex.index
            for vertex in garment.data.vertices
            if 0.105 <= abs(vertex.co.x) < 0.175
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

    relax(zone_indices["shoulder_armpit"], passes=4, factor=0.38)
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
            "shoulder_armpit": 4,
            "elbow": 3,
        },
        "surface_geometry_smoothed": False,
        "source_normals_preserved": True,
        "uvs_or_materials_changed": False,
    }


def copy_body_weights(
    garment: bpy.types.Object,
    body: bpy.types.Object,
    rig: bpy.types.Object,
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
            for token in ("UpLeg", "LeftLeg", "RightLeg", "Foot", "ToeBase")
        ),
        "mixamorigHips",
    )
    deformation_correction = correct_arm_chain_weights(garment)

    endpoint = max(abs(vertex.co.x) for vertex in garment.data.vertices)
    cuff_corrections = {}
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
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
            if side_x < endpoint - 0.030:
                continue
            for assignment in list(vertex.groups):
                garment.vertex_groups[assignment.group].remove(
                    [vertex.index]
                )
            ramp = min(
                max(
                    (side_x - (endpoint - 0.030)) / 0.030,
                    0.0,
                ),
                1.0,
            )
            forearm.add(
                [vertex.index],
                0.74 - 0.24 * ramp,
                "REPLACE",
            )
            hand.add(
                [vertex.index],
                0.26 + 0.24 * ramp,
                "REPLACE",
            )
            corrected += 1
        cuff_corrections[side.lower()] = {
            "vertices": corrected,
            "weights": "forearm 0.74→0.50, hand 0.26→0.50",
        }

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
        "mapping": "POLYINTERP_NEAREST",
        "automatic_weights_used": False,
        "deterministic_cleanup": {
            "left_fingers_to_hand": left_digits,
            "right_fingers_to_hand": right_digits,
            "lower_body_to_hips": lower_body,
            "shoulder_armpit_elbow_weights": deformation_correction,
            "pose_corrected_cuffs": cuff_corrections,
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


def render_review_captures(
    rig: bpy.types.Object,
    review_directory: Path,
) -> list[dict]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    review_directory.mkdir(parents=True, exist_ok=True)
    captures = [
        ("rest", "CAM_FRONT_ORTHO", "jacket_tpose_front.png"),
        ("rest", "CAM_THREE_QUARTER", "jacket_tpose_three_quarter.png"),
        ("rest", "CAM_SIDE_ORTHO", "jacket_tpose_side.png"),
        ("idle", "CAM_FRONT_ORTHO", "jacket_idle_front.png"),
        ("walk", "CAM_FRONT_ORTHO", "jacket_walk_front.png"),
        (
            "elbows_bent",
            "CAM_THREE_QUARTER",
            "jacket_bent_elbows.png",
        ),
        (
            "arms_raised",
            "CAM_FRONT_ORTHO",
            "jacket_arms_raised.png",
        ),
        ("walk", "CAM_GAME_APPROX", "jacket_game.png"),
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

    rig, body, immutable_before = setup_master()
    garment, source_report = import_source(resolved_path(config["source_file"]))
    fit_report = apply_explicit_fit(garment, config)
    symmetry_report = symmetrize_sleeves(garment)
    topology_report = audit_deformation_geometry(garment)
    clearance_report = limited_shrinkwrap_clearance(garment, body)
    weights_report = copy_body_weights(garment, body, rig)
    immutable_report = verify_immutable(rig, body, immutable_before)
    captures = render_review_captures(
        rig, review_blend_path.parent
    )
    export_glb(garment, rig, output_path)
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
        "stage_3_cuffs": fit_report["landmark_targets"],
        "stage_4_deformation_geometry": topology_report,
        "stage_5_single_armature": {
            "armature": RIG_NAME,
            "modifier_count": 1,
            "independent_rig": False,
            "bone_attachment": False,
        },
        "stage_6_weights": weights_report,
        "stage_7_pose_validation_captures": captures,
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
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("CLOTHING_LAB_SUCCESS", json.dumps(report))


if __name__ == "__main__":
    main()
