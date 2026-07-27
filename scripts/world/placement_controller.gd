class_name PlacementController
extends Node3D
## Build mode: ghost previews, grid snapping, rotation, move-with-cancel,
## undo/redo, and every placement safety rule (adjacency, overlap, world
## connectivity, player standing-cell relocation). The grid snaps pieces;
## the player character never snaps.

signal mode_changed(active: bool)
signal held_changed(held: Dictionary)
signal action_result(ok: bool, message: String, kind: String)
signal hover_changed(display_name: String, collection_name: String)

const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)

var core: GameCore
var assets: AssetLibrary
var camera_rig: CameraRig
var player: PlayerController
var effects: EffectsManager
var world_renderer: WorldRenderer
var _tile_visual_factory: TileVisualFactory
var _structure_visual_factory: RefCounted

var active := false
var held: Dictionary = {}      # {kind: tile|structure|deed, id, rotation, moving: {...}|null}
var _ghost: Node3D
var _indicator: MeshInstance3D
var _hover_cell := Vector2i(9999, 9999)
var _hover_elevation := 0
var _hover_valid := false
var _hover_support_instance_id := 0
var _hover_support_slot := ""
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _pointer_down := false
var _pointer_dragging := false
var _pointer_press_position := Vector2.ZERO
var _picked_on_pointer_press := false
var _hover_info_signature := ""

var _ghost_ok_material: StandardMaterial3D
var _ghost_bad_material: StandardMaterial3D


func setup(
	game_core: GameCore,
	asset_library: AssetLibrary,
	rig: CameraRig,
	player_controller: PlayerController,
	effects_manager: EffectsManager,
	renderer: WorldRenderer
) -> void:
	core = game_core
	assets = asset_library
	camera_rig = rig
	player = player_controller
	effects = effects_manager
	world_renderer = renderer
	_tile_visual_factory = TileVisualFactory.new(assets, core.grid)
	_structure_visual_factory = StructureVisualFactoryScript.new(assets, core.grid)
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
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
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
	if (
		held.get("kind", "") == "tile"
		and held.get("moving") != null
		and held["moving"].has("stack")
	):
		_build_tile_stack_ghost(held["moving"]["stack"])
		add_child(_ghost)
		_set_ghost_material(_ghost_ok_material)
		return
	var asset_id := ""
	match held["kind"]:
		"tile":
			var tile_def := core.registries.tile(held["id"])
			if tile_def == null:
				action_result.emit(false, "That tile is no longer available.", "invalid")
				return
			_ghost = _tile_visual_factory.instantiate_visual(tile_def)
		"structure":
			var structure_def := core.registries.structure(held["id"])
			if structure_def == null:
				action_result.emit(false, "That decoration is no longer available.", "invalid")
				return
			_ghost = _structure_visual_factory.instantiate_visual(structure_def)
		"deed":
			var landmark_def := core.registries.landmark(held["id"])
			if landmark_def == null:
				action_result.emit(false, "That landmark is no longer available.", "invalid")
				return
			asset_id = landmark_def.asset_id
	if _ghost == null:
		_ghost = assets.instantiate(asset_id)
	if (
		held.get("kind", "") == "structure"
		and held.get("moving") != null
		and held["moving"].has("stack")
	):
		_add_stack_descendants_to_ghost(held["moving"]["stack"])
	add_child(_ghost)
	_set_ghost_material(_ghost_ok_material)


func _build_tile_stack_ghost(stack: Array) -> void:
	_ghost = Node3D.new()
	_ghost.name = "TileStackGhost"
	if stack.is_empty():
		return
	var base_state: WorldGrid.CellState = stack[0]["state"]
	var base_angle := base_state.rotation * PI * 0.5
	var inverse_base := Transform3D(Basis(Vector3.UP, -base_angle), Vector3.ZERO)
	for entry: Dictionary in stack:
		var relative := int(entry["relative_elevation"])
		var state: WorldGrid.CellState = entry["state"]
		var definition := core.registries.tile(state.tile_id)
		if definition == null:
			continue
		var tile_visual := _tile_visual_factory.instantiate_visual(definition)
		tile_visual.name = "ghost_tile_e%d" % relative
		tile_visual.position.y = relative * core.grid.block_depth
		tile_visual.rotation.y = (state.rotation - base_state.rotation) * PI * 0.5
		_tile_visual_factory.set_surface_covered(
			tile_visual,
			relative < int(stack.back()["relative_elevation"])
		)
		_ghost.add_child(tile_visual)
		for structure: WorldGrid.StructureState in state.structures:
			var structure_def := core.registries.structure(structure.structure_id)
			if structure_def == null:
				continue
			var structure_visual: Node3D = _structure_visual_factory.instantiate_visual(
				structure_def
			)
			structure_visual.name = "ghost_structure_%d" % structure.instance_id
			var elevation_transform := Transform3D(
				Basis.IDENTITY,
				Vector3(0, relative * core.grid.block_depth, 0)
			)
			structure_visual.transform = (
				elevation_transform
				* inverse_base
				* core.grid.structure_local_transform_in_cell(
					state,
					structure.instance_id
				)
			)
			_ghost.add_child(structure_visual)


func _add_stack_descendants_to_ghost(stack: Array[WorldGrid.StructureState]) -> void:
	if _ghost == null or stack.size() <= 1:
		return
	var root: WorldGrid.StructureState = stack[0]
	var by_id := {}
	for structure: WorldGrid.StructureState in stack:
		by_id[structure.instance_id] = structure
	for structure: WorldGrid.StructureState in stack:
		if structure.instance_id == root.instance_id:
			continue
		var definition := core.registries.structure(structure.structure_id)
		if definition == null:
			continue
		var child_visual: Node3D = _structure_visual_factory.instantiate_visual(
			definition
		)
		child_visual.name = "ghost_descendant_%d" % structure.instance_id
		child_visual.transform = _stack_relative_transform(
			structure.instance_id,
			root.instance_id,
			by_id,
			{}
		)
		_ghost.add_child(child_visual)


func _stack_relative_transform(
	instance_id: int,
	root_instance_id: int,
	by_id: Dictionary,
	visiting: Dictionary
) -> Transform3D:
	if instance_id == root_instance_id:
		return Transform3D.IDENTITY
	if not by_id.has(instance_id) or visiting.has(instance_id):
		return Transform3D.IDENTITY
	visiting[instance_id] = true
	var structure: WorldGrid.StructureState = by_id[instance_id]
	if not by_id.has(structure.parent_instance_id):
		visiting.erase(instance_id)
		return Transform3D.IDENTITY
	var parent: WorldGrid.StructureState = by_id[structure.parent_instance_id]
	var parent_def := core.registries.structure(parent.structure_id)
	var slot := (
		parent_def.support_slot(structure.support_slot_id)
		if parent_def != null
		else null
	)
	if slot == null:
		visiting.erase(instance_id)
		return Transform3D.IDENTITY
	var parent_transform := _stack_relative_transform(
		parent.instance_id,
		root_instance_id,
		by_id,
		visiting
	)
	visiting.erase(instance_id)
	return parent_transform * Transform3D(
		Basis(Vector3.UP, structure.rotation * PI * 0.5),
		slot.offset
	)


func _set_ghost_material(mat: StandardMaterial3D) -> void:
	if _ghost == null:
		return
	for child in _ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, mat)


# ------------------------------------------------------------------ per-frame preview

func _process(delta: float) -> void:
	if not active:
		_indicator.visible = false
		_emit_hover_info("", "", "")
		if _ghost != null:
			_ghost.visible = false
		return
	if held.is_empty():
		_indicator.visible = false
		if _ghost != null:
			_ghost.visible = false
		_update_placeable_hover()
		return
	world_renderer.clear_structure_hover()
	_emit_hover_info("", "", "")
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
			if _hover_support_instance_id > 0:
				if _hover_support_slot != "":
					var support_transform := world_renderer.support_slot_world_transform(
						_hover_support_instance_id,
						_hover_support_slot
					)
					target_position = support_transform.origin + Vector3(
						0,
						0.1 + sin(Time.get_ticks_msec() * 0.006) * 0.025,
						0
					)
				else:
					target_position = world_renderer.structure_preview_position(
						_hover_support_instance_id
					) + Vector3(0, 0.1, 0)
			else:
				var socket := _target_socket(_hover_cell, _hover_elevation)
				if socket >= 0:
					target_position += core.grid.socket_offset(socket)
		if was_visible:
			_ghost.position = _ghost.position.lerp(target_position, 1.0 - exp(-delta * 20.0))
		else:
			_ghost.position = target_position
		var target_yaw := int(held["rotation"]) * PI * 0.5
		if _hover_support_instance_id > 0 and _hover_support_slot != "":
			target_yaw += world_renderer.support_slot_world_transform(
				_hover_support_instance_id,
				_hover_support_slot
			).basis.get_euler().y
		_ghost.rotation.y = lerp_angle(
			_ghost.rotation.y,
			target_yaw,
			1.0 - exp(-delta * 22.0)
		)
		_set_ghost_material(_ghost_ok_material if _hover_valid else _ghost_bad_material)
	_sync_indicator_preview(world)


## Valid and invalid previews share the same grid-aligned isometric footprint.
## Validity is communicated by material only, so a rejected placement never
## appears to rotate away from the surface it is testing.
func _sync_indicator_preview(world: Vector3) -> void:
	_indicator.visible = _hover_support_instance_id == 0
	_indicator.position = world + Vector3(0, 0.03, 0)
	_indicator.rotation.y = 0.0
	_indicator.material_override = _ghost_ok_material if _hover_valid else _ghost_bad_material


func _update_placeable_hover() -> void:
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		get_viewport().get_mouse_position()
	)
	if hit.is_empty():
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		return
	if hit.get("kind", "") == "structure":
		var instance_id := int(hit["instance_id"])
		var found := core.grid.find_structure(instance_id)
		if found.is_empty():
			world_renderer.clear_structure_hover()
			_emit_hover_info("", "", "")
			return
		var structure: WorldGrid.StructureState = found["structure"]
		var definition := core.registries.structure(structure.structure_id)
		world_renderer.set_hovered_structure(instance_id, true)
		_emit_hover_info(
			"structure:%d" % instance_id,
			definition.display_name if definition != null else structure.structure_id,
			_structure_collection_name(definition)
		)
		return
	var coord: Vector2i = hit["coord"]
	var elevation := int(hit["elevation"])
	var state := core.grid.cell_at(coord, elevation)
	var tile_definition := core.grid.tile_def_at(coord, elevation)
	world_renderer.set_hovered_tile(coord, elevation, true)
	_emit_hover_info(
		"tile:%d:%d:%d" % [coord.x, coord.y, elevation],
		tile_definition.display_name if tile_definition != null else state.tile_id,
		_tile_collection_name(tile_definition)
	)


func _tile_collection_name(definition: Defs.TileDefinition) -> String:
	if definition == null:
		return "Tile Collection"
	return "%s Tiles" % definition.family.replace("_", " ").capitalize()


func _structure_collection_name(definition: Defs.StructureDefinition) -> String:
	if definition == null:
		return "Object Collection"
	match definition.kind:
		"building":
			return "Structures"
		"utility":
			return "Utilities"
		_:
			return "Decorations"


func _emit_hover_info(signature: String, display_name: String, collection_name: String) -> void:
	if signature == _hover_info_signature:
		return
	_hover_info_signature = signature
	hover_changed.emit(display_name, collection_name)


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
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	if held.get("kind", "") == "structure":
		var structure_hit := world_renderer.pick_structure_at_screen(
			camera_rig.camera,
			get_viewport().get_mouse_position()
		)
		if not structure_hit.is_empty():
			_hover_cell = structure_hit["coord"]
			_hover_elevation = core.grid.top_elevation(_hover_cell)
			if _resolve_highest_structure_target(_hover_cell, _hover_elevation):
				return
	var hit := _slot_under_mouse()
	_hover_cell = hit["coord"]
	var support_elevation := int(hit["elevation"])
	match held.get("kind", ""):
		"tile":
			var tile_column_top := core.grid.top_elevation(_hover_cell)
			_hover_elevation = tile_column_top + 1 if tile_column_top >= 0 else 0
		"structure":
			var structure_column_top := core.grid.top_elevation(_hover_cell)
			_hover_elevation = (
				structure_column_top
				if structure_column_top >= 0
				else maxi(0, support_elevation)
			)
			_resolve_highest_structure_target(_hover_cell, _hover_elevation)
		_:
			_hover_elevation = 0


## A column is resolved from its highest support level, with visual height as a
## same-level tie-breaker, never from whichever lower collider won the ray. If
## that top object cannot accept the held item, validation correctly fails.
func _resolve_highest_structure_target(coord: Vector2i, elevation: int) -> bool:
	var instance_id := _highest_structure_instance_at(coord, elevation)
	if instance_id <= 0:
		return false
	_hover_support_instance_id = instance_id
	_hover_support_slot = core.grid.free_support_slot(
		instance_id,
		String(held.get("id", ""))
	)
	return true


func _highest_structure_instance_at(coord: Vector2i, elevation: int) -> int:
	var state := core.grid.cell_at(coord, elevation)
	if state == null or state.structures.is_empty():
		return -1
	var best_instance_id := -1
	var best_height := -1.0e20
	var best_depth := -1
	for structure: WorldGrid.StructureState in state.structures:
		var depth := core.grid.structure_depth(structure.instance_id)
		var visual := world_renderer.structure_node(structure.instance_id)
		var height := (
			world_renderer.structure_preview_position(structure.instance_id).y
			if visual != null
			else (
				core.grid.cell_to_world(coord, elevation).y
				+ core.grid.structure_local_transform(structure.instance_id).origin.y
			)
		)
		if (
			depth > best_depth
			or (
				depth == best_depth
				and (
					height > best_height + 0.0001
					or (
						is_equal_approx(height, best_height)
						and structure.instance_id > best_instance_id
					)
				)
			)
		):
			best_instance_id = structure.instance_id
			best_height = height
			best_depth = depth
	return best_instance_id


func _validate(cell: Vector2i, elevation: int = 0) -> bool:
	match held.get("kind", ""):
		"tile":
			if held["moving"] != null and held["moving"].has("stack"):
				if player.current_cell() == cell and elevation > 0:
					return false
				return core.grid.can_restore_tile_stack(
					cell,
					elevation,
					held["moving"]["stack"]
				)
			if elevation > 0:
				if player.current_cell() == cell:
					return false
				return core.grid.can_place_tile_at(cell, elevation, held["id"])
			if held["moving"] != null and int(held["moving"].get("elevation", 0)) == 0:
				var from: Vector2i = held["moving"]["coord"]
				return not core.grid.has_cell(cell) and _adjacent_excluding(cell, from)
			return core.grid.can_place_tile_at(cell, 0, held["id"])
		"structure":
			if _hover_support_instance_id > 0:
				if held.get("moving") != null:
					var moving_stack: Array[WorldGrid.StructureState] = held["moving"]["stack"]
					if (
						core.grid.structure_depth(_hover_support_instance_id)
						+ 1
						+ core.grid.structure_stack_height(moving_stack)
						>= core.grid.max_object_stack_depth
					):
						return false
				return core.grid.can_place_structure_on(
					_hover_support_instance_id,
					String(held["id"]),
					_hover_support_slot
				)
			if (
				held.get("moving") != null
				and core.grid.structure_stack_height(held["moving"]["stack"])
					>= core.grid.max_object_stack_depth
			):
				return false
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
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	_hover_cell = cell
	match held.get("kind", ""):
		"tile":
			_hover_elevation = core.grid.top_elevation(cell) + 1 if core.grid.has_cell(cell) else 0
		"structure":
			_hover_elevation = maxi(0, core.grid.top_elevation(cell))
			_resolve_highest_structure_target(cell, _hover_elevation)
		_:
			_hover_elevation = 0
	_hover_valid = _validate(cell, _hover_elevation)
	if not _hover_valid:
		return false
	click()
	return true


func try_place_at_layer(cell: Vector2i, elevation: int) -> bool:
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	_hover_cell = cell
	_hover_elevation = elevation
	if (
		held.get("kind", "") == "structure"
		and core.grid.top_elevation(cell) == elevation
	):
		_resolve_highest_structure_target(cell, elevation)
	_hover_valid = _validate(cell, elevation)
	if not _hover_valid:
		return false
	click()
	return true


## Programmatic equivalent of hovering a specific object. Tests and future
## controller navigation use the same typed-slot validation as the mouse path.
func try_place_on_structure(parent_instance_id: int, slot_id: String = "") -> bool:
	if held.get("kind", "") != "structure":
		return false
	var found := core.grid.find_structure(parent_instance_id)
	if found.is_empty():
		return false
	_hover_support_instance_id = parent_instance_id
	_hover_support_slot = core.grid.free_support_slot(
		parent_instance_id,
		String(held["id"]),
		slot_id
	)
	_hover_cell = found["coord"]
	_hover_elevation = int(found["elevation"])
	_hover_valid = _validate(_hover_cell, _hover_elevation)
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
		if _hover_support_instance_id > 0:
			var parent_found := core.grid.find_structure(_hover_support_instance_id)
			var parent_def := (
				core.registries.structure(parent_found["structure"].structure_id)
				if not parent_found.is_empty()
				else null
			)
			if parent_def != null and parent_def.support_slots.is_empty():
				return "That object cannot hold another item."
			return "That support is full or does not fit this item."
		return "That object needs a clear supported spot."
	return "It can't go there — land must touch the world edge-to-edge."


func _place_tile() -> void:
	var tile_id: String = held["id"]
	var rotation_q: int = held["rotation"]
	if held["moving"] != null:
		var from: Vector2i = held["moving"]["coord"]
		var from_elevation := int(held["moving"].get("elevation", 0))
		var stack: Array = held["moving"]["stack"]
		var from_rotation := int(held["moving"].get("base_rotation", rotation_q))
		_rotate_tile_stack(stack, rotation_q - from_rotation)
		if not core.grid.restore_tile_stack(_hover_cell, _hover_elevation, stack):
			_rotate_tile_stack(stack, from_rotation - rotation_q)
			action_result.emit(false, "That land stack changed before it could settle.", "invalid")
			return
		_push_undo({
			"type": "move_tile_stack",
			"from": from,
			"from_elevation": from_elevation,
			"to": _hover_cell,
			"to_elevation": _hover_elevation,
			"from_rotation": from_rotation,
			"to_rotation": rotation_q,
			"home_before": held["moving"].get("home_before", core.grid.home_cell),
			"home_after": held["moving"].get("home_after", core.grid.home_cell),
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


func _rotate_tile_stack(stack: Array, quarter_turn_delta: int) -> void:
	if posmod(quarter_turn_delta, 4) == 0:
		return
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		state.rotation = posmod(state.rotation + quarter_turn_delta, 4)
		for structure: WorldGrid.StructureState in state.structures:
			if structure.parent_instance_id == 0:
				structure.rotation = posmod(
					structure.rotation + quarter_turn_delta,
					4
				)


func _place_structure() -> void:
	var structure_id: String = held["id"]
	var socket := (
		-1
		if _hover_support_instance_id > 0
		else _target_socket(_hover_cell, _hover_elevation)
	)
	var placed: WorldGrid.StructureState = null
	if held["moving"] != null:
		var moving: Dictionary = held["moving"]
		var stack: Array[WorldGrid.StructureState] = moving["stack"]
		if not core.grid.restore_structure_stack(
			_hover_cell,
			_hover_elevation,
			stack,
			_hover_support_instance_id,
			_hover_support_slot,
			socket,
			int(held["rotation"])
		):
			action_result.emit(false, "That support changed before the item could settle.", "invalid")
			return
		placed = stack[0]
		_push_undo({
			"type": "move_structure",
			"iid": placed.instance_id,
			"structure_id": structure_id,
			"stack": stack,
			"from": moving["origin"],
			"to": {
				"coord": _hover_cell,
				"elevation": _hover_elevation,
				"socket": socket,
				"rot": held["rotation"],
				"parent": _hover_support_instance_id,
				"support": _hover_support_slot,
			},
		})
		held = {}
		core.autosave_paused = false
	else:
		if not core.stock.take_structure(structure_id):
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		if _hover_support_instance_id > 0:
			placed = core.grid.add_structure_on(
				_hover_support_instance_id,
				structure_id,
				_hover_support_slot,
				held["rotation"]
			)
		else:
			placed = core.grid.add_structure(
				_hover_cell,
				structure_id,
				socket,
				held["rotation"],
				_hover_elevation
			)
		if placed == null:
			core.stock.add_structure(structure_id)
			action_result.emit(false, "That support changed before the item could settle.", "invalid")
			return
		core.collection.record_placed("structures", structure_id)
		_push_undo({
			"type": "place_structure",
			"coord": _hover_cell,
			"elevation": _hover_elevation,
			"iid": placed.instance_id,
			"structure_id": structure_id,
			"socket": socket,
			"rot": held["rotation"],
			"parent": _hover_support_instance_id,
			"support": _hover_support_slot,
		})
		if core.stock.structure_count(structure_id) <= 0:
			held = {}
	held_changed.emit(held)
	_build_ghost()
	var def := core.registries.structure(structure_id)
	var effect_position := (
		world_renderer.support_slot_world_transform(
			_hover_support_instance_id,
			_hover_support_slot
		).origin
		if _hover_support_instance_id > 0
		else core.grid.cell_to_world(_hover_cell, _hover_elevation)
			+ core.grid.socket_offset(socket)
	)
	effects.placement_poof(
		effect_position,
		"grass" if def.placement_sound == "grass" else "stone"
	)
	world_renderer.animate_structure_settle(placed.instance_id)
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
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		get_viewport().get_mouse_position()
	)
	if not hit.is_empty() and hit.get("kind", "") == "structure":
		_pick_up_from(
			hit["coord"],
			int(hit["elevation"]),
			int(hit["instance_id"])
		)
		return
	if not hit.is_empty() and hit.get("kind", "") == "tile":
		var tile_state := core.grid.cell_at(hit["coord"], int(hit["elevation"]))
		if tile_state != null:
			_try_pick_up_tile(hit["coord"], int(hit["elevation"]), tile_state)
		return
	var slot_hit := _slot_under_mouse()
	var elevation := int(slot_hit["elevation"])
	if elevation >= 0:
		_pick_up_from(slot_hit["coord"], elevation)


func _pick_up_from(cell: Vector2i, elevation: int, preferred_instance_id := -1) -> void:
	var state := core.grid.cell_at(cell, elevation)
	if state == null:
		return
	if not state.structures.is_empty():
		var s: WorldGrid.StructureState = null
		if preferred_instance_id >= 0:
			for candidate: WorldGrid.StructureState in state.structures:
				if candidate.instance_id == preferred_instance_id:
					s = candidate
					break
		else:
			s = state.structures.back()
		if s == null:
			return
		var origin := {
			"coord": cell,
			"elevation": elevation,
			"socket": s.socket_index,
			"rot": s.rotation,
			"iid": s.instance_id,
			"parent": s.parent_instance_id,
			"support": s.support_slot_id,
		}
		world_renderer.clear_structure_hover()
		var stack := core.grid.detach_structure_stack(s.instance_id)
		if stack.is_empty():
			return
		core.autosave_paused = true
		held = {
			"kind": "structure",
			"id": s.structure_id,
			"rotation": s.rotation,
			"moving": {
				"stack": stack,
				"origin": origin,
			},
		}
		_build_ghost()
		held_changed.emit(held)
		action_result.emit(true, "Click to move it, Esc to put it back, X to store it.", "pickup")
		return
	_try_pick_up_tile(cell, elevation, state)


func _try_pick_up_tile(cell: Vector2i, elevation: int, state: WorldGrid.CellState) -> void:
	if state.movement_locked:
		action_result.emit(false, "This first water tile anchors the opening zone for now.", "invalid")
		return
	if elevation == 0 and state.landmark_id != "":
		action_result.emit(false, "Reclaimed landmarks move by packing them from their pedestal.", "invalid")
		return
	var home_before := core.grid.home_cell
	var home_after := home_before
	if elevation == 0 and home_before == cell:
		home_after = core.grid.nearest_walkable(cell, cell)
		if home_after == cell:
			action_result.emit(false, "Place another safe land tile before moving this one.", "invalid")
			return
	if elevation == 0 and not core.grid.connected_without(cell, home_after):
		action_result.emit(false, "Removing that tile would split your world in two.", "invalid")
		return
	if elevation == 0 and player.current_cell() == cell:
		var refuge := core.grid.nearest_walkable(cell, cell)
		if refuge == cell:
			action_result.emit(false, "There's nowhere safe to stand — place more land first.", "invalid")
			return
		player.position = core.grid.cell_to_world(refuge)
	if elevation == 0:
		core.grid.home_cell = home_after
	var stack := core.grid.detach_tile_stack(cell, elevation)
	if stack.is_empty():
		core.grid.home_cell = home_before
		return
	var removed: WorldGrid.CellState = stack[0]["state"]
	core.autosave_paused = true
	held = {
		"kind": "tile",
		"id": removed.tile_id,
		"rotation": removed.rotation,
		"moving": {
			"coord": cell,
			"elevation": elevation,
			"stack": stack,
			"base_rotation": removed.rotation,
			"home_before": home_before,
			"home_after": home_after,
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
			var moved_stack: Array[WorldGrid.StructureState] = held["moving"]["stack"]
			for structure: WorldGrid.StructureState in moved_stack:
				core.stock.add_structure(structure.structure_id)
			_push_undo({
				"type": "store_structure",
				"structure_id": held["id"],
				"stack": moved_stack,
				"from": held["moving"]["origin"],
			})
		"tile":
			var tile_stack: Array = held["moving"]["stack"]
			_return_tile_stack_to_stock(tile_stack)
			_push_undo({
				"type": "store_tile_stack",
				"tile_id": held["id"],
				"stack": tile_stack,
				"from": held["moving"].duplicate(),
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
				var coord: Vector2i = held["moving"]["coord"]
				var elevation := int(held["moving"].get("elevation", 0))
				core.grid.restore_tile_stack(
					coord,
					elevation,
					held["moving"]["stack"],
					false
				)
				core.grid.home_cell = held["moving"].get("home_before", core.grid.home_cell)
			"structure":
				var moving: Dictionary = held["moving"]
				var origin: Dictionary = moving["origin"]
				core.grid.restore_structure_stack(
					origin["coord"],
					int(origin.get("elevation", 0)),
					moving["stack"],
					int(origin.get("parent", 0)),
					String(origin.get("support", "")),
					int(origin.get("socket", 0)),
					int(origin.get("rot", 0))
				)
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
				var removed_stack := core.grid.detach_structure_stack(entry["iid"])
				if removed_stack.is_empty():
					return false
				for removed_s: WorldGrid.StructureState in removed_stack:
					core.stock.add_structure(removed_s.structure_id)
				return true
			if core.stock.take_structure(entry["structure_id"]):
				var s: WorldGrid.StructureState = null
				if int(entry.get("parent", 0)) > 0:
					s = core.grid.add_structure_on(
						int(entry["parent"]),
						entry["structure_id"],
						String(entry.get("support", "")),
						int(entry.get("rot", 0))
					)
				else:
					s = core.grid.add_structure(
						entry["coord"],
						entry["structure_id"],
						int(entry.get("socket", -1)),
						int(entry.get("rot", 0)),
						structure_elevation
					)
				if s != null:
					entry["iid"] = s.instance_id
					return true
				core.stock.add_structure(entry["structure_id"])
			return false
		"move_tile_stack":
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
			var moving_stack := core.grid.detach_tile_stack(from, from_elevation)
			if moving_stack.is_empty():
				return false
			var source_rotation := int(
				entry.get("to_rotation", 0)
				if reverse
				else entry.get("from_rotation", 0)
			)
			var destination_rotation := int(
				entry.get("from_rotation", 0)
				if reverse
				else entry.get("to_rotation", 0)
			)
			_rotate_tile_stack(moving_stack, destination_rotation - source_rotation)
			if not core.grid.restore_tile_stack(to, to_elevation, moving_stack):
				_rotate_tile_stack(moving_stack, source_rotation - destination_rotation)
				core.grid.restore_tile_stack(from, from_elevation, moving_stack, false)
				return false
			core.grid.home_cell = (
				entry.get("home_before", core.grid.home_cell)
				if reverse
				else entry.get("home_after", core.grid.home_cell)
			)
			return true
		"move_structure":
			var dst: Dictionary = entry["from"] if reverse else entry["to"]
			var found := core.grid.find_structure(entry["iid"])
			if found.is_empty():
				return false
			var moved_stack := core.grid.detach_structure_stack(entry["iid"])
			if moved_stack.is_empty():
				return false
			if not core.grid.restore_structure_stack(
				dst["coord"],
				int(dst.get("elevation", 0)),
				moved_stack,
				int(dst.get("parent", 0)),
				String(dst.get("support", "")),
				int(dst.get("socket", 0)),
				int(dst.get("rot", 0))
			):
				var src: Dictionary = entry["to"] if reverse else entry["from"]
				core.grid.restore_structure_stack(
					src["coord"],
					int(src.get("elevation", 0)),
					moved_stack,
					int(src.get("parent", 0)),
					String(src.get("support", "")),
					int(src.get("socket", 0)),
					int(src.get("rot", 0))
				)
				return false
			entry["stack"] = moved_stack
			return true
		"store_structure":
			var m: Dictionary = entry["from"]
			var stored_stack: Array[WorldGrid.StructureState] = entry["stack"]
			if reverse:
				if not _take_structure_stack_from_stock(stored_stack):
					return false
				if core.grid.restore_structure_stack(
					m["coord"],
					int(m.get("elevation", 0)),
					stored_stack,
					int(m.get("parent", 0)),
					String(m.get("support", "")),
					int(m.get("socket", 0)),
					int(m.get("rot", 0))
				):
					return true
				_return_structure_stack_to_stock(stored_stack)
				return false
			var removed_again := core.grid.detach_structure_stack(
				int(m.get("iid", -1))
			)
			if not removed_again.is_empty():
				entry["stack"] = removed_again
				_return_structure_stack_to_stock(removed_again)
				return true
			return false
		"store_tile_stack":
			var tile_from: Dictionary = entry["from"]
			var tile_coord: Vector2i = tile_from["coord"]
			var tile_elevation := int(tile_from.get("elevation", 0))
			var stored_tiles: Array = entry["stack"]
			if reverse:
				if not _take_tile_stack_from_stock(stored_tiles):
					return false
				if not core.grid.restore_tile_stack(
					tile_coord,
					tile_elevation,
					stored_tiles
				):
					_return_tile_stack_to_stock(stored_tiles)
					return false
				core.grid.home_cell = tile_from.get("home_before", core.grid.home_cell)
				return true
			var removed_tiles := core.grid.detach_tile_stack(tile_coord, tile_elevation)
			if removed_tiles.is_empty():
				return false
			entry["stack"] = removed_tiles
			core.grid.home_cell = tile_from.get("home_after", core.grid.home_cell)
			_return_tile_stack_to_stock(removed_tiles)
			return true
	return false


func _structure_id_of(entry: Dictionary) -> String:
	return entry.get("structure_id", held.get("id", ""))


func _take_structure_stack_from_stock(stack: Array[WorldGrid.StructureState]) -> bool:
	var taken: Array[String] = []
	for structure: WorldGrid.StructureState in stack:
		if not core.stock.take_structure(structure.structure_id):
			for structure_id: String in taken:
				core.stock.add_structure(structure_id)
			return false
		taken.append(structure.structure_id)
	return true


func _return_structure_stack_to_stock(stack: Array[WorldGrid.StructureState]) -> void:
	for structure: WorldGrid.StructureState in stack:
		core.stock.add_structure(structure.structure_id)


func _take_tile_stack_from_stock(stack: Array) -> bool:
	var taken_tiles: Array[String] = []
	var taken_structures: Array[String] = []
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		if not core.stock.take_tile(state.tile_id):
			for tile_id: String in taken_tiles:
				core.stock.add_tile(tile_id)
			for structure_id: String in taken_structures:
				core.stock.add_structure(structure_id)
			return false
		taken_tiles.append(state.tile_id)
		for structure: WorldGrid.StructureState in state.structures:
			if not core.stock.take_structure(structure.structure_id):
				for tile_id: String in taken_tiles:
					core.stock.add_tile(tile_id)
				for structure_id: String in taken_structures:
					core.stock.add_structure(structure_id)
				return false
			taken_structures.append(structure.structure_id)
	return true


func _return_tile_stack_to_stock(stack: Array) -> void:
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		core.stock.add_tile(state.tile_id)
		for structure: WorldGrid.StructureState in state.structures:
			core.stock.add_structure(structure.structure_id)


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
