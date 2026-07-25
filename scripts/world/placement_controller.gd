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
var _hover_valid := false
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

var _ghost_ok_material: StandardMaterial3D
var _ghost_bad_material: StandardMaterial3D


func setup(game_core: GameCore, asset_library: AssetLibrary, rig: CameraRig, player_controller: PlayerController, effects_manager: EffectsManager) -> void:
	core = game_core
	assets = asset_library
	camera_rig = rig
	player = player_controller
	effects = effects_manager
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
			asset_id = core.registries.tile(held["id"]).asset_id
		"structure":
			asset_id = core.registries.structure(held["id"]).asset_id
		"deed":
			asset_id = core.registries.landmark(held["id"]).asset_id
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

func _process(_delta: float) -> void:
	if not active or held.is_empty():
		_indicator.visible = false
		if _ghost != null:
			_ghost.visible = false
		return
	var cell := _cell_under_mouse()
	_hover_cell = cell
	_hover_valid = _validate(cell)
	var world := core.grid.cell_to_world(cell)
	if _ghost != null:
		_ghost.visible = true
		_ghost.position = world + Vector3(0, 0.06, 0)
		_ghost.rotation.y = int(held["rotation"]) * PI * 0.5
		if held["kind"] == "structure":
			var socket := _target_socket(cell)
			if socket >= 0:
				_ghost.position = world + core.grid.socket_offset(socket) + Vector3(0, 0.06, 0)
		_set_ghost_material(_ghost_ok_material if _hover_valid else _ghost_bad_material)
	# Color-independent validity: solid square for valid, rotated (diamond) for
	# invalid — readable without red/green vision.
	_indicator.visible = true
	_indicator.position = world + Vector3(0, 0.03, 0)
	_indicator.rotation.y = 0.0 if _hover_valid else PI * 0.25
	_indicator.material_override = _ghost_ok_material if _hover_valid else _ghost_bad_material


func _cell_under_mouse() -> Vector2i:
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var camera := camera_rig.camera
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return _hover_cell
	var t := -origin.y / direction.y
	var point := origin + direction * t
	return core.grid.world_to_cell(point)


func _validate(cell: Vector2i) -> bool:
	match held.get("kind", ""):
		"tile":
			if held["moving"] != null:
				var from: Vector2i = held["moving"]["coord"]
				return not core.grid.has_cell(cell) and _adjacent_excluding(cell, from)
			return core.grid.can_place_tile(cell)
		"structure":
			return _target_socket(cell) >= 0
		"deed":
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


func _target_socket(cell: Vector2i) -> int:
	if not core.grid.has_cell(cell):
		return -1
	var def := core.registries.structure(held["id"])
	return core.grid.free_socket(cell, def.socket_type)


# ------------------------------------------------------------------ clicks

## Programmatic placement at an explicit cell — used by acceptance tests and
## available for future gamepad cursor support. Same path as a mouse click.
func try_place_at(cell: Vector2i) -> bool:
	_hover_cell = cell
	_hover_valid = _validate(cell)
	if not _hover_valid:
		return false
	click()
	return true


func pick_up_at(cell: Vector2i) -> void:
	_pick_up_from(cell)


func click() -> void:
	if not active:
		return
	if held.is_empty():
		_try_pick_up()
		return
	if not _hover_valid:
		action_result.emit(false, "It can't go there — land must touch the world edge-to-edge.", "invalid")
		return
	match held["kind"]:
		"tile":
			_place_tile()
		"structure":
			_place_structure()
		"deed":
			_place_deed()


func _place_tile() -> void:
	var tile_id: String = held["id"]
	var rotation_q: int = held["rotation"]
	if held["moving"] != null:
		var from: Vector2i = held["moving"]["coord"]
		core.grid.place_tile(_hover_cell, tile_id, rotation_q)
		var moved := core.grid.cell(_hover_cell)
		var original: WorldGrid.CellState = held["moving"]["state"]
		moved.structures = original.structures
		moved.anchor_actions_done = original.anchor_actions_done
		moved.anchor_resting = original.anchor_resting
		moved.anchor_regen_left = original.anchor_regen_left
		moved.anchor_upgrade = original.anchor_upgrade
		core.grid.cell_changed.emit(_hover_cell)
		_push_undo({"type": "move_tile", "from": from, "to": _hover_cell})
		held = {}
		held_changed.emit(held)
		_build_ghost()
		core.autosave_soon()
	else:
		if not core.place_tile_from_stock(_hover_cell, tile_id, rotation_q):
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		_push_undo({"type": "place_tile", "coord": _hover_cell, "tile_id": tile_id})
		var remaining := core.stock.tile_count(tile_id)
		if remaining <= 0:
			held = {}
			held_changed.emit(held)
			_build_ghost()
	var def := core.registries.tile(tile_id)
	effects.placement_poof(core.grid.cell_to_world(_hover_cell), def.placement_sound)
	_settle_animation(_hover_cell)
	action_result.emit(true, "", "place_" + def.placement_sound)


func _place_structure() -> void:
	var structure_id: String = held["id"]
	var socket := _target_socket(_hover_cell)
	if held["moving"] != null:
		var s := core.grid.add_structure(_hover_cell, structure_id, socket, held["rotation"])
		_push_undo({"type": "move_structure", "iid": s.instance_id, "from": held["moving"], "to": {"coord": _hover_cell, "socket": socket, "rot": held["rotation"]}})
		held = {}
	else:
		if not core.stock.take_structure(structure_id):
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		var s := core.grid.add_structure(_hover_cell, structure_id, socket, held["rotation"])
		core.collection.record_placed("structures", structure_id)
		_push_undo({"type": "place_structure", "coord": _hover_cell, "iid": s.instance_id, "structure_id": structure_id})
		if core.stock.structure_count(structure_id) <= 0:
			held = {}
	held_changed.emit(held)
	_build_ghost()
	var def := core.registries.structure(structure_id)
	effects.placement_poof(core.grid.cell_to_world(_hover_cell) + core.grid.socket_offset(socket), "grass" if def.placement_sound == "grass" else "stone")
	_settle_animation(_hover_cell)
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
	_pick_up_from(_cell_under_mouse())


func _pick_up_from(cell: Vector2i) -> void:
	var state := core.grid.cell(cell)
	if state == null:
		return
	if not state.structures.is_empty():
		var s: WorldGrid.StructureState = state.structures.back()
		core.grid.remove_structure(cell, s.instance_id)
		held = {"kind": "structure", "id": s.structure_id, "rotation": s.rotation, "moving": {"coord": cell, "socket": s.socket_index, "rot": s.rotation, "iid": s.instance_id}}
		_build_ghost()
		held_changed.emit(held)
		action_result.emit(true, "Click to move it, Esc to put it back, X to store it.", "pickup")
		return
	_try_pick_up_tile(cell, state)


func _try_pick_up_tile(cell: Vector2i, state: WorldGrid.CellState) -> void:
	if state.starter:
		action_result.emit(false, "The first nine tiles are the heart of your world — they stay (and can be upgraded later).", "invalid")
		return
	if state.landmark_id != "":
		action_result.emit(false, "Reclaimed landmarks move by packing them from their pedestal.", "invalid")
		return
	if not core.grid.connected_without(cell, core.grid.home_cell):
		action_result.emit(false, "Removing that tile would split your world in two.", "invalid")
		return
	if player.current_cell() == cell:
		var refuge := core.grid.nearest_walkable(cell, cell)
		if refuge == cell:
			action_result.emit(false, "There's nowhere safe to stand — place more land first.", "invalid")
			return
		player.position = core.grid.cell_to_world(refuge)
	var removed := core.grid.remove_tile(cell)
	held = {"kind": "tile", "id": removed.tile_id, "rotation": removed.rotation, "moving": {"coord": cell, "state": removed}}
	_build_ghost()
	held_changed.emit(held)
	action_result.emit(true, "Click a new edge to move the whole tile, Esc to put it back.", "pickup")


## X while holding a moved structure stores it instead of replacing it.
func store_held() -> void:
	if held.is_empty() or held["moving"] == null:
		return
	if held["kind"] == "structure":
		core.stock.add_structure(held["id"])
		_push_undo({"type": "store_structure", "structure_id": held["id"], "from": held["moving"]})
		held = {}
		held_changed.emit(held)
		_build_ghost()
		action_result.emit(true, "Stored.", "store")


func cancel_click() -> void:
	if not held.is_empty():
		_cancel_held(true)
	else:
		set_active(false)


## Cancelling a move restores the piece to its original position — nothing is
## ever lost to experimentation.
func _cancel_held(restore: bool) -> void:
	if held.is_empty():
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		return
	if restore and held["moving"] != null:
		match held["kind"]:
			"tile":
				var original: WorldGrid.CellState = held["moving"]["state"]
				var coord: Vector2i = held["moving"]["coord"]
				core.grid.cells[coord] = original
				core.grid.cell_changed.emit(coord)
				core.grid.grid_changed.emit()
			"structure":
				var m: Dictionary = held["moving"]
				var s := core.grid.add_structure(m["coord"], held["id"], m["socket"], m["rot"])
				s.instance_id = m["iid"]
	elif restore and held["moving"] == null and held["kind"] == "tile":
		pass  # piece stays in stock — nothing was consumed until placement
	held = {}
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
			if reverse:
				var coord: Vector2i = entry["coord"]
				if player.current_cell() == coord:
					player.position = core.grid.cell_to_world(core.grid.nearest_walkable(coord, coord))
				if not core.grid.connected_without(coord, core.grid.home_cell):
					return false
				var removed := core.grid.remove_tile(coord)
				if removed != null:
					core.stock.add_tile(removed.tile_id)
				return removed != null
			return core.place_tile_from_stock(entry["coord"], entry["tile_id"], 0)
		"place_structure":
			if reverse:
				var removed_s := core.grid.remove_structure(entry["coord"], entry["iid"])
				if removed_s != null:
					core.stock.add_structure(removed_s.structure_id)
				return removed_s != null
			if core.stock.take_structure(entry["structure_id"]):
				var socket := core.grid.free_socket(entry["coord"], core.registries.structure(entry["structure_id"]).socket_type)
				if socket >= 0:
					var s := core.grid.add_structure(entry["coord"], entry["structure_id"], socket)
					entry["iid"] = s.instance_id
					return true
				core.stock.add_structure(entry["structure_id"])
			return false
		"move_tile":
			var from: Vector2i = entry["to"] if reverse else entry["from"]
			var to: Vector2i = entry["from"] if reverse else entry["to"]
			return core.grid.move_tile(from, to)
		"move_structure":
			var src: Dictionary = entry["to"] if reverse else entry["from"]
			var dst: Dictionary = entry["from"] if reverse else entry["to"]
			var found := core.grid.find_structure(entry["iid"])
			if found.is_empty():
				return false
			core.grid.remove_structure(found["coord"], entry["iid"])
			var s := core.grid.add_structure(dst["coord"], _structure_id_of(entry), dst.get("socket", 0), dst.get("rot", 0))
			s.instance_id = entry["iid"]
			return true
		"store_structure":
			var m: Dictionary = entry["from"]
			if reverse:
				if core.stock.take_structure(entry["structure_id"]):
					var restored := core.grid.add_structure(m["coord"], entry["structure_id"], m["socket"], m["rot"])
					entry["from"]["iid"] = restored.instance_id
					return true
				return false
			var removed_again := core.grid.remove_structure(m["coord"], int(m.get("iid", -1)))
			if removed_again != null:
				core.stock.add_structure(entry["structure_id"])
				return true
			return false
	return false


func _structure_id_of(entry: Dictionary) -> String:
	return entry.get("structure_id", held.get("id", ""))


func _settle_animation(coord: Vector2i) -> void:
	var renderer := get_parent().find_child("WorldRenderer", false, false) as WorldRenderer
	if renderer == null:
		return
	var node := renderer.tile_node(coord)
	if node == null:
		return
	node.position.y = 0.5
	node.scale = Vector3(0.94, 0.94, 0.94)
	var tween := node.create_tween()
	tween.set_parallel()
	tween.tween_property(node, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
