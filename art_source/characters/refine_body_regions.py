"""Refine canonical mannequin armor-region UV2 boundaries.

This opens the existing character master, reclassifies lower-neck polygons as
left/right clavicle, retains a wrist overlap beneath garment cuffs, and
re-exports only the mannequin. Geometry, normals, weights, materials, rig, and
animations are not rebuilt.
"""

from pathlib import Path

import bpy


REPO = Path(r"C:\Dev\suma-nook")
MASTER = REPO / "art_source/characters/suma_character_master.blend"
OUTPUT = REPO / "assets/3d/reworked/player_male_mannequin.glb"

NECK_ID = 1
FOREARM_L_ID = 7
HAND_L_ID = 8
FOREARM_R_ID = 11
HAND_R_ID = 12
CLAVICLE_L_ID = 21
CLAVICLE_R_ID = 26
LOWER_NECK_MAX_Z = 0.145
HAND_OVERLAP_MIN_X = 0.245


def main() -> None:
    body = bpy.data.objects.get("PlayerMaleBody")
    if body is None or body.type != "MESH":
        raise RuntimeError("PlayerMaleBody mesh is missing from character master")
    armature = next(
        (obj for obj in bpy.data.objects if obj.type == "ARMATURE"),
        None,
    )
    if armature is None:
        raise RuntimeError("Character master contains no armature")
    if len(body.data.uv_layers) < 2:
        raise RuntimeError("PlayerMaleBody has no armor-region UV2 layer")

    region_layer = body.data.uv_layers[1]
    collar_changed = 0
    neck_preserved = 0
    wrist_changed = {"left": 0, "right": 0}
    for polygon in body.data.polygons:
        loop_index = polygon.loop_indices[0]
        region_id = round(region_layer.data[loop_index].uv.x)
        replacement = None
        if region_id == NECK_ID:
            if polygon.center.z > LOWER_NECK_MAX_Z:
                neck_preserved += 1
                continue
            replacement = (
                CLAVICLE_L_ID if polygon.center.x >= 0.0 else CLAVICLE_R_ID
            )
            collar_changed += 1
        elif (
            region_id in (FOREARM_L_ID, FOREARM_R_ID)
            and abs(polygon.center.x) > HAND_OVERLAP_MIN_X
            and polygon.center.z < 0.15
        ):
            if polygon.center.x >= 0.0:
                replacement = HAND_L_ID
                wrist_changed["left"] += 1
            else:
                replacement = HAND_R_ID
                wrist_changed["right"] += 1
        if replacement is None:
            continue
        for polygon_loop in polygon.loop_indices:
            region_layer.data[polygon_loop].uv = (float(replacement), 0.0)

    if (
        neck_preserved == 0
        or wrist_changed["left"] == 0
        or wrist_changed["right"] == 0
    ):
        raise RuntimeError(
            "Unexpected body-region refinement: "
            f"collar={collar_changed}, neck={neck_preserved}, "
            f"wrists={wrist_changed}"
        )

    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER))
    armature.data.pose_position = "POSE"
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )
    print(
        "BODY_REGIONS_REFINED",
        {
            "changed_to_clavicle": collar_changed,
            "preserved_as_neck": neck_preserved,
            "changed_to_hand_overlap": wrist_changed,
            "output": str(OUTPUT),
        },
    )


if __name__ == "__main__":
    main()
