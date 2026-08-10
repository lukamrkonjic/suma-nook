class_name NookArrivalGhost
extends Node3D
## A short-lived "starlight garden blueprint" over an unrevealed Nook.
##
## The quilt is presentation-only: translucent low-poly cells and seed lights
## mark the exact future footprint without adding collision or touching world
## state. It appears on the input frame and breathes while generation streams.
## Each cell fades only when its matching terrain cell touches down, so the
## blueprint is visibly replaced by the finished world rather than hidden.

const INVALID_COORD := Vector2i(2147483647, 2147483647)
const CELL_INSET := 0.78
const CELL_THICKNESS := 0.018
const PREVIEW_ALPHA := 0.24
const SEED_ALPHA := 0.58

var core: GameCore
var _palette := PaletteDefinition.shared()
var _active_coord := INVALID_COORD
var _entries: Array[Dictionary] = []
var _generation := 0


func setup(game_core: GameCore) -> void:
	core = game_core
	visible = false


func preview_nook(coord: Vector2i, seam: Vector2i) -> void:
	_clear_now()
	if core == null:
		return
	_generation += 1
	_active_coord = coord
	visible = true
	var origin := core.nooks.world.chunk_origin(coord)
	var nook_size := core.nooks.world.nook_size
	var tile_size := core.grid.tile_size
	for local_y in nook_size:
		for local_x in nook_size:
			var local := Vector2i(local_x, local_y)
			var cell := origin + local
			# Player-authored frontier pieces are already real and stay exactly
			# where they are; the loading blueprint only claims empty slots.
			if core.grid.has_cell(cell):
				continue
			var holder := Node3D.new()
			holder.name = "GhostCell_%d_%d" % [local_x, local_y]
			holder.position = core.grid.cell_to_world(cell) + Vector3.UP * 0.055
			holder.scale = Vector3.ONE * 0.01
			add_child(holder)

			var tint := _cell_tint(local)
			var materials: Array[StandardMaterial3D] = []
			var plate := MeshInstance3D.new()
			plate.name = "MemoryPlate"
			var plate_mesh := BoxMesh.new()
			plate_mesh.size = Vector3(
				tile_size * CELL_INSET,
				CELL_THICKNESS,
				tile_size * CELL_INSET
			)
			plate.mesh = plate_mesh
			var plate_material := _ghost_material(tint, PREVIEW_ALPHA)
			plate.material_override = plate_material
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(plate)
			materials.append(plate_material)

			# Sparse bright squares read as little seeds/stars in the painterly
			# pixel pass, making the loading footprint feel like a garden plan
			# rather than a technical checkerboard.
			if posmod(hash("arrival-seed:%d:%d" % [cell.x, cell.y]), 5) <= 1:
				var seed := MeshInstance3D.new()
				seed.name = "SeedLight"
				var seed_mesh := BoxMesh.new()
				seed_mesh.size = Vector3(
					tile_size * 0.13,
					CELL_THICKNESS * 1.8,
					tile_size * 0.13
				)
				seed.mesh = seed_mesh
				seed.position = Vector3(
					(-0.16 if (local_x + local_y) % 2 == 0 else 0.16) * tile_size,
					CELL_THICKNESS * 1.2,
					(0.13 if local_y % 2 == 0 else -0.13) * tile_size
				)
				var seed_color := _palette.color("vfx_marker_cream")
				var seed_material := _ghost_material(seed_color, SEED_ALPHA)
				seed.material_override = seed_material
				seed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(seed)
				materials.append(seed_material)

			var wave_delay := _wave_delay(local, seam, nook_size)
			_entries.append({
				"node": holder,
				"materials": materials,
				"cell": cell,
				"delay": wave_delay,
				"rest_y": holder.position.y,
				"landed": false,
			})
			_animate_cell_in(holder, wave_delay)


func begin_landing(coord: Vector2i, _reveal_duration := 0.0) -> void:
	if coord != _active_coord:
		return
	# Hold the complete blueprint under the falling terrain. Individual cells
	# are consumed by terrain_cell_landed, not by a second guessed wave timer.
	for entry: Dictionary in _entries:
		var holder := entry["node"] as Node3D
		if holder == null or not is_instance_valid(holder):
			continue
		_kill_cell_tween(holder)
		var tween := holder.create_tween()
		holder.set_meta("arrival_ghost_tween", tween)
		tween.tween_property(
			holder, "scale", Vector3.ONE, 0.12
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(
			holder,
			"position:y",
			float(entry["rest_y"]),
			0.12
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func land_cell(coord: Vector2i, cell: Vector2i) -> void:
	if coord != _active_coord:
		return
	for entry: Dictionary in _entries:
		if entry["cell"] as Vector2i != cell or bool(entry["landed"]):
			continue
		entry["landed"] = true
		var holder := entry["node"] as Node3D
		if holder == null or not is_instance_valid(holder):
			return
		_kill_cell_tween(holder)
		var tween := holder.create_tween()
		holder.set_meta("arrival_ghost_tween", tween)
		# A quick inward wink lets the solid tile appear to press the starlight
		# plan into the earth at the exact contact frame.
		tween.tween_property(
			holder, "scale", Vector3(0.82, 0.02, 0.82), 0.11
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		for material: StandardMaterial3D in entry["materials"]:
			var faded := material.albedo_color
			faded.a = 0.0
			tween.parallel().tween_property(
				material, "albedo_color", faded, 0.09
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(func():
			if is_instance_valid(holder):
				holder.visible = false
		)
		if remaining_cell_count() == 0:
			var token := _generation
			var timer := get_tree().create_timer(0.13)
			timer.timeout.connect(func():
				if token == _generation and coord == _active_coord:
					_clear_now()
			)
		return


func remaining_cell_count() -> int:
	var remaining := 0
	for entry: Dictionary in _entries:
		if not bool(entry.get("landed", false)):
			remaining += 1
	return remaining


func cancel_preview(coord: Vector2i = INVALID_COORD) -> void:
	if _active_coord == INVALID_COORD:
		return
	if coord != INVALID_COORD and coord != _active_coord:
		return
	_generation += 1
	var token := _generation
	for entry: Dictionary in _entries:
		var holder := entry["node"] as Node3D
		if holder == null or not is_instance_valid(holder):
			continue
		_kill_cell_tween(holder)
		var tween := holder.create_tween().set_parallel(true)
		tween.tween_property(holder, "scale", Vector3.ZERO, 0.18).set_trans(
			Tween.TRANS_BACK
		).set_ease(Tween.EASE_IN)
	var timer := get_tree().create_timer(0.2)
	timer.timeout.connect(func():
		if token == _generation:
			_clear_now()
	)


func is_previewing(coord := INVALID_COORD) -> bool:
	return (
		_active_coord != INVALID_COORD
		and (coord == INVALID_COORD or coord == _active_coord)
		and visible
	)


func active_coord() -> Vector2i:
	return _active_coord


func _animate_cell_in(holder: Node3D, delay: float) -> void:
	var rest_y := holder.position.y
	holder.position.y -= 0.16
	var tween := holder.create_tween()
	holder.set_meta("arrival_ghost_tween", tween)
	tween.tween_interval(delay)
	tween.tween_property(holder, "scale", Vector3.ONE, 0.32).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(holder, "position:y", rest_y, 0.3).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_start_cell_breath.bind(holder, rest_y))


func _start_cell_breath(holder: Node3D, rest_y: float) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var phase := float(posmod(hash(holder.name), 11)) * 0.035
	var tween := holder.create_tween().set_loops()
	holder.set_meta("arrival_ghost_tween", tween)
	tween.tween_interval(phase)
	tween.tween_property(holder, "position:y", rest_y + 0.035, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(holder, "position:y", rest_y, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)


func _kill_cell_tween(holder: Node3D) -> void:
	if not holder.has_meta("arrival_ghost_tween"):
		return
	var tween := holder.get_meta("arrival_ghost_tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	holder.remove_meta("arrival_ghost_tween")


func _cell_tint(local: Vector2i) -> Color:
	match posmod(local.x + local.y * 2, 3):
		0: return _palette.color("vfx_marker_gold")
		1: return _palette.color("vfx_marker_cream")
		_: return _palette.color("vfx_water_ripple_mid")


func _ghost_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var translucent := color
	translucent.a = alpha
	material.albedo_color = translucent
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.42
	return material


func _wave_delay(local: Vector2i, seam: Vector2i, nook_size: int) -> float:
	var primary := 0.0
	if seam.x < 0:
		primary = float(local.x)
	elif seam.x > 0:
		primary = float(nook_size - 1 - local.x)
	elif seam.y < 0:
		primary = float(local.y)
	elif seam.y > 0:
		primary = float(nook_size - 1 - local.y)
	else:
		var center := Vector2.ONE * (float(nook_size - 1) * 0.5)
		primary = Vector2(local).distance_to(center)
	var cross := float(local.y if seam.x != 0 else local.x)
	return primary * 0.045 + absf(cross - float(nook_size - 1) * 0.5) * 0.008


func _clear_now() -> void:
	for entry: Dictionary in _entries:
		var holder := entry.get("node") as Node3D
		if holder != null and is_instance_valid(holder):
			_kill_cell_tween(holder)
			holder.free()
	_entries.clear()
	_active_coord = INVALID_COORD
	visible = false
