@tool
class_name GrassFieldManager
extends Node3D
## Owns the grass field: which cells are grass, how they divide into render
## chunks, which chunks need rebuilding, and how much detail each one draws.
##
## The division into chunks is a PERFORMANCE decision and must stay invisible.
## Every chunk therefore receives the whole region's cell set rather than its own
## slice, so a chunk asking "is the cell past my edge grass?" gets a truthful
## answer and does not wall itself in. Chunk boundaries are not art boundaries
## and nothing here is allowed to make them one.
##
## Rebuilds are selective on purpose. A moved prop touches one clearance radius,
## which touches one or two chunks; regenerating the entire field for that would
## make prop placement feel like it stalls the editor, and stalling is what
## makes people stop moving things around.

## Distance beyond the LOD bands at which a chunk is not considered at all.
## Chunks past this keep their last state rather than thrash near the horizon.
const LOD_UPDATE_INTERVAL := 0.25


@export var profile: GrassFieldProfile:
	set(value):
		profile = value
		if is_inside_tree():
			rebuild()

## Where GrassClearance3D markers are searched for. Defaults to the scene root,
## which is what you want when props are children of the world rather than of
## the grass.
@export var clearance_root: NodePath

@export_group("Detail")
## Chunk-level LOD. Off means every chunk draws its full carpet, which is the
## right setting for validation renders and the wrong one for gameplay.
@export var lod_enabled := true
## Camera used for LOD distance. Empty means the viewport's active camera, which
## is correct in-game and in most editor previews.
@export var lod_camera: NodePath

@export_group("Editor Actions")
@export var rebuild_action := false:
	set(value):
		if value:
			rebuild()
		rebuild_action = false
@export var randomize_seed_action := false:
	set(value):
		if value and profile != null:
			profile.random_seed = randi() % 100000
			rebuild()
		randomize_seed_action = false
@export var print_statistics_action := false:
	set(value):
		if value:
			print(JSON.stringify(statistics(), "  "))
		print_statistics_action = false

@export_group("Debug View")
@export var show_chunk_bounds := false:
	set(value):
		show_chunk_bounds = value
		for chunk in _chunks.values():
			(chunk as GrassRenderChunk3D).show_chunk_bounds = value
@export var show_clearance := false:
	set(value):
		show_clearance = value
		for chunk in _chunks.values():
			(chunk as GrassRenderChunk3D).show_clearance = value


## Vector2i -> true. The logical grass footprint; the ONLY thing the grid is
## allowed to decide.
var _grass_cells: Dictionary = {}
## Vector2i (chunk coord) -> GrassRenderChunk3D
var _chunks: Dictionary = {}
var _clearances: Array[Dictionary] = []
var _clearance_signature := ""
var _lod_timer := 0.0


func _ready() -> void:
	if profile == null:
		profile = GrassFieldProfile.new()
	set_process(not Engine.is_editor_hint() or lod_enabled)
	if not _grass_cells.is_empty():
		rebuild()


# --- footprint ---------------------------------------------------------------


## Replaces the field's footprint. Cells are logical gameplay cells in the same
## coordinate space the rest of Suma uses: cell (x, y) is centred at
## (x * tile_size, y * tile_size).
func set_grass_cells(cells: Array) -> void:
	_grass_cells.clear()
	for cell: Vector2i in cells:
		_grass_cells[cell] = true
	rebuild()


func grass_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _grass_cells:
		result.append(cell)
	return result


## Connected components of the footprint. An island separated from the mainland
## has its own exposed rim all the way round, and knowing which cells belong to
## which island is what lets the skirt be right without special-casing anything.
func regions() -> Array:
	var seen: Dictionary = {}
	var found: Array = []
	for start: Vector2i in _grass_cells:
		if seen.has(start):
			continue
		var region: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			region.append(cell)
			for direction in GrassRenderChunk3D.DIRECTIONS:
				var neighbour: Vector2i = cell + direction
				if _grass_cells.has(neighbour) and not seen.has(neighbour):
					seen[neighbour] = true
					queue.append(neighbour)
		found.append(region)
	return found


# --- rebuild -----------------------------------------------------------------


func rebuild() -> void:
	if profile == null:
		return
	_gather_clearances()
	var wanted := _wanted_chunks()
	for coord: Vector2i in _chunks.keys():
		if not wanted.has(coord):
			(_chunks[coord] as Node).queue_free()
			_chunks.erase(coord)
	for coord: Vector2i in wanted:
		_build_chunk(coord)


## Rebuilds only the chunks a world-space circle touches. This is the path a
## moved prop takes, and keeping it narrow is what makes placement feel instant.
func rebuild_around(world_xz: Vector2, radius: float) -> void:
	if profile == null:
		return
	_gather_clearances()
	var reach := radius + profile.chunk_size_in_metres()
	for coord: Vector2i in _chunks:
		var chunk := _chunks[coord] as GrassRenderChunk3D
		if _chunk_centre(coord).distance_to(world_xz) > reach:
			continue
		chunk.configure(profile, coord, _grass_cells, _clearances)
		chunk.rebuild_all()


func _wanted_chunks() -> Dictionary:
	var span: int = maxi(profile.chunk_size_in_tiles, 1)
	var wanted: Dictionary = {}
	for cell: Vector2i in _grass_cells:
		wanted[GrassRenderChunk3D._chunk_of(cell, span)] = true
	return wanted


func _build_chunk(coord: Vector2i) -> void:
	var chunk: GrassRenderChunk3D = _chunks.get(coord)
	if chunk == null:
		chunk = GrassRenderChunk3D.new()
		chunk.name = "GrassRenderChunk_%d_%d" % [coord.x, coord.y]
		add_child(chunk)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			chunk.owner = get_tree().edited_scene_root
		_chunks[coord] = chunk
	# configure() before rebuild: the chunk needs the region's cells in hand
	# before it can decide where its rim is.
	chunk.configure(profile, coord, _grass_cells, _clearances)
	chunk.show_chunk_bounds = show_chunk_bounds
	chunk.show_clearance = show_clearance
	chunk.rebuild_all()


func _chunk_centre(coord: Vector2i) -> Vector2:
	var size := profile.chunk_size_in_metres()
	return Vector2(coord) * size + Vector2.ONE * size * 0.5 - Vector2.ONE * profile.tile_size * 0.5


# --- clearances --------------------------------------------------------------


## Snapshots every marker into plain data. Chunks then evaluate thousands of
## density samples against an Array of Dictionaries instead of walking the scene
## tree, which is the difference between a rebuild that is imperceptible and one
## that hitches.
func _gather_clearances() -> void:
	_clearances.clear()
	var root: Node = get_node_or_null(clearance_root)
	if root == null:
		root = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root == null:
		root = self
	for node in root.find_children("*", "GrassClearance3D", true, false):
		var marker := node as GrassClearance3D
		var origin := marker.global_position
		_clearances.append({
			"position": Vector2(origin.x, origin.z),
			"radius": marker.radius,
			"retain": marker.retain_dense_carpet,
			"softness": marker.edge_softness,
		})
	_clearance_signature = JSON.stringify(_clearances)


## True when a marker has been added, removed or moved since the last gather.
## Cheap enough to poll, which beats asking every prop in the game to remember
## to notify the grass.
func clearances_changed() -> bool:
	var previous := _clearance_signature
	_gather_clearances()
	return previous != _clearance_signature


# --- level of detail ---------------------------------------------------------


func _process(delta: float) -> void:
	if not lod_enabled or profile == null:
		return
	_lod_timer -= delta
	if _lod_timer > 0.0:
		return
	_lod_timer = LOD_UPDATE_INTERVAL
	var camera := _resolve_camera()
	if camera == null:
		return
	var eye := camera.global_position
	var eye_xz := Vector2(eye.x, eye.z)
	for coord: Vector2i in _chunks:
		var chunk := _chunks[coord] as GrassRenderChunk3D
		chunk.set_detail_state(_state_for(chunk, _chunk_centre(coord).distance_to(eye_xz)))


func _resolve_camera() -> Camera3D:
	var explicit := get_node_or_null(lod_camera) as Camera3D
	if explicit != null:
		return explicit
	return get_viewport().get_camera_3d() if get_viewport() != null else null


## Hysteresis, not thresholds. The bands overlap — a chunk only leaves NEAR past
## 12 m but only returns to it inside 10 m — so a camera hovering on a boundary
## cannot flicker a whole chunk of carpet in and out, which is far more
## noticeable than the detail difference itself.
func _state_for(chunk: GrassRenderChunk3D, distance: float) -> GrassRenderChunk3D.DetailState:
	var current := chunk._detail_state
	match current:
		GrassRenderChunk3D.DetailState.NEAR:
			if distance > profile.near_visibility_end:
				return GrassRenderChunk3D.DetailState.MID
		GrassRenderChunk3D.DetailState.MID:
			if distance < profile.mid_visibility_begin:
				return GrassRenderChunk3D.DetailState.NEAR
			if distance > profile.mid_visibility_end:
				return GrassRenderChunk3D.DetailState.FAR
		GrassRenderChunk3D.DetailState.FAR:
			if distance < profile.far_visibility_begin:
				return GrassRenderChunk3D.DetailState.MID
	return current


# --- reporting ---------------------------------------------------------------


func chunk_at(coord: Vector2i) -> GrassRenderChunk3D:
	return _chunks.get(coord)


func chunks() -> Array:
	return _chunks.values()


func statistics() -> Dictionary:
	var per_chunk: Array = []
	var totals := {
		"surface_triangles": 0,
		"skirt_triangles": 0,
		"dense_instances": 0,
		"flexible_instances": 0,
		"dense_triangles": 0,
		"flexible_triangles": 0,
		"total_triangles": 0,
	}
	for coord: Vector2i in _chunks:
		var entry: Dictionary = (_chunks[coord] as GrassRenderChunk3D).statistics()
		per_chunk.append(entry)
		for key: String in totals:
			totals[key] = int(totals[key]) + int(entry.get(key, 0))
	return {
		"cells": _grass_cells.size(),
		"chunks": _chunks.size(),
		"regions": regions().size(),
		"clearances": _clearances.size(),
		"totals": totals,
		"per_chunk": per_chunk,
	}
