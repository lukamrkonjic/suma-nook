extends SceneTree
## Extract authored action clips into compact, runtime-only Animation resources.
## Source GLBs remain untouched in art_source/animation_sources.

const ANIMATION_UTILS := preload(
	"res://scripts/player/player_animation_utils.gd"
)
const SPECS := [
	{
		"source": "res://art_source/animation_sources/player_fish_cast.glb",
		"destination": "res://assets/animations/player_fish_cast.tres",
		"name": "fish_cast",
		"loop": false,
		# The supplied file includes a long follow-through and reset. Gameplay
		# transitions into fish_wait from the held casting pose instead.
		"trim_end": 2.5,
	},
	{
		"source": "res://art_source/animation_sources/player_fish_wait.glb",
		"destination": "res://assets/animations/player_fish_wait.tres",
		"name": "fish_wait",
		"loop": true,
	},
	{
		"source": "res://art_source/animation_sources/player_chop.glb",
		"destination": "res://assets/animations/player_chop.tres",
		"name": "chop",
		"loop": true,
	},
]


func _initialize() -> void:
	for spec in SPECS:
		_extract(spec)
	quit()


func _extract(spec: Dictionary) -> void:
	var source_path := str(spec["source"])
	var packed := load(source_path) as PackedScene
	assert(packed != null, "Could not import %s" % source_path)
	var source_root := packed.instantiate()
	root.add_child(source_root)
	var source_player := _find_animation_player(source_root)
	assert(source_player != null, "%s has no AnimationPlayer" % source_path)
	var source_name := _first_clip_name(source_player)
	assert(not source_name.is_empty(), "%s has no authored animation" % source_path)
	var animation := source_player.get_animation(source_name).duplicate(true) as Animation
	var trim_end := float(spec.get("trim_end", -1.0))
	if trim_end > 0.0 and trim_end < animation.length:
		_trim_animation(animation, trim_end)
	ANIMATION_UTILS.normalize_in_place(animation)
	animation.resource_name = str(spec["name"])
	animation.loop_mode = (
		Animation.LOOP_LINEAR if bool(spec["loop"]) else Animation.LOOP_NONE
	)
	var destination := str(spec["destination"])
	var error := ResourceSaver.save(animation, destination)
	assert(error == OK, "Could not save %s" % destination)
	print(
		"PLAYER_ACTION_EXTRACTED name=",
		spec["name"],
		" source_clip=",
		source_name,
		" length=",
		animation.length,
		" tracks=",
		animation.get_track_count(),
		" loop=",
		bool(spec["loop"]),
		" destination=",
		destination
	)
	source_root.queue_free()


func _trim_animation(animation: Animation, end_time: float) -> void:
	for track_index in animation.get_track_count():
		var sampled: Variant = null
		match animation.track_get_type(track_index):
			Animation.TYPE_POSITION_3D:
				sampled = animation.position_track_interpolate(track_index, end_time)
			Animation.TYPE_ROTATION_3D:
				sampled = animation.rotation_track_interpolate(track_index, end_time)
			Animation.TYPE_SCALE_3D:
				sampled = animation.scale_track_interpolate(track_index, end_time)
		for key_index in range(
			animation.track_get_key_count(track_index) - 1,
			-1,
			-1
		):
			if animation.track_get_key_time(track_index, key_index) > end_time:
				animation.track_remove_key(track_index, key_index)
		if sampled != null:
			var existing := animation.track_find_key(
				track_index,
				end_time,
				Animation.FIND_MODE_APPROX
			)
			if existing >= 0:
				animation.track_set_key_value(track_index, existing, sampled)
			else:
				animation.track_insert_key(track_index, end_time, sampled)
	animation.length = end_time


func _first_clip_name(animation_player: AnimationPlayer) -> StringName:
	for animation_name in animation_player.get_animation_list():
		if animation_name != "RESET":
			return animation_name
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
