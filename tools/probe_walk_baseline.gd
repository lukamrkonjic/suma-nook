extends SceneTree
## Prints the hips position baseline of the extracted walk clip and of the
## mannequin's embedded idle so the two conventions can be matched exactly.


func _initialize() -> void:
	var walk := load("res://assets/animations/player_walk.tres") as Animation
	for track_index in walk.get_track_count():
		var path := String(walk.track_get_path(track_index))
		if (
			walk.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and path.ends_with(":mixamorigHips")
		):
			var first := walk.track_get_key_value(track_index, 0) as Vector3
			var total := Vector3.ZERO
			var count := walk.track_get_key_count(track_index)
			for key_index in count:
				total += walk.track_get_key_value(track_index, key_index) as Vector3
			print("WALK_HIPS first=", first, " mean=", total / count)
	var scene := load(
		"res://assets/3d/reworked/player_male_mannequin.glb"
	) as PackedScene
	var instance := scene.instantiate()
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var idle := player.get_animation("idle_relaxed")
	for track_index in idle.get_track_count():
		var path := String(idle.track_get_path(track_index))
		if (
			idle.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and path.ends_with(":mixamorigHips")
		):
			print(
				"IDLE_HIPS first=",
				idle.track_get_key_value(track_index, 0)
			)
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var hips_index := skeleton.find_bone("mixamorigHips")
	print("HIPS_REST_LOCAL=", skeleton.get_bone_rest(hips_index).origin)
	instance.free()
	for stem in [
		"hair_swoop_brown", "eyes_oval_pair", "brows_soft_pair",
		"nose_round", "moustache_walrus", "mouth_smile",
	]:
		var part_scene := load(
			"res://assets/characters/parts/%s.glb" % stem
		) as PackedScene
		var part := part_scene.instantiate()
		for child in part.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			print("PART_AABB ", stem, " ", mesh_instance.get_aabb())
		part.free()
	await _measure_walk_toes()
	print("WALK_BASELINE_DONE")
	quit(0)


func _measure_walk_toes() -> void:
	var scene := load(
		"res://assets/3d/reworked/player_male_mannequin.glb"
	) as PackedScene
	var instance := scene.instantiate()
	root.add_child(instance)
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var walk := (
		load("res://assets/animations/player_walk.tres") as Animation
	).duplicate(true) as Animation
	var animation_root := player.get_node(player.root_node)
	var skeleton_path := animation_root.get_path_to(skeleton)
	for track_index in walk.get_track_count():
		var source_path := String(walk.track_get_path(track_index))
		if not source_path.contains(":"):
			continue
		var bone_name := source_path.get_slice(":", 1)
		if skeleton.find_bone(bone_name) >= 0:
			walk.track_set_path(
				track_index, NodePath("%s:%s" % [skeleton_path, bone_name])
			)
	player.get_animation_library("").add_animation("walk_probe", walk)
	await process_frame
	player.play("walk_probe")
	var toe_min := INF
	var toe_max := -INF
	for sample in 41:
		player.seek(walk.length * sample / 40.0, true)
		for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
			var toe_index := skeleton.find_bone(toe_name)
			var toe_y := skeleton.get_bone_global_pose(toe_index).origin.y
			toe_min = minf(toe_min, toe_y)
			toe_max = maxf(toe_max, toe_y)
	print("WALK_TOE_RANGE min=", toe_min, " max=", toe_max)
	player.seek(0.0, true)
	var idle := player.get_animation("idle_relaxed")
	player.play("idle_relaxed")
	player.seek(0.0, true)
	var idle_toe := INF
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := skeleton.find_bone(toe_name)
		idle_toe = minf(
			idle_toe, skeleton.get_bone_global_pose(toe_index).origin.y
		)
	print("IDLE_TOE=", idle_toe, " idle_length=", idle.length)
	instance.queue_free()
