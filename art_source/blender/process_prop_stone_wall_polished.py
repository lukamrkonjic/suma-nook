"""Build the polished stone wall as an exact one-tile modular wall segment.

The imported mesh, material, and UVs stay authoritative.  The source's long
axis is Y, so it is first rotated onto game-local X, then given a restrained
proportion correction to the authored size required by Suma's runtime scale.
No remeshing, texture reprojection, or per-stone deformation is performed.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "prop_stone_wall_polished"
    / "stone-wall_source.glb"
)
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "prop_stone_wall_polished.glb"
EXPECTED_SOURCE_SHA256 = "2bf9a664c2b89b155f092434abdc8bc4ce22c9c8ac5e61fcbc86923a934c38ab"

# StructureVisualFactory applies world_model_scale=0.74074074 to ordinary
# placeables.  Height remains exactly one live tile.  Width includes a 0.059
# live-unit overlap so rounded end stones interpenetrate at adjacent module
# joins instead of revealing a background slit between their receding edges.
TARGET_SIZE = Vector((1.43, 0.70, 1.35))
MERGE_DISTANCE = 1.0e-6
DEGENERATE_DISTANCE = 1.0e-12
SMOOTH_ANGLE_DEG = 60.0
EPSILON = 1.0e-5


def _local_bounds(mesh: bpy.types.Mesh) -> tuple[Vector, Vector]:
    lower = Vector(tuple(min(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3)))
    upper = Vector(tuple(max(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3)))
    return lower, upper


def _uv_bounds(mesh: bpy.types.Mesh) -> tuple[float, float, float, float] | None:
    layer = mesh.uv_layers.active
    if layer is None or not layer.data:
        return None
    us = [loop.uv.x for loop in layer.data]
    vs = [loop.uv.y for loop in layer.data]
    return min(us), max(us), min(vs), max(vs)


def _triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(max(0, len(polygon.vertices) - 2) for polygon in mesh.polygons)


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing source GLB: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            f"Source hash mismatch: wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one mesh object, found {len(meshes)}")
    obj = meshes[0]
    obj.name = "StoneWallPolished"
    obj.data.name = "StoneWallPolishedMesh"

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    source_uv_bounds = _uv_bounds(obj.data)
    source_vertices = len(obj.data.vertices)
    source_triangles = _triangle_count(obj.data)
    source_materials = [slot.material.name for slot in obj.material_slots]
    source_lower, source_upper = _local_bounds(obj.data)
    source_size = source_upper - source_lower

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=MERGE_DISTANCE)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=DEGENERATE_DISTANCE)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    # Blender source axes: X=thickness, Y=wall run, Z=height.  Rotate the
    # wall run onto X without changing topology or UV coordinates.
    for vertex in obj.data.vertices:
        source = vertex.co.copy()
        vertex.co = Vector((source.y, -source.x, source.z))
    obj.data.update()

    oriented_lower, oriented_upper = _local_bounds(obj.data)
    oriented_size = oriented_upper - oriented_lower
    scale = Vector(
        tuple(TARGET_SIZE[axis] / oriented_size[axis] for axis in range(3))
    )
    for vertex in obj.data.vertices:
        vertex.co.x *= scale.x
        vertex.co.y *= scale.y
        vertex.co.z *= scale.z
    obj.data.update()

    # Establish the placeable contract: exact bottom-centre pivot.
    scaled_lower, scaled_upper = _local_bounds(obj.data)
    centre = (scaled_lower + scaled_upper) * 0.5
    offset = Vector((-centre.x, -centre.y, -scaled_lower.z))
    for vertex in obj.data.vertices:
        vertex.co += offset
    obj.data.update()

    # Scaling changes face normals, so author them only after final geometry.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(SMOOTH_ANGLE_DEG),
        keep_sharp_edges=True,
    )

    final_lower, final_upper = _local_bounds(obj.data)
    final_size = final_upper - final_lower
    if max(abs(final_size[axis] - TARGET_SIZE[axis]) for axis in range(3)) > EPSILON:
        raise RuntimeError(f"Module bounds mismatch: {tuple(final_size)}")
    if abs(final_lower.z) > EPSILON:
        raise RuntimeError(f"Wall is not grounded: lower Z is {final_lower.z}")
    if abs(final_lower.x + final_upper.x) > EPSILON:
        raise RuntimeError("Wall is not centered on X")
    if abs(final_lower.y + final_upper.y) > EPSILON:
        raise RuntimeError("Wall is not centered on Y")
    if _uv_bounds(obj.data) != source_uv_bounds:
        raise RuntimeError("Modular transform unexpectedly changed UV bounds")
    if [slot.material.name for slot in obj.material_slots] != source_materials:
        raise RuntimeError("Modular transform unexpectedly changed materials")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
    )

    print(
        json.dumps(
            {
                "source": str(SOURCE),
                "output": str(OUTPUT),
                "source_sha256": source_hash,
                "source_vertices": source_vertices,
                "output_vertices": len(obj.data.vertices),
                "source_triangles": source_triangles,
                "output_triangles": _triangle_count(obj.data),
                "source_dimensions": [round(value, 8) for value in source_size],
                "oriented_dimensions": [round(value, 8) for value in oriented_size],
                "scale_factors": [round(value, 8) for value in scale],
                "output_dimensions": [round(value, 8) for value in final_size],
                "output_bounds": {
                    "lower": [round(value, 8) for value in final_lower],
                    "upper": [round(value, 8) for value in final_upper],
                },
                "materials": source_materials,
                "uv_bounds_preserved": True,
                "smooth_angle_degrees": SMOOTH_ANGLE_DEG,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
