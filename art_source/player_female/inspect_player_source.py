"""Read-only structural report for the supplied player_female.glb.

Run with Blender 4.5+:
    blender --background --factory-startup --python inspect_player_source.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


SOURCE = Path(r"C:\Users\Luka\Downloads\player_female.glb")
REPORT = Path(
    r"C:\Dev\suma-nook\art_source\player_female\source-inspection.json"
)
CAPTURE_DIR = REPORT.parent / "source-captures"


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
    bm = bmesh.new()
    bm.from_mesh(obj.data)
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
        parts.append(
            {
                "vertices": len(island),
                "min": [round(value, 6) for value in mins],
                "max": [round(value, 6) for value in maxs],
                "size": [
                    round(maxs[i] - mins[i], 6) for i in range(3)
                ],
            }
        )
    bm.free()
    return sorted(
        parts, key=lambda part: int(part["vertices"]), reverse=True
    )


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat(
        "-Z", "Y"
    ).to_euler()


def _render_source_views() -> None:
    CAPTURE_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("InspectionWorld")
    scene.world.color = (0.035, 0.045, 0.055)

    bpy.ops.object.light_add(type="AREA", location=(-1.8, -2.2, 2.3))
    key = bpy.context.object
    key.data.energy = 900
    key.data.shape = "DISK"
    key.data.size = 2.2
    _look_at(key, Vector((0.0, 0.0, 0.05)))

    bpy.ops.object.light_add(type="AREA", location=(1.8, 1.5, 1.0))
    fill = bpy.context.object
    fill.data.energy = 500
    fill.data.size = 2.8
    _look_at(fill, Vector((0.0, 0.0, 0.05)))

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.25
    scene.camera = camera
    views = {
        "front": (0.0, -2.2, 0.05),
        "back": (0.0, 2.2, 0.05),
        "side": (2.2, 0.0, 0.05),
        "three-quarter": (1.55, -1.75, 0.65),
    }
    for view_name, location in views.items():
        camera.location = location
        _look_at(camera, Vector((0.0, 0.0, 0.0)))
        scene.render.filepath = str(CAPTURE_DIR / f"{view_name}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    ]
    report: dict[str, object] = {
        "blenderVersion": bpy.app.version_string,
        "source": str(SOURCE),
        "importResult": sorted(result),
        "objects": [],
        "armatures": [],
        "animations": [
            {
                "name": action.name,
                "frameRange": [
                    round(action.frame_range[0], 4),
                    round(action.frame_range[1], 4),
                ],
                "slots": len(action.slots),
            }
            for action in bpy.data.actions
        ],
        "images": [
            {
                "name": image.name,
                "size": list(image.size),
                "source": image.source,
                "packed": image.packed_file is not None,
            }
            for image in bpy.data.images
        ],
    }
    for obj in meshes:
        report["objects"].append(
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "edges": len(obj.data.edges),
                "polygons": len(obj.data.polygons),
                "materials": [
                    {
                        "name": slot.material.name,
                        "useNodes": slot.material.use_nodes,
                    }
                    for slot in obj.material_slots
                    if slot.material is not None
                ],
                "uvLayers": [layer.name for layer in obj.data.uv_layers],
                "shapeKeys": (
                    list(obj.data.shape_keys.key_blocks.keys())
                    if obj.data.shape_keys is not None
                    else []
                ),
                "vertexGroups": [group.name for group in obj.vertex_groups],
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
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    _render_source_views()
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
