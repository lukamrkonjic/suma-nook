class_name NookRevealPresenter
extends Node
## The signature moment: terrain falls in as a radial wave from the
## connecting seam, features pop after the wavefront passes, and the Nook's
## mood settles last. Presentation only — every cell already committed
## through the command layer before this starts; skipping or interrupting
## the animation can never lose state.
##
## Timings live in data/reveal.json (via NookRevealTimeline); there is no
## animation constant in this file worth tuning.

signal reveal_started(coord: Vector2i, duration: float)
signal reveal_finished(coord: Vector2i)

var core: GameCore
var renderer: WorldRenderer
var lighting   # LightingRig or null — mood settle degrades to nothing


func setup(
	game_core: GameCore,
	world_renderer: WorldRenderer,
	lighting_rig = null
) -> void:
	core = game_core
	renderer = world_renderer
	lighting = lighting_rig
	core.nooks.nook_revealed.connect(_on_nook_revealed)


func _on_nook_revealed(coord: Vector2i, plan: NookGenerator.NookPlan) -> void:
	var config := core.registries.reveal_config
	var world := core.nooks.world
	var origin_cell := world.chunk_origin(coord)
	var locals: Array[Vector2i] = []
	for tile: Dictionary in plan.tiles:
		locals.append(tile["local"] as Vector2i)
	var seam := _seam_side(coord)
	var wave_origin := NookRevealTimeline.wave_origin(
		world.nook_size, seam, config
	)
	var entries := NookRevealTimeline.tile_wave(locals, wave_origin, config)
	var duration := NookRevealTimeline.wave_duration(entries, config)
	var drop_height := float(config.get("tile_drop_height", 6.0))
	var drop_seconds := maxf(0.05, float(config.get("tile_drop_seconds", 0.34)))
	var overshoot := float(config.get("tile_overshoot", 0.08))
	var animated := 0
	for entry: Dictionary in entries:
		var cell: Vector2i = origin_cell + (entry["local"] as Vector2i)
		var holder := renderer.cell_holder(cell)
		if holder == null:
			continue
		animated += 1
		_drop_tile(
			holder, float(entry["delay"]), drop_height, drop_seconds, overshoot
		)
		_pop_features(
			cell,
			float(entry["delay"]) + drop_seconds
				+ float(config.get("feature_pop_delay", 0.12)),
			maxf(0.05, float(config.get("feature_pop_seconds", 0.22)))
		)
	_settle_mood(plan.mood_id, duration, config)
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
	var state := core.grid.cell(cell)
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


## Mood settles last: weather and time-of-day crossfade after the wave.
func _settle_mood(mood_id: String, wave_duration: float, config: Dictionary) -> void:
	if lighting == null or mood_id == "":
		return
	var mood := core.registries.nook_mood(mood_id)
	if mood == null:
		return
	var timer := get_tree().create_timer(maxf(0.0, wave_duration * 0.6))
	timer.timeout.connect(func():
		if lighting.has_method("set_weather"):
			lighting.set_weather(mood.weather)
		if lighting.has_method("set_time_of_day") and mood.time_of_day != "":
			lighting.set_time_of_day(mood.time_of_day)
	)


## The side of this chunk that touches an already-revealed neighbour, so
## the wave sweeps outward from the seam the player expanded across.
func _seam_side(coord: Vector2i) -> Vector2i:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor := core.nooks.world.nook(coord + offset)
		if neighbor != null \
			and neighbor.revealed_unix < core.nooks.world.nook(coord).revealed_unix:
			return offset
	return Vector2i.ZERO
