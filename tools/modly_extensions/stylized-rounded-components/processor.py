#!/usr/bin/env python3
"""Modly mesh-to-mesh process: Stylized Rounded Components.

The process accepts one trimesh-compatible file and emits a GLB. It preserves
the input coordinate space, origin, orientation, and scale. Rounded Box
Reconstruction replaces component surface noise with deterministic bevelled
cuboids. Smooth Existing regularizes and Taubin-smooths components separately
so neighboring gaps cannot collapse.
"""
from __future__ import annotations

import json
import math
import os
import signal
import sys
import tempfile
import time
import traceback
from pathlib import Path
from typing import Iterable

import numpy as np
import trimesh

from _ipc import done, error, log, parse_bool, progress


SUPPORTED_EXTENSIONS = {".glb", ".gltf", ".obj", ".ply", ".stl"}
PRESET_NAMES = {
    "soft_stone_wall",
    "smooth_generated_mesh",
    "chunky_low_poly",
}
_CANCELLED = False


class ProcessingCancelled(RuntimeError):
    """Raised between safe processing stages after Modly cancels the job."""


def _mark_cancelled(_signum: int, _frame: object) -> None:
    global _CANCELLED
    _CANCELLED = True


for _signal_name in ("SIGINT", "SIGTERM", "SIGBREAK"):
    if hasattr(signal, _signal_name):
        signal.signal(getattr(signal, _signal_name), _mark_cancelled)


def check_cancelled() -> None:
    if _CANCELLED:
        raise ProcessingCancelled("Processing cancelled.")


def clamp(value: float, low: float, high: float) -> float:
    return min(high, max(low, value))


def smoothstep(edge_a: float, edge_b: float, value: float) -> float:
    if edge_b <= edge_a:
        return float(value >= edge_b)
    t = clamp((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def safe_update_faces(mesh: trimesh.Trimesh, mask: np.ndarray) -> None:
    if len(mask) == len(mesh.faces):
        mesh.update_faces(mask)


def load_input_mesh(file_path: Path) -> tuple[
    trimesh.Trimesh,
    object | None,
    int,
]:
    try:
        scene = trimesh.load(file_path, force="scene", process=False)
    except Exception as exc:
        raise RuntimeError(f'Could not load mesh "{file_path}": {exc}') from exc
    if not isinstance(scene, trimesh.Scene) or not scene.geometry:
        raise RuntimeError(f'No triangle geometry found in "{file_path}".')

    transformed_meshes: list[trimesh.Trimesh] = []
    first_material: object | None = None
    for node_name in scene.graph.nodes_geometry:
        check_cancelled()
        transform, geometry_name = scene.graph[node_name]
        source = scene.geometry[geometry_name]
        if not isinstance(source, trimesh.Trimesh) or len(source.faces) == 0:
            continue
        instance = source.copy()
        instance.apply_transform(transform)
        transformed_meshes.append(instance)
        material = getattr(instance.visual, "material", None)
        if first_material is None and material is not None:
            first_material = material
    if not transformed_meshes:
        raise RuntimeError(f'No usable triangular surfaces found in "{file_path}".')

    combined = (
        transformed_meshes[0]
        if len(transformed_meshes) == 1
        else trimesh.util.concatenate(transformed_meshes)
    )
    raw_component_count = len(combined.split(only_watertight=False))
    return combined, first_material, raw_component_count


def repair_mesh(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    repaired = mesh.copy()
    if len(repaired.vertices) == 0 or len(repaired.faces) == 0:
        raise RuntimeError("The input mesh is empty.")
    if not np.isfinite(repaired.vertices).all():
        raise RuntimeError("The input mesh contains non-finite vertices.")

    # Welding reconnects UV/normal seam duplicates before topology analysis.
    repaired.merge_vertices(merge_tex=True, merge_norm=True)
    try:
        safe_update_faces(repaired, repaired.unique_faces())
    except Exception as exc:
        log(f"Duplicate-face repair skipped safely: {exc}")
    try:
        safe_update_faces(repaired, repaired.nondegenerate_faces())
    except Exception as exc:
        log(f"Degenerate-face repair skipped safely: {exc}")
    repaired.remove_unreferenced_vertices()
    try:
        trimesh.repair.fix_winding(repaired)
        trimesh.repair.fix_normals(repaired, multibody=True)
        trimesh.repair.fix_inversion(repaired, multibody=True)
    except Exception as exc:
        log(f"Normal/winding repair was only partially applicable: {exc}")
    return repaired


def mesh_from_face_group(
    mesh: trimesh.Trimesh,
    face_indices: np.ndarray,
) -> trimesh.Trimesh:
    result = mesh.submesh(
        [np.asarray(face_indices, dtype=np.int64)],
        append=True,
        repair=False,
    )
    if not isinstance(result, trimesh.Trimesh):
        raise RuntimeError("Failed to extract a segmented component.")
    result.remove_unreferenced_vertices()
    return result


def split_at_concave_seams(
    component: trimesh.Trimesh,
    concave_angle_degrees: float = 15.0,
) -> list[trimesh.Trimesh]:
    """Split fused rounded assemblies across pronounced concave seams.

    AI wall generators frequently weld touching stones into one connected
    manifold. Convex surface edges remain inside a stone; only sufficiently
    concave edges are cut. This is a conservative fallback after ordinary
    connected-component splitting, not a high-frequency clustering pass.
    """
    if len(component.faces) < 16 or len(component.face_adjacency) == 0:
        return [component]
    adjacency = component.face_adjacency
    angles = component.face_adjacency_angles
    convex = component.face_adjacency_convex
    keep = convex | (angles < math.radians(concave_angle_degrees))
    groups = trimesh.graph.connected_components(
        adjacency[keep],
        nodes=np.arange(len(component.faces)),
        min_len=1,
    )
    if len(groups) <= 1:
        return [component]
    return [
        mesh_from_face_group(component, np.asarray(group))
        for group in groups
    ]


def semantic_components(
    repaired: trimesh.Trimesh,
) -> tuple[list[trimesh.Trimesh], int]:
    connected = list(repaired.split(only_watertight=False))
    semantic: list[trimesh.Trimesh] = []
    for component in connected:
        check_cancelled()
        semantic.extend(split_at_concave_seams(component))
    return semantic, len(connected)


def component_bbox_volume(component: trimesh.Trimesh) -> float:
    extents = np.maximum(np.asarray(component.extents, dtype=float), 0.0)
    return float(np.prod(extents))


def filter_fragments(
    components: list[trimesh.Trimesh],
    remove_small_fragments: bool,
    minimum_relative_volume: float,
) -> tuple[list[trimesh.Trimesh], int]:
    if not components:
        return [], 0
    volumes = np.asarray(
        [component_bbox_volume(item) for item in components],
        dtype=float,
    )
    largest = float(volumes.max(initial=0.0))
    if not remove_small_fragments or largest <= 0.0:
        return components, 0
    threshold = largest * clamp(minimum_relative_volume, 0.0, 1.0)
    kept = [
        component for component, volume in zip(components, volumes)
        if volume >= threshold and len(component.faces) >= 4
    ]
    return kept, len(components) - len(kept)


def pca_frame(
    component: trimesh.Trimesh,
) -> tuple[np.ndarray, np.ndarray]:
    points = np.asarray(component.vertices, dtype=float)
    center = np.asarray(component.bounds, dtype=float).mean(axis=0)
    centered = points - points.mean(axis=0)
    covariance = np.cov(centered, rowvar=False)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    axes = eigenvectors[:, np.argsort(eigenvalues)[::-1]]
    if np.linalg.det(axes) < 0.0:
        axes[:, 2] *= -1.0
    return center, axes


def robust_dimensions(
    component: trimesh.Trimesh,
    center: np.ndarray,
    axes: np.ndarray,
    upper_percentile: float,
    absolute_floor: float,
) -> np.ndarray:
    points = np.asarray(component.vertices, dtype=float)
    projected = (points - center) @ axes
    upper = clamp(upper_percentile, 50.5, 100.0)
    lower = 100.0 - upper
    low = np.percentile(projected, lower, axis=0)
    high = np.percentile(projected, upper, axis=0)
    dimensions = np.maximum(high - low, absolute_floor)
    return dimensions


class MeshBuilder:
    """Indexed triangle builder that welds analytic patch boundaries."""

    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, int, int]] = []
        self._indices: dict[tuple[float, float, float], int] = {}

    def vertex(self, point: Iterable[float]) -> int:
        value = tuple(float(item) for item in point)
        key = tuple(round(item, 10) for item in value)
        if key not in self._indices:
            self._indices[key] = len(self.vertices)
            self.vertices.append(value)
        return self._indices[key]

    def triangle(
        self,
        a: Iterable[float],
        b: Iterable[float],
        c: Iterable[float],
    ) -> None:
        self.faces.append((self.vertex(a), self.vertex(b), self.vertex(c)))

    def quad(
        self,
        a: Iterable[float],
        b: Iterable[float],
        c: Iterable[float],
        d: Iterable[float],
    ) -> None:
        self.triangle(a, b, c)
        self.triangle(a, c, d)


def rounded_box_local(
    dimensions: np.ndarray,
    bevel_radius: float,
    bevel_segments: int,
) -> trimesh.Trimesh:
    half = np.asarray(dimensions, dtype=float) * 0.5
    radius = clamp(
        float(bevel_radius),
        0.0,
        float(np.min(half)) * 0.94,
    )
    inner = np.maximum(half - radius, 0.0)
    segments = max(1, int(bevel_segments))
    builder = MeshBuilder()

    # Six broad planar faces.
    for fixed_axis in range(3):
        other = [axis for axis in range(3) if axis != fixed_axis]
        for fixed_sign in (-1.0, 1.0):
            points = []
            for sign_a, sign_b in (
                (-1.0, -1.0),
                (1.0, -1.0),
                (1.0, 1.0),
                (-1.0, 1.0),
            ):
                point = np.zeros(3, dtype=float)
                point[fixed_axis] = fixed_sign * half[fixed_axis]
                point[other[0]] = sign_a * inner[other[0]]
                point[other[1]] = sign_b * inner[other[1]]
                points.append(point)
            builder.quad(*points)

    # Twelve quarter-cylinder edge strips. The angular samples deliberately
    # match the barycentric corner patch boundary samples below.
    axis_pairs = ((0, 1), (0, 2), (1, 2))
    for axis_a, axis_b in axis_pairs:
        remaining_axis = next(
            axis for axis in range(3)
            if axis not in (axis_a, axis_b)
        )
        for sign_a in (-1.0, 1.0):
            for sign_b in (-1.0, 1.0):
                strip: list[tuple[np.ndarray, np.ndarray]] = []
                for step in range(segments + 1):
                    angle = math.atan2(step, segments - step)
                    offset_a = math.cos(angle) * radius
                    offset_b = math.sin(angle) * radius
                    pair = []
                    for end_sign in (-1.0, 1.0):
                        point = np.zeros(3, dtype=float)
                        point[axis_a] = sign_a * (
                            inner[axis_a] + offset_a
                        )
                        point[axis_b] = sign_b * (
                            inner[axis_b] + offset_b
                        )
                        point[remaining_axis] = (
                            end_sign * inner[remaining_axis]
                        )
                        pair.append(point)
                    strip.append((pair[0], pair[1]))
                for step in range(segments):
                    builder.quad(
                        strip[step][0],
                        strip[step + 1][0],
                        strip[step + 1][1],
                        strip[step][1],
                    )

    # Eight spherical-octant corner patches, each a normalized barycentric
    # triangular grid. No voxel stair steps and no random surface dents.
    for signs in (
        (sx, sy, sz)
        for sx in (-1.0, 1.0)
        for sy in (-1.0, 1.0)
        for sz in (-1.0, 1.0)
    ):
        points: dict[tuple[int, int], np.ndarray] = {}
        sign_vector = np.asarray(signs, dtype=float)
        corner_center = sign_vector * inner
        for index_a in range(segments + 1):
            for index_b in range(segments - index_a + 1):
                index_c = segments - index_a - index_b
                direction = np.asarray(
                    [index_a, index_b, index_c],
                    dtype=float,
                )
                direction /= max(np.linalg.norm(direction), 1e-12)
                points[(index_a, index_b)] = (
                    corner_center + sign_vector * direction * radius
                )
        for index_a in range(segments):
            for index_b in range(segments - index_a):
                a = points[(index_a, index_b)]
                b = points[(index_a + 1, index_b)]
                c = points[(index_a, index_b + 1)]
                builder.triangle(a, b, c)
                if index_b < segments - index_a - 1:
                    d = points[(index_a + 1, index_b + 1)]
                    builder.triangle(c, b, d)

    mesh = trimesh.Trimesh(
        vertices=np.asarray(builder.vertices, dtype=float),
        faces=np.asarray(builder.faces, dtype=np.int64),
        process=True,
        validate=True,
    )
    trimesh.repair.fix_winding(mesh)
    trimesh.repair.fix_normals(mesh)
    return mesh


def apply_restrained_asymmetry(
    vertices: np.ndarray,
    half_dimensions: np.ndarray,
    local_axes: np.ndarray,
    component_index: int,
    amount: float,
) -> np.ndarray:
    amount = clamp(amount, 0.0, 0.04)
    if amount <= 0.0:
        return vertices
    result = np.asarray(vertices, dtype=float).copy()
    world_up_local = local_axes.T @ np.asarray([0.0, 1.0, 0.0])
    up_axis = int(np.argmax(np.abs(world_up_local)))
    up_sign = 1.0 if world_up_local[up_axis] >= 0.0 else -1.0
    side_axes = [axis for axis in range(3) if axis != up_axis]
    up_half = max(float(half_dimensions[up_axis]), 1e-9)

    corner_offsets: dict[tuple[int, int], float] = {}
    for sign_a in (-1, 1):
        for sign_b in (-1, 1):
            phase = (
                (component_index + 1) * 1.61803398875
                + sign_a * 0.73
                + sign_b * 1.37
            )
            corner_offsets[(sign_a, sign_b)] = math.sin(phase) * amount

    for index, vertex in enumerate(result):
        top_coordinate = vertex[up_axis] * up_sign
        top_weight = smoothstep(up_half * 0.15, up_half, top_coordinate)
        if top_weight <= 0.0:
            continue
        sign_a = -1 if vertex[side_axes[0]] < 0.0 else 1
        sign_b = -1 if vertex[side_axes[1]] < 0.0 else 1
        corner_weight = (
            0.35
            + 0.325 * smoothstep(
                0.0,
                max(float(half_dimensions[side_axes[0]]) * 0.8, 1e-9),
                abs(float(vertex[side_axes[0]])),
            )
            + 0.325 * smoothstep(
                0.0,
                max(float(half_dimensions[side_axes[1]]) * 0.8, 1e-9),
                abs(float(vertex[side_axes[1]])),
            )
        )
        delta = corner_offsets[(sign_a, sign_b)]
        result[index, up_axis] += (
            up_sign * up_half * delta * top_weight * corner_weight
        )
    return result


def reconstruct_component(
    component: trimesh.Trimesh,
    component_index: int,
    dimension_percentile: float,
    bevel_ratio: float,
    bevel_segments: int,
    asymmetry_amount: float,
    dimension_floor: float,
) -> trimesh.Trimesh:
    center, axes = pca_frame(component)
    dimensions = robust_dimensions(
        component,
        center,
        axes,
        dimension_percentile,
        dimension_floor,
    )
    radius = clamp(bevel_ratio, 0.0, 0.35) * float(dimensions.min())
    result = rounded_box_local(dimensions, radius, bevel_segments)
    local_vertices = apply_restrained_asymmetry(
        np.asarray(result.vertices),
        dimensions * 0.5,
        axes,
        component_index,
        asymmetry_amount,
    )
    result.vertices = local_vertices @ axes.T + center
    # A rotated analytic cuboid can have a larger world-axis AABB than the
    # irregular source patch that established its PCA frame. Match every
    # reconstructed piece back to that patch's world-space dimensions while
    # keeping its original center exact; this prevents an assembled wall from
    # inflating merely because its stones were oblique.
    source_center = np.asarray(component.bounds, dtype=float).mean(axis=0)
    source_extents = np.maximum(
        np.asarray(component.extents, dtype=float),
        dimension_floor,
    )
    result_center = np.asarray(result.bounds, dtype=float).mean(axis=0)
    result_extents = np.maximum(
        np.asarray(result.extents, dtype=float),
        dimension_floor,
    )
    world_scale = source_extents / result_extents
    result.vertices = (
        (np.asarray(result.vertices) - result_center) * world_scale
        + source_center
    )
    result.metadata["component_id"] = f"rounded_component_{component_index:03d}"
    trimesh.repair.fix_normals(result)
    return result


def pymeshlab_regularize(
    component: trimesh.Trimesh,
    smoothing_iterations: int,
    smoothing_strength: float,
) -> trimesh.Trimesh:
    try:
        import pymeshlab
    except ImportError as exc:
        raise RuntimeError(
            "Smooth Existing requires PyMeshLab. Repair the extension "
            "installation from Modly's Models page."
        ) from exc

    original_center = np.asarray(component.bounds).mean(axis=0)
    original_bbox_volume = max(component_bbox_volume(component), 1e-15)
    mesh_set = pymeshlab.MeshSet()
    mesh_set.add_mesh(pymeshlab.Mesh(
        vertex_matrix=np.asarray(component.vertices, dtype=np.float64),
        face_matrix=np.ascontiguousarray(
            component.faces,
            dtype=np.int32,
        ),
    ))

    area = max(float(component.area), 1e-12)
    target_faces = max(24, len(component.faces))
    edge_length = math.sqrt(4.0 * area / (math.sqrt(3.0) * target_faces))
    try:
        mesh_set.meshing_isotropic_explicit_remeshing(
            targetlen=pymeshlab.PureValue(edge_length),
            iterations=1,
        )
    except Exception as exc:
        log(f"Conservative isotropic remesh skipped for one component: {exc}")

    iterations = max(0, min(40, int(smoothing_iterations)))
    strength = clamp(smoothing_strength, 0.01, 0.75)
    if iterations:
        mesh_set.apply_coord_taubin_smoothing(
            lambda_=strength,
            mu=-strength - 0.01,
            stepsmoothnum=iterations,
        )

    current = mesh_set.current_mesh()
    result = trimesh.Trimesh(
        vertices=np.asarray(current.vertex_matrix(), dtype=float),
        faces=np.asarray(current.face_matrix(), dtype=np.int64),
        process=True,
        validate=True,
    )
    new_center = np.asarray(result.bounds).mean(axis=0)
    result.apply_translation(original_center - new_center)
    new_bbox_volume = max(component_bbox_volume(result), 1e-15)
    volume_restore = clamp(
        (original_bbox_volume / new_bbox_volume) ** (1.0 / 3.0),
        0.9,
        1.1,
    )
    result.vertices = (
        (np.asarray(result.vertices) - original_center) * volume_restore
        + original_center
    )
    trimesh.repair.fix_normals(result)
    return result


def simplify_component(
    component: trimesh.Trimesh,
    target_faces: int,
) -> trimesh.Trimesh:
    if target_faces <= 0 or len(component.faces) <= target_faces:
        return component
    try:
        result = component.simplify_quadric_decimation(
            face_count=max(12, int(target_faces)),
        )
        if isinstance(result, trimesh.Trimesh) and len(result.faces) >= 4:
            return result
    except Exception as exc:
        log(f"Per-component decimation skipped safely: {exc}")
    return component


def apply_face_budget(
    components: list[trimesh.Trimesh],
    target_face_count: int,
) -> list[trimesh.Trimesh]:
    target = max(0, int(target_face_count))
    total = sum(len(item.faces) for item in components)
    if target <= 0 or total <= target:
        return components
    minimum_total = len(components) * 12
    target = max(target, minimum_total)
    result = []
    for component in components:
        check_cancelled()
        allocation = max(
            12,
            int(round(target * len(component.faces) / total)),
        )
        result.append(simplify_component(component, allocation))
    return result


def neutral_material() -> object:
    return trimesh.visual.material.PBRMaterial(
        name="StylizedRoundedMaterial",
        baseColorFactor=[190, 182, 168, 255],
        metallicFactor=0.0,
        roughnessFactor=0.88,
    )


def assign_single_material(
    mesh: trimesh.Trimesh,
    material: object | None,
) -> None:
    selected = material if material is not None else neutral_material()
    uv = np.zeros((len(mesh.vertices), 2), dtype=np.float64)
    mesh.visual = trimesh.visual.TextureVisuals(uv=uv, material=selected)


def validate_output(meshes: list[trimesh.Trimesh]) -> None:
    if not meshes:
        raise RuntimeError("Processing produced no components.")
    for index, mesh in enumerate(meshes):
        if len(mesh.vertices) == 0 or len(mesh.faces) == 0:
            raise RuntimeError(f"Output component {index} is empty.")
        if not np.isfinite(mesh.vertices).all():
            raise RuntimeError(
                f"Output component {index} contains non-finite vertices."
            )
        if mesh.faces.min(initial=0) < 0:
            raise RuntimeError(f"Output component {index} has invalid faces.")
        if mesh.faces.max(initial=0) >= len(mesh.vertices):
            raise RuntimeError(f"Output component {index} has invalid indices.")


def load_preset(extension_dir: Path, preset_name: str) -> dict:
    if preset_name not in PRESET_NAMES:
        return {}
    preset_path = extension_dir / "presets" / f"{preset_name}.json"
    try:
        return json.loads(preset_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(
            f'Preset "{preset_name}" could not be loaded: {exc}'
        ) from exc


def resolved_params(extension_dir: Path, raw_params: dict) -> dict:
    preset = str(raw_params.get("preset", "soft_stone_wall")).strip()
    if preset == "custom":
        return dict(raw_params)
    values = load_preset(extension_dir, preset)
    values["preset"] = preset
    return values


def output_path_for(workspace_dir: str, temp_dir: str) -> Path:
    output_dir = (
        Path(workspace_dir) / "Workflows"
        if workspace_dir
        else Path(temp_dir or tempfile.gettempdir())
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir / (
        f"stylized-rounded-components-{int(time.time() * 1000)}.glb"
    )


def export_glb(
    meshes: list[trimesh.Trimesh],
    out_path: Path,
    merge_output: bool,
    material: object | None,
) -> tuple[int, int]:
    if merge_output:
        combined = (
            meshes[0].copy()
            if len(meshes) == 1
            else trimesh.util.concatenate(meshes)
        )
        assign_single_material(combined, material)
        scene = trimesh.Scene()
        scene.add_geometry(
            combined,
            node_name="StylizedRoundedComponents",
            geom_name="stylized_rounded_components",
        )
        output_vertices = len(combined.vertices)
        output_faces = len(combined.faces)
    else:
        scene = trimesh.Scene()
        output_vertices = 0
        output_faces = 0
        for index, mesh in enumerate(meshes):
            assign_single_material(mesh, material)
            component_name = f"rounded_component_{index:03d}"
            scene.add_geometry(
                mesh,
                node_name=component_name,
                geom_name=component_name,
            )
            output_vertices += len(mesh.vertices)
            output_faces += len(mesh.faces)
    out_path.write_bytes(scene.export(file_type="glb"))
    return output_vertices, output_faces


def process(payload: dict) -> tuple[Path, dict]:
    start_time = time.perf_counter()
    input_data = payload.get("input", {})
    input_path = Path(str(input_data.get("filePath", "")))
    if not input_path.is_file():
        raise RuntimeError(f"Input mesh was not found: {input_path}")
    if input_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise RuntimeError(
            f"Unsupported mesh type {input_path.suffix!r}; expected one of "
            f"{sorted(SUPPORTED_EXTENSIONS)}."
        )

    extension_dir = Path(__file__).resolve().parent
    params = resolved_params(
        extension_dir,
        payload.get("params", {}),
    )
    mode = str(
        params.get("mode", "rounded_box_reconstruction")
    ).strip().lower()
    if mode not in {"rounded_box_reconstruction", "smooth_existing"}:
        raise RuntimeError(f"Unknown processing mode: {mode}")

    progress(3, "Loading mesh…")
    input_mesh, input_material, raw_component_count = load_input_mesh(
        input_path
    )
    input_triangles = int(len(input_mesh.faces))
    input_bounds = np.asarray(input_mesh.bounds, dtype=float)
    input_center = input_bounds.mean(axis=0)
    input_extents = input_bounds[1] - input_bounds[0]
    log(
        f"Input: {input_triangles:,} triangles, "
        f"{raw_component_count} raw disconnected patches."
    )

    progress(10, "Repairing topology…")
    repaired = repair_mesh(input_mesh)
    check_cancelled()

    progress(18, "Splitting components…")
    components, repaired_component_count = semantic_components(repaired)
    segmented_component_count = len(components)
    remove_fragments = parse_bool(
        params.get("remove_small_fragments"),
        True,
    )
    minimum_volume = float(
        params.get("minimum_component_volume", 0.005)
    )
    components, removed_count = filter_fragments(
        components,
        remove_fragments,
        minimum_volume,
    )
    if not components:
        raise RuntimeError(
            "All components were removed. Lower minimum_component_volume."
        )
    log(
        f"Topology: {repaired_component_count} welded body/bodies, "
        f"{segmented_component_count} semantic pieces, "
        f"{removed_count} fragments removed."
    )

    overall_diagonal = max(
        float(np.linalg.norm(input_extents)),
        1e-6,
    )
    dimension_floor = overall_diagonal * 0.003
    output_components: list[trimesh.Trimesh] = []
    count = len(components)
    if mode == "rounded_box_reconstruction":
        progress(24, "Reconstructing rounded components…")
        for index, component in enumerate(components):
            check_cancelled()
            output_components.append(reconstruct_component(
                component,
                index,
                float(params.get("dimension_percentile", 98.0)),
                float(params.get("bevel_ratio", 0.13)),
                int(params.get("bevel_segments", 3)),
                float(params.get("asymmetry_amount", 0.025)),
                dimension_floor,
            ))
            progress(
                24 + int(50 * (index + 1) / count),
                f"Rounded component {index + 1}/{count}…",
            )
    else:
        progress(24, "Regularizing and smoothing components…")
        for index, component in enumerate(components):
            check_cancelled()
            output_components.append(pymeshlab_regularize(
                component,
                int(params.get("smoothing_iterations", 8)),
                float(params.get("smoothing_strength", 0.22)),
            ))
            progress(
                24 + int(50 * (index + 1) / count),
                f"Smoothed component {index + 1}/{count}…",
            )

    progress(78, "Applying triangle budget…")
    output_components = apply_face_budget(
        output_components,
        int(params.get("target_face_count", 30000)),
    )

    if parse_bool(params.get("recalculate_normals"), True):
        for component in output_components:
            check_cancelled()
            trimesh.repair.fix_normals(component, multibody=True)
            # Populate the smooth vertex-normal cache used by the GLB exporter.
            _ = component.vertex_normals

    validate_output(output_components)
    merge_output = parse_bool(params.get("merge_output"), True)
    preserve_material = parse_bool(
        params.get("preserve_material_slots"),
        False,
    )
    material = input_material if preserve_material else None

    progress(90, "Exporting GLB…")
    out_path = output_path_for(
        str(payload.get("workspaceDir", "")),
        str(payload.get("tempDir", "")),
    )
    output_vertices, output_triangles = export_glb(
        output_components,
        out_path,
        merge_output,
        material,
    )
    check_cancelled()

    # Export must retain the same coordinate system and overall placement.
    check_scene = trimesh.load(out_path, force="scene", process=False)
    check_mesh = check_scene.to_geometry()
    output_bounds = np.asarray(check_mesh.bounds, dtype=float)
    output_center = output_bounds.mean(axis=0)
    output_extents = output_bounds[1] - output_bounds[0]
    if not np.isfinite(check_mesh.vertices).all():
        raise RuntimeError("Export validation found non-finite vertices.")

    duration = time.perf_counter() - start_time
    stats = {
        "preset": params.get("preset", "custom"),
        "mode": mode,
        "input_component_count": int(raw_component_count),
        "repaired_component_count": int(repaired_component_count),
        "segmented_component_count": int(segmented_component_count),
        "removed_fragment_count": int(removed_count),
        "output_component_count": int(len(output_components)),
        "input_triangle_count": input_triangles,
        "output_triangle_count": int(output_triangles),
        "output_vertex_count": int(output_vertices),
        "input_center": input_center.round(8).tolist(),
        "output_center": output_center.round(8).tolist(),
        "center_drift": (output_center - input_center).round(8).tolist(),
        "input_extents": input_extents.round(8).tolist(),
        "output_extents": output_extents.round(8).tolist(),
        "material_slots": 1,
        "processing_duration_seconds": round(duration, 3),
    }
    log(
        f"Output: {len(output_components)} components, "
        f"{output_triangles:,} triangles, {duration:.2f}s."
    )
    return out_path, stats


def main() -> None:
    try:
        # Windows PowerShell 5 can surface its UTF-8 BOM as either U+FEFF or
        # the three Latin-1 characters below when the extension is tested
        # manually. Modly's native runner sends plain UTF-8.
        raw = sys.stdin.readline().lstrip("\ufeffï»¿")
        if not raw:
            raise RuntimeError("Modly did not provide a process payload.")
        payload = json.loads(raw)
        out_path, stats = process(payload)
        progress(100, "Done.")
        done(str(out_path), stats)
    except ProcessingCancelled:
        log("Cancelled.")
        raise SystemExit(130)
    except SystemExit:
        raise
    except Exception as exc:
        error(f"{exc}\n{traceback.format_exc()}")


if __name__ == "__main__":
    main()
