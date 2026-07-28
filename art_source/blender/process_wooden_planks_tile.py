"""Mount the polished original four-plank cap on a standardized Suma tile.

The authored plank design comes directly from Luka's hash-pinned generated GLB.
Its noisy lower block is cut away; the real four-plank upper surface, spacing,
rounded shoulders, UVs, and embedded material are retained.  The extracted cap
receives the successful normals-only polish used for the other imported props:

* weld coincident scan vertices;
* remove harmless planar scan triangulation;
* recalculate consistent normals;
* shade smooth by angle at 60 degrees without moving the silhouette.

The polished original cap is fitted nearly edge-to-edge into Suma's standard
surface slot and mounted on the clean structural body copied from
``tile_grass``:

    clean body:   z = -0.500 .. -0.055 m
    plank cap:    z = -0.055 ..  0.000 m

Run from the repository root with Blender 5.x:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_wooden_planks_tile.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT / "art_source" / "imported" / "wooden_planks" / "wooden_planks_source.glb"
)
BASE_SOURCE = ROOT / "assets" / "3d" / "reworked" / "tile_grass.glb"
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "tile_wooden_planks.glb"
EXPECTED_SOURCE_SHA256 = (
    "6157e17e003697ca41e56126b4a4887cd18f5ec6494aadf05420d8896f091f00"
)

TILE = 1.70
# Leave only a 1 mm safety margin per side.  The previous 15 mm margin exposed
# a 30 mm strip of dark body material between neighbours, which ambient
# occlusion turned into a black trench unlike GG's soft tile separation.
CAP_SPAN = TILE - 0.002
CAP_BOTTOM = -0.055
CAP_TOP = 0.0
PLANK_CUT_RATIO = 0.757
MERGE_DISTANCE = 0.0008
DISSOLVE_ANGLE_DEG = 5.0
SMOOTH_ANGLE_DEG = 60.0

PALETTE = {
    "wood_primary": "A76D2D",
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
    shader.inputs["Roughness"].default_value = 0.78
    shader.inputs["Metallic"].default_value = 0.0
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return lower, upper


def extract_original_cap(source: bpy.types.Object) -> tuple[bpy.types.Object, int]:
    """Cut away the generated block while retaining the real four-board layer."""
    source.name = "planks_cap"
    source.data.name = "original_four_planks_cap_mesh"
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source

    # The GLB duplicates vertices along normals and UV boundaries.  Welding
    # only coincident positions reconstructs the intended scan topology without
    # moving or simplifying the authored four-plank surface.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=MERGE_DISTANCE)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    source.data.update()

    local_lower = min(vertex.co.z for vertex in source.data.vertices)
    local_upper = max(vertex.co.z for vertex in source.data.vertices)
    cut_z = local_lower + (local_upper - local_lower) * PLANK_CUT_RATIO

    # Bisect faces at a single horizontal plane rather than deleting whole
    # triangles by centroid.  This produces a clean, deterministic lower edge
    # and avoids the ragged scan artifacts that were visible on the old block.
    mesh = source.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.bisect_plane(
        bm,
        geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        dist=0.00001,
        plane_co=Vector((0.0, 0.0, cut_z)),
        plane_no=Vector((0.0, 0.0, 1.0)),
        clear_inner=True,
        clear_outer=False,
    )
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    if len(mesh.polygons) < 300:
        raise RuntimeError(
            "Original plank extraction retained too little source geometry: "
            f"{len(mesh.polygons)} faces"
        )

    # Collapse only coplanar scan edges.  Material and UV boundaries are
    # explicit delimiters so the original embedded texture remains unchanged.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.tris_convert_to_quads(
        face_threshold=math.radians(DISSOLVE_ANGLE_DEG),
        shape_threshold=math.radians(DISSOLVE_ANGLE_DEG),
    )
    bpy.ops.mesh.dissolve_limited(
        angle_limit=math.radians(DISSOLVE_ANGLE_DEG),
        delimit={"MATERIAL", "UV", "NORMAL"},
    )
    bpy.ops.mesh.normals_make_consistent(inside=False)
    # glTF is triangle-based and the retained source material includes a normal
    # texture.  Re-triangulate the cleaned broad polygons deterministically so
    # Blender can export valid tangents instead of falling back at import time.
    bpy.ops.mesh.quads_convert_to_tris(
        quad_method="BEAUTY",
        ngon_method="BEAUTY",
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    # This is the prior successful "normals-only polish": no remesh, bevel,
    # smoothing displacement, or primitive reconstruction.  Broad curves shade
    # smoothly while the meaningful plank gaps and sharper corners remain.
    try:
        bpy.ops.object.shade_smooth_by_angle(
            angle=math.radians(SMOOTH_ANGLE_DEG),
            keep_sharp_edges=True,
        )
    except Exception:
        bpy.ops.object.shade_smooth()
    return source, len(mesh.polygons)


def fit_cap_to_tile(cap: bpy.types.Object) -> None:
    """Preserve X/Y proportions while fitting the cap into the shared slot."""
    lower, upper = object_bounds(cap)
    size = upper - lower
    center = (lower + upper) * 0.5
    horizontal_scale = min(CAP_SPAN / size.x, CAP_SPAN / size.y)
    scale = Matrix.Diagonal(
        Vector(
            (
                horizontal_scale,
                horizontal_scale,
                (CAP_TOP - CAP_BOTTOM) / size.z,
            )
        )
    ).to_4x4()
    cap.matrix_world = (
        Matrix.Translation(Vector((0.0, 0.0, CAP_TOP)))
        @ scale
        @ Matrix.Translation(Vector((-center.x, -center.y, -upper.z)))
        @ cap.matrix_world
    )


def import_standard_body() -> bpy.types.Object:
    before_import = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(BASE_SOURCE))
    imported = [
        obj
        for obj in bpy.context.scene.objects
        if obj not in before_import and obj.type == "MESH"
    ]
    body_candidates = [
        obj for obj in imported if obj.name.lower().endswith("_body")
    ]
    if len(body_candidates) != 1:
        raise RuntimeError(
            f"Expected one standardized body mesh, found {len(body_candidates)}"
        )
    body = body_candidates[0]
    for obj in imported:
        if obj != body:
            bpy.data.objects.remove(obj, do_unlink=True)
    body.name = "planks_body"
    body.data.name = "clean_standard_tile_body_mesh"
    body.data.materials.clear()
    # This material is visible both on the clean block sides and in the tiny
    # valleys where rounded caps meet.  A mid warm wood keeps those creases
    # readable under SSAO without allowing them to collapse to near-black.
    body.data.materials.append(semantic_material("wood_primary"))
    for polygon in body.data.polygons:
        polygon.material_index = 0
    return body


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing wooden-planks source: {SOURCE}")
    if not BASE_SOURCE.is_file():
        raise FileNotFoundError(f"Missing standardized Suma tile body: {BASE_SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            "Wooden-planks source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    if len(source_meshes) != 1:
        raise RuntimeError(
            f"Expected one original source mesh, found {len(source_meshes)}"
        )
    source = source_meshes[0]
    source_triangles = sum(
        max(0, len(polygon.vertices) - 2)
        for polygon in source.data.polygons
    )
    original_materials = [
        material.name
        for material in source.data.materials
        if material is not None
    ]

    cap, polished_cap_faces = extract_original_cap(source)
    fit_cap_to_tile(cap)
    body = import_standard_body()

    # Validate the stable production body/cap contract before export.
    body_lower, body_upper = object_bounds(body)
    cap_lower, cap_upper = object_bounds(cap)
    epsilon = 0.001
    if (
        abs(body_lower.x + TILE * 0.5) > epsilon
        or abs(body_upper.x - TILE * 0.5) > epsilon
        or abs(body_lower.y + TILE * 0.5) > epsilon
        or abs(body_upper.y - TILE * 0.5) > epsilon
        or abs(body_lower.z + 0.5) > epsilon
        or abs(body_upper.z - CAP_BOTTOM) > epsilon
    ):
        raise RuntimeError(
            "Standardized body no longer matches the tile contract: "
            f"{body_lower} .. {body_upper}"
        )
    if (
        abs(cap_upper.z - CAP_TOP) > epsilon
        or abs(cap_lower.z - CAP_BOTTOM) > epsilon
        or cap_upper.x - cap_lower.x > TILE
        or cap_upper.y - cap_lower.y > TILE
    ):
        raise RuntimeError(
            "Original four-plank cap does not fit its surface slot: "
            f"{cap_lower} .. {cap_upper}"
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
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
        "PLANKS_COMPOSITE_REPORT="
        + json.dumps(
            {
                "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": source_hash,
                "base_source": str(BASE_SOURCE.relative_to(ROOT)),
                "output": str(OUTPUT.relative_to(ROOT)),
                "original_source_geometry_retained": True,
                "discarded_generated_base": True,
                "board_count": 4,
                "authored_inter_tile_gap": round(TILE - CAP_SPAN, 4),
                "exposed_body_material": "wood_primary",
                "source_materials_retained": original_materials,
                "polish": {
                    "merge_distance": MERGE_DISTANCE,
                    "planar_dissolve_angle_degrees": DISSOLVE_ANGLE_DEG,
                    "smooth_by_angle_degrees": SMOOTH_ANGLE_DEG,
                    "vertex_smoothing": False,
                    "remeshing": False,
                },
                "source_triangles": source_triangles,
                "polished_cap_faces": polished_cap_faces,
                "output_faces": len(body.data.polygons) + len(cap.data.polygons),
                "body_bounds": {
                    "min": [round(value, 4) for value in body_lower],
                    "max": [round(value, 4) for value in body_upper],
                },
                "cap_bounds": {
                    "min": [round(value, 4) for value in cap_lower],
                    "max": [round(value, 4) for value in cap_upper],
                },
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
