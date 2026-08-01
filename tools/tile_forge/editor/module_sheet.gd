extends Node3D
## Contact sheet for the Tile Forge module library.
##
## Studio conditions are fixed by the art brief so two review passes are
## comparable: orthographic three-quarter camera, 45-degree yaw, 35-degree
## downward pitch, one large soft key, a gentle fill, warm neutral background,
## and a short contact shadow. No bloom, no outlines, no long dramatic shadows —
## a module must earn its silhouette from its own geometry.
##
##   godot --path . tools/tile_forge/editor/module_sheet.tscn -- --shot-dir=<abs>

const REPORT_PATH := "res://tools/tile_forge/modules/build_report.json"

var _camera: Camera3D
var _output_dir := "user://tile_forge"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	var rows := _build()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("module_sheet.png", Vector3(0.0, 0.0, 0.0), 3.6)
	for row in rows.size():
		await _capture(
			"module_row_%s.png" % rows[row],
			Vector3(0.0, 0.0, (float(row) - float(rows.size() - 1) * 0.5) * 0.62),
			1.25
		)
	print("MODULE SHEET CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _build() -> PackedStringArray:
	var cozy: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(cozy)
	var profile := SumaTileArtProfile.default()

	_studio_lighting()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)

	var file := FileAccess.open(REPORT_PATH, FileAccess.READ)
	if file == null:
		push_error("no module build report at %s" % REPORT_PATH)
		return PackedStringArray()
	var report: Dictionary = JSON.parse_string(file.get_as_text())
	var modules: Array = report.get("modules", [])

	# Group by family so a row can be judged as a set — a module that only works
	# next to unrelated shapes is not part of a collection.
	var by_family: Dictionary = {}
	var order := PackedStringArray()
	for entry: Dictionary in modules:
		var family := String(entry["family"])
		if not by_family.has(family):
			by_family[family] = []
			order.append(family)
		(by_family[family] as Array).append(entry)

	# A neutral plate at the palette's own side value, so a module is judged
	# against the ground it will actually sit on.
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(5.0, 0.06, 4.0)
	plate.mesh = plate_mesh
	plate.position.y = -0.03
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = Color(0.72, 0.66, 0.55)
	plate_material.roughness = 1.0
	plate.material_override = plate_material
	add_child(plate)

	var spacing := 0.62
	for row in order.size():
		var family: String = order[row]
		var entries: Array = by_family[family]
		for column in entries.size():
			var entry: Dictionary = entries[column]
			var scene: PackedScene = load(String(entry["path"]))
			if scene == null:
				continue
			var instance := scene.instantiate() as Node3D
			materials.rebind_materials(instance)
			_tint(instance, family, profile)
			instance.position = Vector3(
				(float(column) - float(entries.size() - 1) * 0.5) * spacing,
				0.0,
				(float(row) - float(order.size() - 1) * 0.5) * spacing
			)
			add_child(instance)
	return order


## Family-appropriate colour so a straw module is not judged as green. Uses the
## real semantic palette plus the profile's own side-darkening rule.
func _tint(root: Node3D, family: String, profile: SumaTileArtProfile) -> void:
	var cozy: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var keys := {
		"grass": ["grass_primary", "grass_sunlit"],
		"straw": ["wood_gold", "warm_yellow"],
		"leaves": ["terracotta_orange", "warm_yellow"],
		"stones": ["stone_mid", "stone_light"],
		"rubble": ["stone_mid_light", "stone_light"],
		"pavers": ["stone_mid", "stone_light"],
		"boards": ["wood_primary", "wood_gold"],
	}
	var pair: Array = keys.get(family, ["stone_mid", "stone_light"])
	var top: Color = cozy.color(String(pair[0]))
	var accent: Color = cozy.color(String(pair[1]))
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			var name := source.resource_name if source != null else ""
			var material := StandardMaterial3D.new()
			material.roughness = profile.roughness
			material.metallic_specular = profile.specular
			material.metallic = profile.metallic
			match name:
				"shadow":
					material.albedo_color = profile.side_colour(top)
				"accent":
					material.albedo_color = accent
				_:
					material.albedo_color = top
			mesh_instance.set_surface_override_material(surface, material)


## One large soft key, one gentle fill, subtle ambient. No harsh dark faces and
## no long cast shadows: the brief judges form, not lighting drama.
func _studio_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.90, 0.87, 0.79)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.84, 0.78)
	environment.ambient_light_energy = 0.85
	environment.ssao_enabled = true
	environment.ssao_radius = 0.35
	environment.ssao_intensity = 1.1
	environment.ssao_power = 2.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 3.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.97, 0.91)
	key.shadow_enabled = true
	key.directional_shadow_blend_splits = true
	key.shadow_blur = 2.4
	key.rotation_degrees = Vector3(-52.0, 138.0, 0.0)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.34
	fill.light_color = Color(0.85, 0.89, 0.98)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, -46.0, 0.0)
	add_child(fill)


func _capture(filename: String, center: Vector3, size: float) -> void:
	_camera.size = size
	# The brief's studio angle: 45-degree yaw, 35-degree downward pitch.
	var pitch := deg_to_rad(-35.0)
	var yaw := deg_to_rad(45.0)
	var direction := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	_camera.position = center + direction * 6.0
	_camera.look_at(center, Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	get_viewport().get_texture().get_image().save_png(absolute_dir.path_join(filename))
