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
var _gold_mode := false
var _seam_audit_mode := false
var _catalog_overlay: CanvasLayer
var _render_host: Node
var _render_viewport: Viewport
var _key_light: DirectionalLight3D
var _environment: Environment


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
		elif argument == "--gold":
			_gold_mode = true
		elif argument == "--seam-audit":
			_seam_audit_mode = true
	# The catalog once rendered through a dedicated 6400x5600 SubViewport.
	# That path produced wrong ortho framing AND phantom sheared under-tile
	# geometry on some machines (the hidpi rig), while the root viewport
	# renders the identical scene correctly. Everything now goes through the
	# root; the catalog is a landscape sheet sized to the window.
	_render_host = self
	_render_viewport = get_viewport()
	_build_rig()
	await get_tree().process_frame
	if _seam_audit_mode:
		await _run_seam_audit()
	elif _gold_mode:
		await _run_gold()
	elif _catalog_mode:
		await _run_catalog()
	elif _focus_ids.is_empty():
		await _run()
	else:
		await _run_focus()
	print("TILE KIT REVIEW CAPTURED — %s" % ProjectSettings.globalize_path(_output_dir))
	get_tree().quit()


func _run_seam_audit() -> void:
	# Five-cell stepped patches deliberately exercise exposed corners beside
	# connected edges: the exact layout that exposed the old V-shaped bite.
	var cells := [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	for audit: Dictionary in [
		{"id": "tile_dirt", "file": "seam_dirt.png"},
		{"id": "tile_snowfield", "file": "seam_snowfield.png"},
		{"id": "tile_proc_brick_court", "file": "seam_brick_court.png"},
	]:
		_clear()
		for cell in cells:
			var generator := TileKitGenerator.new()
			generator.preset = TileKitPreset.official_recipe(String(audit["id"]))
			generator.world_cell = cell
			var mask := 0
			if cell + Vector2i.UP in cells:
				mask |= 1
			if cell + Vector2i.RIGHT in cells:
				mask |= 2
			if cell + Vector2i.DOWN in cells:
				mask |= 4
			if cell + Vector2i.LEFT in cells:
				mask |= 8
			generator.neighbour_mask = mask
			generator.position = Vector3(
				(float(cell.x) - 1.0) * KitBaseBuilder.TILE,
				0.0,
				(float(cell.y) - 0.5) * KitBaseBuilder.TILE
			)
			_stage.add_child(generator)
		_frame(5.8, Vector3(0.0, -0.15, 0.0))
		await _calibrate_width(6.8)
		await _shoot(String(audit["file"]))


func _build_rig() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_render_host.add_child(_camera)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = TileKitPalette.color("background")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Cool restrained fill under a STRONG warm key. The old rig drowned the
	# sun in flat ambient and every sculpted form rendered as pastel mush —
	# the single biggest reason captures read as vector art instead of lit
	# toys. Form must come from the key light; ambient only keeps shadow
	# sides alive.
	environment.ambient_light_color = Color(0.82, 0.87, 0.92)
	environment.ambient_light_energy = 0.52
	environment.ambient_light_sky_contribution = 0.0
	# Filmic response: soft highlight rolloff and richer mid-tone contrast,
	# close to the game's graded pipeline. The capture path's linear→sRGB
	# conversion still applies — the tonemapper writes display-referred
	# values into the linear buffer.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.12
	# Contact depth between close forms — turf lobes, paver joints, drift
	# beds — the same read the game gets from its SSAO pass.
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.2
	environment.ssao_radius = 0.28
	environment.ssao_power = 1.3
	var world := WorldEnvironment.new()
	world.environment = environment
	_environment = environment
	_render_host.add_child(world)

	var key := DirectionalLight3D.new()
	# Golden-hour key: strong and warm. Highlights must visibly roll across
	# turf lobes and dune shoulders; sides must fall into believable shade.
	key.light_energy = 1.18
	key.light_color = Color(1.0, 0.93, 0.80)
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	key.directional_shadow_max_distance = 24.0
	# Lower, front-left: a more grazing key so shallow sculpt — dunes, turf
	# lobes, furrows — actually shades. The old high sun flattened relief.
	key.rotation_degrees = Vector3(-40.0, -32.0, 0.0)
	_key_light = key
	_render_host.add_child(key)

	_stage = Node3D.new()
	_render_host.add_child(_stage)


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


## Empirical framing correction. Window mode, display scale, and stretch
## settings have all bent the effective ortho extent on this rig before, and
## the projection drifts over the first frames while the window maximizes —
## so settle first, then iterate the measurement until it converges. The only
## trustworthy contract is the projection itself: measure how many pixels one
## ground unit spans, then scale the camera so `extent` world units exactly
## fill the viewport width.
func _calibrate_width(extent: float) -> void:
	await get_tree().create_timer(0.4).timeout
	for round in 3:
		await get_tree().process_frame
		var origin := _camera.unproject_position(Vector3.ZERO)
		var step := _camera.unproject_position(
			Vector3(1.0, 0.0, -1.0).normalized())
		var pixels_per_unit := (step - origin).length()
		if pixels_per_unit <= 0.001:
			return
		var width := _render_viewport.get_visible_rect().size.x
		var correction := (pixels_per_unit * extent) / width
		_camera.size *= correction
		if absf(correction - 1.0) < 0.005:
			break


func _shoot(file_name: String) -> void:
	print("shoot %s camera size=%s pos=%s viewport=%s" % [
		file_name, _camera.size, _camera.position,
		_render_viewport.get_visible_rect().size])
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
	await _calibrate_width(3.3)
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
	await _calibrate_width(8.2)
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
	await _calibrate_width(8.2)
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


# --- gold master review ------------------------------------------------------


func _set_neutral_light() -> void:
	_key_light.light_energy = 1.0
	_key_light.light_color = Color(1.0, 0.985, 0.955)
	_environment.ambient_light_color = Color(0.89, 0.90, 0.89)
	_environment.ambient_light_energy = 0.60
	_environment.tonemap_exposure = 1.0


func _set_gameplay_light() -> void:
	_key_light.light_energy = 1.15
	_key_light.light_color = Color(1.0, 0.945, 0.85)
	_environment.ambient_light_color = Color(0.84, 0.88, 0.91)
	_environment.ambient_light_energy = 0.54
	_environment.tonemap_exposure = 1.1


## A cream ground plane at the tile's visual base: hides the deep stacking
## body (in game the tile always sits on terrain or another tile) and
## receives the soft contact shadow the diorama read depends on.
func _add_ground_plane() -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60.0, 60.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = TileKitPalette.color("background")
	material.roughness = 1.0
	mesh.material = material
	plane.mesh = mesh
	plane.position = Vector3(0.0, -0.185, 0.0)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(plane)


func _gold_generator(seed_offset := 0) -> TileKitGenerator:
	var generator := TileKitGenerator.new()
	var preset := TileKitPreset.official_recipe("tile_grass")
	if seed_offset != 0:
		preset.master_seed += seed_offset
	generator.show_structural_base = false
	generator.preset = preset
	return generator


func _run_gold() -> void:
	# A + B: isolated hero under neutral, then gameplay lighting.
	_clear()
	_add_ground_plane()
	var hero := _gold_generator()
	_stage.add_child(hero)
	_frame(3.2, Vector3(0.0, -0.05, 0.0))
	await _calibrate_width(3.9)
	_set_neutral_light()
	await _shoot("gold_a_hero_neutral.png")
	print("gold stats: %s" % JSON.stringify(hero.statistics()))
	_set_gameplay_light()
	await _shoot("gold_b_hero_gameplay.png")

	# C: the four cluster archetypes, each alone on the cream ground.
	_clear()
	_add_ground_plane()
	var archetype_rng := RandomNumberGenerator.new()
	archetype_rng.seed = 4242
	for archetype in 4:
		var batch := TileKitMeshUtils.MeshBatch.new()
		KitClusterBuilder._gold_cluster(batch, archetype_rng,
			Vector2.ZERO, 0.0, archetype + 1, 1.0)
		var instance := MeshInstance3D.new()
		instance.mesh = batch.commit()
		instance.position = Vector3(float(archetype - 1.5) * 0.85, -0.183, 0.0)
		_stage.add_child(instance)
	_frame(2.4, Vector3(0.0, -0.1, 0.0))
	await _calibrate_width(4.4)
	_set_neutral_light()
	await _shoot("gold_c_archetypes.png")

	# D: 3x3 patch — connected grassland.
	_clear()
	_add_ground_plane()
	for z in 3:
		for x in 3:
			var generator := _gold_generator(x * 31 + z * 7)
			generator.world_cell = Vector2i(x - 1, z - 1)
			generator.neighbour_mask = (
				(1 if z > 0 else 0) | (2 if x < 2 else 0)
				| (4 if z < 2 else 0) | (8 if x > 0 else 0)
			)
			generator.position = Vector3((x - 1) * 1.70, 0.0, (z - 1) * 1.70)
			_stage.add_child(generator)
	_frame(6.2, Vector3(0.0, -0.15, 0.0))
	await _calibrate_width(7.6)
	_set_gameplay_light()
	await _shoot("gold_d_patch_3x3.png")

	# E: the same patch with props standing on it.
	for prop: Dictionary in [
		{"asset": "prop_pine_a", "at": Vector3(-1.7, 0.0, -1.7)},
		{"asset": "prop_bench", "at": Vector3(0.35, 0.0, 0.2)},
		{"asset": "prop_lantern", "at": Vector3(1.6, 0.0, 1.2)},
	]:
		var path := AssetLibrary.resolve_path(String(prop["asset"]))
		if path.is_empty():
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var instance := scene.instantiate() as Node3D
		instance.position = prop["at"]
		_stage.add_child(instance)
	await _shoot("gold_e_patch_props.png")

	# F: rejected thick tile beside the gold master, identical framing.
	_clear()
	_add_ground_plane()
	var rejected_path := ProjectSettings.globalize_path(_output_dir).path_join(
		"rejected_tile_grass.tres")
	var rejected := ResourceLoader.load(rejected_path, "",
		ResourceLoader.CACHE_MODE_IGNORE) as TileKitPreset
	if rejected != null:
		var old := TileKitGenerator.new()
		old.preset = rejected
		old.position = Vector3(-1.35, 0.0, 0.0)
		_stage.add_child(old)
	var current := _gold_generator()
	current.position = Vector3(1.35, 0.0, 0.0)
	_stage.add_child(current)
	_frame(4.4, Vector3(0.0, -0.15, 0.0))
	await _calibrate_width(6.4)
	_set_neutral_light()
	await _shoot("gold_f_before_after.png")


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
	await _calibrate_width(float(columns) * 2.45 + 0.9)
	await _shoot("00_focus_tiles.png")


## One production catalog sheet containing every official recipe. Tiles are
## placed along the camera's screen-right and screen-down ground axes, rather
## than the world's X/Z axes, so the isometric previews form a true card grid.
## Titles live in a 2D overlay: they remain crisp at poster resolution and can
## never be hidden by tall procedural dressing.
func _run_catalog() -> void:
	_clear()
	var entries: Array = TileKitPreset.OFFICIAL_RECIPES
	# 12 x 5 landscape grid: the whole library fits one 16:9 root-viewport
	# frame, which is the only projection path that renders faithfully.
	var columns := 12
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
	# Titles live IN the 3D scene as billboarded Label3D nodes — they stay
	# glued to their tiles under any projection behaviour. Only the sheet
	# heading remains 2D.
	_frame(30.0, Vector3(0.0, -0.15, 0.0))
	await _calibrate_width(float(columns) * 2.60 + 1.6)
	await get_tree().process_frame
	_build_catalog_labels(entries, positions)
	_build_catalog_heading()
	await _shoot("all_official_tiles_catalog.png")


## One Label3D above each tile, billboarded at the review camera. In-scene
## labels ride the real projection, so they cannot drift off their tiles the
## way viewport-ratio overlays did.
func _build_catalog_labels(entries: Array, positions: Array[Vector3]) -> void:
	var down_ground := Vector3(1.0, 0.0, 1.0).normalized()
	for index in mini(entries.size(), positions.size()):
		var entry: Array = entries[index]
		var title := Label3D.new()
		title.text = String(entry[0])
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.font_size = 120
		title.pixel_size = 0.0016
		title.outline_size = 20
		title.modulate = Color("3e3b33")
		title.outline_modulate = Color("fff6dd")
		title.no_depth_test = true
		title.position = positions[index] - down_ground * 1.24 + Vector3.UP * 0.58
		_stage.add_child(title)


func _build_catalog_heading() -> void:
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

	# Per-tile titles are Label3D nodes in the scene (_build_catalog_labels);
	# only the sheet heading lives in this 2D layer.
