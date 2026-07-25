extends Node
class_name PlacementController

signal hold_changed(active: bool, definition_id: StringName)
signal preview_changed(valid: bool, reason: String)
signal placement_completed(definition_id: StringName, source: StringName)
signal item_stored(definition_id: StringName)
signal item_recycled(definition_id: StringName, value: int)
signal action_feedback(message: String, positive: bool)
signal undo_state_changed(can_undo: bool, can_redo: bool)

const ItemScene := preload("res://scenes/build_item.tscn")

var grid: GridManager
var data: GameData
var renderer: GridRenderer
var camera_rig: TilegardenCameraRig
var world_root: Node3D
var storage: StorageManager
var economy: EconomyManager

var held_definition_id := &""
var held_source := &""
var held_instance_id := ""
var held_original_state: Dictionary = {}
var held_original_ground := Vector3i.ZERO
var rotation_quarters := 0
var hover_coord := Vector3i.ZERO
var preview_valid := false
var preview_reason := ""
var ghost: BuildItem
var _command_before: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _rare_recycle_armed := false


func setup(
		grid_manager: GridManager,
		game_data: GameData,
		grid_renderer: GridRenderer,
		rig: TilegardenCameraRig,
		root: Node3D,
		storage_manager: StorageManager,
		economy_manager: EconomyManager
	) -> void:
	grid = grid_manager
	data = game_data
	renderer = grid_renderer
	camera_rig = rig
	world_root = root
	storage = storage_manager
	economy = economy_manager


func is_holding() -> bool:
	return held_definition_id != &""


func begin_reward(definition_id: StringName) -> bool:
	return _begin_hold(definition_id, &"reward")


func begin_growth(definition_id: StringName) -> bool:
	return _begin_hold(definition_id, &"growth")


func begin_from_storage(definition_id: StringName) -> bool:
	if not storage.take(definition_id, 1):
		action_feedback.emit("That item is no longer in storage.", false)
		return false
	if not _begin_hold(definition_id, &"storage"):
		storage.add(definition_id, 1)
		return false
	return true


func begin_move(item: BuildItem) -> bool:
	if item == null or is_holding():
		return false
	var definition := item.definition
	if definition == null:
		return false
	_command_before = grid.snapshot()
	if definition.is_ground():
		var removable := grid.can_remove_ground(item.grid_coord)
		if not bool(removable.valid):
			action_feedback.emit(str(removable.reason), false)
			return false
		held_original_ground = item.grid_coord
		grid.remove_ground(item.grid_coord)
		held_source = &"world_ground"
		held_definition_id = definition.id
		rotation_quarters = item.rotation_quarters
	else:
		held_original_state = grid.remove_prop(item.instance_id)
		if held_original_state.is_empty():
			return false
		held_instance_id = item.instance_id
		held_source = &"world_prop"
		held_definition_id = definition.id
		rotation_quarters = int(held_original_state.get("rotation", 0))
	_create_ghost()
	hold_changed.emit(true, held_definition_id)
	return true


func _begin_hold(definition_id: StringName, source: StringName) -> bool:
	if is_holding() or data.item(definition_id) == null:
		return false
	_command_before = grid.snapshot()
	held_definition_id = definition_id
	held_source = StringName(source)
	held_instance_id = ""
	held_original_state.clear()
	rotation_quarters = 0
	_create_ghost()
	hold_changed.emit(true, held_definition_id)
	return true


func _create_ghost() -> void:
	if ghost != null:
		ghost.queue_free()
	var definition := data.item(held_definition_id)
	ghost = ItemScene.instantiate() as BuildItem
	world_root.add_child(ghost)
	ghost.setup(definition, "preview", Vector3i.ZERO, rotation_quarters, grid.tile_size, true)
	update_preview(get_viewport().get_mouse_position())


func update_preview(screen_position: Vector2) -> void:
	if not is_holding() or ghost == null:
		return
	var definition := data.item(held_definition_id)
	var world := camera_rig.screen_to_ground(screen_position)
	var base := grid.coord_from_world(world)
	if definition.is_ground():
		hover_coord = Vector3i(base.x, 0, base.z)
		var ground_check := grid.can_place_ground(hover_coord)
		preview_valid = bool(ground_check.valid)
		preview_reason = str(ground_check.reason)
	else:
		var desired_layer := 1
		var hit_item := pick_build_item_at(screen_position)
		if hit_item != null and not hit_item.definition.is_ground() and definition.stackability:
			desired_layer = hit_item.grid_coord.y + 1
			base.x = hit_item.grid_coord.x
			base.z = hit_item.grid_coord.z
		hover_coord = Vector3i(base.x, desired_layer, base.z)
		var prop_check := grid.can_place_prop(definition, hover_coord, rotation_quarters, held_instance_id)
		preview_valid = bool(prop_check.valid)
		preview_reason = str(prop_check.reason)
	ghost.grid_coord = hover_coord
	ghost.position = grid.world_position(hover_coord)
	ghost.position.y += 0.10
	ghost.set_preview_valid(preview_valid)
	preview_changed.emit(preview_valid, preview_reason)


func rotate_held(direction: int = 1) -> void:
	if not is_holding() or ghost == null:
		return
	rotation_quarters = posmod(rotation_quarters + direction, 4)
	ghost.rotation_quarters = rotation_quarters
	var target_rotation := float(rotation_quarters) * PI * 0.5
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "rotation:y", target_rotation, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	update_preview(get_viewport().get_mouse_position())


func confirm() -> bool:
	if not is_holding():
		return false
	if not preview_valid:
		action_feedback.emit(preview_reason if not preview_reason.is_empty() else "That cannot be placed there.", false)
		return false
	var definition := data.item(held_definition_id)
	var placed := false
	var placed_instance := ""
	if definition.is_ground():
		placed = grid.place_ground(held_definition_id, hover_coord)
	else:
		placed_instance = grid.place_prop(held_definition_id, hover_coord, rotation_quarters, held_instance_id)
		placed = not placed_instance.is_empty()
	if not placed:
		action_feedback.emit("The garden changed before that item could settle.", false)
		update_preview(get_viewport().get_mouse_position())
		return false
	_commit_command(_command_before, grid.snapshot())
	var source := held_source
	var definition_id := held_definition_id
	_clear_hold(false)
	var item := renderer.node_for_ground(hover_coord) if definition.is_ground() else renderer.node_for_instance(placed_instance)
	if item != null:
		item.animate_placed()
	placement_completed.emit(definition_id, source)
	action_feedback.emit("%s settled into the garden." % definition.display_name, true)
	return true


func cancel() -> void:
	if not is_holding():
		return
	match held_source:
		&"world_prop":
			grid.restore_prop(held_original_state)
		&"world_ground":
			grid.add_ground_unchecked(held_definition_id, held_original_ground)
			grid.grid_changed.emit()
		&"storage":
			storage.add(held_definition_id, 1)
		_:
			pass
	action_feedback.emit("Placement cancelled.", true)
	_clear_hold(false)


func store_current() -> bool:
	if not is_holding():
		return false
	var id := held_definition_id
	storage.add(id, 1)
	if held_source == &"world_prop" or held_source == &"world_ground":
		_commit_command(_command_before, grid.snapshot())
	item_stored.emit(id)
	action_feedback.emit("%s tucked safely into storage." % data.item(id).display_name, true)
	_clear_hold(false)
	return true


func recycle_current() -> bool:
	if not is_holding():
		return false
	var definition := data.item(held_definition_id)
	if definition.rarity == &"rare" and not _rare_recycle_armed:
		_rare_recycle_armed = true
		action_feedback.emit("Rare piece — choose Sell once more to confirm.", false)
		return false
	var id := held_definition_id
	var value := definition.recycle_value
	economy.sell(value)
	if held_source == &"world_prop" or held_source == &"world_ground":
		_commit_command(_command_before, grid.snapshot())
	item_recycled.emit(id, value)
	action_feedback.emit("%s added %d value to the coin press." % [definition.display_name, value], true)
	_clear_hold(false)
	return true


func held_snapshot() -> Dictionary:
	if not is_holding():
		return {}
	return {
		"definition_id": String(held_definition_id),
		"source": String(held_source),
		"instance_id": held_instance_id,
		"original_state": held_original_state.duplicate(true),
		"original_ground": [held_original_ground.x, held_original_ground.y, held_original_ground.z],
		"rotation": rotation_quarters,
		"command_before": _command_before.duplicate(true),
	}


func restore_held(state: Dictionary) -> bool:
	if state.is_empty() or is_holding():
		return false
	var id := StringName(str(state.get("definition_id", "")))
	if data.item(id) == null:
		return false
	held_definition_id = id
	held_source = StringName(str(state.get("source", "reward")))
	held_instance_id = str(state.get("instance_id", ""))
	held_original_state = (state.get("original_state", {}) as Dictionary).duplicate(true)
	held_original_ground = GridManager.array_to_coord(state.get("original_ground", [0, 0, 0]))
	rotation_quarters = int(state.get("rotation", 0))
	_command_before = (state.get("command_before", grid.snapshot()) as Dictionary).duplicate(true)
	_create_ghost()
	hold_changed.emit(true, held_definition_id)
	return true


func undo() -> bool:
	if is_holding():
		cancel()
	if _undo_stack.is_empty():
		action_feedback.emit("Nothing to undo.", false)
		return false
	var command: Dictionary = _undo_stack.pop_back()
	grid.restore_snapshot(command.before)
	_redo_stack.append(command)
	undo_state_changed.emit(not _undo_stack.is_empty(), not _redo_stack.is_empty())
	action_feedback.emit("Garden change undone.", true)
	return true


func redo() -> bool:
	if is_holding():
		cancel()
	if _redo_stack.is_empty():
		action_feedback.emit("Nothing to redo.", false)
		return false
	var command: Dictionary = _redo_stack.pop_back()
	grid.restore_snapshot(command.after)
	_undo_stack.append(command)
	undo_state_changed.emit(not _undo_stack.is_empty(), not _redo_stack.is_empty())
	action_feedback.emit("Garden change restored.", true)
	return true


func pick_build_item_at(screen_position: Vector2) -> BuildItem:
	if camera_rig.camera == null:
		return null
	var origin := camera_rig.camera.project_ray_origin(screen_position)
	var end := origin + camera_rig.camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera_rig.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.get("collider") as Area3D
	if collider != null and collider.has_meta("build_item"):
		return collider.get_meta("build_item") as BuildItem
	return null


func _commit_command(before: Dictionary, after: Dictionary) -> void:
	_undo_stack.append({"before": before.duplicate(true), "after": after.duplicate(true)})
	if _undo_stack.size() > 40:
		_undo_stack.pop_front()
	_redo_stack.clear()
	undo_state_changed.emit(true, false)


func _clear_hold(restore_storage := false) -> void:
	if restore_storage and held_source == &"storage":
		storage.add(held_definition_id, 1)
	if ghost != null:
		ghost.queue_free()
	ghost = null
	held_definition_id = &""
	held_source = &""
	held_instance_id = ""
	held_original_state.clear()
	preview_valid = false
	preview_reason = ""
	_rare_recycle_armed = false
	hold_changed.emit(false, &"")
