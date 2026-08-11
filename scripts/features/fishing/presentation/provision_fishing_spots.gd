class_name ProvisionFishingSpots
extends Node3D
## Readable, world-native provision shoals. The spot layout is deterministic
## from the world seed and water coordinates; only completed catches and their
## cooldowns persist. Timing is intentionally transient and forgiving.

signal feedback(kind: String, data: Dictionary)
signal spot_state_changed(coord: Vector2i)

const PHASE_IDLE := "idle"
const PHASE_WAITING := "waiting"
const PHASE_CUE := "cue"
const PHASE_COOLDOWN := "cooldown"
const HITS_REQUIRED := 3
const CUE_SECONDS := 0.9
const COOLDOWN_SECONDS := 35.0
const VISUAL_STATE_KEY := "provision_fishing_spots"

var core: GameCore
var assets: AssetLibrary
var effects: EffectsManager
var _spots: Dictionary = {} # Vector2i -> Node3D
var _states: Dictionary = {} # Vector2i -> transient timing state
var _sync_queued := false
var _bubble_material: StandardMaterial3D


func setup(game_core: GameCore, asset_library: AssetLibrary, effects_manager: EffectsManager) -> void:
	core = game_core
	assets = asset_library
	effects = effects_manager
	_bubble_material = StandardMaterial3D.new()
	_bubble_material.albedo_color = Color(0.82, 0.95, 1.0, 0.78)
	_bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	core.grid.slot_changed.connect(func(_coord: Vector2i, _elevation: int) -> void:
		_queue_spot_sync()
	)
	core.grid.grid_changed.connect(_queue_spot_sync)
	_sync_spots()


func _process(delta: float) -> void:
	if core == null:
		return
	_animate_fish(delta)
	var now := Time.get_unix_time_from_system()
	for coord: Vector2i in _spots.keys():
		var state := _state_for(coord)
		var phase := String(state.get("phase", PHASE_IDLE))
		if phase == PHASE_COOLDOWN:
			var seconds_left := maxi(0, ceili(
				float(_persistent_for(coord).get("cooldown_until", 0.0)) - now
			))
			if seconds_left <= 0:
				state["phase"] = PHASE_IDLE
				state["progress"] = 0
				spot_state_changed.emit(coord)
			elif int(state.get("display_seconds", -1)) != seconds_left:
				state["display_seconds"] = seconds_left
				spot_state_changed.emit(coord)
			continue
		if phase == PHASE_WAITING:
			state["remaining"] = float(state.get("remaining", 0.0)) - delta
			if float(state["remaining"]) <= 0.0:
				state["phase"] = PHASE_CUE
				state["remaining"] = CUE_SECONDS
				_bubble(coord, true)
				feedback.emit("bubble", _feedback_data(coord))
				spot_state_changed.emit(coord)
		elif phase == PHASE_CUE:
			state["remaining"] = float(state.get("remaining", 0.0)) - delta
			if float(state["remaining"]) <= 0.0:
				state["phase"] = PHASE_WAITING
				state["remaining"] = _next_wait(coord, int(state.get("progress", 0)) + 1)
				feedback.emit("missed", _feedback_data(coord))
				spot_state_changed.emit(coord)


func has_spot(coord: Vector2i) -> bool:
	return _spots.has(coord)


func interaction_at_cell(coord: Vector2i) -> Dictionary:
	if not _spots.has(coord):
		return {}
	return _interaction(coord)


func interaction_at_screen(
	camera: Camera3D,
	screen_position: Vector2,
	radius := 64.0
) -> Dictionary:
	if camera == null:
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for coord: Vector2i in _spots:
		var point := spot_position(coord)
		var visual_point := point + Vector3.UP * 0.08
		if camera.is_position_behind(visual_point):
			continue
		var distance := screen_position.distance_to(
			camera.unproject_position(visual_point)
		)
		if distance <= radius and distance < best_distance:
			best = _interaction(coord)
			best_distance = distance
	return best


func interaction_near(position: Vector3, maximum_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := maximum_distance
	for coord: Vector2i in _spots:
		var point := spot_position(coord)
		var distance := position.distance_to(point)
		if distance < best_distance:
			best = _interaction(coord)
			best_distance = distance
	if not best.is_empty():
		best["distance"] = best_distance
	return best


func interact(coord: Vector2i) -> bool:
	if not _spots.has(coord):
		return false
	var state := _state_for(coord)
	var phase := String(state.get("phase", PHASE_IDLE))
	if phase == PHASE_COOLDOWN:
		_bubble(coord, false)
		feedback.emit("cooldown", _feedback_data(coord))
		return true
	if phase == PHASE_IDLE:
		state["phase"] = PHASE_WAITING
		state["progress"] = 0
		state["remaining"] = _next_wait(coord, 0)
		_bubble(coord, false)
		feedback.emit("armed", _feedback_data(coord))
		spot_state_changed.emit(coord)
		return true
	if phase == PHASE_WAITING:
		# Early taps stay playful: one visible bubble, no punishment and no
		# accidental progress. The player learns to wait for the full boil.
		_bubble(coord, false)
		feedback.emit("early", _feedback_data(coord))
		return true
	if phase != PHASE_CUE:
		return false
	state["progress"] = int(state.get("progress", 0)) + 1
	_bubble(coord, false)
	if int(state["progress"]) >= HITS_REQUIRED:
		_complete_catch(coord, state)
	else:
		state["phase"] = PHASE_WAITING
		state["remaining"] = _next_wait(coord, int(state["progress"]))
		feedback.emit("hit", _feedback_data(coord))
		spot_state_changed.emit(coord)
	return true


func prompt_for(coord: Vector2i) -> String:
	if not _spots.has(coord):
		return "Fish this shoal"
	var state := _state_for(coord)
	var progress := int(state.get("progress", 0))
	match String(state.get("phase", PHASE_IDLE)):
		PHASE_WAITING:
			return "Watch for bubbles · %d/%d" % [progress, HITS_REQUIRED]
		PHASE_CUE:
			return "Hook now! · %d/%d" % [progress, HITS_REQUIRED]
		PHASE_COOLDOWN:
			var remaining := maxi(0, ceili(
				float(_persistent_for(coord).get("cooldown_until", 0.0))
				- Time.get_unix_time_from_system()
			))
			return "Shoal returns in %ds" % remaining
		_:
			return "Fish this shoal"


func spot_position(coord: Vector2i) -> Vector3:
	var water_level := core.registries.tunef("water_level_y", -0.14)
	return core.grid.cell_to_world(coord) + Vector3.UP * water_level


func debug_spot_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord: Vector2i in _spots:
		result.append(coord)
	return result


func debug_force_cue(coord: Vector2i) -> void:
	if not _spots.has(coord):
		return
	var state := _state_for(coord)
	state["phase"] = PHASE_CUE
	state["remaining"] = CUE_SECONDS
	spot_state_changed.emit(coord)


func debug_state(coord: Vector2i) -> Dictionary:
	return _state_for(coord).duplicate(true) if _spots.has(coord) else {}


func _queue_spot_sync() -> void:
	if _sync_queued:
		return
	_sync_queued = true
	call_deferred("_sync_spots")


func _sync_spots() -> void:
	_sync_queued = false
	if core == null:
		return
	var eligible: Array[Vector2i] = []
	for raw_coord: Variant in core.grid.cells.keys():
		var coord := raw_coord as Vector2i
		var definition := core.grid.tile_def(coord)
		if definition != null and definition.water_cells.has("open_water"):
			eligible.append(coord)
	eligible.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.x == b.x else a.x < b.x
	)
	var wanted: Dictionary = {}
	for coord: Vector2i in eligible:
		if wrapi(hash("%d:%d:%d" % [core.rng.world_seed, coord.x, coord.y]), 0, 4) == 0:
			wanted[coord] = true
	if wanted.is_empty() and not eligible.is_empty():
		var closest := eligible[0]
		var best_distance := closest.distance_squared_to(core.grid.home_cell)
		for coord: Vector2i in eligible:
			var distance := coord.distance_squared_to(core.grid.home_cell)
			if distance < best_distance:
				closest = coord
				best_distance = distance
		wanted[closest] = true
	for coord: Vector2i in _spots.keys():
		if wanted.has(coord):
			continue
		var old_root := _spots[coord] as Node3D
		if is_instance_valid(old_root):
			old_root.queue_free()
		_spots.erase(coord)
		_states.erase(coord)
	for coord: Vector2i in wanted:
		if not _spots.has(coord):
			_build_spot(coord)


func _build_spot(coord: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "ProvisionShoal_%d_%d" % [coord.x, coord.y]
	root.position = spot_position(coord)
	root.set_meta("coord", coord)
	add_child(root)
	_spots[coord] = root
	_state_for(coord)
	for index in 4:
		var fish := Node3D.new()
		fish.name = "Fish%d" % index
		fish.set_meta("angle", float(index) * TAU / 4.0)
		fish.set_meta("radius", 0.27 + 0.07 * float(index % 2))
		fish.set_meta("speed", 0.85 + 0.13 * float(index))
		fish.set_meta("depth", -0.13 - 0.035 * float(index % 3))
		root.add_child(fish)
		_build_fish_visual(fish, index)


func _build_fish_visual(fish: Node3D, index: int) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.075
	body_mesh.height = 0.15
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	body.mesh = body_mesh
	body.scale = Vector3(1.5, 0.62, 0.7)
	body.rotation.z = PI * 0.5
	body.material_override = assets.materials.material(
		"gold" if index % 2 == 0 else "fabric_accent"
	)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fish.add_child(body)
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.07, 0.055, 0.018)
	tail.mesh = tail_mesh
	tail.position.x = -0.1
	tail.rotation.z = PI * 0.25
	tail.material_override = body.material_override
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fish.add_child(tail)


func _animate_fish(delta: float) -> void:
	for coord: Vector2i in _spots:
		var root := _spots[coord] as Node3D
		if not is_instance_valid(root):
			continue
		for raw_fish: Node in root.get_children():
			var fish := raw_fish as Node3D
			if fish == null:
				continue
			var angle := float(fish.get_meta("angle", 0.0))
			angle = fposmod(angle + float(fish.get_meta("speed", 1.0)) * delta, TAU)
			fish.set_meta("angle", angle)
			var radius := float(fish.get_meta("radius", 0.3))
			fish.position = Vector3(
				cos(angle) * radius,
				float(fish.get_meta("depth", -0.15)) + sin(angle * 2.0) * 0.018,
				sin(angle) * radius
			)
			# The fish body's long axis is local X; point it along the circle's
			# tangent so the shoal visibly swims instead of orbiting sideways.
			fish.rotation.y = -angle - PI * 0.5


func _bubble(coord: Vector2i, strong: bool) -> void:
	var point := spot_position(coord)
	effects.ripple(point)
	var count := 6 if strong else 3
	for index in count:
		var bubble := MeshInstance3D.new()
		bubble.name = "FishingBubble"
		var mesh := SphereMesh.new()
		mesh.radius = 0.018 + 0.006 * float(index % 3)
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		bubble.mesh = mesh
		bubble.material_override = _bubble_material
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bubble.position = point + Vector3(
			cos(float(index) * 2.3) * 0.16,
			-0.12 - 0.03 * float(index % 2),
			sin(float(index) * 2.3) * 0.16
		)
		add_child(bubble)
		var tween := bubble.create_tween()
		tween.set_parallel()
		tween.tween_property(
			bubble, "position:y", point.y + 0.08, 0.32 + 0.035 * float(index)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(bubble, "scale", Vector3.ONE * 0.2, 0.45).set_delay(0.18)
		tween.chain().tween_callback(bubble.queue_free)


func _complete_catch(coord: Vector2i, state: Dictionary) -> void:
	var persistent := _persistent_for(coord)
	var cycle := int(persistent.get("cycle", 0)) + 1
	var contribution := core.contributions.contribute(
		["provisions", "fish"],
		"provision_spot:%d:%d:%d" % [coord.x, coord.y, cycle],
		{
			"source": "provision_fishing_spot",
			"coord": [coord.x, coord.y],
			"cycle": cycle,
		}
	)
	persistent["cycle"] = cycle
	persistent["cooldown_until"] = Time.get_unix_time_from_system() + COOLDOWN_SECONDS
	_store_persistent(coord, persistent)
	state["phase"] = PHASE_COOLDOWN
	state["remaining"] = 0.0
	state["progress"] = HITS_REQUIRED
	core.autosave_soon()
	var data := _feedback_data(coord)
	data["contribution"] = contribution.duplicate(true)
	feedback.emit("complete", data)
	spot_state_changed.emit(coord)


func _interaction(coord: Vector2i) -> Dictionary:
	return {
		"kind": "provision_fishing_spot",
		"coord": coord,
		"point": spot_position(coord),
	}


func _state_for(coord: Vector2i) -> Dictionary:
	if not _states.has(coord):
		var cooldown_until := float(_persistent_for(coord).get("cooldown_until", 0.0))
		_states[coord] = {
			"phase": (
				PHASE_COOLDOWN
				if cooldown_until > Time.get_unix_time_from_system()
				else PHASE_IDLE
			),
			"progress": 0,
			"remaining": 0.0,
		}
	return _states[coord]


func _persistent_for(coord: Vector2i) -> Dictionary:
	var all_spots := core.visual_state.get(VISUAL_STATE_KEY, {}) as Dictionary
	return (all_spots.get(_coord_key(coord), {}) as Dictionary).duplicate(true)


func _store_persistent(coord: Vector2i, value: Dictionary) -> void:
	var all_spots := core.visual_state.get(VISUAL_STATE_KEY, {}) as Dictionary
	all_spots[_coord_key(coord)] = value.duplicate(true)
	core.visual_state[VISUAL_STATE_KEY] = all_spots


func _feedback_data(coord: Vector2i) -> Dictionary:
	var state := _state_for(coord)
	return {
		"coord": coord,
		"progress": int(state.get("progress", 0)),
		"hits_required": HITS_REQUIRED,
		"phase": String(state.get("phase", PHASE_IDLE)),
		"point": spot_position(coord),
	}


func _next_wait(coord: Vector2i, step: int) -> float:
	var cycle := int(_persistent_for(coord).get("cycle", 0))
	var value := wrapi(hash("%d:%d:%d:%d:%d" % [
		core.rng.world_seed, coord.x, coord.y, cycle, step,
	]), 0, 61)
	return 0.86 + float(value) / 100.0


func _coord_key(coord: Vector2i) -> String:
	return "%d:%d" % [coord.x, coord.y]
