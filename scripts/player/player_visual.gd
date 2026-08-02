class_name PlayerVisual
extends Node3D
## Presents whichever authored player profile is current behind one stable
## animation/equipment API. The current model is explicitly temporary; gameplay
## never depends on its asset name, clip names, bone names, scale, or materials.

const WALK_BOB_HZ := 7.5
const CURRENT_PLAYER_PROFILE: PlayerAssetProfile = preload(
	"res://assets/player/current_player_profile.tres"
)
const DEFAULT_APPEARANCE: CharacterAppearancePreset = preload(
	"res://assets/characters/presets/default_male_appearance.tres"
)
const PART_CATALOG: CharacterPartCatalog = preload(
	"res://assets/characters/parts/catalog_male.tres"
)
const BODY_CATALOG: CharacterBodyCatalog = preload(
	"res://assets/characters/body_catalog.tres"
)
const FishingRodScript := preload(
	"res://scripts/visuals/fishing_rod.gd"
)
const FishingPoseModifierScript := preload(
	"res://scripts/player/fishing_pose_modifier.gd"
)
const ProceduralCritterPlayerScript := preload(
	"res://scripts/player/procedural_critter_player.gd"
)

signal animation_started(animation_name: String)
signal animation_event(animation_name: String, event_name: String)
signal animation_finished(animation_name: String)

const ANIMATION_MANIFEST := {
	"idle": {
		"looping": true,
		"duration": 2.4,
		"events": [],
		"procedural_tracks": {
			"body.position.y": "sin(time * TAU / 2.4) * 0.006",
			"head.rotation.z": "sin(time * TAU / 4.8) * 0.008",
		},
	},
	"walk": {
		"looping": true,
		"duration": 0.84,
		"events": [{"name": "left_step", "time": 0.0}, {"name": "right_step", "time": 0.42}],
		"procedural_tracks": {
			"body.position.y": "abs(sin(phase)) * 0.05",
			"body.rotation.x": 0.06,
			"arms.rotation.x": "opposed sin(phase) * 0.55",
		},
	},
	"fish_cast": {
		"looping": false,
		"duration": 1.15,
		"events": [{"name": "release", "time": 1.15}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.22, "value": -2.2, "curve": "back_out"},
				{"time": 0.38, "value": -0.9, "curve": "cubic_in"},
			],
		},
	},
	"fish_wait": {
		"looping": true,
		"duration": 3.5333333,
		"events": [],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": -0.9},
				{"time": 0.4, "value": -0.95, "curve": "linear"},
				{"time": 1.3, "value": -0.85, "curve": "sine_in_out"},
			],
		},
	},
	"fish_catch": {
		"looping": false,
		"duration": 0.69,
		"events": [{"name": "impact", "time": 0.14}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": -0.9},
				{"time": 0.14, "value": -2.5, "curve": "back_out"},
			],
			"body.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.14, "value": -0.12, "curve": "linear"},
				{"time": 0.49, "value": -0.12},
				{"time": 0.69, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"chop": {
		"looping": true,
		"duration": 1.9,
		"events": [{"name": "impact", "time": 0.893}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.28, "value": -2.4, "curve": "quad_out"},
				{"time": 0.38, "value": -0.3, "curve": "quart_in"},
			],
			"body.rotation.y": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.28, "value": 0.16, "curve": "linear"},
				{"time": 0.38, "value": -0.08, "curve": "linear"},
				{"time": 0.52, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"attack": {
		"looping": false,
		"duration": 0.38,
		"events": [{"name": "impact", "time": 0.22}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.12, "value": -2.1, "curve": "quad_out"},
				{"time": 0.22, "value": 0.5, "curve": "quart_in"},
				{"time": 0.38, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"dodge": {
		"looping": false,
		"duration": 0.3,
		"events": [],
		"tracks": {
			"body.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.1, "value": 0.5, "curve": "linear"},
				{"time": 0.3, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"hit": {
		"looping": false,
		"duration": 0.18,
		"events": [{"name": "flash", "time": 0.0}],
		"tracks": {
			"body.position.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.05, "value": 0.07, "curve": "linear"},
				{"time": 0.1, "value": -0.05, "curve": "linear"},
				{"time": 0.18, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"celebrate": {
		"looping": false,
		"duration": 0.7,
		"events": [{"name": "apex", "time": 0.2}],
		"tracks": {
			"arms.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.2, "value": -2.9, "curve": "back_out"},
				{"time": 0.4, "value": -2.9},
				{"time": 0.7, "value": 0.0, "curve": "linear"},
			],
			"body.position.y": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.18, "value": 0.16, "curve": "quad_out"},
				{"time": 0.4, "value": 0.0, "curve": "bounce_out"},
			],
		},
	},
}
const ANIMATION_TRANSITIONS := {
	"idle": ["walk", "fish_cast", "fish_wait", "fish_catch", "chop", "attack", "dodge", "hit", "celebrate"],
	"walk": ["idle", "fish_cast", "chop", "attack", "dodge", "hit", "celebrate"],
	"fish_cast": ["fish_wait", "fish_catch", "idle", "walk"],
	"fish_wait": ["fish_catch", "idle", "walk"],
	"fish_catch": ["fish_cast", "fish_wait", "idle", "walk"],
	"chop": ["chop", "idle", "walk"],
	"attack": ["attack", "dodge", "hit", "idle", "walk"],
	"dodge": ["attack", "hit", "idle", "walk"],
	"hit": ["attack", "dodge", "idle", "walk"],
	"celebrate": ["idle", "walk"],
}

var materials: MaterialLibrary
var assets: AssetLibrary
var palette: CozyPalette

var _body: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _head_group: Node3D
var _tool_mount: Node3D
var _back_mount: Node3D
var _head_mount: Node3D
var _hair_nodes: Array[Node3D] = []
var _eye_nodes: Array[Node3D] = []
var _rigged_skin_nodes: Array[MeshInstance3D] = []
var _appearance_assembler := CharacterAssembler.new()
var _animation_player: AnimationPlayer
var _skeleton: Skeleton3D
var _asset_profile: PlayerAssetProfile
var _appearance_preset: CharacterAppearancePreset
var _body_option: CharacterBodyOption
var _active_body_index := -1
var _uses_rigged_preview := false
var _active_hair_style := 0
var _hair_hidden_by_headwear := false
var _base_body_meshes: Array[MeshInstance3D] = []
var _body_garment_meshes: Array[MeshInstance3D] = []
var _armor_anchors: Dictionary = {}
var _body_region_mask := 0
var _body_base_position := Vector3.ZERO
var _body_base_rotation := Vector3.ZERO
var _locomotion_clip := ""
var _locomotion_walking := false
var _locomotion_transition_count := 0
var _fishing_rod: FishingRod
var _fishing_pose_modifier: FishingPoseModifier
var _seated_fishing_active := false
var _procedural_critter: Node3D
var _procedural_critter_enabled := false

var _walk_amount := 0.0
var _walk_phase := 0.0
var _idle_phase := 0.0
var _action_tween: Tween
var _current_anim := "idle"


func build(asset_library: AssetLibrary, pal: CozyPalette) -> void:
	assets = asset_library
	materials = asset_library.materials
	palette = pal
	_switch_body(0)


func _switch_body(body_index: int) -> void:
	var option := BODY_CATALOG.option_for(body_index)
	assert(option != null, "Character body catalog has no default option")
	var option_errors := option.validation_errors()
	assert(
		option_errors.is_empty(),
		"Invalid character body option '%s': %s"
		% [option.option_id, option_errors]
	)
	_teardown_body()
	_body_option = option
	_appearance_preset = option.appearance
	_asset_profile = option.asset_profile
	_active_body_index = (
		body_index
		if body_index >= 0 and body_index < BODY_CATALOG.options.size()
		else 0
	)
	var profile_errors := _asset_profile.validation_errors()
	assert(profile_errors.is_empty(), "Invalid current player profile: %s" % profile_errors)
	assert(
		assets.exists(_asset_profile.asset_id),
		"Current player asset '%s' cannot be resolved" % _asset_profile.asset_id
	)
	_body = assets.instantiate(_asset_profile.asset_id)
	add_child(_body)
	_uses_rigged_preview = _body.find_child("Skeleton3D", true, false) is Skeleton3D
	if _uses_rigged_preview:
		_setup_rigged_preview()
	else:
		push_warning(
			"PlayerVisual: '%s' has no skeleton; using legacy proxy bindings"
			% _asset_profile.asset_id
		)
		_collect_parts()
	_sync_procedural_critter_visibility()


func set_procedural_critter_enabled(enabled: bool) -> void:
	_procedural_critter_enabled = enabled
	if enabled and not is_instance_valid(_procedural_critter):
		_procedural_critter = ProceduralCritterPlayerScript.new()
		_procedural_critter.name = "ProceduralCritterPlayer"
		add_child(_procedural_critter)
		_procedural_critter.call("build")
		# The critter's action engine keeps the legacy animation contract:
		# its phase events surface through the same animation_event signal.
		_procedural_critter.connect(
			"action_event",
			func(action_name: String, event_name: String) -> void:
				animation_event.emit(action_name, event_name)
		)
	_sync_procedural_critter_visibility()


func procedural_critter_enabled() -> bool:
	return _procedural_critter_enabled


func _sync_procedural_critter_visibility() -> void:
	if is_instance_valid(_body):
		_body.visible = not _procedural_critter_enabled
	if is_instance_valid(_procedural_critter):
		_procedural_critter.visible = _procedural_critter_enabled


func _teardown_body() -> void:
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	if _animation_player != null:
		_animation_player.stop()
	if is_instance_valid(_body):
		_body.free()
	_body = null
	_arm_r = null
	_arm_l = null
	_head_group = null
	_tool_mount = null
	_back_mount = null
	_head_mount = null
	_animation_player = null
	_skeleton = null
	_fishing_rod = null
	_fishing_pose_modifier = null
	_seated_fishing_active = false
	_uses_rigged_preview = false
	_hair_nodes.clear()
	_eye_nodes.clear()
	_rigged_skin_nodes.clear()
	_base_body_meshes.clear()
	_body_garment_meshes.clear()
	_armor_anchors.clear()
	_body_region_mask = 0
	_appearance_assembler = CharacterAssembler.new()


func _setup_rigged_preview() -> void:
	var bounds := _visual_bounds_in(_body)
	var authored_height := maxf(bounds.size.y, 0.001)
	var preview_scale := _asset_profile.target_height / authored_height
	_skeleton = _body.find_child("Skeleton3D", true, false) as Skeleton3D
	_animation_player = _body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_assemble_default_appearance()
	_prepare_embedded_animation_library()
	var rig_errors := _asset_profile.rig_validation_errors(
		_skeleton, _animation_player
	)
	assert(
		rig_errors.is_empty(),
		"Invalid rig for player profile '%s': %s"
		% [_asset_profile.profile_id, rig_errors]
	)
	if (
		_animation_player != null
		and _animation_player.has_animation(_asset_profile.idle_clip_name)
	):
		if _asset_profile.animation_updates_in_physics:
			# CharacterBody3D advances in physics. Advancing its skeleton in the
			# same clock prevents render/physics beat-frequency judder.
			_animation_player.callback_mode_process = (
				AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
			)
		var idle := _animation_player.get_animation(_asset_profile.idle_clip_name)
		idle.loop_mode = Animation.LOOP_LINEAR
		_animation_player.play(_asset_profile.idle_clip_name)
		# Apply frame zero immediately. Mixamo's clip translates the hips from
		# the centered bind pose into a ground-relative animated pose.
		_animation_player.seek(0.0, true)
	else:
		push_warning(
			"PlayerVisual: '%s' is missing idle clip '%s'"
			% [_asset_profile.asset_id, _asset_profile.idle_clip_name]
		)
	_body.scale = Vector3.ONE * preview_scale
	_body_base_rotation = Vector3(
		0.0, deg_to_rad(_asset_profile.model_yaw_degrees), 0.0
	)
	_body.rotation = _body_base_rotation
	_body_base_position = Vector3(
		0.0, _animated_ground_offset(bounds, preview_scale), 0.0
	)
	_body.position = _body_base_position
	_apply_authored_materials()
	_collect_rigged_customization_parts()
	_capture_base_body_meshes()
	_tool_mount = _make_bone_mount(
		"ToolMount", _asset_profile.tool_bone, preview_scale
	)
	_head_mount = _make_bone_mount(
		"HeadMount", _asset_profile.head_bone, preview_scale
	)
	_back_mount = _make_bone_mount(
		"BackMount", _asset_profile.back_bone, preview_scale
	)
	_install_armor_anchors(preview_scale)
	_fishing_pose_modifier = FishingPoseModifierScript.new()
	_fishing_pose_modifier.name = "FishingSeatedPose"
	_fishing_pose_modifier.active = false
	_fishing_pose_modifier.influence = 0.0
	_skeleton.add_child(_fishing_pose_modifier)
	_install_walk_animation()
	_install_action_animations()
	_locomotion_clip = _asset_profile.idle_clip_name
	if _asset_profile.animation_updates_in_physics:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()


## The default appearance is pure data: a CharacterAppearancePreset assembled
## onto the mannequin through the shared CharacterAssembler. Changing the
## player's face, hair, or future clothing means editing resources, not this
## class.
func _assemble_default_appearance() -> void:
	if _skeleton == null:
		return
	if not _appearance_assembler.assemble_onto(_body, _appearance_preset):
		push_warning(
			"PlayerVisual: default appearance failed to assemble: %s"
			% ", ".join(_appearance_assembler.last_warnings)
		)


func _install_walk_animation() -> void:
	if _asset_profile.walk_animation == null:
		return
	install_rig_animation(
		_asset_profile.walk_clip_name,
		_asset_profile.walk_animation,
		Animation.LOOP_LINEAR
	)


func _install_action_animations() -> void:
	for action_name in _asset_profile.action_animations:
		var source := (
			_asset_profile.action_animations[action_name] as Animation
		)
		if source == null:
			continue
		install_rig_animation(
			StringName(action_name),
			source,
			(
				Animation.LOOP_LINEAR
				if _asset_profile.looping_action_clips.has(action_name)
				else Animation.LOOP_NONE
			)
		)


func install_rig_animation(
	clip_name: StringName,
	source: Animation,
	loop_mode := Animation.LOOP_NONE
) -> void:
	if _animation_player == null or source == null:
		return
	var library := _animation_player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library("", library)
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	var clip := source.duplicate(true) as Animation
	clip.resource_name = str(clip_name)
	clip.loop_mode = loop_mode
	_retarget_animation_to_live_skeleton(clip)
	_normalize_animation_in_place(clip)
	library.add_animation(clip_name, clip)


func _prepare_embedded_animation_library() -> void:
	if _animation_player == null:
		return
	var source_library := _animation_player.get_animation_library("")
	if source_library == null:
		return
	var runtime_library := AnimationLibrary.new()
	for clip_name in source_library.get_animation_list():
		var source := source_library.get_animation(clip_name)
		var clip := source.duplicate(true) as Animation
		clip.resource_name = source.resource_name
		_retarget_animation_to_live_skeleton(clip)
		_normalize_animation_in_place(clip)
		runtime_library.add_animation(clip_name, clip)
	_animation_player.remove_animation_library("")
	_animation_player.add_animation_library("", runtime_library)


func _retarget_animation_to_live_skeleton(animation: Animation) -> void:
	if _animation_player == null or _skeleton == null:
		return
	var animation_root := _animation_player.get_node_or_null(
		_animation_player.root_node
	)
	if animation_root == null:
		return
	var skeleton_path := animation_root.get_path_to(_skeleton)
	for track_index in animation.get_track_count():
		var source_path := String(animation.track_get_path(track_index))
		if not source_path.contains(":"):
			continue
		var bone_name := source_path.get_slice(":", 1)
		if _skeleton.find_bone(bone_name) < 0:
			continue
		animation.track_set_path(
			track_index,
			NodePath("%s:%s" % [skeleton_path, bone_name])
		)


func _normalize_animation_in_place(animation: Animation) -> int:
	return PlayerAnimationUtils.normalize_in_place(
		animation,
		_asset_profile.hips_bone
	)


func _is_root_motion_track(animation: Animation, track_index: int) -> bool:
	return PlayerAnimationUtils.is_root_motion_track(
		animation,
		track_index,
		_asset_profile.hips_bone
	)


func _set_locomotion(walking: bool, blend_seconds := -1.0) -> void:
	if _animation_player == null:
		return
	var clip := (
		_asset_profile.walk_clip_name
		if walking
		else _asset_profile.idle_clip_name
	)
	if (
		clip == _locomotion_clip
		and _animation_player.current_animation == clip
	):
		return
	_locomotion_walking = walking
	_locomotion_clip = clip
	_locomotion_transition_count += 1
	_animation_player.speed_scale = 1.0
	_animation_player.play(
		clip,
		(
			_asset_profile.locomotion_blend_seconds
			if blend_seconds < 0.0
			else blend_seconds
		)
	)


func _animated_ground_offset(bounds: AABB, preview_scale: float) -> float:
	if _skeleton == null or _animation_player == null:
		return -bounds.position.y * preview_scale
	var skeleton_to_body := (
		_body.global_transform.affine_inverse() * _skeleton.global_transform
	)
	var lowest_rest_y := INF
	var animated_y_for_lowest := 0.0
	for bone_name in [
		_asset_profile.left_toe_bone,
		_asset_profile.right_toe_bone,
	]:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var rest_y := (
			skeleton_to_body * _skeleton.get_bone_global_rest(bone_index).origin
		).y
		if rest_y < lowest_rest_y:
			lowest_rest_y = rest_y
			animated_y_for_lowest = (
				skeleton_to_body * _skeleton.get_bone_global_pose(bone_index).origin
			).y
	if is_inf(lowest_rest_y):
		return -bounds.position.y * preview_scale
	# Preserve the authored sole thickness below the toe bone while grounding
	# against the animated pose rather than the centered bind pose.
	var sole_margin := bounds.position.y - lowest_rest_y
	var animated_mesh_min_y := animated_y_for_lowest + sole_margin
	return -animated_mesh_min_y * preview_scale


## Live animated sole anchors for terrain presentation. Gameplay remains
## capsule-driven; soft ground consumes only these world-space X/Z positions
## so swapping the temporary character asset never couples terrain to its rig.
func foot_world_positions() -> Array[Vector3]:
	if _procedural_critter_enabled and is_instance_valid(_procedural_critter):
		var critter_feet: Array[Vector3] = []
		for foot_position in _procedural_critter.call("foot_world_positions"):
			critter_feet.append(foot_position as Vector3)
		if critter_feet.size() == 2:
			return critter_feet
	var result: Array[Vector3] = []
	if _skeleton != null and _asset_profile != null:
		for bone_name in [
			_asset_profile.left_toe_bone,
			_asset_profile.right_toe_bone,
		]:
			var bone_index := _skeleton.find_bone(bone_name)
			if bone_index >= 0:
				result.append(_skeleton.to_global(
					_skeleton.get_bone_global_pose(bone_index).origin
				))
	if result.size() == 2:
		return result
	# A future non-rigged preview still gets deterministic left/right contact
	# points until its own asset profile provides sole anchors.
	result.clear()
	result.append(to_global(Vector3(-0.11, 0.0, 0.03)))
	result.append(to_global(Vector3(0.11, 0.0, 0.03)))
	return result


func _apply_authored_materials() -> void:
	if _asset_profile.material_shader == null:
		return
	for child in _body.find_children("*", "MeshInstance3D", true, false):
		_apply_authored_material_to(child as MeshInstance3D)


func _apply_authored_material_to(mesh_instance: MeshInstance3D) -> void:
	if _asset_profile.material_shader == null or mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_active_material(surface_index)
		if not source is BaseMaterial3D:
			push_warning(
				"PlayerVisual: leaving unsupported player material '%s' unchanged"
				% (source.get_class() if source != null else "null")
			)
			continue
		var base := source as BaseMaterial3D
		var styled := ShaderMaterial.new()
		# Preserve authored semantic markers such as "NoTint"; the character
		# assembler uses them to keep eye highlights, teeth, and tongues from
		# inheriting palette colors.
		styled.resource_name = "%s_palette_surface_%d_%s" % [
			_asset_profile.profile_id, surface_index, source.resource_name
		]
		styled.shader = _asset_profile.material_shader
		styled.set_shader_parameter("albedo_texture", base.albedo_texture)
		styled.set_shader_parameter("base_albedo", base.albedo_color)
		styled.set_shader_parameter("palette_tint", _asset_profile.material_tint())
		styled.set_shader_parameter(
			"saturation", _asset_profile.material_saturation
		)
		styled.set_shader_parameter(
			"value_scale", _asset_profile.material_value_scale
		)
		styled.set_shader_parameter(
			"roughness_value", _asset_profile.material_roughness
		)
		styled.set_shader_parameter(
			"specular_value", _asset_profile.material_specular
		)
		mesh_instance.set_surface_override_material(surface_index, styled)


func _capture_base_body_meshes() -> void:
	_base_body_meshes.clear()
	var modular_body := _primary_body_mesh()
	if modular_body != null:
		_base_body_meshes.append(modular_body)
		return
	for child in _body.find_children("*", "MeshInstance3D", true, false):
		_base_body_meshes.append(child as MeshInstance3D)


func _install_armor_anchors(preview_scale: float) -> void:
	_armor_anchors.clear()
	for region_name in PlayerArmorRegions.names():
		var attachment := BoneAttachment3D.new()
		attachment.name = "ArmorAttachment_%s" % region_name
		attachment.bone_name = String(
			_asset_profile.armor_region_bones[region_name]
		)
		_skeleton.add_child(attachment)
		var anchor := Node3D.new()
		anchor.name = "ArmorAnchor_%s" % region_name
		# Armor assets are authored in world meters, so cancel the preview
		# model's root scale just like the existing equipment mounts.
		anchor.scale = Vector3.ONE / preview_scale
		attachment.add_child(anchor)
		_armor_anchors[region_name] = anchor


func armor_anchor(region_name: String) -> Node3D:
	return _armor_anchors.get(region_name) as Node3D


func _set_body_region_mask(regions: Array[String]) -> void:
	# Preset clothing (via the assembler) and equipped garments both cover
	# body regions; the body mask is their union.
	var combined: Array[String] = regions.duplicate()
	if _uses_rigged_preview:
		for region in _appearance_assembler.hidden_regions():
			if not combined.has(region):
				combined.append(region)
	var unknown := PlayerArmorRegions.unknown_regions(combined)
	assert(
		unknown.is_empty(),
		"Unknown player armor regions: %s" % ", ".join(unknown)
	)
	var next_mask := PlayerArmorRegions.mask_for(combined)
	if next_mask == _body_region_mask:
		return
	_body_region_mask = next_mask
	for mesh_instance in _base_body_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.set_instance_shader_parameter(
				"hide_mask", _body_region_mask
			)
	for mesh_instance in _body_garment_meshes:
		if (
			is_instance_valid(mesh_instance)
			and mesh_instance.name.begins_with("BodyExposedFor")
		):
			mesh_instance.set_instance_shader_parameter(
				"hide_mask", _body_region_mask
			)


func _clear_body_garment() -> void:
	for mesh_instance in _body_garment_meshes:
		if is_instance_valid(mesh_instance):
			if mesh_instance.name.begins_with("BodyExposedFor"):
				mesh_instance.set_instance_shader_parameter("hide_mask", 0)
			if mesh_instance.mesh != null:
				for surface_index in mesh_instance.mesh.get_surface_count():
					mesh_instance.set_surface_override_material(
						surface_index, null
					)
			if mesh_instance.get_parent() != null:
				mesh_instance.get_parent().remove_child(mesh_instance)
			mesh_instance.queue_free()
	_body_garment_meshes.clear()
	for mesh_instance in _base_body_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.visible = true
	_set_body_region_mask([])


func _attach_skinned_body_bundle(asset_id: String) -> bool:
	if _skeleton == null or asset_id == "" or not assets.exists(asset_id):
		return false
	if _primary_body_mesh() != null:
		# Existing body-slot bundles were fitted to the retired character and
		# are deliberately ignored until wardrobe assets are authored for this
		# production body.
		return false
	var bundle := assets.instantiate(asset_id)
	var source_skeleton := (
		bundle.find_child("Skeleton3D", true, false) as Skeleton3D
	)
	if source_skeleton == null:
		push_warning(
			"PlayerVisual: body garment '%s' has no Skeleton3D" % asset_id
		)
		bundle.free()
		return false

	var source_meshes: Array[MeshInstance3D] = []
	for child in source_skeleton.find_children(
		"*", "MeshInstance3D", true, false
	):
		source_meshes.append(child as MeshInstance3D)
	var has_garment := false
	var has_exposed_body := false
	for mesh_instance in source_meshes:
		var skeleton_space := mesh_instance.transform
		var ancestor := mesh_instance.get_parent()
		while ancestor != source_skeleton:
			if not ancestor is Node3D:
				push_warning(
					"PlayerVisual: body garment '%s' has an invalid mesh hierarchy"
					% asset_id
				)
				bundle.free()
				_clear_body_garment()
				return false
			skeleton_space = (ancestor as Node3D).transform * skeleton_space
			ancestor = ancestor.get_parent()
		mesh_instance.get_parent().remove_child(mesh_instance)
		mesh_instance.owner = null
		_skeleton.add_child(mesh_instance)
		mesh_instance.transform = skeleton_space
		mesh_instance.skeleton = NodePath("..")
		_body_garment_meshes.append(mesh_instance)
		if mesh_instance.name.begins_with("BodyExposedFor"):
			has_exposed_body = true
			_apply_authored_material_to(mesh_instance)
		else:
			has_garment = true
	bundle.free()

	if not has_garment or not has_exposed_body:
		push_warning(
			"PlayerVisual: body garment '%s' must include a garment and "
			+ "BodyExposedFor* mesh" % asset_id
		)
		_clear_body_garment()
		return false
	for mesh_instance in _base_body_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.visible = false
	return true


func _visual_bounds_in(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_point := false
	var root_inverse := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.get_aabb()
		var relative := root_inverse * mesh_instance.global_transform
		for corner in 8:
			var point := relative * mesh_bounds.get_endpoint(corner)
			if not has_point:
				bounds = AABB(point, Vector3.ZERO)
				has_point = true
			else:
				bounds = bounds.expand(point)
	return bounds


func _make_bone_mount(mount_name: String, bone_name: String, preview_scale: float) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sAttachment" % mount_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	var mount := Node3D.new()
	mount.name = mount_name
	# Items are authored at world scale; cancel the preview model's root scale.
	mount.scale = Vector3.ONE / preview_scale
	attachment.add_child(mount)
	return mount


func _collect_parts() -> void:
	_hair_nodes.clear()
	_eye_nodes.clear()
	for i in 4:
		var hair := _find("Hair%02d" % i)
		if hair != null:
			_hair_nodes.append(hair)
	# The bun/fall sub-meshes follow their parent style visibility.
	for extra_name in [
		"Hair00_bangL", "Hair00_bangR", "Hair01_tuft",
		"Hair02_bun", "Hair03_fall",
	]:
		var extra := _find(extra_name)
		if extra != null:
			_hair_nodes.append(extra)
	for eye_name in ["EyeL", "EyeR", "EyeHighlightL", "EyeHighlightR"]:
		var eye := _find(eye_name) as MeshInstance3D
		if eye != null:
			_eye_nodes.append(eye)

	# Shoulder pivots so arms swing naturally; hands ride along.
	_arm_r = _wrap_pivot("ArmRPivot", Vector3(0.22, 0.66, 0.0), ["ArmR", "HandR"])
	_arm_l = _wrap_pivot("ArmLPivot", Vector3(-0.22, 0.66, 0.0), ["ArmL", "HandL"])
	_head_group = _wrap_pivot("HeadPivot", Vector3(0, 0.69, 0), [
		"Head", "EarL", "EarR", "EyeL", "EyeR", "EyeHighlightL",
		"EyeHighlightR", "Nose", "CheekL", "CheekR", "MouthL", "MouthR",
		"Hair00", "Hair00_bangL", "Hair00_bangR", "Hair01", "Hair01_tuft",
		"Hair02", "Hair02_bun", "Hair03", "Hair03_fall",
	])

	_tool_mount = Node3D.new()
	_tool_mount.name = "ToolMount"
	_tool_mount.position = Vector3(0.05, -0.36, -0.06)  # at the hand, relative to shoulder pivot
	_arm_r.add_child(_tool_mount)
	_back_mount = Node3D.new()
	_back_mount.name = "BackMount"
	_back_mount.position = Vector3(0, 0.72, 0.24)
	add_child(_back_mount)
	_head_mount = Node3D.new()
	_head_mount.name = "HeadMount"
	_head_mount.position = Vector3(0, 0.42, 0)
	_head_group.add_child(_head_mount)


func _collect_rigged_customization_parts() -> void:
	_hair_nodes.clear()
	_eye_nodes.clear()
	_rigged_skin_nodes.clear()
	var body_mesh := _primary_body_mesh()
	if body_mesh != null:
		_rigged_skin_nodes.append(body_mesh)
	var hair_root := _appearance_assembler.equipped_node(CharacterSlots.HAIR)
	if hair_root != null:
		_hair_nodes.append(hair_root)
	var eyes_root := _appearance_assembler.equipped_node(CharacterSlots.EYES)
	if eyes_root != null:
		_eye_nodes.append(eyes_root)
	_update_hair_visibility()


func _primary_body_mesh() -> MeshInstance3D:
	for node_name in ["PlayerMaleBody", "PlayerFemaleBody"]:
		var candidate := _find(node_name) as MeshInstance3D
		if candidate != null:
			return candidate
	return null


func _find(node_name: String) -> Node3D:
	return _body.find_child(node_name, true, false) as Node3D


func _wrap_pivot(pivot_name: String, pivot_pos: Vector3, part_names: Array) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	_body.add_child(pivot)
	pivot.position = pivot_pos
	for part_name in part_names:
		var part := _find(part_name)
		if part == null or part == pivot or part.get_parent() == pivot:
			continue
		var global := part.global_transform
		part.get_parent().remove_child(part)
		pivot.add_child(part)
		part.global_transform = global
	return pivot


# ------------------------------------------------------------------ customization

func apply_profile(profile: PlayerProfile) -> void:
	if profile.body_index != _active_body_index:
		_switch_body(profile.body_index)
	if _uses_rigged_preview:
		_apply_rigged_profile(profile)
		return
	var design_palette := palette as PaletteDefinition
	var skin_swatches := design_palette.character_swatches("skin")
	var hair_swatches := design_palette.character_swatches("hair")
	var outfit_swatches := design_palette.character_swatches("outfit")
	var skin := skin_swatches[clampi(profile.skin_index, 0, skin_swatches.size() - 1)]
	var hair := hair_swatches[clampi(profile.hair_color_index, 0, hair_swatches.size() - 1)]
	var outfit := outfit_swatches[clampi(profile.outfit_index, 0, outfit_swatches.size() - 1)]
	_tint_parts(["Head", "EarL", "EarR", "HandL", "HandR"], materials.tinted("skin", skin))
	_tint_parts(["Nose"], materials.tinted("skin", skin.darkened(0.08)))
	_tint_parts(["CheekL", "CheekR"], materials.tinted("petal_pink", skin.lerp(palette.color("petal_pink"), 0.34)))
	_tint_parts([
		"Hair00", "Hair00_bangL", "Hair00_bangR", "Hair01", "Hair01_tuft",
		"Hair02", "Hair02_bun", "Hair03", "Hair03_fall",
	], materials.tinted("hair", hair))
	_tint_parts(["Torso", "ArmL", "ArmR"], materials.tinted("fabric", outfit))
	_tint_parts(["Belt", "Collar"], materials.material("fabric_accent"))
	for i in _hair_nodes.size():
		var node := _hair_nodes[i]
		var style_index := profile.hair_style
		node.visible = node.name.begins_with("Hair%02d" % style_index)
	match profile.eye_index:
		1:  # sleepy
			for eye in _eye_nodes:
				eye.scale = Vector3(1.0, 0.55, 1.0)
		2:  # bright
			for eye in _eye_nodes:
				eye.scale = Vector3(1.3, 1.3, 1.3)
		_:
			for eye in _eye_nodes:
				eye.scale = Vector3.ONE


func _apply_rigged_profile(profile: PlayerProfile) -> void:
	_apply_catalog_parts(profile)
	var design_palette := palette as PaletteDefinition
	var skin_swatches := design_palette.character_swatches("skin")
	var hair_swatches := design_palette.character_swatches("hair")
	var skin := skin_swatches[
		clampi(profile.skin_index, 0, skin_swatches.size() - 1)
	]
	var hair := hair_swatches[
		clampi(profile.hair_color_index, 0, hair_swatches.size() - 1)
	]
	_active_hair_style = clampi(
		profile.hair_style, 0, maxi(PART_CATALOG.hair.size() - 1, 0)
	)
	for skin_node in _rigged_skin_nodes:
		_set_rigged_mesh_color(skin_node, skin)
	_appearance_assembler.apply_color(CharacterSlots.NOSE, skin)
	_appearance_assembler.apply_color(CharacterSlots.HAIR, hair)
	_appearance_assembler.apply_color(CharacterSlots.EYEBROWS, hair)
	_appearance_assembler.apply_color(CharacterSlots.MOUSTACHE, hair)
	_appearance_assembler.apply_color(
		CharacterSlots.EYES, palette.color("eyes")
	)
	_appearance_assembler.apply_color(
		CharacterSlots.MOUTH, _appearance_preset.mouth_color
	)
	_update_hair_visibility()
	for eye in _eye_nodes:
		eye.scale = Vector3.ONE


func _apply_catalog_parts(profile: PlayerProfile) -> void:
	var requested := {
		CharacterSlots.HAIR: profile.hair_style,
		CharacterSlots.EYES: profile.eye_index,
		CharacterSlots.MOUTH: profile.mouth_index,
		CharacterSlots.NOSE: profile.nose_index,
	}
	var changed := false
	for slot in requested:
		var part := PART_CATALOG.part_for(slot, int(requested[slot]))
		if part == null:
			continue
		var current := _appearance_assembler.equipped_part(slot)
		if current != null and current.part_id == part.part_id:
			continue
		if _appearance_assembler.replace_rigid_part(
			part, _appearance_preset
		):
			_style_assembled_part(slot)
			changed = true
	if changed:
		_collect_rigged_customization_parts()


func _style_assembled_part(slot: String) -> void:
	var root := _appearance_assembler.equipped_node(slot)
	if root == null:
		return
	if root is MeshInstance3D:
		_apply_authored_material_to(root as MeshInstance3D)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		_apply_authored_material_to(child as MeshInstance3D)


func _set_rigged_mesh_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_surface_override_material(surface_index)
		if material is ShaderMaterial:
			var styled := material as ShaderMaterial
			styled.set_shader_parameter("base_albedo", color)
			styled.set_shader_parameter(
				"palette_tint",
				palette.color("neutral_white")
			)
			styled.set_shader_parameter("saturation", 1.0)
			styled.set_shader_parameter("value_scale", 1.0)


func _update_hair_visibility() -> void:
	if _uses_rigged_preview:
		_appearance_assembler.set_slot_visible(
			CharacterSlots.HAIR, not _hair_hidden_by_headwear
		)
		return
	for hair_node in _hair_nodes:
		hair_node.visible = (
			not _hair_hidden_by_headwear
			and hair_node.name == "Hair%02d" % _active_hair_style
		)


func _tint_parts(part_names: Array, mat: Material) -> void:
	for part_name in part_names:
		var part := _find(part_name) as MeshInstance3D
		if part == null:
			continue
		for surface in part.mesh.get_surface_count():
			part.set_surface_override_material(surface, mat)


## Equipment: rigid items use bone mounts; body garments share the live skeleton.
func apply_equipment(equipment: EquipmentManager, held_tool_type := "") -> void:
	_fishing_rod = null
	for mount in [_tool_mount, _back_mount, _head_mount]:
		if mount == null:
			continue
		for child in mount.get_children():
			child.queue_free()
	var held: Defs.ItemDefinition = null
	if held_tool_type != "":
		held = equipment.best_tool(held_tool_type)
		if held == null:
			held = (
				equipment.equipped_in("weapon")
				if held_tool_type == "weapon"
				else equipment.equipped_in("tool")
			)
	if held_tool_type == "rod" and _tool_mount != null:
		_fishing_rod = FishingRodScript.new()
		_fishing_rod.name = "FishingRod"
		_fishing_rod.position = Vector3(0.015, 0.018, -0.02)
		_fishing_rod.rotation_degrees = (
			Vector3(-8.0, -4.0, -18.0)
			if _uses_rigged_preview
			else Vector3(-4.0, 2.0, -5.0)
		)
		_tool_mount.add_child(_fishing_rod)
		_fishing_rod.set_idle_active(_seated_fishing_active)
	elif held != null and held.asset_id != "":
		var tool_visual := assets.instantiate(held.asset_id)
		tool_visual.rotation_degrees = (
			Vector3(0, 0, -70) if _uses_rigged_preview else Vector3(-52, 0, 0)
		)
		_tool_mount.add_child(tool_visual)
	var head_item := equipment.equipped_in("head")
	if head_item != null and head_item.asset_id != "":
		var head_visual := assets.instantiate(head_item.asset_id)
		head_visual.scale = Vector3.ONE * 1.35
		_head_mount.add_child(head_visual)
	_hair_hidden_by_headwear = (
		_uses_rigged_preview
		and head_item != null
		and head_item.asset_id != ""
	)
	_update_hair_visibility()
	var back_item := equipment.equipped_in("back")
	if back_item != null and back_item.asset_id != "":
		_back_mount.add_child(assets.instantiate(back_item.asset_id))
	_clear_body_garment()
	var body_item := equipment.equipped_in("body")
	if body_item != null:
		if _uses_rigged_preview and body_item.asset_id != "":
			_attach_skinned_body_bundle(body_item.asset_id)
		elif not _uses_rigged_preview:
			_tint_parts(
				["Torso", "ArmL", "ArmR"],
				materials.tinted(
					"fabric", palette.color("moss").lightened(0.1)
				)
			)
		_set_body_region_mask(body_item.hide_regions)


# ------------------------------------------------------------------ presentation sockets

## A stable live endpoint for the procedural fishing line. The authored rod
## remains free to change; the line follows the active hand mount and extends
## toward the cast instead of depending on a particular mesh or bone name.
func fishing_line_origin(cast_point: Vector3) -> Vector3:
	if is_instance_valid(_fishing_rod):
		var marker := _fishing_rod.line_origin()
		if is_instance_valid(marker):
			return marker.global_position
	var hand := (
		_tool_mount.global_position
		if is_instance_valid(_tool_mount)
		else global_position + Vector3.UP * 0.78
	)
	var toward := cast_point - hand
	toward.y = 0.0
	if toward.length_squared() <= 0.0001:
		toward = -global_basis.z
	else:
		toward = toward.normalized()
	return hand + toward * 0.58 + Vector3.UP * 0.2


## Pins the held rod's world yaw to the given heading. The hand mount keeps
## positioning the rod, but its orientation is world-exact: the shaft always
## points straight over the cast edge no matter how the hands animate.
func align_fishing_rod(yaw: float) -> void:
	if is_instance_valid(_fishing_rod):
		_fishing_rod.global_rotation = Vector3(0.0, yaw, 0.0)


## Relays the cast to the held rod: a wrist flick that visibly throws the
## line out in the direction the keeper faces.
func cast_fishing_rod() -> void:
	if is_instance_valid(_fishing_rod):
		_fishing_rod.cast_flick()


## Relays a bite to the held rod so its tip visibly dips the moment the
## luminous line reacts, keeping rod and line in the same beat.
func bite_fishing_rod() -> void:
	if is_instance_valid(_fishing_rod):
		_fishing_rod.bite_dip()


## Blends the authored fishing hand/head motion into a relaxed seated lower
## body without swapping out the current production character.
func set_seated_fishing(active: bool, blend_seconds := 0.42) -> void:
	_seated_fishing_active = active
	if is_instance_valid(_fishing_rod):
		_fishing_rod.set_idle_active(active)
	if _fishing_pose_modifier == null:
		return
	_fishing_pose_modifier.active = true
	var target := 1.0 if active else 0.0
	var tween := create_tween()
	tween.tween_property(
		_fishing_pose_modifier,
		"influence",
		target,
		maxf(0.01, blend_seconds)
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if not active:
		tween.tween_callback(func():
			if (
				is_instance_valid(_fishing_pose_modifier)
				and not _seated_fishing_active
			):
				_fishing_pose_modifier.active = false
		)


## Where a newly retrieved miniature build piece rests while its discovery
## card is open. This intentionally uses a character-level contract instead
## of exposing the procedural/rigged body hierarchy to world effects.
func reward_hold_world_position() -> Vector3:
	return (
		global_position
		+ Vector3.UP * 0.86
		- global_basis.z * 0.28
		- global_basis.x * 0.16
	)


# ------------------------------------------------------------------ animation

func set_walk(amount: float, delta: float) -> void:
	# Above 1.0 means sprinting: the stride quickens and a light run wobble
	# rolls the body. 1.6 matches the sprint speed multiplier's ceiling.
	_walk_amount = lerpf(
		_walk_amount,
		clampf(amount, 0.0, 1.6),
		minf(1.0, 12.0 * delta)
	)
	_walk_phase += delta * WALK_BOB_HZ * (0.4 + 0.6 * _walk_amount)
	_idle_phase += delta * TAU / 2.4
	if _current_anim != "idle":
		return
	var gait := minf(_walk_amount, 1.0)
	var sprint_blend := clampf((_walk_amount - 1.0) / 0.6, 0.0, 1.0)
	var bob := absf(sin(_walk_phase)) * 0.05 * gait
	if _uses_rigged_preview:
		var wants_walk := _walk_amount > (0.06 if _locomotion_walking else 0.14)
		_set_locomotion(wants_walk)
		_animation_player.speed_scale = (
			lerpf(
				_asset_profile.walk_speed_scale_min,
				_asset_profile.walk_speed_scale_max,
				gait
			) * (1.0 + 0.45 * sprint_blend)
			if wants_walk
			else 1.0
		)
		# The authored clips own the gait (no root rewrites — they invalidate
		# physics interpolation), but a gentle roll on the body wrapper sells
		# the sprint wobble without touching root translation.
		_body.rotation.z = lerpf(
			_body.rotation.z,
			sin(_walk_phase) * 0.055 * sprint_blend,
			minf(1.0, 10.0 * delta)
		)
		return
	if _walk_amount < 0.05:
		bob += sin(_idle_phase) * 0.006
		_head_group.rotation.z = sin(_idle_phase * 0.5) * 0.008
	else:
		_head_group.rotation.z = lerpf(_head_group.rotation.z, 0.0, minf(1.0, delta * 8.0))
	_body.position.y = bob + absf(sin(_walk_phase)) * 0.02 * sprint_blend
	# Sprinting leans further into the run and rolls side to side.
	_body.rotation.x = gait * 0.06 + sprint_blend * 0.07
	_body.rotation.z = sin(_walk_phase) * 0.055 * sprint_blend
	var swing := sin(_walk_phase) * 0.55 * minf(_walk_amount, 1.25)
	_arm_r.rotation.x = swing
	_arm_l.rotation.x = -swing


func play(anim: String, cycle_duration := -1.0) -> void:
	if not ANIMATION_MANIFEST.has(anim):
		return
	if _procedural_critter_enabled and is_instance_valid(_procedural_critter):
		var previous := _current_anim
		if previous != "idle" and previous != anim:
			animation_finished.emit(previous)
		_current_anim = anim
		animation_started.emit(anim)
		_procedural_critter.call("play_action", anim, cycle_duration)
		return
	if _uses_rigged_preview and _continue_authored_loop(anim, cycle_duration):
		return
	var previous_anim := _current_anim
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	if previous_anim != "idle" and previous_anim != anim:
		animation_finished.emit(previous_anim)
	_current_anim = anim
	animation_started.emit(anim)
	if _uses_rigged_preview:
		_play_rigged_preview(anim, cycle_duration)
		return
	_action_tween = create_tween()
	match anim:
		"idle":
			_action_tween.tween_property(_arm_r, "rotation", Vector3.ZERO, 0.18)
			_action_tween.parallel().tween_property(_arm_l, "rotation", Vector3.ZERO, 0.18)
			_action_tween.parallel().tween_property(_body, "rotation", Vector3.ZERO, 0.18)
			_action_tween.tween_callback(func():
				_current_anim = "idle"
				animation_finished.emit("idle")
			)
			_current_anim = "idle"
		"fish_cast":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.2, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "release"))
			_action_tween.tween_property(_arm_r, "rotation:x", -0.9, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		"fish_wait":
			_action_tween.tween_property(_arm_r, "rotation:x", -0.95, 0.4)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.85, 0.9).set_trans(Tween.TRANS_SINE)
			_action_tween.set_loops()
		"fish_catch":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.5, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "rotation:x", -0.12, 0.14)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_interval(0.35)
			_action_tween.tween_property(_body, "rotation:x", 0.0, 0.2)
		"chop":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.4, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "rotation:y", 0.16, 0.28)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.3, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			_action_tween.parallel().tween_property(_body, "rotation:y", -0.08, 0.1)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_property(_body, "rotation:y", 0.0, 0.14)
		"attack":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.1, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_arm_r, "rotation:x", 0.5, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_property(_arm_r, "rotation:x", 0.0, 0.16)
		"dodge":
			_action_tween.tween_property(_body, "rotation:x", 0.5, 0.1)
			_action_tween.tween_property(_body, "rotation:x", 0.0, 0.2)
		"hit":
			animation_event.emit(anim, "flash")
			_flash(palette.color("vfx_player_damage_flash"))
			_action_tween.tween_property(_body, "position:x", 0.07, 0.05)
			_action_tween.tween_property(_body, "position:x", -0.05, 0.05)
			_action_tween.tween_property(_body, "position:x", 0.0, 0.08)
		"celebrate":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.9, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_arm_l, "rotation:x", -2.9, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "position:y", 0.16, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "apex"))
			_action_tween.tween_property(_body, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_arm_r, "rotation:x", 0.0, 0.3)
			_action_tween.parallel().tween_property(_arm_l, "rotation:x", 0.0, 0.3)
	if anim != "idle" and anim != "fish_wait":
		_action_tween.tween_callback(func():
			_current_anim = "idle"
			animation_finished.emit(anim)
		)


func _play_rigged_preview(anim: String, cycle_duration: float) -> void:
	if _asset_profile.action_animations.has(anim):
		_play_authored_action(anim, cycle_duration)
		return
	if anim != "idle" and not (
		_seated_fishing_active and anim == "fish_catch"
	):
		_set_locomotion(false, 0.16)
	_action_tween = create_tween()
	match anim:
		"idle":
			_set_locomotion(_walk_amount > 0.12)
			_action_tween.tween_property(_body, "position", _body_base_position, 0.18)
			_action_tween.parallel().tween_property(
				_body, "rotation", _body_base_rotation, 0.18
			)
			_action_tween.tween_callback(func():
				_current_anim = "idle"
				animation_finished.emit("idle")
			)
			_current_anim = "idle"
		"fish_cast":
			_rigged_timed_action(
				anim,
				0.22,
				0.38,
				_body_base_rotation + Vector3(-0.10, 0.0, -0.08),
				"release"
			)
		"fish_wait":
			_action_tween.tween_property(
				_body, "position", _body_base_position + Vector3.UP * 0.018, 0.65
			).set_trans(Tween.TRANS_SINE)
			_action_tween.tween_property(
				_body, "position", _body_base_position, 0.65
			).set_trans(Tween.TRANS_SINE)
			_action_tween.set_loops()
		"fish_catch":
			if _seated_fishing_active:
				_action_tween.tween_property(
					_body,
					"rotation",
					_body_base_rotation + Vector3(-0.13, 0.0, 0.0),
					0.14
				).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				_action_tween.tween_callback(
					func(): animation_event.emit(anim, "impact")
				)
				_action_tween.tween_property(
					_body,
					"rotation",
					_body_base_rotation,
					0.55
				).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_action_tween.tween_callback(func():
					_current_anim = "fish_wait"
					animation_finished.emit(anim)
				)
			else:
				_rigged_timed_action(
					anim,
					0.14,
					0.69,
					_body_base_rotation + Vector3(-0.14, 0.0, 0.0),
					"impact"
				)
		"chop":
			_rigged_timed_action(
				anim,
				0.38,
				0.52,
				_body_base_rotation + Vector3(0.0, 0.16, -0.08),
				"impact"
			)
		"attack":
			_rigged_timed_action(
				anim,
				0.22,
				0.38,
				_body_base_rotation + Vector3(-0.08, 0.12, 0.0),
				"impact"
			)
		"dodge":
			_action_tween.tween_property(
				_body,
				"rotation",
				_body_base_rotation + Vector3(0.32, 0.0, 0.0),
				0.1
			)
			_action_tween.tween_property(
				_body, "rotation", _body_base_rotation, 0.2
			)
			_action_tween.tween_callback(func(): _finish_rigged_action(anim))
		"hit":
			animation_event.emit(anim, "flash")
			_flash(palette.color("vfx_player_damage_flash"))
			_action_tween.tween_property(
				_body, "position", _body_base_position + Vector3.RIGHT * 0.07, 0.05
			)
			_action_tween.tween_property(
				_body, "position", _body_base_position + Vector3.LEFT * 0.05, 0.05
			)
			_action_tween.tween_property(_body, "position", _body_base_position, 0.08)
			_action_tween.tween_callback(func(): _finish_rigged_action(anim))
		"celebrate":
			_action_tween.tween_property(
				_body, "position", _body_base_position + Vector3.UP * 0.16, 0.2
			).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "apex"))
			_action_tween.tween_property(
				_body, "position", _body_base_position, 0.5
			).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): _finish_rigged_action(anim))


func _play_authored_action(anim: String, cycle_duration: float) -> void:
	var clip_name := StringName(anim)
	if not _animation_player.has_animation(clip_name):
		return
	var animation := _animation_player.get_animation(clip_name)
	_animation_player.speed_scale = (
		animation.length / cycle_duration
		if cycle_duration > 0.0
		else 1.0
	)
	_animation_player.play(
		clip_name,
		_asset_profile.action_blend_seconds
	)


func _continue_authored_loop(anim: String, cycle_duration: float) -> bool:
	if (
		_animation_player == null
		or _current_anim != anim
		or not _asset_profile.looping_action_clips.has(anim)
		or _animation_player.current_animation != anim
	):
		return false
	if cycle_duration > 0.0:
		var animation := _animation_player.get_animation(anim)
		_animation_player.speed_scale = animation.length / cycle_duration
	return true


func authored_action_duration(anim: String, fallback: float) -> float:
	return float(
		_asset_profile.action_playback_seconds.get(anim, fallback)
	)


func authored_action_impact_ratio(anim: String, fallback: float) -> float:
	if _procedural_critter_enabled and is_instance_valid(_procedural_critter):
		return float(
			_procedural_critter.call("action_impact_ratio", anim, fallback)
		)
	return clampf(
		float(_asset_profile.action_impact_ratios.get(anim, fallback)),
		0.01,
		0.99
	)


func _rigged_timed_action(
	anim: String,
	event_time: float,
	duration: float,
	target_rotation: Vector3,
	event_name: String
) -> void:
	_action_tween.tween_property(_body, "rotation", target_rotation, event_time)
	_action_tween.tween_callback(func(): animation_event.emit(anim, event_name))
	_action_tween.tween_property(
		_body,
		"rotation",
		_body_base_rotation,
		maxf(0.01, duration - event_time)
	)
	_action_tween.tween_callback(func(): _finish_rigged_action(anim))


func _finish_rigged_action(anim: String) -> void:
	_body.position = _body_base_position
	_body.rotation = _body_base_rotation
	_current_anim = "idle"
	_set_locomotion(_walk_amount > 0.12)
	animation_finished.emit(anim)


func animation_manifest() -> Dictionary:
	return {
		"states": ANIMATION_MANIFEST.duplicate(true),
		"transitions": ANIMATION_TRANSITIONS.duplicate(true),
		"default_state": "idle",
		"transition_policy": {
			"interruptible": true,
			"interruption_reset": "previous tween is killed before the next state",
			"action_to_idle": "automatic on non-looping completion",
		},
	}


func _flash(color: Color) -> void:
	if _uses_rigged_preview:
		var flashes: Array[MeshInstance3D] = []
		var restores: Array[Material] = []
		var overlay := StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.albedo_color = Color(color, 0.48)
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for child in _body.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			flashes.append(mesh_instance)
			restores.append(mesh_instance.material_overlay)
			mesh_instance.material_overlay = overlay
		get_tree().create_timer(0.12).timeout.connect(func():
			for index in flashes.size():
				if is_instance_valid(flashes[index]):
					flashes[index].material_overlay = restores[index]
		)
		return
	var head := _find("Head") as MeshInstance3D
	if head == null:
		return
	var overlay := materials.tinted("skin", color)
	var restore: Material = head.get_surface_override_material(0)
	head.set_surface_override_material(0, overlay)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(head):
			head.set_surface_override_material(0, restore))
