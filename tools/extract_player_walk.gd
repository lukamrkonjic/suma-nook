extends SceneTree
## One-shot extraction of the authored Mixamo walk clip. The character mesh
## stays in art_source; runtime loads only the compact Animation resource.

const SOURCE := "res://art_source/animation_sources/player_walk.glb"
const DESTINATION := "res://assets/animations/player_walk.tres"
const ANIMATION_UTILS := preload(
	"res://scripts/player/player_animation_utils.gd"
)


func _initialize() -> void:
	var packed := load(SOURCE) as PackedScene
	assert(packed != null, "Walk source GLB did not import")
	var source_root := packed.instantiate()
	root.add_child(source_root)
	var source_player := _find_animation_player(source_root)
	assert(source_player != null, "Walk source has no AnimationPlayer")
	var animation_names := source_player.get_animation_list()
	assert(not animation_names.is_empty(), "Walk source has no animation clip")
	var source_animation := source_player.get_animation(animation_names[0])
	var walk := source_animation.duplicate(true) as Animation
	walk.resource_name = "player_walk"
	walk.loop_mode = Animation.LOOP_LINEAR
	ANIMATION_UTILS.normalize_in_place(walk)
	var error := ResourceSaver.save(walk, DESTINATION)
	assert(error == OK, "Could not save extracted walk animation")
	print(
		"PLAYER_WALK_EXTRACTED name=",
		animation_names[0],
		" length=",
		walk.length,
		" tracks=",
		walk.get_track_count(),
		" destination=",
		DESTINATION
	)
	quit()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
