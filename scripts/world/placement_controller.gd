class_name PlacementController
extends Node3D
## Build mode: ghost previews, grid snapping, rotation, move-with-cancel,
## undo/redo, and every placement safety rule (adjacency, overlap, world
## connectivity, player standing-cell relocation). The grid snaps pieces;
## the player character never snaps.

signal mode_changed(active: bool)
signal held_changed(held: Dictionary)
signal action_result(ok: bool, message: String, kind: String)

var core: GameCore
var assets: AssetLibrary
var camera_rig: CameraRig
var player: PlayerController
var effects: EffectsManager

var active := false
var held: Dictionary = {}      # {kind: tile|structure|deed, id, rotation, moving: {...}|null}
var _ghost: Node3D
var _indicator: MeshInstance3D
var _hover_cell := Vector2i(9999, 9999)
var _hover_elevation := 0
var _hover_valid := false
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _pointer_down := false
var _pointer_dragging := false
var _pointer_press_position := Vector2.ZERO
var _picked_on_pointer_press := false

var _ghost_ok_material: StandardMaterial3D
var _ghost_bad_material: StandardMaterial3D


func setup(game_core: GameCore, asset_library: AssetLibrary, rig: CameraRig, player_controller: PlayerController, effects_manager: EffectsManager) -> void:
	core = game_core
	assets = asset_library
	camera_rig = rig
	player = player_controller
	effects = effects_manager
	core.before_save.connect(prepare_for_save)
	_ghost_ok_material = _ghost_material(Color(0.65, 0.85, 0.55, 0.55))
	_ghost_bad_material = _ghost_material(Color(0.85, 0.5, 0.42, 0.5))
	_indicator = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(core.grid.tile_size * 0.96, core.grid.tile_size * 0.96)
	_indicator.mesh = plane
	_indicator.visible = false
	add_child(_indicator)


func _ghost_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


# ------------------------------------------------------------------ mode

func toggle() -> void:
	set_active(not active)


func set_active(enabled: bool) -> void:
	if active == enabled:
		return
	active = enabled
	if not active:
		_cancel_held(true)
	camera_rig.set_build_mode(active)
	player.set_state(PlayerController.State.BUILDING if active else PlayerController.State.FREE)
	mode_changed.emit(active)


## HUD hands over a piece from stock (or a packed deed).
func hold_new(kind: String, id: String) -> void:
	if not active:
		set_active(true)
	_cancel_held(true)
	held = {"kind": kind, "id": id, "rotation": 0, "moving": null}
	_build_ghost()
	held_changed.emit(held)


func rotate_held() -> void:
	if held.is_empty():
		return
	held["rotation"] = (int(held["rotation"]) + 1) % 4
	action_result.emit(true, "", "rotate")


func _build_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if held.is_empty():
		return
	var asset_id := ""
	match held["kind"]:
		"tile":
			var tile_def := core.registries.tile(held["id"])
			if tile_def == null:
				action_result.emit(false, "That tile is no longer available.", "invalid")
				return
			asset_id = tile_def.asset_id
		"structure":
			var structure_def := core.registries.structure(held["id"])
			if structure_def == null:
				action_result.emit(false, "That decoration is no longer available.", "invalid")
				return
			asset_id = structure_def.asset_id
		"deed":
			var landmark_def := core.registries.landmark(held["id"])
			if landmark_def == null:
				action_result.emit(false, "That landmark is no longer available.", "invalid")
				return
			asset_id = landmark_def.asset_id
	_ghost = assets.instantiate(asset_id)
	add_child(_ghost)
	_set_ghost_material(_ghost_ok_material)


func _set_ghost_material(mat: StandardMaterial3D) -> void:
	if _ghost == null:
		return
	for child in _ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, mat)


# ------------------------------------------------------------------ per-frame preview

func _process(delta: float) -> void:
	if not active or held.is_empty():
		_indicator.visible = false
		if _ghost != null:
			_ghost.visible = false
		return
	_update_hover_target()
	_hover_valid = _validate(_hover_cell, _hover_elevation)
	var world := core.grid.cell_to_world(_hover_cell, _hover_elevation)
	if _ghost != null:
		var was_visible := _ghost.visible
		_ghost.visible = true
		var target_position := world + Vector3(
			0,
			0.1 + sin(Time.get_ticks_msec() * 0.006) * 0.025,
			0
		)
		if held["kind"] == "structure":
			var socket := _target_socket(_hover_cell, _hover_elevation)
			if socket >= 0:
				target_position += core.grid.socket_offset(socket)
		if was_visible:
			_ghost.position = _ghost.position.lerp(target_position, 1.0 - exp(-delta * 20.0))
		else:
			_ghost.position = target_position
		_ghost.rotation.y = lerp_angle(
			_ghost.rotation.y,
			int(held["rotation"]) * PI * 0.5,
			1.0 - exp(-delta * 22.0)
		)
		_set_ghost_material(_ghost_ok_material if _hover_valid else _ghost_bad_material)
	# Color-independent validity: solid square for valid, rotated (diamond) for
	# invalid — readable without red/green vision.
	_indicator.visible = true
	_indicator.position = world + Vector3(0, 0.03, 0)
	_indicator.rotation.y = 0.0 if _hover_valid else PI * 0.25
	_indicator.material_override = _ghost_ok_material if _hover_valid else _ghost_bad_material


func _slot_under_mouse() -> Dictionary:
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var camera := camera_rig.camera
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return {"coord": _hover_cell, "elevation": -1}
	for elevation in range(core.grid.highest_elevation(), -1, -1):
		var plane_y := core.grid.cell_to_world(Vector2i.ZERO, elevation).y
		var distance := (plane_y - origin.y) / direction.y
		if distance < 0.0:
			continue
		var point := origin + direction * distance
		var coord := core.grid.world_to_cell(point)
		if core.grid.has_cell_at(coord, elevation):
			return {"coord": coord, "elevation": elevation}
	var ground_distance := -origin.y / direction.y
	var ground_point := origin + direction * ground_distance
	return {"coord": core.grid.world_to_cell(ground_point), "elevation": -1}


func _cell_under_mouse() -> Vector2i:
	return _slot_under_mouse()["coord"]


func _update_hover_target() -> void:
	var hit := _slot_under_mouse()
	_hover_cell = hit["coord"]
	var support_elevation := int(hit["elevation"])
	match held.get("kind", ""):
		"tile":
			_hover_elevation = support_elevation + 1 if support_elevation >= 0 else 0
		"structure":
			_hover_elevation = maxi(0, support_elevation)
		_:
			_hover_elevation = 0


func _validate(cell: Vector2i, elevation: int = 0) -> bool:
	match held.get("kind", ""):
		"tile":
			if elevation > 0:
				if player.current_cell() == cell:
					return false
				return core.grid.can_place_tile_at(cell, elevation, held["id"])
			if held["moving"] != null and int(held["moving"].get("elevation", 0)) == 0:
				var from: Vector2i = held["moving"]["coord"]
				return not core.grid.has_cell(cell) and _adjacent_excluding(cell, from)
			return core.grid.can_place_tile_at(cell, 0, held["id"])
		"structure":
			return _target_socket(cell, elevation) >= 0
		"deed":
			if elevation != 0:
				return false
			var def := core.registries.landmark(held["id"])
			var adjacent := false
			for offset in def.footprint:
				var coord: Vector2i = cell + offset
				if core.grid.has_cell(coord):
					return false
				if core.grid.is_adjacent_to_world(coord):
					adjacent = true
			return adjacent
	return false


func _adjacent_excluding(cell: Vector2i, excluded: Vector2i) -> bool:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor: Vector2i = cell + offset
		if neighbor != excluded and core.grid.has_cell(neighbor):
			return true
	return false


func _target_socket(cell: Vector2i, elevation: int = 0) -> int:
	if not core.grid.has_cell_at(cell, elevation):
		return -1
	var def := core.registries.structure(held["id"])
	if not core.grid.can_place_structure_at(cell, elevation, def.id):
		return -1
	return core.grid.free_socket(cell, def.socket_type, elevation)


# ------------------------------------------------------------------ clicks

## Programmatic placement at an explicit cell — used by acceptance tests and
## available for future gamepad cursor support. Same path as a mouse click.
func try_place_at(cell: Vector2i) -> bool:
	_hover_cell = cell
	match held.get("kind", ""):
		"tile":
			_hover_elevation = core.grid.top_elevation(cell) + 1 if core.grid.has_cell(cell) else 0
		"structure":
			_hover_elevation = maxi(0, core.grid.top_elevation(cell))
		_:
			_hover_elevation = 0
	_hover_valid = _validate(cell, _hover_elevation)
	if not _hover_valid:
		return false
	click()
	return true


func try_place_at_layer(cell: Vector2i, elevation: int) -> bool:
	_hover_cell = cell
	_hover_elevation = elevation
	_hover_valid = _validate(cell, elevation)
	if not _hover_valid:
		return false
	click()
	return true


func pick_up_at(cell: Vector2i, elevation: int = -1) -> void:
	var target_elevation := core.grid.top_elevation(cell) if elevation < 0 else elevation
	_pick_up_from(cell, target_elevation)


func pointer_press(screen_position: Vector2) -> void:
	_pointer_down = true
	_pointer_dragging = false
	_pointer_press_position = screen_position
	_picked_on_pointer_press = false
	if held.is_empty():
		_try_pick_up()
		_picked_on_pointer_press = not held.is_empty()
	else:
		click()


func pointer_motion(screen_position: Vector2) -> void:
	if (
		_pointer_down
		and _picked_on_pointer_press
		and screen_position.distance_to(_pointer_press_position) >= 8.0
	):
		_pointer_dragging = true


func pointer_release(_screen_position: Vector2) -> void:
	if _pointer_down and _pointer_dragging and _picked_on_pointer_press and not held.is_empty():
		if _hover_valid:
			click()
		else:
			action_result.emit(false, _invalid_message(), "invalid")
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false


func click() -> void:
	if not active:
		return
	if held.is_empty():
		_try_pick_up()
		return
	if not _hover_valid:
		action_result.emit(false, _invalid_message(), "invalid")
		return
	match held["kind"]:
		"tile":
			_place_tile()
		"structure":
			_place_structure()
		"deed":
			_place_deed()


func _invalid_message() -> String:
	if held.get("kind", "") == "tile" and _hover_elevation > 0:
		return "That surface can't support another land tile — use a flat, clear block."
	if held.get("kind", "") == "structure":
		return "That object needs a clear supported spot."
	return "It can't go there — land must touch the world edge-to-edge."


func _place_tile() -> void:
	var tile_id: String = held["id"]
	var rotation_q: int = held["rotation"]
	if held["moving"] != null:
		var from: Vector2i = held["moving"]["coord"]
		var from_elevation := int(held["moving"].get("elevation", 0))
		var original: WorldGrid.CellState = held["moving"]["state"]
		var from_rotation := original.rotation
		original.rotation = rotation_q
		core.grid.restore_cell_at(_hover_cell, _hover_elevation, original)
		_push_undo({
			"type": "move_tile",
			"from": from,
			"from_elevation": from_elevation,
			"to": _hover_cell,
			"to_elevation": _hover_elevation,
			"from_rotation": from_rotation,
			"to_rotation": rotation_q,
		})
		held = {}
		held_changed.emit(held)
		_build_ghost()
		core.autosave_paused = false
		core.autosave_soon()
	else:
		if not core.place_tile_from_stock(_hover_cell, tile_id, rotation_q, _hover_elevation):
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		_push_undo({
			"type": "place_tile",
			"coord": _hover_cell,
			"elevation": _hover_elevation,
			"tile_id": tile_id,
			"rotation": rotation_q,
		})
		var remaining := core.stock.tile_count(tile_id)
		if remaining <= 0:
			held = {}
			held_changed.emit(held)
			_build_ghost()
	var def := core.registries.tile(tile_id)
	effects.placement_poof(
		core.grid.cell_to_world(_hover_cell, _hover_elevation),
		def.placement_sound
	)
	_settle_animation(_hover_cell, _hover_elevation)
	action_result.emit(
		true,
		"Stacked at level %d." % _hover_elevation if _hover_elevation > 0 else "",
		"place_" + def.placement_sound
	)


func _place_structure() -> void:
	var structure_id: String = held["id"]
	var socket := _target_socket(_hover_cell, _hover_elevation)
	if held["moving"] != null:
		var s := core.grid.add_structure(
			_hover_cell,
			structure_id,
			socket,
			held["rotation"],
			_hover_elevation
		)
		s.instance_id = int(held["moving"]["iid"])
		_push_undo({
			"type": "move_structure",
			"iid": s.instance_id,
			"structure_id": structure_id,
			"from": held["moving"],
			"to": {
				"coord": _hover_cell,
				"elevation": _hover_elevation,
				"socket": socket,
				"rot": held["rotation"],
			},
		})
		held = {}
		core.autosave_paused = false
	else:
		if not core.stock.take_structure(structure_id):
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		var s := core.grid.add_structure(
			_hover_cell,
			structure_id,
			socket,
			held["rotation"],
			_hover_elevation
		)
		core.collection.record_placed("structures", structure_id)
		_push_undo({
			"type": "place_structure",
			"coord": _hover_cell,
			"elevation": _hover_elevation,
			"iid": s.instance_id,
			"structure_id": structure_id,
		})
		if core.stock.structure_count(structure_id) <= 0:
			held = {}
	held_changed.emit(held)
	_build_ghost()
	var def := core.registries.structure(structure_id)
	effects.placement_poof(
		core.grid.cell_to_world(_hover_cell, _hover_elevation) + core.grid.socket_offset(socket),
		"grass" if def.placement_sound == "grass" else "stone"
	)
	_settle_animation(_hover_cell, _hover_elevation)
	core.autosave_soon()
	action_result.emit(true, "", "place_" + def.placement_sound)


func _place_deed() -> void:
	if core.landmarks.place_deed(held["id"], _hover_cell):
		held = {}
		held_changed.emit(held)
		_build_ghost()
		core.autosave_soon()
		action_result.emit(true, "The landmark settles into its new home.", "place_stone")
	else:
		action_result.emit(false, "The landmark needs clear ground beside your world.", "invalid")


## Pick up an existing structure (preferred) or a movable tile under the cursor.
func _try_pick_up() -> void:
	var hit := _slot_under_mouse()
	var elevation := int(hit["elevation"])
	if elevation >= 0:
		_pick_up_from(hit["coord"], elevation)


func _pick_up_from(cell: Vector2i, elevation: int) -> void:
	var state := core.grid.cell_at(cell, elevation)
	if state == null:
		return
	if not state.structures.is_empty():
		var s: WorldGrid.StructureState = state.structures.back()
		core.grid.remove_structure(cell, s.instance_id, elevation)
		core.autosave_paused = true
		held = {
			"kind": "structure",
			"id": s.structure_id,
			"rotation": s.rotation,
			"moving": {
				"coord": cell,
				"elevation": elevation,
				"socket": s.socket_index,
				"rot": s.rotation,
				"iid": s.instance_id,
			},
		}
		_build_ghost()
		held_changed.emit(held)
		action_result.emit(true, "Click to move it, Esc to put it back, X to store it.", "pickup")
		return
	_try_pick_up_tile(cell, elevation, state)


func _try_pick_up_tile(cell: Vector2i, elevation: int, state: WorldGrid.CellState) -> void:
	if elevation == 0 and state.starter:
		action_result.emit(false, "The first nine tiles are the heart of your world — they stay (and can be upgraded later).", "invalid")
		return
	if elevation == 0 and state.landmark_id != "":
		action_result.emit(false, "Reclaimed landmarks move by packing them from their pedestal.", "invalid")
		return
	if core.grid.top_elevation(cell) > elevation:
		action_result.emit(false, "Move the upper blocks first.", "invalid")
		return
	if elevation == 0 and not core.grid.connected_without(cell, core.grid.home_cell):
		action_result.emit(false, "Removing that tile would split your world in two.", "invalid")
		return
	if elevation == 0 and player.current_cell() == cell:
		var refuge := core.grid.nearest_walkable(cell, cell)
		if refuge == cell:
			action_result.emit(false, "There's nowhere safe to stand — place more land first.", "invalid")
			return
		player.position = core.grid.cell_to_world(refuge)
	var removed := core.grid.remove_tile_at(cell, elevation)
	if removed == null:
		return
	core.autosave_paused = true
	held = {
		"kind": "tile",
		"id": removed.tile_id,
		"rotation": removed.rotation,
		"moving": {
			"coord": cell,
			"elevation": elevation,
			"state": removed,
		},
	}
	_build_ghost()
	held_changed.emit(held)
	action_result.emit(
		true,
		"Drag or click it onto a clear edge or flat supporting block. Esc restores it.",
		"pickup"
	)


## X while holding a moved piece stores it instead of replacing it.
func store_held() -> void:
	if held.is_empty() or held["moving"] == null:
		return
	match held["kind"]:
		"structure":
			core.stock.add_structure(held["id"])
			_push_undo({
				"type": "store_structure",
				"structure_id": held["id"],
				"from": held["moving"],
			})
		"tile":
			var original: WorldGrid.CellState = held["moving"]["state"]
			core.stock.add_tile(held["id"])
			_push_undo({
				"type": "store_tile",
				"tile_id": held["id"],
				"from": held["moving"],
				"rotation": original.rotation,
			})
		_:
			return
	held = {}
	core.autosave_paused = false
	held_changed.emit(held)
	_build_ghost()
	core.autosave_soon()
	action_result.emit(true, "Stored.", "store")


func cancel_click() -> void:
	if not held.is_empty():
		_cancel_held(true)
	else:
		set_active(false)


## A save is an explicit transaction boundary. A piece being moved is restored
## before serialization so no save can capture it in the transient held state.
func prepare_for_save() -> void:
	if not held.is_empty() and held.get("moving") != null:
		_cancel_held(true)


## Cancelling a move restores the piece to its original position — nothing is
## ever lost to experimentation.
func _cancel_held(restore: bool) -> void:
	if held.is_empty():
		core.autosave_paused = false
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		return
	if restore and held["moving"] != null:
		match held["kind"]:
			"tile":
				var original: WorldGrid.CellState = held["moving"]["state"]
				var coord: Vector2i = held["moving"]["coord"]
				var elevation := int(held["moving"].get("elevation", 0))
				core.grid.restore_cell_at(coord, elevation, original)
			"structure":
				var m: Dictionary = held["moving"]
				var s := core.grid.add_structure(
					m["coord"],
					held["id"],
					m["socket"],
					m["rot"],
					int(m.get("elevation", 0))
				)
				s.instance_id = m["iid"]
	elif restore and held["moving"] == null and held["kind"] == "tile":
		pass  # piece stays in stock — nothing was consumed until placement
	held = {}
	core.autosave_paused = false
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false
	held_changed.emit(held)
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


# ------------------------------------------------------------------ undo / redo

func _push_undo(entry: Dictionary) -> void:
	_undo_stack.append(entry)
	if _undo_stack.size() > 40:
		_undo_stack.pop_front()
	_redo_stack.clear()


func undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	if _apply(entry, true):
		_redo_stack.append(entry)
		action_result.emit(true, "", "undo")


func redo() -> void:
	if _redo_stack.is_empty():
		return
	var entry: Dictionary = _redo_stack.pop_back()
	if _apply(entry, false):
		_undo_stack.append(entry)
		action_result.emit(true, "", "redo")


func _apply(entry: Dictionary, reverse: bool) -> bool:
	match entry["type"]:
		"place_tile":
			var elevation := int(entry.get("elevation", 0))
			if reverse:
				var coord: Vector2i = entry["coord"]
				if elevation == 0 and player.current_cell() == coord:
					player.position = core.grid.cell_to_world(core.grid.nearest_walkable(coord, coord))
				if elevation == 0 and not core.grid.connected_without(coord, core.grid.home_cell):
					return false
				var removed := core.grid.remove_tile_at(coord, elevation)
				if removed != null:
					core.stock.add_tile(removed.tile_id)
				return removed != null
			return core.place_tile_from_stock(
				entry["coord"],
				entry["tile_id"],
				int(entry.get("rotation", 0)),
				elevation
			)
		"place_structure":
			var structure_elevation := int(entry.get("elevation", 0))
			if reverse:
				var removed_s := core.grid.remove_structure(
					entry["coord"],
					entry["iid"],
					structure_elevation
				)
				if removed_s != null:
					core.stock.add_structure(removed_s.structure_id)
				return removed_s != null
			if core.stock.take_structure(entry["structure_id"]):
				var structure_def := core.registries.structure(entry["structure_id"])
				if structure_def == null:
					core.stock.add_structure(entry["structure_id"])
					return false
				var socket := core.grid.free_socket(
					entry["coord"],
					structure_def.socket_type,
					structure_elevation
				)
				if socket >= 0:
					var s := core.grid.add_structure(
						entry["coord"],
						entry["structure_id"],
						socket,
						0,
						structure_elevation
					)
					entry["iid"] = s.instance_id
					return true
				core.stock.add_structure(entry["structure_id"])
			return false
		"move_tile":
			var from: Vector2i = entry["to"] if reverse else entry["from"]
			var to: Vector2i = entry["from"] if reverse else entry["to"]
			var from_elevation := (
				int(entry.get("to_elevation", 0))
				if reverse
				else int(entry.get("from_elevation", 0))
			)
			var to_elevation := (
				int(entry.get("from_elevation", 0))
				if reverse
				else int(entry.get("to_elevation", 0))
			)
			if not core.grid.move_tile_at(from, from_elevation, to, to_elevation):
				return false
			var moved_state := core.grid.cell_at(to, to_elevation)
			moved_state.rotation = int(
				entry.get("from_rotation", moved_state.rotation)
				if reverse
				else entry.get("to_rotation", moved_state.rotation)
			)
			core.grid.slot_changed.emit(to, to_elevation)
			return true
		"move_structure":
			var src: Dictionary = entry["to"] if reverse else entry["from"]
			var dst: Dictionary = entry["from"] if reverse else entry["to"]
			var found := core.grid.find_structure(entry["iid"])
			if found.is_empty():
				return false
			core.grid.remove_structure(
				found["coord"],
				entry["iid"],
				int(found.get("elevation", 0))
			)
			var s := core.grid.add_structure(
				dst["coord"],
				_structure_id_of(entry),
				dst.get("socket", 0),
				dst.get("rot", 0),
				int(dst.get("elevation", 0))
			)
			s.instance_id = entry["iid"]
			return true
		"store_structure":
			var m: Dictionary = entry["from"]
			if reverse:
				if core.stock.take_structure(entry["structure_id"]):
					var restored := core.grid.add_structure(
						m["coord"],
						entry["structure_id"],
						m["socket"],
						m["rot"],
						int(m.get("elevation", 0))
					)
					entry["from"]["iid"] = restored.instance_id
					return true
				return false
			var removed_again := core.grid.remove_structure(
				m["coord"],
				int(m.get("iid", -1)),
				int(m.get("elevation", 0))
			)
			if removed_again != null:
				core.stock.add_structure(entry["structure_id"])
				return true
			return false
		"store_tile":
			var tile_from: Dictionary = entry["from"]
			var tile_coord: Vector2i = tile_from["coord"]
			var tile_elevation := int(tile_from.get("elevation", 0))
			if reverse:
				if not core.stock.take_tile(entry["tile_id"]):
					return false
				var original: WorldGrid.CellState = tile_from["state"]
				original.rotation = int(entry.get("rotation", original.rotation))
				if core.grid.has_cell_at(tile_coord, tile_elevation):
					core.stock.add_tile(entry["tile_id"])
					return false
				core.grid.restore_cell_at(tile_coord, tile_elevation, original)
				return true
			var removed_tile := core.grid.remove_tile_at(tile_coord, tile_elevation)
			if removed_tile == null:
				return false
			entry["from"]["state"] = removed_tile
			core.stock.add_tile(entry["tile_id"])
			return true
	return false


func _structure_id_of(entry: Dictionary) -> String:
	return entry.get("structure_id", held.get("id", ""))


func _settle_animation(coord: Vector2i, elevation: int = 0) -> void:
	var renderer := get_parent().find_child("WorldRenderer", false, false) as WorldRenderer
	if renderer == null:
		return
	var node := renderer.tile_node(coord, elevation)
	if node == null:
		return
	var target_position := core.grid.cell_to_world(coord, elevation)
	node.position = target_position + Vector3(0, 0.5, 0)
	node.scale = Vector3(0.94, 0.94, 0.94)
	var tween := node.create_tween()
	tween.set_parallel()
	tween.tween_property(node, "position", target_position, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
