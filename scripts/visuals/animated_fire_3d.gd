class_name AnimatedFire3D
extends Node3D
## Reusable, allocation-free stylized fire.
##
## A small pool of softly faceted flame blobs grows from the fuel bed, drifts
## upward, fades, and is recycled. Per-prop profiles control the footprint and
## height without requiring prop-specific animation or sprite sheets.

@export_range(0.1, 4.0, 0.01) var fire_width := 0.56
@export_range(0.1, 4.0, 0.01) var fire_height := 0.58
@export_range(0.1, 2.5, 0.01) var intensity := 1.0
@export_range(0.0, 1.0, 0.01) var smoke_amount := 0.3
@export_range(0.0, 1.0, 0.01) var ember_amount := 0.65
@export_range(0.1, 3.0, 0.01) var animation_speed := 1.0
@export var wind := Vector3.ZERO
@export var random_seed := 73021
@export var playing := true

var _materials: MaterialLibrary
var _rng := RandomNumberGenerator.new()
var _flames: Array[FlameState] = []
var _embers: Array[DriftState] = []
var _smoke: Array[DriftState] = []
var _bound_light: OmniLight3D
var _light_energy := 1.0
var _last_light_energy := -1.0
var _elapsed := 0.0
var _built := false


class FlameState:
	var pool: MultiMesh
	var index := 0
	var color_band := 0
	var age := 0.0
	var lifetime := 1.0
	var start := Vector3.ZERO
	var scale := Vector3.ONE
	var rise := 0.5
	var sway := 0.1
	var phase := 0.0
	var yaw := 0.0
	var lean := 0.0


class DriftState:
	var pool: MultiMesh
	var index := 0
	var age := 0.0
	var lifetime := 1.0
	var start := Vector3.ZERO
	var velocity := Vector3.UP
	var start_scale := 0.1
	var end_scale := 0.2
	var phase := 0.0


func _init() -> void:
	# Flame blobs are cosmetic and intentionally animate on rendered frames.
	# Opt this subtree out of physics interpolation so per-frame MultiMesh
	# transforms are not treated as physics motion.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	if not _built:
		_rebuild()
	set_process(playing)


## Supported profile keys: width, height, intensity, smoke, embers, speed,
## wind [x,y,z], seed, and light_energy.
func configure(material_library: MaterialLibrary, profile := {}) -> void:
	_materials = material_library
	fire_width = float(profile.get("width", fire_width))
	fire_height = float(profile.get("height", fire_height))
	intensity = float(profile.get("intensity", intensity))
	smoke_amount = float(profile.get("smoke", smoke_amount))
	ember_amount = float(profile.get("embers", ember_amount))
	animation_speed = float(profile.get("speed", animation_speed))
	random_seed = int(profile.get("seed", random_seed))
	var wind_data: Array = profile.get("wind", [])
	if wind_data.size() >= 3:
		wind = Vector3(
			float(wind_data[0]),
			float(wind_data[1]),
			float(wind_data[2])
		)
	_light_energy = float(profile.get("light_energy", _light_energy))
	_rebuild()


## A renderer can pass its budgeted light so the flame and pool flicker
## together without adding an unbounded light per burning prop.
func bind_light(light: OmniLight3D) -> void:
	_bound_light = light
	if _bound_light != null:
		_light_energy = _bound_light.light_energy
		_last_light_energy = _bound_light.light_energy


func set_burning(active: bool) -> void:
	var was_playing := playing
	playing = active
	visible = active
	set_process(active)
	if active and not was_playing:
		# A relit fire begins at the fuel bed and grows naturally rather than
		# revealing whatever frozen frame happened to be hidden.
		for flame in _flames:
			_reset_flame(flame, false)
		for ember in _embers:
			_reset_ember(ember, false)
		for puff in _smoke:
			_reset_smoke(puff, false)
	if _bound_light != null:
		_bound_light.visible = active


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_flames.clear()
	_embers.clear()
	_smoke.clear()
	_rng.seed = random_seed

	var blob_meshes := [
		_build_flame_blob_mesh(7, 0),
		_build_flame_blob_mesh(7, 1),
		_build_flame_blob_mesh(7, 2),
	]
	var colors := _flame_palette()
	var band_names := [
		"FlameDeepOrange",
		"FlameOrange",
		"FlameAmber",
		"FlameGold",
		"FlameLightYellow",
	]
	var emission_strengths := [1.2, 1.4, 1.62, 1.82, 2.0]
	var flame_count := maxi(16, roundi(22.0 * intensity))
	for color_band in colors.size():
		var count := flame_count / colors.size()
		if color_band < flame_count % colors.size():
			count += 1
		_add_flame_layer(
			band_names[color_band],
			count,
			color_band,
			blob_meshes[color_band % blob_meshes.size()],
			_tinted_fire_material(
				colors[color_band],
				float(emission_strengths[color_band])
			)
		)

	var ember_count := maxi(0, roundi(5.0 * ember_amount * intensity))
	if ember_count > 0:
		_add_drift_pool(
			"Embers",
			ember_count,
			_ember_mesh(),
			_tinted_fire_material(colors[1], 1.25),
			_embers
		)
	var smoke_count := maxi(0, roundi(6.0 * smoke_amount * intensity))
	if smoke_count > 0:
		_add_drift_pool(
			"Smoke",
			smoke_count,
			_smoke_mesh(),
			_smoke_material(),
			_smoke
		)

	for flame in _flames:
		_reset_flame(flame, true)
	for ember in _embers:
		_reset_ember(ember, true)
	for puff in _smoke:
		_reset_smoke(puff, true)
	_built = true


func _process(delta: float) -> void:
	if not playing:
		return
	var step := minf(delta, 0.05) * animation_speed
	_elapsed += step
	for flame in _flames:
		_update_flame(flame, step)
	for ember in _embers:
		_update_ember(ember, step)
	for puff in _smoke:
		_update_smoke(puff, step)
	if _bound_light != null and is_instance_valid(_bound_light):
		if not is_equal_approx(_bound_light.light_energy, _last_light_energy):
			_light_energy = _bound_light.light_energy
		var flicker := (
			0.91
			+ sin(_elapsed * 15.7 + random_seed * 0.017) * 0.055
			+ sin(_elapsed * 24.1 + 1.7) * 0.035
		)
		_last_light_energy = _light_energy * maxf(0.72, flicker)
		_bound_light.light_energy = _last_light_energy


func _add_flame_layer(
	node_name: String,
	count: int,
	color_band: int,
	source_mesh: ArrayMesh,
	material: StandardMaterial3D
) -> void:
	var mesh := source_mesh.duplicate() as ArrayMesh
	mesh.surface_set_material(0, material)
	var pool := _make_pool(node_name, mesh, count)
	for index in count:
		var state := FlameState.new()
		state.pool = pool
		state.index = index
		state.color_band = color_band
		_flames.append(state)


func _add_drift_pool(
	node_name: String,
	count: int,
	mesh: PrimitiveMesh,
	material: StandardMaterial3D,
	states: Array[DriftState]
) -> void:
	mesh.material = material
	var pool := _make_pool(node_name, mesh, count)
	for index in count:
		var state := DriftState.new()
		state.pool = pool
		state.index = index
		states.append(state)


func _make_pool(node_name: String, mesh: Mesh, count: int) -> MultiMesh:
	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.use_colors = true
	pool.mesh = mesh
	pool.instance_count = count
	pool.custom_aabb = AABB(
		Vector3(-fire_width, -0.1, -fire_width),
		Vector3(fire_width * 2.0, fire_height * 2.6, fire_width * 2.0)
	)
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual.multimesh = pool
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(visual)
	return pool


func _reset_flame(state: FlameState, initial: bool) -> void:
	var heat := float(state.color_band) / 4.0
	var size_factor := lerpf(1.08, 0.72, heat)
	var radius := fire_width * lerpf(0.21, 0.11, heat)
	var angle := _rng.randf_range(0.0, TAU)
	var distance := radius * sqrt(_rng.randf())
	state.lifetime = _rng.randf_range(0.65, 1.05)
	state.age = (
		_rng.randf_range(-state.lifetime * 0.55, state.lifetime)
		if initial
		else -_rng.randf_range(0.0, 0.15)
	)
	state.start = Vector3(
		cos(angle) * distance,
		0.005,
		sin(angle) * distance
	)
	state.scale = Vector3(
		fire_width * size_factor * _rng.randf_range(0.15, 0.25),
		fire_height * size_factor * _rng.randf_range(0.23, 0.42),
		fire_width * size_factor * _rng.randf_range(0.14, 0.24)
	)
	state.rise = fire_height * _rng.randf_range(0.24, 0.58)
	state.sway = fire_width * _rng.randf_range(0.015, 0.052)
	state.phase = _rng.randf_range(0.0, TAU)
	state.yaw = _rng.randf_range(0.0, TAU)
	state.lean = _rng.randf_range(-0.18, 0.18)


func _update_flame(state: FlameState, delta: float) -> void:
	state.age += delta
	if state.age >= state.lifetime:
		_reset_flame(state, false)
	if state.age < 0.0:
		state.pool.set_instance_transform(
			state.index,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * 0.001),
				state.start
			)
		)
		state.pool.set_instance_color(
			state.index,
			Color(1.0, 1.0, 1.0, 0.0)
		)
		return
	var t := clampf(state.age / state.lifetime, 0.0, 1.0)
	var rise_t := t * t * (3.0 - 2.0 * t)
	var appear := smoothstep(0.0, 0.24, t)
	var disappear := 1.0 - smoothstep(0.5, 1.0, t)
	var opacity := appear * disappear
	var width_curve := (
		lerpf(0.26, 1.0, smoothstep(0.0, 0.24, t))
		* lerpf(1.0, 0.08, smoothstep(0.24, 1.0, t))
	)
	var height_curve := (
		lerpf(0.22, 1.0, smoothstep(0.0, 0.25, t))
		* lerpf(1.0, 0.16, smoothstep(0.5, 1.0, t))
	)
	var sway_angle := state.phase + t * TAU * 1.35
	var drift := Vector3(
		sin(sway_angle) * state.sway,
		state.rise * rise_t,
		cos(sway_angle * 0.83) * state.sway
	)
	drift += wind * (t * t)
	var rotation := Vector3(
		state.lean * sin(sway_angle * 0.7),
		state.yaw + t * 0.45,
		state.lean * cos(sway_angle)
	)
	var basis := Basis.from_euler(rotation).scaled(Vector3(
		state.scale.x * width_curve,
		state.scale.y * height_curve,
		state.scale.z * width_curve
	))
	state.pool.set_instance_transform(
		state.index,
		Transform3D(basis, state.start + drift)
	)
	state.pool.set_instance_color(
		state.index,
		Color(1.0, 1.0, 1.0, opacity)
	)


func _reset_ember(state: DriftState, initial: bool) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := fire_width * _rng.randf_range(0.02, 0.2)
	state.lifetime = _rng.randf_range(0.72, 1.25)
	state.age = (
		_rng.randf_range(-state.lifetime, state.lifetime)
		if initial
		else 0.0
	)
	state.start = Vector3(
		cos(angle) * radius,
		fire_height * 0.2,
		sin(angle) * radius
	)
	state.velocity = Vector3(
		_rng.randf_range(-0.14, 0.14) * fire_width,
		_rng.randf_range(0.55, 1.05) * fire_height,
		_rng.randf_range(-0.14, 0.14) * fire_width
	)
	state.start_scale = fire_width * _rng.randf_range(0.035, 0.065)
	state.end_scale = state.start_scale * 0.18
	state.phase = _rng.randf_range(0.0, TAU)


func _update_ember(state: DriftState, delta: float) -> void:
	state.age += delta
	if state.age >= state.lifetime:
		_reset_ember(state, false)
	if state.age < 0.0:
		_hide_drift(state)
		return
	var t := clampf(state.age / state.lifetime, 0.0, 1.0)
	var scale_value := lerpf(state.start_scale, state.end_scale, t)
	var drift := state.velocity * t + wind * (t * t)
	drift.x += sin(state.phase + t * TAU) * fire_width * 0.035
	var basis := Basis.from_euler(
		Vector3(t * 3.0, t * 2.0, t * 4.0)
	).scaled(Vector3.ONE * scale_value)
	state.pool.set_instance_transform(
		state.index,
		Transform3D(basis, state.start + drift)
	)
	state.pool.set_instance_color(
		state.index,
		Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.35, 1.0, t))
	)


func _reset_smoke(state: DriftState, initial: bool) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := fire_width * _rng.randf_range(0.0, 0.12)
	state.lifetime = _rng.randf_range(1.5, 2.25)
	state.age = (
		_rng.randf_range(-state.lifetime, state.lifetime)
		if initial
		else 0.0
	)
	state.start = Vector3(
		cos(angle) * radius,
		fire_height * _rng.randf_range(0.56, 0.72),
		sin(angle) * radius
	)
	state.velocity = Vector3(
		_rng.randf_range(-0.08, 0.08) * fire_width,
		_rng.randf_range(0.5, 0.82) * fire_height,
		_rng.randf_range(-0.08, 0.08) * fire_width
	)
	state.start_scale = fire_width * _rng.randf_range(0.12, 0.18)
	state.end_scale = fire_width * _rng.randf_range(0.28, 0.42)
	state.phase = _rng.randf_range(0.0, TAU)


func _update_smoke(state: DriftState, delta: float) -> void:
	state.age += delta
	if state.age >= state.lifetime:
		_reset_smoke(state, false)
	if state.age < 0.0:
		_hide_drift(state)
		return
	var t := clampf(state.age / state.lifetime, 0.0, 1.0)
	var scale_value := lerpf(
		state.start_scale,
		state.end_scale,
		smoothstep(0.0, 1.0, t)
	)
	var drift := state.velocity * t + wind * (t * t)
	drift.x += sin(state.phase + t * TAU * 0.7) * fire_width * 0.08
	drift.z += cos(state.phase + t * TAU * 0.55) * fire_width * 0.05
	var basis := Basis(Vector3.UP, state.phase + t * 0.5).scaled(
		Vector3(scale_value * 1.08, scale_value, scale_value * 0.94)
	)
	state.pool.set_instance_transform(
		state.index,
		Transform3D(basis, state.start + drift)
	)
	var opacity := (
		smoothstep(0.0, 0.16, t)
		* (1.0 - smoothstep(0.4, 1.0, t))
		* 0.52
	)
	state.pool.set_instance_color(
		state.index,
		Color(1.0, 1.0, 1.0, opacity)
	)


func _hide_drift(state: DriftState) -> void:
	state.pool.set_instance_transform(
		state.index,
		Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * 0.001),
			state.start
		)
	)
	state.pool.set_instance_color(
		state.index,
		Color(1.0, 1.0, 1.0, 0.0)
	)


func _flame_palette() -> Array[Color]:
	var deep := _palette_color("fire_red", Color("#b84a2a"))
	var orange := _palette_color("fire_orange", Color("#d98b22"))
	var yellow := _palette_color("fire_yellow", Color("#f2d84a"))
	var pale := _palette_color("fire_core", Color("#fff4cc"))
	return [
		deep.lerp(orange, 0.58),
		orange.darkened(0.06),
		orange.lerp(yellow, 0.32),
		orange.lerp(yellow, 0.68),
		yellow.lerp(pale, 0.22),
	]


func _palette_color(key: String, fallback: Color) -> Color:
	return (
		_materials.palette.color(key, fallback)
		if _materials != null
		else fallback
	)


func _tinted_fire_material(
	color: Color,
	emission_energy: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	return material


func _smoke_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = null
	if _materials != null:
		var source := _materials.material("smoke")
		if source != null:
			material = source.duplicate() as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = Color("#c4baa7")
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	)
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material


func _ember_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh


func _smoke_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 7
	mesh.rings = 4
	return mesh


## Deliberately different softly faceted profiles. Their centers wander as
## they rise, so random rotation and non-uniform scale read as handmade blobs.
static func _build_flame_blob_mesh(sides: int, variant: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profiles := [
		{
			"heights": [0.0, 0.13, 0.36, 0.61, 0.82, 1.0],
			"radii": [0.2, 0.4, 0.47, 0.34, 0.17, 0.0],
			"x": [-0.03, -0.06, 0.02, -0.04, 0.04, 0.11],
			"z": [0.02, -0.01, 0.035, 0.015, -0.025, -0.05],
		},
		{
			"heights": [0.0, 0.1, 0.31, 0.57, 0.79, 1.0],
			"radii": [0.18, 0.39, 0.49, 0.38, 0.19, 0.0],
			"x": [0.02, 0.055, -0.025, 0.05, -0.035, -0.1],
			"z": [-0.025, 0.02, -0.04, 0.015, 0.04, 0.07],
		},
		{
			"heights": [0.0, 0.15, 0.4, 0.65, 0.84, 1.0],
			"radii": [0.22, 0.44, 0.43, 0.36, 0.16, 0.0],
			"x": [-0.015, 0.035, -0.045, 0.015, 0.055, 0.08],
			"z": [0.03, 0.05, -0.01, -0.045, 0.01, 0.04],
		},
	]
	var profile: Dictionary = profiles[variant % profiles.size()]
	var ring_heights: Array = profile["heights"]
	var ring_radii: Array = profile["radii"]
	var ring_x: Array = profile["x"]
	var ring_z: Array = profile["z"]
	for ring in ring_heights.size() - 1:
		for side in sides:
			var next_side := (side + 1) % sides
			var a := _flame_blob_point(
				ring_heights[ring],
				ring_radii[ring],
				ring_x[ring],
				ring_z[ring],
				side,
				sides,
				variant,
				ring
			)
			var b := _flame_blob_point(
				ring_heights[ring + 1],
				ring_radii[ring + 1],
				ring_x[ring + 1],
				ring_z[ring + 1],
				side,
				sides,
				variant,
				ring + 1
			)
			var c := _flame_blob_point(
				ring_heights[ring + 1],
				ring_radii[ring + 1],
				ring_x[ring + 1],
				ring_z[ring + 1],
				next_side,
				sides,
				variant,
				ring + 1
			)
			var d := _flame_blob_point(
				ring_heights[ring],
				ring_radii[ring],
				ring_x[ring],
				ring_z[ring],
				next_side,
				sides,
				variant,
				ring
			)
			surface.add_vertex(a)
			surface.add_vertex(c)
			surface.add_vertex(b)
			if ring < ring_heights.size() - 2:
				surface.add_vertex(a)
				surface.add_vertex(d)
				surface.add_vertex(c)
	surface.generate_normals()
	return surface.commit()


static func _flame_blob_point(
	height: float,
	radius: float,
	x_offset: float,
	z_offset: float,
	side: int,
	sides: int,
	variant: int,
	ring: int
) -> Vector3:
	var angle := TAU * float(side) / float(sides)
	var wobble := (
		1.0
		+ sin(angle * 2.0 + variant * 1.7 + ring * 0.8) * 0.11
		+ cos(angle * 3.0 - variant * 0.9 + ring * 0.45) * 0.055
	)
	var cross_squash := 2.0 - wobble
	return Vector3(
		x_offset + cos(angle) * radius * wobble,
		height,
		z_offset + sin(angle) * radius * cross_squash
	)
