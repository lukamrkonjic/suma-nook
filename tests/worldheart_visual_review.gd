extends Node
## Captures the Worldheart's day, night, hover, fall, meter, and reward states.

const SAVE_PATH := "user://worldheart_visual_review_save.json"
const OUTPUT_DIR := "res://artifacts/worldheart_review"

var main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	await _capture("01_empty_vibe_choice.png")
	main.collection_vibe_panel._choose("winter")
	main.camera_rig.set_zoom_immediate(10.0)
	await get_tree().create_timer(0.9).timeout
	await _capture("02_winter_nine_tiles.png")
	var wardrobe_screen := main.camera_rig.camera.unproject_position(
		main.worldheart_presenter._wardrobe_interaction_anchor()
	)
	main.placement.set_process(false)
	main.placement._show_interaction_hover(
		main.placement._interaction_hover_at_screen(wardrobe_screen)
	)
	await get_tree().create_timer(0.15).timeout
	await _capture("02b_wardrobe_hover_outline.png")
	main.renderer.clear_structure_hover()
	main.placement.set_process(true)
	main.lighting.set_time_of_day("night")
	main.lighting.set_background_preset("night")
	await get_tree().create_timer(0.5).timeout
	await _capture("03_portal_at_night.png")
	main.lighting.set_time_of_day("noon")
	main.lighting.set_background_preset("profile")
	await get_tree().create_timer(0.35).timeout
	main.core.stock.add_tile("tile_grass_flower", 3)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	main.placement.hold_new("tile", "tile_grass_flower")
	main.placement._controller_cell = Vector2i.ZERO
	# Freeze Main's mouse/controller synchronizer while the presenter advances
	# its own animation. This keeps automated captures independent of host input.
	main.set_process(false)
	main.worldheart_presenter.show_offering_preview(
		"tile", "tile_grass_flower"
	)
	main.placement.set_external_offer_preview(true)
	await get_tree().create_timer(0.16).timeout
	await _capture("04a_door_swing.png")
	await get_tree().create_timer(0.40).timeout
	await _capture("04_offering_preview.png")
	main.project_panel.close()
	await get_tree().create_timer(0.15).timeout
	main._contribute_held_to_worldheart()
	main.set_process(true)
	await get_tree().create_timer(0.2).timeout
	await _capture("05_offering_fall.png")
	await get_tree().create_timer(0.64).timeout
	await _capture("06_meter_one_of_two.png")
	main.hud.worldheart_offer_requested.emit("tile", "tile_grass_flower")
	await get_tree().create_timer(1.78).timeout
	await _capture("07a_reward_doors_open.png")
	await get_tree().create_timer(0.30).timeout
	await _capture("07_reward_spit.png")
	get_tree().quit()


func _capture(file_name: String) -> void:
	# `frame_post_draw` does not fire in every offscreen Windows renderer. Two
	# process frames still guarantee the viewport has submitted fresh content.
	await get_tree().process_frame
	await get_tree().process_frame
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	if image == null:
		print("WORLDHEART CAPTURE SKIPPED (no framebuffer): %s" % file_name)
		return
	var path := ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name])
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save Worldheart review capture: %s" % error_string(error))
	else:
		print("WORLDHEART CAPTURE: %s" % path)
