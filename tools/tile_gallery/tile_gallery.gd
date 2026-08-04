extends Node3D
## In-game tile gallery capture.
##
## Renders tiles through the production presentation path — the same
## PaletteDefinition, MaterialLibrary, AssetLibrary, TileVisualFactory and
## LightingRig the running game uses — so a capture is evidence about the game,
## not about a bespoke preview shader.
##
##   godot --path . tools/tile_gallery/tile_gallery.tscn -- \
##       --out=docs/tile_gallery --mode=sheet --frames=45
##
## Options:
##   --out=DIR       output directory (res:// or absolute)
##   --mode=         sheet | closeups | both      (default both)
##   --tiles=a,b,c   explicit tile ids            (default every catalog tile)
##   --cols=N        contact-sheet columns        (default 8)
##   --frames=N      frames to settle before capture (default 40)
##   --weather=      day | mist | rain | snow ... (default day)
##   --time=         morning | noon | sunset | night (default noon)
##   --sheet-patch=N connected patch size per sheet cell (default 3)
##   --gutter=N      empty tile widths between sheet cells (default 0.4)
##   --patch=N       closeup patch size in tiles  (default 3)

const LIGHTING_SCENE := "res://scenes/visual/SumaSoftDaylight.tscn"

var _palette: PaletteDefinition
var _materials: MaterialLibrary
var _assets: AssetLibrary
var _registries: Registries
var _grid: WorldGrid
var _factory: TileVisualFactory
var _lighting: LightingRig
var _camera: Camera3D
var _stage: Node3D

var _options: Dictionary = {}
var _tile_ids: PackedStringArray = PackedStringArray()
var _out_dir := ""
var _frames := 40
var _tile_size := 1.35


func _ready() -> void:
	_options = _parse_options()
	_out_dir = _absolute_dir(String(_options.get("out", "docs/tile_gallery")))
	_frames = maxi(2, int(_options.get("frames", 40)))
	DirAccess.make_dir_recursive_absolute(_out_dir)

	_palette = load("res://assets/palettes/gg_material_palette.tres")
	_materials = MaterialLibrary.new(_palette)
	_assets = AssetLibrary.new(_materials)

	_registries = Registries.new()
	# Registries.load_all() adopts nothing unless the *whole* catalog validates —
	# landmarks, structures, loot and every asset reference included. A tile
	# capture must not be hostage to unrelated content breakage, so fall back to
	# reading the tile catalog straight off disk when full validation fails.
	if not _registries.load_all("res://data", false):
		_load_tiles_unvalidated("res://data")
	if _registries.tiles.is_empty():
		push_error("tile_gallery: no tile definitions loaded")
		get_tree().quit(1)
		return

	_grid = WorldGrid.new(_registries)
	_tile_size = _grid.tile_size
	_factory = TileVisualFactory.new(_assets, _grid)

	_lighting = (load(LIGHTING_SCENE) as PackedScene).instantiate()
	add_child(_lighting)
	# Apply the exact saved runtime state synchronously. set_weather() and
	# set_time_of_day() intentionally animate between states for gameplay; a
	# deterministic capture must not sample that transition partway through.
	_lighting.apply_runtime_state({
		"weather": String(_options.get("weather", "day")),
		"time_of_day": String(_options.get("time", "noon")),
		"background": "profile",
		"particle_quality": "high",
	})
	if bool(_options.get("flat_bg", "1") == "1"):
		_flatten_background()

	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)

	_camera = Camera3D.new()
	_camera.name = "GalleryCamera"
	# Match the shipped gameplay framing: narrow-FOV perspective standing in
	# for orthographic, yaw 45, pitch -40 (data/tuning.json).
	_camera.fov = float(_registries.tuning.get("camera_fov_deg", 15.0))
	_camera.near = 1.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()

	_tile_ids = _requested_tile_ids()
	if _tile_ids.is_empty():
		push_error("tile_gallery: no tiles resolved")
		get_tree().quit(1)
		return

	var mode := String(_options.get("mode", "both"))
	_run(mode)


func _run(mode: String) -> void:
	var manifest := {
		"tiles": [],
		"mode": mode,
		"weather": _options.get("weather", "day"),
		"time_of_day": _options.get("time", "noon"),
	}
	if mode in ["sheet", "both"]:
		var sheet_path := _out_dir.path_join("tile_sheet.png")
		await _capture_sheet(sheet_path)
		manifest["sheet"] = sheet_path
	if mode in ["closeups", "both"]:
		for tile_id in _tile_ids:
			var path := _out_dir.path_join("tile_%s.png" % tile_id.trim_prefix("tile_"))
			var ok := await _capture_closeup(tile_id, path)
			manifest["tiles"].append({"id": tile_id, "path": path, "ok": ok})
			print("SHOT %s -> %s" % [tile_id, path])
	var f := FileAccess.open(_out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
	print("GALLERY COMPLETE %d tiles -> %s" % [_tile_ids.size(), _out_dir])
	get_tree().quit(0)


## One tile family per cell, laid out on a single plane so the sheet shows how
## the whole catalog reads together under one light.
func _capture_sheet(path: String) -> bool:
	_clear_stage()
	var cols := maxi(1, int(_options.get("cols", 8)))
	var patch := maxi(1, int(_options.get("sheet-patch", 3)))
	var gutter := maxf(0.0, float(_options.get("gutter", 0.4)))
	var pitch := _tile_size * (patch + gutter)
	var rows := int(ceil(float(_tile_ids.size()) / float(cols)))
	for i in _tile_ids.size():
		var col := i % cols
		var row := i / cols
		var origin := Vector3(col * pitch, 0.0, row * pitch)
		_add_patch(_tile_ids[i], origin, patch)
	var last_cell_offset := (patch - 1) * _tile_size
	var centre := Vector3(
		((cols - 1) * pitch + last_cell_offset) * 0.5,
		0.0,
		((rows - 1) * pitch + last_cell_offset) * 0.5
	)
	var width := (cols - 1) * pitch + patch * _tile_size
	var depth := (rows - 1) * pitch + patch * _tile_size
	_frame(centre, maxf(width, depth) * 1.15)
	return await _shoot(path)


func _capture_closeup(tile_id: String, path: String) -> bool:
	_clear_stage()
	var patch := maxi(1, int(_options.get("patch", 3)))
	_add_patch(tile_id, Vector3.ZERO, patch)
	var extent := (patch - 1) * _tile_size * 0.5
	_frame(Vector3(extent, 0.0, extent), patch * _tile_size * 2.6)
	return await _shoot(path)


## A patch rather than a lone tile: neighbouring copies are what reveal seams,
## edge treatment and whether a family tiles cleanly.
func _add_patch(tile_id: String, origin: Vector3, size: int) -> void:
	var def = _registries.tiles.get(tile_id)
	if def == null:
		push_warning("tile_gallery: unknown tile '%s'" % tile_id)
		return
	for x in size:
		for z in size:
			var mask := 0
			if def.connection_mode == "full_flush":
				mask = _patch_neighbour_mask(x, z, size)
			var coord := Vector2i(x, z)
			var visual := _factory.instantiate_visual(
				def,
				false,
				mask,
				TileVisualFactory.detail_variant_for_coord(def, coord)
			)
			visual.position = origin + Vector3(x * _tile_size, 0.0, z * _tile_size)
			_stage.add_child(visual)


## Cardinal neighbours available inside one square patch. This is deliberately
## identical to Asset Studio's F8 preview and WorldRenderer's bit contract:
## 1 north, 2 east, 4 south, 8 west. The old screenshotter passed 0xFF, which
## selected no valid baked topology and silently fell back to isolated meshes.
static func _patch_neighbour_mask(x: int, z: int, size: int) -> int:
	return (
		(1 if z > 0 else 0)
		| (2 if x < size - 1 else 0)
		| (4 if z < size - 1 else 0)
		| (8 if x > 0 else 0)
	)


func _frame(target: Vector3, span: float) -> void:
	var pitch_deg := float(_registries.tuning.get("camera_pitch_deg", -40.0))
	var yaw_deg := float(_registries.tuning.get("camera_default_yaw_deg", 45.0))
	var fov := deg_to_rad(_camera.fov)
	var distance := (span * 0.5) / maxf(0.05, tan(fov * 0.5))
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	var offset := basis * Vector3(0.0, 0.0, distance)
	_camera.global_transform = Transform3D(basis, target + offset)
	_camera.near = maxf(1.0, distance - span)
	_camera.far = distance + span * 2.0
	if _lighting != null:
		_lighting.set_camera_shadow_distance(distance)


func _shoot(path: String) -> bool:
	for _i in _frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# Match the display blit and the official gameplay capture harness. With
	# hdr_2d enabled this image is still linear; saving it directly produces a
	# visibly darker PNG even though the live viewport is correctly lit.
	if bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false)):
		GGCaptureEncode.encode_srgb(image)
	var absolute := _absolute_dir(path) if not path.is_absolute_path() else path
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	return image.save_png(absolute) == OK


func _clear_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()


func _requested_tile_ids() -> PackedStringArray:
	var explicit := String(_options.get("tiles", ""))
	var result := PackedStringArray()
	if not explicit.is_empty():
		for raw in explicit.split(",", false):
			var id := String(raw).strip_edges()
			if not id.is_empty():
				result.append(id)
		return result
	var ids: Array = _registries.tiles.keys()
	ids.sort()
	for id in ids:
		result.append(String(id))
	return result


## Suma's own sky — gradient gradients, the void cloud sea, weather particles —
## is deliberate game identity, but it is noise in a tile capture: it puts a
## moving, non-uniform field behind the very silhouettes being judged. The
## gallery flattens it to a single colour so a capture can be compared with the
## Garden Galaxy references, which are flat-background by construction. This
## changes the capture only; gameplay backgrounds are untouched.
func _flatten_background() -> void:
	if _lighting.void_clouds != null:
		_lighting.void_clouds.visible = false
	# Hide only atmosphere backdrops. GGColorGrade is the production noon
	# post-process (including its +0.3 EV exposure) and must remain enabled or
	# the raw linear camera buffer appears much darker than gameplay.
	var canvas_backdrop := _lighting.find_child(
		"Backdrop", true, false
	) as CanvasLayer
	if canvas_backdrop != null:
		canvas_backdrop.visible = false
	var gg_backdrop := _lighting.find_child(
		"GGBackdrop", true, false
	) as MeshInstance3D
	if gg_backdrop != null:
		gg_backdrop.visible = false
	for particles in _lighting.find_children("*", "GPUParticles3D", true, false):
		(particles as GPUParticles3D).emitting = false
	var found := _lighting.find_children("*", "WorldEnvironment", true, false)
	if found.is_empty():
		return
	var environment: Environment = (found[0] as WorldEnvironment).environment
	if environment == null:
		return
	environment.background_mode = Environment.BG_COLOR
	# Environment.background_color is consumed as a linear value, so assigning an
	# authored sRGB colour renders it one sRGB->linear conversion too dark
	# (#CCC6AF displayed as #998F6D). Pre-encode so the authored colour is what
	# actually appears behind the tiles.
	environment.background_color = _palette.color("background_day").linear_to_srgb()
	environment.fog_enabled = false


## Minimal tile-only catalog load, used when whole-catalog validation fails for
## reasons a tile capture does not care about. Prints what it stepped over so a
## degraded run is never mistaken for a healthy one.
func _load_tiles_unvalidated(base_path: String) -> void:
	push_warning(
		"tile_gallery: catalog validation failed; loading tiles.json unvalidated. "
		+ "Captures are still real geometry, but content errors elsewhere are unfixed."
	)
	_registries.tuning = _read_json_object(base_path + "/tuning.json")
	var tiles := _read_json_object(base_path + "/tiles.json")
	for entry in tiles.get("tiles", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var definition = Defs.TileDefinition.from_dict(entry)
		if definition != null:
			_registries.tiles[definition.id] = definition
	print("tile_gallery: loaded %d tiles unvalidated" % _registries.tiles.size())


func _read_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _absolute_dir(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _parse_options() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if not text.begins_with("--") or "=" not in text:
			continue
		var split := text.trim_prefix("--").split("=", true, 1)
		result[split[0]] = split[1]
	return result
