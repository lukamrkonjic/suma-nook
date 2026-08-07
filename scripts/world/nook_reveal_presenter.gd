class_name NookRevealPresenter
extends Node
## The signature moment: terrain falls in as a radial wave from the
## connecting seam and features pop after the wavefront passes. Presentation
## only — every cell already committed through the command layer before this
## starts; skipping or interrupting the animation can never lose state.
##
## Timings live in data/reveal.json (via NookRevealTimeline); there is no
## animation constant in this file worth tuning.

signal reveal_started(coord: Vector2i, duration: float)
signal reveal_finished(coord: Vector2i)

var core: GameCore
var renderer: WorldRenderer


func setup(
	game_core: GameCore,
	world_renderer: WorldRenderer
) -> void:
	core = game_core
	renderer = world_renderer
	core.nooks.nook_revealed.connect(_on_nook_revealed)


func _on_nook_revealed(coord: Vector2i, plan: NookGenerator.NookPlan) -> void:
	var config := core.registries.reveal_config
	var world := core.nooks.world
	var origin_cell := world.chunk_origin(coord)
	var locals: Array[Vector2i] = []
	var seen_locals: Dictionary = {}
	for tile: Dictionary in plan.tiles:
		var local: Vector2i = tile["local"]
		if not seen_locals.has(local):
			seen_locals[local] = true
			locals.append(local)
	var seam := _seam_side(coord)
	var wave_origin := NookRevealTimeline.wave_origin(
		world.nook_size, seam, config
	)
	var entries := NookRevealTimeline.tile_wave(locals, wave_origin, config)
	var duration := NookRevealTimeline.wave_duration(entries, config)
	var drop_height := float(config.get("tile_drop_height", 6.0))
	var drop_seconds := maxf(0.05, float(config.get("tile_drop_seconds", 0.34)))
	var overshoot := float(config.get("tile_overshoot", 0.08))
	var delays: Dictionary = {}
	for entry: Dictionary in entries:
		delays[entry["local"] as Vector2i] = float(entry["delay"])
	var animated := 0
	for tile: Dictionary in plan.tiles:
		var local: Vector2i = tile["local"]
		var cell: Vector2i = origin_cell + local
		var elevation := int(tile.get("elevation", 0))
		var holder := renderer.cell_holder(cell, elevation)
		if holder == null:
			continue
		animated += 1
		# Relief caps land a beat after their ground, stacking the wave.
		var delay := float(delays.get(local, 0.0)) + 0.08 * elevation
		_drop_tile(holder, delay, drop_height, drop_seconds, overshoot)
		if elevation == maxi(0, core.grid.top_elevation(cell)):
			_pop_features(
				cell,
				delay + drop_seconds
					+ float(config.get("feature_pop_delay", 0.12)),
				maxf(0.05, float(config.get("feature_pop_seconds", 0.22)))
			)
	reveal_started.emit(coord, duration)
	if animated == 0:
		reveal_finished.emit(coord)
		return
	var finish := get_tree().create_timer(duration + 0.25)
	finish.timeout.connect(func(): reveal_finished.emit(coord))


func _drop_tile(
	holder: Node3D,
	delay: float,
	drop_height: float,
	drop_seconds: float,
	overshoot: float
) -> void:
	var target_y := holder.position.y
	holder.position.y = target_y + drop_height
	holder.visible = false
	var tween := holder.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(func(): holder.visible = true)
	# Drop with a slight overshoot bounce: down past the target, then a
	# short return — reads as weight without a physics body.
	tween.tween_property(
		holder, "position:y", target_y - overshoot, drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(
		holder, "position:y", target_y, drop_seconds * 0.35
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop_features(cell: Vector2i, delay: float, pop_seconds: float) -> void:
	var state := core.grid.top_cell(cell)
	if state == null:
		return
	for structure: WorldGrid.StructureState in state.structures:
		var visual := renderer.structure_node(structure.instance_id)
		if visual == null:
			continue
		var target_scale := visual.scale
		visual.scale = Vector3.ONE * 0.001
		var tween := visual.create_tween()
		tween.tween_interval(maxf(0.0, delay))
		tween.tween_property(
			visual, "scale", target_scale, pop_seconds
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The side of this chunk that touches an already-revealed neighbour, so
## the wave sweeps outward from the seam the player expanded across.
func _seam_side(coord: Vector2i) -> Vector2i:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor := core.nooks.world.nook(coord + offset)
		if neighbor != null \
			and neighbor.revealed_unix < core.nooks.world.nook(coord).revealed_unix:
			return offset
	return Vector2i.ZERO
