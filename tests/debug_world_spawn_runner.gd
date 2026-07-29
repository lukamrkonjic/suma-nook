extends Node
## Rendered regression for the maxed debug-world spawn. It proves the player
## can leave the reserved clearing after the real chunk colliders are built.

const SAVE_PATH := "user://debug_world_spawn_test.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.8).timeout
	if not _main._gameplay_started:
		push_error("Debug spawn runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for _frame in 60:
		await get_tree().physics_frame

	var start := _main.player.global_position
	Input.action_press("move_right", 1.0)
	for _frame in 90:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var finish := _main.player.global_position
	var horizontal_distance := Vector2(
		finish.x - start.x,
		finish.z - start.z
	).length()
	var spawn_clear := true
	for y in range(
		-DebugWorldBuilder.SPAWN_CLEAR_RADIUS,
		DebugWorldBuilder.SPAWN_CLEAR_RADIUS + 1
	):
		for x in range(
			-DebugWorldBuilder.SPAWN_CLEAR_RADIUS,
			DebugWorldBuilder.SPAWN_CLEAR_RADIUS + 1
		):
			var state := _main.core.grid.cell(Vector2i(x, y))
			if state != null and not state.structures.is_empty():
				spawn_clear = false
	var result := {
		"spawn_clear": spawn_clear,
		"start": start,
		"finish": finish,
		"horizontal_distance": horizontal_distance,
		"player_moved": horizontal_distance > 0.75,
		"world": _main.renderer.debug_stats(),
	}
	print("DEBUG_WORLD_SPAWN_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if spawn_clear and horizontal_distance > 0.75 else 1)
