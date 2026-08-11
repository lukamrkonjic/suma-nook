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
signal terrain_cell_landed(coord: Vector2i, cell: Vector2i)
signal reveal_finished(coord: Vector2i)

const REVEAL_REST_POSITION_META := &"nook_reveal_rest_position"

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
	var land_locals: Array[Vector2i] = []
	var water_locals: Array[Vector2i] = []
	var seen_land := {}
	var seen_water := {}
	for tile: Dictionary in plan.tiles:
		var local: Vector2i = tile["local"]
		var definition := core.registries.tile(String(tile.get("tile_id", "")))
		var is_water := (
			definition != null
			and definition.render_profile == "continuous_water"
		)
		if is_water and not seen_water.has(local):
			seen_water[local] = true
			water_locals.append(local)
		elif not is_water and not seen_land.has(local):
			seen_land[local] = true
			land_locals.append(local)
	var seam := _seam_side(coord)
	var wave_origin := NookRevealTimeline.wave_origin(
		world.nook_size, seam, config
	)
	var entries := NookRevealTimeline.tile_wave(
		land_locals, wave_origin, config
	)
	var drop_height := float(config.get("tile_drop_height", 6.0))
	var drop_seconds := maxf(
		0.05, float(config.get("tile_drop_seconds", 0.34))
	)
	var overshoot := float(config.get("tile_overshoot", 0.08))
	var delays := {}
	for entry: Dictionary in entries:
		delays[entry["local"] as Vector2i] = float(entry["delay"])
	var animated := 0
	var land_finish := 0.0
	for tile: Dictionary in plan.tiles:
		var local: Vector2i = tile["local"]
		var cell: Vector2i = origin_cell + local
		var elevation := int(tile.get("elevation", 0))
		var definition := core.registries.tile(String(tile.get("tile_id", "")))
		if definition != null \
			and definition.render_profile == "continuous_water":
			continue
		# Raised layers wait for their support to finish landing.
		var landing_seconds := drop_seconds * 1.35
		var delay := (
			float(delays.get(local, 0.0))
			+ landing_seconds * elevation
		)
		var holder := renderer.cell_holder(cell, elevation)
		var tile_animated := false
		if holder != null:
			_drop_tile(
				holder,
				core.grid.cell_to_world(cell, elevation),
				delay,
				drop_height,
				drop_seconds,
				overshoot
			)
			tile_animated = true
		else:
			tile_animated = renderer.animate_scalable_nook_tile(
				cell,
				elevation,
				delay,
				drop_height,
				drop_seconds,
				overshoot
			)
		if not tile_animated:
			continue
		if elevation > 0:
			# The support keeps its complete authored top for the entire fall.
			# Only first contact may begin the covered-form cross-fade; before
			# that instant a missing cap exposes an ugly hollow block.
			_cover_support_surface_after(
				cell,
				elevation - 1,
				delay + drop_seconds
			)
		animated += 1
		land_finish = maxf(land_finish, delay + landing_seconds)
		# The arrival blueprint is replaced cell-by-cell at first contact. Raised
		# layers do not own another footprint marker, so only the base landing
		# consumes it.
		if elevation == 0:
			_emit_terrain_cell_landed_after(
				coord, cell, delay + drop_seconds
			)

	# Water is a joined sheet. Its bed and surface remain below the world until
	# the complete land wave has settled, then rise as one fluid phase.
	var water_start := land_finish + maxf(
		0.0, float(config.get("water_phase_delay", 0.08))
	)
	var water_depth := maxf(
		0.0, float(config.get("water_rise_depth", 1.35))
	)
	var water_seconds := maxf(
		0.05, float(config.get("water_rise_seconds", 0.42))
	)
	var water_overshoot := maxf(
		0.0, float(config.get("water_overshoot", 0.035))
	)
	var water_cells: Array[Vector2i] = []
	for local: Vector2i in water_locals:
		var cell := origin_cell + local
		water_cells.append(cell)
		var holder := renderer.cell_holder(cell, 0)
		var water_animated := false
		if holder != null:
			water_animated = _rise_water_tile(
				holder,
				core.grid.cell_to_world(cell, 0),
				water_start,
				water_depth,
				water_seconds,
				water_overshoot
			)
		else:
			water_animated = renderer.animate_scalable_nook_water_tile(
				cell,
				0,
				water_start,
				water_depth,
				water_seconds,
				water_overshoot
			)
		if water_animated:
			animated += 1
			_emit_terrain_cell_landed_after(
				coord, cell, water_start + water_seconds
			)
	if renderer.animate_nook_water_surface(
		water_cells,
		water_start,
		water_depth,
		water_seconds,
		water_overshoot
	):
		animated += 1
	var water_finish := (
		water_start + water_seconds * 1.28
		if not water_cells.is_empty()
		else land_finish
	)

	# Models ripple outward after the terrain, with a shorter weighted drop and
	# a small squash at contact so walls, rocks, and trees visibly plop in.
	var model_locals: Array[Vector2i] = []
	var seen_models := {}
	for feature: Dictionary in plan.features:
		var local: Vector2i = feature["local"]
		if not seen_models.has(local):
			seen_models[local] = true
			model_locals.append(local)
	var model_entries := NookRevealTimeline.tile_wave(
		model_locals, wave_origin, config
	)
	var model_delays := {}
	for entry: Dictionary in model_entries:
		model_delays[entry["local"] as Vector2i] = float(entry["delay"])
	var model_start := land_finish + maxf(
		0.0, float(config.get("model_phase_delay", 0.12))
	)
	var model_height := maxf(
		0.0, float(config.get("model_drop_height", 1.45))
	)
	var model_seconds := maxf(
		0.05, float(config.get("model_drop_seconds", 0.28))
	)
	var model_overshoot := maxf(
		0.0, float(config.get("model_overshoot", 0.075))
	)
	var model_finish := land_finish
	for feature: Dictionary in plan.features:
		var instance_id := int(feature.get("instance_id", 0))
		if instance_id <= 0:
			continue
		var local: Vector2i = feature["local"]
		var delay := model_start + float(model_delays.get(local, 0.0))
		var model_animated := false
		var visual := renderer.structure_node(instance_id)
		if visual != null:
			model_animated = _drop_feature(
				visual,
				delay,
				model_height,
				model_seconds,
				model_overshoot
			)
		else:
			model_animated = renderer.animate_scalable_nook_structure(
				instance_id,
				delay,
				model_height,
				model_seconds,
				model_overshoot
			)
		if not model_animated:
			continue
		animated += 1
		model_finish = maxf(
			model_finish,
			delay + model_seconds * 1.34
		)

	var duration := maxf(land_finish, maxf(water_finish, model_finish))
	# Keep staging authoritative for the whole presentation. Settled boundary
	# tiles deliberately treat staged neighbours as void, so their rim, side
	# wall, water shoreline, and edge blocker cannot react before land exists.
	reveal_started.emit(coord, duration)
	if animated == 0:
		renderer.release_nook_reveal_staging(origin_cell, plan)
		await renderer.finalize_nook_reveal_topology_async(origin_cell, plan)
		reveal_finished.emit(coord)
		return
	var finish := get_tree().create_timer(duration + 0.25)
	finish.timeout.connect(
		_finish_reveal.bind(coord, origin_cell, plan)
	)


func _finish_reveal(
	coord: Vector2i,
	origin_cell: Vector2i,
	plan: NookGenerator.NookPlan
) -> void:
	# Final authority pass: interrupted presentation can never alter seating.
	_settle_plan_tiles(origin_cell, plan)
	renderer.release_nook_reveal_staging(origin_cell, plan)
	await renderer.finalize_nook_reveal_topology_async(origin_cell, plan)
	reveal_finished.emit(coord)


func _emit_terrain_cell_landed_after(
	coord: Vector2i,
	cell: Vector2i,
	delay: float
) -> void:
	var timer := get_tree().create_timer(maxf(0.0, delay))
	timer.timeout.connect(func():
		terrain_cell_landed.emit(coord, cell)
	)


func _cover_support_surface_after(
	cell: Vector2i,
	elevation: int,
	delay: float
) -> void:
	var timer := get_tree().create_timer(maxf(0.0, delay))
	timer.timeout.connect(func():
		renderer.begin_reveal_surface_cover(cell, elevation)
	)


func _drop_tile(
	holder: Node3D,
	authoritative_position: Vector3,
	delay: float,
	drop_height: float,
	drop_seconds: float,
	overshoot: float
) -> void:
	if holder.get_child_count() == 0:
		return
	var visual := holder.get_child(0) as Node3D
	if visual == null:
		return

	# Generated cells have already started the ordinary placement-settle
	# tween when nook_revealed is emitted. That tween temporarily raises the
	# holder by 0.1 m. The old reveal captured that temporary offset as its
	# landing Y and animated the same property, so some generated tiles stayed
	# floating until a pickup/rebuild corrected them.
	#
	# The holder is authoritative. Animate only its disposable visual child so
	# overlapping presentation tweens can never alter the seating plane.
	holder.position = authoritative_position
	holder.visible = true
	var target_position := visual.position
	visual.set_meta(REVEAL_REST_POSITION_META, target_position)
	visual.position = target_position + Vector3.UP * drop_height
	visual.visible = false
	var tween := visual.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(func():
		if is_instance_valid(visual):
			visual.visible = true
	)
	# Drop with a slight overshoot bounce: down past the target, then a
	# short return — reads as weight without a physics body.
	tween.tween_property(
		visual, "position:y", target_position.y - overshoot, drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(
		visual, "position:y", target_position.y, drop_seconds * 0.35
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(
		_settle_reveal_tile.bind(holder, authoritative_position, visual)
	)


func _rise_water_tile(
	holder: Node3D,
	authoritative_position: Vector3,
	delay: float,
	rise_depth: float,
	rise_seconds: float,
	overshoot: float
) -> bool:
	if holder.get_child_count() == 0:
		return false
	var visual := holder.get_child(0) as Node3D
	if visual == null:
		return false
	holder.position = authoritative_position
	holder.visible = true
	var target_position := visual.position
	visual.set_meta(REVEAL_REST_POSITION_META, target_position)
	visual.position = target_position + Vector3.DOWN * rise_depth
	visual.visible = false
	var tween := visual.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(func():
		if is_instance_valid(visual):
			visual.visible = true
	)
	tween.tween_property(
		visual, "position:y", target_position.y + overshoot, rise_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		visual, "position:y", target_position.y, rise_seconds * 0.28
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(
		_settle_reveal_tile.bind(holder, authoritative_position, visual)
	)
	return true


func _settle_reveal_tile(
	holder: Node3D,
	authoritative_position: Vector3,
	visual: Node3D
) -> void:
	if is_instance_valid(holder):
		holder.position = authoritative_position
		holder.visible = true
	if not is_instance_valid(visual):
		return
	if visual.has_meta(REVEAL_REST_POSITION_META):
		visual.position = visual.get_meta(REVEAL_REST_POSITION_META) as Vector3
		visual.remove_meta(REVEAL_REST_POSITION_META)
	visual.visible = true


func _settle_plan_tiles(
	origin_cell: Vector2i,
	plan: NookGenerator.NookPlan
) -> void:
	for tile: Dictionary in plan.tiles:
		var cell := origin_cell + (tile["local"] as Vector2i)
		var elevation := int(tile.get("elevation", 0))
		var holder := renderer.cell_holder(cell, elevation)
		if holder == null:
			continue
		var visual: Node3D = null
		if holder.get_child_count() > 0:
			visual = holder.get_child(0) as Node3D
		_settle_reveal_tile(
			holder,
			core.grid.cell_to_world(cell, elevation),
			visual
		)


func _drop_feature(
	visual: Node3D,
	delay: float,
	drop_height: float,
	drop_seconds: float,
	overshoot: float
) -> bool:
	if visual == null or not is_instance_valid(visual):
		return false
	var target_position := visual.position
	var target_scale := visual.scale
	visual.position = target_position + Vector3.UP * drop_height
	visual.scale = target_scale * 0.88
	visual.visible = false
	var movement := visual.create_tween()
	movement.tween_interval(maxf(0.0, delay))
	movement.tween_callback(func():
		if is_instance_valid(visual):
			visual.visible = true
	)
	movement.tween_property(
		visual, "position:y", target_position.y - overshoot, drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	movement.tween_property(
		visual, "position:y", target_position.y, drop_seconds * 0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	movement.tween_callback(func():
		if is_instance_valid(visual):
			visual.position = target_position
			visual.scale = target_scale
			visual.visible = true
	)
	var squash := visual.create_tween()
	squash.tween_interval(maxf(0.0, delay))
	squash.tween_property(
		visual, "scale", target_scale * 1.035, drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	squash.tween_property(
		visual, "scale", target_scale, drop_seconds * 0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return true


## The side of this chunk that touches an already-revealed neighbour, so
## the wave sweeps outward from the seam the player expanded across.
func _seam_side(coord: Vector2i) -> Vector2i:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor := core.nooks.world.nook(coord + offset)
		if neighbor != null \
			and neighbor.revealed_unix < core.nooks.world.nook(coord).revealed_unix:
			return offset
	return Vector2i.ZERO
