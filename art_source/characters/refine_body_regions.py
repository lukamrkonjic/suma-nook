"""Refine canonical mannequin armor-region UV2 boundaries.

This opens the existing character master, repairs head/neck/clavicle regions
from the mannequin's transferred deformation weights, retains a wrist overlap
beneath garment cuffs, and re-exports only the mannequin. Geometry, normals,
weights, materials, rig, and animations are not rebuilt.
"""

from pathlib import Path

import bpy


REPO = Path(r"C:\Dev\suma-nook")
MASTER = REPO / "art_source/characters/suma_character_master.blend"
OUTPUT = REPO / "assets/3d/reworked/player_male_mannequin.glb"

HEAD_ID = 0
NECK_ID = 1
FOREARM_L_ID = 7
HAND_L_ID = 8
FOREARM_R_ID = 11
HAND_R_ID = 12
CLAVICLE_L_ID = 21
CLAVICLE_R_ID = 26
SHOULDER_CAP_L_ID = 22
SHOULDER_CAP_R_ID = 27
UPPER_CHEST_L_ID = 24
UPPER_CHEST_R_ID = 29
CHEST_ID = 2
CLAVICLE_MIN_Z = 0.075
CLAVICLE_MAX_Z = 0.120
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
    group_names = {group.index: group.name for group in body.vertex_groups}

    def dominant_group(polygon) -> str:
        weights = {}
        for vertex_index in polygon.vertices:
            for membership in body.data.vertices[vertex_index].groups:
                group_name = group_names[membership.group]
                weights[group_name] = (
                    weights.get(group_name, 0.0)
                    + membership.weight
                )
        return max(weights, key=weights.get) if weights else ""

    anatomy_changed = 0
    anatomy_counts = {
        "head": 0,
        "neck": 0,
        "clavicle_l": 0,
        "clavicle_r": 0,
        "shoulder_cap_l": 0,
        "shoulder_cap_r": 0,
        "upper_chest_l": 0,
        "upper_chest_r": 0,
    }
    wrist_changed = {"left": 0, "right": 0}
    for polygon in body.data.polygons:
        loop_index = polygon.loop_indices[0]
        region_id = round(region_layer.data[loop_index].uv.x)
        replacement = None
        if region_id in (HEAD_ID, NECK_ID, CLAVICLE_L_ID, CLAVICLE_R_ID):
            dominant = dominant_group(polygon)
            side = "l" if polygon.center.x >= 0.0 else "r"
            if dominant == "mixamorigHead":
                replacement = HEAD_ID
                anatomy_counts["head"] += 1
            elif dominant == "mixamorigNeck":
                replacement = NECK_ID
                anatomy_counts["neck"] += 1
            elif dominant in (
                "mixamorigLeftShoulder",
                "mixamorigRightShoulder",
            ):
                side = (
                    "l"
                    if dominant == "mixamorigLeftShoulder"
                    else "r"
                )
                if polygon.center.z > CLAVICLE_MAX_Z:
                    replacement = (
                        SHOULDER_CAP_L_ID
                        if side == "l"
                        else SHOULDER_CAP_R_ID
                    )
                    anatomy_counts[f"shoulder_cap_{side}"] += 1
                elif polygon.center.z > CLAVICLE_MIN_Z:
                    replacement = (
                        CLAVICLE_L_ID if side == "l" else CLAVICLE_R_ID
                    )
                    anatomy_counts[f"clavicle_{side}"] += 1
                else:
                    replacement = (
                        UPPER_CHEST_L_ID
                        if side == "l"
                        else UPPER_CHEST_R_ID
                    )
                    anatomy_counts[f"upper_chest_{side}"] += 1
            elif polygon.center.z > 0.04:
                replacement = (
                    UPPER_CHEST_L_ID
                    if side == "l"
                    else UPPER_CHEST_R_ID
                )
                anatomy_counts[f"upper_chest_{side}"] += 1
            else:
                replacement = CHEST_ID
            if replacement != region_id:
                anatomy_changed += 1
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

    post_counts = {
        "neck": 0,
        "clavicle_l": 0,
        "clavicle_r": 0,
    }
    wrong_anatomy = 0
    wrist_overlap = {"left": 0, "right": 0}
    for polygon in body.data.polygons:
        region_id = round(
            region_layer.data[polygon.loop_indices[0]].uv.x
        )
        dominant = dominant_group(polygon)
        if region_id == NECK_ID:
            post_counts["neck"] += 1
            if dominant != "mixamorigNeck":
                wrong_anatomy += 1
        elif region_id == CLAVICLE_L_ID:
            post_counts["clavicle_l"] += 1
            if dominant != "mixamorigLeftShoulder":
                wrong_anatomy += 1
        elif region_id == CLAVICLE_R_ID:
            post_counts["clavicle_r"] += 1
            if dominant != "mixamorigRightShoulder":
                wrong_anatomy += 1
        if (
            HAND_OVERLAP_MIN_X < abs(polygon.center.x) < 0.262
            and region_id in (HAND_L_ID, HAND_R_ID)
        ):
            wrist_overlap[
                "left" if region_id == HAND_L_ID else "right"
            ] += 1

    if (
        min(post_counts.values()) == 0
        or wrong_anatomy != 0
        or min(wrist_overlap.values()) == 0
    ):
        raise RuntimeError(
            "Unexpected body-region refinement: "
            f"anatomy={anatomy_counts}, post={post_counts}, "
            f"wrong={wrong_anatomy}, overlap={wrist_overlap}"
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
            "anatomy_changed": anatomy_changed,
            "anatomy_counts": anatomy_counts,
            "changed_to_hand_overlap": wrist_changed,
            "post_counts": post_counts,
            "wrong_anatomy": wrong_anatomy,
            "wrist_overlap": wrist_overlap,
            "output": str(OUTPUT),
        },
    )


if __name__ == "__main__":
    main()
