"""Render candidate garment transforms against the canonical rest mannequin.

This is a review helper only. It reads the same explicit transform controls
used by the Clothing Lab builder, so a reviewed candidate can be copied into
the persisted fit resource without a second fitting interpretation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process_clothing as clothing


def arguments() -> tuple[Path, Path]:
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    values = sys.argv[separator + 1 :]
    if len(values) != 2:
        raise RuntimeError(
            "Expected: -- <candidate-manifest.json> <output-directory>"
        )
    return Path(values[0]), Path(values[1])


def apply_rigid_transform(obj: bpy.types.Object, candidate: dict) -> None:
    scale = clothing.vector(candidate["scale"])
    position = clothing.vector(candidate["position"])
    rotation = clothing.vector(candidate["rotation_degrees"])
    transform = (
        Matrix.Translation(position)
        @ Euler(tuple(value * 0.017453292519943295 for value in rotation))
        .to_matrix()
        .to_4x4()
        @ Matrix.Diagonal((scale.x, scale.y, scale.z, 1.0))
    )
    obj.data.transform(transform)
    obj.data.update()


def render_candidate(candidate: dict, output: Path) -> None:
    _rig, _body, _immutable = clothing.setup_master()
    garment, _source = clothing.import_source(
        clothing.resolved_path(candidate["source_file"])
    )
    if candidate.get("attachment_type", "skinned") == "rigid":
        apply_rigid_transform(garment, candidate)
    else:
        clothing.apply_explicit_fit(garment, candidate)

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    output.mkdir(parents=True, exist_ok=True)
    for camera_name, suffix in (
        ("CAM_FRONT_ORTHO", "front"),
        ("CAM_THREE_QUARTER", "three_quarter"),
        ("CAM_SIDE_ORTHO", "side"),
    ):
        camera = bpy.data.objects.get(camera_name)
        if camera is None:
            raise RuntimeError(f"Missing review camera {camera_name}")
        scene.camera = camera
        scene.render.filepath = str(
            output / f"{candidate['part_id']}_{suffix}.png"
        )
        bpy.ops.render.render(write_still=True)


def main() -> None:
    manifest_path, output = arguments()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for candidate in manifest["candidates"]:
        render_candidate(candidate, output)
    print(f"Rendered {len(manifest['candidates'])} clothing candidates")


if __name__ == "__main__":
    main()
