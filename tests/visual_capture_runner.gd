extends Node
## Boots the real main scene and captures one screenshot per progression-v2
## visual surface. Not an assertion suite — a camera crew. Run:
##   Godot --path . --resolution 1600x900 tests/visual_capture_runner.tscn \
##     -- --shot-dir=<absolute folder>

const SAVE_PATH := "user://visual_capture_save.json"

var main: Node
var _shot_dir := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_shot_dir = argument.trim_prefix("--shot-dir=")
	if _shot_dir == "":
		_shot_dir = ProjectSettings.globalize_path("user://visual_captures")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	main.core.rng.world_seed = 7
	main.core.rng._streams.clear()
	_run()


func shot(name: String) -> void:
	await wait(0.15)
	var output_path := _shot_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(output_path)
	print("[shot] " + output_path)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	await wait(0.6)

	# 1 — full-screen character creation: keeper alone against the sky.
	var creator: CharacterCreator = main.find_child("Creator", false, false)
	if creator == null:
		printerr("CAPTURE FAIL: creator missing")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	await wait(0.5)
	await shot("01_fullscreen_character_creation")

	# 2 — the portal arrival freezes on the three rendered land choices.
	creator._name_edit.text = "Keeper"
	creator._finish()
	await wait(1.1)
	await shot("02_first_land_choice")

	# 3 — the chosen land catches the keeper and Quiet Water is handed over.
	main.arrival_picker.select("tile_sand")
	await wait(1.45)
	await shot("03_arrival_chosen_sand")
	main.camera_rig.set_zoom_immediate(70.0)
	await wait(0.8)
	await shot("03b_streamed_water_tiles_distance_fog")

	# Recompose the broad showcase fixture after capturing the authored opening.
	main.core.new_game(main.core.profile)
	main.renderer.rebuild_all()
	main.player.position = main.core.profile.position
	main.hud._refresh_all()

	# 4 — the wishing well and shrine placed in the world.
	main.core.grid.add_structure(Vector2i(1, 1), "struct_wishing_well", 0, 0)
	main.core.grid.add_structure(Vector2i(-1, 1), "struct_shrine", 0, 1)
	main.renderer.rebuild_all()
	main.camera_rig.set_zoom_immediate(17.0)
	await wait(0.8)
	await shot("04_wishing_well_and_shrine_placed")

	# 5 — a Vision banks: domain chip pop + toast, meters visible.
	main.core.progression.inspiration.add("domain_grove", 40.0)   # banks (first-vision cost)
	main.core.progression.inspiration.add("domain_waterside", 120.0)  # partial meter
	await wait(0.35)
	await shot("05_hud_domain_meters_and_banked_toast")

	# 6 — the Vision reveal ritual: three options, keep one.
	main.vision_reveal.open_from_well()
	await wait(1.1)
	await shot("06_vision_reveal_three_choices")
	main.vision_reveal._choose(0)
	await wait(0.9)

	# 7 — Activities panel: sessions + upcoming milestones, no levels.
	for i in 3:
		main.core.progression.on_activity_action("fishing")
	main.panels.toggle("skills")
	await wait(0.4)
	await shot("07_activities_panel_milestones")
	main.panels.close()
	await wait(0.2)

	# 8 — refund picker with a live carving meter.
	main.core.stock.add_tile("tile_grass", 5)
	main.core.progression.refunds.refund("tile", "tile_grass")
	main.panels.show_refund_picker()
	await wait(0.4)
	await shot("08_well_refund_picker")
	main.panels.close()
	await wait(0.2)

	# 9 — a minted domain coin waiting at the well.
	main.core.progression.refunds.refund("tile", "tile_grass")
	main.core.progression.refunds.refund("tile", "tile_grass")   # meter 3 → coin
	main.panels.show_coin_picker()
	await wait(0.4)
	await shot("09_promised_domain_coin")
	main.panels.close()
	await wait(0.2)

	# 10 — shrine focus picker: visible targeting.
	main.panels.show_shrine_picker()
	await wait(0.4)
	await shot("10_shrine_focus_picker")
	main.panels.close()
	await wait(0.2)

	# 11 — the well is full: earning politely refuses, three visions wait.
	main.core.progression.inspiration.add("domain_grove", 720.0)
	main.core.progression.inspiration.add("domain_grove", 12.0)   # refused → toast
	main.skill_actions.action_feedback.emit("inspiration_full", {})
	await wait(0.3)
	await shot("11_well_full_three_visions_waiting")

	print("VISUAL CAPTURE DONE — %s" % _shot_dir)
	main.core.autosave_paused = true
	main.free()
	get_tree().quit(0)
