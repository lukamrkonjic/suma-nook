extends Node
## Boots the real main scene and captures one screenshot per discovery-era
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

	creator._name_edit.text = "Keeper"
	creator._finish()
	await wait(1.1)
	await shot("02_first_land_choice")

	main.arrival_picker.select("tile_sand")
	await wait(1.45)
	await shot("03_sand_island_surrounded_by_void")

	main.core.fishing.debug_force_catch(Vector2i.ZERO)
	await wait(0.8)
	await shot("04_first_haul_guides_water_placement")
	main._resume_guided_onboarding()
	await wait(0.45)
	main.placement.try_place_at(Vector2i(0, 2))
	await wait(0.4)
	await shot("05_player_placed_water_tile")

	main.core.new_game(main.core.profile)
	main.renderer.rebuild_all()
	main.player.position = main.core.profile.position
	main.hud._refresh_all()

	main.core.progression.activity_actions["fishing"] = 3
	main.panels.toggle("skills")
	await wait(0.4)
	await shot("06_activities_and_practice")
	main.panels.close()

	main.core.fishing.debug_force_catch(Vector2i.ZERO)
	main.core.fishing.debug_force_catch(Vector2i.ZERO)
	main.panels.show_catch_basket()
	await wait(0.4)
	await shot("07_catch_basket_hauls")
	main.panels.close()

	main.core.progression.on_activity_cycle_completed("woodcutting")
	main.core.progression.on_activity_cycle_completed("mining")
	main.panels.show_spirit_pouch()
	await wait(0.4)
	await shot("08_spirit_pouch_charms")
	main.panels.close()
	await wait(0.3)
	await shot("09_world_after_fishing")

	print("VISUAL CAPTURE DONE — %s" % _shot_dir)
	main.core.autosave_paused = true
	main.free()
	get_tree().quit(0)
