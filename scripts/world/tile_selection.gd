class_name TileSelection
extends RefCounted
## Rectangular multi-tile selection, and moving the whole set at once.
##
## Modelled on how Garden Galaxy does it: the pointer drags an inclusive
## rectangle of grid coords, and every coord in it contributes its ENTIRE
## column -- ground tile, everything stacked on top, and every structure those
## cells carry. You never select "the tile at elevation 2"; a coord is in or it
## is out. That is what makes a selection behave like one object rather than a
## pile of independently-moving parts.
##
## The grid already had the primitives for this (detach_tile_stack /
## can_restore_tile_stack / restore_tile_stack); what this adds is the set
## semantics and the move, which has one subtlety worth stating -- see move_by.

const BASE_ELEVATION := 0

enum State {
	IDLE,      ## nothing selected
	DRAGGING,  ## the marquee is being dragged out
	SETTLED,   ## a selection exists and can be moved
}

var grid: WorldGrid

var _state: int = State.IDLE
var _anchor := Vector2i.ZERO
var _cursor := Vector2i.ZERO
var _coords: Array[Vector2i] = []


func _init(world_grid: WorldGrid) -> void:
	grid = world_grid


func state() -> int:
	return _state


func is_dragging() -> bool:
	return _state == State.DRAGGING


func has_selection() -> bool:
	return _state == State.SETTLED and not _coords.is_empty()


func coords() -> Array[Vector2i]:
	return _coords.duplicate()


func size() -> int:
	return _coords.size()


func contains(coord: Vector2i) -> bool:
	return _coords.has(coord)


## The inclusive coord rectangle the marquee currently spans, occupied or not.
func rectangle() -> Rect2i:
	var minimum := Vector2i(mini(_anchor.x, _cursor.x), mini(_anchor.y, _cursor.y))
	var maximum := Vector2i(maxi(_anchor.x, _cursor.x), maxi(_anchor.y, _cursor.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func begin(coord: Vector2i) -> void:
	_state = State.DRAGGING
	_anchor = coord
	_cursor = coord
	_refresh_coords()


## Returns whether the selected set actually changed, so callers can skip
## redecorating. Pointer motion fires many times per cell crossed, and the
## overwhelming majority of those events land on the cell already under the
## cursor.
func drag_to(coord: Vector2i) -> bool:
	if _state != State.DRAGGING:
		return false
	if coord == _cursor:
		return false
	_cursor = coord
	_refresh_coords()
	return true


## Settles the marquee. Returns whether anything was actually caught: dragging
## across empty space selects nothing rather than leaving an empty selection
## that swallows the next click.
func end_drag() -> bool:
	if _state != State.DRAGGING:
		return has_selection()
	_state = State.SETTLED if not _coords.is_empty() else State.IDLE
	return has_selection()


func clear() -> void:
	_state = State.IDLE
	_coords.clear()


## Every occupied coord inside the rectangle. A coord counts as occupied when it
## has a ground cell, since that is what anchors the column.
func _refresh_coords() -> void:
	_coords.clear()
	if grid == null:
		return
	var area := rectangle()
	for x in range(area.position.x, area.position.x + area.size.x):
		for y in range(area.position.y, area.position.y + area.size.y):
			var coord := Vector2i(x, y)
			if grid.has_cell_at(coord, BASE_ELEVATION):
				_coords.append(coord)


## Slides the whole selection by a grid delta, carrying every stacked tile and
## every structure. Returns false and changes nothing if the destination will
## not take it.
##
## The order matters and is the whole reason this is not a loop over
## move_tile_at: every source column is detached BEFORE any destination is
## validated. Validating first would see the selection's own tiles still
## occupying the cells it is about to vacate, so nudging a selection one step in
## any direction -- the most common move there is -- would always be rejected.
func move_by(delta: Vector2i) -> bool:
	if _coords.is_empty():
		return false
	if delta == Vector2i.ZERO:
		return true

	var detached := {}
	for coord: Vector2i in _coords:
		var stack := grid.detach_tile_stack(coord, BASE_ELEVATION)
		if not stack.is_empty():
			detached[coord] = stack

	var accepted := not detached.is_empty()
	for coord: Vector2i in detached:
		if not grid.can_restore_tile_stack(
			coord + delta, BASE_ELEVATION, detached[coord]
		):
			accepted = false
			break

	# Restoring is unvalidated on purpose. On the accepted path every
	# destination was just checked; on the rejected path the cells are the ones
	# these very stacks came from, and re-checking them would be the same
	# occupancy trap in reverse.
	var moved: Array[Vector2i] = []
	for coord: Vector2i in detached:
		var destination: Vector2i = coord + delta if accepted else coord
		grid.restore_tile_stack(
			destination, BASE_ELEVATION, detached[coord], false
		)
		if accepted:
			moved.append(destination)
	if accepted:
		_coords = moved
		_anchor += delta
		_cursor += delta
	return accepted


## Whether the selection could move by a delta, without moving it. Used to keep
## a drag preview honest instead of letting it settle somewhere illegal.
func can_move_by(delta: Vector2i) -> bool:
	if _coords.is_empty():
		return false
	if delta == Vector2i.ZERO:
		return true
	var selected := {}
	for coord: Vector2i in _coords:
		selected[coord] = true
	for coord: Vector2i in _coords:
		var destination: Vector2i = coord + delta
		# A destination still inside the selection is being vacated by this same
		# move, so it is free even though the grid still reports it occupied.
		if selected.has(destination):
			continue
		var stack := grid.tile_stack_from(coord, BASE_ELEVATION)
		if stack.is_empty():
			return false
		if not grid.can_restore_tile_stack(destination, BASE_ELEVATION, stack):
			return false
	return true
