"""Build the first-pass smooth, rigged female Suma mannequin.

The supplied GLB follows the same normalized low-poly convention as the male
source, but it is half the authored height. It is normalized to the male
source scale first, then receives the exact same offline smoothing pass:

    Smooth factor 0.38, 6 iterations

The current Mixamo-compatible export skeleton and idle clip are reused so the
body can enter the game immediately. Automatic weights and Rigify controls are
deliberately an initial pass for later artist tuning.

Run with Blender 4.5 LTS:
    blender --background --factory-startup --python build_player_female.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import bpy
from mathutils import Vector


REPO = Path(r"C:\Dev\suma-nook")
SOURCE = Path(r"C:\Users\Luka\Downloads\player_female.glb")
MALE_BUILDER_PATH = (
    REPO / "art_source/player_male/build_player_male.py"
)
CONTRACT_MODEL = (
    REPO / "assets/3d/reworked/player_male_mannequin.glb"
)
OUT_DIR = REPO / "art_source/player_female"
BLEND_OUT = OUT_DIR / "player_female_rigify.blend"
GLB_OUT = REPO / "assets/3d/reworked/player_female_mannequin.glb"
CAPTURE_DIR = OUT_DIR / "captures"
REPORT_OUT = OUT_DIR / "build-report.json"

# Female source height is 1.0 while the male source height is 2.0. Normalize
# first so the male pipeline's voxel size and final scale have the same
# physical meaning.
SOURCE_NORMALIZATION_SCALE = 2.0
SMOOTH_FACTOR = 0.38
SMOOTH_ITERATIONS = 6


def _load_male_builder():
    spec = importlib.util.spec_from_file_location(
        "suma_player_male_builder", MALE_BUILDER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {MALE_BUILDER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.SOURCE = SOURCE
    module.CONTRACT_MODEL = CONTRACT_MODEL
    module.OUT_DIR = OUT_DIR
    module.BLEND_OUT = BLEND_OUT
    module.GLB_OUT = GLB_OUT
    module.CAPTURE_DIR = CAPTURE_DIR
    return module


def _normalize_source(mesh: bpy.types.Object) -> None:
    mesh.scale = Vector(
        (
            SOURCE_NORMALIZATION_SCALE,
            SOURCE_NORMALIZATION_SCALE,
            SOURCE_NORMALIZATION_SCALE,
        )
    )
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.ops.object.transform_apply(
        location=False, rotation=False, scale=True
    )


def _rename_authoring_rigs(
    metarig: bpy.types.Object, control_rig: bpy.types.Object
) -> None:
    metarig.name = "PlayerFemale_RigifyMeta"
    metarig.data.name = "PlayerFemale_RigifyMeta"
    control_rig.name = "PlayerFemale_Rigify"
    control_rig.data.name = "PlayerFemale_Rigify"


def _validate(
    mesh: bpy.types.Object,
    export_rig: bpy.types.Object,
    control_rig: bpy.types.Object,
    male,
) -> dict[str, object]:
    triangles = sum(
        len(polygon.vertices) - 2 for polygon in mesh.data.polygons
    )
    if not 8_000 <= triangles <= 50_000:
        raise RuntimeError(f"Unexpected body triangle count: {triangles}")
    required_groups = set(male.EXPORT_BONES)
    actual_groups = {group.name for group in mesh.vertex_groups}
    missing_groups = required_groups - actual_groups
    if missing_groups:
        raise RuntimeError(
            "Skinned mesh is missing required groups: "
            f"{sorted(missing_groups)}"
        )
    if len(control_rig.data.bones) < 50:
        raise RuntimeError("Rigify control rig was not generated completely")
    if export_rig.animation_data is None:
        raise RuntimeError("Export rig lost its embedded idle action")
    if len(mesh.data.materials) != 1:
        raise RuntimeError("Female mannequin must export one skin material")
    bounds = [
        mesh.matrix_world @ Vector(corner) for corner in mesh.bound_box
    ]
    mins = [min(point[axis] for point in bounds) for axis in range(3)]
    maxs = [max(point[axis] for point in bounds) for axis in range(3)]
    report = {
        "source": str(SOURCE),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "normalization_scale": SOURCE_NORMALIZATION_SCALE,
        "smoothing": {
            "modifier": "SMOOTH",
            "factor": SMOOTH_FACTOR,
            "iterations": SMOOTH_ITERATIONS,
            "voxel_size_after_normalization": 0.022,
        },
        "body": {
            "name": mesh.name,
            "vertices": len(mesh.data.vertices),
            "triangles": triangles,
            "bounds": {
                "min": [round(value, 6) for value in mins],
                "max": [round(value, 6) for value in maxs],
            },
            "weighted_groups": len(actual_groups),
        },
        "rig": {
            "deform_bones": len(export_rig.data.bones),
            "rigify_bones": len(control_rig.data.bones),
            "contract_source": str(CONTRACT_MODEL),
            "status": "initial_auto_weights_for_artist_tuning",
        },
        "outputs": {
            "blend": str(BLEND_OUT),
            "glb": str(GLB_OUT),
        },
    }
    REPORT_OUT.write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print("PLAYER_FEMALE_BUILD", report)
    return report


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(SOURCE)
    male = _load_male_builder()
    male.reset_scene()
    skin = male.make_material(
        "Imota_Female_Skin", male.COLORS["skin"], 0.68, 0.18
    )
    export_rig = male.load_contract_rig()
    male.fit_export_rig(export_rig)

    source_mesh = male.import_source()
    _normalize_source(source_mesh)
    male.smooth_source(source_mesh)
    source_mesh.name = "PlayerFemaleBody"
    source_mesh.data.name = "PlayerFemaleBodyMesh"
    source_mesh.data.materials.clear()
    source_mesh.data.materials.append(skin)
    male.apply_model_scale(source_mesh)
    male.parent_with_weights(source_mesh, export_rig)

    control_rig = male.fit_rigify_metarig(export_rig)
    metarig = bpy.data.objects.get("PlayerMale_RigifyMeta")
    if metarig is None:
        raise RuntimeError("Rigify metarig disappeared during generation")
    male.connect_rigify_to_export(control_rig, export_rig)
    _rename_authoring_rigs(metarig, control_rig)
    _validate(source_mesh, export_rig, control_rig, male)

    ground, camera = male.prepare_review_scene(
        source_mesh, [], metarig, control_rig, export_rig
    )
    # The supplied textured material is replaced by the palette skin material.
    # Purge its now-unused packed source images so the authoring file does not
    # make Godot extract irrelevant 1024px textures.
    bpy.ops.outliner.orphans_purge(
        do_local_ids=True, do_linked_ids=True, do_recursive=True
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    male.remove_authoring_constraints(export_rig)
    export_rig.data.pose_position = "REST"
    male.render_views(camera)

    review_objects = [
        ground,
        camera,
        *[
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "LIGHT"
        ],
        metarig,
        control_rig,
    ]
    male.export_runtime(source_mesh, [], export_rig, review_objects)
    print("PLAYER_FEMALE_BUILD_COMPLETE")


if __name__ == "__main__":
    main()
