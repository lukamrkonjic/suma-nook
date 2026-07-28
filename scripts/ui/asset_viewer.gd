class_name AssetViewer
extends CanvasLayer
## Debug-only in-game asset review room.
##
## The viewer uses the production AssetLibrary, MaterialLibrary, LightingRig,
## weather profiles, and post-processing. Tiles are shown as a 3x3 patch so
## seams are visible; registered models are shown on the standard neutral tile.
## Closing the viewer restores the exact gameplay camera, lighting state, pause
## state, and visibility it found.

signal closed

const TILE_PATCH_RADIUS := 1
const DEFAULT_TILE_ID := "tile_sand"
const MODEL_BASE_ASSET := "tile_plain_ground"
const WEATHER_PRESETS := [
	["Day", "day"],
	["Mist", "mist"],
	["Rain", "rain"],
	["Snow", "snow"],
	["Leaves", "leaves"],
	["Blossom", "blossom"],
]
const LIGHT_PRESETS := [
	["Morning", "morning"],
	["Noon", "noon"],
	["Sunset", "sunset"],
	["Night", "night"],
]

var _main: Main
var _kit: UiKit
var _assets: AssetLibrary

var _root: Control
var _preview_input: Control
var _list: VBoxContainer
var _search: LineEdit
var _title: Label
var _subtitle: Label
var _status: Label
var _hint: Label
var _tile_tab: Button
var _model_tab: Button
var _weather_buttons: Dictionary = {}
var _light_buttons: Dictionary = {}

var _preview_root: Node3D
var _content_root: Node3D
var _camera: Camera3D
var _target := Vector3.ZERO
var _orbit_yaw := deg_to_rad(45.0)
var _orbit_pitch := deg_to_rad(29.0)
var _orbit_distance := 8.0
var _dragging := false

var _category := "tiles"
var _selected_content_id := ""
var _selected_asset_id := ""
var _entries: Array[Dictionary] = []
var _saved_visibility: Dictionary = {}
var _saved_camera: Camera3D
var _saved_lighting_state: Dictionary = {}
var _saved_lighting_process_mode := Node.PROCESS_MODE_INHERIT
var _saved_tree_paused := false
var _saved_tuner_visible := false


func setup(game: Main) -> void:
	_main = game
	_kit = game.kit
	_assets = game.assets
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_preview_stage()
	_build_ui()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_saved_tree_paused = get_tree().paused
	_saved_camera = get_viewport().get_camera_3d()
	_saved_lighting_state = _main.lighting.runtime_manifest().get(
		"runtime_state", {}
	).duplicate(true)
	_saved_lighting_process_mode = _main.lighting.process_mode
	_saved_tuner_visible = (
		_main.lighting_tuner != null and _main.lighting_tuner.visible
	)
	if _main.lighting_tuner != null:
		_main.lighting_tuner.visible = false
	_main.lighting.process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_gameplay_presentation()
	_preview_root.visible = true
	_camera.current = true
	visible = true
	get_tree().paused = true
	if _selected_content_id.is_empty():
		select_content(DEFAULT_TILE_ID)
	else:
		_rebuild_preview()
	_refresh_preset_buttons()
	_search.grab_focus()


func close() -> void:
	if not visible:
		return
	_dragging = false
	visible = false
	_preview_root.visible = false
	_restore_gameplay_presentation()
	_main.lighting.apply_runtime_state(_saved_lighting_state)
	_main.lighting.process_mode = _saved_lighting_process_mode
	if _main.lighting_tuner != null:
		_main.lighting_tuner.visible = _saved_tuner_visible
	if is_instance_valid(_saved_camera):
		_saved_camera.current = true
	get_tree().paused = _saved_tree_paused
	closed.emit()


func selected_asset_id() -> String:
	return _selected_asset_id


func selected_category() -> String:
	return _category


func select_content(content_id: String) -> void:
	var definition
	if _main.core.registries.tiles.has(content_id):
		_category = "tiles"
		definition = _main.core.registries.tile(content_id)
	elif _main.core.registries.structures.has(content_id):
		_category = "models"
		definition = _main.core.registries.structure(content_id)
	else:
		return
	_selected_content_id = content_id
	_selected_asset_id = definition.asset_id
	_search.text = ""
	_rebuild_catalog()
	_rebuild_preview()


func select_asset(asset_id: String) -> void:
	for tile_id: String in _main.core.registries.tiles:
		var tile := _main.core.registries.tile(tile_id)
		if tile.asset_id == asset_id:
			select_content(tile_id)
			return
	for structure_id: String in _main.core.registries.structures:
		var structure := _main.core.registries.structure(structure_id)
		if structure.asset_id == asset_id:
			select_content(structure_id)
			return


func set_weather_preset(preset_id: String) -> void:
	_main.lighting.set_weather(preset_id)
	_status.text = "%s weather · production profile" % preset_id.capitalize()
	_refresh_preset_buttons()


func set_light_preset(preset_id: String) -> void:
	_main.lighting.set_time_of_day(preset_id)
	_status.text = "%s light · production profile" % preset_id.capitalize()
	_refresh_preset_buttons()


func reset_view() -> void:
	_orbit_yaw = deg_to_rad(45.0)
	_orbit_pitch = deg_to_rad(29.0)
	_frame_preview()


func capture_png() -> void:
	if _selected_asset_id.is_empty():
		return
	var directory := "user://asset_viewer_captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var filename := "%s_%s_%s.png" % [
		_selected_asset_id,
		_main.lighting.weather_id(),
		_main.lighting.time_of_day_id,
	]
	var absolute_path := ProjectSettings.globalize_path(
		directory.path_join(filename)
	)
	_status.text = "Capturing %s…" % filename
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(absolute_path)
	_status.text = (
		"Saved %s" % absolute_path
		if error == OK
		else "Capture failed: %s" % error_string(error)
	)


func _build_preview_stage() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "AssetViewerStage"
	_preview_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_main.world_root.add_child(_preview_root)
	_content_root = Node3D.new()
	_content_root.name = "PreviewContent"
	_preview_root.add_child(_content_root)
	_camera = Camera3D.new()
	_camera.name = "AssetViewerCamera"
	_camera.fov = 34.0
	_camera.near = 0.05
	_camera.far = 150.0
	_preview_root.add_child(_camera)
	_preview_root.visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "AssetViewerRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.theme = _kit.theme
	add_child(_root)

	_preview_input = Control.new()
	_preview_input.name = "AssetViewerPreviewInput"
	_preview_input.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_input.offset_left = 326.0
	_preview_input.offset_top = 76.0
	_preview_input.offset_bottom = -118.0
	_preview_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_input.gui_input.connect(_on_preview_input)
	_root.add_child(_preview_input)

	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 14.0
	header.offset_top = 14.0
	header.offset_right = -14.0
	header.offset_bottom = 68.0
	header.add_theme_stylebox_override("panel", _kit.panel_style(false, 16))
	_root.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	header.add_child(header_row)
	var heading := _kit.label("ASSET VIEWER", 22, false, true)
	header_row.add_child(heading)
	_title = _kit.label("Choose a tile or model", 20, false, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_row.add_child(_title)
	var center_button := _compact_button("Center")
	center_button.name = "AssetViewerCenter"
	center_button.pressed.connect(reset_view)
	header_row.add_child(center_button)
	var close_button := _compact_button("Return to Game", true)
	close_button.name = "AssetViewerReturn"
	close_button.pressed.connect(close)
	header_row.add_child(close_button)

	var browser := PanelContainer.new()
	browser.name = "AssetViewerBrowser"
	browser.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	browser.offset_left = 14.0
	browser.offset_top = 76.0
	browser.offset_right = 314.0
	browser.offset_bottom = -118.0
	browser.add_theme_stylebox_override("panel", _kit.panel_style(false, 18))
	_root.add_child(browser)
	var browser_column := VBoxContainer.new()
	browser_column.add_theme_constant_override("separation", 8)
	browser.add_child(browser_column)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	browser_column.add_child(tabs)
	_tile_tab = _kit.choice_button("Tiles", true)
	_tile_tab.name = "AssetViewerTabTiles"
	_tile_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_tab.pressed.connect(_set_category.bind("tiles"))
	tabs.add_child(_tile_tab)
	_model_tab = _kit.choice_button("Models")
	_model_tab.name = "AssetViewerTabModels"
	_model_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_tab.pressed.connect(_set_category.bind("models"))
	tabs.add_child(_model_tab)
	_search = LineEdit.new()
	_search.name = "AssetViewerSearch"
	_search.placeholder_text = "Search name or asset id…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 42.0
	_search.text_changed.connect(func(_value: String): _rebuild_catalog())
	browser_column.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.name = "AssetViewerCatalogScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser_column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

	var info := PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -365.0
	info.offset_top = 82.0
	info.offset_right = -18.0
	info.offset_bottom = 168.0
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_stylebox_override("panel", _translucent_panel())
	_root.add_child(info)
	var info_column := VBoxContainer.new()
	info_column.add_theme_constant_override("separation", 2)
	info.add_child(info_column)
	_subtitle = _kit.label("Production GLB", 14, false, true)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_column.add_child(_subtitle)
	_hint = _kit.label(
		"Drag to orbit  ·  Wheel to zoom  ·  3×3 tile seam check",
		13
	)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_column.add_child(_hint)

	var controls := PanelContainer.new()
	controls.name = "AssetViewerBottomControls"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 14.0
	controls.offset_top = -106.0
	controls.offset_right = -14.0
	controls.offset_bottom = -14.0
	controls.add_theme_stylebox_override("panel", _kit.panel_style(false, 18))
	_root.add_child(controls)
	var control_column := VBoxContainer.new()
	control_column.add_theme_constant_override("separation", 5)
	controls.add_child(control_column)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	control_column.add_child(preset_row)
	preset_row.add_child(_group_label("LIGHT"))
	for preset in LIGHT_PRESETS:
		var button := _preset_button(String(preset[0]))
		var preset_id := String(preset[1])
		button.name = "AssetViewerLight" + preset_id.to_pascal_case()
		button.pressed.connect(set_light_preset.bind(preset_id))
		_light_buttons[preset_id] = button
		preset_row.add_child(button)
	preset_row.add_child(_divider())
	preset_row.add_child(_group_label("WEATHER"))
	for preset in WEATHER_PRESETS:
		var button := _preset_button(String(preset[0]))
		var preset_id := String(preset[1])
		button.name = "AssetViewerWeather" + preset_id.to_pascal_case()
		button.pressed.connect(set_weather_preset.bind(preset_id))
		_weather_buttons[preset_id] = button
		preset_row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(spacer)
	var tune := _compact_button("Fine Tune")
	tune.name = "AssetViewerFineTune"
	tune.pressed.connect(_toggle_fine_tuner)
	preset_row.add_child(tune)
	var capture := _compact_button("Capture PNG", true)
	capture.name = "AssetViewerCapture"
	capture.pressed.connect(capture_png)
	preset_row.add_child(capture)
	_status = _kit.label(
		"Select an asset, then compare it under production conditions.",
		13
	)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_column.add_child(_status)
	_rebuild_catalog()


func _hide_gameplay_presentation() -> void:
	_saved_visibility.clear()
	for node: Node in [
		_main.renderer,
		_main.effects,
		_main.delivery_point,
		_main.ferry_presentation,
		_main.player,
		_main.camera_rig,
		_main.placement,
		_main.hud,
		_main.panels,
		_main.parcel_reveal,
		_main.pixel_look,
	]:
		if node is CanvasLayer:
			_saved_visibility[node] = (node as CanvasLayer).visible
			(node as CanvasLayer).visible = false
		elif node is CanvasItem:
			_saved_visibility[node] = (node as CanvasItem).visible
			(node as CanvasItem).visible = false
		elif node is Node3D:
			_saved_visibility[node] = (node as Node3D).visible
			(node as Node3D).visible = false


func _restore_gameplay_presentation() -> void:
	for node: Node in _saved_visibility:
		if not is_instance_valid(node):
			continue
		if node is CanvasLayer:
			(node as CanvasLayer).visible = bool(_saved_visibility[node])
		elif node is CanvasItem:
			(node as CanvasItem).visible = bool(_saved_visibility[node])
		elif node is Node3D:
			(node as Node3D).visible = bool(_saved_visibility[node])
	_saved_visibility.clear()


func _set_category(category: String) -> void:
	if category not in ["tiles", "models"]:
		return
	_category = category
	_search.text = ""
	_rebuild_catalog()
	var first := _first_visible_entry()
	if not first.is_empty():
		select_content(String(first["content_id"]))


func _rebuild_catalog() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_entries.clear()
	if _category == "tiles":
		for content_id: String in _main.core.registries.tiles:
			var definition := _main.core.registries.tile(content_id)
			_entries.append({
				"content_id": content_id,
				"asset_id": definition.asset_id,
				"name": definition.display_name,
			})
	else:
		for content_id: String in _main.core.registries.structures:
			var definition := _main.core.registries.structure(content_id)
			_entries.append({
				"content_id": content_id,
				"asset_id": definition.asset_id,
				"name": definition.display_name,
			})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	var query := _search.text.strip_edges().to_lower()
	for entry: Dictionary in _entries:
		var haystack := (
			"%s %s %s"
			% [entry["name"], entry["content_id"], entry["asset_id"]]
		).to_lower()
		if not query.is_empty() and not haystack.contains(query):
			continue
		var selected := String(entry["content_id"]) == _selected_content_id
		var button := _catalog_button(entry, selected)
		_list.add_child(button)
	_tile_tab.set_pressed_no_signal(_category == "tiles")
	_model_tab.set_pressed_no_signal(_category == "models")


func _catalog_button(entry: Dictionary, selected: bool) -> Button:
	var button := _kit.choice_button(String(entry["name"]), selected)
	button.name = "AssetViewerItem_" + String(entry["content_id"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 43.0)
	button.tooltip_text = "%s\n%s" % [entry["content_id"], entry["asset_id"]]
	button.pressed.connect(select_content.bind(String(entry["content_id"])))
	return button


func _first_visible_entry() -> Dictionary:
	var query := _search.text.strip_edges().to_lower()
	for entry: Dictionary in _entries:
		var haystack := (
			"%s %s %s"
			% [entry["name"], entry["content_id"], entry["asset_id"]]
		).to_lower()
		if query.is_empty() or haystack.contains(query):
			return entry
	return {}


func _rebuild_preview() -> void:
	if _selected_asset_id.is_empty() or not _assets.exists(_selected_asset_id):
		_status.text = "Missing production asset: %s" % _selected_asset_id
		return
	for child in _content_root.get_children():
		child.free()
	var tile_size: float = _main.core.grid.tile_size
	if _category == "tiles":
		for z in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
			for x in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
				var tile := _assets.instantiate(_selected_asset_id)
				tile.position = Vector3(x * tile_size, 0.0, z * tile_size)
				_content_root.add_child(tile)
	else:
		_content_root.add_child(_assets.instantiate(MODEL_BASE_ASSET))
		var model := _assets.instantiate(_selected_asset_id)
		_content_root.add_child(model)
		var definition := _main.core.registries.structure(
			_selected_content_id
		)
		if definition != null and definition.has_capability("light"):
			_add_production_warm_light(model, definition)
	_title.text = _display_name(_selected_content_id)
	_subtitle.text = "%s  ·  %s" % [
		_selected_asset_id,
		"3×3 seam patch" if _category == "tiles" else "production model",
	]
	_hint.text = (
		"Drag to orbit  ·  Wheel to zoom  ·  inspect all tile seams"
		if _category == "tiles"
		else "Drag to orbit  ·  Wheel to zoom  ·  shown on the default tile"
	)
	_status.text = "Viewing %s under live Suma lighting." % _selected_asset_id
	_frame_preview()


func _frame_preview() -> void:
	var bounds := _combined_bounds(_content_root)
	if bounds.size.length_squared() <= 0.0001:
		_target = Vector3.ZERO
		_orbit_distance = 7.0
	else:
		_target = bounds.get_center()
		var radius := maxf(
			bounds.size.y,
			maxf(bounds.size.x, bounds.size.z)
		) * 0.5
		_orbit_distance = clampf(radius * 3.7, 3.6, 34.0)
	_refresh_camera()


func _combined_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for descendant in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := descendant as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.get_aabb()
		for endpoint_index in 8:
			var point := root.to_local(
				mesh_instance.to_global(local_bounds.get_endpoint(endpoint_index))
			)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result


func _refresh_camera() -> void:
	var horizontal := cos(_orbit_pitch)
	var offset := Vector3(
		sin(_orbit_yaw) * horizontal,
		sin(_orbit_pitch),
		cos(_orbit_yaw) * horizontal
	) * _orbit_distance
	_camera.position = _target + offset
	_camera.look_at(_target, Vector3.UP)


func _add_production_warm_light(
	parent: Node3D,
	definition: Defs.StructureDefinition
) -> void:
	var base_energy := (
		1.1
		if definition.id in ["struct_campfire", "struct_firepit_polished"]
		else 0.6
	)
	var light := OmniLight3D.new()
	light.name = "AssetViewerProductionLight"
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 4.5
	light.position.y = definition.light_height
	light.light_energy = _main.lighting.local_light_energy(base_energy)
	light.set_meta("base_energy", base_energy)
	light.add_to_group("warm_lights")
	parent.add_child(light)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
			_preview_input.accept_event()
		elif mouse.pressed and mouse.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN
		]:
			var direction := -1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_orbit_distance = clampf(
				_orbit_distance * (1.0 + direction * 0.1),
				2.0,
				40.0
			)
			_refresh_camera()
			_preview_input.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * 0.008
		_orbit_pitch = clampf(
			_orbit_pitch - motion.relative.y * 0.006,
			deg_to_rad(8.0),
			deg_to_rad(78.0)
		)
		_refresh_camera()
		_preview_input.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).physical_keycode == KEY_F8
	):
		close()
		get_viewport().set_input_as_handled()


func _toggle_fine_tuner() -> void:
	var shown := _main.toggle_lighting_tuner()
	_status.text = (
		"Fine tuner open · changes apply live to this review."
		if shown
		else "Fine tuner closed."
	)


func _refresh_preset_buttons() -> void:
	for preset_id: String in _weather_buttons:
		(_weather_buttons[preset_id] as Button).set_pressed_no_signal(
			preset_id == _main.lighting.weather_id()
		)
	for preset_id: String in _light_buttons:
		(_light_buttons[preset_id] as Button).set_pressed_no_signal(
			preset_id == _main.lighting.time_of_day_id
		)


func _display_name(content_id: String) -> String:
	if _main.core.registries.tiles.has(content_id):
		return _main.core.registries.tile(content_id).display_name
	if _main.core.registries.structures.has(content_id):
		return _main.core.registries.structure(content_id).display_name
	return content_id


func _compact_button(text: String, accent := false) -> Button:
	var button := _kit.button(text, accent)
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _preset_button(text: String) -> Button:
	var button := _kit.choice_button(text)
	button.custom_minimum_size = Vector2(68.0, 34.0)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _group_label(text: String) -> Label:
	var label := _kit.label(text, 12, false, true)
	label.custom_minimum_size.x = 62.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override(
		"font_color", _kit.palette.color("ui_good").darkened(0.12)
	)
	return label


func _divider() -> VSeparator:
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 12.0
	return divider


func _translucent_panel() -> StyleBoxFlat:
	var style := _kit.panel_style(false, 16)
	style.bg_color = Color(0.95, 0.94, 0.89, 0.84)
	return style
