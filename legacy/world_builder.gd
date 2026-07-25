extends Node3D
# legacy-disabled class_name WorldBuilder

signal preset_changed(preset_id: StringName, display_name: String)

const Factory := preload("res://scripts/visual_factory.gd")
const PixelArt := preload("res://scripts/pixel_art.gd")
const PRESETS := [&"greenwood", &"firefly_dusk", &"moss_rain"]

var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var floor_mesh: MeshInstance3D
var effect_root: Node3D
var forest_root: Node3D
var preset_id := &"greenwood"
var _time := 0.0


func setup(initial_preset: StringName = &"greenwood") -> void:
	name = "PixelForestEnvironment"
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
		if preset_id == &"moss_rain":
			mote.position.y -= delta * speed
			mote.position.x -= delta * 0.35
			if mote.position.y < -0.1:
				mote.position.y = 9.0 + float(mote.get_index() % 5)
		else:
			mote.position.y += sin(_time * speed + mote.get_index()) * delta * 0.24
			mote.position.x += cos(_time * 0.5 + mote.get_index()) * delta * 0.05


func cycle_preset() -> StringName:
	var index := PRESETS.find(preset_id)
	var next: StringName = PRESETS[posmod(index + 1, PRESETS.size())]
	set_preset(next)
	return next


func set_preset(id: StringName) -> void:
	preset_id = id if id in PRESETS else &"greenwood"
	_clear_effects()
	match preset_id:
		&"firefly_dusk":
			_apply_colors(
				Color("#10251d"), Color("#173527"), Color("#7da474"),
				Color("#f0b56a"), 0.78, Color("#10251d"))
			_build_fireflies()
		&"moss_rain":
			_apply_colors(
				Color("#223a31"), Color("#29483a"), Color("#9cb89b"),
				Color("#c8d5a6"), 0.56, Color("#223a31"))
			_build_rain()
		_:
			_apply_colors(
				Color("#1a3828"), Color("#244b32"), Color("#b3cb91"),
				Color("#f1d58a"), 0.82, Color("#1a3828"))
			_build_fireflies()
	preset_changed.emit(preset_id, display_name())


func display_name() -> String:
	match preset_id:
		&"firefly_dusk": return "Firefly Dusk"
		&"moss_rain": return "Moss Rain"
		_: return "Greenwood"


func _build() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = false
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
	sun.name = "CanopySun"
	sun.rotation_degrees = Vector3(-48, 38, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 36.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.70
	sun.shadow_blur = 0.1
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
	_build_forest_frame()


func _build_forest_frame() -> void:
	forest_root = Node3D.new()
	forest_root.name = "DeepForestFrame"
	add_child(forest_root)
	for i: int in 40:
		var angle := float(i) / 40.0 * TAU
		var radius := 10.5 + float(posmod(i * 17, 27)) * 0.13
		var tree := Sprite3D.new()
		tree.name = "ForestTree_%02d" % i
		tree.texture = PixelArt.forest_tree_texture(i)
		tree.pixel_size = 0.050 + float(i % 3) * 0.004
		tree.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tree.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		tree.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		tree.shaded = true
		tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tree.position = Vector3(cos(angle) * radius, 1.65, sin(angle) * radius)
		forest_root.add_child(tree)
	for i: int in 24:
		var angle := float(i) / 24.0 * TAU + 0.13
		var radius := 8.8 + float(posmod(i * 11, 13)) * 0.10
		var undergrowth := Sprite3D.new()
		undergrowth.name = "Undergrowth_%02d" % i
		undergrowth.texture = PixelArt.prop_texture(&"moss_rock" if i % 5 == 0 else &"berry_bush")
		undergrowth.pixel_size = 0.034
		undergrowth.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		undergrowth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		undergrowth.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		undergrowth.shaded = true
		undergrowth.position = Vector3(cos(angle) * radius, 0.75, sin(angle) * radius)
		forest_root.add_child(undergrowth)


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
	environment.fog_enabled = preset_id != &"greenwood"
	environment.fog_light_color = fog_color
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.008 if preset_id == &"moss_rain" else 0.004
	environment.fog_depth_begin = 14.0
	environment.fog_depth_end = 46.0
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	fill.light_color = ambient
	fill.light_energy = 0.08
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = floor_color
	floor_material.roughness = 1.0
	floor_material.albedo_texture = PixelArt.tile_texture(&"ground_grass")
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	floor_material.uv1_scale = Vector3(28, 28, 28)
	floor_mesh.material_override = floor_material


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
