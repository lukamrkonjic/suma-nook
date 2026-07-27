"""Create Suma's canonical Blender wardrobe mannequin.

The mannequin imports the exact production player GLB, keeps its transforms,
skin, UVs, materials, and bone names unchanged, switches the armature to rest
display, and records the source hash. Garment templates should link or copy
from this file instead of importing ad-hoc character variants.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "assets" / "3d" / "reworked" / "suma_player.glb"
WARDROBE_DIR = ROOT / "art_source" / "blender" / "wardrobe"
OUTPUT = WARDROBE_DIR / "suma_wardrobe_mannequin.blend"
REPORT = WARDROBE_DIR / "suma_wardrobe_mannequin.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds_for(obj: bpy.types.Object) -> dict[str, list[float]]:
    coordinates = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "minimum": [
            min(coordinate[axis] for coordinate in coordinates)
            for axis in range(3)
        ],
        "maximum": [
            max(coordinate[axis] for coordinate in coordinates)
            for axis in range(3)
        ],
    }


def main() -> None:
    if not PLAYER.is_file():
        raise FileNotFoundError(f"Missing production player: {PLAYER}")
    WARDROBE_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.ops.import_scene.gltf(filepath=str(PLAYER))

    armature = next(
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    )
    body = max(
        (obj for obj in bpy.context.scene.objects if obj.type == "MESH"),
        key=lambda obj: len(obj.data.polygons),
    )
    armature.name = "WardrobeArmature"
    armature.data.name = "WardrobeArmatureData"
    armature.data.pose_position = "REST"
    armature["wardrobe_source"] = str(PLAYER.relative_to(ROOT))
    armature["wardrobe_source_sha256"] = sha256(PLAYER)
    body.name = "WardrobeBodyReference"
    body.data.name = "WardrobeBodyReferenceMesh"
    body["wardrobe_reference_only"] = True

    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    armature.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = armature

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
    report = {
        "source": str(PLAYER.relative_to(ROOT)),
        "source_sha256": sha256(PLAYER),
        "output": str(OUTPUT.relative_to(ROOT)),
        "units": "meters",
        "up_axis_in_blender": "Z",
        "armature": armature.name,
        "bones": len(armature.data.bones),
        "body": body.name,
        "vertices": len(body.data.vertices),
        "polygons": len(body.data.polygons),
        "uv_layers": [layer.name for layer in body.data.uv_layers],
        "vertex_groups": len(body.vertex_groups),
        "bounds": bounds_for(body),
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("WARDROBE_MANNEQUIN_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
