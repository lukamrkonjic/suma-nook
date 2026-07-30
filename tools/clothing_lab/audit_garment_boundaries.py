"""Print connected boundary-loop diagnostics for a garment GLB.

Run with Blender:
    blender --background --factory-startup --python audit_garment_boundaries.py -- file.glb
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict, deque
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def _arguments() -> list[str]:
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    return sys.argv[separator + 1 :]


def _boundary_components(mesh_object: bpy.types.Object) -> list[dict]:
    bm = bmesh.new()
    bm.from_mesh(mesh_object.data)
    bm.verts.ensure_lookup_table()
    boundary_edges = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    adjacency: dict[int, set[int]] = defaultdict(set)
    edge_lookup: dict[tuple[int, int], bmesh.types.BMEdge] = {}
    for edge in boundary_edges:
        first, second = edge.verts
        adjacency[first.index].add(second.index)
        adjacency[second.index].add(first.index)
        edge_lookup[tuple(sorted((first.index, second.index)))] = edge
    remaining = set(adjacency)
    components: list[dict] = []
    while remaining:
        seed = remaining.pop()
        queue = deque([seed])
        vertices = {seed}
        while queue:
            current = queue.popleft()
            for neighbor in adjacency[current]:
                if neighbor in vertices:
                    continue
                vertices.add(neighbor)
                remaining.discard(neighbor)
                queue.append(neighbor)
        points = [mesh_object.matrix_world @ bm.verts[index].co for index in vertices]
        minimum = Vector(
            (
                min(point.x for point in points),
                min(point.y for point in points),
                min(point.z for point in points),
            )
        )
        maximum = Vector(
            (
                max(point.x for point in points),
                max(point.y for point in points),
                max(point.z for point in points),
            )
        )
        centroid = sum(points, Vector()) / len(points)
        component_edges = [
            edge
            for key, edge in edge_lookup.items()
            if key[0] in vertices and key[1] in vertices
        ]
        perimeter = sum(edge.calc_length() for edge in component_edges)
        degrees = [len(adjacency[index]) for index in vertices]
        components.append(
            {
                "vertices": len(vertices),
                "edges": len(component_edges),
                "centroid": [round(value, 6) for value in centroid],
                "bounds_min": [round(value, 6) for value in minimum],
                "bounds_max": [round(value, 6) for value in maximum],
                "extent": [round(value, 6) for value in maximum - minimum],
                "perimeter": round(perimeter, 6),
                "closed_loop": all(degree == 2 for degree in degrees),
                "degree_histogram": {
                    str(degree): degrees.count(degree) for degree in sorted(set(degrees))
                },
            }
        )
    bm.free()
    return sorted(components, key=lambda item: item["perimeter"], reverse=True)


def _weld_coincident_vertices(mesh_object: bpy.types.Object) -> int:
    mesh = mesh_object.data
    before = len(mesh.vertices)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00001)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return before - len(mesh.vertices)


def main() -> None:
    arguments = _arguments()
    if len(arguments) != 1:
        raise SystemExit("Expected exactly one garment GLB path")
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(Path(arguments[0]).resolve()))
    mesh_objects = [
        obj
        for obj in bpy.context.scene.objects
        if obj not in existing and obj.type == "MESH"
    ]
    for mesh_object in mesh_objects:
        merged_vertices = _weld_coincident_vertices(mesh_object)
        components = _boundary_components(mesh_object)
        report = {
            "object": mesh_object.name,
            "vertices": len(mesh_object.data.vertices),
            "polygons": len(mesh_object.data.polygons),
            "merged_coincident_vertices": merged_vertices,
            "boundary_component_count": len(components),
            "boundary_edge_count": sum(item["edges"] for item in components),
            "largest_boundary_components": components[:16],
        }
        print("GARMENT_BOUNDARY_AUDIT " + json.dumps(report))


if __name__ == "__main__":
    main()
