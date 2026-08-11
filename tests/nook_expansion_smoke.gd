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
	var frontier_cell := NookFrontierMarkers.marker_cell(
		_main.core.nooks.world,
		coord,
		targets[0]["direction"]
	)
	var protected_local := Vector2i(2, 2)
	var protected_cell := (
		_main.core.nooks.world.chunk_origin(coord) + protected_local
	)
	# The legacy smoke opening starts with its tutorial tree held. Clear that
	# fixture before probing the live player-placement boundary.
	if not _main.placement.held.is_empty():
		_main.placement.cancel_click()
	_main.core.stock.add_tile("tile_grass")
	_main.placement.hold_new("tile", "tile_grass")
	_expect(
		not _main.placement.try_place_at(protected_cell)
		and not _main.core.grid.has_cell(protected_cell)
		and _main.core.stock.tile_count("tile_grass") == 1,
		"the unrevealed frontier rejects pointer/controller tile placement"
	)
	_main.placement.cancel_click()
	# Grandfathered saves from before the boundary may still contain a column
	# here. Simulate one directly so asynchronous generation remains proven
	# non-destructive for those worlds.
	_main.core.grid.place_tile(protected_cell, "tile_grass")
	var protected_structure := _main.core.grid.add_structure(
		protected_cell, "struct_pine", 1
	)
	_expect(
		protected_structure != null,
		"a grandfathered frontier tile and model can be represented safely"
	)
	var expected_ghost_cells := (
		_main.core.nooks.world.nook_size ** 2 - 1
	)
	_main.placement.set_active(false)
	_main._update_frontier_marker_availability()
	_main._try_expand_frontier_at_cell(frontier_cell)
	var frontier_project := _main.core.projects.tracked_project()
	_expect(
		not _main.project_panel.is_open()
		and frontier_project.get("type", "") == ProjectService.TYPE_FRONTIER
		and not bool(frontier_project.get("complete", false))
		and not _main._nook_reveal_in_progress,
		"clicking a locked frontier tracks its requirements without modal friction or generation"
	)
	_main.frontier_picker.call("_show_for_coord", coord)
	var requirement_row := _main.frontier_picker.find_child(
		"Requirements", true, false
	) as HBoxContainer
	var frontier_action := _main.frontier_picker.find_child(
		"FrontierAction", true, false
	) as Button
	_expect(
		(frontier_project.get("slots", []) as Array).size() == 3
		and requirement_row != null
		and requirement_row.get_child_count() == 3
		and frontier_action != null
		and frontier_action.disabled
		and frontier_action.text.contains("remaining")
		and _main.frontier_picker.find_child(
			"Requirement_timber", true, false
		) != null
		and not (frontier_project.get("frontier_metadata", {}) as Dictionary).get(
			"preview", ""
		).is_empty(),
		"the dot card exposes three icon-count requirements backed by one reserved frontier"
	)
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
		"ghost_held_for_landing": false,
		"ghost_cell_consumed_on_contact": false,
		"landed_cells": 0,
		"protected_slot_omitted_from_plan": false,
		"coverable_supports": 0,
		"supports_kept_full_before_landing": false,
		"cover_transitions_started": 0,
		"cover_transition_started_with_full_top": true,
		"cover_transition_started_after_contact": true,
	}
	var hidden_builds_before := (
		_main.renderer.reveal_staged_instances_built_hidden
	)
	var preflash_violations_before := _main.renderer.reveal_preflash_violations
	_main.renderer.reveal_surface_cover_started.connect(
		func(cell: Vector2i, elevation: int):
			var origin := _main.core.nooks.world.chunk_origin(coord)
			var local := cell - origin
			if (
				local.x < 0
				or local.y < 0
				or local.x >= _main.core.nooks.world.nook_size
				or local.y >= _main.core.nooks.world.nook_size
			):
				return
			reveal_state["cover_transitions_started"] = int(
				reveal_state["cover_transitions_started"]
			) + 1
			var key := _main.core.grid.slot_key(cell, elevation)
			var holder := _main.renderer._reveal_cover_transition_holders.get(
				key
			) as Node3D
			reveal_state["cover_transition_started_with_full_top"] = (
				bool(reveal_state["cover_transition_started_with_full_top"])
				and _has_visible_authored_top(holder)
			)
			var incoming_key := _main.core.grid.slot_key(cell, elevation + 1)
			var incoming: Dictionary = (
				_main.renderer._scalable_backend.tile_instances.get(
					incoming_key, {}
				) as Dictionary
			)
			var multimesh := incoming.get("multimesh") as MultiMesh
			var index := int(incoming.get("index", -1))
			var reached_contact := false
			if (
				multimesh != null
				and index >= 0
				and index < multimesh.instance_count
				and incoming.has("base")
			):
				var current := multimesh.get_instance_transform(index)
				var target: Transform3D = incoming["base"]
				reached_contact = current.origin.y <= target.origin.y + 0.12
			reveal_state["cover_transition_started_after_contact"] = (
				bool(reveal_state["cover_transition_started_after_contact"])
				and reached_contact
			)
	)
	_main.core.nooks.nook_revealed.connect(
		func(revealed_coord: Vector2i, plan: NookGenerator.NookPlan):
			if revealed_coord != coord:
				return
			var planned_protected_content := false
			for tile: Dictionary in plan.tiles:
				if tile["local"] as Vector2i == protected_local:
					planned_protected_content = true
			for feature: Dictionary in plan.features:
				if feature["local"] as Vector2i == protected_local:
					planned_protected_content = true
			reveal_state["protected_slot_omitted_from_plan"] = (
				not planned_protected_content
			)
			reveal_state["model_count"] = plan.features.size()
			var coverable_supports := 0
			var supports_kept_full := true
			for tile: Dictionary in plan.tiles:
				var elevation := int(tile.get("elevation", 0))
				if elevation > 0:
					var cell := (
						_main.core.nooks.world.chunk_origin(coord)
						+ (tile["local"] as Vector2i)
					)
					var support_definition := _main.core.grid.tile_def_at(
						cell, elevation - 1
					)
					if (
						support_definition != null
						and support_definition.supports_tiles
					):
						coverable_supports += 1
						var support_key := _main.core.grid.slot_key(
							cell, elevation - 1
						)
						var support_data: Dictionary = (
							_main.renderer._scalable_backend.tile_instances.get(
								support_key, {}
							)
						)
						if (
							support_data.is_empty()
							or bool(support_data.get("covered", true))
						):
							supports_kept_full = false
				var definition := _main.core.registries.tile(
					String(tile.get("tile_id", ""))
				)
				if definition != null \
					and definition.render_profile == "continuous_water":
					reveal_state["water_count"] = int(
						reveal_state["water_count"]
					) + 1
			reveal_state["coverable_supports"] = coverable_supports
			reveal_state["supports_kept_full_before_landing"] = (
				coverable_supports > 0 and supports_kept_full
			)
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
				var origin := _main.core.nooks.world.chunk_origin(coord)
				reveal_state["staging_held_during_reveal"] = (
					_main.renderer.is_coord_staged_for_reveal(origin)
				)
				reveal_state["ghost_held_for_landing"] = (
					_main.nook_arrival_ghost.is_previewing(coord)
					and _main.nook_arrival_ghost.remaining_cell_count()
						== expected_ghost_cells
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
	_main.nook_reveal_presenter.terrain_cell_landed.connect(
		func(revealed_coord: Vector2i, _cell: Vector2i):
			if revealed_coord != coord:
				return
			reveal_state["landed_cells"] = int(
				reveal_state["landed_cells"]
			) + 1
			if int(reveal_state["landed_cells"]) == 1:
				reveal_state["ghost_cell_consumed_on_contact"] = (
					_main.nook_arrival_ghost.remaining_cell_count()
						== expected_ghost_cells - 1
				)
	)
	_main.nook_reveal_presenter.reveal_finished.connect(
		func(revealed_coord: Vector2i):
			if revealed_coord == coord:
				reveal_state["finished"] = true
	)
	var frontier_id := String(frontier_project.get("id", ""))
	for slot_index in (frontier_project.get("slots", []) as Array).size():
		var slot: Dictionary = frontier_project["slots"][slot_index]
		if bool(slot.get("consumes_find", false)):
			var accepted_find_id := String(
				(slot.get("accepted_tags", []) as Array)[0]
			).trim_prefix("find:")
			_main.core.finds.add(accepted_find_id)
			_main.core.projects.spend_find(frontier_id, slot_index)
		else:
			_main.core.projects.contribute(
				frontier_id,
				slot_index,
				"nook-smoke:%d" % slot_index
			)
	_expect(
		not _main._nook_reveal_in_progress
		and not frontier_action.disabled
		and frontier_action.text == "Unfold land",
		"finishing the requirements leaves the frontier visibly ready"
	)
	_main._try_expand_frontier_at_cell(frontier_cell)
	var accepted := _main._nook_reveal_in_progress
	_expect(accepted, "clicking the ready frontier schedules expansion once")
	_expect(
		_main.nook_arrival_ghost.is_previewing(coord),
		"the terrain arrival ghost appears on the accepted input frame"
	)
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
		bool(reveal_state.get("staging_held_during_reveal", false)),
		"incoming cells remain excluded from settled topology while falling"
	)
	_expect(
		bool(reveal_state.get("ghost_held_for_landing", false)),
		"the complete arrival ghost remains beneath the falling terrain"
	)
	_expect(
		bool(reveal_state.get("ghost_cell_consumed_on_contact", false)),
		"each ghost cell fades on its matching terrain contact"
	)
	_expect(
		int(reveal_state["coverable_supports"]) > 0,
		"the deterministic expansion fixture includes raised terrain"
	)
	_expect(
		bool(reveal_state["supports_kept_full_before_landing"]),
		"raised terrain supports keep their authored tops while upper tiles fall"
	)
	_expect(
		int(reveal_state["cover_transitions_started"])
			== int(reveal_state["coverable_supports"])
		and bool(reveal_state["cover_transition_started_with_full_top"])
		and bool(reveal_state["cover_transition_started_after_contact"]),
		"support tops begin covering from their complete form only after contact"
	)
	var protected_found := _main.core.grid.find_structure(
		protected_structure.instance_id
	) if protected_structure != null else {}
	_expect(
		bool(reveal_state.get("protected_slot_omitted_from_plan", false))
		and _main.core.grid.tile_def(protected_cell).id == "tile_grass"
		and _main.core.grid.top_elevation(protected_cell) == 0
		and not protected_found.is_empty()
		and (protected_found["coord"] as Vector2i) == protected_cell,
		"generation preserves player terrain and models in occupied frontier slots"
	)
	_expect(
		all_seated
		and _main.renderer._scalable_backend.reveal_tiles_in_flight.is_empty()
		and _main.renderer._staged_reveal_tiles.is_empty()
		and _main.renderer._reveal_cover_transition_holders.is_empty()
		and not _main.nook_arrival_ghost.is_previewing(coord),
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


func _has_visible_authored_top(holder: Node3D) -> bool:
	if holder == null or not is_instance_valid(holder) \
		or holder.get_child_count() == 0:
		return false
	var visual := holder.get_child(0) as Node3D
	if visual == null:
		return false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if (
			mesh.name == TileVisualFactory.COVERED_INFILL_NAME
			or mesh.name == TileVisualFactory.STACK_SEAM_NAME
		):
			continue
		var layer_role := String(
			mesh.get_meta(TileVisualFactory.LAYER_ROLE_META, "")
		)
		var cover_behavior := String(
			mesh.get_meta(TileVisualFactory.LAYER_COVER_BEHAVIOR_META, "")
		)
		if (
			layer_role == "base"
			or cover_behavior == "persist"
			or (
				layer_role == ""
				and mesh.name.to_lower().ends_with("_body")
			)
		):
			continue
		if mesh.visible and mesh.transparency < 0.01:
			return true
	return false


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
