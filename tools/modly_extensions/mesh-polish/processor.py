#!/usr/bin/env python3
"""Surface-preserving Modly mesh-to-mesh process: Mesh Polish."""
from __future__ import annotations

import json
import math
import signal
import sys
import tempfile
import time
import traceback
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh

from _ipc import done, error, log, parse_bool, progress


SUPPORTED_EXTENSIONS = {".glb", ".gltf", ".obj", ".ply", ".stl"}
PRESET_NAMES = {
    "soft_polish",
    "standard_polish",
    "strong_polish",
    "normals_only",
    "preserve_hard_surface",
}
_CANCELLED = False


class ProcessingCancelled(RuntimeError):
    """Raised between safe processing stages after Modly cancels the job."""


class UnsafeResult(RuntimeError):
    """Raised when a candidate exceeds a source-preservation limit."""


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


def safe_update_faces(mesh: trimesh.Trimesh, mask: np.ndarray) -> None:
    if len(mask) == len(mesh.faces):
        mesh.update_faces(mask)


def triangle_count(scene: trimesh.Scene) -> int:
    return int(sum(
        len(geometry.faces)
        for geometry in scene.geometry.values()
        if isinstance(geometry, trimesh.Trimesh)
    ))


def first_material(scene: trimesh.Scene) -> object | None:
    for geometry in scene.geometry.values():
        material = getattr(geometry.visual, "material", None)
        if material is not None:
            return material
    return None


def neutral_material() -> object:
    return trimesh.visual.material.PBRMaterial(
        name="MeshPolishMaterial",
        baseColorFactor=[182, 178, 169, 255],
        metallicFactor=0.0,
        roughnessFactor=0.9,
    )


def assign_material(mesh: trimesh.Trimesh, material: object | None) -> None:
    selected = material if material is not None else neutral_material()
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=np.zeros((len(mesh.vertices), 2), dtype=np.float64),
        material=selected,
    )


def load_input_scene(file_path: Path) -> trimesh.Scene:
    try:
        loaded = trimesh.load(file_path, force="scene", process=False)
    except Exception as exc:
        raise RuntimeError(f'Could not load mesh "{file_path}": {exc}') from exc
    if not isinstance(loaded, trimesh.Scene) or not loaded.geometry:
        raise RuntimeError(f'No triangle geometry found in "{file_path}".')
    usable = [
        geometry for geometry in loaded.geometry.values()
        if isinstance(geometry, trimesh.Trimesh) and len(geometry.faces) > 0
    ]
    if not usable:
        raise RuntimeError(f'No usable triangular surfaces found in "{file_path}".')
    for geometry in usable:
        if not np.isfinite(geometry.vertices).all():
            raise RuntimeError("The input contains non-finite vertices.")
    return loaded


def repair_mesh(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    repaired = mesh.copy()
    if len(repaired.vertices) == 0 or len(repaired.faces) == 0:
        raise RuntimeError("The input mesh is empty.")
    if not np.isfinite(repaired.vertices).all():
        raise RuntimeError("The input mesh contains non-finite vertices.")

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
    if len(repaired.faces) == 0 or not np.isfinite(repaired.vertices).all():
        raise RuntimeError("Safe repair produced an empty or invalid mesh.")
    return repaired


def connected_components(mesh: trimesh.Trimesh) -> list[trimesh.Trimesh]:
    return list(mesh.split(only_watertight=False))


def positional_component_count(mesh: trimesh.Trimesh) -> int:
    welded = mesh.copy()
    welded.merge_vertices(merge_tex=True, merge_norm=True)
    welded.remove_unreferenced_vertices()
    return len(welded.split(only_watertight=False))


def vertex_centroid(mesh: trimesh.Trimesh) -> np.ndarray:
    return np.asarray(mesh.vertices, dtype=np.float64).mean(axis=0)


def component_diagonal(mesh: trimesh.Trimesh) -> float:
    return max(float(np.linalg.norm(np.asarray(mesh.extents))), 1e-12)


def boundary_length(mesh: trimesh.Trimesh) -> float:
    if len(mesh.faces) == 0 or len(mesh.edges_unique) == 0:
        return 0.0
    counts = np.bincount(
        mesh.edges_unique_inverse,
        minlength=len(mesh.edges_unique),
    )
    boundary = mesh.edges_unique[counts == 1]
    if len(boundary) == 0:
        return 0.0
    points = np.asarray(mesh.vertices, dtype=np.float64)
    return float(np.linalg.norm(
        points[boundary[:, 0]] - points[boundary[:, 1]],
        axis=1,
    ).sum())


def closest_surface_max(
    source: trimesh.Trimesh,
    candidate: trimesh.Trimesh,
) -> float:
    """Return symmetric maximum vertex-to-surface distance."""
    try:
        _, forward, _ = trimesh.proximity.closest_point(
            source, np.asarray(candidate.vertices)
        )
        _, backward, _ = trimesh.proximity.closest_point(
            candidate, np.asarray(source.vertices)
        )
        values = np.concatenate((forward, backward))
        if len(values) and np.isfinite(values).all():
            return float(values.max(initial=0.0))
    except Exception as exc:
        log(f"Exact surface query unavailable; using vertex distance: {exc}")

    from scipy.spatial import cKDTree

    source_tree = cKDTree(np.asarray(source.vertices))
    candidate_tree = cKDTree(np.asarray(candidate.vertices))
    forward = source_tree.query(np.asarray(candidate.vertices), workers=-1)[0]
    backward = candidate_tree.query(np.asarray(source.vertices), workers=-1)[0]
    return float(max(
        np.max(forward, initial=0.0),
        np.max(backward, initial=0.0),
    ))


@dataclass
class Validation:
    displacement: float
    displacement_percent: float
    dimension_change_percent: float
    boundary_length: float


def validate_component(
    source: trimesh.Trimesh,
    candidate: trimesh.Trimesh,
    max_dimension_percent: float,
    max_displacement_percent: float,
) -> Validation:
    if len(candidate.vertices) == 0 or len(candidate.faces) == 0:
        raise UnsafeResult("component became empty")
    if not np.isfinite(candidate.vertices).all():
        raise UnsafeResult("component contains non-finite vertices")
    if candidate.faces.min(initial=0) < 0:
        raise UnsafeResult("component contains a negative face index")
    if candidate.faces.max(initial=0) >= len(candidate.vertices):
        raise UnsafeResult("component contains an invalid face index")
    if positional_component_count(candidate) != 1:
        raise UnsafeResult("component split into multiple pieces")

    source_center = vertex_centroid(source)
    candidate_center = vertex_centroid(candidate)
    center_error = float(np.linalg.norm(candidate_center - source_center))
    tolerance = component_diagonal(source) * 1e-9 + 1e-12
    if center_error > tolerance:
        raise UnsafeResult("component center moved")

    source_extents = np.asarray(source.extents, dtype=np.float64)
    candidate_extents = np.asarray(candidate.extents, dtype=np.float64)
    denominator = np.maximum(source_extents, component_diagonal(source) * 1e-8)
    dimension_change = float(
        np.max(np.abs(candidate_extents - source_extents) / denominator) * 100.0
    )
    if dimension_change > max_dimension_percent + 1e-7:
        raise UnsafeResult(
            f"dimension change {dimension_change:.3f}% exceeds "
            f"{max_dimension_percent:.3f}%"
        )

    source_boundary = boundary_length(source)
    candidate_boundary = boundary_length(candidate)
    diagonal = component_diagonal(source)
    if source.is_watertight and not candidate.is_watertight:
        raise UnsafeResult("a closed component developed an opening")
    if (
        source_boundary > 0.0
        and candidate_boundary > source_boundary * 1.2 + diagonal * 0.01
    ):
        raise UnsafeResult("component boundary grew enough to indicate a new hole")

    displacement = closest_surface_max(source, candidate)
    displacement_percent = displacement / diagonal * 100.0
    if displacement_percent > max_displacement_percent + 1e-7:
        raise UnsafeResult(
            f"surface displacement {displacement_percent:.3f}% exceeds "
            f"{max_displacement_percent:.3f}%"
        )
    return Validation(
        displacement=displacement,
        displacement_percent=displacement_percent,
        dimension_change_percent=dimension_change,
        boundary_length=candidate_boundary,
    )


def to_pymeshlab(mesh: trimesh.Trimesh):
    import pymeshlab

    mesh_set = pymeshlab.MeshSet()
    mesh_set.add_mesh(pymeshlab.Mesh(
        vertex_matrix=np.asarray(mesh.vertices, dtype=np.float64),
        face_matrix=np.ascontiguousarray(mesh.faces, dtype=np.int32),
    ))
    return mesh_set


def from_pymeshlab(mesh_set) -> trimesh.Trimesh:
    current = mesh_set.current_mesh()
    result = trimesh.Trimesh(
        vertices=np.asarray(current.vertex_matrix(), dtype=np.float64),
        faces=np.asarray(current.face_matrix(), dtype=np.int64),
        process=False,
        validate=False,
    )
    result.remove_unreferenced_vertices()
    return result


def isotropic_remesh(
    source: trimesh.Trimesh,
    params: dict,
) -> trimesh.Trimesh:
    import pymeshlab

    diagonal = component_diagonal(source)
    mesh_set = to_pymeshlab(source)
    mesh_set.meshing_isotropic_explicit_remeshing(
        iterations=max(1, min(8, int(params["remesh_iterations"]))),
        adaptive=parse_bool(params.get("adaptive"), False),
        selectedonly=False,
        targetlen=pymeshlab.PureValue(
            diagonal
            * clamp(float(params["target_edge_length_percent"]), 0.25, 10.0)
            / 100.0
        ),
        featuredeg=clamp(float(params["feature_angle"]), 5.0, 90.0),
        checksurfdist=parse_bool(params.get("check_surface_distance"), True),
        maxsurfdist=pymeshlab.PureValue(
            diagonal
            * clamp(
                float(params["maximum_surface_distance_percent"]),
                0.1,
                5.0,
            )
            / 100.0
        ),
        splitflag=parse_bool(params.get("refine_step"), True),
        collapseflag=parse_bool(params.get("collapse_step"), True),
        swapflag=parse_bool(params.get("edge_swap"), True),
        smoothflag=parse_bool(params.get("smoothing_step"), True),
        reprojectflag=parse_bool(params.get("reproject_step"), True),
    )
    result = from_pymeshlab(mesh_set)
    result.vertices += vertex_centroid(source) - vertex_centroid(result)
    return result


def taubin_smooth(
    source: trimesh.Trimesh,
    iterations: int,
    lambda_value: float,
    mu_value: float,
) -> trimesh.Trimesh:
    if iterations <= 0:
        return source.copy()
    mesh_set = to_pymeshlab(source)
    mesh_set.apply_coord_taubin_smoothing(
        lambda_=clamp(lambda_value, 0.05, 0.75),
        mu=clamp(mu_value, -0.8, -0.05),
        stepsmoothnum=max(1, min(12, int(iterations))),
        selected=False,
    )
    result = from_pymeshlab(mesh_set)
    result.vertices += vertex_centroid(source) - vertex_centroid(result)
    return result


def decimate(
    source: trimesh.Trimesh,
    ratio: float,
) -> trimesh.Trimesh:
    ratio = clamp(ratio, 0.8, 1.0)
    if ratio >= 0.999999 or len(source.faces) < 8:
        return source.copy()
    mesh_set = to_pymeshlab(source)
    mesh_set.meshing_decimation_quadric_edge_collapse(
        targetfacenum=max(4, int(round(len(source.faces) * ratio))),
        qualitythr=0.3,
        preserveboundary=True,
        boundaryweight=1.0,
        preservenormal=True,
        preservetopology=True,
        optimalplacement=True,
        planarquadric=True,
        planarweight=0.001,
        qualityweight=False,
        autoclean=True,
        selected=False,
    )
    result = from_pymeshlab(mesh_set)
    result.vertices += vertex_centroid(source) - vertex_centroid(result)
    return result


def smoothing_schedule(requested: int) -> list[int]:
    requested = max(0, min(12, int(requested)))
    if requested == 0:
        return [0]
    values = [requested]
    values.extend(range(requested - 1, -1, -1))
    return list(dict.fromkeys(values))


def shade_normals(
    source: trimesh.Trimesh,
    mode: str,
    angle_degrees: float,
) -> trimesh.Trimesh:
    result = source.copy()
    trimesh.repair.fix_normals(result, multibody=True)
    if mode == "smooth_by_angle":
        result = trimesh.graph.smooth_shade(
            result,
            angle=math.radians(clamp(angle_degrees, 5.0, 180.0)),
            facet_minarea=None,
        )
    _ = result.vertex_normals
    return result


@dataclass
class ComponentReport:
    requested_iterations: int
    effective_iterations: int
    input_triangles: int
    output_triangles: int
    displacement: float
    displacement_percent: float
    dimension_change_percent: float
    fallback_reason: str | None


def polish_component(
    source: trimesh.Trimesh,
    params: dict,
) -> tuple[trimesh.Trimesh, ComponentReport]:
    check_cancelled()
    source_center = vertex_centroid(source)
    requested = max(0, min(12, int(params["smoothing_iterations"])))
    fallback_reason: str | None = None
    max_dimension = float(params["maximum_dimension_change_percent"])
    max_displacement = float(params["maximum_surface_displacement_percent"])

    if (
        not parse_bool(params.get("remesh_enabled"), True)
        and requested == 0
    ):
        candidate = source.copy()
        validation = validate_component(
            source, candidate, max_dimension, max_displacement
        )
        return candidate, ComponentReport(
            requested_iterations=requested,
            effective_iterations=0,
            input_triangles=len(source.faces),
            output_triangles=len(candidate.faces),
            displacement=validation.displacement,
            displacement_percent=validation.displacement_percent,
            dimension_change_percent=validation.dimension_change_percent,
            fallback_reason=None,
        )

    base = source.copy()
    if parse_bool(params.get("remesh_enabled"), True):
        if len(source.faces) < 4:
            fallback_reason = "too few faces for safe remeshing"
        else:
            try:
                base = isotropic_remesh(source, params)
            except Exception as exc:
                fallback_reason = f"remeshing was not safely applicable: {exc}"
                base = source.copy()

    accepted: trimesh.Trimesh | None = None
    accepted_validation: Validation | None = None
    effective = 0
    last_failure = fallback_reason
    for iterations in smoothing_schedule(requested):
        check_cancelled()
        try:
            candidate = taubin_smooth(
                base,
                iterations,
                float(params["taubin_lambda"]),
                float(params["taubin_mu"]),
            )
            candidate.vertices += source_center - vertex_centroid(candidate)
            validation = validate_component(
                source,
                candidate,
                max_dimension,
                max_displacement,
            )
            accepted = candidate
            accepted_validation = validation
            effective = iterations
            break
        except Exception as exc:
            last_failure = str(exc)

    if accepted is None or accepted_validation is None:
        accepted = source.copy()
        accepted_validation = validate_component(
            source, accepted, max_dimension, max_displacement
        )
        effective = 0
        fallback_reason = (
            f"restored repaired source after safety rejection: {last_failure}"
        )
    elif effective < requested:
        fallback_reason = (
            f"reduced smoothing from {requested} to {effective}: {last_failure}"
        )

    if parse_bool(params.get("decimation_enabled"), False):
        before_decimation = accepted
        before_validation = accepted_validation
        try:
            candidate = decimate(
                accepted,
                float(params.get("decimation_ratio", 0.9)),
            )
            candidate.vertices += source_center - vertex_centroid(candidate)
            accepted_validation = validate_component(
                source,
                candidate,
                max_dimension,
                max_displacement,
            )
            accepted = candidate
        except Exception as exc:
            accepted = before_decimation
            accepted_validation = before_validation
            suffix = f"final decimation skipped: {exc}"
            fallback_reason = (
                f"{fallback_reason}; {suffix}" if fallback_reason else suffix
            )

    return accepted, ComponentReport(
        requested_iterations=requested,
        effective_iterations=effective,
        input_triangles=len(source.faces),
        output_triangles=len(accepted.faces),
        displacement=accepted_validation.displacement,
        displacement_percent=accepted_validation.displacement_percent,
        dimension_change_percent=accepted_validation.dimension_change_percent,
        fallback_reason=fallback_reason,
    )


def concatenate_components(
    components: list[trimesh.Trimesh],
) -> trimesh.Trimesh:
    if not components:
        raise RuntimeError("No components remain after processing.")
    if len(components) == 1:
        return components[0].copy()
    return trimesh.util.concatenate(components)


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
    preset = str(raw_params.get("preset", "standard_polish")).strip()
    if preset == "custom":
        values = dict(raw_params)
    else:
        values = load_preset(extension_dir, preset)
        if not values:
            raise RuntimeError(f"Unknown Mesh Polish preset: {preset}")
    values["preset"] = preset
    values.setdefault("remesh_enabled", True)
    values.setdefault("remesh_iterations", 3)
    values.setdefault("adaptive", False)
    values.setdefault("target_edge_length_percent", 2.0)
    values.setdefault("feature_angle", 50.0)
    values.setdefault("check_surface_distance", True)
    values.setdefault("maximum_surface_distance_percent", 1.0)
    values.setdefault("refine_step", True)
    values.setdefault("collapse_step", True)
    values.setdefault("edge_swap", True)
    values.setdefault("smoothing_step", True)
    values.setdefault("reproject_step", True)
    values.setdefault("taubin_lambda", 0.45)
    values.setdefault("taubin_mu", -0.48)
    values.setdefault("smoothing_iterations", 6)
    values.setdefault("maximum_dimension_change_percent", 3.0)
    values.setdefault("maximum_overall_bounds_change_percent", 2.0)
    values.setdefault("maximum_surface_displacement_percent", 1.5)
    values.setdefault("normals_mode", "smooth_by_angle")
    values.setdefault("normals_angle", 60.0)
    values.setdefault("decimation_enabled", False)
    values.setdefault("decimation_ratio", 0.9)
    return values


def output_path_for(workspace_dir: str, temp_dir: str) -> Path:
    output_dir = (
        Path(workspace_dir) / "Workflows"
        if workspace_dir
        else Path(temp_dir or tempfile.gettempdir())
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir / f"mesh-polish-{int(time.time() * 1000)}.glb"


def bounds_change_percent(
    source_bounds: np.ndarray,
    candidate_bounds: np.ndarray,
) -> tuple[np.ndarray, float]:
    source_extents = source_bounds[1] - source_bounds[0]
    candidate_extents = candidate_bounds[1] - candidate_bounds[0]
    diagonal = max(float(np.linalg.norm(source_extents)), 1e-12)
    denominator = np.maximum(source_extents, diagonal * 1e-8)
    change = np.abs(candidate_extents - source_extents) / denominator * 100.0
    return change, float(change.max(initial=0.0))


def process_geometry(
    geometry: trimesh.Trimesh,
    params: dict,
    geometry_index: int,
    geometry_total: int,
) -> tuple[trimesh.Trimesh, trimesh.Trimesh, list[ComponentReport]]:
    repaired = repair_mesh(geometry)
    components = connected_components(repaired)
    if not components:
        raise RuntimeError("Repair produced no connected components.")

    polished: list[trimesh.Trimesh] = []
    reports: list[ComponentReport] = []
    for component_index, component in enumerate(components):
        check_cancelled()
        processed, report = polish_component(component, params)
        polished.append(processed)
        reports.append(report)
        progress(
            18 + int(
                57
                * (
                    geometry_index
                    + (component_index + 1) / len(components)
                )
                / max(geometry_total, 1)
            ),
            (
                f"Polishing geometry {geometry_index + 1}/{geometry_total}, "
                f"component {component_index + 1}/{len(components)}..."
            ),
        )

    combined = concatenate_components(polished)
    if positional_component_count(combined) != len(components):
        raise RuntimeError(
            "Processed components fused, disappeared, or changed count."
        )
    shaded = shade_normals(
        combined,
        str(params.get("normals_mode", "smooth_by_angle")).strip().lower(),
        float(params.get("normals_angle", 60.0)),
    )
    if positional_component_count(shaded) != len(components):
        raise RuntimeError("Normal generation changed geometric components.")
    return shaded, repaired, reports


def geometry_node_snapshot(scene: trimesh.Scene) -> dict[str, tuple[str, list]]:
    snapshot = {}
    for node_name in scene.graph.nodes_geometry:
        transform, geometry_name = scene.graph[node_name]
        snapshot[str(node_name)] = (
            str(geometry_name),
            np.asarray(transform, dtype=np.float64).round(12).tolist(),
        )
    return snapshot


def scene_bounds(scene: trimesh.Scene) -> np.ndarray:
    bounds = np.asarray(scene.bounds, dtype=np.float64)
    if bounds.shape != (2, 3) or not np.isfinite(bounds).all():
        raise RuntimeError("Scene bounds are invalid.")
    return bounds


def validate_export(
    output_path: Path,
    expected_component_count: int,
) -> trimesh.Scene:
    checked = trimesh.load(output_path, force="scene", process=False)
    if not isinstance(checked, trimesh.Scene) or not checked.geometry:
        raise RuntimeError("Export validation found no geometry.")
    component_count = 0
    for geometry in checked.geometry.values():
        if not isinstance(geometry, trimesh.Trimesh):
            continue
        if not np.isfinite(geometry.vertices).all():
            raise RuntimeError("Export validation found non-finite vertices.")
        component_count += positional_component_count(geometry)
    if component_count != expected_component_count:
        raise RuntimeError(
            "GLB validation found a changed connected-component count."
        )
    return checked


def process(payload: dict) -> tuple[Path, dict]:
    start_time = time.perf_counter()
    input_path = Path(str(payload.get("input", {}).get("filePath", "")))
    if not input_path.is_file():
        raise RuntimeError(f"Input mesh was not found: {input_path}")
    if input_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise RuntimeError(
            f"Unsupported mesh type {input_path.suffix!r}; expected one of "
            f"{sorted(SUPPORTED_EXTENSIONS)}."
        )

    extension_dir = Path(__file__).resolve().parent
    params = resolved_params(extension_dir, payload.get("params", {}))
    progress(3, "Loading original mesh...")
    source_scene = load_input_scene(input_path)
    source_snapshot = geometry_node_snapshot(source_scene)
    source_bounds = scene_bounds(source_scene)
    source_triangles = triangle_count(source_scene)
    material = first_material(source_scene)
    output_scene = source_scene.copy()
    repaired_geometry: dict[str, trimesh.Trimesh] = {}
    reports: list[ComponentReport] = []
    expected_components = 0

    mesh_items = [
        (name, geometry)
        for name, geometry in source_scene.geometry.items()
        if isinstance(geometry, trimesh.Trimesh) and len(geometry.faces) > 0
    ]
    progress(10, "Repairing and separating components...")
    for geometry_index, (geometry_name, geometry) in enumerate(mesh_items):
        check_cancelled()
        polished, repaired, geometry_reports = process_geometry(
            geometry,
            params,
            geometry_index,
            len(mesh_items),
        )
        repaired_geometry[geometry_name] = repaired
        expected_components += len(connected_components(repaired))
        reports.extend(geometry_reports)
        assign_material(polished, material)
        output_scene.geometry[geometry_name] = polished

    if geometry_node_snapshot(output_scene) != source_snapshot:
        raise RuntimeError("Scene hierarchy or transforms changed during processing.")

    candidate_bounds = scene_bounds(output_scene)
    bounds_vector, max_bounds_change = bounds_change_percent(
        source_bounds, candidate_bounds
    )
    max_allowed_bounds = float(
        params["maximum_overall_bounds_change_percent"]
    )
    scene_fallback = None
    if max_bounds_change > max_allowed_bounds + 1e-7:
        scene_fallback = (
            f"whole-scene bounds changed {max_bounds_change:.3f}%, above "
            f"{max_allowed_bounds:.3f}%; restored repaired source geometry"
        )
        log(scene_fallback)
        for geometry_name, repaired in repaired_geometry.items():
            shaded = shade_normals(
                repaired,
                str(params.get("normals_mode", "smooth_by_angle")).lower(),
                float(params.get("normals_angle", 60.0)),
            )
            assign_material(shaded, material)
            output_scene.geometry[geometry_name] = shaded
        candidate_bounds = scene_bounds(output_scene)
        bounds_vector, max_bounds_change = bounds_change_percent(
            source_bounds, candidate_bounds
        )

    output_component_count = sum(
        positional_component_count(geometry)
        for geometry in output_scene.geometry.values()
        if isinstance(geometry, trimesh.Trimesh)
    )
    if output_component_count != expected_components:
        raise RuntimeError(
            "Final validation found fused, missing, or newly split components."
        )
    if geometry_node_snapshot(output_scene) != source_snapshot:
        raise RuntimeError("Scene transforms or hierarchy were not preserved.")

    progress(86, "Exporting validated GLB...")
    output_path = output_path_for(
        str(payload.get("workspaceDir", "")),
        str(payload.get("tempDir", "")),
    )
    output_path.write_bytes(output_scene.export(file_type="glb"))
    check_cancelled()
    checked = validate_export(output_path, expected_components)
    checked_bounds = scene_bounds(checked)
    checked_bounds_vector, checked_max_bounds_change = bounds_change_percent(
        source_bounds, checked_bounds
    )
    if checked_max_bounds_change > max_allowed_bounds + 1e-7:
        raise RuntimeError(
            "Exported GLB exceeds the permitted whole-scene bounds change."
        )

    max_displacement = max(
        (item.displacement for item in reports),
        default=0.0,
    )
    max_displacement_percent = max(
        (item.displacement_percent for item in reports),
        default=0.0,
    )
    fallbacks = [
        {
            "component": index,
            "reason": item.fallback_reason,
        }
        for index, item in enumerate(reports)
        if item.fallback_reason
    ]
    duration = time.perf_counter() - start_time
    final_triangles = triangle_count(checked)
    stats = {
        "preset": params["preset"],
        "original_triangle_count": int(source_triangles),
        "final_triangle_count": int(final_triangles),
        "connected_component_count": int(expected_components),
        "maximum_surface_displacement": round(max_displacement, 9),
        "maximum_surface_displacement_percent": round(
            max_displacement_percent, 6
        ),
        "bounds_change_percent_xyz": checked_bounds_vector.round(6).tolist(),
        "maximum_bounds_change_percent": round(
            checked_max_bounds_change, 6
        ),
        "processing_duration_seconds": round(duration, 3),
        "requested_smoothing_iterations": [
            item.requested_iterations for item in reports
        ],
        "effective_smoothing_iterations": [
            item.effective_iterations for item in reports
        ],
        "fallback_component_count": len(fallbacks),
        "fallbacks": fallbacks,
        "scene_fallback": scene_fallback,
        "scene_node_count": len(source_snapshot),
        "geometry_count": len(mesh_items),
        "transforms_preserved": True,
        "input_bounds": source_bounds.round(9).tolist(),
        "output_bounds": checked_bounds.round(9).tolist(),
    }
    log(
        f"Mesh Polish: {source_triangles:,} -> {final_triangles:,} triangles; "
        f"{expected_components} components; max displacement "
        f"{max_displacement_percent:.3f}%; bounds "
        f"{checked_max_bounds_change:.3f}%; {duration:.2f}s."
    )
    progress(100, "Done.")
    return output_path, stats


def main() -> None:
    try:
        raw = sys.stdin.readline().lstrip("\ufeffï»¿")
        if not raw:
            raise RuntimeError("Modly did not provide a process payload.")
        payload = json.loads(raw)
        output_path, stats = process(payload)
        done(str(output_path), stats)
    except ProcessingCancelled:
        log("Cancelled.")
        raise SystemExit(130)
    except SystemExit:
        raise
    except Exception as exc:
        error(f"{exc}\n{traceback.format_exc()}")


if __name__ == "__main__":
    main()
