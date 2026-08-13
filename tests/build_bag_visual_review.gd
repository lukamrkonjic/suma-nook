extends Node
## Deterministic camera crew for the collection-sheet Build Bag. Run this
## scene at each target resolution and compare the PNGs side by side.

const SAVE_PATH := "user://build_bag_visual_review.json"

var main: Main
var _shot_dir := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_shot_dir = argument.trim_prefix("--shot-dir=")
	if _shot_dir == "":
		_shot_dir = ProjectSettings.globalize_path("user://build_bag_visual_review")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _wait(0.7)
	var creator := main.find_child("Creator", false, false) as CharacterCreator
	if creator != null:
		creator._name_edit.text = "Keeper"
		creator._finish()
		await _wait(0.8)
	if main.arrival_picker != null and main.arrival_picker.is_open():
		main.arrival_picker.select("tile_grass")
		await _wait(1.25)
	if main.collection_vibe_panel != null and main.collection_vibe_panel.is_open():
		main.collection_vibe_panel.call("_choose", "homestead")
		await _wait(0.5)

	main.core.new_game(main.core.profile)
	main.renderer.rebuild_all()
	main.player.position = main.core.profile.position
	main.core.stock.tiles.clear()
	for tile_id: String in main.core.registries.active_tile_ids():
		main.core.stock.tiles[tile_id] = 10
	main.core.stock.structures.clear()
	for structure_id: String in main.core.registries.structures:
		main.core.stock.structures[structure_id] = 6
	main.core.stock.landmark_deeds.clear()
	for landmark_id: String in main.core.registries.landmarks:
		main.core.stock.landmark_deeds.append(landmark_id)
	main.core.stock.stock_changed.emit()
	main.hud._refresh_all()
	main.placement.set_active(true)
	main.hud.set_build_library_expanded(true, false)
	if main.debug_menu != null:
		main.debug_menu.visible = false
	await _wait(11.0)
	main.hud._build_item_scroll.scroll_vertical = 0
	_ensure_bag_state()
	await _wait(0.25)

	await _shot("initial")

	var scroll := main.hud._build_item_scroll as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(maxf(0.0, bar.max_value - bar.page) * 0.62)
	_ensure_bag_state()
	await _wait(0.3)
	await _shot("deep_scroll")

	scroll.scroll_vertical = 0
	await _wait(0.2)
	var first := main.hud._build_item_buttons[0] as InventoryItemCell
	first.set_selected(true)
	first.mouse_entered.emit()
	main.hud._build_bar.show_focus_detail(first.tooltip_text)
	Input.warp_mouse(first.get_global_rect().get_center())
	_ensure_bag_state()
	await _wait(0.75)
	await _shot("hover_selected")

	print("BUILD BAG VISUAL REVIEW DONE — %s" % _shot_dir)
	main.core.autosave_paused = true
	main.free()
	get_tree().quit(0)


func _shot(state: String) -> void:
	await RenderingServer.frame_post_draw
	var viewport_size := get_viewport().get_visible_rect().size
	var filename := "build_bag_%dx%d_%s.png" % [
		int(viewport_size.x), int(viewport_size.y), state
	]
	var output_path := _shot_dir.path_join(filename)
	get_viewport().get_texture().get_image().save_png(output_path)
	print("[shot] %s" % output_path)


func _ensure_bag_state() -> void:
	get_tree().paused = false
	if main.pause_menu != null and main.pause_menu.is_open():
		main.pause_menu.close()
	main.placement.set_active(true)
	main.hud.visible = true
	main.hud.set_build_library_expanded(true, false)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
