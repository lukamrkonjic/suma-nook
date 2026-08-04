class_name AssetViewer
extends CanvasLayer
## Debug-only in-game asset authoring room.
##
## The viewer uses the production AssetLibrary, MaterialLibrary, LightingRig,
## weather profiles, and post-processing. Tiles are shown as a 3x3 patch so
## seams are visible; registered models are shown on the standard neutral tile.
## Surface-normal and per-material edits are persisted through AssetLibrary and
## are therefore consumed by the real game, not by a separate preview format.
## Closing the viewer restores the exact gameplay camera, lighting state, pause
## state, and visibility it found.

signal closed

const TILE_PATCH_RADIUS := 1
const CatalogTaxonomy := preload("res://tools/tile_kit/library/tile_catalog_taxonomy.gd")
const DEFAULT_TILE_ID := "tile_sand"
const MODEL_BASE_TILE_ID := "tile_plain_ground"
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
const DESIGN_PALETTE := [
	{
		"label": "Foundations & Neutrals",
		"keys": [
			"warm_white", "ivory_highlight", "plain_ground_gg", "smoke",
			"warm_near_black",
		],
	},
	{
		"label": "Sand",
		"keys": [
			"sand_highlight", "sand_light", "sand_top", "sand_shadow",
			"sand_deep",
		],
	},
	{
		"label": "Snow",
		"keys": [
			"snow_highlight", "snow_light", "snow_top", "snow_shadow",
			"snow_deep", "snow_side",
		],
	},
	{
		"label": "Concrete",
		"keys": [
			"concrete_highlight", "concrete_light", "concrete_top",
			"concrete_shadow", "concrete_deep", "concrete_side",
		],
	},
	{
		"label": "Stone",
		"keys": [
			"stone_light", "stone_mid_light", "stone_mid",
			"stone_warm_shadow", "stone_shadow", "stone_deep_shadow",
			"soft_sage_gray",
		],
	},
	{
		"label": "Grass",
		"keys": [
			"grass_highlight", "grass_sunlit", "grass_primary",
			"grass_secondary", "grass_vivid_accent", "grass_shade",
			"deep_grass",
		],
	},
	{
		"label": "Moss & Olive",
		"keys": [
			"moss_bright", "moss_primary", "olive_shadow", "earthy_olive",
		],
	},
	{
		"label": "Leaves",
		"keys": [
			"leaf_bright", "leaf_soft_sage", "leaf_medium", "leaf_olive",
		],
	},
	{
		"label": "Pine",
		"keys": [
			"pine_light", "pine_medium", "pine_shadow", "pine_deep",
		],
	},
	{
		"label": "Earth",
		"keys": [
			"earth_light", "earth_primary", "earth_mid", "earth_shadow",
			"earth_deep",
		],
	},
	{
		"label": "Soil",
		"keys": [
			"soil_orange", "soil_red_shadow", "soil_deep", "soil_deepest",
		],
	},
	{
		"label": "Wood",
		"keys": [
			"wood_highlight", "wood_light", "wood_gold", "wood_primary",
			"wood_warm_shadow", "wood_brown", "wood_deep", "wood_dark",
		],
	},
	{
		"label": "Terracotta",
		"keys": [
			"terracotta_light", "terracotta_primary", "terracotta_orange",
			"terracotta_shadow",
		],
	},
	{
		"label": "Coral & Red",
		"keys": [
			"burnt_red", "coral", "soft_coral",
		],
	},
	{
		"label": "Gold & Warm Accents",
		"keys": [
			"gold_highlight", "gold_primary", "gold_deep", "warm_yellow",
		],
	},
	{
		"label": "Skin",
		"keys": [
			"skin_light", "skin_mid", "skin_shadow",
		],
	},
	{
		"label": "Hair",
		"keys": [
			"hair_light", "hair_primary", "hair_deep",
		],
	},
	{
		"label": "Fabric",
		"keys": [
			"cream_fabric", "mustard_fabric", "brown_fabric", "dark_fabric",
		],
	},
	{
		"label": "Water",
		"keys": [
			"water_foam", "water_shallow_highlight", "water_shallow",
			"water_turquoise", "water_mid", "water_deep_mid", "water_deep",
			"water_abyss",
		],
	},
	{
		"label": "Underwater Sand & Rock",
		"keys": [
			"uw_sand_light", "uw_sand_shadow", "uw_rock_light",
			"uw_rock_mid", "uw_rock_shadow",
		],
	},
	{
		"label": "Underwater Flora",
		"keys": [
			"uw_flora_light", "uw_flora_mid", "uw_flora_dark",
			"uw_flora_deep",
		],
	},
	{
		"label": "Light & Effects",
		"keys": [
			"fire_core", "fire_yellow", "fire_orange", "fire_red",
			"water_caustic", "crystal", "magic",
		],
	},
	{
		"label": "Petals & Flowers",
		"keys": [
			"petal_white", "petal_pink", "petal_red", "flower_yellow",
		],
	},
]

var _main: Main
var _kit: UiKit
var _input_service: InputDeviceService
var _assets: AssetLibrary
var _tile_factory: TileVisualFactory
var _structure_factory: StructureVisualFactory

var _root: Control
var _preview_input: Control
var _list: VBoxContainer
var _search: LineEdit
var _catalog_buttons: Dictionary = {}
var _title: Label
var _subtitle: Label
var _status: Label
var _hint: Label
var _tile_tab: Button
var _model_tab: Button
var _tile_kit_panel: TileKitPanel
var _standard_inspector: PanelContainer
var _asset_editor_content: VBoxContainer
var _weather_buttons: Dictionary = {}
var _light_buttons: Dictionary = {}
var _edit_target: OptionButton
var _material_slot: OptionButton
var _smoothing_slider: HSlider
var _smoothing_readout: Label
var _model_scale_section: Label
var _model_scale_heading: HBoxContainer
var _model_scale_slider: HSlider
var _model_scale_readout: Label
var _color_picker: ColorPickerButton
var _roughness_slider: HSlider
var _roughness_readout: Label
var _metallic_slider: HSlider
var _metallic_readout: Label
var _wind_slider: HSlider
var _wind_readout: Label
var _save_button: Button
var _import_status: Label
var _palette_status: Label
var _palette_swatch_buttons: Dictionary = {}
var _design_palette_colors: Dictionary = {}
var _design_palette_families: Dictionary = {}
var _palette_family_select: OptionButton
var _palette_search: LineEdit
var _palette_grid: GridContainer
var _palette_count: Label
var _selected_palette_token := ""

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
var _edit_asset_id := ""
var _entries: Array[Dictionary] = []
var _working_profile: Dictionary = {}
var _material_defaults: Dictionary = {}
var _selected_material_key := ""
var _edit_dirty := false
var _updating_edit_controls := false
var _wind_strength := 0.0
var _wind_elapsed := 0.0
var _wind_bases: Dictionary = {}
## asset id -> resource path for the selected procedural tile's baked cardinal
## variants. They stream in off-thread so sand/snow selection stays responsive.
var _pending_topology_assets: Dictionary = {}
var _pending_topology_content_id := ""
var _topology_load_failed := false
var _topology_ready: Dictionary = {}
var _saved_visibility: Dictionary = {}
var _saved_camera: Camera3D
var _saved_lighting_state: Dictionary = {}
var _saved_lighting_process_mode := Node.PROCESS_MODE_INHERIT
var _saved_tree_paused := false
var _saved_tuner_visible := false


func setup(game: Main) -> void:
	_main = game
	_kit = game.kit
	_input_service = InputDeviceService.shared()
	_assets = game.assets
	_tile_factory = TileVisualFactory.new(game.assets, game.core.grid)
	_structure_factory = StructureVisualFactory.new(game.assets, game.core.grid)
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_preview_stage()
	_build_ui()
	_input_service.input_method_changed.connect(_on_input_method_changed)
	_input_service.active_controller_changed.connect(
		func(_device): _on_input_method_changed(_input_service.input_method)
	)
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
	if _input_service.is_controller():
		_input_service.focus_first(_root, _tile_tab)
	else:
		_search.grab_focus()
	_refresh_input_hint()


func close() -> void:
	if not visible:
		return
	_dragging = false
	_input_service.release_focus_in(_root)
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


func _process(delta: float) -> void:
	if not visible:
		return
	_poll_published_topology_loads()
	_animate_wind(delta)
	if _input_service.is_controller():
		var look := Input.get_vector(
			"look_left",
			"look_right",
			"look_up",
			"look_down"
		)
		if look.length_squared() >= 0.04:
			_orbit_yaw -= look.x * delta * 1.8
			_orbit_pitch = clampf(
				_orbit_pitch - look.y * delta * 1.4,
				deg_to_rad(8.0),
				deg_to_rad(78.0)
			)
			_refresh_camera()


func selected_asset_id() -> String:
	return _selected_asset_id


func selected_category() -> String:
	return _category


func select_content(content_id: String) -> void:
	var previous_category := _category
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
	var had_search := not _search.text.is_empty()
	_search.set_block_signals(true)
	_search.text = ""
	_search.set_block_signals(false)
	if _tile_kit_panel != null:
		_tile_kit_panel.visible = _category == "tiles"
		if _category == "tiles":
			_tile_kit_panel.select_tile(content_id)
	if previous_category != _category or had_search:
		_rebuild_catalog()
	else:
		_sync_catalog_selection()
	# Switching previews the already-published runtime topology variants.
	# Rebuilding nine procedural generators here made high-resolution sand/snow
	# selection block the main thread. The baked N/E/S/W variants stream in
	# off-thread, then appear as one finished patch. Actual recipe edits still
	# use the live generator through TileKitPanel.changed.
	var loading_topology := _begin_published_topology_load(definition)
	_rebuild_preview()
	if loading_topology:
		_content_root.visible = false
		_status.text = "Preparing connected tile preview..."


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


func _on_tile_library_changed(tile_id: String) -> void:
	if not _main.core.registries.reload_all_atomic("res://data"):
		_status.text = "Catalog was written, but the live registry rejected its reload."
		return
	_assets.clear_edit_caches()
	_rebuild_catalog()
	if (
		_tile_kit_panel.current_manifest != null
		and _tile_kit_panel.current_manifest.lifecycle
			== TileLibraryManifest.LIFECYCLE_DRAFT
	):
		_selected_content_id = ""
		_selected_asset_id = ""
		_asset_editor_content.visible = false
		_rebuild_catalog()
		return
	if _main.core.registries.tiles.has(tile_id):
		select_content(tile_id)
	elif _tile_kit_panel.current_manifest == null:
		var first := _first_visible_entry()
		if not first.is_empty():
			select_content(String(first["content_id"]))


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
	_preview_input.offset_right = -477.0
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
	var heading := _kit.label("ASSET STUDIO", 22, false, true)
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
	scroll.follow_focus = true
	browser_column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

	_build_inspector(_root)

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
		"Select an asset, edit the runtime presentation, then save to game.",
		13
	)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_column.add_child(_status)
	_rebuild_catalog()


func _build_inspector(parent: Control) -> void:
	var inspector := PanelContainer.new()
	inspector.name = "AssetViewerInspector"
	inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inspector.offset_left = -465.0
	inspector.offset_top = 76.0
	inspector.offset_right = -14.0
	inspector.offset_bottom = -118.0
	inspector.add_theme_stylebox_override("panel", _kit.panel_style(false, 18))
	parent.add_child(inspector)
	_standard_inspector = inspector
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	inspector.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	scroll.add_child(column)
	_tile_kit_panel = TileKitPanel.new()
	_tile_kit_panel.name = "AssetStudioTileInspector"
	_tile_kit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_kit_panel.setup(_kit)
	_tile_kit_panel.changed.connect(_rebuild_tile_kit_preview)
	_tile_kit_panel.bake_requested.connect(_bake_tile_kit)
	_tile_kit_panel.export_requested.connect(_export_tile_kit_glb)
	_tile_kit_panel.library_changed.connect(_on_tile_library_changed)
	_tile_kit_panel.status.connect(func(message: String) -> void:
		_status.text = message)
	column.add_child(_tile_kit_panel)
	var material_section := _inspector_accordion(
		column,
		"ADVANCED MATERIAL OVERRIDES",
		false,
		"Optional per-asset color, roughness, metallic, and smoothing overrides. "
		+ "These are separate from saving a procedural tile recipe."
	)
	_asset_editor_content = VBoxContainer.new()
	_asset_editor_content.add_theme_constant_override("separation", 9)
	(material_section["content"] as VBoxContainer).add_child(_asset_editor_content)
	column = _asset_editor_content

	_subtitle = _kit.label("Production GLB", 14, false, true)
	column.add_child(_subtitle)
	_hint = _kit.label(
		"Real AssetLibrary instance · authored values loaded",
		12
	)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	_import_status = _kit.label("Choose an asset to import its values.", 12)
	_import_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_status.add_theme_color_override(
		"font_color",
		_kit.palette.color("ui_asset_debug_text_dark")
	)
	column.add_child(_import_status)

	column.add_child(_editor_section("GAME ASSET"))
	_edit_target = OptionButton.new()
	_edit_target.name = "AssetStudioEditTarget"
	_edit_target.custom_minimum_size.y = 40.0
	_edit_target.tooltip_text = (
		"Layered tiles expose their real base and surface GLBs separately."
	)
	_edit_target.item_selected.connect(_on_edit_target_selected)
	column.add_child(_edit_target)

	column.add_child(_editor_section("TOP / DETAIL SURFACE"))
	var smoothing := _add_editor_slider(column, "Desired smoothing")
	_smoothing_slider = smoothing["slider"]
	_smoothing_readout = smoothing["readout"]
	_smoothing_slider.name = "AssetStudioSmoothing"
	_smoothing_slider.tooltip_text = (
		"For tiles this is absolute: 0% is the authored relief with flat "
		+ "per-face shading. Higher values relax and compress the exposed "
		+ "surface; 100% is strongly smoothed and nearly flat. Only exposed "
		+ "tops and fused details participate. The rectangular body, border, "
		+ "perimeter, bevel, sides, UVs, topology, and collision stay rigid. "
		+ "Models retain their source baseline and smooth their complete form."
	)
	_smoothing_slider.value_changed.connect(_on_smoothing_changed)

	_model_scale_section = _editor_section("MODEL TRANSFORM")
	column.add_child(_model_scale_section)
	var model_scale := _add_editor_slider(column, "Uniform size")
	_model_scale_heading = model_scale["heading"]
	_model_scale_slider = model_scale["slider"]
	_model_scale_readout = model_scale["readout"]
	_model_scale_slider.name = "AssetStudioModelScale"
	_model_scale_slider.min_value = AssetEditLibrary.MODEL_SCALE_MIN
	_model_scale_slider.max_value = AssetEditLibrary.MODEL_SCALE_MAX
	_model_scale_slider.step = 0.05
	_model_scale_slider.tooltip_text = (
		"Uniformly resize this model everywhere it appears in the game. "
		+ "100% is the authored GLB size. Tiles remain dimension-locked."
	)
	_model_scale_slider.value_changed.connect(_on_model_scale_changed)

	column.add_child(_editor_section("MATERIAL SLOT"))
	_material_slot = OptionButton.new()
	_material_slot.name = "AssetStudioMaterialSlot"
	_material_slot.custom_minimum_size.y = 40.0
	_material_slot.item_selected.connect(_on_material_slot_selected)
	column.add_child(_material_slot)
	_color_picker = ColorPickerButton.new()
	_color_picker.name = "AssetStudioMaterialColor"
	_color_picker.text = "Material color"
	_color_picker.custom_minimum_size.y = 42.0
	_color_picker.edit_alpha = false
	_color_picker.edit_intensity = false
	_color_picker.color_changed.connect(_on_material_color_changed)
	column.add_child(_color_picker)
	_configure_color_picker()
	_build_design_palette(column)
	var roughness := _add_editor_slider(column, "Roughness")
	_roughness_slider = roughness["slider"]
	_roughness_readout = roughness["readout"]
	_roughness_slider.name = "AssetStudioRoughness"
	_roughness_slider.value_changed.connect(_on_material_roughness_changed)
	var metallic := _add_editor_slider(column, "Metallic")
	_metallic_slider = metallic["slider"]
	_metallic_readout = metallic["readout"]
	_metallic_slider.name = "AssetStudioMetallic"
	_metallic_slider.value_changed.connect(_on_material_metallic_changed)

	column.add_child(_editor_section("SCENE TEST"))
	var wind := _add_editor_slider(column, "Wind")
	_wind_slider = wind["slider"]
	_wind_readout = wind["readout"]
	_wind_slider.name = "AssetStudioWind"
	_wind_slider.tooltip_text = (
		"Preview-only wind for foliage and flexible details. "
		+ "Weather and light controls are below the viewport."
	)
	_wind_slider.value_changed.connect(_on_wind_changed)

	column.add_child(_editor_section("PUBLISH"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	var reimport := _compact_button("Reimport")
	reimport.name = "AssetStudioReimport"
	reimport.tooltip_text = (
		"Discard unsaved edits and reload the game's saved profile."
	)
	reimport.pressed.connect(discard_asset_edits)
	reimport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(reimport)
	var authored := _compact_button("Authored")
	authored.name = "AssetStudioAuthored"
	authored.tooltip_text = (
		"Return to the untouched GLB geometry, normals, and palette materials."
	)
	authored.pressed.connect(restore_authored_values)
	authored.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(authored)
	_save_button = _kit.button("Save Material Override", true)
	_save_button.name = "AssetStudioSave"
	_save_button.custom_minimum_size.y = 44.0
	_save_button.tooltip_text = (
		"Writes an optional material/smoothing override. AssetLibrary applies it "
		+ "everywhere in the game."
	)
	_save_button.pressed.connect(save_asset_edits)
	column.add_child(_save_button)


func _configure_color_picker() -> void:
	var picker := _color_picker.get_picker()
	picker.edit_alpha = false
	picker.edit_intensity = false
	picker.color_mode = ColorPicker.MODE_RGB
	picker.color_modes_visible = false
	picker.presets_visible = false
	picker.hex_visible = true
	picker.sliders_visible = true
	var popup := _color_picker.get_popup()
	popup.transparent_bg = false
	var panel := StyleBoxFlat.new()
	panel.bg_color = _kit.palette.color("ui_asset_panel")
	panel.border_color = _kit.palette.color("ui_asset_panel_border")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(12.0)
	popup.add_theme_stylebox_override("panel", panel)


func _build_design_palette(parent: VBoxContainer) -> void:
	parent.add_child(_editor_section("SUMA DESIGN PALETTE"))
	var guidance := _kit.label(
		"Browse cohesive shade families or search every named token.",
		11
	)
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guidance.add_theme_color_override(
		"font_color",
		_kit.palette.color("ui_asset_debug_text_a")
	)
	parent.add_child(guidance)
	_palette_status = _kit.label("Choose a material slot first.", 11, false, true)
	_palette_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_palette_status)
	_design_palette_colors.clear()
	_design_palette_families.clear()
	var total_colors := 0
	for raw_group: Variant in DESIGN_PALETTE:
		var group: Dictionary = raw_group
		var family_name := String(group.get("label", ""))
		for raw_key: Variant in group.get("keys", []):
			var key := String(raw_key)
			if not _assets.materials.palette.colors.has(key):
				continue
			_design_palette_colors[key] = _design_palette_color(key)
			_design_palette_families[key] = family_name
			total_colors += 1

	_palette_family_select = OptionButton.new()
	_palette_family_select.name = "AssetStudioPaletteFamily"
	_palette_family_select.custom_minimum_size.y = 38.0
	for index in DESIGN_PALETTE.size():
		var group: Dictionary = DESIGN_PALETTE[index]
		var available := 0
		for raw_key: Variant in group.get("keys", []):
			if _design_palette_colors.has(String(raw_key)):
				available += 1
		_palette_family_select.add_item(
			"%s · %d shades"
			% [String(group.get("label", "")), available]
		)
		_palette_family_select.set_item_metadata(
			_palette_family_select.item_count - 1,
			index
		)
	_palette_family_select.add_item("All colors · %d tokens" % total_colors)
	_palette_family_select.set_item_metadata(
		_palette_family_select.item_count - 1,
		-1
	)
	_palette_family_select.item_selected.connect(
		_on_palette_family_selected
	)
	parent.add_child(_palette_family_select)

	_palette_search = LineEdit.new()
	_palette_search.name = "AssetStudioPaletteSearch"
	_palette_search.placeholder_text = "Search color or token…"
	_palette_search.clear_button_enabled = true
	_palette_search.custom_minimum_size.y = 36.0
	_palette_search.text_changed.connect(_on_palette_search_changed)
	parent.add_child(_palette_search)

	_palette_count = _kit.label("", 10, false, true)
	_palette_count.add_theme_color_override(
		"font_color",
		_kit.palette.color("ui_asset_debug_text_light")
	)
	parent.add_child(_palette_count)
	_palette_grid = GridContainer.new()
	_palette_grid.name = "AssetStudioPaletteGrid"
	_palette_grid.columns = 3
	_palette_grid.add_theme_constant_override("h_separation", 5)
	_palette_grid.add_theme_constant_override("v_separation", 5)
	parent.add_child(_palette_grid)
	_rebuild_palette_swatches()


func _on_palette_family_selected(_index: int) -> void:
	if not _palette_search.text.is_empty():
		_palette_search.set_block_signals(true)
		_palette_search.text = ""
		_palette_search.set_block_signals(false)
	_rebuild_palette_swatches()
	_refresh_palette_selection(
		_color_picker.color,
		not _selected_material_key.is_empty()
	)


func _on_palette_search_changed(_query: String) -> void:
	_rebuild_palette_swatches()
	_refresh_palette_selection(
		_color_picker.color,
		not _selected_material_key.is_empty()
	)


func _rebuild_palette_swatches() -> void:
	if _palette_grid == null:
		return
	for child in _palette_grid.get_children():
		child.free()
	_palette_swatch_buttons.clear()
	var query := _palette_search.text.strip_edges().to_lower()
	var selected_group := int(
		_palette_family_select.get_item_metadata(
			_palette_family_select.selected
		)
	)
	var visible_keys: Array[String] = []
	for group_index in DESIGN_PALETTE.size():
		var group: Dictionary = DESIGN_PALETTE[group_index]
		var family_name := String(group.get("label", ""))
		for raw_key: Variant in group.get("keys", []):
			var key := String(raw_key)
			if not _design_palette_colors.has(key):
				continue
			var matches_family := (
				selected_group < 0 or selected_group == group_index
			)
			var haystack := "%s %s %s" % [
				_palette_label(key),
				key,
				family_name,
			]
			if (
				(not query.is_empty() and haystack.to_lower().contains(query))
				or (query.is_empty() and matches_family)
			):
				visible_keys.append(key)
	for key: String in visible_keys:
		var color: Color = _design_palette_colors[key]
		var swatch := Button.new()
		swatch.name = "AssetStudioPalette_%s" % key
		swatch.custom_minimum_size = Vector2(92.0, 38.0)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.text = _palette_label(key)
		swatch.tooltip_text = "%s\n%s · #%s" % [
			String(_design_palette_families.get(key, "")),
			key,
			color.to_html(false).to_upper(),
		]
		swatch.set_meta("palette_key", key)
		swatch.set_meta("palette_label", swatch.text)
		swatch.pressed.connect(_on_palette_color_selected.bind(key))
		_style_palette_swatch(
			swatch,
			color,
			key == _selected_palette_token
		)
		swatch.disabled = _selected_material_key.is_empty()
		_palette_grid.add_child(swatch)
		_palette_swatch_buttons[key] = swatch
	var scope := (
		"search results"
		if not query.is_empty()
		else "all families"
		if selected_group < 0
		else String(DESIGN_PALETTE[selected_group].get("label", ""))
	)
	_palette_count.text = "%d colors · %s" % [visible_keys.size(), scope]
	if visible_keys.is_empty():
		var empty := _kit.label("No palette token matches that search.", 11)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_palette_grid.add_child(empty)


func _design_palette_color(key: String) -> Color:
	var fallback := _assets.materials.palette.color(
		key,
		_assets.materials.palette.color("neutral_white")
	)
	var material := _assets.materials.material(key)
	if material == null:
		fallback.a = 1.0
		return fallback
	var values := _assets.edits.material_values(material)
	var color := Color.from_string(
		String(values.get("color", fallback.to_html(false))),
		fallback
	)
	color.a = 1.0
	return color


func _palette_label(key: String) -> String:
	var aliases := {
		"warm_white": "Warm White",
		"ivory_highlight": "Ivory",
		"plain_ground_gg": "Plain Ground",
		"sand_top": "Sand",
		"sand_highlight": "Sand Highlight",
		"sand_light": "Sand Light",
		"sand_shadow": "Sand Shadow",
		"sand_deep": "Sand Deep",
		"snow_top": "Snow",
		"snow_highlight": "Snow Highlight",
		"snow_light": "Snow Light",
		"snow_shadow": "Snow Shadow",
		"snow_deep": "Snow Deep",
		"snow_side": "Snow Side",
		"concrete_highlight": "Concrete Highlight",
		"concrete_light": "Concrete Light",
		"concrete_top": "Concrete",
		"concrete_shadow": "Concrete Shadow",
		"concrete_deep": "Concrete Deep",
		"concrete_side": "Concrete Side",
		"stone_mid_light": "Stone Light 2",
		"stone_mid": "Stone",
		"stone_warm_shadow": "Warm Stone",
		"stone_deep_shadow": "Deep Stone",
		"soft_sage_gray": "Sage Gray",
		"warm_near_black": "Near Black",
		"grass_highlight": "Grass Light",
		"grass_primary": "Grass",
		"grass_vivid_accent": "Vivid Grass",
		"moss_primary": "Moss",
		"leaf_soft_sage": "Leaf Sage",
		"pine_medium": "Pine",
		"deep_grass": "Deep Grass",
		"earth_light": "Earth Light",
		"earth_primary": "Earth",
		"soil_orange": "Soil",
		"soil_red_shadow": "Red Soil",
		"wood_light": "Wood Light",
		"wood_primary": "Wood",
		"wood_warm_shadow": "Warm Wood",
		"wood_deep": "Wood Deep",
		"terracotta_light": "Terra Light",
		"terracotta_primary": "Terracotta",
		"terracotta_orange": "Terra Orange",
		"terracotta_shadow": "Terra Shadow",
		"soft_coral": "Soft Coral",
		"gold_highlight": "Gold Light",
		"gold_primary": "Gold",
		"warm_yellow": "Yellow",
		"water_foam": "Foam",
		"water_shallow_highlight": "Water Highlight",
		"water_shallow": "Shallow",
		"water_turquoise": "Turquoise",
		"water_mid": "Water Mid",
		"water_deep_mid": "Water Deep Mid",
		"water_deep": "Deep Water",
		"water_abyss": "Abyss",
		"uw_sand_light": "UW Sand Light",
		"uw_sand_shadow": "UW Sand Shadow",
		"uw_rock_light": "UW Rock Light",
		"uw_rock_mid": "UW Rock",
		"uw_rock_shadow": "UW Rock Shadow",
		"uw_flora_light": "UW Flora Light",
		"uw_flora_mid": "UW Flora",
		"uw_flora_dark": "UW Flora Dark",
		"uw_flora_deep": "UW Flora Deep",
	}
	return String(
		aliases.get(key, key.replace("_", " ").capitalize())
	)


func _style_palette_swatch(
	button: Button,
	color: Color,
	selected: bool
) -> void:
	var border := (
		_kit.palette.color("ui_asset_selected")
		if selected
		else _kit.palette.color("ui_asset_unselected_border")
	)
	var width := 4 if selected else 1
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = (
			color.darkened(0.06)
			if state == "pressed"
			else color.lightened(0.045) if state == "hover" else color
		)
		style.border_color = (
			_kit.palette.color("ui_asset_hover")
			if state in ["hover", "focus"]
			else border
		)
		style.set_border_width_all(3 if state in ["hover", "focus"] else width)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(4.0)
		button.add_theme_stylebox_override(state, style)
	var luminance := color.get_luminance()
	var text_color := (
		_kit.palette.color("ui_asset_text_dark")
		if luminance > 0.62
		else _kit.palette.color("ui_asset_text_light")
	)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_font_size_override("font_size", 10)


func _editor_section(text: String) -> Label:
	var label := _kit.label(text, 12, false, true)
	label.add_theme_color_override(
		"font_color",
		_kit.palette.color("ui_asset_debug_text_b")
	)
	return label


func _inspector_accordion(
	parent: Container,
	title: String,
	expanded: bool,
	help_text := ""
) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	parent.add_child(root)
	var header := _kit.choice_button("", false)
	header.toggle_mode = true
	header.set_pressed_no_signal(expanded)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size.y = 44
	root.add_child(header)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.visible = expanded
	root.add_child(content)
	if not help_text.is_empty():
		var help := _kit.label(help_text, 11)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.add_theme_color_override(
			"font_color",
			_kit.palette.color("ui_asset_debug_text_c")
		)
		content.add_child(help)
	var refresh := func(open: bool) -> void:
		header.text = ("▼  " if open else "▶  ") + title
		content.visible = open
	refresh.call(expanded)
	header.toggled.connect(refresh)
	return {"root": root, "header": header, "content": content}


func _add_editor_slider(
	parent: VBoxContainer,
	label_text: String
) -> Dictionary:
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := _kit.label(label_text, 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var readout := _kit.label("0%", 12, false, true)
	readout.custom_minimum_size.x = 44.0
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size.y = 24.0
	parent.add_child(slider)
	return {
		"heading": heading,
		"label": label,
		"slider": slider,
		"readout": readout,
	}


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
		_main.discovery_reveal,
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
	_catalog_buttons.clear()
	if _category == "tiles":
		# Authoring shows every real compiled tile, including hidden and archived
		# records. Draft recipes are intentionally absent until publication.
		for content_id: String in _main.core.registries.tiles:
			var definition := _main.core.registries.tile(content_id)
			var manifest := _tile_kit_panel.manifest_for(content_id)
			var display_name := definition.display_name
			if (
				manifest != null
				and manifest.lifecycle == TileLibraryManifest.LIFECYCLE_ARCHIVED
			):
				display_name += " · Archived"
			_entries.append({
				"content_id": content_id,
				"asset_id": definition.asset_id,
				"name": display_name,
				"group": definition.catalog_category.replace("_", " ").capitalize(),
				"group_key": definition.catalog_category,
				"catalog_order": definition.catalog_order,
			})
	else:
		for content_id: String in _main.core.registries.structures:
			var definition := _main.core.registries.structure(content_id)
			_entries.append({
				"content_id": content_id,
				"asset_id": definition.asset_id,
				"name": definition.display_name,
				"group": definition.kind.capitalize(),
				"group_key": definition.kind,
				"catalog_order": 1000,
			})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if _category == "tiles":
			var category_a := CatalogTaxonomy.category_rank(
				String(a.get("group_key", ""))
			)
			var category_b := CatalogTaxonomy.category_rank(
				String(b.get("group_key", ""))
			)
			if category_a != category_b:
				return category_a < category_b
		var group_order := String(a["group"]).naturalnocasecmp_to(
			String(b["group"])
		)
		if group_order != 0:
			return group_order < 0
		var catalog_order_a := int(a.get("catalog_order", 1000))
		var catalog_order_b := int(b.get("catalog_order", 1000))
		if catalog_order_a != catalog_order_b:
			return catalog_order_a < catalog_order_b
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	var query := _search.text.strip_edges().to_lower()
	var last_group := ""
	for entry: Dictionary in _entries:
		var haystack := (
			"%s %s %s"
			% [entry["name"], entry["content_id"], entry["asset_id"]]
		).to_lower()
		if not query.is_empty() and not haystack.contains(query):
			continue
		var group := String(entry["group"])
		if group != last_group:
			_list.add_child(_catalog_group_label(group))
			last_group = group
		var selected := String(entry["content_id"]) == _selected_content_id
		var button := _catalog_button(entry, selected)
		_list.add_child(button)
		_catalog_buttons[String(entry["content_id"])] = button
	_tile_tab.set_pressed_no_signal(_category == "tiles")
	_model_tab.set_pressed_no_signal(_category == "models")


func _sync_catalog_selection() -> void:
	for content_id: String in _catalog_buttons:
		var button := _catalog_buttons[content_id] as Button
		if is_instance_valid(button):
			button.set_pressed_no_signal(content_id == _selected_content_id)


func _catalog_button(entry: Dictionary, selected: bool) -> Button:
	var button := _kit.choice_button(String(entry["name"]), selected)
	button.name = "AssetViewerItem_" + String(entry["content_id"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 43.0)
	button.tooltip_text = "%s\n%s" % [entry["content_id"], entry["asset_id"]]
	button.pressed.connect(select_content.bind(String(entry["content_id"])))
	return button


func _catalog_group_label(text: String) -> Label:
	var label := _kit.label(text.to_upper(), 12, false, true)
	label.custom_minimum_size.y = 28.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_color_override(
		"font_color",
		_kit.palette.color("ui_asset_debug_text_d")
	)
	return label


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


## Tile Kit preview: a 3x3 patch of the SAME preset, because repetition is the
## test that matters — a kit tile ships as terrain, and terrain is judged in
## multiples, never as a hero piece.
func _rebuild_tile_kit_preview() -> void:
	if _content_root == null or _tile_kit_panel == null:
		return
	# A recipe edit supersedes any not-yet-presented published patch. Threaded
	# requests may finish in ResourceLoader's global cache, but this inspector
	# now intentionally shows the live working recipe.
	_pending_topology_assets.clear()
	_pending_topology_content_id = ""
	_content_root.visible = true
	for child in _content_root.get_children():
		child.free()
	var tile_size: float = _main.core.grid.tile_size
	var manifest := _tile_kit_panel.current_manifest
	if (
		manifest != null
		and manifest.tile_id.is_empty()
		and not _selected_content_id.is_empty()
	):
		_selected_content_id = ""
		_selected_asset_id = ""
		_rebuild_catalog()
	if _asset_editor_content != null:
		_asset_editor_content.visible = (
			manifest != null
			and _main.core.registries.tiles.has(manifest.tile_id)
		)
	if (
		manifest != null
		and manifest.source_kind == TileLibraryManifest.SOURCE_EXTERNAL
	):
		var imported_definition := Defs.TileDefinition.from_dict(
			manifest.to_tile_dictionary()
		)
		for z in 3:
			for x in 3:
				var tile := _tile_factory.instantiate_visual(
					imported_definition,
					false,
					0,
					TileVisualFactory.detail_variant_for_coord(
						imported_definition, Vector2i(x - 1, z - 1)
					)
				)
				tile.position = Vector3(
					(x - 1) * tile_size, 0.0, (z - 1) * tile_size
				)
				_content_root.add_child(tile)
		_title.text = "Tile Library — %s" % manifest.display_name
		_subtitle.text = "%s  ·  imported official tile" % manifest.tile_id
		_hint.text = "Drag to orbit  ·  Wheel to zoom  ·  inspect all tile seams"
		_status.text = (
			"Viewing the current external geometry. Its manifest is editable; "
			+ "replace its source with a procedural recipe to sculpt it here."
		)
		_collect_wind_nodes()
		_frame_preview()
		return
	var scale := tile_size / 1.70
	var first: TileKitGenerator
	for z in 3:
		for x in 3:
			var generator := TileKitGenerator.new()
			generator.preset = _tile_kit_panel.preset
			generator.world_cell = Vector2i(x - 1, z - 1)
			# Cardinal mask: 1 north, 2 east, 4 south, 8 west. The preset's
			# separation checkbox decides whether the generator uses or ignores
			# this real patch topology.
			generator.neighbour_mask = (
				(1 if z > 0 else 0)
				| (2 if x < 2 else 0)
				| (4 if z < 2 else 0)
				| (8 if x > 0 else 0)
			)
			# Preview at live scale, exactly as TileVisualFactory will show it:
			# X/Z normalized to the 1.00 m live cell, verticals untouched.
			generator.scale = Vector3(scale, 1.0, scale)
			generator.position = Vector3((x - 1) * tile_size, 0.0, (z - 1) * tile_size)
			_content_root.add_child(generator)
			if first == null:
				first = generator
	_title.text = (
		manifest.display_name
		if manifest != null
		else _tile_kit_panel.preset.preset_name
	)
	_subtitle.text = "%s  ·  procedural  ·  3×3 seam patch" % (
		manifest.tile_id if manifest != null and not manifest.tile_id.is_empty()
		else "unsaved tile"
	)
	_hint.text = "Drag to orbit  ·  Wheel to zoom  ·  judge the repetition"
	_status.text = "Live procedural tile preview under game lighting."
	if first != null:
		_tile_kit_panel.show_statistics(first.statistics())
	var selected_tile := _main.core.registries.tile(_selected_content_id)
	if selected_tile != null:
		_refresh_edit_targets(selected_tile)
	_collect_wind_nodes()
	_frame_preview()


## Manual development bake for the currently selected stable tile ID.
## Publish/Overwrite use the same baker and additionally compile the catalog.
func _bake_tile_kit() -> void:
	if _tile_kit_panel == null:
		return
	if not _tile_kit_panel.can_bake_current():
		_status.text = (
			"Select an editable procedural tile. Official baking is read-only "
			+ "in release builds."
		)
		return
	var tile_id := _tile_kit_panel.current_tile_id()
	var result := TileKitBaker.new().bake(_tile_kit_panel.preset, tile_id)
	if not bool(result.get("ok", false)):
		var errors: PackedStringArray = result.get("errors", PackedStringArray())
		_status.text = "Bake failed: %s" % "; ".join(errors)
		return
	_assets.clear_edit_caches()
	_status.text = "Baked %s with 16 edge topologies under its stable ID." % tile_id


func _export_tile_kit_glb() -> void:
	if _tile_kit_panel == null:
		return
	var generator := TileKitGenerator.new()
	generator.preset = _tile_kit_panel.preset
	add_child(generator)
	var directory := "user://tile_kit_export"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "%s/%s.glb" % [
		directory,
		_tile_kit_panel.preset.preset_name.validate_filename().to_snake_case(),
	]
	var error := generator.export_glb(ProjectSettings.globalize_path(path))
	generator.queue_free()
	_status.text = (
		"Exported %s" % ProjectSettings.globalize_path(path)
		if error == OK
		else "GLB export failed: %s" % error_string(error)
	)


func _rebuild_preview() -> void:
	if _asset_editor_content != null:
		_asset_editor_content.visible = true
	_wind_bases.clear()
	var selected_tile := _main.core.registries.tile(_selected_content_id)
	var uses_layered_tile := (
		_category == "tiles"
		and selected_tile != null
		and selected_tile.uses_layered_visual()
	)
	if (
		_selected_asset_id.is_empty()
		or (not uses_layered_tile and not _assets.exists(_selected_asset_id))
	):
		_status.text = "Missing production asset: %s" % _selected_asset_id
		return
	for child in _content_root.get_children():
		child.free()
	var tile_size: float = _main.core.grid.tile_size
	if _category == "tiles":
		for z in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
			for x in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
				var neighbour_mask := 0
				if (
					selected_tile.connection_mode == "full_flush"
					and bool(_topology_ready.get(_selected_content_id, false))
				):
					neighbour_mask = _patch_neighbour_mask(
						x, z, TILE_PATCH_RADIUS
					)
				var tile := _tile_factory.instantiate_visual(
					selected_tile,
					false,
					neighbour_mask,
					TileVisualFactory.detail_variant_for_coord(
						selected_tile, Vector2i(x, z)
					)
				)
				tile.position = Vector3(x * tile_size, 0.0, z * tile_size)
				_content_root.add_child(tile)
	else:
		var base_definition := _main.core.registries.tile(MODEL_BASE_TILE_ID)
		_content_root.add_child(
			_tile_factory.instantiate_visual(base_definition, true)
		)
		var definition := _main.core.registries.structure(
			_selected_content_id
		)
		var model := (
			_structure_factory.instantiate_visual(definition)
			if definition != null
			else _assets.instantiate(_selected_asset_id)
		)
		_content_root.add_child(model)
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
	_refresh_edit_targets(selected_tile)
	_collect_wind_nodes()
	_frame_preview()


## Cardinal neighbours available inside an Asset Studio square preview patch.
## Uses the same bit contract as TileKitGenerator and WorldRenderer:
## 1 north, 2 east, 4 south, 8 west.
static func _patch_neighbour_mask(x: int, z: int, radius: int) -> int:
	return (
		(1 if z > -radius else 0)
		| (2 if x < radius else 0)
		| (4 if z < radius else 0)
		| (8 if x > -radius else 0)
	)


## Starts (or adopts) threaded requests for exactly the baked variants needed
## by this 3x3 patch. Returns true while the correct connected preview is not
## ready; callers hide the canonical standalone fallback during that interval
## so the UI never lies about the unchecked "Keep tiles separated" setting.
func _begin_published_topology_load(selected_tile: Variant) -> bool:
	_pending_topology_assets.clear()
	_pending_topology_content_id = ""
	_topology_load_failed = false
	_content_root.visible = true
	if (
		_category != "tiles"
		or selected_tile == null
		or selected_tile.connection_mode != "full_flush"
		or _tile_kit_panel == null
		or _tile_kit_panel.current_manifest == null
		or _tile_kit_panel.current_manifest.source_kind
			!= TileLibraryManifest.SOURCE_PROCEDURAL
		or _tile_kit_panel.preset == null
		or _tile_kit_panel.preset.separate_tiles
	):
		return false
	var masks := {}
	for z in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
		for x in range(-TILE_PATCH_RADIUS, TILE_PATCH_RADIUS + 1):
			masks[_patch_neighbour_mask(x, z, TILE_PATCH_RADIUS)] = true
	for layer: Defs.TileVisualLayerDefinition in selected_tile.visual_layers:
		for mask: int in masks:
			var candidate := "%s_n%02d" % [layer.asset_id, mask]
			if not _assets.exists(candidate) or _assets.has_cached_scene(candidate):
				continue
			var path := AssetLibrary.resolve_path(candidate)
			var state := ResourceLoader.load_threaded_get_status(path)
			if state == ResourceLoader.THREAD_LOAD_LOADED:
				var loaded := ResourceLoader.load_threaded_get(path) as PackedScene
				_assets.prime_packed_scene(candidate, loaded)
				continue
			if state != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var error := ResourceLoader.load_threaded_request(path, "PackedScene")
				if error != OK:
					_topology_load_failed = true
					continue
			_pending_topology_assets[candidate] = path
	if _pending_topology_assets.is_empty():
		if not _topology_load_failed:
			_topology_ready[_selected_content_id] = true
		return false
	_topology_ready.erase(_selected_content_id)
	_pending_topology_content_id = _selected_content_id
	return true


func _poll_published_topology_loads() -> void:
	if _pending_topology_assets.is_empty():
		return
	for asset_id: String in _pending_topology_assets.keys():
		var path := String(_pending_topology_assets[asset_id])
		var state := ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			_assets.prime_packed_scene(asset_id, packed)
		else:
			_topology_load_failed = true
		_pending_topology_assets.erase(asset_id)
	if not _pending_topology_assets.is_empty():
		return
	var completed_content_id := _pending_topology_content_id
	_pending_topology_content_id = ""
	if completed_content_id != _selected_content_id:
		return
	_content_root.visible = true
	if _topology_load_failed:
		_status.text = "Connected preview could not be streamed; showing live recipe."
		_rebuild_tile_kit_preview()
		return
	_topology_ready[completed_content_id] = true
	_rebuild_preview()


func _refresh_edit_targets(selected_tile: Defs.TileDefinition) -> void:
	var target_ids: Array[String] = []
	var target_roles := {}
	if (
		_category == "tiles"
		and selected_tile != null
		and selected_tile.uses_layered_visual()
	):
		for layer: Defs.TileVisualLayerDefinition in selected_tile.visual_layers:
			if (
				layer.role == "surface"
				and not target_ids.has(layer.asset_id)
			):
				target_ids.append(layer.asset_id)
				target_roles[layer.asset_id] = layer.role
		for layer: Defs.TileVisualLayerDefinition in selected_tile.visual_layers:
			if not target_ids.has(layer.asset_id):
				target_ids.append(layer.asset_id)
				target_roles[layer.asset_id] = layer.role
	else:
		target_ids.append(_selected_asset_id)
		target_roles[_selected_asset_id] = (
			"tile details" if _category == "tiles" else "model"
		)
	_updating_edit_controls = true
	_edit_target.clear()
	for asset_id: String in target_ids:
		var role := String(target_roles.get(asset_id, "asset")).capitalize()
		var label := "%s · %s" % [
			role,
			asset_id.replace("_", " ").capitalize(),
		]
		if not _asset_supports_smoothing(asset_id):
			label += " (rigid)"
		_edit_target.add_item(label)
		_edit_target.set_item_metadata(_edit_target.item_count - 1, asset_id)
	_edit_target.disabled = target_ids.size() <= 1
	_updating_edit_controls = false
	if target_ids.is_empty():
		_edit_asset_id = ""
		_clear_edit_controls()
		return
	_edit_asset_id = target_ids[0]
	_edit_target.select(0)
	_import_working_profile()


func _on_edit_target_selected(index: int) -> void:
	if _updating_edit_controls or index < 0:
		return
	_edit_asset_id = String(_edit_target.get_item_metadata(index))
	_import_working_profile()


func _import_working_profile() -> void:
	if _edit_asset_id.is_empty():
		_clear_edit_controls()
		return
	_working_profile = _assets.edits.profile(_edit_asset_id)
	if _working_profile.is_empty():
		_working_profile = {
			"scale": 1.0,
			"smoothing": 0.0,
			"materials": {},
		}
	if not _asset_supports_scaling(_edit_asset_id):
		_working_profile["scale"] = 1.0
	if not _asset_supports_smoothing(_edit_asset_id):
		## Structural base-layer profiles made before this protection are
		## ignored and normalize to authored normals when next saved.
		_working_profile["smoothing"] = 0.0
	_material_defaults = _assets.edits.collect_material_defaults(
		_content_root,
		_edit_asset_id
	)
	_edit_dirty = false
	_refresh_edit_controls()
	var saved := _assets.edits.has_profile(_edit_asset_id)
	var can_scale := _asset_supports_scaling(_edit_asset_id)
	if not _asset_supports_smoothing(_edit_asset_id):
		_import_status.text = (
			"Structural tile layer · smoothing locked; materials remain editable."
		)
	elif saved and can_scale:
		_import_status.text = (
			"Imported saved game profile · %d%% size · %d%% smoothing"
			% [
				roundi(float(_working_profile.get("scale", 1.0)) * 100.0),
				roundi(
					float(_working_profile.get("smoothing", 0.0)) * 100.0
				),
			]
		)
	else:
		_import_status.text = (
			"Imported saved game profile · %d%% desired smoothing"
			% roundi(float(_working_profile.get("smoothing", 0.0)) * 100.0)
			if saved
			else (
				"Imported flat tile GLB · 0% desired smoothing"
				if _category == "tiles"
				else (
					"Imported authored model GLB · 100% size · "
					+ "0% source-relative smoothing"
				)
			)
		)
	var resolved := AssetLibrary.resolve_path(_edit_asset_id)
	_hint.text = (
		resolved.trim_prefix("res://")
		if not resolved.is_empty()
		else "Runtime-composed asset"
	)


func _refresh_edit_controls() -> void:
	_updating_edit_controls = true
	var smoothing := float(_working_profile.get("smoothing", 0.0))
	var can_smooth := _asset_supports_smoothing(_edit_asset_id)
	_smoothing_slider.set_value_no_signal(smoothing)
	_smoothing_slider.editable = can_smooth
	_smoothing_readout.text = (
		"%d%%" % roundi(smoothing * 100.0) if can_smooth else "Rigid"
	)
	var can_scale := _asset_supports_scaling(_edit_asset_id)
	var model_scale := float(_working_profile.get("scale", 1.0))
	_model_scale_section.visible = can_scale
	_model_scale_heading.visible = can_scale
	_model_scale_slider.visible = can_scale
	_model_scale_slider.editable = can_scale
	_model_scale_slider.set_value_no_signal(model_scale)
	_model_scale_readout.text = "%d%%" % roundi(model_scale * 100.0)
	_material_slot.clear()
	var keys: Array[String] = []
	for key: String in _material_defaults:
		keys.append(key)
	var edits: Dictionary = _working_profile.get("materials", {})
	for key: String in edits:
		if not keys.has(key):
			keys.append(key)
	keys.sort_custom(_material_key_before)
	for key: String in keys:
		_material_slot.add_item(key.replace("_", " ").capitalize())
		_material_slot.set_item_metadata(_material_slot.item_count - 1, key)
	_material_slot.disabled = keys.is_empty()
	_color_picker.disabled = keys.is_empty()
	_roughness_slider.editable = not keys.is_empty()
	_metallic_slider.editable = not keys.is_empty()
	if keys.is_empty():
		_selected_material_key = ""
		_color_picker.color = _kit.palette.color("neutral_white")
		_roughness_slider.set_value_no_signal(0.0)
		_metallic_slider.set_value_no_signal(0.0)
		_roughness_readout.text = "—"
		_metallic_readout.text = "—"
		_refresh_palette_selection(_kit.palette.color("neutral_white"), false)
	else:
		_selected_material_key = keys[0]
		_material_slot.select(0)
		_refresh_selected_material_controls()
	_save_button.disabled = not _edit_dirty
	_updating_edit_controls = false


static func _material_key_before(a: String, b: String) -> bool:
	return _material_key_priority(a) < _material_key_priority(b) or (
		_material_key_priority(a) == _material_key_priority(b) and a < b
	)


static func _material_key_priority(key: String) -> int:
	var lower := key.to_lower()
	if lower.ends_with("_top") or lower == "top":
		return 0
	if "primary" in lower or "surface" in lower:
		return 1
	if "bevel" in lower or "light" in lower:
		return 2
	if "side" in lower or "medium" in lower:
		return 3
	if "deep" in lower or "lower" in lower:
		return 4
	return 5


func _clear_edit_controls() -> void:
	_working_profile = {}
	_material_defaults = {}
	_selected_material_key = ""
	if _edit_target != null:
		_edit_target.clear()
	_edit_dirty = false
	_refresh_edit_controls()


func _on_material_slot_selected(index: int) -> void:
	if _updating_edit_controls or index < 0:
		return
	_selected_material_key = String(_material_slot.get_item_metadata(index))
	_updating_edit_controls = true
	_refresh_selected_material_controls()
	_updating_edit_controls = false


func _refresh_selected_material_controls() -> void:
	if _selected_material_key.is_empty():
		return
	var values := _material_values(_selected_material_key)
	_color_picker.color = Color.from_string(
		String(values.get("color", "ffffff")),
		_kit.palette.color("neutral_white")
	)
	var roughness := float(values.get("roughness", 0.72))
	var metallic := float(values.get("metallic", 0.0))
	_roughness_slider.set_value_no_signal(roughness)
	_metallic_slider.set_value_no_signal(metallic)
	_roughness_readout.text = "%d%%" % roundi(roughness * 100.0)
	_metallic_readout.text = "%d%%" % roundi(metallic * 100.0)
	_focus_palette_family_for_color(_color_picker.color)
	_refresh_palette_selection(_color_picker.color)


func _material_values(key: String) -> Dictionary:
	var edits: Dictionary = _working_profile.get("materials", {})
	if edits.has(key):
		return (edits[key] as Dictionary).duplicate(true)
	if _material_defaults.has(key):
		return (_material_defaults[key] as Dictionary).duplicate(true)
	return {
		"color": "ffffff",
		"roughness": 0.72,
		"metallic": 0.0,
	}


func _editable_material_values() -> Dictionary:
	var edits: Dictionary = _working_profile.get("materials", {})
	if not edits.has(_selected_material_key):
		edits[_selected_material_key] = _material_values(
			_selected_material_key
		)
		_working_profile["materials"] = edits
	return edits[_selected_material_key]


func _on_smoothing_changed(value: float) -> void:
	if (
		_updating_edit_controls
		or not _asset_supports_smoothing(_edit_asset_id)
	):
		return
	_working_profile["smoothing"] = value
	_smoothing_readout.text = "%d%%" % roundi(value * 100.0)
	_mark_edit_dirty()


func _asset_supports_smoothing(asset_id: String) -> bool:
	return (
		not asset_id.is_empty()
		and not asset_id.begins_with("tile_layer_base_")
		and not asset_id.ends_with("_base")
	)


func _asset_supports_scaling(asset_id: String) -> bool:
	return (
		not asset_id.is_empty()
		and not asset_id.begins_with("tile_")
	)


func _on_model_scale_changed(value: float) -> void:
	if (
		_updating_edit_controls
		or not _asset_supports_scaling(_edit_asset_id)
	):
		return
	_working_profile["scale"] = value
	_model_scale_readout.text = "%d%%" % roundi(value * 100.0)
	_mark_edit_dirty()


func _on_material_color_changed(value: Color) -> void:
	if _updating_edit_controls or _selected_material_key.is_empty():
		return
	_commit_material_color(value)


func _on_palette_color_selected(key: String) -> void:
	if (
		_updating_edit_controls
		or _selected_material_key.is_empty()
		or not _design_palette_colors.has(key)
	):
		return
	_commit_material_color(_design_palette_colors[key])


func _commit_material_color(value: Color) -> void:
	var opaque := Color(value.r, value.g, value.b, 1.0)
	_color_picker.set_block_signals(true)
	_color_picker.color = opaque
	_color_picker.set_block_signals(false)
	var values := _editable_material_values()
	values["color"] = opaque.to_html(false)
	_refresh_palette_selection(opaque)
	_mark_edit_dirty()


func _focus_palette_family_for_color(color: Color) -> void:
	if (
		_palette_family_select == null
		or _palette_search == null
		or not _palette_search.text.is_empty()
	):
		return
	var exact_key := ""
	for raw_key: Variant in _design_palette_colors:
		var key := String(raw_key)
		var palette_color: Color = _design_palette_colors[key]
		if (
			absf(color.r - palette_color.r) <= 0.001
			and absf(color.g - palette_color.g) <= 0.001
			and absf(color.b - palette_color.b) <= 0.001
		):
			exact_key = key
			break
	if exact_key.is_empty():
		return
	var family_name := String(
		_design_palette_families.get(exact_key, "")
	)
	for index in DESIGN_PALETTE.size():
		if String(DESIGN_PALETTE[index].get("label", "")) != family_name:
			continue
		if (
			int(
				_palette_family_select.get_item_metadata(
					_palette_family_select.selected
				)
			) != index
		):
			_palette_family_select.select(index)
			_rebuild_palette_swatches()
		return


func _refresh_palette_selection(
	color: Color,
	enabled := true
) -> void:
	if _palette_status == null:
		return
	var exact_key := ""
	var nearest_key := ""
	var nearest_distance := INF
	for raw_key: Variant in _design_palette_colors:
		var key := String(raw_key)
		var palette_color: Color = _design_palette_colors[key]
		var distance := (
			(color.r - palette_color.r) * (color.r - palette_color.r)
			+ (color.g - palette_color.g) * (color.g - palette_color.g)
			+ (color.b - palette_color.b) * (color.b - palette_color.b)
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_key = key
		if distance <= 0.000002:
			exact_key = key
	if exact_key != _selected_palette_token:
		_selected_palette_token = exact_key
		for raw_key: Variant in _palette_swatch_buttons:
			var key := String(raw_key)
			var button := _palette_swatch_buttons[key] as Button
			_style_palette_swatch(
				button,
				_design_palette_colors[key],
				enabled and key == exact_key
			)
	for button: Button in _palette_swatch_buttons.values():
		button.disabled = not enabled
	if not enabled:
		_palette_status.text = "Choose a material slot first."
	elif not exact_key.is_empty():
		_palette_status.text = "Using %s · #%s" % [
			_palette_label(exact_key),
			color.to_html(false).to_upper(),
		]
	else:
		_palette_status.text = "Custom #%s · nearest token: %s" % [
			color.to_html(false).to_upper(),
			_palette_label(nearest_key),
		]


func _on_material_roughness_changed(value: float) -> void:
	if _updating_edit_controls or _selected_material_key.is_empty():
		return
	var values := _editable_material_values()
	values["roughness"] = value
	_roughness_readout.text = "%d%%" % roundi(value * 100.0)
	_mark_edit_dirty()


func _on_material_metallic_changed(value: float) -> void:
	if _updating_edit_controls or _selected_material_key.is_empty():
		return
	var values := _editable_material_values()
	values["metallic"] = value
	_metallic_readout.text = "%d%%" % roundi(value * 100.0)
	_mark_edit_dirty()


func _on_wind_changed(value: float) -> void:
	_wind_strength = value
	_wind_readout.text = "%d%%" % roundi(value * 100.0)


func _mark_edit_dirty() -> void:
	_edit_dirty = true
	_save_button.disabled = false
	_import_status.text = "Unsaved live edit · Save writes the game profile."
	_assets.apply_asset_profile_to_tree(
		_content_root,
		_edit_asset_id,
		_working_profile
	)
	_collect_wind_nodes()


func save_asset_edits() -> void:
	if _edit_asset_id.is_empty():
		return
	var error := _assets.save_asset_profile(
		_edit_asset_id,
		_working_profile
	)
	if error != OK:
		_status.text = (
			"Could not save %s: %s"
			% [_edit_asset_id, error_string(error)]
		)
		return
	_main.renderer.refresh_asset_edits()
	_assets.apply_asset_profile_to_tree(
		_main,
		_edit_asset_id,
		_working_profile
	)
	_edit_dirty = false
	_save_button.disabled = true
	_import_status.text = (
		"Saved to data/asset_edits.json · used by AssetLibrary in game."
	)
	_status.text = "Saved %s and rebuilt the running world." % _edit_asset_id


func discard_asset_edits() -> void:
	if _edit_asset_id.is_empty():
		return
	_import_working_profile()
	_assets.apply_asset_profile_to_tree(
		_content_root,
		_edit_asset_id,
		_working_profile
	)


func restore_authored_values() -> void:
	if _edit_asset_id.is_empty():
		return
	_working_profile = {
		"scale": 1.0,
		"smoothing": 0.0,
		"materials": {},
	}
	_edit_dirty = true
	_refresh_edit_controls()
	_save_button.disabled = false
	_assets.apply_asset_profile_to_tree(
		_content_root,
		_edit_asset_id,
		_working_profile
	)
	_import_status.text = (
		(
			"Authored tile relief and flat normals restored · Save to remove "
			+ "the game override."
			if _category == "tiles"
			else "Authored model GLB restored · Save to remove the game override."
		)
	)


func set_surface_smoothing(value: float) -> void:
	if not _asset_supports_smoothing(_edit_asset_id):
		return
	_smoothing_slider.value = clampf(value, 0.0, 1.0)


func working_surface_smoothing() -> float:
	return float(_working_profile.get("smoothing", 0.0))


func set_model_scale(value: float) -> void:
	if not _asset_supports_scaling(_edit_asset_id):
		return
	_model_scale_slider.value = clampf(
		value,
		AssetEditLibrary.MODEL_SCALE_MIN,
		AssetEditLibrary.MODEL_SCALE_MAX
	)


func working_model_scale() -> float:
	return float(_working_profile.get("scale", 1.0))


func has_unsaved_asset_edits() -> bool:
	return _edit_dirty


func _collect_wind_nodes() -> void:
	for raw_node: Variant in _wind_bases:
		if is_instance_valid(raw_node):
			(raw_node as Node3D).rotation = _wind_bases[raw_node]
	_wind_bases.clear()
	var flexible_tokens := [
		"grass", "leaf", "foliage", "flower", "bush", "pine", "reed",
		"branch", "cloth", "banner", "canopy",
	]
	for descendant in _content_root.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := descendant as MeshInstance3D
		var source_id := _source_asset_id(mesh_instance)
		var haystack := ("%s %s" % [source_id, mesh_instance.name]).to_lower()
		var flexible := false
		for token: String in flexible_tokens:
			if haystack.contains(token):
				flexible = true
				break
		if flexible:
			_wind_bases[mesh_instance] = mesh_instance.rotation


func _source_asset_id(node: Node) -> String:
	var current: Node = node
	while current != null:
		if current.has_meta(AssetEditLibrary.SOURCE_ASSET_META):
			return String(
				current.get_meta(AssetEditLibrary.SOURCE_ASSET_META)
			)
		current = current.get_parent()
	return ""


func _animate_wind(delta: float) -> void:
	_wind_elapsed += delta
	for raw_node: Variant in _wind_bases.keys():
		if not is_instance_valid(raw_node):
			continue
		var node := raw_node as Node3D
		var base: Vector3 = _wind_bases[raw_node]
		if _wind_strength <= 0.0001:
			node.rotation = base
			continue
		var phase := float(node.get_instance_id() % 29) * 0.17
		var sway := sin(
			_wind_elapsed * lerpf(0.7, 3.4, _wind_strength) + phase
		) * deg_to_rad(lerpf(0.4, 5.0, _wind_strength))
		node.rotation = base + Vector3(sway * 0.28, 0.0, sway)


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
	light.light_color = _kit.palette.color("vfx_local_light")
	light.omni_range = 4.5
	light.position.y = (
		definition.light_height
		* _structure_factory.effective_model_scale(definition)
	)
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
		and (event as InputEventKey).ctrl_pressed
		and (event as InputEventKey).physical_keycode == KEY_S
	):
		if _edit_dirty:
			save_asset_edits()
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).physical_keycode == KEY_F8
	):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_in"):
		_zoom_preview(-1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_preview(1.0)
		get_viewport().set_input_as_handled()


func _zoom_preview(direction: float) -> void:
	_orbit_distance = clampf(
		_orbit_distance * (1.0 + direction * 0.1),
		2.0,
		40.0
	)
	_refresh_camera()


func _on_input_method_changed(_method: int) -> void:
	_refresh_input_hint()
	if visible and _input_service.is_controller():
		_input_service.focus_first(_root, _tile_tab)


func _refresh_input_hint() -> void:
	if _hint == null:
		return
	_hint.text = (
		"%s  ·  %s  ·  3×3 tile seam check"
		% [
			_input_service.format_action(&"look_right", "orbit"),
			_input_service.format_action(&"camera_zoom_in", "zoom"),
		]
		if _input_service.is_controller()
		else "Drag to orbit  ·  Wheel to zoom  ·  3×3 tile seam check"
	)


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
	style.bg_color = _kit.palette.color("ui_asset_preview_surface")
	return style
