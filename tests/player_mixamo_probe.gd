extends SceneTree
## Import + assembly smoke test for the modular default player: the clean
## mannequin GLB, the authored idle_relaxed loop, the data-driven appearance
## preset, and the runtime socket binding.

const PLAYER_SCENE := preload(
	"res://assets/3d/reworked/player_male_mannequin.glb"
)
const WALK_ANIMATION: Animation = preload(
	"res://assets/animations/player_walk.tres"
)
const PLAYER_PROFILE: PlayerAssetProfile = preload(
	"res://assets/player/current_player_profile.tres"
)
const APPEARANCE: CharacterAppearancePreset = preload(
	"res://assets/characters/presets/default_male_appearance.tres"
)

const LEGACY_MODULES := [
	"EyeL", "EyeR", "Brows", "Moustache",
	"Hair00", "Hair01", "Hair02", "Hair03",
]
const FACE_SLOTS := [
	CharacterSlots.HAIR, CharacterSlots.EYES, CharacterSlots.EYEBROWS,
	CharacterSlots.NOSE, CharacterSlots.MOUSTACHE, CharacterSlots.MOUTH,
]


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
			== "res://assets/3d/reworked/player_male_mannequin.glb",
		"Probe and current player profile must target the same model"
	)
	assert(
		PLAYER_PROFILE.walk_animation == WALK_ANIMATION,
		"Current player profile must own the extracted walk animation"
	)
	assert(
		APPEARANCE.validation_errors().is_empty(),
		"Default appearance preset must validate"
	)

	# --- Mannequin GLB contract -------------------------------------------
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	var body := player.find_child("PlayerMaleBody", true, false) as MeshInstance3D
	assert(body != null and body.skin != null, "Mannequin body must be skinned")
	# The hide-region system depends on per-triangle region ids in UV2.x; the
	# bake silently vanishing would turn all region hiding into a no-op.
	var body_arrays := body.mesh.surface_get_arrays(0)
	var body_uv2: Variant = body_arrays[Mesh.ARRAY_TEX_UV2]
	assert(body_uv2 != null, "Mannequin body lost its armor-region UV2 bake")
	var region_ids := {}
	for value in body_uv2:
		region_ids[int(round((value as Vector2).x))] = true
	print("ARMOR_REGION_IDS=", region_ids.keys().size())
	assert(
		region_ids.keys().size() >= 25,
		"Armor-region bake must cover the body (found %d regions)"
		% region_ids.keys().size()
	)
	for node_name in LEGACY_MODULES:
		assert(
			player.find_child(node_name, true, false) == null,
			"Mannequin must not carry baked face module '%s'" % node_name
		)
	var animation_player := player.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	assert(animation_player != null, "Mannequin must import an AnimationPlayer")
	var names := animation_player.get_animation_list()
	print("MANNEQUIN_ANIMATIONS=", names)
	assert(names.has("idle_relaxed"), "idle_relaxed clip was not imported")
	var idle := animation_player.get_animation("idle_relaxed")
	print("IDLE_LENGTH=", idle.length)
	assert(idle.length > 4.4 and idle.length < 6.1, "idle_relaxed must run ~5 s")
	_assert_loop_pose_closes(idle, "idle_relaxed")

	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "Mannequin must import a Skeleton3D")
	assert(
		PLAYER_PROFILE.rig_validation_errors(
			skeleton, animation_player
		).is_empty(),
		"Current player profile must match the imported rig and walk tracks"
	)
	print("MANNEQUIN_BONES=", skeleton.get_bone_count())

	# The relaxed idle must not slide the feet: toe bones stay put through the
	# loop while the upper body breathes.
	animation_player.play("idle_relaxed")
	animation_player.seek(0.0, true)
	var arm_index := skeleton.find_bone("mixamorigRightArm")
	var arm_at_start := skeleton.get_bone_pose(arm_index)
	var toe_travel := 0.0
	var toe_reference := {}
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := skeleton.find_bone(toe_name)
		toe_reference[toe_name] = skeleton.get_bone_global_pose(toe_index).origin
	for sample in 27:
		animation_player.seek(idle.length * sample / 26.0, true)
		for toe_name in toe_reference:
			var toe_index := skeleton.find_bone(toe_name)
			toe_travel = maxf(
				toe_travel,
				(
					skeleton.get_bone_global_pose(toe_index).origin
					- toe_reference[toe_name]
				).length()
			)
	print("IDLE_TOE_TRAVEL=", toe_travel)
	assert(toe_travel < 0.004, "idle_relaxed must keep the feet planted")
	animation_player.seek(idle.length * 0.5, true)
	assert(
		not arm_at_start.is_equal_approx(skeleton.get_bone_pose(arm_index)),
		"idle_relaxed must actually breathe (arm follow-through missing)"
	)
	# The idle pose must hold the arms away from the torso (T-pose is the rest
	# pose; the idle hangs them with visible clearance).
	animation_player.seek(0.0, true)
	var hips_index := skeleton.find_bone("mixamorigHips")
	var hips_height := skeleton.get_bone_global_pose(hips_index).origin.y
	var shoulder_index := skeleton.find_bone("mixamorigRightShoulder")
	var shoulder_height := skeleton.get_bone_global_pose(shoulder_index).origin.y
	var hand_index := skeleton.find_bone("mixamorigRightHand")
	var hand_position := skeleton.get_bone_global_pose(hand_index).origin
	print("IDLE_HIPS_HEIGHT=", hips_height, " HAND=", hand_position)
	# The idle must share the walk clip's ground-relative hips baseline so
	# locomotion never changes the character's height.
	assert(
		absf(hips_height - 0.246) < 0.02,
		"idle hips must match the walk clip baseline (~0.246)"
	)
	assert(
		hand_position.y < shoulder_height - 0.10,
		"idle hands must hang, not stay in T-pose"
	)
	assert(
		absf(hand_position.x) > 0.10,
		"idle hands must keep clearance from the torso"
	)

	# --- Walk clip contract (unchanged from the previous character) --------
	assert(
		WALK_ANIMATION.loop_mode == Animation.LOOP_LINEAR,
		"Extracted walk clip must loop"
	)
	var walk_root_track_found := false
	for track_index in WALK_ANIMATION.get_track_count():
		var track_path := String(WALK_ANIMATION.track_get_path(track_index))
		if (
			WALK_ANIMATION.track_get_type(track_index)
			== Animation.TYPE_POSITION_3D
			and track_path.ends_with(":mixamorigHips")
		):
			walk_root_track_found = true
		if not track_path.contains(":mixamorig"):
			continue
		var bone_name := track_path.get_slice(":", 1)
		assert(
			skeleton.find_bone(bone_name) >= 0,
			"Walk clip targets a bone absent from the rig: %s" % bone_name
		)
	assert(walk_root_track_found, "Walk animation has no hips position track")
	for action_name in ["fish_cast", "fish_wait", "chop"]:
		assert(
			PLAYER_PROFILE.action_animations.has(action_name),
			"Current player profile is missing authored action '%s'"
			% action_name
		)

	# --- Runtime assembly through PlayerVisual ----------------------------
	await process_frame
	await process_frame
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var visual := PlayerVisual.new()
	root.add_child(visual)
	visual.build(assets, palette)
	var head_attachment := visual.find_child(
		"HeadAttachment", true, false
	) as BoneAttachment3D
	assert(head_attachment != null, "Runtime player must create HeadAttachment")
	var face_root := head_attachment.find_child("FaceRoot", false, false)
	assert(face_root != null, "HeadAttachment must own FaceRoot")
	var assembler := visual._appearance_assembler
	assert(
		assembler.last_warnings.is_empty(),
		"Default assembly must produce no warnings: %s"
		% assembler.last_warnings
	)
	for slot in FACE_SLOTS:
		var part := assembler.equipped_node(slot)
		assert(part != null, "Slot %s must be equipped" % slot)
		assert(
			head_attachment.is_ancestor_of(part),
			"Slot %s must bind under the head attachment" % slot
		)
	assert(
		visual.find_child("Skeleton3D", true, false) == visual._skeleton,
		"Assembly must not introduce a second Skeleton3D"
	)
	var skeleton_count := 0
	for child in visual.find_children("*", "Skeleton3D", true, false):
		skeleton_count += 1
	assert(skeleton_count == 1, "Exactly one Skeleton3D may exist")

	var profile := PlayerProfile.new()
	profile.hair_style = 2
	profile.hair_color_index = 5
	visual.apply_profile(profile)
	assert(
		assembler.equipped_node(CharacterSlots.HAIR).visible,
		"Hair must stay visible after applying a profile"
	)

	var core := GameCore.new()
	assert(core.setup(), "Equipment content must load for player socket probe")
	core.equipment.acquire("armor_explorer_hood")
	assert(
		core.equipment.equip("armor_explorer_hood"),
		"Explorer hood must equip for hair-occlusion probe"
	)
	visual.apply_equipment(core.equipment)
	assert(
		not assembler.equipped_node(CharacterSlots.HAIR).visible,
		"Headwear must hide the hair part"
	)
	for slot in [
		CharacterSlots.EYES, CharacterSlots.EYEBROWS, CharacterSlots.NOSE,
		CharacterSlots.MOUSTACHE, CharacterSlots.MOUTH,
	]:
		assert(
			assembler.equipped_node(slot).visible,
			"Headwear must not hide facial features (%s)" % slot
		)
	print("MODULAR_PLAYER_IMPORT_OK")
	quit()


func _assert_loop_pose_closes(animation: Animation, clip_name: String) -> void:
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
					first_position.distance_to(last_position) < 0.0005,
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
					first_rotation.angle_to(last_rotation) < 0.004,
					"%s rotation track does not close: %s"
					% [clip_name, animation.track_get_path(track_index)]
				)
