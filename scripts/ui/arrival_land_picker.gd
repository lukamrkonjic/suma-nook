class_name ArrivalLandPicker
extends CanvasLayer
## The first keep-one-of-three ritual. It pauses the portal arrival at its
## apex and lets the player choose the literal first piece of their world.

signal land_chosen(tile_id: String)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer
var _root: Control
var _first_button: Button


func setup(
	game_core: GameCore,
	ui_kit: UiKit,
	asset_library: AssetLibrary
) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_thumbnail_renderer = BuildThumbnailRenderer.new()
	_thumbnail_renderer.name = "ArrivalLandThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, asset_library)


func is_open() -> bool:
	return _root != null


func open(tile_ids: Array) -> void:
	if is_open():
		return
	_root = Control.new()
	_root.name = "FirstLandChoice"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = kit.palette.color("ui_arrival_scrim")
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var shell := VBoxContainer.new()
	shell.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_theme_constant_override("separation", 13)
	center.add_child(shell)

	var eyebrow := kit.eyebrow(
		"Your first piece of the world",
		kit.palette.color("ui_arrival_border")
	)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_arrival_eyebrow")
	)
	shell.add_child(eyebrow)
	var title := kit.label("Choose where you land", 34, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var subtitle := kit.label(
		"Nine patches of land, a living tree, and water all around.",
		15,
		true
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_arrival_subtitle")
	)
	shell.add_child(subtitle)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	shell.add_child(row)
	_first_button = null
	for raw_tile_id in tile_ids:
		var tile_id := String(raw_tile_id)
		var definition := core.registries.tile(tile_id)
		if definition == null or not core.registries.is_tile_active(tile_id):
			continue
		row.add_child(_land_card(definition))

	var prompt := kit.label(
		"%s  ·  This only chooses your beginning."
		% _input_service.format_action(&"ui_accept", "Choose"),
		13,
		true
	)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_arrival_prompt")
	)
	shell.add_child(prompt)
	focus_default()


func select(tile_id: String) -> void:
	if not is_open():
		return
	var allowed: Array = core.registries.tune("starter_land_options", [])
	if tile_id not in allowed:
		return
	_input_service.release_focus_in(_root)
	_thumbnail_renderer.discard_pending()
	var old_root := _root
	_root = null
	old_root.queue_free()
	land_chosen.emit(tile_id)


func focus_default() -> void:
	if _root != null and _first_button != null:
		_input_service.focus_first(_root, _first_button)


func _land_card(definition: Defs.TileDefinition) -> Control:
	var accent := kit.palette.color("ui_good")
	if definition.biome_tags.has("beach"):
		accent = kit.palette.color("ui_arrival_warm")
	elif definition.biome_tags.has("winter"):
		accent = kit.palette.color("ui_arrival_cool")
	var card := kit.progression_card(Vector2(250, 340), accent)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	card.add_child(col)

	col.add_child(_centered(kit.pill(
		_starting_label(definition.id),
		accent
	)))
	var name_label := kit.label(definition.display_name, 21, false, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var preview := _preview(definition.id, accent)
	col.add_child(preview)
	var description := kit.muted_label(_starting_description(definition.id), 13)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 210
	col.add_child(description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var choose := kit.button("Begin here", true)
	choose.tooltip_text = "%s. %s" % [
		definition.display_name,
		_starting_description(definition.id),
	]
	choose.pressed.connect(select.bind(definition.id))
	col.add_child(choose)
	if _first_button == null:
		_first_button = choose
	return card


func _preview(tile_id: String, accent: Color) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(214, 154)
	var style := kit.surface_style(
		accent.lightened(0.62),
		16,
		accent.lightened(0.28),
		1
	)
	style.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", style)
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(206, 146)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(texture_rect)
	_thumbnail_renderer.request("starter_island", tile_id, func(texture):
		if is_instance_valid(texture_rect) and texture != null:
			texture_rect.texture = texture)
	return frame


func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	return center


func _starting_label(tile_id: String) -> String:
	match tile_id:
		"tile_grove_mature":
			return "GROVE"
		"tile_sand":
			return "SHORE"
		"tile_snowfield":
			return "WINTER"
	return "LAND"


func _starting_description(tile_id: String) -> String:
	match tile_id:
		"tile_grove_mature":
			return "A mossy green island with a warm woodland floor."
		"tile_sand":
			return "A bright sand island held inside a quiet blue ring."
		"tile_snowfield":
			return "A hushed winter island beneath a fresh blanket of snow."
	return "A small place to begin."
