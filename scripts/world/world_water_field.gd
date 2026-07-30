class_name WorldWaterField
extends RefCounted
## Infinite logical field of real water tiles around the sparse built world.
##
## A coordinate does not need a persisted WorldGrid.CellState to be a tile.
## Explicit grid cells override this field; otherwise every revealed coordinate
## resolves to the configured open-water TileDefinition. Renderers may stream
## only a finite window, while fishing, building, and future bucket tools all
## address the same deterministic tile coordinates.

const DEFAULT_WATER_TILE_ID := "tile_open_water"

signal field_changed(coord: Vector2i)

var registries: Registries
var grid: WorldGrid
var envelope: WorldEnvelope
var _removed_generated_cells: Dictionary = {}


func _init(
	regs: Registries,
	world_grid: WorldGrid,
	world_envelope: WorldEnvelope
) -> void:
	registries = regs
	grid = world_grid
	envelope = world_envelope


func ocean_tile_id() -> String:
	var configured := String(
		registries.tune("ocean_tile_id", DEFAULT_WATER_TILE_ID)
	)
	return (
		configured
		if registries.tile(configured) != null
		else DEFAULT_WATER_TILE_ID
	)


## Resolves the effective elevation-zero tile. Explicit WorldGrid state always
## wins. Pass include_hidden=true for deterministic generation outside the
## current discovery envelope; ordinary gameplay uses revealed tiles only.
func tile_id_at(coord: Vector2i, include_hidden := false) -> String:
	var explicit := grid.cell(coord)
	if explicit != null:
		return explicit.tile_id
	if _removed_generated_cells.has(coord):
		return ""
	if not include_hidden and not envelope.contains_cell(coord):
		return ""
	return ocean_tile_id()


func tile_definition_at(
	coord: Vector2i,
	include_hidden := false
) -> Defs.TileDefinition:
	var tile_id := tile_id_at(coord, include_hidden)
	return registries.tile(tile_id) if tile_id != "" else null


func source_at(coord: Vector2i, include_hidden := false) -> String:
	if grid.has_cell(coord):
		return "explicit"
	if _removed_generated_cells.has(coord):
		return "removed"
	if include_hidden or envelope.contains_cell(coord):
		return "generated"
	return "hidden"


func is_generated_water(
	coord: Vector2i,
	include_hidden := false
) -> bool:
	if grid.has_cell(coord):
		return false
	if _removed_generated_cells.has(coord):
		return false
	if not include_hidden and not envelope.contains_cell(coord):
		return false
	var definition := registries.tile(ocean_tile_id())
	return (
		definition != null
		and definition.water_cells.has("open_water")
	)


func is_explicit_open_water(coord: Vector2i) -> bool:
	var definition := grid.tile_def(coord)
	return (
		definition != null
		and definition.water_cells.has("open_water")
	)


func is_open_water(coord: Vector2i, include_hidden := false) -> bool:
	var definition := tile_definition_at(coord, include_hidden)
	return (
		definition != null
		and definition.water_cells.has("open_water")
	)


## The replacement record is intentionally source-aware. Generated water needs
## no serialized CellState and reappears when an overriding land cell is
## removed; authored water preserves its exact state for undo.
func replacement_record(
	coord: Vector2i,
	incoming_tile_id: String
) -> Dictionary:
	var incoming := registries.tile(incoming_tile_id)
	if incoming == null or incoming.water_cells.has("open_water"):
		return {}
	if grid.can_replace_open_water(coord, incoming_tile_id):
		return {
			"source": "explicit",
			"tile_id": ocean_tile_id(),
			"state": grid.cell(coord),
		}
	if (
		is_generated_water(coord)
		and grid.is_adjacent_to_world(coord)
	):
		return {
			"source": "generated",
			"tile_id": ocean_tile_id(),
		}
	return {}


## Promote a generated tile into WorldGrid only when mutable per-cell state is
## required (for example, a future dock, upgrade, or bucket operation).
func materialize(coord: Vector2i) -> WorldGrid.CellState:
	if not is_generated_water(coord):
		return grid.cell(coord) if is_explicit_open_water(coord) else null
	return grid.place_tile(coord, ocean_tile_id())


## Mutation backend reserved for the future bucket tool. Generated cells use a
## sparse tombstone; authored cells preserve their complete CellState. Nothing
## in the current build-mode pickup path calls this yet.
func remove_water_tile(coord: Vector2i) -> Dictionary:
	if is_explicit_open_water(coord):
		var state := grid.cell(coord)
		if (
			state == null
			or grid.top_elevation(coord) != 0
			or not state.structures.is_empty()
			or state.landmark_id != ""
			or state.movement_locked
		):
			return {}
		var removed := grid.remove_tile(coord)
		return {
			"source": "explicit",
			"tile_id": ocean_tile_id(),
			"state": removed,
		} if removed != null else {}
	if not is_generated_water(coord):
		return {}
	_removed_generated_cells[coord] = true
	field_changed.emit(coord)
	return {
		"source": "generated",
		"tile_id": ocean_tile_id(),
	}


func restore_water_tile(coord: Vector2i, record: Dictionary) -> bool:
	if grid.has_cell(coord):
		return false
	if record.get("source", "") == "explicit":
		var state := record.get("state") as WorldGrid.CellState
		if state == null:
			return false
		grid.restore_cell_at(coord, 0, state)
		return true
	if record.get("source", "") != "generated":
		return false
	if not _removed_generated_cells.erase(coord):
		return false
	field_changed.emit(coord)
	return true


func water_cells_in(
	rect: Rect2i,
	include_hidden := false
) -> Array[Vector2i]:
	var active := rect if include_hidden else rect.intersection(
		envelope.bounds()
	)
	var result: Array[Vector2i] = []
	for y in range(active.position.y, active.end.y):
		for x in range(active.position.x, active.end.x):
			var coord := Vector2i(x, y)
			if is_open_water(coord, include_hidden):
				result.append(coord)
	return result


func to_save_dict() -> Dictionary:
	var removed: Array = []
	for coord: Vector2i in _removed_generated_cells:
		removed.append([coord.x, coord.y])
	return {"removed_generated_cells": removed}


func from_save_dict(data: Dictionary) -> void:
	_removed_generated_cells.clear()
	for raw: Variant in data.get("removed_generated_cells", []):
		if raw is Array and raw.size() >= 2:
			_removed_generated_cells[
				Vector2i(int(raw[0]), int(raw[1]))
			] = true
	field_changed.emit(Vector2i.ZERO)


func reset() -> void:
	if _removed_generated_cells.is_empty():
		return
	_removed_generated_cells.clear()
	field_changed.emit(Vector2i.ZERO)


func runtime_manifest() -> Dictionary:
	return {
		"tile_id": ocean_tile_id(),
		"coordinate_model": "infinite_generated_tile_field",
		"visible_bounds": envelope.bounds(),
		"explicit_overrides": grid.cells.size(),
		"removed_generated_cells": _removed_generated_cells.size(),
		"persistence": "explicit_overrides_plus_sparse_tombstones",
		"future_mutation": "bucket_backend_ready",
	}
