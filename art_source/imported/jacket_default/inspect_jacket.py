"""Inspect the generated jacket GLB: stats, bounds, and orientation renders.

Run:
    blender --background --factory-startup --python inspect_jacket.py
"""

from __future__ import annotations

import json
from math import radians
from pathlib import Path

import bpy
from mathutils import Vector

DIR = Path(r"C:\Dev\suma-nook\art_source\imported\jacket_default")
GLB = DIR / "jacket_source.glb"


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    report = {"objects": []}
    for obj in meshes:
        coords = [obj.matrix_world @ v.co for v in obj.data.vertices]
        min_v = [round(min(c[i] for c in coords), 4) for i in range(3)]
        max_v = [round(max(c[i] for c in coords), 4) for i in range(3)]
        report["objects"].append({
            "name": obj.name,
            "vertices": len(obj.data.vertices),
            "triangles": sum(len(p.vertices) - 2 for p in obj.data.polygons),
            "min": min_v,
            "max": max_v,
            "scale": list(obj.scale),
            "materials": [m.name if m else "none" for m in obj.data.materials],
        })
    (DIR / "jacket_inspection.json").write_text(json.dumps(report, indent=2))
    print("JACKET_INSPECTION", json.dumps(report))

    # Orientation renders: +Y, -Y, +X, top.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.image_settings.file_format = "PNG"
    center = Vector((0.0, 0.0, 0.0))
    all_min = Vector((1e9, 1e9, 1e9))
    all_max = Vector((-1e9, -1e9, -1e9))
    for entry in report["objects"]:
        all_min = Vector(map(min, all_min, Vector(entry["min"])))
        all_max = Vector(map(max, all_max, Vector(entry["max"])))
    center = (all_min + all_max) / 2.0
    size = max(all_max - all_min)

    bpy.ops.object.light_add(type="SUN", location=(2, -2, 4))
    sun = bpy.context.object
    sun.data.energy = 3.0
    look_at(sun, center)

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = size * 1.4
    scene.camera = camera
    views = {
        "from_minus_y": (center.x, center.y - size * 3, center.z),
        "from_plus_y": (center.x, center.y + size * 3, center.z),
        "from_plus_x": (center.x + size * 3, center.y, center.z),
        "from_top": (center.x, center.y - 0.001, center.z + size * 3),
    }
    for view_name, location in views.items():
        camera.location = location
        look_at(camera, center)
        scene.render.filepath = str(DIR / f"inspect_{view_name}.png")
        bpy.ops.render.render(write_still=True)
    print("JACKET_INSPECT_DONE")


if __name__ == "__main__":
    main()
