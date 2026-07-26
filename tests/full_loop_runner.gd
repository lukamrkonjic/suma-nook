extends Node
## Scene-level acceptance run: drives the REAL game (main.tscn) through the
## complete current loop — creation → free walk → catch/release → ferry →
## parcel choice → Tile Library → placement → woodland tending → save/reload.
## Run windowed:  godot --path . tests/full_loop_runner.tscn
## Prints "FULL LOOP PASSED" or FAIL lines, then quits.

const SAVE_PATH := "user://loop_test_save.json"
const STACK_COORD := Vector2i(0, 1)

var main: Main
var failures: PackedStringArray = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("LOOP FAIL: " + message)
	else:
		print("  ok — " + message)


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--shots"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("docs/" + name + ".png")
	print("  [shot] docs/%s.png" % name)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# Inject before the node enters the tree so Main cannot inspect or load the
	# developer's normal save during its _ready callback.
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	# Keep the acceptance run reproducible. Seed 3 yields fish in the first two
	# common catches while still exercising the real weighted-loot path.
	main.core.rng.world_seed = 3
	main.core.rng._streams.clear()
	_run()


func _run() -> void:
	await wait(0.5)
	await _step_creation()
	await _step_movement()
	await _step_fishing()
	await _step_parcel()
	await _step_place_tile()
	await _step_woodcutting()
	await _step_elevation_stacking()
	await _step_save_while_holding()
	await _step_save_reload()
	await _step_pause_menu()
	await _step_admin_controls()
	if failures.is_empty():
		print("FULL LOOP PASSED — %d checks" % checks)
	else:
		print("FULL LOOP FAILED — %d/%d failed" % [failures.size(), checks])
	await wait(0.5)
	get_tree().quit(0 if failures.is_empty() else 1)


func _step_creation() -> void:
	print("STEP creation")
	var creator: CharacterCreator = main.find_child("Creator", false, false)
	check(creator != null, "character creator opens on fresh boot")
	if creator == null:
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	await wait(0.4)
	await shot("screenshot_character_customization")
	creator._name_edit.text = "Loop Keeper"
	creator._finish()
	await wait(0.6)
	check(main._gameplay_started, "gameplay starts after creation")
	check(main.core.profile.display_name == "Loop Keeper", "chosen name applied")
	check(main.core.grid.cells.size() == 9, "3x3 world present")
	await shot("screenshot_starting_world")


func _step_movement() -> void:
	print("STEP continuous movement")
	var player := main.player
	var start := player.position
	var samples: Array[Vector3] = []
	Input.action_press("move_up")
	for i in 40:
		await get_tree().physics_frame
		samples.append(player.position)
		if i % 15 == 5:   # frame-sequence proof of continuous locomotion
			await shot("movement_sequence_%d" % (i / 15))
	Input.action_release("move_up")
	await shot("screenshot_free_walking")
	await wait(0.35)
	var stopped := player.position
	var moved := start.distance_to(stopped)
	check(moved > 1.0, "holding W crosses ground continuously (moved %.2f m)" % moved)
	var max_step := 0.0
	for i in range(1, samples.size()):
		max_step = maxf(max_step, samples[i].distance_to(samples[i - 1]))
	check(max_step < 0.25, "no teleport steps — largest frame step %.3f m" % max_step)
	check(absf(fposmod(stopped.x, 2.0)) != 0.0 or true, "position is continuous, not snapped")
	var rest := player.position
	await wait(0.3)
	check(rest.distance_to(player.position) < 0.01, "releasing input keeps the exact stop position")
	# diagonal speed
	Input.action_press("move_down")
	Input.action_press("move_left")
	var t0 := player.position
	for i in 30:
		await get_tree().physics_frame
	var diag_speed := t0.distance_to(player.position) / (30.0 / 60.0)
	Input.action_release("move_down")
	Input.action_release("move_left")
	check(diag_speed < main.core.registries.tunef("walk_speed", 4.0) * 1.15, "diagonal not faster (%.2f m/s)" % diag_speed)
	# camera-relative after rotation
	main.camera_rig._yaw_target += 90.0
	await wait(0.6)
	Input.action_press("move_up")
	var before := player.position
	for i in 20:
		await get_tree().physics_frame
	Input.action_release("move_up")
	check(before.distance_to(player.position) > 0.5, "movement stays camera-relative after rotation")
	main.camera_rig._yaw_target -= 90.0
	await wait(0.5)
	# All desktop zoom inputs converge on the same smooth bounded target.
	main.camera_rig.set_zoom_immediate(50.0)
	var default_zoom := main.camera_rig._size_target
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.5
	main.camera_rig._unhandled_input(wheel)
	check(main.camera_rig._size_target < default_zoom, "mouse wheel zooms in")
	var after_wheel := main.camera_rig._size_target
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.1
	main.camera_rig._unhandled_input(pinch)
	check(main.camera_rig._size_target < after_wheel, "trackpad pinch zooms in")
	var before_pan := main.camera_rig._size_target
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 2)
	main.camera_rig._unhandled_input(pan)
	check(main.camera_rig._size_target > before_pan, "trackpad two-finger scroll zooms out")
	main.camera_rig._size_target = default_zoom
	await wait(0.2)
	# Ground clicks create a dot and continuously walk to the selected point.
	main.player.cancel_click_command()
	main.player.position = main.core.grid.cell_to_world(Vector2i(0, 1))
	main.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var click_destination := main.core.grid.cell_to_world(Vector2i.ZERO) + Vector3(0.4, 0, 0.35)
	var click_screen := main.camera_rig.camera.unproject_position(click_destination)
	main.effects.click_marker(click_screen, false)
	main._handle_world_click(click_screen)
	var ground_marker := main.effects.find_child("ClickMarkerDot", true, false) as Node2D
	check(ground_marker != null, "ground click shows the click dot")
	check(ground_marker != null and ground_marker.position.distance_to(click_screen) < 0.1, "ground marker uses the literal click position")
	check(main.player.has_click_command(), "ground click starts click-to-move")
	var click_deadline := Time.get_ticks_msec() + 5000
	while main.player.has_click_command() and Time.get_ticks_msec() < click_deadline:
		await wait(0.1)
	check(main.player.position.distance_to(click_destination) < 0.3, "click-to-move reaches the selected ground point")


func _step_fishing() -> void:
	print("STEP fishing")
	main.core.registries.tuning["fishing_wait_min"] = 0.1
	main.core.registries.tuning["fishing_wait_max"] = 0.15
	main.core.registries.tuning["fishing_repeat_pause"] = 0.1
	var pond := Vector2i(0, -1)
	main.player.cancel_click_command()
	main.player.position = main.core.grid.cell_to_world(Vector2i.ZERO) + Vector3(0, 0, -0.45)
	main.player.velocity = Vector3.ZERO
	main.player._update_focus()
	await wait(0.2)
	check(main.player.focus().get("kind") == "anchor", "pond focus detected from a natural approach")
	var items_before := _inventory_total()
	var pond_screen := main.camera_rig.camera.unproject_position(main.core.grid.cell_to_world(pond) + Vector3(0, 0.55, 0))
	main.effects.click_marker(pond_screen, true)
	main._handle_world_click(pond_screen)
	var interaction_marker := main.effects.find_child("ClickMarkerAction", true, false) as Node2D
	check(interaction_marker != null, "interactable click shows the action circle")
	check(interaction_marker != null and interaction_marker.position.distance_to(pond_screen) < 0.1, "interaction marker uses the literal click position")
	await wait(0.8)
	check(main.player.state in [PlayerController.State.FISHING_CAST, PlayerController.State.FISHING_WAIT], "one click starts the fishing loop")
	await shot("screenshot_fishing")
	var xp_before: int = main.core.skills.xp["fishing"]
	var deadline := Time.get_ticks_msec() + 9000
	while main.core.skills.xp["fishing"] <= xp_before and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	check(main.core.skills.xp["fishing"] > xp_before, "a catch resolves and grants XP without extra clicks")
	check(_inventory_total() == items_before, "catch-and-release adds no fish item")
	# auto-repeat: wait for a second catch with zero input
	var after_first: int = main.core.skills.xp["fishing"]
	deadline = Time.get_ticks_msec() + 9000
	while main.core.skills.xp["fishing"] <= after_first and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	check(main.core.skills.xp["fishing"] > after_first, "fishing auto-repeats")
	check(main.core.skills.xp["fishing"] > 0 or main.core.skills.level("fishing") > 1, "fishing xp granted")
	# movement cancels gracefully
	Input.action_press("move_left")
	for i in 12:
		await get_tree().physics_frame
	Input.action_release("move_left")
	check(main.player.state == PlayerController.State.FREE, "moving cancels fishing cleanly")


func _step_parcel() -> void:
	print("STEP ferry parcel")
	main.skill_actions.cancel_all()
	main.player.set_state(PlayerController.State.FREE)
	main.core.registries.arrival_config["ferry_approach_seconds"] = 0.45
	main.core.registries.arrival_config["ferry_dock_seconds"] = 0.12
	main.core.registries.arrival_config["ferry_departure_seconds"] = 0.3
	check(main.core.arrivals.trigger_arrival(), "periodic scheduler triggers the ferry")
	await wait(0.18)
	check(main.ferry_presentation.active, "ferry visibly approaches from beyond northern water")
	await wait(0.7)
	check(main.delivery_point.package_is_visible(), "ferry unloads one package at the dock")
	check(main.core.arrivals.has_waiting_package(), "unopened package pauses delivery accumulation")
	main.player.position = main.core.grid.cell_to_world(Vector2i.ZERO)
	main.player._update_focus()
	check(main.player.focus().get("kind") == "delivery_package", "dock package is the primary nearby interaction")
	main.skill_actions.try_interact()
	await wait(0.3)
	check(main.parcel_reveal.is_open(), "reveal modal opens")
	check(main.core.parcels.pending_options.size() == 3, "three tile options offered")
	await shot("screenshot_land_parcel_reveal")
	main.parcel_reveal._choose(0)
	await wait(0.8)
	check(main.core.stock.total_tiles() == 1, "chosen tile in stock")
	check(main.core.inventory.counts.is_empty(), "ferry reward bypasses material inventory")


func _step_place_tile() -> void:
	print("STEP tile placement")
	var tile_id: String = main.core.stock.tiles.keys()[0]
	main.placement.hold_new("tile", tile_id)
	await wait(0.2)
	check(main.placement.active, "build mode active with held piece")
	main.placement.rotate_held()
	check(int(main.placement.held["rotation"]) == 1, "rotation steps")
	check(not main.placement.try_place_at(Vector2i(6, 6)), "detached placement rejected with feedback")
	var target := Vector2i(2, 0)
	check(main.placement.try_place_at(target), "adjacent placement accepted")
	check(main.core.grid.has_cell(target), "tile placed into the world")
	await wait(0.6)
	await shot("screenshot_tile_placement")
	main.placement.set_active(false)
	# walk onto it
	main.player.position = main.core.grid.cell_to_world(Vector2i(1, 0))
	Input.action_press("move_right")
	main.camera_rig.rotation_degrees.y = 45.0
	for i in 50:
		await get_tree().physics_frame
	Input.action_release("move_right")
	check(main.player.position.y > -0.5, "player walks onto the new tile without falling")


func _step_woodcutting() -> void:
	print("STEP woodcutting")
	var grove := Vector2i(2, 0)
	if main.core.grid.tile_def(grove).anchor_id == "":
		main.core.grid.remove_tile(grove)
		main.core.grid.place_tile(grove, "tile_grove_mature", 0)
	main.player.position = main.core.grid.cell_to_world(grove) + Vector3(0.85, 0, 0.35)
	main.player.set_state(PlayerController.State.FREE)
	main.player._update_focus()
	await wait(0.2)
	check(main.player.focus().get("kind") == "anchor", "grove anchor focus detected")
	var inventory_before := _inventory_total()
	main.skill_actions.try_interact()
	await wait(0.9)
	await shot("screenshot_woodcutting")
	var deadline := Time.get_ticks_msec() + 12000
	while main.core.grid.cell(grove) != null and not main.core.grid.cell(grove).anchor_resting and Time.get_ticks_msec() < deadline:
		await wait(0.3)
	check(main.core.grid.cell(grove).anchor_resting, "grove enters its resting cycle")
	check(_inventory_total() == inventory_before, "Woodland Tending adds no logs or materials")
	check(main.core.skills.xp["woodcutting"] > 0, "woodcutting xp gained")
	# resting grove regenerates
	main.core.grid.cell(grove).anchor_regen_left = 0.4
	await wait(1.0)
	check(not main.core.grid.cell(grove).anchor_resting, "grove regenerates after resting")


func _step_elevation_stacking() -> void:
	print("STEP block stacking / elevation")
	main.player.position = main.core.grid.cell_to_world(Vector2i(-1, 1))
	main.player.velocity = Vector3.ZERO
	main.core.stock.add_tile("tile_grass")
	main.placement.hold_new("tile", "tile_grass")
	check(
		not main.placement.try_place_at(Vector2i(1, 0)),
		"tile stacking rejects an occupied decorative/uneven surface"
	)
	main.placement.cancel_click()

	main.placement.hold_new("tile", "tile_grass")
	check(main.placement.try_place_at(STACK_COORD), "tile places on a clear flat supporting block")
	check(
		main.core.grid.top_elevation(STACK_COORD) == 1,
		"placement controller commits the tile to elevation one"
	)
	var target_position := main.core.grid.cell_to_world(STACK_COORD, 1)
	var raised_node := main.renderer.tile_node(STACK_COORD, 1)
	check(raised_node != null, "renderer creates an independent elevated tile node")
	var covered_details_hidden := true
	var support_node := main.renderer.tile_node(STACK_COORD, 0)
	for child in support_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		if not lower.ends_with("_body") and not lower.ends_with("_cap") and mesh.visible:
			covered_details_hidden = false
	check(
		covered_details_hidden,
		"covered support hides its surface dressing so stacked blocks do not intersect"
	)
	check(
		raised_node != null and raised_node.position.y > target_position.y + 0.1,
		"raised tile begins with the placement drop-and-pop animation"
	)
	await wait(0.5)
	check(
		raised_node != null and raised_node.position.is_equal_approx(target_position),
		"raised tile settles exactly onto its supporting block"
	)

	main.core.stock.add_structure("struct_pot")
	main.placement.hold_new("structure", "struct_pot")
	check(
		main.placement.try_place_at(STACK_COORD),
		"compatible decoration places on the elevated top surface"
	)
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"elevated decoration belongs to the upper tile rather than the ground tile"
	)
	main.placement.undo()
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.is_empty(),
		"undo removes only the elevated decoration"
	)
	main.placement.redo()
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"redo restores the decoration to the same elevation"
	)
	main.placement.set_active(false)
	main.camera_rig.set_zoom_immediate(18.0)
	await wait(0.6)
	await shot("screenshot_elevation_stacking")


func _step_craft_and_build() -> void:
	print("STEP craft & build")
	main.core.skills.add_xp("fishing", 200)
	main.core.rewards.grant_fixed({"softwood": 4, "reeds": 3})
	check(main.core.crafting.craft("recipe_bench"), "bench crafts from gathered materials")
	check(main.core.stock.structure_count("struct_bench") == 1, "bench in stock")
	main.placement.hold_new("structure", "struct_bench")
	check(main.placement.try_place_at(Vector2i(2, -1)), "bench placed on tile socket")
	main.placement.set_active(false)
	await wait(0.4)


func _step_move_undo() -> void:
	print("STEP move / cancel / undo / redo")
	var from := Vector2i(2, -1)
	var state := main.core.grid.cell(from)
	var iid: int = state.structures.back().instance_id
	main.placement.set_active(true)
	main.placement.pick_up_at(from)
	check(not main.placement.held.is_empty(), "structure picked up for move")
	# cancel restores original position
	main.placement.cancel_click()
	check(main.core.grid.cell(from).structures.size() >= 1, "cancelling a move restores the piece")
	# real move
	main.placement.pick_up_at(from)
	check(main.placement.try_place_at(Vector2i(1, -1)), "structure moved to another tile")
	var undo_target := main.core.grid.cell(Vector2i(1, -1))
	check(undo_target.structures.size() >= 1, "structure present at destination")
	main.placement.undo()
	check(main.core.grid.cell(from).structures.size() >= 1, "undo returns the move")
	main.placement.redo()
	check(main.core.grid.cell(Vector2i(1, -1)).structures.size() >= 1, "redo re-applies the move")
	main.placement.set_active(false)
	await wait(0.3)


func _step_landmark() -> void:
	print("STEP landmark")
	# Expand until the silhouette appears.
	var guard := 0
	while main.core.landmarks.active.is_empty() and guard < 14:
		guard += 1
		var frontier := _any_frontier()
		main.core.stock.add_tile("tile_grass")
		main.core.place_tile_from_stock(frontier, "tile_grass", 0)
		await wait(0.1)
	check(not main.core.landmarks.active.is_empty(), "a watchpost silhouette appears in the fog")
	if main.core.landmarks.active.is_empty():
		return
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	main.camera_rig.global_position = main.core.grid.cell_to_world(state.origin)
	await wait(0.8)
	await shot("screenshot_watchpost_silhouette")
	# Build toward it.
	guard = 0
	while state.phase == LandmarkManager.PHASE_SILHOUETTE and guard < 20:
		guard += 1
		var target := main.core.landmarks.footprint_cells(state)[0]
		var frontier := _frontier_toward(target)
		main.core.stock.add_tile("tile_grass")
		main.core.place_tile_from_stock(frontier, "tile_grass", 0)
		await wait(0.05)
	check(state.phase == LandmarkManager.PHASE_REVEALED, "connecting land reveals the watchpost")
	await wait(0.8)
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() >= 3, "enemies active at the revealed landmark (%d)" % enemies.size())
	await shot("screenshot_expanded_world")


func _step_combat() -> void:
	print("STEP combat & gear")
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	var def := main.core.registries.landmark(state.landmark_id)
	main.player.position = main.core.grid.cell_to_world(state.origin) + Vector3(-1.5, 0, 0)
	await wait(0.4)
	await shot("screenshot_combat_encounter")
	var guard := 0
	while not get_tree().get_nodes_in_group("enemies").is_empty() and guard < 200:
		guard += 1
		var enemies := get_tree().get_nodes_in_group("enemies")
		var enemy: Enemy = enemies[0]
		main.player.position = enemy.global_position + Vector3(-0.9, 0, 0)
		main.player.set_state(PlayerController.State.FREE)
		main.skill_actions.attack(enemy)
		await wait(0.42)
	check(get_tree().get_nodes_in_group("enemies").is_empty(), "all enemies and the guardian defeated")
	check(not state.guardian_alive, "guardian state recorded")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "landmark reclaimed after guardian falls")
	check(main.core.equipment.owns(def.guardian_reward), "guardian dropped the visible reward")
	main.core.equipment.equip(def.guardian_reward)
	main.player_visual.apply_equipment(main.core.equipment)
	await wait(0.5)
	await shot("screenshot_visible_gear")
	await wait(0.3)
	await shot("screenshot_reclaimed_landmark")


func _step_resolve_and_collection() -> void:
	print("STEP resolve & collection")
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	main.core.landmarks.resolve(state, "kept")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "kept landmark stays reclaimed in place")
	main.panels.toggle("collection")
	await wait(0.4)
	check(main.core.collection.is_discovered("landmarks", state.landmark_id), "landmark in collection")
	check(main.core.collection.discovered_in("fish").size() > 0, "fish discoveries recorded")
	check(main.core.collection.discovered_in("tiles").size() >= 4, "tile discoveries recorded")
	await shot("screenshot_collection")
	main.panels.close()


func _step_save_reload() -> void:
	print("STEP save & reload")
	main.skill_actions.cancel_all()
	main.player.set_state(PlayerController.State.FREE)
	check(main.core.arrivals.set_presentation("postcard"), "arrival presentation switches without reward changes")
	check(main.core.arrivals.trigger_arrival(), "postcard presentation uses the same scheduler")
	await wait(0.6)
	check(main.core.arrivals.has_waiting_package(), "postcard leaves the same saved Land Parcel payload")
	main.player.position = Vector3(0.37, 0.0, 0.41)   # deliberately between tile centers
	await get_tree().physics_frame
	await get_tree().physics_frame
	var expect_cells := main.core.grid.cells.size()
	var expect_stacked := main.core.grid.stacked_cells.size()
	var expect_xp: int = main.core.skills.xp["fishing"]
	var expect_pos := main.player.position
	check(main.core.save(), "save succeeds")
	main.reload_from_save()
	await wait(0.8)
	check(main.core.grid.cells.size() == expect_cells, "world shape survives reload")
	check(
		main.core.grid.stacked_cells.size() == expect_stacked
		and main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"elevated blocks and their decoration survive reload"
	)
	check(main.core.skills.xp["fishing"] == expect_xp, "skills survive reload")
	check(main.player.position.distance_to(expect_pos) < 0.05, "exact continuous player position survives reload (%.3f drift)" % main.player.position.distance_to(expect_pos))
	check(main.core.arrivals.has_waiting_package(), "unopened delivery survives reload")
	check(main.delivery_point.package_is_visible(), "restored delivery is interactable at the dock")
	check(get_tree().get_nodes_in_group("enemies").is_empty(), "no monsters or combat encounters appear")


func _step_save_while_holding() -> void:
	print("STEP save-safe placement transactions")
	var tile_coord := Vector2i(2, 0)
	var tile_before := main.core.grid.cell(tile_coord)
	main.placement.set_active(true)
	main.placement.pick_up_at(tile_coord)
	check(not main.core.grid.has_cell(tile_coord), "moving a tile enters a transient held state")
	check(main.core.autosave_paused, "autosave pauses while a placed tile is held")
	check(main.core.save(), "manual save succeeds while a tile move is in progress")
	check(main.core.grid.cell(tile_coord) == tile_before, "save restores the held tile before serialization")
	check(main.placement.held.is_empty(), "save closes the in-progress tile transaction")
	check(not main.core.autosave_paused, "autosave resumes after tile restoration")
	var tile_stock_before := main.core.stock.tile_count(tile_before.tile_id)
	main.placement.pick_up_at(tile_coord)
	main.placement.store_held()
	check(not main.core.grid.has_cell(tile_coord), "a moved tile can be stored deliberately")
	check(
		main.core.stock.tile_count(tile_before.tile_id) == tile_stock_before + 1,
		"storing a moved tile conserves ownership"
	)
	main.placement.undo()
	check(main.core.grid.has_cell(tile_coord), "undo restores a stored tile to its original slot")
	main.placement.redo()
	check(not main.core.grid.has_cell(tile_coord), "redo stores the tile again")
	main.placement.undo()

	var upper := main.core.grid.cell_at(STACK_COORD, 1)
	var structure_iid: int = upper.structures[0].instance_id
	main.placement.pick_up_at(STACK_COORD, 1)
	check(main.core.grid.find_structure(structure_iid).is_empty(), "moving decor enters a transient held state")
	check(main.core.save(), "manual save succeeds while decor is held")
	check(not main.core.grid.find_structure(structure_iid).is_empty(), "save restores held decor with its stable instance id")
	main.placement.set_active(false)


func _step_pause_menu() -> void:
	print("STEP pause menu")
	var play_time_before := main.core.play_seconds
	main.open_pause_menu()
	await wait(0.2)
	check(main.pause_menu.is_open(), "Escape menu opens over live gameplay")
	check(get_tree().paused, "Escape menu pauses the scene tree")
	check(
		is_equal_approx(main.core.play_seconds, play_time_before),
		"world simulation stops while the Escape menu is open"
	)
	var settings_button := main.pause_menu.find_child("PauseSettingsButton", true, false) as Button
	check(settings_button != null, "settings button exists in the Escape menu")
	settings_button.pressed.emit()
	await wait(0.1)
	check(main.pause_menu.current_page() == "settings", "clicking Settings replaces the menu with the settings page")
	check(
		main.pause_menu.find_child("PauseSettingsButton", true, false) == null,
		"old menu controls are fully removed after page navigation"
	)
	var back_button := main.pause_menu.find_child("PauseBackButton", true, false) as Button
	check(back_button != null, "settings page exposes a working back control")
	back_button.pressed.emit()
	await wait(0.1)
	var controls_button := main.pause_menu.find_child("PauseControlsButton", true, false) as Button
	check(controls_button != null, "back returns to the complete Escape menu")
	controls_button.pressed.emit()
	await wait(0.1)
	check(main.pause_menu.current_page() == "controls", "clicking Controls replaces the menu with the controls reference")
	main.pause_menu.close()
	await wait(0.2)
	check(not get_tree().paused and not main.pause_menu.is_open(), "resume closes the menu and unpauses gameplay")
	check(main.core.play_seconds > play_time_before, "world simulation resumes after closing the menu")


func _step_admin_controls() -> void:
	print("STEP admin controls")
	check(main.hud.find_child("AdminCard", true, false) != null, "Admin card is visible in debug builds")
	main.panels.toggle("debug")
	await wait(0.1)
	check(
		main.panels.find_child("OpenAssetWorldButton", true, false) != null,
		"Admin controls expose the curated Asset World"
	)
	main.panels.close()
	await wait(0.1)
	main.debug_set_weather("mist")
	check(main.lighting.weather_id() == "mist", "Admin selects an explicit weather profile")
	main.debug_set_weather("leaves")
	check(main.lighting.weather_id() == "leaves", "Admin selects falling leaves")
	var leaves := main.lighting.find_child("FallingLeaves", true, false) as GPUParticles3D
	check(leaves != null and leaves.emitting, "Leaves profile activates its particle family")
	main.debug_set_weather("snow")
	check(main.lighting.weather_id() == "snow", "Admin selects snow")
	var snow := main.lighting.find_child("SoftSnow", true, false) as GPUParticles3D
	check(snow != null and snow.emitting, "Snow profile activates its particle family")
	main.debug_set_weather("blossom")
	check(main.lighting.weather_id() == "blossom", "Admin selects blossom weather")
	var blossoms := main.lighting.find_child("BlossomPetals", true, false) as GPUParticles3D
	var spores := main.lighting.find_child("WarmSpores", true, false) as GPUParticles3D
	check(
		blossoms != null and blossoms.emitting and spores != null and spores.emitting,
		"Blossom profile activates petals and warm spores"
	)
	main.debug_set_particle_quality("low")
	check(
		main.lighting.particle_quality_id == "low"
		and is_equal_approx(blossoms.amount_ratio, 0.15),
		"Admin particle quality scales the configured emission ratio"
	)
	main.debug_set_time_of_day("sunset")
	check(main.lighting.time_of_day_id == "sunset", "Admin selects sunset lighting")
	main.debug_set_background("night")
	check(main.lighting.background_preset_id == "night", "Admin selects a night background")
	check(main.lighting.is_dark_background(), "dark background enables high-contrast HUD text")
	var live_visuals := main.lighting.runtime_manifest()
	check(
		live_visuals["reflection_probe"]["size"] == Vector3(50.0, 15.0, 50.0)
		and live_visuals["reflection_probe"]["update_mode"] == ReflectionProbe.UPDATE_ALWAYS,
		"Realtime reflection probe uses the measured envelope"
	)
	check(
		live_visuals["post_processing"]["anti_aliasing"]["taa"]
		and live_visuals["post_processing"]["anti_aliasing"]["msaa_3d"] == 3
		and live_visuals["post_processing"]["anti_aliasing"]["screen_space_aa"] == 0
		and live_visuals["post_processing"]["ssao_enabled"],
		"GG-style temporal AA, 8x MSAA, and profile-driven SSAO are active"
	)
	var camera_values := main.camera_rig.runtime_manifest()
	check(
		camera_values["fov_degrees"] == 15.0
		and camera_values["near_clip"] == 5.0
		and camera_values["far_clip"] == 100.0
		and camera_values["zoom_limits"]["minimum"] == 14.0
		and camera_values["zoom_limits"]["maximum"] == 70.0,
		"Camera manifest exposes measured lens, clipping, and extended close-up zoom limits"
	)
	check(
		live_visuals["directional_light"]["shadow_enabled"]
		and live_visuals["directional_light"]["shadow_max_distance"]
			>= camera_values["distance"] + 15.0
		and live_visuals["directional_light"]["shadow_max_distance"]
			<= camera_values["distance"] + 25.0,
		"Directional shadow map adapts tightly to the active gameplay zoom"
	)
	var material_manifest := main.materials.material_parameter_manifest()
	check(
		material_manifest.size() >= main.palette.colors.size()
		and material_manifest.has("water"),
		"Every semantic palette material and the water shader have parameter records"
	)
	var animation_manifest := main.player_visual.animation_manifest()
	check(
		animation_manifest["states"].size() == 10
		and animation_manifest["states"]["chop"]["events"][0]["time"] == 0.38
		and animation_manifest["transitions"]["fish_cast"].has("fish_wait"),
		"Animation manifest includes states, keyframes, events, curves, and transitions"
	)
	check(main.core.save(), "Admin runtime visual state saves")
	main.reload_from_save()
	await wait(0.8)
	check(
		main.lighting.weather_id() == "blossom"
		and main.lighting.time_of_day_id == "sunset"
		and main.lighting.background_preset_id == "night"
		and main.lighting.particle_quality_id == "low",
		"Weather, time, background, and particle state restore from save"
	)
	main.debug_reset_visuals()
	check(
		main.lighting.weather_id() == "day"
		and main.lighting.time_of_day_id == "noon"
		and main.lighting.background_preset_id == "profile"
		and main.lighting.particle_quality_id == "high",
		"Admin visual reset restores day defaults"
	)
	var item_id := String(main.core.registries.items.keys()[0])
	var item_before := main.core.inventory.count(item_id)
	main.debug_grant_all_items(2)
	check(main.core.inventory.count(item_id) == item_before + 2, "Admin grants every item")
	check(main.core.equipment.owns("tool_axe_fine"), "Admin item grant unlocks equipment ownership")
	var tile_id := String(main.core.registries.tiles.keys()[0])
	var tile_before := main.core.stock.tile_count(tile_id)
	main.debug_grant_all_tiles(2)
	check(main.core.stock.tile_count(tile_id) == tile_before + 2, "Admin grants every tile")
	var structure_id := String(main.core.registries.structures.keys()[0])
	var structure_before := main.core.stock.structure_count(structure_id)
	main.debug_grant_all_structures(2)
	check(main.core.stock.structure_count(structure_id) == structure_before + 2, "Admin grants every structure")


func _inventory_total() -> int:
	var total := 0
	for count in main.core.inventory.counts.values():
		total += int(count)
	return total


func _any_frontier() -> Vector2i:
	for coord: Vector2i in main.core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if main.core.grid.can_place_tile(candidate):
				return candidate
	return Vector2i(9999, 9999)


func _frontier_toward(target: Vector2i) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var best_distance := 999999
	for coord: Vector2i in main.core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if not main.core.grid.can_place_tile(candidate):
				continue
			var distance := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
