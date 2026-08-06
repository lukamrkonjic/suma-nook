"""Report loose-piece geometry for the polished stone-wall source GLB.

Run with Blender in background mode.  This is intentionally read-only and is
used to decide whether the wall can be re-laid from intact textured stones.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "prop_stone_wall_polished"
    / "stone-wall_source.glb"
)


def _component_vertices(mesh: bpy.types.Mesh) -> list[list[int]]:
    adjacency: list[list[int]] = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)

    remaining = set(range(len(mesh.vertices)))
    components: list[list[int]] = []
    while remaining:
        seed = remaining.pop()
        stack = [seed]
        component = [seed]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
                    component.append(neighbor)
        components.append(component)
    return components


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(objects) != 1:
        raise RuntimeError(f"Expected one mesh, found {len(objects)}")

    obj = objects[0]
    mesh = obj.data
    components = _component_vertices(mesh)
    reports = []
    for index, indices in enumerate(components):
        points = [obj.matrix_world @ mesh.vertices[i].co for i in indices]
        lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
        upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
        vertex_set = set(indices)
        face_count = sum(
            1 for polygon in mesh.polygons if polygon.vertices[0] in vertex_set
        )
        reports.append(
            {
                "source_index": index,
                "vertices": len(indices),
                "faces": face_count,
                "lower": [round(value, 6) for value in lower],
                "upper": [round(value, 6) for value in upper],
                "size": [round(value, 6) for value in (upper - lower)],
                "center": [round(value, 6) for value in ((lower + upper) * 0.5)],
            }
        )

    reports.sort(key=lambda item: item["center"][2])
    print(
        "STONE_WALL_COMPONENT_REPORT="
        + json.dumps(
            {
                "source": str(SOURCE),
                "object": obj.name,
                "vertices": len(mesh.vertices),
                "faces": len(mesh.polygons),
                "materials": [slot.material.name for slot in obj.material_slots],
                "uv_layers": [layer.name for layer in mesh.uv_layers],
                "component_count": len(reports),
                "components": reports,
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
