extends SceneTree
## Narrow import smoke test for the modular Rigify-authored default player.

const PLAYER_SCENE := preload(
	"res://assets/3d/reworked/player_male_rigged.glb"
)
const WALK_ANIMATION: Animation = preload(
	"res://assets/animations/player_walk.tres"
)
const PLAYER_PROFILE: PlayerAssetProfile = preload(
	"res://assets/player/current_player_profile.tres"
)


func _initialize() -> void:
	assert(
		PLAYER_PROFILE.validation_errors().is_empty(),
		"Current player asset profile must be complete"
	)
	assert(
		not PLAYER_PROFILE.testing_only,
		"Current authored character must be production-ready"
	)
	assert(
		PLAYER_PROFILE.model_resource_path
			== "res://assets/3d/reworked/player_male_rigged.glb",
		"Probe and current player profile must target the same model"
	)
	assert(
		PLAYER_PROFILE.walk_animation == WALK_ANIMATION,
		"Current player profile must own the extracted walk animation"
	)
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	_print_tree(player)
	for node_name in [
		"PlayerMaleBody",
		"EyeL",
		"EyeR",
		"Nose",
		"Brows",
		"Moustache",
		"Mouth",
		"Hair00",
		"Hair01",
		"Hair02",
		"Hair03",
	]:
		assert(
			player.find_child(node_name, true, false) is MeshInstance3D,
			"Modular player is missing skinned mesh '%s'" % node_name
		)
	for node_name in [
		"EyeL",
		"EyeR",
		"Nose",
		"Brows",
		"Moustache",
		"Mouth",
		"Hair00",
		"Hair01",
		"Hair02",
		"Hair03",
	]:
		var module := player.find_child(
			node_name, true, false
		) as MeshInstance3D
		assert(
			module.skin == null,
			"Rigid module '%s' must not carry an independent skin"
			% node_name
		)
	var animation_player := _find_first(player, "AnimationPlayer") as AnimationPlayer
	assert(animation_player != null, "Mixamo player must import an AnimationPlayer")
	var names := animation_player.get_animation_list()
	print("MIXAMO_ANIMATIONS=", names)
	assert(names.has("mixamo_com"), "Mixamo idle animation was not imported")
	var idle := animation_player.get_animation("mixamo_com")
	print("MIXAMO_IDLE_LENGTH=", idle.length, " LOOP=", idle.loop_mode)
	var skeleton := _find_first(player, "Skeleton3D") as Skeleton3D
	assert(skeleton != null, "Mixamo player must import a Skeleton3D")
	assert(
		PLAYER_PROFILE.rig_validation_errors(
			skeleton, animation_player
		).is_empty(),
		"Current player profile must match the imported rig and walk tracks"
	)
	print("MIXAMO_BONES=", skeleton.get_bone_count())
	assert(skeleton.find_bone("mixamorigHips") >= 0, "Mixamo hips bone is missing")
	assert(
		WALK_ANIMATION.loop_mode == Animation.LOOP_LINEAR,
		"Extracted walk clip must loop"
	)
	assert(
		is_equal_approx(WALK_ANIMATION.length, 1.0333333),
		"Extracted walk clip has an unexpected duration"
	)
	var walk_root_track_found := false
	var walk_vertical_range := 0.0
	var walk_horizontal_sway := 0.0
	for track_index in WALK_ANIMATION.get_track_count():
		var track_path := String(WALK_ANIMATION.track_get_path(track_index))
		if (
			WALK_ANIMATION.track_get_type(track_index)
			== Animation.TYPE_POSITION_3D
			and track_path.ends_with(":mixamorigHips")
		):
			walk_root_track_found = true
			var key_count := WALK_ANIMATION.track_get_key_count(track_index)
			var first := WALK_ANIMATION.track_get_key_value(
				track_index, 0
			) as Vector3
			var last := WALK_ANIMATION.track_get_key_value(
				track_index, key_count - 1
			) as Vector3
			var minimum := first
			var maximum := first
			for key_index in key_count:
				var value := WALK_ANIMATION.track_get_key_value(
					track_index, key_index
				) as Vector3
				minimum = minimum.min(value)
				maximum = maximum.max(value)
			walk_vertical_range = maximum.y - minimum.y
			walk_horizontal_sway = maxf(
				maximum.x - minimum.x,
				maximum.z - minimum.z
			)
			assert(
				absf(last.x - first.x) < 0.0001
					and absf(last.z - first.z) < 0.0001,
				"Walk root must close horizontally instead of snapping on loop"
			)
		if not track_path.contains(":mixamorig"):
			continue
		var bone_name := track_path.get_slice(":", 1)
		assert(
			skeleton.find_bone(bone_name) >= 0,
			"Walk clip targets a bone absent from the idle rig: %s" % bone_name
		)
	assert(walk_root_track_found, "Walk animation has no hips position track")
	assert(
		walk_vertical_range > 0.02,
		"In-place cleanup must preserve authored vertical bounce"
	)
	assert(
		walk_horizontal_sway > 0.005,
		"In-place cleanup must preserve cyclic horizontal hips sway"
	)
	for action_name in ["fish_cast", "fish_wait", "chop"]:
		assert(
			PLAYER_PROFILE.action_animations.has(action_name),
			"Current player profile is missing authored action '%s'"
			% action_name
		)
	var fish_cast := (
		PLAYER_PROFILE.action_animations["fish_cast"] as Animation
	)
	var fish_wait := (
		PLAYER_PROFILE.action_animations["fish_wait"] as Animation
	)
	var chop := PLAYER_PROFILE.action_animations["chop"] as Animation
	assert(
		fish_cast.loop_mode == Animation.LOOP_NONE
			and is_equal_approx(fish_cast.length, 2.5),
		"Fishing cast must use the reviewed non-looping source segment"
	)
	_assert_loop_pose_closes(fish_wait, "fish_wait")
	_assert_loop_pose_closes(chop, "chop")
	var chop_arm_track := _find_track(
		chop,
		":mixamorigRightArm",
		Animation.TYPE_ROTATION_3D
	)
	assert(chop_arm_track >= 0, "Chop clip has no right-arm rotation track")
	var chop_start := chop.rotation_track_interpolate(chop_arm_track, 0.0)
	var chop_swing := chop.rotation_track_interpolate(
		chop_arm_track, chop.length * 0.5
	)
	var chop_recovery := chop.rotation_track_interpolate(
		chop_arm_track, chop.length * 0.92
	)
	assert(
		chop_start.angle_to(chop_swing) > 0.7,
		"Chop clip does not contain a substantial authored swing"
	)
	assert(
		chop_start.angle_to(chop_recovery)
			< chop_start.angle_to(chop_swing) * 0.65,
		"Chop clip must visibly recover toward its starting pose before looping"
	)
	var mesh := player.find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	assert(mesh != null and mesh.skin != null, "Player mesh must retain its skin")
	print("MIXAMO_MESH_AABB=", mesh.get_aabb())
	for surface_index in mesh.mesh.get_surface_count():
		var surface_material := mesh.mesh.surface_get_material(surface_index)
		print(
			"MIXAMO_MATERIAL[",
			surface_index,
			"]=",
			surface_material.get_class() if surface_material != null else "null"
		)
		if surface_material is BaseMaterial3D:
			var base_material := surface_material as BaseMaterial3D
			print(
				"  ALBEDO=",
				base_material.albedo_color,
				" TEXTURE=",
				base_material.albedo_texture,
				" METALLIC=",
				base_material.metallic,
				" ROUGHNESS=",
				base_material.roughness,
				" SPECULAR=",
				base_material.metallic_specular,
				" EMISSION=",
				base_material.emission_enabled
			)
	var right_arm := skeleton.find_bone("mixamorigRightArm")
	animation_player.play("mixamo_com")
	animation_player.seek(0.0, true)
	for bone_name in [
		"mixamorigHips",
		"mixamorigLeftFoot",
		"mixamorigLeftToeBase",
		"mixamorigRightFoot",
		"mixamorigRightToeBase",
	]:
		var bone_index := skeleton.find_bone(bone_name)
		print(
			"MIXAMO_POSE ",
			bone_name,
			" rest=",
			skeleton.get_bone_global_rest(bone_index).origin,
			" pose=",
			skeleton.get_bone_global_pose(bone_index).origin
		)
	var pose_at_start := skeleton.get_bone_pose(right_arm)
	animation_player.seek(1.0, true)
	var pose_after_one_second := skeleton.get_bone_pose(right_arm)
	assert(
		not pose_at_start.is_equal_approx(pose_after_one_second),
		"Idle clip must drive the imported skeleton"
	)
	var lowest_toe_min := INF
	var lowest_toe_max := -INF
	for sample in 61:
		animation_player.seek(idle.length * sample / 60.0, true)
		var lowest_toe := INF
		for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
			var toe_index := skeleton.find_bone(toe_name)
			lowest_toe = minf(
				lowest_toe, skeleton.get_bone_global_pose(toe_index).origin.y
			)
		lowest_toe_min = minf(lowest_toe_min, lowest_toe)
		lowest_toe_max = maxf(lowest_toe_max, lowest_toe)
	print("MIXAMO_LOWEST_TOE_RANGE=", lowest_toe_min, "..", lowest_toe_max)
	var library := animation_player.get_animation_library("")
	var walk_probe := WALK_ANIMATION.duplicate(true) as Animation
	_retarget_to_live_skeleton(walk_probe, animation_player, skeleton)
	library.add_animation("walk_probe", walk_probe)
	animation_player.callback_mode_process = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	)
	assert(
		animation_player.callback_mode_process
		== AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS,
		"Locomotion must advance on the CharacterBody physics clock"
	)
	animation_player.play("mixamo_com")
	animation_player.advance(0.2)
	animation_player.play("walk_probe", 0.22)
	animation_player.advance(0.11)
	assert(
		animation_player.current_animation == "walk_probe",
		"AnimationPlayer did not enter the blended walk clip"
	)
	animation_player.seek(0.0, true)
	await process_frame
	await process_frame
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var visual := PlayerVisual.new()
	root.add_child(visual)
	visual.build(assets, palette)
	var head_socket := visual.find_child(
		"PlayerHeadSocket", true, false
	) as BoneAttachment3D
	assert(head_socket != null, "Runtime player must create one head socket")
	for node_name in [
		"EyeL",
		"EyeR",
		"Brows",
		"Moustache",
		"Mouth",
		"Hair00",
		"Hair01",
		"Hair02",
		"Hair03",
	]:
		var module := visual.find_child(
			node_name, true, false
		) as MeshInstance3D
		assert(
			module != null and module.get_parent() == head_socket,
			"Runtime module '%s' must bind to PlayerHeadSocket" % node_name
		)
	var profile := PlayerProfile.new()
	profile.hair_style = 2
	profile.hair_color_index = 5
	visual.apply_profile(profile)
	for style_index in 4:
		var hair := visual.find_child(
			"Hair%02d" % style_index, true, false
		) as MeshInstance3D
		assert(
			hair.visible == (style_index == 2),
			"Only the selected hairstyle may render"
		)
	var core := GameCore.new()
	assert(core.setup(), "Equipment content must load for player socket probe")
	core.equipment.acquire("armor_explorer_hood")
	assert(
		core.equipment.equip("armor_explorer_hood"),
		"Explorer hood must equip for hair-occlusion probe"
	)
	visual.apply_equipment(core.equipment)
	for style_index in 4:
		assert(
			not (
				visual.find_child(
					"Hair%02d" % style_index, true, false
				) as MeshInstance3D
			).visible,
			"Headwear must hide every hairstyle without hiding facial features"
		)
	print("MIXAMO_PLAYER_IMPORT_OK")
	quit()


func _retarget_to_live_skeleton(
	animation: Animation,
	animation_player: AnimationPlayer,
	skeleton: Skeleton3D
) -> void:
	var animation_root := animation_player.get_node(animation_player.root_node)
	var skeleton_path := animation_root.get_path_to(skeleton)
	for track_index in animation.get_track_count():
		var source_path := String(animation.track_get_path(track_index))
		if not source_path.contains(":"):
			continue
		var bone_name := source_path.get_slice(":", 1)
		if skeleton.find_bone(bone_name) >= 0:
			animation.track_set_path(
				track_index,
				NodePath("%s:%s" % [skeleton_path, bone_name])
			)


func _print_tree(node: Node, depth := 0) -> void:
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]")
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _find_first(node: Node, class_name_value: String) -> Node:
	if node.is_class(class_name_value):
		return node
	for child in node.get_children():
		var result := _find_first(child, class_name_value)
		if result != null:
			return result
	return null


func _assert_loop_pose_closes(animation: Animation, clip_name: String) -> void:
	assert(
		animation.loop_mode == Animation.LOOP_LINEAR,
		"%s must be configured as a looping authored action" % clip_name
	)
	for track_index in animation.get_track_count():
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2:
			continue
		match animation.track_get_type(track_index):
			Animation.TYPE_POSITION_3D:
				var first_position := animation.track_get_key_value(
					track_index, 0
				) as Vector3
				var last_position := animation.track_get_key_value(
					track_index, key_count - 1
				) as Vector3
				assert(
					first_position.distance_to(last_position) < 0.0002,
					"%s position track does not close: %s"
					% [clip_name, animation.track_get_path(track_index)]
				)
			Animation.TYPE_ROTATION_3D:
				var first_rotation := animation.track_get_key_value(
					track_index, 0
				) as Quaternion
				var last_rotation := animation.track_get_key_value(
					track_index, key_count - 1
				) as Quaternion
				assert(
					first_rotation.angle_to(last_rotation) < 0.002,
					"%s rotation track does not close: %s"
					% [clip_name, animation.track_get_path(track_index)]
				)


func _find_track(
	animation: Animation,
	path_suffix: String,
	type: Animation.TrackType
) -> int:
	for track_index in animation.get_track_count():
		if (
			animation.track_get_type(track_index) == type
			and String(animation.track_get_path(track_index)).ends_with(
				path_suffix
			)
		):
			return track_index
	return -1
