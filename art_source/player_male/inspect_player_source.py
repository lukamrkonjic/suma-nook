"""Read-only structural report for the supplied player_male.glb.

Run with Blender 4.5+:
    blender --background --factory-startup --python inspect_player_source.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
import bmesh


REPORT = Path(r"C:\Dev\suma-nook\art_source\player_male\source-inspection.json")
SOURCES = {
    "supplied": Path(r"C:\Users\Luka\Downloads\player_male.glb"),
    "current_contract": Path(
        r"C:\Dev\suma-nook\assets\3d\reworked\suma_player.glb"
    ),
}


def _bounds(obj: bpy.types.Object) -> dict[str, list[float]]:
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    mins = [min(point[axis] for point in points) for axis in range(3)]
    maxs = [max(point[axis] for point in points) for axis in range(3)]
    return {
        "min": [round(value, 6) for value in mins],
        "max": [round(value, 6) for value in maxs],
        "size": [round(maxs[i] - mins[i], 6) for i in range(3)],
    }


def _loose_parts(obj: bpy.types.Object) -> list[dict[str, object]]:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()

    remaining = set(bm.verts)
    parts: list[dict[str, object]] = []
    while remaining:
        seed = next(iter(remaining))
        stack = [seed]
        island = set()
        while stack:
            vertex = stack.pop()
            if vertex in island:
                continue
            island.add(vertex)
            remaining.discard(vertex)
            stack.extend(edge.other_vert(vertex) for edge in vertex.link_edges)

        coords = [obj.matrix_world @ vertex.co for vertex in island]
        mins = [min(point[axis] for point in coords) for axis in range(3)]
        maxs = [max(point[axis] for point in coords) for axis in range(3)]
        center = [(mins[i] + maxs[i]) * 0.5 for i in range(3)]
        parts.append(
            {
                "vertices": len(island),
                "min": [round(value, 6) for value in mins],
                "max": [round(value, 6) for value in maxs],
                "center": [round(value, 6) for value in center],
                "size": [round(maxs[i] - mins[i], 6) for i in range(3)],
            }
        )
    bm.free()
    return sorted(parts, key=lambda part: int(part["vertices"]), reverse=True)


def _inspect_source(source: Path) -> dict[str, object]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    ]
    animations = [
        {
            "name": action.name,
            "frameRange": [
                round(action.frame_range[0], 4),
                round(action.frame_range[1], 4),
            ],
            "fCurves": len(action.fcurves),
        }
        for action in bpy.data.actions
    ]
    report: dict[str, object] = {
        "source": str(source),
        "importResult": sorted(result),
        "objects": [],
        "armatures": [],
        "animations": animations,
    }

    for obj in meshes:
        report["objects"].append(
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "edges": len(obj.data.edges),
                "polygons": len(obj.data.polygons),
                "materials": [slot.material.name for slot in obj.material_slots],
                "bounds": _bounds(obj),
                "looseParts": _loose_parts(obj),
            }
        )
    for obj in armatures:
        report["armatures"].append(
            {
                "name": obj.name,
                "bones": [
                    {
                        "name": bone.name,
                        "parent": bone.parent.name if bone.parent else None,
                        "head": [
                            round(value, 6)
                            for value in (obj.matrix_world @ bone.head_local)
                        ],
                        "tail": [
                            round(value, 6)
                            for value in (obj.matrix_world @ bone.tail_local)
                        ],
                    }
                    for bone in obj.data.bones
                ],
            }
        )
    return report


def main() -> None:
    report: dict[str, object] = {
        "blenderVersion": bpy.app.version_string,
        "sources": {},
        "rigify": {
            "moduleAvailable": False,
            "addonEnableResult": None,
        },
    }
    try:
        import rigify  # noqa: F401

        report["rigify"]["moduleAvailable"] = True
        try:
            report["rigify"]["addonEnableResult"] = sorted(
                bpy.ops.preferences.addon_enable(module="rigify")
            )
        except RuntimeError as error:
            report["rigify"]["addonEnableResult"] = str(error)
    except ImportError as error:
        report["rigify"]["importError"] = str(error)

    for source_id, source in SOURCES.items():
        report["sources"][source_id] = _inspect_source(source)

    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
