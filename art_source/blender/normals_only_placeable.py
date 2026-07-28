"""Shared, geometry-preserving polish pass for imported Suma placeables.

The pass intentionally does not remesh, smooth vertex positions, decimate, or
reconstruct the source. It only welds exactly coincident vertices, removes
degenerate faces, repairs face orientation, and authors 60-degree
smooth-by-angle normals. The final translation establishes Suma's placeable
contract: horizontally centred with the lowest point at ground level.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


MERGE_DISTANCE = 1.0e-6
DEGENERATE_DISTANCE = 1.0e-12
SMOOTH_ANGLE_DEG = 60.0
EPSILON = 1.0e-5


def _world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return lower, upper


def _uv_bounds(mesh: bpy.types.Mesh) -> tuple[float, float, float, float] | None:
    layer = mesh.uv_layers.active
    if layer is None or not layer.data:
        return None
    us = [loop.uv.x for loop in layer.data]
    vs = [loop.uv.y for loop in layer.data]
    return min(us), max(us), min(vs), max(vs)


def _triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(max(0, len(poly.vertices) - 2) for poly in mesh.polygons)


def process(
    *,
    source: Path,
    output: Path,
    expected_source_sha256: str,
    object_name: str,
) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"Missing source GLB: {source}")
    actual_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual_hash != expected_source_sha256:
        raise RuntimeError(
            f"Source hash mismatch for {source.name}: "
            f"wanted {expected_source_sha256}, found {actual_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one mesh object, found {len(meshes)}")
    obj = meshes[0]
    obj.name = object_name
    obj.data.name = f"{object_name}Mesh"

    source_lower, source_upper = _world_bounds(obj)
    source_size = source_upper - source_lower
    source_uv_bounds = _uv_bounds(obj.data)
    source_vertices = len(obj.data.vertices)
    source_triangles = _triangle_count(obj.data)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=MERGE_DISTANCE)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=DEGENERATE_DISTANCE)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(SMOOTH_ANGLE_DEG),
        keep_sharp_edges=True,
    )

    polished_lower, polished_upper = _world_bounds(obj)
    polished_size = polished_upper - polished_lower
    if max(abs(polished_size[i] - source_size[i]) for i in range(3)) > EPSILON:
        raise RuntimeError("Normals-only cleanup unexpectedly changed mesh dimensions")
    polished_uv_bounds = _uv_bounds(obj.data)
    if source_uv_bounds != polished_uv_bounds:
        raise RuntimeError("Normals-only cleanup unexpectedly changed UV bounds")

    # Keep the exact shape and size, but author a game-ready bottom-centre
    # origin so WorldRenderer places the object on top of a tile, not through it.
    centre = (polished_lower + polished_upper) * 0.5
    obj.location += Vector((-centre.x, -centre.y, -polished_lower.z))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    final_lower, final_upper = _world_bounds(obj)
    final_size = final_upper - final_lower
    if max(abs(final_size[i] - source_size[i]) for i in range(3)) > EPSILON:
        raise RuntimeError("Grounding unexpectedly changed mesh dimensions")
    if abs(final_lower.z) > EPSILON:
        raise RuntimeError(f"Grounding failed; lowest point is {final_lower.z}")
    if abs((final_lower.x + final_upper.x) * 0.5) > EPSILON:
        raise RuntimeError("Grounding failed to centre the mesh on X")
    if abs((final_lower.y + final_upper.y) * 0.5) > EPSILON:
        raise RuntimeError("Grounding failed to centre the mesh on Y")

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(output),
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

    print(json.dumps({
        "source": str(source),
        "output": str(output),
        "source_sha256": actual_hash,
        "source_vertices": source_vertices,
        "output_vertices": len(obj.data.vertices),
        "welded_vertices": source_vertices - len(obj.data.vertices),
        "source_triangles": source_triangles,
        "output_triangles": _triangle_count(obj.data),
        "source_dimensions": [round(value, 8) for value in source_size],
        "output_dimensions": [round(value, 8) for value in final_size],
        "output_ground_height": round(final_lower.z, 8),
        "smooth_angle_degrees": SMOOTH_ANGLE_DEG,
    }, indent=2))
