class_name AdminAssetWorld
extends Node3D
## Debug-only curated tile and large-placeable gallery.
##
## The roster comes from the tile and structure registries. Small scatter
## meshes remain out of the gallery until they are promoted to intentional,
## player-placeable content.

const MAIN_SCENE := "res://scenes/main.tscn"
const SLOT_SPACING := 4.6
const SECTION_GAP := 7.0
const COLUMNS := 6
const CAMERA_MIN_DISTANCE := 12.0
const CAMERA_MAX_DISTANCE := 260.0
const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)
const CATEGORY_ORDER := [
	"Tiles",
	"Large Decor",
	"Structures",
]

var registries: Registries
var palette: CozyPalette
var materials: MaterialLibrary
var assets: AssetLibrary
var kit: UiKit
var _tile_visual_factory: TileVisualFactory
var _structure_visual_factory: RefCounted

var _manifest: Array[Dictionary] = []
var _slot_records: Array[Dictionary] = []
var _section_frames: Dictionary = {}
var _section_names: Array[String] = []
var _gallery_root: Node3D
var _lighting: LightingRig

var _camera_rig: Node3D
var _pitch: Node3D
var _camera: Camera3D
var _target_position := Vector3.ZERO
var _target_distance := 48.0
var _target_yaw := 45.0
var _dragging := false

var _section_picker: OptionButton
var _section_status: Label
var _font: FontFile


func _ready() -> void:
	DisplayServer.window_set_title("Suma Nook — Admin Asset World")
	_setup_services()
	_build_lighting()
	_manifest = _build_manifest()
	_build_gallery()
	_build_camera()
	_build_ui()
	focus_section("Tiles", true)
	_handle_command_line()


func _setup_services() -> void:
	registries = Registries.new()
	if not registries.load_all():
		push_error("AdminAssetWorld: content registries failed to load")
	palette = load("res://assets/palettes/gg_material_palette.tres")
	materials = MaterialLibrary.new(palette)
	assets = AssetLibrary.new(materials)
	var grid := WorldGrid.new(registries)
	_tile_visual_factory = TileVisualFactory.new(assets, grid)
	_structure_visual_factory = StructureVisualFactoryScript.new(assets, grid)
	kit = UiKit.new(palette)
	_font = load("res://assets/fonts/Fredoka-Medium.ttf")


func _build_lighting() -> void:
	_lighting = (load("res://scenes/visual/GGDayLightingRig.tscn") as PackedScene).instantiate()
	_lighting.name = "GalleryLighting"
	add_child(_lighting)
	_lighting.set_camera_shadow_distance(110.0)


func _build_manifest() -> Array[Dictionary]:
	var by_asset := {}

	for tile: Defs.TileDefinition in registries.tiles.values():
		_register_entry(by_asset, tile.asset_id, tile.display_name, "Tiles", tile.id)

	for structure: Defs.StructureDefinition in registries.structures.values():
		var category := "Large Decor" if structure.socket_type == "decor" else "Structures"
		_register_entry(by_asset, structure.asset_id, structure.display_name, category, structure.id)

	var result: Array[Dictionary] = []
	for entry: Dictionary in by_asset.values():
		entry["exists"] = assets.exists(String(entry["asset_id"]))
		entry["base_tile"] = _presentation_tile_for(String(entry["category"]))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_a := CATEGORY_ORDER.find(String(a["category"]))
		var category_b := CATEGORY_ORDER.find(String(b["category"]))
		if category_a == category_b:
			return String(a["asset_id"]) < String(b["asset_id"])
		return category_a < category_b
	)
	return result


func _register_entry(
	by_asset: Dictionary,
	asset_id: String,
	display_name: String,
	category: String,
	source_id: String
) -> void:
	if asset_id == "":
		return
	if by_asset.has(asset_id):
		var existing: Dictionary = by_asset[asset_id]
		if source_id != "" and not existing["source_ids"].has(source_id):
			existing["source_ids"].append(source_id)
		return
	by_asset[asset_id] = {
		"asset_id": asset_id,
		"display_name": display_name,
		"category": category,
		"source_ids": [source_id] if source_id != "" else [],
	}


func _presentation_tile_for(category: String) -> String:
	match category:
		"Large Decor":
			return "tile_grass"
		"Structures":
			return "tile_stone_clearing"
		_:
			return ""


func _humanize_asset_id(asset_id: String) -> String:
	var words := asset_id.split("_")
	if words.size() > 1 and words[0] in ["tile", "prop", "equip", "enemy", "fx", "calib"]:
		words.remove_at(0)
	var result := PackedStringArray()
	for word in words:
		result.append(String(word).capitalize())
	return " ".join(result)


func _build_gallery() -> void:
	_gallery_root = Node3D.new()
	_gallery_root.name = "AssetGrid"
	add_child(_gallery_root)

	var cursor_z := 0.0
	var world_min := Vector2(INF, INF)
	var world_max := Vector2(-INF, -INF)
	for category in CATEGORY_ORDER:
		var entries := _entries_in_category(category)
		if entries.is_empty():
			continue
		_section_names.append(category)
		var rows := ceili(float(entries.size()) / float(COLUMNS))
		var columns := mini(COLUMNS, entries.size())
		var span_x := maxf(2.0, float(columns - 1) * SLOT_SPACING + 2.0)
		var span_z := maxf(2.0, float(rows - 1) * SLOT_SPACING + 2.0)
		var center := Vector3(
			float(columns - 1) * SLOT_SPACING * 0.5,
			0.0,
			cursor_z + float(rows - 1) * SLOT_SPACING * 0.5
		)
		_section_frames[category] = {
			"center": center,
			"span": Vector2(span_x, span_z),
			"count": entries.size(),
		}
		_add_section_label(category, entries.size(), Vector3(center.x, 0.12, cursor_z - 2.8))

		for index in entries.size():
			var column := index % COLUMNS
			var row := index / COLUMNS
			var position := Vector3(float(column) * SLOT_SPACING, 0.0, cursor_z + float(row) * SLOT_SPACING)
			_build_slot(entries[index], position)

		world_min.x = minf(world_min.x, -3.0)
		world_min.y = minf(world_min.y, cursor_z - 3.5)
		world_max.x = maxf(world_max.x, float(columns - 1) * SLOT_SPACING + 3.0)
		world_max.y = maxf(world_max.y, cursor_z + float(rows - 1) * SLOT_SPACING + 3.0)
		cursor_z += float(rows) * SLOT_SPACING + SECTION_GAP

	var overview_center := Vector3(
		(world_min.x + world_max.x) * 0.5,
		0.0,
		(world_min.y + world_max.y) * 0.5
	)
	_section_frames["Overview"] = {
		"center": overview_center,
		"span": world_max - world_min,
		"count": _manifest.size(),
	}
	_section_names.insert(0, "Overview")


func _entries_in_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _manifest:
		if entry["category"] == category:
			result.append(entry)
	return result


func _build_slot(entry: Dictionary, world_position: Vector3) -> void:
	var slot := Node3D.new()
	var asset_id := String(entry["asset_id"])
	slot.name = "Asset_%s" % asset_id
	slot.position = world_position
	slot.set_meta("asset_id", asset_id)
	slot.set_meta("category", entry["category"])
	_gallery_root.add_child(slot)

	var base_tile := String(entry["base_tile"])
	if base_tile != "":
		var plinth_def := registries.tile(base_tile)
		var plinth := _tile_visual_factory.instantiate_visual(plinth_def)
		plinth.name = "PresentationTile"
		slot.add_child(plinth)

	var model: Node3D
	if String(entry["category"]) == "Tiles" and entry["source_ids"].size() > 0:
		var tile_def := registries.tile(String(entry["source_ids"][0]))
		if tile_def != null and tile_def.render_profile != "continuous_water":
			model = _tile_visual_factory.instantiate_visual(tile_def)
		else:
			model = _build_open_water_preview()
	elif (
		String(entry["category"]) in ["Large Decor", "Structures"]
		and entry["source_ids"].size() > 0
	):
		var structure_def := registries.structure(String(entry["source_ids"][0]))
		if structure_def != null:
			model = _structure_visual_factory.instantiate_visual(structure_def)
		else:
			model = assets.instantiate(asset_id)
	elif asset_id == "tile_open_water" and not assets.exists(asset_id):
		model = _build_open_water_preview()
	else:
		model = assets.instantiate(asset_id)
	model.name = "DisplayedAsset"
	slot.add_child(model)
	if base_tile != "":
		_raise_to_tile_surface(model)

	var label := _asset_label(
		String(entry["display_name"]),
		asset_id,
		String(entry["category"])
	)
	slot.add_child(label)

	_slot_records.append({
		"asset_id": asset_id,
		"category": entry["category"],
		"base_tile": base_tile,
		"world_position": world_position,
		"node": slot,
	})


func _build_open_water_preview() -> Node3D:
	var root := Node3D.new()
	var floor := assets.instantiate("tile_water_floor")
	floor.name = "WaterFloor"
	var tile_size := _tile_visual_factory.grid.tile_size
	var horizontal_scale := tile_size / TileVisualFactory.AUTHORED_TILE_SIZE
	floor.scale = Vector3(horizontal_scale, 1.0, horizontal_scale)
	root.add_child(floor)
	var surface := WaterSurface.new()
	surface.name = "WaterSurface"
	root.add_child(surface)
	surface.rebuild(
		[Vector2i.ZERO],
		func(_cell: Vector2i) -> Vector3: return Vector3.ZERO,
		tile_size,
		-0.14,
		materials.material("water")
	)
	return root


func _raise_to_tile_surface(model: Node3D) -> void:
	var bounds := _combined_local_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	model.position.y += 0.08 - bounds.position.y


func _combined_local_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	var to_root := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform_to_root := to_root * mesh_instance.global_transform
		var local_bounds: AABB = transform_to_root * mesh_instance.get_aabb()
		if not has_bounds:
			result = local_bounds
			has_bounds = true
		else:
			result = result.merge(local_bounds)
	return result


func _asset_label(display_name: String, asset_id: String, category: String) -> Label3D:
	var label := Label3D.new()
	label.name = "AssetLabel"
	label.text = "%s\n%s" % [display_name, asset_id]
	label.font = _font
	label.font_size = 36
	label.pixel_size = 0.009
	label.position = Vector3(0.0, 0.28, 1.45)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.outline_size = 7
	label.modulate = Color(0.21, 0.2, 0.17)
	label.outline_modulate = Color(0.97, 0.96, 0.92, 0.96)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_meta("category", category)
	return label


func _add_section_label(category: String, count: int, position: Vector3) -> void:
	var label := Label3D.new()
	label.name = "Section_%s" % category.replace(" ", "_")
	var qualifier := " · ONE PLACEABLE PER TILE" if category == "Large Decor" else ""
	label.text = "%s · %d%s" % [category.to_upper(), count, qualifier]
	label.font = _font
	label.font_size = 64
	label.pixel_size = 0.012
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.shaded = false
	label.outline_size = 9
	label.modulate = palette.color("ui_good").darkened(0.12)
	label.outline_modulate = Color(0.96, 0.95, 0.9, 0.98)
	_gallery_root.add_child(label)


func _build_camera() -> void:
	_camera_rig = Node3D.new()
	_camera_rig.name = "GalleryCameraRig"
	_camera_rig.rotation_degrees.y = _target_yaw
	add_child(_camera_rig)

	_pitch = Node3D.new()
	_pitch.name = "Pitch"
	_pitch.rotation_degrees.x = -39.0
	_camera_rig.add_child(_pitch)

	_camera = Camera3D.new()
	_camera.name = "GalleryCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _target_distance
	_camera.near = 0.5
	_camera.far = 600.0
	_camera.position.z = 200.0
	_camera.current = true
	_pitch.add_child(_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GalleryUI"
	layer.layer = 40
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = kit.theme
	layer.add_child(root)

	var info := PanelContainer.new()
	info.position = Vector2(22, 22)
	info.add_theme_stylebox_override("panel", kit.cloud_panel_style(22))
	root.add_child(info)
	var info_column := VBoxContainer.new()
	info_column.add_theme_constant_override("separation", 5)
	info.add_child(info_column)
	info_column.add_child(kit.label("Admin Asset World", 28, false, true))
	info_column.add_child(kit.label(
		"%d curated tiles + large placeables · small scatter hidden" % _manifest.size(),
		16
	))
	var controls := kit.label(
		"WASD pan  ·  drag anywhere  ·  wheel zoom  ·  Q/X rotate  ·  H overview",
		14
	)
	controls.add_theme_color_override("font_color", Color(0.47, 0.46, 0.41))
	info_column.add_child(controls)

	var navigation := PanelContainer.new()
	navigation.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	navigation.position = Vector2(-22, 22)
	navigation.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	navigation.add_theme_stylebox_override("panel", kit.cloud_panel_style(22))
	root.add_child(navigation)
	var navigation_column := VBoxContainer.new()
	navigation_column.custom_minimum_size.x = 250
	navigation_column.add_theme_constant_override("separation", 10)
	navigation.add_child(navigation_column)
	_section_status = kit.label("Tiles", 18, false, true)
	navigation_column.add_child(_section_status)
	_section_picker = OptionButton.new()
	_section_picker.name = "GallerySectionPicker"
	_section_picker.custom_minimum_size = Vector2(250, 48)
	_section_picker.add_theme_font_override("font", kit.font_bold)
	_section_picker.add_theme_font_size_override("font_size", 17)
	for section_name in _section_names:
		_section_picker.add_item(section_name)
	_section_picker.item_selected.connect(func(index: int):
		focus_section(_section_picker.get_item_text(index))
	)
	navigation_column.add_child(_section_picker)
	var exit := kit.button("Exit to Game")
	exit.name = "GalleryExitButton"
	exit.pressed.connect(_return_to_game)
	navigation_column.add_child(exit)


func _process(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if movement.length_squared() > 0.0:
		var right := _camera_rig.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var forward := -_camera_rig.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var speed := maxf(8.0, _target_distance * 0.32)
		_target_position += (right * movement.x + forward * -movement.y) * speed * delta
		_clamp_target()

	_camera_rig.position = _camera_rig.position.lerp(_target_position, minf(1.0, delta * 8.0))
	_camera_rig.rotation.y = lerp_angle(
		_camera_rig.rotation.y,
		deg_to_rad(_target_yaw),
		minf(1.0, delta * 9.0)
	)
	_camera.size = lerpf(_camera.size, _target_distance, minf(1.0, delta * 9.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		_return_to_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("return_home"):
		focus_section("Overview")
	elif event.is_action_pressed("camera_rotate_left"):
		_target_yaw += 90.0
	elif event.is_action_pressed("camera_rotate_right"):
		_target_yaw -= 90.0
	elif event.is_action_pressed("camera_zoom_in"):
		_zoom(-4.0)
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom(4.0)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse.pressed
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-maxf(1.0, mouse.factor) * 4.0)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(maxf(1.0, mouse.factor) * 4.0)
	elif event is InputEventMouseMotion and _dragging:
		_pan_pixels((event as InputEventMouseMotion).relative)
	elif event is InputEventPanGesture:
		_pan_pixels((event as InputEventPanGesture).delta * 16.0)
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom((1.0 - magnify.factor) * 24.0)


func _pan_pixels(relative: Vector2) -> void:
	var right := _camera_rig.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -_camera_rig.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var scale := _target_distance * 0.00125
	_target_position += right * -relative.x * scale + forward * relative.y * scale
	_clamp_target()


func _zoom(amount: float) -> void:
	_target_distance = clampf(
		_target_distance + amount,
		CAMERA_MIN_DISTANCE,
		CAMERA_MAX_DISTANCE
	)
	_lighting.set_camera_shadow_distance(minf(_target_distance * 1.7, 180.0))


func _clamp_target() -> void:
	var overview: Dictionary = _section_frames.get("Overview", {})
	if overview.is_empty():
		return
	var center: Vector3 = overview["center"]
	var span: Vector2 = overview["span"]
	_target_position.x = clampf(_target_position.x, center.x - span.x * 0.6, center.x + span.x * 0.6)
	_target_position.z = clampf(_target_position.z, center.z - span.y * 0.55, center.z + span.y * 0.55)


func focus_section(section_name: String, immediate := false) -> void:
	if not _section_frames.has(section_name):
		return
	var frame: Dictionary = _section_frames[section_name]
	_target_position = frame["center"]
	var span: Vector2 = frame["span"]
	var viewport_size := get_viewport().get_visible_rect().size
	var viewport_aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	_target_distance = clampf(
		maxf(span.y * 0.9, span.x / viewport_aspect * 1.1) + 4.0,
		CAMERA_MIN_DISTANCE,
		CAMERA_MAX_DISTANCE
	)
	_lighting.set_camera_shadow_distance(minf(_target_distance * 1.7, 180.0))
	if immediate:
		_camera_rig.position = _target_position
		_camera.size = _target_distance
	if _section_status != null:
		_section_status.text = "%s · %d" % [section_name, int(frame["count"])]
	if _section_picker != null:
		var index := _section_names.find(section_name)
		if index >= 0:
			_section_picker.select(index)


func _return_to_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _handle_command_line() -> void:
	var shot_path := ""
	var requested_section := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--section="):
			requested_section = arg.trim_prefix("--section=").replace("_", " ")
	if requested_section != "":
		for section_name in _section_names:
			if section_name.to_lower() == requested_section.to_lower():
				focus_section(section_name, true)
				break
	if shot_path == "":
		return
	get_viewport().gui_disable_input = true
	get_tree().create_timer(2.5).timeout.connect(func():
		var image := get_viewport().get_texture().get_image()
		image.save_png(shot_path)
		print("ADMIN ASSET WORLD SHOT SAVED: " + shot_path)
		get_tree().quit()
	)


func catalog_asset_ids() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _manifest:
		result.append(String(entry["asset_id"]))
	return result


func slot_records() -> Array[Dictionary]:
	return _slot_records.duplicate()


func section_names() -> Array[String]:
	return _section_names.duplicate()


func camera_target() -> Vector3:
	return _target_position
