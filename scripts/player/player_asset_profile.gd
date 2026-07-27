class_name PlayerAssetProfile
extends Resource
## One replaceable contract for the authored player model and its locomotion.
##
## Gameplay talks only to PlayerVisual's stable state/equipment API. Replacing
## the temporary character therefore means supplying another profile and its
## assets, rather than adding model-specific branches to controllers or skills.

@export_group("Identity")
@export var profile_id := "temporary_mixamo_keeper"
@export var testing_only := true
@export var asset_id := "suma_player"
@export_file("*.glb") var model_resource_path := ""
@export_file("*.glb") var walk_source_path := ""

@export_group("Presentation")
@export var target_height := 1.17
@export var model_yaw_degrees := 180.0

@export_group("Locomotion")
@export var idle_clip_name := "mixamo_com"
@export var walk_clip_name := "walk"
@export var walk_animation: Animation
@export var locomotion_blend_seconds := 0.22
@export var walk_speed_scale_min := 0.88
@export var walk_speed_scale_max := 1.12
@export var animation_updates_in_physics := true

@export_group("Authored Actions")
@export var action_source_paths: Dictionary = {}
@export var action_animations: Dictionary = {}
@export var looping_action_clips := PackedStringArray()
@export_range(0.0, 1.0, 0.01) var action_blend_seconds := 0.18
@export var action_playback_seconds: Dictionary = {}
@export var action_impact_ratios: Dictionary = {}

@export_group("Rig Contract")
@export var hips_bone := "mixamorigHips"
@export var left_toe_bone := "mixamorigLeftToeBase"
@export var right_toe_bone := "mixamorigRightToeBase"
@export var tool_bone := "mixamorigRightHand"
@export var head_bone := "mixamorigHead"
@export var back_bone := "mixamorigSpine2"
@export var armor_region_bones: Dictionary = {}

@export_group("Material Treatment")
@export var material_shader: Shader
@export_range(0.0, 2.0, 0.01) var material_saturation := 1.14
@export_range(0.0, 2.0, 0.01) var material_value_scale := 0.88
@export var material_tint := Color(1.0, 0.97, 0.92, 1.0)
@export_range(0.0, 1.0, 0.01) var material_roughness := 0.9
@export_range(0.0, 1.0, 0.01) var material_specular := 0.14


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if asset_id.is_empty():
		errors.append("asset_id is empty")
	if model_resource_path.is_empty():
		errors.append("model_resource_path is empty")
	if target_height <= 0.0:
		errors.append("target_height must be positive")
	if idle_clip_name.is_empty():
		errors.append("idle_clip_name is empty")
	if walk_clip_name.is_empty():
		errors.append("walk_clip_name is empty")
	if walk_animation == null:
		errors.append("walk_animation is missing")
	for action_name in action_animations:
		if not action_animations[action_name] is Animation:
			errors.append(
				"action animation '%s' is not an Animation resource" % action_name
			)
		if not action_source_paths.has(action_name):
			errors.append("action '%s' has no preserved source path" % action_name)
	for looping_action in looping_action_clips:
		if not action_animations.has(looping_action):
			errors.append(
				"looping action '%s' has no animation resource" % looping_action
			)
	for action_name in action_playback_seconds:
		if float(action_playback_seconds[action_name]) <= 0.0:
			errors.append(
				"action '%s' has a non-positive playback duration" % action_name
			)
	for action_name in action_impact_ratios:
		var ratio := float(action_impact_ratios[action_name])
		if ratio <= 0.0 or ratio >= 1.0:
			errors.append(
				"action '%s' impact ratio must be between zero and one"
				% action_name
			)
	if material_shader == null:
		errors.append("material_shader is missing")
	for bone_name in [
		hips_bone,
		left_toe_bone,
		right_toe_bone,
		tool_bone,
		head_bone,
		back_bone,
	]:
		if bone_name.is_empty():
			errors.append("a required rig bone name is empty")
	for region_name in PlayerArmorRegions.names():
		if not armor_region_bones.has(region_name):
			errors.append(
				"armor region '%s' has no anchor bone" % region_name
			)
		elif String(armor_region_bones[region_name]).is_empty():
			errors.append(
				"armor region '%s' has an empty anchor bone" % region_name
			)
	return errors


func rig_validation_errors(
	skeleton: Skeleton3D,
	animation_player: AnimationPlayer
) -> PackedStringArray:
	var errors := PackedStringArray()
	if skeleton == null:
		errors.append("model has no Skeleton3D")
		return errors
	if animation_player == null:
		errors.append("model has no AnimationPlayer")
	else:
		if not animation_player.has_animation(idle_clip_name):
			errors.append("idle clip '%s' is missing" % idle_clip_name)
	for bone_name in [
		hips_bone,
		left_toe_bone,
		right_toe_bone,
		tool_bone,
		head_bone,
		back_bone,
	]:
		if skeleton.find_bone(bone_name) < 0:
			errors.append("required bone '%s' is missing" % bone_name)
	for region_name in armor_region_bones:
		var armor_bone := String(armor_region_bones[region_name])
		if skeleton.find_bone(armor_bone) < 0:
			errors.append(
				"armor region '%s' targets absent bone '%s'"
				% [region_name, armor_bone]
			)
	var authored_animations: Array[Animation] = []
	if walk_animation != null:
		authored_animations.append(walk_animation)
	for action_name in action_animations:
		var action_animation := action_animations[action_name] as Animation
		if action_animation != null:
			authored_animations.append(action_animation)
	for authored_animation in authored_animations:
		for track_index in authored_animation.get_track_count():
			var track_path := String(
				authored_animation.track_get_path(track_index)
			)
			if not track_path.contains(":"):
				continue
			var bone_name := track_path.get_slice(":", 1)
			if skeleton.find_bone(bone_name) < 0:
				errors.append(
					"authored animation track targets absent bone '%s'"
					% bone_name
				)
	return errors
