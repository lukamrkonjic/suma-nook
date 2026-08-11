extends Node
## Fast scene-level contract for the live debug card and skyfall shortcut.

const SAVE_PATH := "user://debug_menu_smoke_save.json"

var _main: Main
var _failures := 0


func _ready() -> void:
	OS.set_environment("SUMA_LEGACY_OPENING", "1")
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.8).timeout
	_expect(_main._gameplay_started, "the debug card smoke reaches Shape Land")
	await _exercise_card()
	await _finish()


func _exercise_card() -> void:
	var menu = _main.debug_menu
	_expect(menu != null and menu.visible, "debug builds show the live debug card")
	if menu == null:
		return
	var card := menu.find_child("DebugMenuCard", true, false) as Control
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_expect(
		card != null
		and card.get_global_rect().end.x <= viewport_size.x - 12.0
		and card.get_global_rect().end.y <= viewport_size.y - 12.0
		and card.get_global_rect().get_center().x > viewport_size.x * 0.5
		and card.get_global_rect().get_center().y > viewport_size.y * 0.5,
		"the admin card stays in the bottom-right clear of the top-left HUD"
	)
	var skyfall := menu.find_child("DebugSkyfallNow", true, false) as Button
	var items := menu.find_child("DebugGrantItems99", true, false) as Button
	var tiles := menu.find_child("DebugGrantTiles99", true, false) as Button
	var models := menu.find_child("DebugGrantModels99", true, false) as Button
	var toggle := menu.find_child("DebugMenuToggle", true, false) as Button
	_expect(
		skyfall != null and items != null and tiles != null and models != null,
		"the card exposes skyfall, items, tiles, and models"
	)
	for button in [skyfall, items, tiles, models]:
		_expect(
			button != null
			and button.custom_minimum_size.y <= 30.0,
			"%s stays compact" % (button.name if button != null else "missing button")
		)

	var stock_before := _main.core.stock.to_save_dict()
	var inventory_before := _main.core.inventory.to_save_dict()
	var item_id := String(_main.core.registries.items.keys()[0])
	var tile_id := String(_main.core.registries.obtainable_tile_ids()[0])
	var model_id := "struct_bench"
	var item_count := _main.core.inventory.count(item_id)
	var tile_count := _main.core.stock.tile_count(tile_id)
	var model_count := _main.core.stock.structure_count(model_id)
	items.pressed.emit()
	tiles.pressed.emit()
	models.pressed.emit()
	await get_tree().process_frame
	_expect(
		_main.core.inventory.count(item_id) == item_count + 99,
		"Items ×99 grants exactly 99 copies"
	)
	_expect(
		_main.core.stock.tile_count(tile_id) == tile_count + 99,
		"Tiles ×99 grants exactly 99 copies"
	)
	_expect(
		_main.core.stock.structure_count(model_id) == model_count + 99,
		"Models ×99 grants exactly 99 copies"
	)
	_main.core.stock.from_save_dict(stock_before)
	_main.core.inventory.from_save_dict(inventory_before)

	var discovery_before := _main.core.progression.discovery.to_save_dict()
	skyfall.pressed.emit()
	await get_tree().process_frame
	_expect(
		_main.wish_offer_panel.is_open()
		and _main.core.progression.discovery.current_wish_choices().size() == 3,
		"Skyfall now immediately opens a three-category wish"
	)
	_main.wish_offer_panel.close()
	_main.core.progression.discovery.from_save_dict(discovery_before)
	_main.wish_offer_panel.notify_ready(false)

	toggle.pressed.emit()
	_expect(not menu.is_expanded(), "the debug card collapses to its small header")
	var input_service := InputDeviceService.shared()
	var previous_method := input_service.input_method
	input_service.input_method = InputDeviceService.InputMethod.CONTROLLER
	_main.pause_menu.open("admin")
	await get_tree().process_frame
	var focus_card := _main.pause_menu.find_child(
		"AdminRowDebugMenu", true, false
	) as Button
	_expect(focus_card != null, "Pause Admin retains a controller route to the card")
	if focus_card != null:
		focus_card.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner()
		_expect(
			not _main.pause_menu.is_open()
			and menu.is_expanded()
			and focus != null
			and menu.is_ancestor_of(focus),
			"focusing the card closes Pause, expands it, and assigns controller focus"
		)
	input_service.input_method = previous_method

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				argument.trim_prefix("--shot=")
			)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok — " + message)
	else:
		_failures += 1
		push_error("DEBUG MENU FAIL: " + message)


func _finish() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if _failures == 0:
		print("DEBUG MENU SMOKE PASSED")
	else:
		print("DEBUG MENU SMOKE FAILED — %d checks" % _failures)
	if is_instance_valid(_main):
		_main.free()
		_main = null
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(_failures)
