class_name PlacementRules
extends RefCounted
## Pure placement policy facade. Presentation and pointer state stay in the
## controller; legal placement is decided here against the authoritative grid.

var core: GameCore
var player: PlayerController


func _init(game_core: GameCore, player_controller: PlayerController) -> void:
	core = game_core
	player = player_controller


func validate(
	held: Dictionary,
	cell: Vector2i,
	elevation: int,
	support_instance_id: int,
	support_slot: String
) -> bool:
	match held.get("kind", ""):
		"tile":
			if held["moving"] != null and held["moving"].has("stack"):
				if player.current_cell() == cell and elevation > 0:
					return false
				return core.grid.can_restore_tile_stack(
					cell, elevation, held["moving"]["stack"]
				)
			if elevation > 0:
				if player.current_cell() == cell:
					return false
				return core.grid.can_place_tile_at(cell, elevation, held["id"])
			if held["moving"] != null and int(held["moving"].get("elevation", 0)) == 0:
				return not core.grid.has_cell(cell)
			return core.grid.can_place_tile_at(cell, 0, held["id"])
		"structure":
			if support_instance_id > 0:
				if held.get("moving") != null:
					var moving_stack: Array[WorldGrid.StructureState] = held["moving"]["stack"]
					if (
						core.grid.structure_depth(support_instance_id)
						+ 1
						+ core.grid.structure_stack_height(moving_stack)
						>= core.grid.max_object_stack_depth
					):
						return false
				return core.grid.can_place_structure_on(
					support_instance_id, String(held["id"]), support_slot
				)
			if (
				held.get("moving") != null
				and core.grid.structure_stack_height(held["moving"]["stack"])
					>= core.grid.max_object_stack_depth
			):
				return false
			return target_socket(held, cell, elevation) >= 0
		"deed":
			if elevation != 0:
				return false
			var definition := core.registries.landmark(held["id"])
			if definition == null:
				return false
			var adjacent := false
			for offset in definition.footprint:
				var coord: Vector2i = cell + offset
				if core.grid.has_cell(coord):
					return false
				if core.grid.is_adjacent_to_world(coord):
					adjacent = true
			return adjacent
	return false


func target_socket(held: Dictionary, cell: Vector2i, elevation: int) -> int:
	if not core.grid.has_cell_at(cell, elevation):
		return -1
	var definition := core.registries.structure(held.get("id", ""))
	if (
		definition == null
		or not core.grid.can_place_structure_at(cell, elevation, definition.id)
	):
		return -1
	return core.grid.free_socket(cell, definition.socket_type, elevation)


func invalid_message(
	held: Dictionary,
	elevation: int,
	support_instance_id: int
) -> String:
	if held.get("kind", "") == "tile" and elevation > 0:
		return "That surface can't support another land tile — use a flat, clear block."
	if held.get("kind", "") == "structure":
		if support_instance_id > 0:
			var parent_found := core.grid.find_structure(support_instance_id)
			var parent_definition := (
				core.registries.structure(parent_found["structure"].structure_id)
				if not parent_found.is_empty()
				else null
			)
			if parent_definition != null and parent_definition.support_slots.is_empty():
				return "That object cannot hold another item."
			return "That support is full or does not fit this item."
		return "That object needs a clear supported spot."
	if held.get("kind", "") == "tile":
		return "That grid space is already occupied."
	return "It can't go there."
