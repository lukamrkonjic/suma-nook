"""Build the grass-tuft surface layer from the Gemini-referenced v4 source.

The v4 source (Gemini reference image through Hunyuan3D 2.1 at raised
octree resolution) is a clean block whose top carries discrete sculpted
tuft clusters. This processor keeps those ACTUAL rounded lobes:

* samples the whole source for a whisper of ground undulation;
* finds the top plateau by area-weighted height of upward faces;
* bisects just above the plateau and keeps only the tuft shells;
* drops flat sheet remnants and dust fragments;
* maps tuft positions from the source block onto the Suma footprint,
  sinking their open bottoms into the ground cap;
* decimates to a strict performance budget while lobes stay smooth;
* exports flat-shaded as Asset Studio's absolute 0% smoothing baseline.

Run from the repository root with Blender 5.x:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_grass_tufts_surface.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import process_sand_tile as shared

ROOT = shared.ROOT
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "grass_tile"
    / "grass_tile_source_v4.glb"
)
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "tile_layer_surface_grass_tufts.glb"
EXPECTED_SOURCE_SHA256 = (
    "C17F9A2D3E10C75E0BE00D460D162D4ED7D68EEE7F6CB7B5B08DC984D2D99093"
)
REPORT_PREFIX = "GRASS_TUFTS_SURFACE_REPORT="

TILE = 1.70
HALF = TILE * 0.5
MATERIAL_NAME = "grass_primary"
FOOTPRINT_FIT = 0.995
TUFT_SINK = 0.012
PLATEAU_BINS = 120
CUT_LIFT_FRACTION = 0.018          # of source height above the plateau
MIN_FRAGMENT_TRIANGLES = 30
SHEET_MAX_XY_FRACTION = 0.45       # of source span — larger means leftover sheet
MIN_TUFT_ASPECT = 0.22             # height / horizontal extent
TRIANGLE_BUDGET = 7500
SMOOTH_ANGLE_DEGREES = 55.0

# Ground cap: the source contributes only a whisper of undulation.
shared.MATERIAL_NAME = MATERIAL_NAME
shared.CAP_OBJECT_NAME = "grass_tufts_cap"
shared.CAP_MESH_NAME = "flat_baseline_soft_grass_ground_cap_mesh"
shared.PALETTE = {MATERIAL_NAME: "708C4B"}
shared.GRID_SIZE = 25
shared.EDGE_BLEND_FRACTION = 0.16
shared.INTERIOR_BASE_HEIGHT = 0.004
shared.RELIEF_AMPLITUDE = 0.020
shared.RELIEF_EXPONENT = 1.0
shared.TAUBIN_ITERATIONS = 6
shared.GAUSSIAN_PASSES = 2
shared.CONTOUR_SMOOTHING_PASSES = 3
shared.CONTOUR_SMOOTHING_BLEND = 0.6
shared.CONTOUR_SAMPLE_SPACING = 1.35


def find_plateau_z(obj: bpy.types.Object, lower_z: float, upper_z: float) -> float:
    mesh = obj.data
    mesh.calc_loop_triangles()
    height = max(upper_z - lower_z, 1e-6)
    bins = [0.0] * PLATEAU_BINS
    for triangle in mesh.loop_triangles:
        normal = triangle.normal
        if normal.z < 0.6:
            continue
        center_z = sum(mesh.vertices[i].co.z for i in triangle.vertices) / 3.0
        index = int((center_z - lower_z) / height * (PLATEAU_BINS - 1))
        index = max(0, min(PLATEAU_BINS - 1, index))
        bins[index] += triangle.area
    best = max(range(PLATEAU_BINS), key=lambda i: bins[i])
    return lower_z + (best + 0.5) / PLATEAU_BINS * height


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    return shared.object_bounds(obj)


def triangle_count(obj: bpy.types.Object) -> int:
    return shared.triangle_count(obj)


def separate_loose(obj: bpy.types.Object) -> list[bpy.types.Object]:
    base_name = obj.name.split(".")[0]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [
        candidate
        for candidate in bpy.context.scene.objects
        if candidate.type == "MESH"
        and candidate.name.split(".")[0] == base_name
    ]


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing grass source: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest().upper()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            "Grass source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    if not source_meshes:
        raise RuntimeError("Grass source does not contain a mesh")
    source = max(source_meshes, key=triangle_count)
    for obj in source_meshes:
        if obj is not source:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    source_triangles = triangle_count(source)

    # Ground undulation is sampled from the intact source.
    sampled, _filled = shared.sample_source_height_field(source)
    ground_heights = shared.normalized_dune_heights(sampled)

    full_lower, full_upper = object_bounds(source)
    source_span_x = full_upper.x - full_lower.x
    source_span_y = full_upper.y - full_lower.y
    source_height = full_upper.z - full_lower.z
    source_center = (full_lower + full_upper) * 0.5

    plateau_z = find_plateau_z(source, full_lower.z, full_upper.z)
    cut_z = plateau_z + source_height * CUT_LIFT_FRACTION

    # Keep only geometry above the cut: the tuft shells.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(
        plane_co=(0.0, 0.0, cut_z),
        plane_no=(0.0, 0.0, 1.0),
        clear_inner=True,
        use_fill=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    components = separate_loose(source)
    kept: list[bpy.types.Object] = []
    dropped_fragments = 0
    dropped_sheets = 0
    max_sheet_span = max(source_span_x, source_span_y) * SHEET_MAX_XY_FRACTION
    for component in components:
        triangles = triangle_count(component)
        lower, upper = object_bounds(component)
        extent_xy = max(upper.x - lower.x, upper.y - lower.y)
        height = upper.z - lower.z
        if triangles < MIN_FRAGMENT_TRIANGLES:
            dropped_fragments += 1
            bpy.data.objects.remove(component, do_unlink=True)
            continue
        if extent_xy > max_sheet_span or (
            extent_xy > 1e-6 and height / extent_xy < MIN_TUFT_ASPECT
        ):
            dropped_sheets += 1
            bpy.data.objects.remove(component, do_unlink=True)
            continue
        kept.append(component)
    if not kept:
        raise RuntimeError("No tuft components survived extraction")

    bpy.ops.object.select_all(action="DESELECT")
    for component in kept:
        component.select_set(True)
    bpy.context.view_layer.objects.active = kept[0]
    if len(kept) > 1:
        bpy.ops.object.join()
    tufts = bpy.context.active_object
    tufts.name = "grass_tufts"
    tufts.data.name = "extracted_grass_tuft_clusters_mesh"

    # Map source block coordinates onto the Suma footprint; sink the open
    # shell bottoms into the ground cap.
    scale_x = TILE * FOOTPRINT_FIT / source_span_x
    scale_y = TILE * FOOTPRINT_FIT / source_span_y
    scale_z = (scale_x + scale_y) * 0.5
    for vertex in tufts.data.vertices:
        position = vertex.co
        position.x = (position.x - source_center.x) * scale_x
        position.y = (position.y - source_center.y) * scale_y
        position.z = (position.z - cut_z) * scale_z
    tufts.data.update()
    lower, upper = object_bounds(tufts)
    for vertex in tufts.data.vertices:
        vertex.co.z -= lower.z + TUFT_SINK
    tufts.data.update()

    # Performance budget without visual loss: collapse-decimate only if the
    # raised octree resolution produced more than the budget.
    pre_decimate_triangles = triangle_count(tufts)
    if pre_decimate_triangles > TRIANGLE_BUDGET:
        decimate = tufts.modifiers.new(name="budget_decimate", type="DECIMATE")
        decimate.ratio = TRIANGLE_BUDGET / pre_decimate_triangles
        decimate.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = tufts
        bpy.ops.object.modifier_apply(modifier=decimate.name)

    # Collapse decimation leaves sliver triangles at the high-curvature lobe
    # tips; runtime smoothing (which welds and averages normals) turns those
    # into visible holes. Weld, dissolve degenerates, repair normals, and
    # relax the surface so smoothing always has sound closed domes to work on.
    bpy.context.view_layer.objects.active = tufts
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0018)
    bpy.ops.mesh.dissolve_degenerate(threshold=0.001)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    relax = tufts.modifiers.new(name="tip_relax", type="SMOOTH")
    relax.factor = 0.35
    relax.iterations = 2
    bpy.ops.object.modifier_apply(modifier=relax.name)

    tufts.data.materials.clear()
    tufts.data.materials.append(shared.semantic_material(MATERIAL_NAME))
    for polygon in tufts.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = False
    tufts.data.update()

    cap = shared.create_dune_cap(ground_heights)

    epsilon = 0.002
    cap_lower, cap_upper = object_bounds(cap)
    tuft_lower, tuft_upper = object_bounds(tufts)
    if (
        abs(cap_lower.x + HALF) > epsilon
        or abs(cap_upper.x - HALF) > epsilon
        or abs(cap_lower.y + HALF) > epsilon
        or abs(cap_upper.y - HALF) > epsilon
        or abs(cap_lower.z + 0.055) > epsilon
    ):
        raise RuntimeError(f"Ground cap outside contract: {cap_lower} .. {cap_upper}")
    if (
        tuft_lower.x < -HALF - epsilon
        or tuft_upper.x > HALF + epsilon
        or tuft_lower.y < -HALF - epsilon
        or tuft_upper.y > HALF + epsilon
        or tuft_upper.z > 0.30
    ):
        raise RuntimeError(f"Tufts outside envelope: {tuft_lower} .. {tuft_upper}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    tufts.select_set(True)
    bpy.context.view_layer.objects.active = tufts
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )

    print(
        REPORT_PREFIX
        + json.dumps(
            {
                "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": source_hash,
                "output": str(OUTPUT.relative_to(ROOT)),
                "method": "plateau-cut tuft extraction on softly sampled ground",
                "reference_image": "gemini_ref.png",
                "source_triangles": source_triangles,
                "plateau_z": round(plateau_z, 5),
                "cut_z": round(cut_z, 5),
                "component_count": len(components),
                "kept_tuft_components": len(kept),
                "dropped_fragments": dropped_fragments,
                "dropped_sheets": dropped_sheets,
                "pre_decimate_triangles": pre_decimate_triangles,
                "output_tuft_triangles": triangle_count(tufts),
                "triangle_budget": TRIANGLE_BUDGET,
                "cap_bounds": {
                    "min": [round(v, 4) for v in cap_lower],
                    "max": [round(v, 4) for v in cap_upper],
                },
                "tuft_bounds": {
                    "min": [round(v, 4) for v in tuft_lower],
                    "max": [round(v, 4) for v in tuft_upper],
                },
                "normal_baseline": "flat_per_face_0_percent",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
