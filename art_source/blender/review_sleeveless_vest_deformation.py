"""Render the continuous vest candidate through Suma's real animations."""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
WARDROBE_DIR = ROOT / "art_source" / "blender" / "wardrobe"
CANDIDATE_DIR = WARDROBE_DIR / "continuous_candidate"
INPUT = CANDIDATE_DIR / "sleeveless_vest_continuous_candidate.blend"
OUTPUT = CANDIDATE_DIR / "sleeveless_vest_continuous_stress.blend"
REVIEW_DIR = CANDIDATE_DIR / "stress_reviews"
REPORT = CANDIDATE_DIR / "sleeveless_vest_continuous_stress_review.json"
ACTION_SOURCES = {
    "walk": ROOT / "art_source" / "animation_sources" / "player_walk.glb",
    "chop": ROOT / "art_source" / "animation_sources" / "player_chop.glb",
    "fish_cast": ROOT / "art_source" / "animation_sources" / "player_fish_cast.glb",
    "fish_wait": ROOT / "art_source" / "animation_sources" / "player_fish_wait.glb",
}
FRAME_RATIOS = {
    "walk": 0.46,
    "chop": 0.52,
    "fish_cast": 0.58,
    "fish_wait": 0.44,
}


def import_action(name: str, path: Path) -> bpy.types.Action:
    existing_objects = set(bpy.data.objects)
    existing_actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported_objects = [
        obj for obj in bpy.data.objects if obj not in existing_objects
    ]
    actions = [
        action for action in bpy.data.actions if action not in existing_actions
    ]
    if not actions:
        raise RuntimeError(f"No action imported from {path}")
    action = max(
        actions,
        key=lambda candidate: candidate.frame_range[1]
        - candidate.frame_range[0],
    )
    action.name = "WardrobeReview_" + name
    action.use_fake_user = True
    for obj in imported_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    return action


def render(
    camera: bpy.types.Object,
    path: Path,
    location: Vector,
    target: Vector,
    ortho_scale: float,
) -> None:
    camera.location = location
    camera.rotation_euler = (
        target - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = ortho_scale
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def evaluated_center(obj: bpy.types.Object) -> Vector:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    minimum = Vector(
        min(point[axis] for point in points) for axis in range(3)
    )
    maximum = Vector(
        max(point[axis] for point in points) for axis in range(3)
    )
    evaluated.to_mesh_clear()
    return (minimum + maximum) * 0.5


def main() -> None:
    if not INPUT.is_file():
        raise FileNotFoundError(INPUT)
    for source in ACTION_SOURCES.values():
        if not source.is_file():
            raise FileNotFoundError(source)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(INPUT))
    armature = bpy.data.objects["WardrobeArmature"]
    camera = bpy.data.objects["ContinuousVestReviewCamera"]
    body = bpy.data.objects["WardrobeBodyReference"]
    body.hide_set(True)
    body.hide_render = True
    exposed = bpy.data.objects["BodyExposedForCowboyVest"]
    exposed.hide_set(False)
    exposed.hide_render = False
    all_z = [
        body.matrix_world @ vertex.co for vertex in body.data.vertices
    ]
    character_height = max(point.z for point in all_z) - min(
        point.z for point in all_z
    )
    actions = {
        name: import_action(name, source)
        for name, source in ACTION_SOURCES.items()
    }
    animation_data = armature.animation_data_create()
    for track in list(animation_data.nla_tracks):
        animation_data.nla_tracks.remove(track)
    armature.data.pose_position = "POSE"

    frames = {}
    pose_signatures = {}
    images = []
    for name, action in actions.items():
        animation_data.action = action
        animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        frame = start + (end - start) * FRAME_RATIOS[name]
        frames[name] = frame
        bpy.context.scene.frame_set(int(round(frame)))
        bpy.context.view_layer.update()
        target = evaluated_center(exposed)
        pose_signatures[name] = {
            bone_name: list(
                armature.matrix_world
                @ armature.pose.bones[bone_name].head
            )
            for bone_name in [
                "mixamorigLeftHand",
                "mixamorigRightHand",
                "mixamorigHead",
            ]
            if armature.pose.bones.get(bone_name) is not None
        }
        front_path = REVIEW_DIR / f"{name}_front.png"
        orbit_path = REVIEW_DIR / f"{name}_orbit.png"
        render(
            camera,
            front_path,
            target
            + Vector(
                (
                    0.0,
                    -character_height * 2.4,
                    character_height * 0.43,
                )
            ),
            target,
            character_height * 1.12,
        )
        render(
            camera,
            orbit_path,
            target
            + Vector(
                (
                    -character_height * 1.55,
                    -character_height * 2.0,
                    character_height * 0.64,
                )
            ),
            target,
            character_height * 1.16,
        )
        images.extend([front_path, orbit_path])

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
    report = {
        "candidate": str(INPUT.relative_to(ROOT)),
        "output": str(OUTPUT.relative_to(ROOT)),
        "actions": {
            name: {
                "source": str(ACTION_SOURCES[name].relative_to(ROOT)),
                "frame_range": list(actions[name].frame_range),
                "review_frame": frames[name],
            }
            for name in actions
        },
        "pose_signatures": pose_signatures,
        "images": [str(path.relative_to(ROOT)) for path in images],
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SLEEVELESS_VEST_STRESS_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
