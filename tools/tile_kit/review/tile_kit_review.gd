extends Node3D
## Reference-presentation captures for Tile Kit tiles.
##
## Reproduces the approved reference framing — orthographic three-quarter
## view, warm sand background, one soft key light — so a capture here is
## directly comparable against the reference image instead of being argued
## about under arbitrary lighting.
##
##   godot --path . tools/tile_kit/review/tile_kit_review.tscn -- --shot-dir=<abs>

var _output_dir := "user://tile_kit_review"
var _camera: Camera3D
var _stage: Node3D
var _focus_ids := PackedStringArray()
var _catalog_mode := false
var _catalog_overlay: CanvasLayer
var _catalog_size := Vector2i(6400, 5600)
var _render_host: Node
var _render_viewport: Viewport


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--focus-ids="):
			_focus_ids = PackedStringArray(
				argument.trim_prefix("--focus-ids=").split(",", false)
			)
		elif argument == "--catalog":
			_catalog_mode = true
		elif argument.begins_with("--catalog-size="):
			var dimensions := argument.trim_prefix("--catalog-size=").split("x")
			if dimensions.size() == 2:
				_catalog_size = Vector2i(
					maxi(1280, int(dimensions[0])),
					maxi(720, int(dimensions[1]))
				)
	if _catalog_mode:
		_build_catalog_viewport()
	else:
		_render_host = self
		_render_viewport = get_viewport()
	_build_rig()
	await get_tree().process_frame
	if _catalog_mode:
		await _run_catalog()
	elif _focus_ids.is_empty():
		await _run()
	else:
		await _run_focus()
	print("TILE KIT REVIEW CAPTURED — %s" % ProjectSettings.globalize_path(_output_dir))
	get_tree().quit()


func _build_rig() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_render_host.add_child(_camera)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = TileKitPalette.color("background")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Warm-neutral fill, strong enough that grass roots and the shaded tile
	# side stay readable — the reference has no crushed blacks anywhere.
	environment.ambient_light_color = Color(0.94, 0.93, 0.88)
	environment.ambient_light_energy = 0.92
	# Fully colour-driven ambient: sky contribution would halve the fill with
	# a flat background and crush the tile sides toward black.
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	_render_host.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 0.48
	key.light_color = Color(1.0, 0.995, 0.97)
	key.shadow_enabled = true
	key.shadow_blur = 2.4
	key.directional_shadow_max_distance = 24.0
	# Above, front-left, per the reference read.
	key.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	_render_host.add_child(key)

	_stage = Node3D.new()
	_render_host.add_child(_stage)


func _build_catalog_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.name = "CatalogRenderViewport"
	viewport.size = _catalog_size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_hdr_2d = true
	add_child(viewport)
	_render_host = viewport
	_render_viewport = viewport


func _clear() -> void:
	for child in _stage.get_children():
		child.free()


func _frame(extent: float, target := Vector3.ZERO) -> void:
	_camera.size = extent
	# The classic diorama axes: yaw 45, isometric-style downward pitch.
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(-35.264)) \
		.rotated(Vector3.UP, deg_to_rad(45.0))
	_camera.position = target + direction * 12.0
	_camera.look_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	var image := _render_viewport.get_texture().get_image()
	# The project runs with viewport/hdr_2d, so the root buffer is LINEAR and
	# get_image() returns it raw. Saved as-is, every capture looks darker and
	# more saturated than the screen — which quietly mis-calibrated an entire
	# round of palette judgment. Convert before anyone judges a colour again.
	if _render_viewport.use_hdr_2d:
		# The HDR buffer arrives as float RGBAF, and linear_to_srgb() only
		# operates on 8-bit images — it errors and silently does nothing on
		# float data, which is exactly how this fix failed its first attempt.
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	image.save_png(absolute.path_join(file_name))


func _run() -> void:
	# 1. The hero: one Reference Clean Grass tile, framed like the reference.
	_clear()
	var hero := TileKitGenerator.new()
	hero.preset = TileKitPreset.reference_clean_grass()
	_stage.add_child(hero)
	_frame(2.6, Vector3(0.0, -0.1, 0.0))
	await _shoot("01_reference_tile.png")
	print("stats: %s" % JSON.stringify(hero.statistics()))

	# 2. Six seeds, judged together: randomization quality is a property of
	# the population, not of one lucky roll.
	_clear()
	for index in 6:
		var generator := TileKitGenerator.new()
		var preset := TileKitPreset.reference_clean_grass()
		preset.master_seed = 20260801 + index * 7919
		generator.preset = preset
		generator.position = Vector3(
			(index % 3 - 1) * 2.1, 0.0, (index / 3 - 0.5) * 2.1)
		_stage.add_child(generator)
	_frame(6.4, Vector3(0.0, -0.15, 0.0))
	await _shoot("02_six_seeds.png")

	# 3. A 3x3 patch of one seed: grass consumes the patch topology, so only
	# the outside perimeter keeps a rim and the interior reads as one land mass.
	_clear()
	for z in 3:
		for x in 3:
			var generator := TileKitGenerator.new()
			var preset := TileKitPreset.reference_clean_grass()
			preset.master_seed = 41000
			generator.preset = preset
			generator.world_cell = Vector2i(x - 1, z - 1)
			generator.neighbour_mask = (
				(1 if z > 0 else 0)
				| (2 if x < 2 else 0)
				| (4 if z < 2 else 0)
				| (8 if x > 0 else 0)
			)
			generator.position = Vector3((x - 1) * 1.70, 0.0, (z - 1) * 1.70)
			_stage.add_child(generator)
	_frame(6.2, Vector3(0.0, -0.2, 0.0))
	await _shoot("03_patch_3x3.png")

	# The same topology supplied to a separated paving preset is deliberately
	# ignored: every constructed cell keeps its authored bevel and groove.
	_clear()
	for z in 3:
		for x in 3:
			var generator := TileKitGenerator.new()
			generator.preset = TileKitPreset.cobblestone_paving()
			generator.world_cell = Vector2i(x - 1, z - 1)
			generator.neighbour_mask = (
				(1 if z > 0 else 0)
				| (2 if x < 2 else 0)
				| (4 if z < 2 else 0)
				| (8 if x > 0 else 0)
			)
			generator.position = Vector3((x - 1) * 1.70, 0.0, (z - 1) * 1.70)
			_stage.add_child(generator)
	_frame(6.2, Vector3(0.0, -0.2, 0.0))
	await _shoot("03b_separated_paving_3x3.png")

	# 4. Layer breakdown of the hero seed: base only, +dressing, +clutter,
	# +grass — the lego bricks shown one at a time.
	var kinds := ["base", "dressing", "clutter", "grass_clusters"]
	for step in kinds.size():
		_clear()
		var generator := TileKitGenerator.new()
		generator.preset = TileKitPreset.reference_clean_grass()
		_stage.add_child(generator)
		for kind_index in kinds.size():
			generator.set_layer_visible(kinds[kind_index], kind_index <= step)
		_frame(2.6, Vector3(0.0, -0.1, 0.0))
		await _shoot("04_layer_%d_%s.png" % [step, kinds[step]])

	# 5. The four built-in families side by side — the "all kinds of tiles"
	# promise, checked in one frame.
	_clear()
	var families := TileKitPreset.built_in_names()
	var columns := 4
	for index in families.size():
		var generator := TileKitGenerator.new()
		generator.preset = TileKitPreset.make_built_in(families[index])
		generator.position = Vector3(
			(index % columns) * 2.1 - 3.15, 0.0,
			(index / columns) * 2.1 - 4.2)
		_stage.add_child(generator)
	_frame(12.2, Vector3(0.0, -0.3, 0.0))
	await _shoot("05_family_lineup.png")

	# 6–9. Source-look dune studies plus the complete strength range exposed by
	# the editor slider. These captures are the visual acceptance evidence for
	# replacing the imported sand/snow surfaces later, without touching them now.
	for study: Dictionary in [
		{"name": "06_sand_dune_study.png", "preset": TileKitPreset.sand_dune_study()},
		{"name": "07_snow_drift_study.png", "preset": TileKitPreset.snow_drift_study()},
	]:
		_clear()
		var generator := TileKitGenerator.new()
		generator.preset = study["preset"]
		_stage.add_child(generator)
		_frame(2.7, Vector3(0.0, -0.1, 0.0))
		await _shoot(study["name"])
	for strength: Dictionary in [
		{"name": "08_dune_strength_min.png", "value": 0.005},
		{"name": "09_dune_strength_max.png", "value": 0.180},
	]:
		_clear()
		var generator := TileKitGenerator.new()
		var preset := TileKitPreset.sand_dune_study()
		preset.layer_of_kind("base").params["relief_amplitude"] = strength["value"]
		generator.preset = preset
		_stage.add_child(generator)
		_frame(2.7, Vector3(0.0, -0.1, 0.0))
		await _shoot(strength["name"])

	# 10–11. Connected study patches: opposite edges use the same periodic
	# height field, while only the outside perimeter feathers down to a rim.
	for study: Dictionary in [
		{"name": "10_sand_dune_patch_3x3.png", "kind": "sand"},
		{"name": "11_snow_drift_patch_3x3.png", "kind": "snow"},
	]:
		_clear()
		for z in 3:
			for x in 3:
				var generator := TileKitGenerator.new()
				generator.preset = (
					TileKitPreset.sand_dune_study()
					if study["kind"] == "sand"
					else TileKitPreset.snow_drift_study()
				)
				generator.world_cell = Vector2i(x - 1, z - 1)
				generator.neighbour_mask = (
					(1 if z > 0 else 0)
					| (2 if x < 2 else 0)
					| (4 if z < 2 else 0)
					| (8 if x > 0 else 0)
				)
				generator.position = Vector3(
					(x - 1) * 1.70, 0.0, (z - 1) * 1.70
				)
				_stage.add_child(generator)
		_frame(6.2, Vector3(0.0, -0.2, 0.0))
		await _shoot(study["name"])


func _run_focus() -> void:
	_clear()
	var columns := mini(3, maxi(1, _focus_ids.size()))
	for index in _focus_ids.size():
		var tile_id := _focus_ids[index]
		var preset := TileKitPreset.official_recipe(tile_id)
		if preset == null:
			push_error("Missing focus recipe: %s" % tile_id)
			continue
		var generator := TileKitGenerator.new()
		generator.preset = preset
		generator.position = Vector3(
			(index % columns - (columns - 1) * 0.5) * 2.15,
			0.0,
			(index / columns - (_focus_ids.size() - 1) / columns * 0.5) * 2.15
		)
		_stage.add_child(generator)
		print("focus %s: %s" % [tile_id, JSON.stringify(generator.statistics())])
	var rows := ceili(float(_focus_ids.size()) / float(columns))
	_frame(maxf(3.0, maxf(columns, rows) * 2.35), Vector3(0.0, -0.2, 0.0))
	await _shoot("00_focus_tiles.png")


## One production catalog sheet containing every official recipe. Tiles are
## placed along the camera's screen-right and screen-down ground axes, rather
## than the world's X/Z axes, so the isometric previews form a true card grid.
## Titles live in a 2D overlay: they remain crisp at poster resolution and can
## never be hidden by tall procedural dressing.
func _run_catalog() -> void:
	_clear()
	var entries: Array = TileKitPreset.OFFICIAL_RECIPES
	var columns := 8
	var rows := ceili(float(entries.size()) / float(columns))
	var right_ground := Vector3(1.0, 0.0, -1.0).normalized()
	var down_ground := Vector3(1.0, 0.0, 1.0).normalized()
	var positions: Array[Vector3] = []
	for index in entries.size():
		var entry: Array = entries[index]
		var preset := TileKitPreset.official_recipe(String(entry[1]))
		if preset == null:
			push_error("Missing catalog recipe: %s" % entry[1])
			continue
		var column := index % columns
		var row := index / columns
		var position := (
			right_ground * (column - (columns - 1) * 0.5) * 2.60
			+ down_ground * (row - (rows - 1) * 0.5) * 4.65
		)
		var generator := TileKitGenerator.new()
		generator.preset = preset
		generator.position = position
		_stage.add_child(generator)
		positions.append(position)
	# Leave a full card margin around the outer previews. The tallest grass and
	# ruin recipes otherwise touch the image edge even though their footprints
	# themselves fit the mathematical grid.
	_frame(30.0, Vector3(0.0, -0.15, 0.0))
	await get_tree().process_frame
	_build_catalog_overlay(entries, positions, columns)
	await _shoot("all_official_tiles_catalog.png")


func _build_catalog_overlay(
	entries: Array, positions: Array[Vector3], columns: int
) -> void:
	if is_instance_valid(_catalog_overlay):
		_catalog_overlay.free()
	_catalog_overlay = CanvasLayer.new()
	_catalog_overlay.layer = 20
	_render_host.add_child(_catalog_overlay)
	var viewport_size := _render_viewport.get_visible_rect().size

	var heading := Label.new()
	heading.text = "SUMA — OFFICIAL PROCEDURAL TILE LIBRARY"
	heading.position = Vector2(0.0, viewport_size.y * 0.004)
	heading.size = Vector2(viewport_size.x, viewport_size.y * 0.030)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(
		"font_size", maxi(42, roundi(viewport_size.x * 0.0095))
	)
	heading.add_theme_color_override("font_color", Color("39372f"))
	heading.add_theme_color_override("font_outline_color", Color("fff6dd"))
	heading.add_theme_constant_override("outline_size", 12)
	_catalog_overlay.add_child(heading)

	# The 3D camera inside a SubViewport reports projection coordinates in the
	# host window's coordinate space on some platforms. Use the deliberately
	# authored card grid instead: these ratios correspond to the 30 m catalog
	# frame above and remain exact at every requested output resolution.
	var title_width := viewport_size.x * 0.100
	var title_offset := viewport_size.y * 0.067
	var font_size := maxi(25, roundi(viewport_size.x * 0.0060))
	for index in mini(entries.size(), positions.size()):
		var entry: Array = entries[index]
		var column := index % columns
		var row := index / columns
		var tile_center := Vector2(
			viewport_size.x * (0.1171875 + column * 0.109375),
			viewport_size.y * (0.1160714 + row * 0.1294643)
		)
		var title := Label.new()
		title.text = String(entry[0])
		title.position = Vector2(
			tile_center.x - title_width * 0.5,
			tile_center.y - title_offset - font_size * 0.70
		)
		title.size = Vector2(title_width, font_size * 1.55)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.add_theme_font_size_override("font_size", font_size)
		title.add_theme_color_override("font_color", Color("3e3b33"))
		title.add_theme_color_override("font_outline_color", Color("fff6dd"))
		title.add_theme_constant_override("outline_size", 6)
		_catalog_overlay.add_child(title)
