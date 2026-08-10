extends Node
## Scene-level regression for frame-budgeted Nook expansion.

const SAVE_PATH := "user://nook_expansion_smoke_save.json"

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
	await _exercise_expansion()
	await _finish()


func _exercise_expansion() -> void:
	# Mirror a mature player save so the test exercises the MultiMesh backend,
	# not only the small exact-node renderer.
	_main.renderer.begin_bulk_update()
	for y in 23:
		for x in 23:
			var mature_cell := Vector2i(100 + x, 100 + y)
			if not _main.core.grid.has_cell(mature_cell):
				_main.core.grid.place_tile(mature_cell, "tile_grass")
	await _main.renderer.end_bulk_update_async(false)
	_expect(_main.renderer._scalable_mode, "mature worlds use the scalable renderer")
	var targets := NookFrontierMarkers.frontier_targets(_main.core.nooks.world)
	_expect(not targets.is_empty(), "the live world exposes a frontier target")
	if targets.is_empty():
		return
	var coord: Vector2i = targets[0]["nook"]
	# The legacy smoke opening starts with its tutorial tree held. Expansion is
	# intentionally blocked while moving a piece, so clear that test fixture.
	if not _main.placement.held.is_empty():
		_main.placement.cancel_click()
	var reveal_state := {
		"started": false,
		"finished": false,
		"duration": 0.0,
		"saw_scalable_fall": false,
		"saw_reveal_headroom": false,
		"model_count": 0,
		"water_count": 0,
		"saw_model_plop": false,
		"saw_water_rise": false,
		"staged_without_preflash": false,
	}
	var hidden_builds_before := (
		_main.renderer.reveal_staged_instances_built_hidden
	)
	var preflash_violations_before := _main.renderer.reveal_preflash_violations
	_main.core.nooks.nook_revealed.connect(
		func(revealed_coord: Vector2i, plan: NookGenerator.NookPlan):
			if revealed_coord != coord:
				return
			reveal_state["model_count"] = plan.features.size()
			for tile: Dictionary in plan.tiles:
				var definition := _main.core.registries.tile(
					String(tile.get("tile_id", ""))
				)
				if definition != null \
					and definition.render_profile == "continuous_water":
					reveal_state["water_count"] = int(
						reveal_state["water_count"]
					) + 1
			reveal_state["saw_model_plop"] = not (
				_main.renderer._scalable_backend
					.reveal_structures_in_flight.is_empty()
			)
			reveal_state["saw_water_rise"] = not (
				_main.renderer.reveal_water_in_flight.is_empty()
			)
			var expected_hidden := plan.tiles.size()
			for feature: Dictionary in plan.features:
				if int(feature.get("instance_id", 0)) > 0:
					expected_hidden += 1
			var hidden_build_delta := (
				_main.renderer.reveal_staged_instances_built_hidden
				- hidden_builds_before
			)
			reveal_state["staged_without_preflash"] = (
				hidden_build_delta >= expected_hidden
				and _main.renderer.reveal_preflash_violations
					== preflash_violations_before
			)
	)
	_main.nook_reveal_presenter.reveal_started.connect(
		func(revealed_coord: Vector2i, duration: float):
			if revealed_coord == coord:
				reveal_state["started"] = true
				reveal_state["duration"] = duration
				reveal_state["saw_scalable_fall"] = not (
					_main.renderer._scalable_backend
						.reveal_tiles_in_flight.is_empty()
				)
				var backend = _main.renderer._scalable_backend
				for tile: Dictionary in backend.tile_instances.values():
					var multimesh: MultiMesh = tile["multimesh"]
					if multimesh == null or multimesh.mesh == null:
						continue
					var configured_drop := float(
						_main.core.registries.reveal_config.get(
							"tile_drop_height", 6.0
						)
					)
					reveal_state["saw_reveal_headroom"] = (
						multimesh.custom_aabb.size.y
							>= multimesh.mesh.get_aabb().size.y + configured_drop
					)
					if bool(reveal_state["saw_reveal_headroom"]):
						break
	)
	_main.nook_reveal_presenter.reveal_finished.connect(
		func(revealed_coord: Vector2i):
			if revealed_coord == coord:
				reveal_state["finished"] = true
	)
	var accepted := _main._expand_nook_at(coord)
	_expect(accepted, "frontier input schedules expansion immediately")
	var responsive_frames := 0
	var max_frame_gap_ms := 0.0
	var previous_tick := Time.get_ticks_usec()
	var expansion_started_tick := previous_tick
	while (
		not bool(reveal_state["started"])
		and Time.get_ticks_usec() - expansion_started_tick < 10000000
	):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		max_frame_gap_ms = maxf(
			max_frame_gap_ms,
			float(now - previous_tick) / 1000.0
		)
		previous_tick = now
		responsive_frames += 1
	_expect(
		bool(reveal_state["started"]) and responsive_frames >= 3,
		"expansion yields across multiple responsive frames before reveal"
	)
	_expect(
		max_frame_gap_ms < 150.0,
		"no expansion frame monopolizes the main thread"
	)
	print("  expansion max frame gap: %.2f ms" % max_frame_gap_ms)
	print(
		"  expansion preparation time: %.2f ms" % (
			float(Time.get_ticks_usec() - expansion_started_tick) / 1000.0
		)
	)
	if not bool(reveal_state["started"]):
		return
	await get_tree().create_timer(float(reveal_state["duration"]) + 0.4).timeout
	_expect(bool(reveal_state["finished"]), "the flying-tile reveal completes")
	var origin := _main.core.nooks.world.chunk_origin(coord)
	var all_seated := true
	for local_y in _main.core.nooks.world.nook_size:
		for local_x in _main.core.nooks.world.nook_size:
			var cell := origin + Vector2i(local_x, local_y)
			for elevation in range(0, _main.core.grid.top_elevation(cell) + 1):
				var holder := _main.renderer.cell_holder(cell, elevation)
				if holder != null:
					if not holder.position.is_equal_approx(
						_main.core.grid.cell_to_world(cell, elevation)
					):
						all_seated = false
					continue
				var key := _main.core.grid.slot_key(cell, elevation)
				var backend = _main.renderer._scalable_backend
				if not backend.tile_instances.has(key):
					all_seated = false
	_expect(
		bool(reveal_state["saw_scalable_fall"]),
		"mature-world MultiMesh tiles participate in the flying reveal"
	)
	_expect(
		bool(reveal_state["saw_reveal_headroom"]),
		"MultiMesh culling bounds include the full sky-drop path"
	)
	_expect(
		bool(reveal_state["staged_without_preflash"]),
		"new tiles and models enter the scene hidden before reveal ownership"
	)
	_expect(
		all_seated
		and _main.renderer._scalable_backend.reveal_tiles_in_flight.is_empty(),
		"every asynchronously generated tile finishes seated"
	)
	if int(reveal_state["model_count"]) > 0:
		_expect(
			bool(reveal_state["saw_model_plop"]),
			"generated MultiMesh models use the post-terrain plop phase"
		)
	if int(reveal_state["water_count"]) > 0:
		_expect(
			bool(reveal_state["saw_water_rise"]),
			"generated water uses its independent rise-from-below phase"
		)
	print(
		"  generated reveal content: %d models, %d water layers" % [
			int(reveal_state["model_count"]),
			int(reveal_state["water_count"]),
		]
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok — " + message)
	else:
		_failures += 1
		push_error("NOOK EXPANSION FAIL: " + message)


func _finish() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if _failures == 0:
		print("NOOK EXPANSION SMOKE PASSED")
	else:
		print("NOOK EXPANSION SMOKE FAILED — %d checks" % _failures)
	if is_instance_valid(_main):
		_main.free()
		_main = null
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(_failures)
