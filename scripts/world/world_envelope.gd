class_name WorldEnvelope
extends RefCounted
## Derived, non-persistent limit around the sparse constructed world.
##
## The envelope controls discovery, camera travel, and renderer streaming. It
## deliberately does not decide what an empty coordinate contains; that is the
## responsibility of WorldWaterField.

signal bounds_changed(bounds: Rect2i)

var registries: Registries
var grid: WorldGrid

var _dirty := true
var _constructed_bounds := Rect2i()
var _envelope_bounds := Rect2i()


func _init(regs: Registries, world_grid: WorldGrid) -> void:
	registries = regs
	grid = world_grid
	var owner_ref: WeakRef = weakref(self)
	grid.grid_changed.connect(func() -> void:
		var owner := owner_ref.get_ref() as WorldEnvelope
		if owner != null:
			owner.invalidate()
	)


func invalidate() -> void:
	_dirty = true


func refresh() -> bool:
	if not _dirty:
		return false
	_dirty = false
	var previous := _envelope_bounds
	_constructed_bounds = _derive_constructed_bounds()
	_envelope_bounds = _constructed_bounds.grow(margin_cells())
	if _envelope_bounds != previous:
		bounds_changed.emit(_envelope_bounds)
		return true
	return false


func constructed_bounds() -> Rect2i:
	refresh()
	return _constructed_bounds


func bounds() -> Rect2i:
	refresh()
	return _envelope_bounds


func margin_cells() -> int:
	return maxi(2, registries.tunei("ocean_margin_cells", 20))


func fade_cells() -> int:
	return clampi(
		registries.tunei("ocean_fade_cells", 8),
		1,
		margin_cells() - 1
	)


func camera_inset_cells() -> int:
	return clampi(
		registries.tunei("ocean_camera_inset_cells", 3),
		0,
		margin_cells() - 1
	)


func contains_cell(coord: Vector2i, inset := 0) -> bool:
	var active := _inset_bounds(bounds(), inset)
	return active.has_point(coord)


func clamp_cell(coord: Vector2i, inset := 0) -> Vector2i:
	var active := _inset_bounds(bounds(), inset)
	var last := active.end - Vector2i.ONE
	return Vector2i(
		clampi(coord.x, active.position.x, last.x),
		clampi(coord.y, active.position.y, last.y)
	)


func contains_world_position(position: Vector3, inset_cells := 0) -> bool:
	var coord := grid.world_to_cell(position)
	return contains_cell(coord, inset_cells)


func clamp_world_position(position: Vector3, inset_cells := 0) -> Vector3:
	var active := world_bounds(inset_cells)
	var last := active.end
	return Vector3(
		clampf(position.x, active.position.x, last.x),
		position.y,
		clampf(position.z, active.position.y, last.y)
	)


## World-space rectangle at cell outer edges. Rect2.y maps to world Z.
func world_bounds(inset_cells := 0) -> Rect2:
	var active := _inset_bounds(bounds(), inset_cells)
	var tile_size := grid.tile_size
	return Rect2(
		Vector2(
			(active.position.x - 0.5) * tile_size,
			(active.position.y - 0.5) * tile_size
		),
		Vector2(active.size.x, active.size.y) * tile_size
	)


func hidden_generation_bounds() -> Rect2i:
	var ring := maxi(
		1,
		registries.tunei("ocean_hidden_generation_ring_cells", 12)
	)
	return bounds().grow(ring)


func runtime_manifest() -> Dictionary:
	return {
		"constructed_bounds": constructed_bounds(),
		"envelope_bounds": bounds(),
		"world_bounds": world_bounds(),
		"margin_cells": margin_cells(),
		"fade_cells": fade_cells(),
		"camera_inset_cells": camera_inset_cells(),
		"hidden_generation_bounds": hidden_generation_bounds(),
		"persistence": "derived_sparse_grid",
	}


func _derive_constructed_bounds() -> Rect2i:
	if grid.cells.is_empty():
		return Rect2i(grid.home_cell, Vector2i.ONE)
	return grid.bounds()


func _inset_bounds(source: Rect2i, amount: int) -> Rect2i:
	var safe_amount := maxi(0, amount)
	var maximum := maxi(0, (mini(source.size.x, source.size.y) - 1) / 2)
	safe_amount = mini(safe_amount, maximum)
	return source.grow(-safe_amount)
