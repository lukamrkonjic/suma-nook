extends Node3D
class_name WorldBuilder

signal preset_changed(preset_id: StringName, display_name: String)

const Factory := preload("res://scripts/visual_factory.gd")
const PRESETS := [&"sunroom", &"ember_dusk", &"soft_rain"]

var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var floor_mesh: MeshInstance3D
var effect_root: Node3D
var preset_id := &"sunroom"
var _time := 0.0


func setup(initial_preset: StringName = &"sunroom") -> void:
	name = "DioramaEnvironment"
	_build()
	set_preset(initial_preset)


func _process(delta: float) -> void:
	_time += delta
	if effect_root == null:
		return
	for child: Node in effect_root.get_children():
		if not child is MeshInstance3D:
			continue
		var mote := child as MeshInstance3D
		var speed := float(mote.get_meta("speed", 1.0))
		if preset_id == &"soft_rain":
			mote.position.y -= delta * speed
			mote.position.x -= delta * 0.35
			if mote.position.y < -0.1:
				mote.position.y = 9.0 + float(mote.get_index() % 5)
		elif preset_id == &"ember_dusk":
			mote.position.y += sin(_time * speed + mote.get_index()) * delta * 0.24
			mote.position.x += cos(_time * 0.5 + mote.get_index()) * delta * 0.05


func cycle_preset() -> StringName:
	var index := PRESETS.find(preset_id)
	var next: StringName = PRESETS[posmod(index + 1, PRESETS.size())]
	set_preset(next)
	return next


func set_preset(id: StringName) -> void:
	preset_id = id if id in PRESETS else &"sunroom"
	_clear_effects()
	match preset_id:
		&"ember_dusk":
			_apply_colors(
				Color("#2e2928"), Color("#3b302c"), Color("#9e8d82"),
				Color("#ffb06c"), 0.72, Color("#2e2928"))
			_build_fireflies()
		&"soft_rain":
			_apply_colors(
				Color("#66796c"), Color("#75897a"), Color("#b8cbb4"),
				Color("#d9e4c6"), 0.50, Color("#66796c"))
			_build_rain()
		_:
			_apply_colors(
				Color("#e9e3c9"), Color("#f3ead1"), Color("#fff3d2"),
				Color("#ffe2a2"), 0.62, Color("#e9e3c9"))
	preset_changed.emit(preset_id, display_name())


func display_name() -> String:
	match preset_id:
		&"ember_dusk": return "Ember Dusk"
		&"soft_rain": return "Soft Rain"
		_: return "Sunroom"


func _build() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.82
	environment.ssao_enabled = true
	environment.ssao_radius = 1.35
	environment.ssao_intensity = 1.15
	environment.ssao_power = 1.45
	environment.ssao_detail = 0.42
	environment.ssao_horizon = 0.04
	environment.ssao_sharpness = 0.72
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "SoftboxSun"
	sun.rotation_degrees = Vector3(-48, 38, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 36.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.70
	sun.shadow_blur = 1.6
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-55, -140, 0)
	fill.shadow_enabled = false
	add_child(fill)

	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "BackdropFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.52
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)

	effect_root = Node3D.new()
	effect_root.name = "Atmosphere"
	add_child(effect_root)


func _apply_colors(
		background: Color,
		floor_color: Color,
		ambient: Color,
		sun_color: Color,
		sun_energy: float,
		fog_color: Color
	) -> void:
	environment.background_color = background
	environment.ambient_light_color = ambient
	environment.ambient_light_energy = 0.22
	environment.fog_enabled = preset_id != &"sunroom"
	environment.fog_light_color = fog_color
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.008 if preset_id == &"soft_rain" else 0.004
	environment.fog_depth_begin = 14.0
	environment.fog_depth_end = 46.0
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	fill.light_color = ambient
	fill.light_energy = 0.08
	floor_mesh.material_override = Factory.material("backdrop_%s" % preset_id, floor_color)


func _clear_effects() -> void:
	if effect_root == null:
		return
	for child: Node in effect_root.get_children():
		child.queue_free()


func _build_rain() -> void:
	var rain_material := Factory.transparent_material("rain", Color(0.88, 0.96, 0.91, 0.56))
	for i: int in 46:
		var drop := MeshInstance3D.new()
		drop.name = "RainDrop"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.62 + float(i % 4) * 0.10, 0.025)
		drop.mesh = mesh
		drop.material_override = rain_material
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drop.position = Vector3(
			-11.0 + float((i * 47) % 100) / 100.0 * 22.0,
			0.5 + float((i * 31) % 100) / 100.0 * 11.0,
			-8.0 + float((i * 67) % 100) / 100.0 * 16.0)
		drop.rotation.z = -0.13
		drop.set_meta("speed", 5.8 + float(i % 5) * 0.55)
		effect_root.add_child(drop)


func _build_fireflies() -> void:
	for i: int in 24:
		var glow := MeshInstance3D.new()
		glow.name = "GlowOrb"
		var mesh := SphereMesh.new()
		mesh.radius = 0.035 + float(i % 3) * 0.012
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		glow.mesh = mesh
		glow.material_override = Factory.material("firefly", Color("#ffd968"), Color("#ffbe38"))
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(
			-7.0 + float((i * 43) % 100) / 100.0 * 14.0,
			0.6 + float((i * 29) % 100) / 100.0 * 4.5,
			-5.0 + float((i * 71) % 100) / 100.0 * 10.0)
		glow.set_meta("speed", 0.8 + float(i % 5) * 0.18)
		effect_root.add_child(glow)
