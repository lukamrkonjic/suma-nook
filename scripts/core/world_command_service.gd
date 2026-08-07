class_name WorldCommandService
extends RefCounted
## Single choke point for Unfolding World state changes. UI and systems
## issue commands; this reducer applies them to WorldGrid and publishes the
## resulting world events. Discovery systems never mutate world state
## directly — they listen, then issue their own commands here.
##
## The command log is the save/snapshot substrate: `RestoreSeed`-style
## filtered replays (bare Nook, clear details) operate on this log without
## any special-cased clearing code.

var grid: WorldGrid
var registries: Registries
var events: WorldEvents

## Bounded append-only history: [{"name": String, "args": Dictionary}].
var log: Array[Dictionary] = []
var max_log_entries := 4096
## Depth counter: >0 while a command mutates the grid. The GameCore
## model-event forwarder consults this so command-internal structure churn
## (generation, growth swaps, clearing remainders) never double-publishes
## as player model placement.
var _apply_depth := 0

var is_applying: bool:
	get: return _apply_depth > 0


func _init(
	world_grid: WorldGrid,
	regs: Registries,
	world_events: WorldEvents
) -> void:
	grid = world_grid
	registries = regs
	events = world_events


## Applies one command. Returns a result dictionary; `ok` is always present.
## Unknown commands fail loudly — a typo must never silently no-op.
func apply(name: String, args: Dictionary) -> Dictionary:
	var result: Dictionary
	_apply_depth += 1
	match name:
		"place_tile": result = _place_tile(args)
		"remove_tile": result = _remove_tile(args)
		"place_feature": result = _place_feature(args)
		"clear_feature": result = _clear_feature(args)
		"plant_sapling": result = _plant_sapling(args)
		"advance_growth": result = _advance_growth(args)
		"wake_dormant": result = _wake_dormant(args)
		_:
			_apply_depth -= 1
			push_error("WorldCommandService: unknown command '%s'" % name)
			return {"ok": false, "reason": "unknown_command"}
	_apply_depth -= 1
	if bool(result.get("ok", false)):
		_record(name, args)
	return result


func _record(name: String, args: Dictionary) -> void:
	log.append({"name": name, "args": args.duplicate(true)})
	while log.size() > max_log_entries:
		log.pop_front()


## --- Terrain -------------------------------------------------------------


func _place_tile(args: Dictionary) -> Dictionary:
	var coord: Vector2i = args.get("coord", Vector2i.ZERO)
	var tile_id := String(args.get("tile_id", ""))
	var elevation := int(args.get("elevation", 0))
	if registries.tile(tile_id) == null:
		return {"ok": false, "reason": "unknown_tile"}
	if grid.has_cell_at(coord, elevation):
		return {"ok": false, "reason": "occupied"}
	grid.place_tile_at(
		coord, elevation, tile_id,
		int(args.get("rotation", 0)),
		bool(args.get("starter", false)),
		bool(args.get("movement_locked", false))
	)
	var payload := {
		"coord": coord,
		"elevation": elevation,
		"tile_id": tile_id,
		"nook": args.get("nook", Vector2i.ZERO),
		"source": String(args.get("source", "player")),
	}
	events.publish("tile_placed", payload)
	if _tile_has_tag(tile_id, "water"):
		events.publish("water_added", payload)
	if _tile_has_tag(tile_id, "path"):
		events.publish("path_linked", payload)
	return {"ok": true}


func _remove_tile(args: Dictionary) -> Dictionary:
	var coord: Vector2i = args.get("coord", Vector2i.ZERO)
	var elevation := int(args.get("elevation", 0))
	var removed := grid.remove_tile_at(coord, elevation)
	return {"ok": removed != null}


## --- Features (generated nature: trees, stones, stumps) ------------------


func _place_feature(args: Dictionary) -> Dictionary:
	var coord: Vector2i = args.get("coord", Vector2i.ZERO)
	var structure_id := String(args.get("structure_id", ""))
	var definition := registries.structure(structure_id)
	if definition == null:
		return {"ok": false, "reason": "unknown_structure"}
	var elevation := int(args.get("elevation", 0))
	var socket := grid.free_socket(coord, definition.socket_type, elevation)
	if socket < 0:
		return {"ok": false, "reason": "no_socket"}
	var placed := grid.add_structure(
		coord, structure_id, socket, int(args.get("rotation", 0)), elevation
	)
	if placed == null:
		return {"ok": false, "reason": "rejected"}
	return {"ok": true, "instance_id": placed.instance_id}


## Removes a cleared feature and leaves its manifest-declared remainder
## (stump, rubble) in place. Emits feature_cleared with the host's tags so
## treasure assignment can match by tag, never by ID.
func _clear_feature(args: Dictionary) -> Dictionary:
	var instance_id := int(args.get("instance_id", 0))
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"ok": false, "reason": "missing"}
	var coord: Vector2i = found["coord"]
	var elevation := int(found["elevation"])
	var structure: WorldGrid.StructureState = found["structure"]
	var structure_id := structure.structure_id
	var socket := structure.socket_index
	var removed := grid.remove_structure(coord, instance_id, elevation)
	if removed == null:
		return {"ok": false, "reason": "blocked"}
	var leaves_id := String(args.get("leaves_structure_id", ""))
	var leaves_instance := 0
	if leaves_id != "" and registries.structure(leaves_id) != null:
		var leaves := grid.add_structure(
			coord, leaves_id, socket, removed.rotation, elevation
		)
		if leaves != null:
			leaves_instance = leaves.instance_id
	var definition := registries.structure(structure_id)
	events.publish("feature_cleared", {
		"coord": coord,
		"elevation": elevation,
		"instance_id": instance_id,
		"structure_id": structure_id,
		"tags": definition.placement_tags.duplicate() if definition != null else [],
		"leaves_structure_id": leaves_id if leaves_instance != 0 else "",
		"leaves_instance_id": leaves_instance,
		"nook": args.get("nook", Vector2i.ZERO),
		"verb": String(args.get("verb", "")),
	})
	return {"ok": true, "leaves_instance_id": leaves_instance}


## --- Planting & growth ---------------------------------------------------


func _plant_sapling(args: Dictionary) -> Dictionary:
	var coord: Vector2i = args.get("coord", Vector2i.ZERO)
	var tile := grid.top_tile_def(coord)
	if tile == null or not tile.supports_decor:
		return {"ok": false, "reason": "not_plantable"}
	var placed := _place_feature(args)
	if not bool(placed.get("ok", false)):
		return placed
	events.publish("sapling_planted", {
		"coord": coord,
		"instance_id": int(placed.get("instance_id", 0)),
		"structure_id": String(args.get("structure_id", "")),
		"nook": args.get("nook", Vector2i.ZERO),
	})
	return placed


## Replaces a growing feature with its next stage in place, preserving the
## socket. Emits sapling_matured on the final stage.
func _advance_growth(args: Dictionary) -> Dictionary:
	var instance_id := int(args.get("instance_id", 0))
	var next_id := String(args.get("structure_id", ""))
	var found := grid.find_structure(instance_id)
	if found.is_empty() or registries.structure(next_id) == null:
		return {"ok": false, "reason": "missing"}
	var coord: Vector2i = found["coord"]
	var elevation := int(found["elevation"])
	var socket := (found["structure"] as WorldGrid.StructureState).socket_index
	var rotation := (found["structure"] as WorldGrid.StructureState).rotation
	var removed := grid.remove_structure(coord, instance_id, elevation)
	if removed == null:
		return {"ok": false, "reason": "blocked"}
	# A dormant may wake into a different placement class (for example a decor
	# pillar becoming a utility well). Resolve the replacement's own socket
	# instead of reusing the old class's index.
	var next_definition := registries.structure(next_id)
	var next_socket := grid.free_socket(
		coord,
		next_definition.socket_type,
		elevation
	)
	var grown := grid.add_structure(
		coord, next_id, next_socket, rotation, elevation
	) if next_socket >= 0 else null
	if grown == null:
		# Never lose the plant: restore the previous stage.
		grid.add_structure(
			coord, removed.structure_id, socket, rotation, elevation
		)
		return {"ok": false, "reason": "rejected"}
	if bool(args.get("final_stage", false)):
		events.publish("sapling_matured", {
			"coord": coord,
			"instance_id": grown.instance_id,
			"structure_id": next_id,
			"nook": args.get("nook", Vector2i.ZERO),
		})
	return {"ok": true, "instance_id": grown.instance_id}


## --- Dormants ------------------------------------------------------------


func _wake_dormant(args: Dictionary) -> Dictionary:
	var instance_id := int(args.get("instance_id", 0))
	var woken_id := String(args.get("woken_structure_id", ""))
	if woken_id != "" and instance_id != 0:
		var advanced := _advance_growth({
			"instance_id": instance_id,
			"structure_id": woken_id,
		})
		if not bool(advanced.get("ok", false)):
			return advanced
		instance_id = int(advanced.get("instance_id", instance_id))
	events.publish("dormant_woken", {
		"nook": args.get("nook", Vector2i.ZERO),
		"dormant_id": String(args.get("dormant_id", "")),
		"instance_id": instance_id,
	})
	return {"ok": true, "instance_id": instance_id}


func _tile_has_tag(tile_id: String, tag: String) -> bool:
	var definition := registries.tile(tile_id)
	if definition == null:
		return false
	if definition.traits.has_tag(tag):
		return true
	# Fall back to well-known surface kinds so untagged legacy tiles still
	# produce correct world signals.
	if tag == "water":
		return definition.surface_kind == "water"
	return false
