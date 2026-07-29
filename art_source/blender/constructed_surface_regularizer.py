"""Feature-preserving cleanup for AI-generated constructed surface meshes.

This module is intentionally not a remesher. It keeps the source vertices,
faces, connectivity, panel count, gaps, and authored depth. It only regularizes
features that should read as manufactured:

* detect large, upward-facing connected patches;
* fit each patch to a stable horizontal plane;
* infer the mesh's dominant pair of perpendicular construction axes;
* project noisy patch boundaries onto four straight side lines;
* propagate those small XY corrections into nearby wall/groove vertices;
* keep every polygon flat-shaded.

The processor using this module chooses tolerances per asset and records the
resulting report. Organic surfaces should not use this pass.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import math
from statistics import median
from typing import Iterable

import bpy
from mathutils import Vector


@dataclass(frozen=True)
class ConstructedRegularizationConfig:
    """Scale-relative controls for a constructed top.

    `top_normal_min` separates near-horizontal panel faces from bevels/walls.
    `min_patch_area_ratio` rejects small upward-facing groove floors and noise.
    `wall_propagation_ratio` controls how far a boundary correction may travel
    through nearby non-top vertices, relative to the larger XY footprint.
    """

    top_normal_min: float = 0.90
    min_patch_area_ratio: float = 0.02
    top_patch_max_drop_ratio: float = 0.35
    max_top_patches: int | None = None
    wall_propagation_ratio: float = 0.06
    dominant_axis_override_degrees: float | None = None
    flatten_top_patches: bool = True
    align_patch_heights: bool = True
    straighten_patch_boundaries: bool = True
    rebuild_side_walls: bool = False
    force_flat_shading: bool = True


def _edge_key(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _connected_face_patches(
    mesh: bpy.types.Mesh,
    candidate_faces: set[int],
) -> list[set[int]]:
    edge_faces: dict[tuple[int, int], list[int]] = {}
    for face_index in candidate_faces:
        polygon = mesh.polygons[face_index]
        vertices = list(polygon.vertices)
        for index, vertex_a in enumerate(vertices):
            vertex_b = vertices[(index + 1) % len(vertices)]
            edge_faces.setdefault(_edge_key(vertex_a, vertex_b), []).append(
                face_index
            )

    adjacency: dict[int, set[int]] = {
        face_index: set() for face_index in candidate_faces
    }
    for faces in edge_faces.values():
        if len(faces) != 2:
            continue
        a, b = faces
        adjacency[a].add(b)
        adjacency[b].add(a)

    remaining = set(candidate_faces)
    patches: list[set[int]] = []
    while remaining:
        start = remaining.pop()
        patch = {start}
        stack = [start]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    patch.add(neighbor)
                    stack.append(neighbor)
        patches.append(patch)
    return patches


def _patch_vertices(
    mesh: bpy.types.Mesh,
    patch: Iterable[int],
) -> set[int]:
    result: set[int] = set()
    for face_index in patch:
        result.update(mesh.polygons[face_index].vertices)
    return result


def _patch_boundary_edges(
    mesh: bpy.types.Mesh,
    patch: set[int],
) -> list[tuple[int, int]]:
    use_count: dict[tuple[int, int], int] = {}
    for face_index in patch:
        vertices = list(mesh.polygons[face_index].vertices)
        for index, vertex_a in enumerate(vertices):
            vertex_b = vertices[(index + 1) % len(vertices)]
            key = _edge_key(vertex_a, vertex_b)
            use_count[key] = use_count.get(key, 0) + 1
    return [edge for edge, count in use_count.items() if count == 1]


def _ordered_boundary_loops(
    boundary_edges: list[tuple[int, int]],
) -> list[list[int]]:
    adjacency: dict[int, list[int]] = {}
    unused: set[tuple[int, int]] = set()
    for vertex_a, vertex_b in boundary_edges:
        adjacency.setdefault(vertex_a, []).append(vertex_b)
        adjacency.setdefault(vertex_b, []).append(vertex_a)
        unused.add(_edge_key(vertex_a, vertex_b))

    loops: list[list[int]] = []
    while unused:
        first_edge = next(iter(unused))
        start, current = first_edge
        previous = start
        loop = [start, current]
        unused.remove(first_edge)
        while current != start:
            choices = [
                neighbor
                for neighbor in adjacency.get(current, [])
                if _edge_key(current, neighbor) in unused
            ]
            if not choices:
                break
            next_vertex = next(
                (neighbor for neighbor in choices if neighbor != previous),
                choices[0],
            )
            unused.remove(_edge_key(current, next_vertex))
            previous, current = current, next_vertex
            if current != start:
                loop.append(current)
        if current == start and len(loop) >= 3:
            loops.append(loop)
    return loops


def _signed_loop_area(mesh: bpy.types.Mesh, loop: list[int]) -> float:
    area = 0.0
    for index, vertex_index in enumerate(loop):
        point = mesh.vertices[vertex_index].co
        next_point = mesh.vertices[loop[(index + 1) % len(loop)]].co
        area += point.x * next_point.y - next_point.x * point.y
    return area * 0.5


def _rebuild_top_patches_with_clean_walls(
    obj: bpy.types.Object,
    patches: list[set[int]],
    patch_boundaries: list[list[tuple[int, int]]],
    wall_bottom_z: float,
) -> dict:
    """Keep source top faces and replace only their noisy side bands."""

    source_mesh = obj.data
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    wall_face_count = 0
    boundary_loop_count = 0

    for patch, boundary_edges in zip(patches, patch_boundaries):
        patch_vertices = sorted(_patch_vertices(source_mesh, patch))
        vertex_map: dict[int, int] = {}
        for source_index in patch_vertices:
            vertex_map[source_index] = len(vertices)
            vertices.append(tuple(source_mesh.vertices[source_index].co))
        for face_index in sorted(patch):
            faces.append(
                tuple(
                    vertex_map[source_index]
                    for source_index in source_mesh.polygons[face_index].vertices
                )
            )

        for loop in _ordered_boundary_loops(boundary_edges):
            if _signed_loop_area(source_mesh, loop) < 0.0:
                loop.reverse()
            boundary_loop_count += 1
            bottom_loop: list[int] = []
            for source_index in loop:
                point = source_mesh.vertices[source_index].co
                bottom_loop.append(len(vertices))
                vertices.append((point.x, point.y, wall_bottom_z))
            for index, source_index in enumerate(loop):
                next_index = (index + 1) % len(loop)
                top_a = vertex_map[source_index]
                top_b = vertex_map[loop[next_index]]
                bottom_a = bottom_loop[index]
                bottom_b = bottom_loop[next_index]
                faces.append((top_a, bottom_a, bottom_b, top_b))
                wall_face_count += 1

    replacement = bpy.data.meshes.new(source_mesh.name + "_regularized")
    replacement.from_pydata(vertices, [], faces)
    replacement.update()
    obj.data = replacement
    bpy.data.meshes.remove(source_mesh)
    return {
        "scope": "source_top_faces_plus_rebuilt_boundary_walls",
        "top_faces_preserved": sum(len(patch) for patch in patches),
        "boundary_loops": boundary_loop_count,
        "clean_wall_faces_generated": wall_face_count,
        "output_vertices": len(replacement.vertices),
        "output_polygons": len(replacement.polygons),
    }


def _dominant_rectilinear_angle(
    mesh: bpy.types.Mesh,
    boundary_edges: Iterable[tuple[int, int]],
) -> float:
    """Return the dominant construction angle, modulo 90 degrees.

    The four-angle circular mean makes horizontal and vertical edges vote for
    the same axis family. Long straight segments outweigh short noisy arcs.
    """

    sin_sum = 0.0
    cos_sum = 0.0
    for vertex_a, vertex_b in boundary_edges:
        a = mesh.vertices[vertex_a].co
        b = mesh.vertices[vertex_b].co
        dx = b.x - a.x
        dy = b.y - a.y
        length = math.hypot(dx, dy)
        if length <= 1.0e-8:
            continue
        angle = math.atan2(dy, dx)
        sin_sum += math.sin(angle * 4.0) * length
        cos_sum += math.cos(angle * 4.0) * length
    if abs(sin_sum) + abs(cos_sum) <= 1.0e-8:
        return 0.0
    return math.atan2(sin_sum, cos_sum) * 0.25


def _project(point: Vector, axis: Vector) -> float:
    return point.x * axis.x + point.y * axis.y


def _xy_from_axes(u_value: float, v_value: float, u: Vector, v: Vector) -> Vector:
    return Vector(
        (
            u.x * u_value + v.x * v_value,
            u.y * u_value + v.y * v_value,
        )
    )


def regularize_constructed_surface(
    obj: bpy.types.Object,
    config: ConstructedRegularizationConfig,
) -> dict:
    """Regularize manufactured planes/edges without changing topology."""

    if obj.type != "MESH":
        raise TypeError("Constructed regularization requires a mesh object")
    mesh = obj.data
    mesh.update()

    footprint_x = max(vertex.co.x for vertex in mesh.vertices) - min(
        vertex.co.x for vertex in mesh.vertices
    )
    footprint_y = max(vertex.co.y for vertex in mesh.vertices) - min(
        vertex.co.y for vertex in mesh.vertices
    )
    footprint = max(footprint_x, footprint_y)
    if footprint <= 1.0e-8:
        raise RuntimeError("Constructed mesh has a degenerate XY footprint")

    candidates = {
        polygon.index
        for polygon in mesh.polygons
        if polygon.normal.z >= config.top_normal_min
    }
    if not candidates:
        raise RuntimeError(
            "Constructed regularization found no upward-facing top patches"
        )
    candidate_area = sum(mesh.polygons[index].area for index in candidates)
    minimum_area = candidate_area * config.min_patch_area_ratio
    mesh_z_min = min(vertex.co.z for vertex in mesh.vertices)
    mesh_z_max = max(vertex.co.z for vertex in mesh.vertices)
    mesh_depth = mesh_z_max - mesh_z_min
    minimum_patch_height = (
        mesh_z_max - mesh_depth * config.top_patch_max_drop_ratio
    )
    patches = []
    for patch in _connected_face_patches(mesh, candidates):
        if sum(mesh.polygons[index].area for index in patch) < minimum_area:
            continue
        patch_height = median(
            mesh.vertices[index].co.z
            for index in _patch_vertices(mesh, patch)
        )
        if patch_height < minimum_patch_height:
            continue
        patches.append(patch)
    if not patches:
        raise RuntimeError(
            "Constructed regularization rejected every top patch as noise"
        )
    patches.sort(
        key=lambda patch: sum(mesh.polygons[index].area for index in patch),
        reverse=True,
    )
    if config.max_top_patches is not None:
        patches = patches[:config.max_top_patches]
    patch_vertex_sets = [_patch_vertices(mesh, patch) for patch in patches]
    aligned_top_z = (
        median(
            mesh.vertices[index].co.z
            for vertices in patch_vertex_sets
            for index in vertices
        )
        if config.align_patch_heights
        else None
    )

    patch_boundaries = [
        _patch_boundary_edges(mesh, patch) for patch in patches
    ]
    all_boundary_edges = [
        edge for boundary in patch_boundaries for edge in boundary
    ]
    dominant_angle = _dominant_rectilinear_angle(mesh, all_boundary_edges)
    if config.dominant_axis_override_degrees is not None:
        dominant_angle = math.radians(config.dominant_axis_override_degrees)
    u_axis = Vector((math.cos(dominant_angle), math.sin(dominant_angle)))
    v_axis = Vector((-math.sin(dominant_angle), math.cos(dominant_angle)))

    original_xy = {
        vertex.index: Vector((vertex.co.x, vertex.co.y))
        for vertex in mesh.vertices
    }
    original_points = [
        Vector((point.x, point.y, 0.0)) for point in original_xy.values()
    ]
    global_u_values = [_project(point, u_axis) for point in original_points]
    global_v_values = [_project(point, v_axis) for point in original_points]
    global_frame = (
        min(global_u_values),
        max(global_u_values),
        min(global_v_values),
        max(global_v_values),
    )
    top_vertices: set[int] = set()
    patch_frames: list[tuple[float, float, float, float]] = []
    patch_reports: list[dict] = []

    for patch_index, patch in enumerate(patches):
        vertices = patch_vertex_sets[patch_index]
        top_vertices.update(vertices)
        boundary_edges = patch_boundaries[patch_index]
        boundary_vertices = {
            vertex_index
            for edge in boundary_edges
            for vertex_index in edge
        }
        if len(boundary_vertices) < 4:
            continue

        z_before = [mesh.vertices[index].co.z for index in vertices]
        target_z = (
            aligned_top_z
            if aligned_top_z is not None
            else median(z_before)
        )
        if config.flatten_top_patches:
            for vertex_index in vertices:
                mesh.vertices[vertex_index].co.z = target_z

        boundary_points = [
            mesh.vertices[index].co.copy() for index in boundary_vertices
        ]
        u_values = [_project(point, u_axis) for point in boundary_points]
        v_values = [_project(point, v_axis) for point in boundary_points]
        u_min, u_max = min(u_values), max(u_values)
        v_min, v_max = min(v_values), max(v_values)
        patch_frames.append((u_min, u_max, v_min, v_max))

        displacement_values: list[float] = []
        residual_before: list[float] = []
        for vertex_index in boundary_vertices:
            point = mesh.vertices[vertex_index].co
            u_value = _project(point, u_axis)
            v_value = _project(point, v_axis)
            distances = [
                abs(u_value - u_min),
                abs(u_value - u_max),
                abs(v_value - v_min),
                abs(v_value - v_max),
            ]
            residual_before.append(min(distances))
            if config.straighten_patch_boundaries:
                closest_side = min(range(4), key=distances.__getitem__)
                if closest_side == 0:
                    u_value = u_min
                elif closest_side == 1:
                    u_value = u_max
                elif closest_side == 2:
                    v_value = v_min
                else:
                    v_value = v_max
                target_xy = _xy_from_axes(
                    u_value, v_value, u_axis, v_axis
                )
                source_xy = original_xy[vertex_index]
                delta = target_xy - source_xy
                mesh.vertices[vertex_index].co.x = target_xy.x
                mesh.vertices[vertex_index].co.y = target_xy.y
                displacement_values.append(delta.length)

        patch_reports.append(
            {
                "patch": patch_index,
                "faces": len(patch),
                "vertices": len(vertices),
                "boundary_edges": len(boundary_edges),
                "boundary_vertices": len(boundary_vertices),
                "area": round(
                    sum(mesh.polygons[index].area for index in patch), 6
                ),
                "top_height_span_before": round(max(z_before) - min(z_before), 6),
                "top_height_span_after": 0.0
                if config.flatten_top_patches
                else round(max(z_before) - min(z_before), 6),
                "boundary_residual_before_mean": round(
                    sum(residual_before) / len(residual_before), 6
                ),
                "boundary_displacement_mean": round(
                    sum(displacement_values) / len(displacement_values), 6
                )
                if displacement_values
                else 0.0,
                "boundary_displacement_max": round(
                    max(displacement_values), 6
                )
                if displacement_values
                else 0.0,
            }
        )

    moved_vertices_before_wall_rebuild = sum(
        1
        for vertex in mesh.vertices
        if (
            Vector((vertex.co.x, vertex.co.y)) - original_xy[vertex.index]
        ).length > 1.0e-8
    )
    propagated_vertices = 0
    outer_wall_vertices = 0
    propagation_limit = footprint * config.wall_propagation_ratio
    wall_rebuild_report: dict | None = None
    if config.rebuild_side_walls:
        wall_rebuild_report = _rebuild_top_patches_with_clean_walls(
            obj,
            patches,
            patch_boundaries,
            min(vertex.co.z for vertex in mesh.vertices),
        )
        mesh = obj.data
    elif patch_frames and propagation_limit > 0.0:
        for vertex in mesh.vertices:
            if vertex.index in top_vertices:
                continue
            source_xy = original_xy[vertex.index]
            source_3d = Vector((source_xy.x, source_xy.y, 0.0))
            source_u = _project(source_3d, u_axis)
            source_v = _project(source_3d, v_axis)
            best_target: Vector | None = None
            best_distance = math.inf
            global_u_min, global_u_max, global_v_min, global_v_max = global_frame
            global_distances = [
                abs(source_u - global_u_min),
                abs(source_u - global_u_max),
                abs(source_v - global_v_min),
                abs(source_v - global_v_max),
            ]
            global_side = min(range(4), key=global_distances.__getitem__)
            if global_distances[global_side] <= propagation_limit:
                target_u = source_u
                target_v = source_v
                if global_side == 0:
                    target_u = global_u_min
                elif global_side == 1:
                    target_u = global_u_max
                elif global_side == 2:
                    target_v = global_v_min
                else:
                    target_v = global_v_max
                best_target = _xy_from_axes(
                    target_u, target_v, u_axis, v_axis
                )
                best_distance = global_distances[global_side]
                outer_wall_vertices += 1
            for u_min, u_max, v_min, v_max in patch_frames:
                # Global perimeter vertices belong to the one shared outer
                # wall. Never let an individual panel frame pull them inward.
                if best_target is not None:
                    break
                if (
                    source_u < u_min - propagation_limit
                    or source_u > u_max + propagation_limit
                    or source_v < v_min - propagation_limit
                    or source_v > v_max + propagation_limit
                ):
                    continue
                distances = [
                    abs(source_u - u_min),
                    abs(source_u - u_max),
                    abs(source_v - v_min),
                    abs(source_v - v_max),
                ]
                side = min(range(4), key=distances.__getitem__)
                distance = distances[side]
                if distance > propagation_limit or distance >= best_distance:
                    continue
                target_u = source_u
                target_v = source_v
                if side == 0:
                    target_u = u_min
                elif side == 1:
                    target_u = u_max
                elif side == 2:
                    target_v = v_min
                else:
                    target_v = v_max
                best_target = _xy_from_axes(
                    target_u, target_v, u_axis, v_axis
                )
                best_distance = distance
            if best_target is not None:
                vertex.co.x = best_target.x
                vertex.co.y = best_target.y
                propagated_vertices += 1

    if config.force_flat_shading:
        for polygon in mesh.polygons:
            polygon.use_smooth = False
    mesh.update()
    bpy.context.view_layer.update()

    return {
        "method": "plane_and_boundary_constrained",
        "config": asdict(config),
        "dominant_axis_degrees": round(math.degrees(dominant_angle), 4),
        "candidate_top_faces": len(candidates),
        "accepted_top_patches": len(patches),
        "patches": patch_reports,
        "xy_vertices_moved": moved_vertices_before_wall_rebuild,
        "wall_or_groove_vertices_propagated": propagated_vertices,
        "outer_wall_vertices_regularized": outer_wall_vertices,
        "boundary_wall_rebuild": wall_rebuild_report,
        "output_vertex_count": len(mesh.vertices),
        "output_polygon_count": len(mesh.polygons),
        "smooth_polygons_after": sum(
            1 for polygon in mesh.polygons if polygon.use_smooth
        ),
        "topology_changed": config.rebuild_side_walls,
        "shading_smoothing_applied": False,
    }
