"""Normalize Luka's generated concrete top into a Suma surface layer.

The source already contains the useful shallow construction: four broad
precast panels separated by recessed cross joints. It is not used as a
gameplay block. This processor:

* hash-pins and imports the immutable revised source GLB;
* preserves its panel/joint topology and authored flat shading;
* regularizes existing panel planes and noisy boundaries without remeshing;
* normalizes the footprint with near-uniform source proportions;
* maps its complete depth to the constructed zone at z=-0.20..0.0;
* performs no shading smoothing, welding, subdivision, decimation, or remesh;
* assigns one semantic runtime material;
* exports only ``tile_layer_surface_concrete_brutalist.glb``.

The runtime composes this surface with ``tile_layer_base_deep_recess`` using
the ``concrete_side`` material. This preserves deep control joints without
changing the tile's walk plane, stacking height, or collision.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_concrete_tile.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from constructed_surface_regularizer import (
    ConstructedRegularizationConfig,
    regularize_constructed_surface,
)

SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "concrete_tile"
    / "concrete_tile_source_v2.glb"
)
OUTPUT = (
    ROOT
    / "assets"
    / "3d"
    / "reworked"
    / "tile_layer_surface_concrete_brutalist.glb"
)
EXPECTED_SOURCE_SHA256 = (
    "6643CE66290E74C426070F91F0C756CCBCF63D2D625859D224A1AF0ECBAE852A"
)

TILE = 1.70
SURFACE_BOTTOM = -0.20
RUNTIME_BASE = "tile_layer_base_deep_recess"
MATERIAL_NAME = "concrete_top"
OBJECT_NAME = "concrete_brutalist_cap"
MESH_NAME = "source_precast_panel_surface_mesh"
REPORT_PREFIX = "CONCRETE_TILE_SURFACE_REPORT="


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in values
    ]
    return (*linear, 1.0)


def semantic_material() -> bpy.types.Material:
    material = bpy.data.materials.new(name=MATERIAL_NAME)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = srgb("C8C5BC")
    shader.inputs["Roughness"].default_value = 0.92
    shader.inputs["Metallic"].default_value = 0.0
    return material


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return lower, upper


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(
        max(0, len(polygon.vertices) - 2)
        for polygon in obj.data.polygons
    )


def connected_component_count(obj: bpy.types.Object) -> int:
    adjacency: list[set[int]] = [set() for _vertex in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    remaining = set(range(len(adjacency)))
    components = 0
    while remaining:
        components += 1
        stack = [remaining.pop()]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
    return components


def apply_object_transform(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def normalize_geometry(obj: bpy.types.Object) -> dict:
    lower, upper = object_bounds(obj)
    dimensions = upper - lower
    if min(dimensions) <= 1.0e-6:
        raise RuntimeError(
            f"Concrete source has a degenerate bounding box: {lower} .. {upper}"
    )
    center_x = (lower.x + upper.x) * 0.5
    center_y = (lower.y + upper.y) * 0.5
    scale_x = TILE / dimensions.x
    scale_y = TILE / dimensions.y
    scale_z = abs(SURFACE_BOTTOM) / dimensions.z
    for vertex in obj.data.vertices:
        vertex.co.x = (vertex.co.x - center_x) * scale_x
        vertex.co.y = (vertex.co.y - center_y) * scale_y
        vertex.co.z = (vertex.co.z - upper.z) * scale_z

    obj.data.update()
    bpy.context.view_layer.update()
    return {
        "x_scale": round(scale_x, 8),
        "y_scale": round(scale_y, 8),
        "z_scale": round(scale_z, 8),
        "xy_scale_difference_percent": round(
            abs(scale_x - scale_y) / ((scale_x + scale_y) * 0.5) * 100.0,
            5,
        ),
        "z_to_xy_mean_scale_ratio": round(
            scale_z / ((scale_x + scale_y) * 0.5), 6
        ),
        "source_dimensions_after_regularization": [
            round(value, 6) for value in dimensions
        ],
    }


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing concrete source: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest().upper()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            "Concrete source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    if not source_meshes:
        raise RuntimeError("Concrete source contains no mesh")
    source = max(source_meshes, key=triangle_count)
    source_name = source.name
    source_triangles = triangle_count(source)
    source_vertices = len(source.data.vertices)
    source_polygons = len(source.data.polygons)
    source_smooth_polygons = sum(
        1 for polygon in source.data.polygons if polygon.use_smooth
    )
    if source_smooth_polygons != 0:
        raise RuntimeError(
            "Revised concrete source is expected to be fully flat-shaded, "
            f"but {source_smooth_polygons} polygons are smooth"
        )
    source_materials = [
        material.name for material in source.data.materials if material is not None
    ]
    source_image_count = len(bpy.data.images)
    discarded_helper_count = 0
    for obj in source_meshes:
        if obj == source:
            continue
        discarded_helper_count += 1
        bpy.data.objects.remove(obj, do_unlink=True)

    apply_object_transform(source)
    regularization_report = regularize_constructed_surface(
        source,
        ConstructedRegularizationConfig(
            top_normal_min=0.45,
            min_patch_area_ratio=0.04,
            top_patch_max_drop_ratio=0.35,
            max_top_patches=4,
            wall_propagation_ratio=0.0,
            dominant_axis_override_degrees=0.0,
            flatten_top_patches=True,
            align_patch_heights=True,
            straighten_patch_boundaries=True,
            rebuild_side_walls=True,
            force_flat_shading=True,
        ),
    )
    normalization_report = normalize_geometry(source)
    source.name = OBJECT_NAME
    source.data.name = MESH_NAME
    source.data.materials.clear()
    source.data.materials.append(semantic_material())
    for polygon in source.data.polygons:
        polygon.material_index = 0

    lower, upper = object_bounds(source)
    epsilon = 0.001
    if (
        abs(lower.x + TILE * 0.5) > epsilon
        or abs(upper.x - TILE * 0.5) > epsilon
        or abs(lower.y + TILE * 0.5) > epsilon
        or abs(upper.y - TILE * 0.5) > epsilon
        or abs(lower.z - SURFACE_BOTTOM) > epsilon
        or abs(upper.z) > epsilon
    ):
        raise RuntimeError(
            "Normalized concrete surface is outside the tile contract: "
            f"{lower} .. {upper}"
        )
    if any(
        not math.isfinite(component)
        for vertex in source.data.vertices
        for component in vertex.co
    ):
        raise RuntimeError("Concrete surface contains non-finite vertices")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
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
                "layer_role": "surface",
                "runtime_base": RUNTIME_BASE,
                "source_mesh_name": source_name,
                "source_mesh_count": len(source_meshes),
                "discarded_helper_meshes": discarded_helper_count,
                "source_materials_discarded": source_materials,
                "embedded_images_discarded": source_image_count,
                "source_triangles": source_triangles,
                "source_vertices": source_vertices,
                "source_polygons": source_polygons,
                "source_smooth_polygons": source_smooth_polygons,
                "regularization": regularization_report,
                "normalization": normalization_report,
                "output_triangles": triangle_count(source),
                "output_vertices": len(source.data.vertices),
                "output_polygons": len(source.data.polygons),
                "output_smooth_polygons": sum(
                    1 for polygon in source.data.polygons if polygon.use_smooth
                ),
                "topology_preserved": (
                    source_vertices == len(source.data.vertices)
                    and source_polygons == len(source.data.polygons)
                    and source_triangles == triangle_count(source)
                ),
                "smoothing_applied": False,
                "connected_components": connected_component_count(source),
                "bounds": {
                    "min": [round(value, 4) for value in lower],
                    "max": [round(value, 4) for value in upper],
                },
                "material": MATERIAL_NAME,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
