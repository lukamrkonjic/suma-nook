"""Measure the canonical male body for character-part authoring.

Imports the runtime player GLB, reports the armature rest layout, and slices
the head region so part placement can be driven by the real surface instead of
guessed coordinates. Writes art_source/characters/body_inspection.json.

Run:
    blender --background --factory-startup --python inspect_character_body.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy

REPO = Path(r"C:\Dev\suma-nook")
GLB = REPO / "assets/3d/reworked/player_male_rigged.glb"
OUT = REPO / "art_source/characters/body_inspection.json"


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))

    armatures = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one armature, found {len(armatures)}")
    armature = armatures[0]

    body = None
    modules = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if obj.name.startswith("PlayerMaleBody"):
            body = obj
        else:
            modules.append(obj)
    if body is None:
        raise RuntimeError("PlayerMaleBody mesh not found")

    bones = {}
    for bone in armature.data.bones:
        head = armature.matrix_world @ bone.head_local
        tail = armature.matrix_world @ bone.tail_local
        bones[bone.name] = {
            "head": [round(v, 5) for v in head],
            "tail": [round(v, 5) for v in tail],
        }

    depsgraph = bpy.context.evaluated_depsgraph_get()
    body_eval = body.evaluated_get(depsgraph)
    world = body.matrix_world
    coords = [world @ v.co for v in body_eval.data.vertices]

    min_v = [min(c[i] for c in coords) for i in range(3)]
    max_v = [max(c[i] for c in coords) for i in range(3)]

    # Head region: everything above the neck bone tail.
    neck_top_z = bones["mixamorigNeck"]["tail"][2]
    head_pts = [c for c in coords if c[2] >= neck_top_z]
    head_min = [min(c[i] for c in head_pts) for i in range(3)]
    head_max = [max(c[i] for c in head_pts) for i in range(3)]

    # Horizontal slices through the head: front surface (min y), width (max |x|).
    slices = []
    z0, z1 = head_min[2], head_max[2]
    steps = 26
    for s in range(steps):
        za = z0 + (z1 - z0) * s / steps
        zb = z0 + (z1 - z0) * (s + 1) / steps
        band = [c for c in head_pts if za <= c[2] < zb]
        if not band:
            continue
        near_axis = [c for c in band if abs(c[0]) < 0.03]
        slices.append({
            "z_mid": round((za + zb) / 2.0, 5),
            "front_y": round(min(c[1] for c in band), 5),
            "front_y_center": (
                round(min(c[1] for c in near_axis), 5) if near_axis else None
            ),
            "back_y": round(max(c[1] for c in band), 5),
            "half_width": round(max(abs(c[0]) for c in band), 5),
        })

    report = {
        "glb": str(GLB),
        "armature": armature.name,
        "body_object": body.name,
        "body_vertices": len(coords),
        "body_bounds_min": [round(v, 5) for v in min_v],
        "body_bounds_max": [round(v, 5) for v in max_v],
        "neck_top_z": neck_top_z,
        "head_bounds_min": [round(v, 5) for v in head_min],
        "head_bounds_max": [round(v, 5) for v in head_max],
        "head_slices": slices,
        "modules": {},
        "animations": [a.name for a in bpy.data.actions],
    }
    for module in modules:
        module_world = module.matrix_world
        module_coords = [module_world @ v.co for v in module.data.vertices]
        report["modules"][module.name] = {
            "min": [round(min(c[i] for c in module_coords), 5) for i in range(3)],
            "max": [round(max(c[i] for c in module_coords), 5) for i in range(3)],
            "triangles": sum(
                len(p.vertices) - 2 for p in module.data.polygons
            ),
        }

    OUT.write_text(json.dumps(report, indent=2))
    print("INSPECTION_WRITTEN", OUT)


if __name__ == "__main__":
    main()
