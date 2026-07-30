"""Print compact Blender-side diagnostics for one or more source GLBs.

Run with:
    blender --background --factory-startup --python inspect_source_glbs.py -- a.glb b.glb
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _mesh_topology(mesh: bpy.types.Mesh) -> dict[str, int]:
    edge_faces = [0] * len(mesh.edges)
    pair_to_edge = {
        tuple(sorted(edge.vertices)): edge.index for edge in mesh.edges
    }
    for polygon in mesh.polygons:
        for pair in polygon.edge_keys:
            edge_faces[pair_to_edge[tuple(sorted(pair))]] += 1
    return {
        "boundary_edges": sum(count == 1 for count in edge_faces),
        "non_manifold_edges": sum(count != 2 for count in edge_faces),
        "wire_edges": sum(count == 0 for count in edge_faces),
    }


def inspect(path: Path) -> dict:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    armatures = [
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    ]
    world_points: list[Vector] = []
    mesh_reports = []
    for obj in meshes:
        world_points.extend(
            obj.matrix_world @ Vector(corner) for corner in obj.bound_box
        )
        mesh = obj.data
        report = {
            "name": obj.name,
            "vertices": len(mesh.vertices),
            "polygons": len(mesh.polygons),
            "materials": [
                material.name if material else "" for material in mesh.materials
            ],
            "dimensions": list(obj.dimensions),
            "location": list(obj.location),
            "scale": list(obj.scale),
        }
        report.update(_mesh_topology(mesh))
        mesh_reports.append(report)
    if world_points:
        minimum = [min(point[axis] for point in world_points) for axis in range(3)]
        maximum = [max(point[axis] for point in world_points) for axis in range(3)]
    else:
        minimum = maximum = [0.0, 0.0, 0.0]
    return {
        "file": str(path),
        "meshes": mesh_reports,
        "armatures": [armature.name for armature in armatures],
        "bounds_min": minimum,
        "bounds_max": maximum,
        "dimensions": [
            maximum[axis] - minimum[axis] for axis in range(3)
        ],
    }


def main() -> None:
    reports = [inspect(Path(argument)) for argument in _arguments()]
    print("CLOTHING_SOURCE_REPORT=" + json.dumps(reports, separators=(",", ":")))


if __name__ == "__main__":
    main()
