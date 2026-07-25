extends Node

const MainScene := preload("res://scenes/main.tscn")
const TEST_SAVE := "user://tilegarden-integration-save.json"

var failures: Array[String] = []
var assertions := 0
var game: Node


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# Isolate integration persistence and normalize any developer save that Main may have loaded.
	game.save_manager.save_path = TEST_SAVE
	game.save_manager.delete_paths(TEST_SAVE)
	game.grid.make_initial_island(1)
	game.economy.restore_snapshot({})
	game.storage.restore_snapshot({})
	game.collection.restore_snapshot({})
	game.rewards.setup(game.game_data, 730291)
	game.progression.setup(game.grid, game.economy, game.storage, game.collection, 730291)
	game.player.restore_snapshot({"name": "Fern", "appearance": {"skin": 1, "hair": 0, "outfit": 0}, "coord": [0, 1, 0]})
	game.player.can_control = true
	game.character_created = true
	game.hud.character_overlay.visible = false
	for mote: Mote in game.visitors.motes.duplicate():
		game.visitors._on_departed(mote)
	game.visitors.spawn_timer = 999.0

	await _exercise_visitor_seed_reward()
	await _exercise_building_storage_recycling()
	await _exercise_character_walk_and_growth()
	await _exercise_undo_save()

	game.save_manager.delete_paths(TEST_SAVE)
	if failures.is_empty():
		print("SUMA NOOK FULL LOOP PASSED — %d scene-level assertions" % assertions)
		_quit_clean(0)
	else:
		for failure: String in failures:
			push_error("FULL LOOP FAILURE: %s" % failure)
		_quit_clean(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _exercise_visitor_seed_reward() -> void:
	var mote: Mote = game.visitors.spawn_mote(&"meadow_coin", Vector3i(1, 1, 1))
	check(mote != null and mote.has_seed, "a visible Mote arrives carrying a themed coin")
	await get_tree().create_timer(0.62).timeout
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	mote.area.input_event.emit(game.camera_rig.camera, click, mote.global_position, Vector3.UP, 0)
	await get_tree().process_frame
	check(mote.state == Mote.State.REWARDING_PLAYER, "the Mote's own 3D hit area accepts a collection click")
	await get_tree().create_timer(0.95).timeout
	check(game.economy.amount(&"meadow_coin") == 1, "coin count updates at animation impact")
	game.offer_seed(&"meadow_coin")
	await get_tree().create_timer(2.25).timeout
	check(game.economy.amount(&"meadow_coin") == 0, "Bloomforge exchange spends exactly one coin")
	check(game.waiting_reward != null, "Bloomforge reward settles as a clickable world object")
	check(not game.placement.is_holding(), "reward does not teleport directly into placement mode")
	check(game.claim_waiting_reward(), "clicking the waiting reward picks it up")
	check(game.placement.is_holding(), "claimed reward becomes a held placement item")
	check(game.placement.held_definition_id == &"ground_grass", "beginner sequence guarantees expansion first")
	var target := Vector3i(2, 0, 0)
	_set_placement_target(target, true)
	check(game.placement.confirm(), "first reward places beside the island")
	check(game.grid.ground.has(target), "placed expansion tile is authoritative grid state")
	var placed_ground: BuildItem = game.grid_renderer.node_for_ground(target)
	check(game.placement.begin_move(placed_ground), "placed ground can be picked back up")
	game.placement.cancel()
	check(game.grid.ground.has(target), "cancel restores picked ground exactly")


func _exercise_building_storage_recycling() -> void:
	game.collection.record_obtained(&"moss_rock")
	check(game.placement.begin_reward(&"moss_rock"), "a prop reward enters placement")
	_set_placement_target(Vector3i(1, 1, 0), true)
	check(game.placement.confirm(), "prop places on supported ground")
	var lower_id := _instance_at(Vector3i(1, 1, 0))
	check(not lower_id.is_empty(), "placed prop occupies its grid cell")
	check(game.placement.begin_reward(&"moss_rock"), "duplicate stackable reward remains usable")
	_set_placement_target(Vector3i(1, 2, 0), true)
	check(game.placement.confirm(), "compatible duplicate stacks vertically")
	var upper_id := _instance_at(Vector3i(1, 2, 0))
	check(not upper_id.is_empty(), "upper stack layer has authoritative occupancy")
	var upper_node: BuildItem = game.grid_renderer.node_for_instance(upper_id)
	check(game.placement.begin_move(upper_node), "stacked item remains selectable")
	check(game.placement.store_current(), "held item can move to compact storage")
	check(game.storage.amount(&"moss_rock") == 1, "storage retains exact item identity")
	check(game.placement.begin_from_storage(&"moss_rock"), "stored item can be retrieved")
	game.placement.cancel()
	check(game.storage.amount(&"moss_rock") == 1, "cancel returns retrieved item to storage")
	game.storage.take(&"moss_rock", 1)
	game.placement.begin_reward(&"moonflowers")
	_set_placement_target(Vector3i(-1, 1, 1), true)
	game.placement.confirm()
	var flowers_id := _instance_at(Vector3i(-1, 1, 1))
	var flowers_node: BuildItem = game.grid_renderer.node_for_instance(flowers_id)
	game.placement.begin_move(flowers_node)
	check(game.placement.recycle_current(), "common held item sells without punitive confirmation")
	check(game.economy.recycle_progress > 0, "selling advances visible coin progress")


func _exercise_undo_save() -> void:
	var before: int = game.grid.props.size()
	check(game.placement.undo(), "placement history supports undo")
	check(game.grid.props.size() >= before, "undo restores the recycled world item")
	check(game.placement.redo(), "placement history supports redo")
	check(game.grid.props.size() == before, "redo reapplies the recycling world change")
	game.environment_style.set_preset(&"moss_rain")
	game.save_game(false)
	var loaded: Dictionary = game.save_manager.read_save()
	check(not loaded.is_empty(), "main scene writes a valid versioned save")
	check((loaded.grid.ground as Array).size() == game.grid.ground.size(), "full garden survives save serialization")
	check(int(loaded.economy.recycle_progress) == game.economy.recycle_progress, "sale progress survives save serialization")
	check((loaded.collection.discoveries as Array).size() >= 1, "collection discoveries survive save serialization")
	check(loaded.has("camera") and loaded.has("visitors"), "camera and visitor state are included in the save")
	check(str(loaded.environment_preset) == "moss_rain", "pixel-forest weather selection survives save serialization")
	check(loaded.has("player") and str(loaded.player.name) == "Fern", "custom character identity survives save serialization")
	check(loaded.has("progression") and int(loaded.progression.tiles_grown) >= 1, "world-growth progress survives save serialization")


func _exercise_character_walk_and_growth() -> void:
	game.player.stop()
	var moved: bool = game.player.try_step(Vector3i(0, 0, -1))
	check(moved, "the custom character accepts a cardinal movement step")
	await get_tree().create_timer(0.55).timeout
	check(game.player.grid_coord == Vector3i(0, 1, -1), "the character walks onto another starting tile")
	game.economy.restore_snapshot({})
	game.economy.add(&"meadow_coin", 1)
	game.progression.tiles_grown = 2
	game.progression.claimed.clear()
	var before: int = game.grid.ground.size()
	check(game.start_growth(), "Forest Light starts player-directed tile growth")
	var target := Vector3i(2, 0, 1)
	_set_placement_target(target, true)
	check(game.placement.confirm(), "a grown tile can be placed on an empty cardinal edge")
	check(game.grid.ground.size() == before + 1 and game.grid.ground.has(target), "growth expands authoritative walkable world state")
	check(game.economy.amount(&"meadow_coin") == 0, "growth charges one light only after successful placement")
	check(game.progression.tiles_grown == 3, "growth completion advances the forest milestone counter")
	check(game.storage.amount(&"sapling") >= 1, "the first adventure milestone unlocks a decoration")


func _set_placement_target(coord: Vector3i, valid: bool) -> void:
	game.placement.hover_coord = coord
	game.placement.preview_valid = valid
	game.placement.preview_reason = ""
	if game.placement.ghost != null:
		game.placement.ghost.position = game.grid.world_position(coord)
		game.placement.ghost.set_preview_valid(valid)


func _instance_at(coord: Vector3i) -> String:
	return str(game.grid.occupancy.get(coord, ""))


func _quit_clean(code: int) -> void:
	var tree := get_tree()
	tree.create_timer(0.15).timeout.connect(tree.quit.bind(code))
	queue_free()
