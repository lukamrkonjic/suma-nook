extends Node
## Real-scene smoke test for the shipped calm diorama loop. Uses an isolated
## save and exercises the same tray -> controller cursor -> world -> Build Bag
## route as the player-facing UI.

const SAVE_PATH := "user://diorama_scene_test_save.json"

var main: Main
var failures: PackedStringArray = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  ok — " + message)
	else:
		failures.append(message)
		printerr("DIORAMA SCENE FAIL: " + message)


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(0.4).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	check(
		main._gameplay_started
		and not main.nook_offer_panel.is_open()
		and main.core.grid.cells.is_empty(),
		"a fresh save enters the blank build canvas without a starting-world prompt"
	)

	var tray := main.discovery_tray_panel
	check(
		tray != null and tray.visible and main.core.diorama.tray.offers().size() == 3,
		"the real scene presents the persistent three-miniature tray"
	)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	tray.open_focus()
	await get_tree().process_frame
	check(
		tray.has_focus(),
		"controller focus enters the tray deterministically without a pointer"
	)

	var offer := main.core.diorama.tray.offer_at(0)
	var tile_id := String(offer.get("id", ""))
	tray._select(0)
	check(
		main.placement.active
		and main.placement.controller_cursor_active()
		and String(main.placement.held.get("offer_id", ""))
			== String(offer.get("offer_id", "")),
		"accepting a focused offer hands its exact receipt to the controller grid cursor"
	)

	var placement_cell := Vector2i(
		main.core.nooks.world.nook_size + 4,
		-main.core.nooks.world.nook_size - 2
	)
	var placed := (
		main.core.can_place_player_tile_at(placement_cell, 0, tile_id)
		and main.placement.try_place_at_layer(placement_cell, 0)
	)
	await get_tree().process_frame
	check(
		placed
		and not main.placement.active
		and tray.visible
		and main.core.stock.tile_count(tile_id) == 0,
		"first placement refills the tray and returns to calm play without an extra back action"
	)

	# A lone home tile is deliberately protected from pickup until another safe
	# surface exists. Place the refilled terrain offer beside it, then exercise
	# the ordinary move-to-Build-Bag path on the first tile.
	var second_terrain := main.core.diorama.tray.offer_at(0)
	tray._select(0)
	var second_cell := placement_cell + Vector2i.RIGHT
	check(
		String(second_terrain.get("kind", "")) == "tile"
		and main.placement.try_place_at_layer(second_cell, 0),
		"the terrain tray role can extend the blank canvas one tile at a time"
	)
	main.placement.set_active(true)
	main.placement.pick_up_at(placement_cell, 0)
	check(
		not main.placement.held.is_empty()
		and main.placement.held.get("moving") != null,
		"the newly owned tile can be picked up again"
	)
	main.placement.store_held()
	main.placement.set_active(false)
	check(
		main.core.stock.tile_count(tile_id) == 1,
		"the placed tray tile returns to the existing Build Bag"
	)
	var cancelled_offer := main.core.diorama.tray.offer_at(1)
	tray._select(1)
	main.placement.cancel_click()
	check(
		not main.placement.active
		and tray.visible
		and String(main.core.diorama.tray.offer_at(1).get("offer_id", ""))
			== String(cancelled_offer.get("offer_id", ""))
		and String(main.core.diorama.tray.offer_at(1).get("state", "")) == "available",
		"controller back returns an unplaced miniature to its exact tray slot"
	)

	if failures.is_empty():
		print("DIORAMA SCENE PASSED — %d checks" % checks)
	else:
		print("DIORAMA SCENE FAILED — %d/%d failed" % [failures.size(), checks])
	var exit_code := 0 if failures.is_empty() else 1
	main.core.save()
	main.free()
	main = null
	await get_tree().process_frame
	get_tree().quit(exit_code)
