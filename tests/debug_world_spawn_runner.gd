extends Node
## Rendered regression for the maxed debug-world spawn. It proves the player
## can leave the reserved clearing after the real chunk colliders are built.

const SAVE_PATH := "user://debug_world_spawn_test.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.8).timeout
	if not _main._gameplay_started:
		push_error("Debug spawn runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for _frame in 60:
		await get_tree().physics_frame
	var scalable_contract := await _exercise_scalable_presentation()

	var start := _main.player.global_position
	Input.action_press("move_right", 1.0)
	for _frame in 90:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var finish := _main.player.global_position
	var horizontal_distance := Vector2(
		finish.x - start.x,
		finish.z - start.z
	).length()
	var spawn_clear := true
	for y in range(
		-DebugWorldBuilder.SPAWN_CLEAR_RADIUS,
		DebugWorldBuilder.SPAWN_CLEAR_RADIUS + 1
	):
		for x in range(
			-DebugWorldBuilder.SPAWN_CLEAR_RADIUS,
			DebugWorldBuilder.SPAWN_CLEAR_RADIUS + 1
		):
			var state := _main.core.grid.cell(Vector2i(x, y))
			if state != null and not state.structures.is_empty():
				spawn_clear = false
	var result := {
		"spawn_clear": spawn_clear,
		"start": start,
		"finish": finish,
		"horizontal_distance": horizontal_distance,
		"player_moved": horizontal_distance > 0.75,
		"scalable_presentation": scalable_contract,
		"world": _main.renderer.debug_stats(),
	}
	print("DEBUG_WORLD_SPAWN_RESULT ", JSON.stringify(result))
	var movement_required := (
		"--maxed-world" in OS.get_cmdline_user_args()
		or "--debug-world=maxed" in OS.get_cmdline_user_args()
	)
	get_tree().quit(
		0
		if (
			spawn_clear
			and (horizontal_distance > 0.75 or not movement_required)
			and bool(scalable_contract.get("passed", false))
		)
		else 1
	)


func _exercise_scalable_presentation() -> Dictionary:
	var instance_id := 0
	var harvest_instance_id := 0
	for slot: Dictionary in _main.core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if instance_id == 0:
				instance_id = structure.instance_id
			var definition := _main.core.registries.structure(structure.structure_id)
			if (
				harvest_instance_id == 0
				and definition != null
				and definition.has_capability("harvest_source")
			):
				harvest_instance_id = structure.instance_id
		if instance_id > 0 and harvest_instance_id > 0:
			break
	if instance_id <= 0 or harvest_instance_id <= 0:
		return {"passed": false, "reason": "missing_fixture"}

	_main.renderer.set_hovered_structure(instance_id)
	var hover_ok := (
		_main.renderer.hovered_structure_id() == instance_id
		and not _main.renderer._outlined_meshes.is_empty()
	)
	_main.renderer.clear_structure_hover()
	var falling := _main.renderer.animate_structure_wish_landing(instance_id)
	var fall_started := (
		falling != null
		and _main.renderer.placeable_is_wish_falling(
			"structure", Vector2i.ZERO, 0, instance_id
		)
	)
	await get_tree().create_timer(1.15).timeout
	var fall_settled := not _main.renderer.placeable_is_wish_falling(
		"structure", Vector2i.ZERO, 0, instance_id
	)

	var impact_state := {"finished": false}
	var impact_started := _main.renderer.animate_scalable_structure_harvest_impact(
		harvest_instance_id,
		0.5,
		false,
		"clay_tree",
		func() -> void: impact_state["finished"] = true
	)
	await get_tree().create_timer(0.3).timeout
	var impact_finished := bool(impact_state["finished"])
	var harvest_found := _main.core.grid.find_structure(harvest_instance_id)
	var harvest_status: Dictionary = _main.core.harvesting.status(
		harvest_instance_id
	)
	var harvest_data_before: Dictionary = (
		_main.renderer._scalable_backend.structure_instances.get(
			harvest_instance_id, {}
		) as Dictionary
	)
	var multimesh_before := harvest_data_before.get("multimesh") as MultiMesh
	if not harvest_found.is_empty() and not harvest_status.is_empty():
		var harvest_structure: WorldGrid.StructureState = harvest_found["structure"]
		var runtime: Dictionary = harvest_structure.runtime_state.get(
			HarvestingModule.RUNTIME_KEY, {}
		)
		runtime["state"] = HarvestingModule.STATE_REGROWING
		_main.renderer.refresh_structure_harvest(harvest_instance_id, false)
	var harvest_data_after: Dictionary = (
		_main.renderer._scalable_backend.structure_instances.get(
			harvest_instance_id, {}
		) as Dictionary
	)
	var multimesh_after := harvest_data_after.get("multimesh") as MultiMesh
	var depleted_refresh := (
		multimesh_before != null
		and multimesh_after != null
		and multimesh_after != multimesh_before
	)
	return {
		"passed": hover_ok and fall_started and fall_settled
			and impact_started and impact_finished and depleted_refresh,
		"hover": hover_ok,
		"fall_started": fall_started,
		"fall_settled": fall_settled,
		"harvest_impact": impact_started and impact_finished,
		"harvest_impact_started": impact_started,
		"harvest_impact_finished": impact_finished,
		"depleted_refresh": depleted_refresh,
	}
