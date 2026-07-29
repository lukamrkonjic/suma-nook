"""Build Suma's grass tile from Luka's second faceted foliage source.

The supplied GLB contains a strong layered foliage composition and a disposable
generated block.  This processor preserves the source foliage arrangement,
proportions, UVs, textures, and material variation while:

* separating the generated block and perimeter surfaces from the foliage;
* welding only coincident source vertices;
* removing isolated one-to-three-triangle export fragments;
* applying a restrained smooth-by-angle normals pass without moving vertices;
* fitting the polished top to the complete Suma square footprint;
* preserving the source color breakup and embedded textures;
* mounting it on a clean grass cap and the standard earthy tile body.

Run from the repository root with Blender 5.x:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_grass_tile.py
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
    / "grass_tile_source_v2.glb"
)
BASE_SOURCE = ROOT / "assets" / "3d" / "reworked" / "tile_sand.glb"
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "tile_grass.glb"
EXPECTED_SOURCE_SHA256 = (
    "5696144AF826C61DE668621FA1EA69268BBB8F6110767413EDF93BC097013967"
)

TILE = 1.70
CAP_BOTTOM = -0.055
FOLIAGE_EDGE_MARGIN = 0.0
FOLIAGE_BASE_Z = 0.010
FOLIAGE_SOURCE_MIN_TOP = 0.025
FOLIAGE_SOURCE_MAX_HORIZONTAL_SPAN = 0.35
WELD_DISTANCE = 0.00075
MIN_RECOVERED_COMPONENT_TRIANGLES = 4
SMOOTH_ANGLE_DEGREES = 55.0
FOLIAGE_HEIGHT_SCALE = 1.0

shared.PALETTE = {
    "grass_ground": "708C4B",
    "earth_mid": "8A5B35",
}
shared.BASE_SOURCE = BASE_SOURCE
shared.BODY_MATERIAL_NAME = "earth_mid"
shared.BODY_OBJECT_NAME = "grass_body"
shared.BODY_MESH_NAME = "clean_standard_grass_body_mesh"


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lower = Vector(
        tuple(min(point[axis] for point in points) for axis in range(3))
    )
    upper = Vector(
        tuple(max(point[axis] for point in points) for axis in range(3))
    )
    return lower, upper


def triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def is_foliage_source_component(obj: bpy.types.Object) -> bool:
    lower, upper = object_bounds(obj)
    size = upper - lower
    return (
        upper.z > FOLIAGE_SOURCE_MIN_TOP
        and max(size.x, size.y) < FOLIAGE_SOURCE_MAX_HORIZONTAL_SPAN
    )


def join_objects(
    objects: list[bpy.types.Object],
    active: bpy.types.Object | None = None,
) -> bpy.types.Object:
    if not objects:
        raise RuntimeError("No objects supplied for joining")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]
    bpy.ops.object.join()
    return bpy.context.active_object


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


def prepare_foliage(
    source_meshes: list[bpy.types.Object],
) -> tuple[bpy.types.Object, dict[str, int]]:
    detailed = max(source_meshes, key=triangle_count)
    bpy.ops.object.select_all(action="DESELECT")
    detailed.select_set(True)
    bpy.context.view_layer.objects.active = detailed
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    source_components = separate_loose(detailed)
    foliage_components = [
        obj for obj in source_components if is_foliage_source_component(obj)
    ]
    if not foliage_components:
        raise RuntimeError("No foliage components survived source separation")
    selected_source_triangles = sum(
        triangle_count(obj) for obj in foliage_components
    )

    foliage = join_objects(foliage_components)
    foliage.name = "grass_foliage_raw"
    foliage.data.name = "source_grass_foliage_mesh"

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=WELD_DISTANCE)
    bpy.ops.object.mode_set(mode="OBJECT")

    recovered_components = separate_loose(foliage)
    kept_components = [
        obj
        for obj in recovered_components
        if triangle_count(obj) >= MIN_RECOVERED_COMPONENT_TRIANGLES
    ]
    removed_fragments = len(recovered_components) - len(kept_components)
    if not kept_components:
        raise RuntimeError("Foliage repair removed every recovered component")
    foliage = join_objects(kept_components)
    foliage.name = "grass_foliage"
    foliage.data.name = "rounded_source_grass_foliage_mesh"

    for material in foliage.data.materials:
        if material is None:
            continue
        material.name = "grass_foliage_textured"
        material.use_backface_culling = False
        if material.use_nodes and material.node_tree is not None:
            principled = next(
                (
                    node
                    for node in material.node_tree.nodes
                    if node.type == "BSDF_PRINCIPLED"
                ),
                None,
            )
            if principled is not None:
                roughness = principled.inputs.get("Roughness")
                if roughness is not None and not roughness.is_linked:
                    roughness.default_value = 0.86

    bpy.context.view_layer.objects.active = foliage
    try:
        bpy.ops.object.shade_smooth_by_angle(
            angle=math.radians(SMOOTH_ANGLE_DEGREES),
            keep_sharp_edges=True,
        )
    except Exception:
        bpy.ops.object.shade_smooth()

    triangulate = foliage.modifiers.new(
        name="stable_foliage_triangulation",
        type="TRIANGULATE",
    )
    triangulate.quad_method = "BEAUTY"
    triangulate.ngon_method = "BEAUTY"
    bpy.ops.object.modifier_apply(modifier=triangulate.name)

    lower, upper = object_bounds(foliage)
    target_span = TILE - FOLIAGE_EDGE_MARGIN * 2.0
    scale_x = target_span / (upper.x - lower.x)
    scale_y = target_span / (upper.y - lower.y)
    scale_z = (scale_x + scale_y) * 0.5 * FOLIAGE_HEIGHT_SCALE
    center = (lower + upper) * 0.5
    for vertex in foliage.data.vertices:
        position = foliage.matrix_world @ vertex.co
        position.x = (position.x - center.x) * scale_x
        position.y = (position.y - center.y) * scale_y
        position.z = (
            (position.z - lower.z) * scale_z + FOLIAGE_BASE_Z
        )
        vertex.co = foliage.matrix_world.inverted() @ position
    foliage.data.update()

    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and obj is not foliage:
            bpy.data.objects.remove(obj, do_unlink=True)

    return foliage, {
        "source_component_count": len(source_components),
        "selected_source_component_count": len(foliage_components),
        "selected_source_triangles": selected_source_triangles,
        "recovered_component_count": len(recovered_components),
        "removed_fragment_count": removed_fragments,
        "kept_component_count": len(kept_components),
    }


def create_flat_cap() -> bpy.types.Object:
    half = TILE * 0.5
    vertices = [
        (-half, -half, CAP_BOTTOM),
        (half, -half, CAP_BOTTOM),
        (half, half, CAP_BOTTOM),
        (-half, half, CAP_BOTTOM),
        (-half, -half, 0.0),
        (half, -half, 0.0),
        (half, half, 0.0),
        (-half, half, 0.0),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new("clean_standard_grass_cap_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    cap = bpy.data.objects.new("grass_cap", mesh)
    bpy.context.scene.collection.objects.link(cap)
    mesh.materials.append(shared.semantic_material("grass_ground"))
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (
                vertex.x / TILE + 0.5,
                vertex.y / TILE + 0.5,
            )
    return cap


def validate(
    body: bpy.types.Object,
    cap: bpy.types.Object,
    foliage: bpy.types.Object,
) -> dict[str, tuple[Vector, Vector]]:
    bounds = {
        "body": object_bounds(body),
        "cap": object_bounds(cap),
        "foliage": object_bounds(foliage),
    }
    epsilon = 0.002
    body_lower, body_upper = bounds["body"]
    cap_lower, cap_upper = bounds["cap"]
    foliage_lower, foliage_upper = bounds["foliage"]
    if (
        abs(body_lower.x + TILE * 0.5) > epsilon
        or abs(body_upper.x - TILE * 0.5) > epsilon
        or abs(body_lower.y + TILE * 0.5) > epsilon
        or abs(body_upper.y - TILE * 0.5) > epsilon
        or abs(body_lower.z + 0.5) > epsilon
        or abs(body_upper.z - CAP_BOTTOM) > epsilon
    ):
        raise RuntimeError(
            "Standard grass body is outside its contract: "
            f"{body_lower} .. {body_upper}"
        )
    if (
        abs(cap_lower.x + TILE * 0.5) > epsilon
        or abs(cap_upper.x - TILE * 0.5) > epsilon
        or abs(cap_lower.y + TILE * 0.5) > epsilon
        or abs(cap_upper.y - TILE * 0.5) > epsilon
        or abs(cap_lower.z - CAP_BOTTOM) > epsilon
        or abs(cap_upper.z) > epsilon
    ):
        raise RuntimeError(
            "Grass cap is outside its contract: "
            f"{cap_lower} .. {cap_upper}"
        )
    expected_edge = TILE * 0.5 - FOLIAGE_EDGE_MARGIN
    if (
        abs(foliage_lower.x + expected_edge) > epsilon
        or abs(foliage_upper.x - expected_edge) > epsilon
        or abs(foliage_lower.y + expected_edge) > epsilon
        or abs(foliage_upper.y - expected_edge) > epsilon
        or foliage_lower.z < 0.0
        or foliage_upper.z > 0.50
    ):
        raise RuntimeError(
            "Rounded foliage is outside its production envelope: "
            f"{foliage_lower} .. {foliage_upper}"
        )
    for obj in (body, cap, foliage):
        if any(
            not math.isfinite(component)
            for vertex in obj.data.vertices
            for component in vertex.co
        ):
            raise RuntimeError(f"{obj.name} contains non-finite vertices")
    return bounds


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing grass source: {SOURCE}")
    if not BASE_SOURCE.is_file():
        raise FileNotFoundError(
            f"Missing standardized Suma tile body: {BASE_SOURCE}"
        )
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
    source_triangles = sum(triangle_count(obj) for obj in source_meshes)
    foliage, recovery = prepare_foliage(source_meshes)

    body = shared.import_standard_body()
    cap = create_flat_cap()
    bounds = validate(body, cap, foliage)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (body, cap, foliage):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = foliage
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

    def rounded_bounds(
        values: tuple[Vector, Vector],
    ) -> dict[str, list[float]]:
        return {
            "min": [round(value, 4) for value in values[0]],
            "max": [round(value, 4) for value in values[1]],
        }

    print(
        "ROUNDED_GRASS_TILE_REPORT="
        + json.dumps(
            {
                "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": source_hash,
                "output": str(OUTPUT.relative_to(ROOT)),
                "source_triangles": source_triangles,
                **recovery,
                "smooth_by_angle_degrees": SMOOTH_ANGLE_DEGREES,
                "foliage_height_scale": FOLIAGE_HEIGHT_SCALE,
                "output_foliage_triangles": triangle_count(foliage),
                "body_bounds": rounded_bounds(bounds["body"]),
                "cap_bounds": rounded_bounds(bounds["cap"]),
                "foliage_bounds": rounded_bounds(bounds["foliage"]),
                "material_contract": (
                    "source foliage textures + grass_ground cap + earth_mid body"
                ),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
