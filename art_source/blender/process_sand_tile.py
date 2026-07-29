"""Build the sand surface layer from Luka's generated dune.

The source GLB contains one low-poly sand mesh. Its useful information is the
actual asymmetric upper dune field; its generated block, hard facets, color,
and irregular underside are discarded. This processor:

* samples the real source top with vertical ray casts;
* regularizes it into a 41 x 41 height field;
* applies three light Taubin passes, one local relaxation pass, and a restrained
  contour-following filter that softens facets without erasing the dunes;
* blends only the outer 16% to a shared zero-height edge so repeated tiles meet;
* adds a short sand-colored cap skirt down to the standard body seam;
* exports only that replaceable surface layer.

The runtime mounts the resulting GLB on ``tile_layer_base_standard``. Keeping
the structural base separate means this source processor never has to copy or
join a body mesh, and future surface revisions cannot change gameplay depth.

Run from the repository root with Blender 5.x:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_sand_tile.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source" / "imported" / "sand_tile" / "sand_tile_source_v3.glb"
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "tile_layer_surface_sand.glb"
EXPECTED_SOURCE_SHA256 = (
    "429444B1DA517DF193CE6BAEA469436AB62F86482B9C088D876620FC91F169F8"
)
ASSET_LABEL = "sand"
MATERIAL_NAME = "sand_top"
CAP_OBJECT_NAME = "sand_cap"
CAP_MESH_NAME = "smoothed_source_dune_cap_mesh"
REPORT_PREFIX = "SAND_TILE_SURFACE_REPORT="

TILE = 1.70
# Connected terrain reaches the exact slot boundary. A deliberate gap here
# exposes the cap skirt in a 3x3 patch and reads as a dark artificial grid.
CAP_SPAN = TILE
CAP_BOTTOM = -0.055
EDGE_HEIGHT = 0.0
GRID_SIZE = 41
EDGE_BLEND_FRACTION = 0.16
INTERIOR_BASE_HEIGHT = 0.004
RELIEF_AMPLITUDE = 0.060
RELIEF_EXPONENT = 1.10
TAUBIN_ITERATIONS = 3
TAUBIN_LAMBDA = 0.45
TAUBIN_MU = -0.48
GAUSSIAN_PASSES = 1
CONTOUR_SMOOTHING_PASSES = 3
CONTOUR_SMOOTHING_BLEND = 0.60
CONTOUR_SAMPLE_SPACING = 1.35
SMOOTH_ANGLE_DEG = 60.0

PALETTE = {
    "sand_top": "D1BD9E",
}


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in values
    ]
    return (*linear, 1.0)


def semantic_material(name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = srgb(PALETTE[name])
    shader.inputs["Roughness"].default_value = 0.88
    shader.inputs["Metallic"].default_value = 0.0
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
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


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = max(0.0, min(1.0, fraction)) * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def sample_source_height_field(
    source: bpy.types.Object,
) -> tuple[list[list[float]], int]:
    lower, upper = object_bounds(source)
    inset = min(0.003, min(upper.x - lower.x, upper.y - lower.y) * 0.002)
    x_min = lower.x + inset
    x_max = upper.x - inset
    y_min = lower.y + inset
    y_max = upper.y - inset
    ray_start = upper.z + max(0.5, upper.z - lower.z)
    ray_length = ray_start - lower.z + 1.0

    result: list[list[float]] = []
    misses = 0
    for row in range(GRID_SIZE):
        v = row / float(GRID_SIZE - 1)
        y = y_min + (y_max - y_min) * v
        heights: list[float] = []
        for column in range(GRID_SIZE):
            u = column / float(GRID_SIZE - 1)
            x = x_min + (x_max - x_min) * u
            hit, location, _normal, _face_index = source.ray_cast(
                Vector((x, y, ray_start)),
                Vector((0.0, 0.0, -1.0)),
                distance=ray_length,
            )
            if not hit:
                misses += 1
                heights.append(float("nan"))
            else:
                heights.append(location.z)
        result.append(heights)
    # The generated source has slightly rounded footprint corners, so a few
    # square-grid rays can land just outside it. Those points are all within
    # the later edge-blend zone; extend the nearest valid source height into
    # them instead of shrinking or recentering the dune.
    if misses:
        valid = [
            (row, column, result[row][column])
            for row in range(GRID_SIZE)
            for column in range(GRID_SIZE)
            if math.isfinite(result[row][column])
        ]
        for row in range(GRID_SIZE):
            for column in range(GRID_SIZE):
                if math.isfinite(result[row][column]):
                    continue
                _nearest_row, _nearest_column, nearest_height = min(
                    valid,
                    key=lambda entry: (
                        (entry[0] - row) ** 2
                        + (entry[1] - column) ** 2
                    ),
                )
                result[row][column] = nearest_height
    return result, misses


def laplacian_step(
    heights: list[list[float]],
    factor: float,
) -> list[list[float]]:
    size = len(heights)
    output = [row[:] for row in heights]
    for row in range(1, size - 1):
        for column in range(1, size - 1):
            cardinal_average = (
                heights[row - 1][column]
                + heights[row + 1][column]
                + heights[row][column - 1]
                + heights[row][column + 1]
            ) * 0.25
            output[row][column] = (
                heights[row][column]
                + factor * (cardinal_average - heights[row][column])
            )
    return output


def bilinear_height(
    heights: list[list[float]],
    row_position: float,
    column_position: float,
) -> float:
    size = len(heights)
    row_position = max(0.0, min(size - 1.0, row_position))
    column_position = max(0.0, min(size - 1.0, column_position))
    row_low = int(math.floor(row_position))
    row_high = min(size - 1, row_low + 1)
    column_low = int(math.floor(column_position))
    column_high = min(size - 1, column_low + 1)
    row_weight = row_position - row_low
    column_weight = column_position - column_low
    lower = (
        heights[row_low][column_low] * (1.0 - column_weight)
        + heights[row_low][column_high] * column_weight
    )
    upper = (
        heights[row_high][column_low] * (1.0 - column_weight)
        + heights[row_high][column_high] * column_weight
    )
    return lower * (1.0 - row_weight) + upper * row_weight


def contour_smoothing_step(
    heights: list[list[float]],
) -> list[list[float]]:
    """Smooth along local height contours instead of across every dune.

    Each cell derives a tangent from its own height gradient, so curved dunes
    lengthen along different directions rather than becoming one uniform set
    of parallel waves.
    """
    size = len(heights)
    output = [row[:] for row in heights]
    kernel = (1.0, 4.0, 6.0, 4.0, 1.0)
    for row in range(1, size - 1):
        for column in range(1, size - 1):
            gradient_column = (
                heights[row][column + 1]
                - heights[row][column - 1]
            ) * 0.5
            gradient_row = (
                heights[row + 1][column]
                - heights[row - 1][column]
            ) * 0.5
            magnitude = math.hypot(gradient_column, gradient_row)
            if magnitude < 1.0e-8:
                continue
            tangent_column = -gradient_row / magnitude
            tangent_row = gradient_column / magnitude
            tangent_average = 0.0
            for offset in range(-2, 3):
                distance = offset * CONTOUR_SAMPLE_SPACING
                tangent_average += kernel[offset + 2] * bilinear_height(
                    heights,
                    row + tangent_row * distance,
                    column + tangent_column * distance,
                )
            tangent_average /= 16.0
            output[row][column] = (
                heights[row][column] * (1.0 - CONTOUR_SMOOTHING_BLEND)
                + tangent_average * CONTOUR_SMOOTHING_BLEND
            )
    return output


def smooth_height_field(heights: list[list[float]]) -> list[list[float]]:
    smoothed = [row[:] for row in heights]
    for _iteration in range(TAUBIN_ITERATIONS):
        smoothed = laplacian_step(smoothed, TAUBIN_LAMBDA)
        smoothed = laplacian_step(smoothed, TAUBIN_MU)
    # One separable five-tap binomial pass softens local polygon transitions
    # without altering the source's broad dune layout or smaller folds.
    kernel = (1.0, 4.0, 6.0, 4.0, 1.0)
    radius = len(kernel) // 2
    size = len(smoothed)
    for _iteration in range(GAUSSIAN_PASSES):
        horizontal = [[0.0 for _column in range(size)] for _row in range(size)]
        for row in range(size):
            for column in range(size):
                horizontal[row][column] = sum(
                    kernel[offset + radius]
                    * smoothed[row][max(0, min(size - 1, column + offset))]
                    for offset in range(-radius, radius + 1)
                ) / 16.0
        vertical = [[0.0 for _column in range(size)] for _row in range(size)]
        for row in range(size):
            for column in range(size):
                vertical[row][column] = sum(
                    kernel[offset + radius]
                    * horizontal[max(0, min(size - 1, row + offset))][column]
                    for offset in range(-radius, radius + 1)
                ) / 16.0
        smoothed = vertical
    for _iteration in range(CONTOUR_SMOOTHING_PASSES):
        smoothed = contour_smoothing_step(smoothed)
    return smoothed


def smoothstep(value: float) -> float:
    clamped = max(0.0, min(1.0, value))
    return clamped * clamped * (3.0 - 2.0 * clamped)


def normalized_dune_heights(
    sampled: list[list[float]],
) -> list[list[float]]:
    smoothed = smooth_height_field(sampled)
    values = [height for row in smoothed for height in row]
    low = percentile(values, 0.05)
    high = percentile(values, 0.98)
    span = max(high - low, 0.0001)
    result: list[list[float]] = []
    for row in range(GRID_SIZE):
        heights: list[float] = []
        v = row / float(GRID_SIZE - 1)
        for column in range(GRID_SIZE):
            u = column / float(GRID_SIZE - 1)
            normalized = max(
                0.0,
                min(1.0, (smoothed[row][column] - low) / span),
            )
            # Keep the source's height relationships unchanged.
            normalized = normalized ** RELIEF_EXPONENT
            distance_to_edge = min(u, 1.0 - u, v, 1.0 - v)
            edge_weight = smoothstep(
                distance_to_edge / EDGE_BLEND_FRACTION
            )
            height = (
                EDGE_HEIGHT
                + edge_weight
                * (INTERIOR_BASE_HEIGHT + normalized * RELIEF_AMPLITUDE)
            )
            heights.append(height)
        result.append(heights)
    return result


def perimeter_indices() -> list[int]:
    size = GRID_SIZE
    indices: list[int] = []
    indices.extend(range(size))
    indices.extend(row * size + (size - 1) for row in range(1, size))
    indices.extend(
        (size - 1) * size + column
        for column in range(size - 2, -1, -1)
    )
    indices.extend(row * size for row in range(size - 2, 0, -1))
    return indices


def create_dune_cap(heights: list[list[float]]) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    half_span = CAP_SPAN * 0.5

    for row in range(GRID_SIZE):
        v = row / float(GRID_SIZE - 1)
        y = -half_span + CAP_SPAN * v
        for column in range(GRID_SIZE):
            u = column / float(GRID_SIZE - 1)
            x = -half_span + CAP_SPAN * u
            vertices.append((x, y, heights[row][column]))

    for row in range(GRID_SIZE - 1):
        for column in range(GRID_SIZE - 1):
            lower_left = row * GRID_SIZE + column
            faces.append(
                (
                    lower_left,
                    lower_left + 1,
                    lower_left + GRID_SIZE + 1,
                    lower_left + GRID_SIZE,
                )
            )

    perimeter = perimeter_indices()
    bottom_start = len(vertices)
    for top_index in perimeter:
        x, y, _z = vertices[top_index]
        vertices.append((x, y, CAP_BOTTOM))
    for index, top_index in enumerate(perimeter):
        next_index = (index + 1) % len(perimeter)
        faces.append(
            (
                top_index,
                bottom_start + index,
                bottom_start + next_index,
                perimeter[next_index],
            )
        )

    mesh = bpy.data.meshes.new(CAP_MESH_NAME)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    cap = bpy.data.objects.new(CAP_OBJECT_NAME, mesh)
    bpy.context.scene.collection.objects.link(cap)
    mesh.materials.append(semantic_material(MATERIAL_NAME))
    for polygon in mesh.polygons:
        polygon.material_index = 0

    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (
                vertex.x / CAP_SPAN + 0.5,
                vertex.y / CAP_SPAN + 0.5,
            )

    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    bpy.context.view_layer.objects.active = cap
    try:
        bpy.ops.object.shade_smooth_by_angle(
            angle=math.radians(SMOOTH_ANGLE_DEG),
            keep_sharp_edges=True,
        )
    except Exception:
        bpy.ops.object.shade_smooth()
    return cap


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing {ASSET_LABEL} source: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest().upper()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            f"{ASSET_LABEL.title()} source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    if not source_meshes:
        raise RuntimeError(
            f"Replacement {ASSET_LABEL} source does not contain a mesh"
        )
    # Select the most detailed component deterministically. The current source
    # contains one mesh; the guard keeps future exporter helpers from affecting
    # the sampled top surface.
    source = max(source_meshes, key=triangle_count)
    source_mesh_name = source.name
    source_triangles = triangle_count(source)
    discarded_helper_count = sum(
        1 for obj in source_meshes if obj != source
    )
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    sampled, filled_sample_count = sample_source_height_field(source)
    dune_heights = normalized_dune_heights(sampled)
    for obj in source_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)

    cap = create_dune_cap(dune_heights)
    cap_lower, cap_upper = object_bounds(cap)
    epsilon = 0.001
    if (
        abs(cap_lower.x + CAP_SPAN * 0.5) > epsilon
        or abs(cap_upper.x - CAP_SPAN * 0.5) > epsilon
        or abs(cap_lower.y + CAP_SPAN * 0.5) > epsilon
        or abs(cap_upper.y - CAP_SPAN * 0.5) > epsilon
        or abs(cap_lower.z - CAP_BOTTOM) > epsilon
        or cap_upper.z > INTERIOR_BASE_HEIGHT + RELIEF_AMPLITUDE * 1.09
    ):
        raise RuntimeError(
            "Smoothed dune cap is outside its production envelope: "
            f"{cap_lower} .. {cap_upper}"
        )
    if any(
        not math.isfinite(component)
        for vertex in cap.data.vertices
        for component in vertex.co
    ):
        raise RuntimeError("Smoothed dune cap contains non-finite vertices")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    bpy.context.view_layer.objects.active = cap
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
                "runtime_base": "tile_layer_base_standard",
                "source_height_field_retained": True,
                "discarded_generated_block": True,
                "source_mesh_count": len(source_meshes),
                "source_mesh_name": source_mesh_name,
                "discarded_helper_meshes": discarded_helper_count,
                "grid_size": GRID_SIZE,
                "perimeter_samples_filled": filled_sample_count,
                "taubin_iterations": TAUBIN_ITERATIONS,
                "gaussian_passes": GAUSSIAN_PASSES,
                "contour_smoothing_passes": CONTOUR_SMOOTHING_PASSES,
                "contour_smoothing_blend": CONTOUR_SMOOTHING_BLEND,
                "contour_sample_spacing": CONTOUR_SAMPLE_SPACING,
                "relief_exponent": RELIEF_EXPONENT,
                "edge_blend_fraction": EDGE_BLEND_FRACTION,
                "authored_inter_tile_gap": round(TILE - CAP_SPAN, 4),
                "source_triangles": source_triangles,
                "output_triangles": sum(
                    max(0, len(polygon.vertices) - 2)
                    for polygon in cap.data.polygons
                ),
                "cap_bounds": {
                    "min": [round(value, 4) for value in cap_lower],
                    "max": [round(value, 4) for value in cap_upper],
                },
                "material": MATERIAL_NAME,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
