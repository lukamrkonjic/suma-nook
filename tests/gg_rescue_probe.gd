extends Node
## Verifies the overboard water rescue: drops the player past the island
## edge, expects the RESCUED state, then a safe landing on walkable ground.

const SAVE_PATH := "user://gg_rescue_probe_save.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	creator._preview()
	creator._name_edit.text = "Swimmer"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	var player := _main.player
	# Fling the player well past the island edge, below the waterline.
	var start_cell := player.current_cell()
	player.position = _main.core.grid.cell_to_world(start_cell) + Vector3(-14.0, -0.2, 0.0)
	player.velocity = Vector3.ZERO
	var saw_rescue := false
	var shot_saved := false
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if player.state == PlayerController.State.RESCUED:
			if not saw_rescue:
				saw_rescue = true
				get_tree().create_timer(0.52).timeout.connect(func():
					if shot_saved:
						return
					shot_saved = true
					var image := get_viewport().get_texture().get_image()
					GGCaptureEncode.encode_srgb(image)
					image.save_png("res://artifacts/gg_exact/rescue_swallow_moment.png")
				)
		if saw_rescue and player.state == PlayerController.State.FREE:
			break
	var final_cell := player.current_cell()
	var landed_walkable := _main.core.grid.is_traversable(final_cell)
	var upright := absf(player.position.y) < 1.5
	if saw_rescue and player.state == PlayerController.State.FREE and landed_walkable and upright:
		print("RESCUE PROBE PASSED — rescued to %s at y=%.2f" % [final_cell, player.position.y])
		get_tree().quit(0)
	else:
		print(
			"RESCUE PROBE FAILED — saw_rescue=%s state=%s cell=%s walkable=%s y=%.2f"
			% [saw_rescue, player.state, final_cell, landed_walkable, player.position.y]
		)
		get_tree().quit(1)
