class_name TileKitPanel
extends VBoxContainer
## The Tile Kit inspector inside the F8 Asset Studio.
##
## Owns the working preset and the seed history; the studio owns the preview
## scene. Every control funnels through one debounced `changed` signal so the
## studio rebuilds its preview at most a few times a second no matter how fast
## a slider moves — and the panel never touches the 3D scene directly, which
## keeps the studio free to preview a kit tile however it likes (single tile,
## seam patch, or a full land-mass mock).

signal changed
signal bake_requested
signal export_requested
signal status(message: String)
signal library_changed(tile_id: String)

const DEBOUNCE_SECONDS := 0.13

var preset: TileKitPreset
var _kit: UiKit
var _seed_field: LineEdit
var _seed_history: Array[int] = []
var _stats_label: Label
var _preset_name: LineEdit
var _tile_id_field: LineEdit
var _family_field: LineEdit
var _visibility_field: OptionButton
var _manifest_status: Label
var _template_select: OptionButton
var _library: TileLibraryService
var current_manifest: TileLibraryManifest
var _pending_operation := ""
var _confirmation: ConfirmationDialog
var _mutation_buttons: Array[Button] = []
var _draft_button: Button
var _publish_button: Button
var _overwrite_button: Button
var _archive_button: Button
var _delete_button: Button
var _bake_button: Button
var _recipe_editable := true
var _procedural_controls: Array[Control] = []
var _separate_tiles: CheckBox
var _layer_rows: Dictionary = {}
var _layer_list: VBoxContainer
var _parameter_editor: VBoxContainer
var _add_layer_select: OptionButton
var _add_layer_button: Button
## Generated controls to resync when the preset changes.
var _bound_controls: Dictionary = {}
var _debounce: SceneTreeTimer
var _suppress := false


func setup(
	ui_kit: UiKit,
	library_service: TileLibraryService = null
) -> void:
	_kit = ui_kit
	_library = library_service if library_service != null else TileLibraryService.new()
	_library.reload()
	current_manifest = _library.official_manifest("tile_kit_grass")
	preset = _library.load_recipe(current_manifest)
	if preset == null:
		preset = TileKitPreset.reference_clean_grass()
	_build()


# --- UI ----------------------------------------------------------------------


func _build() -> void:
	add_theme_constant_override("separation", 9)

	add_child(_section("TILE IDENTITY & LIFECYCLE"))
	add_child(_field_label("Stable ID"))
	_tile_id_field = LineEdit.new()
	_tile_id_field.placeholder_text = "Stable ID (tile_…)"
	_tile_id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tile_id_field)
	add_child(_field_label("Display name"))
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Display name…"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_preset_name)
	add_child(_field_label("Catalog family & availability"))
	var metadata_row := HBoxContainer.new()
	metadata_row.add_theme_constant_override("separation", 6)
	add_child(metadata_row)
	_family_field = LineEdit.new()
	_family_field.placeholder_text = "Catalog family"
	_family_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata_row.add_child(_family_field)
	_visibility_field = OptionButton.new()
	_visibility_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_visibility_field.tooltip_text = "Runtime availability after publication"
	_visibility_field.add_item("Active")
	_visibility_field.add_item("Preview")
	_visibility_field.add_item("Hidden")
	metadata_row.add_child(_visibility_field)
	_manifest_status = _kit.label("", 11)
	_manifest_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_manifest_status)

	add_child(_section("CREATE FROM GENERIC TEMPLATE"))
	var template_row := HBoxContainer.new()
	template_row.add_theme_constant_override("separation", 6)
	add_child(template_row)
	_template_select = OptionButton.new()
	_template_select.name = "TileLibraryTemplate"
	_template_select.fit_to_longest_item = false
	_template_select.custom_minimum_size.x = 140.0
	_template_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_select.tooltip_text = "Generic starting recipe used only for New Tile"
	for template in TileTemplateLibrary.TEMPLATES:
		_template_select.add_item(String(template["name"]))
		var template_index := _template_select.item_count - 1
		_template_select.set_item_metadata(template_index, template["id"])
		_template_select.set_item_tooltip(template_index, template["description"])
	template_row.add_child(_template_select)
	var new_button := _button("New Tile")
	new_button.custom_minimum_size.x = 86.0
	new_button.pressed.connect(_new_tile)
	template_row.add_child(new_button)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	add_child(actions)
	_draft_button = _button("Save Draft")
	_draft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draft_button.pressed.connect(func() -> void: _request_operation("draft"))
	actions.add_child(_draft_button)
	_mutation_buttons.append(_draft_button)
	_publish_button = _button("Publish New", true)
	_publish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_publish_button.pressed.connect(func() -> void: _request_operation("publish"))
	actions.add_child(_publish_button)
	_mutation_buttons.append(_publish_button)
	_overwrite_button = _button("Overwrite")
	_overwrite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overwrite_button.pressed.connect(func() -> void: _request_operation("overwrite"))
	actions.add_child(_overwrite_button)
	_mutation_buttons.append(_overwrite_button)
	_archive_button = _button("Archive")
	_archive_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_archive_button.pressed.connect(func() -> void: _request_operation("archive"))
	actions.add_child(_archive_button)
	_mutation_buttons.append(_archive_button)
	_delete_button = _button("Hard Delete")
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_button.pressed.connect(func() -> void: _request_operation("delete"))
	actions.add_child(_delete_button)
	_mutation_buttons.append(_delete_button)
	var action_spacer := Control.new()
	action_spacer.custom_minimum_size.y = 38.0
	actions.add_child(action_spacer)

	_confirmation = ConfirmationDialog.new()
	_confirmation.name = "TileLibraryConfirmation"
	_confirmation.confirmed.connect(_execute_pending_operation)
	add_child(_confirmation)
	var procedural_start := get_child_count()

	# Seed row.
	add_child(_section("MASTER SEED"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	add_child(seed_row)
	_seed_field = LineEdit.new()
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_field.text = str(preset.master_seed)
	_seed_field.text_submitted.connect(_on_seed_entered)
	seed_row.add_child(_seed_field)
	var previous := _button("Prev")
	previous.tooltip_text = "Return to the previous master seed"
	previous.pressed.connect(_previous_seed)
	seed_row.add_child(previous)
	var reroll := _button("Randomize All", true)
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll.pressed.connect(_randomize_all)
	add_child(reroll)

	# Topology is a preset-level art decision, not a layer parameter: an
	# organic grass cap should fuse across cells, while a paved path can keep
	# the soft groove around every authored tile.
	add_child(_section("TILE EDGES"))
	_separate_tiles = CheckBox.new()
	_separate_tiles.name = "TileKitSeparateTiles"
	_separate_tiles.text = "Keep tiles separated"
	_separate_tiles.tooltip_text = (
		"Keep the bevel and groove between neighbouring tiles. Turn this off "
		+ "for grass and other ground that should fuse into one surface."
	)
	_separate_tiles.button_pressed = preset.separate_tiles
	_separate_tiles.toggled.connect(func(on: bool) -> void:
		if not _suppress:
			preset.separate_tiles = on
			_emit_change(true))
	add_child(_separate_tiles)

	# Capabilities and their controls are generated from one declarative schema.
	# This is what keeps Leaves, Wood Chips, Snow Lumps, Pavers, or a future
	# builder reusable instead of growing tile-name-specific inspector code.
	add_child(_section("CAPABILITY STACK"))
	_layer_list = VBoxContainer.new()
	_layer_list.name = "TileKitCapabilityStack"
	_layer_list.add_theme_constant_override("separation", 5)
	add_child(_layer_list)
	var add_layer_row := HBoxContainer.new()
	add_layer_row.add_theme_constant_override("separation", 6)
	add_child(add_layer_row)
	_add_layer_select = OptionButton.new()
	_add_layer_select.name = "TileKitAddCapability"
	_add_layer_select.fit_to_longest_item = false
	_add_layer_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_layer_row.add_child(_add_layer_select)
	_add_layer_button = _button("Add")
	_add_layer_button.name = "TileKitAddCapabilityButton"
	_add_layer_button.pressed.connect(_add_selected_layer)
	add_layer_row.add_child(_add_layer_button)

	add_child(_section("CAPABILITY SETTINGS"))
	_parameter_editor = VBoxContainer.new()
	_parameter_editor.name = "TileKitCapabilitySettings"
	_parameter_editor.add_theme_constant_override("separation", 5)
	add_child(_parameter_editor)
	_rebuild_capability_ui()

	# Output.
	add_child(_section("OUTPUT"))
	var regenerate := _button("Regenerate")
	regenerate.pressed.connect(func() -> void: _emit_change(true))
	add_child(regenerate)
	_bake_button = _button("Bake To Game", true)
	_bake_button.tooltip_text = "Write uniquely named layer scenes for this stable tile ID"
	_bake_button.pressed.connect(func() -> void: bake_requested.emit())
	add_child(_bake_button)
	var export_button := _button("Export GLB")
	export_button.pressed.connect(func() -> void: export_requested.emit())
	add_child(export_button)

	_stats_label = _kit.label("", 12)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats_label)
	for index in range(procedural_start, get_child_count()):
		var child := get_child(index)
		if child is Control:
			_procedural_controls.append(child as Control)
	_sync_manifest_fields()
	_sync_recipe_controls()
	_sync_mutation_controls()


func _section(text: String) -> Label:
	var label := _kit.label(text, 12, false, true)
	label.add_theme_color_override("font_color", Color(0.42, 0.46, 0.40))
	return label


func _field_label(text: String) -> Label:
	var label := _kit.label(text, 11, false, true)
	label.add_theme_color_override("font_color", Color(0.34, 0.38, 0.34))
	return label


func _button(text: String, accent := false) -> Button:
	var button := _kit.choice_button(text, accent)
	button.custom_minimum_size.y = 38.0
	return button


## Compatibility entry point for the focused dune contract. The generated
## inspector now adds/removes conditional rows instead of hiding a fixed set.
func _sync_dune_controls() -> void:
	_rebuild_capability_ui()


# --- schema-driven capabilities ---------------------------------------------


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _rebuild_capability_ui() -> void:
	if _layer_list == null or _parameter_editor == null or preset == null:
		return
	_clear_container(_layer_list)
	_layer_rows.clear()
	for layer: TileKitLayer in preset.layers:
		var row := _capability_layer_row(layer.kind)
		_layer_list.add_child(row)
	_rebuild_add_layer_menu()
	_rebuild_parameter_editor()


func _rebuild_add_layer_menu() -> void:
	_add_layer_select.clear()
	for kind: String in TileLayerParameterSchema.KIND_ORDER:
		if preset.layer_of_kind(kind) != null:
			continue
		_add_layer_select.add_item(TileLayerParameterSchema.label(kind))
		_add_layer_select.set_item_metadata(_add_layer_select.item_count - 1, kind)
	var disabled := _add_layer_select.item_count == 0 or not _recipe_editable
	_add_layer_button.disabled = disabled
	_add_layer_select.disabled = disabled


func _capability_layer_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TileKitLayerRow_%s" % kind
	row.add_theme_constant_override("separation", 5)
	var layer := preset.layer_of_kind(kind)
	var enabled := CheckBox.new()
	enabled.text = "On"
	enabled.tooltip_text = "Include this capability in the generated tile"
	enabled.button_pressed = layer != null and layer.enabled
	enabled.toggled.connect(func(on: bool) -> void:
		var target := preset.layer_of_kind(kind)
		if target != null and not _suppress:
			target.enabled = on
			_emit_change(true))
	row.add_child(enabled)
	var lock := CheckBox.new()
	lock.text = "Lock"
	lock.tooltip_text = "Keep this capability's layout through Randomize All"
	lock.button_pressed = layer != null and layer.locked
	lock.toggled.connect(func(on: bool) -> void:
		var target := preset.layer_of_kind(kind)
		if target == null:
			return
		if on:
			target.stream_snapshot = TileKitGenerator.layer_stream(preset.master_seed, target)
		else:
			target.stream_snapshot = 0
		target.locked = on)
	row.add_child(lock)
	var label := _kit.label(TileLayerParameterSchema.label(kind), 12)
	label.tooltip_text = TileLayerParameterSchema.description(kind)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	if kind != "base":
		var reroll := _button("Roll")
		reroll.custom_minimum_size.x = 54.0
		reroll.tooltip_text = "Randomize layout while preserving every setting"
		reroll.pressed.connect(func() -> void: _randomize_layer_layout(kind))
		row.add_child(reroll)
		var remove := _button("-")
		remove.name = "TileKitRemoveCapability_%s" % kind
		remove.custom_minimum_size.x = 34.0
		remove.tooltip_text = "Remove this capability from the recipe"
		remove.pressed.connect(func() -> void: _remove_layer(kind))
		row.add_child(remove)
	_layer_rows[kind] = row
	return row


func _randomize_layer_layout(kind: String) -> void:
	var layer := preset.layer_of_kind(kind)
	if layer == null or layer.locked:
		status.emit("%s is locked." % TileLayerParameterSchema.label(kind))
		return
	layer.seed_offset += 1
	_emit_change(true)


func _vary_layer_settings(kind: String) -> void:
	var layer := preset.layer_of_kind(kind)
	if layer == null or layer.locked:
		status.emit("%s is locked." % TileLayerParameterSchema.label(kind))
		return
	var rng := RandomNumberGenerator.new()
	layer.seed_offset += 1
	rng.seed = hash("%d|%s|settings|%d" % [
		preset.master_seed, kind, layer.seed_offset,
	])
	TileLayerParameterSchema.randomize_parameters(layer, rng)
	_rebuild_parameter_editor()
	status.emit("Varied %s settings and layout." % TileLayerParameterSchema.label(kind))
	_emit_change(true)


func _add_selected_layer() -> void:
	if _add_layer_select.item_count == 0:
		return
	var kind := String(_add_layer_select.get_item_metadata(_add_layer_select.selected))
	var layer := TileLayerParameterSchema.new_layer(kind)
	if layer == null or preset.layer_of_kind(kind) != null:
		return
	var index := TileLayerParameterSchema.ordered_insertion_index(preset.layers, kind)
	preset.layers.insert(index, layer)
	_rebuild_capability_ui()
	status.emit("Added %s capability." % TileLayerParameterSchema.label(kind))
	_emit_change(true)


func _remove_layer(kind: String) -> void:
	if kind == "base":
		return
	var layer := preset.layer_of_kind(kind)
	if layer == null:
		return
	preset.layers.erase(layer)
	_rebuild_capability_ui()
	status.emit("Removed %s capability." % TileLayerParameterSchema.label(kind))
	_emit_change(true)


func _rebuild_parameter_editor() -> void:
	if _parameter_editor == null or preset == null:
		return
	_clear_container(_parameter_editor)
	_bound_controls.clear()
	for layer: TileKitLayer in preset.layers:
		var heading := _section(TileLayerParameterSchema.label(layer.kind).to_upper())
		_parameter_editor.add_child(heading)
		var help := _kit.label(TileLayerParameterSchema.description(layer.kind), 10)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.modulate = Color(1.0, 1.0, 1.0, 0.72)
		_parameter_editor.add_child(help)
		var previous_section := ""
		for raw: Variant in TileLayerParameterSchema.parameters(layer.kind):
			var parameter := raw as Dictionary
			if not TileLayerParameterSchema.is_visible(parameter, layer):
				continue
			var section := String(parameter.get("section", ""))
			if not section.is_empty() and section != previous_section:
				_parameter_editor.add_child(_field_label(section))
				previous_section = section
			_add_parameter_control(layer, parameter)
		var vary := _button("Vary Settings & Layout")
		vary.name = "TileKitVarySettings_%s" % layer.kind
		vary.tooltip_text = "Randomize numeric ranges; content type stays unchanged"
		vary.disabled = not _recipe_editable or layer.locked
		var vary_kind := layer.kind
		vary.pressed.connect(func() -> void: _vary_layer_settings(vary_kind))
		_parameter_editor.add_child(vary)
		if layer.kind == "base" and String(layer.value("relief_style", "none")) \
				== "sculpted_dunes":
			var randomize_dunes := _button("Randomize Dune Study", true)
			randomize_dunes.name = "TileKitRandomizeDunes"
			randomize_dunes.tooltip_text = "Vary the deterministic wind-shaped dune study"
			randomize_dunes.pressed.connect(_randomize_dunes)
			_parameter_editor.add_child(randomize_dunes)
	_sync_bound_controls()


func _add_parameter_control(layer: TileKitLayer, parameter: Dictionary) -> void:
	match String(parameter.get("type", "float")):
		"bool":
			_add_parameter_checkbox(layer, parameter)
		"enum":
			_add_parameter_enum(layer, parameter)
		"multi":
			_add_parameter_multi(layer, parameter)
		"range_float", "range_int":
			_add_parameter_slider(layer, parameter, 0)
			_add_parameter_slider(layer, parameter, 1)
		_:
			_add_parameter_slider(layer, parameter, -1)


func _add_parameter_slider(layer: TileKitLayer, parameter: Dictionary,
		range_index: int) -> void:
	var key := String(parameter["key"])
	var label_text := String(parameter["label"])
	if range_index == 0:
		label_text += " min"
	elif range_index == 1:
		label_text += " max"
	var suffix := "" if range_index < 0 else "_%s" % ["min", "max"][range_index]
	var row := HBoxContainer.new()
	row.name = "TileKitSliderRow_%s_%s%s" % [layer.kind, key, suffix]
	row.add_theme_constant_override("separation", 7)
	_parameter_editor.add_child(row)
	var label := _kit.label(label_text, 11)
	label.custom_minimum_size.x = 104.0
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "TileKitSlider_%s_%s%s" % [layer.kind, key, suffix]
	slider.tooltip_text = label_text
	slider.min_value = float(parameter.get("min", 0.0))
	slider.max_value = float(parameter.get("max", 1.0))
	slider.step = float(parameter.get("step", 0.01))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := _kit.label("", 10)
	value_label.custom_minimum_size.x = 42.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_bound_controls[slider] = {
		"kind": layer.kind, "key": key, "type": String(parameter.get("type", "float")),
		"range_index": range_index,
		"fallback": TileLayerParameterSchema.fallback(parameter, layer.kind),
		"value_label": value_label,
	}
	var slider_kind := layer.kind
	slider.value_changed.connect(func(value: float) -> void:
		if _suppress:
			return
		var target := preset.layer_of_kind(slider_kind)
		if target == null:
			return
		if range_index < 0:
			target.params[key] = int(round(value)) \
				if String(parameter.get("type", "float")) == "int" else value
		else:
			var band: Array = target.value(
				key, TileLayerParameterSchema.fallback(parameter, slider_kind)
			)
			band = band.duplicate() if band.size() >= 2 else [value, value]
			band[range_index] = int(round(value)) \
				if String(parameter.get("type", "")) == "range_int" else value
			if float(band[0]) > float(band[1]):
				band[1 - range_index] = band[range_index]
			target.params[key] = band
		_update_slider_value_label(slider, value_label)
		_emit_change(false))


func _add_parameter_checkbox(layer: TileKitLayer, parameter: Dictionary) -> void:
	var key := String(parameter["key"])
	var box := CheckBox.new()
	box.name = "TileKitCheck_%s_%s" % [layer.kind, key]
	box.text = String(parameter["label"])
	_parameter_editor.add_child(box)
	_bound_controls[box] = {"kind": layer.kind, "key": key,
		"type": "bool", "fallback": TileLayerParameterSchema.fallback(parameter, layer.kind)}
	var box_kind := layer.kind
	box.toggled.connect(func(on: bool) -> void:
		var target := preset.layer_of_kind(box_kind)
		if target != null and not _suppress:
			target.params[key] = on
			_emit_change(true))


func _add_parameter_enum(layer: TileKitLayer, parameter: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_parameter_editor.add_child(row)
	var label := _kit.label(String(parameter["label"]), 11)
	label.custom_minimum_size.x = 104.0
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "TileKitOption_%s_%s" % [layer.kind, parameter["key"]]
	option.fit_to_longest_item = false
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var values: Array = parameter.get("values", [])
	var labels: Array = parameter.get("value_labels", [])
	for index in values.size():
		option.add_item(String(labels[index]) if index < labels.size() \
			else _humanize(String(values[index])))
		option.set_item_metadata(index, values[index])
	row.add_child(option)
	var key := String(parameter["key"])
	_bound_controls[option] = {"kind": layer.kind, "key": key,
		"type": "enum", "fallback": TileLayerParameterSchema.fallback(parameter, layer.kind)}
	var option_kind := layer.kind
	option.item_selected.connect(func(index: int) -> void:
		if _suppress:
			return
		var target := preset.layer_of_kind(option_kind)
		if target != null:
			target.params[key] = option.get_item_metadata(index)
			call_deferred("_rebuild_parameter_editor")
			_emit_change(true))


func _add_parameter_multi(layer: TileKitLayer, parameter: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_parameter_editor.add_child(row)
	var label := _kit.label(String(parameter["label"]), 11)
	label.custom_minimum_size.x = 104.0
	row.add_child(label)
	var menu := MenuButton.new()
	menu.name = "TileKitMulti_%s_%s" % [layer.kind, parameter["key"]]
	menu.set_meta("allow_empty", bool(parameter.get("allow_empty", false)))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var values: Array = parameter.get("values", [])
	var labels: Array = parameter.get("value_labels", [])
	var popup := menu.get_popup()
	for index in values.size():
		popup.add_check_item(String(labels[index]) if index < labels.size() \
			else _humanize(String(values[index])), index)
		popup.set_item_metadata(index, values[index])
	var multi_kind := layer.kind
	var key := String(parameter["key"])
	popup.id_pressed.connect(func(id: int) -> void: _on_multi_item(menu, multi_kind, key, id))
	row.add_child(menu)
	_bound_controls[menu] = {"kind": layer.kind, "key": key,
		"type": "multi", "fallback": TileLayerParameterSchema.fallback(parameter, layer.kind)}


func _on_multi_item(menu: MenuButton, kind: String, key: String, id: int) -> void:
	var layer := preset.layer_of_kind(kind)
	if layer == null:
		return
	var popup := menu.get_popup()
	var selected: Array = layer.value(key, []).duplicate()
	var value: Variant = popup.get_item_metadata(id)
	if value in selected:
		if selected.size() == 1 and not bool(menu.get_meta("allow_empty", false)):
			status.emit("At least one piece type or edge must remain selected.")
			return
		selected.erase(value)
	else:
		selected.append(value)
	layer.params[key] = selected
	_sync_multi_control(menu, selected)
	_emit_change(true)


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _sync_bound_controls() -> void:
	_suppress = true
	for control: Control in _bound_controls:
		var binding := _bound_controls[control] as Dictionary
		var layer := preset.layer_of_kind(String(binding["kind"]))
		if layer == null:
			continue
		var value: Variant = layer.value(
			String(binding["key"]), binding.get("fallback", 0.0)
		)
		match String(binding["type"]):
			"float", "int":
				var slider := control as HSlider
				slider.set_value_no_signal(clampf(float(value), slider.min_value, slider.max_value))
				_update_slider_value_label(slider, binding["value_label"] as Label)
			"range_float", "range_int":
				var slider := control as HSlider
				var band: Array = value if value is Array else [value, value]
				var index := int(binding["range_index"])
				var component: Variant = (
					band[index] if band.size() > index else slider.min_value
				)
				slider.set_value_no_signal(clampf(float(component), slider.min_value, slider.max_value))
				_update_slider_value_label(slider, binding["value_label"] as Label)
			"bool":
				(control as CheckBox).set_pressed_no_signal(bool(value))
			"enum":
				var option := control as OptionButton
				for index in option.item_count:
					if option.get_item_metadata(index) == value:
						option.select(index)
						break
			"multi":
				_sync_multi_control(control as MenuButton, value if value is Array else [])
	_suppress = false


func _sync_multi_control(menu: MenuButton, selected: Array) -> void:
	var popup := menu.get_popup()
	for index in popup.item_count:
		popup.set_item_checked(index, popup.get_item_metadata(index) in selected)
	menu.text = "%d selected" % selected.size()


func _update_slider_value_label(slider: HSlider, label: Label) -> void:
	label.text = str(int(round(slider.value))) if slider.step >= 1.0 \
		else String.num(slider.value, 3).trim_suffix("0").trim_suffix("0").trim_suffix(".")


# --- behaviour ---------------------------------------------------------------


func _emit_change(immediate: bool) -> void:
	if _suppress:
		return
	if immediate:
		changed.emit()
		return
	# Debounce: sliders fire per pixel; the preview only needs the last one.
	var stamp := Time.get_ticks_msec()
	set_meta("last_change", stamp)
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(DEBOUNCE_SECONDS)
	timer.timeout.connect(func() -> void:
		if get_meta("last_change", 0) == stamp:
			changed.emit())


func _on_seed_entered(text: String) -> void:
	if not text.is_valid_int():
		status.emit("Seeds are whole numbers.")
		return
	_seed_history.append(preset.master_seed)
	preset.master_seed = int(text)
	_emit_change(true)


func _randomize_all() -> void:
	_seed_history.append(preset.master_seed)
	preset.master_seed = randi() % 1000000
	_seed_field.text = str(preset.master_seed)
	_emit_change(true)


func _randomize_dunes() -> void:
	var base := preset.layer_of_kind("base")
	if base == null or String(base.value("relief_style", "none")) \
			!= "sculpted_dunes":
		status.emit("Choose a sculpted dune preset first.")
		return
	var next_pattern := int(base.value("dune_seed_offset", 0)) + 1
	var dune_rng := RandomNumberGenerator.new()
	dune_rng.seed = hash("%d|dune_editor|%d" % [preset.master_seed, next_pattern])
	base.params["dune_seed_offset"] = next_pattern
	base.params["relief_amplitude"] = dune_rng.randf_range(0.025, 0.145)
	base.params["dune_scale"] = dune_rng.randf_range(0.45, 1.10)
	base.params["dune_amount"] = dune_rng.randf_range(0.20, 0.92)
	base.params["dune_softness"] = dune_rng.randf_range(0.38, 0.96)
	base.params["dune_irregularity"] = dune_rng.randf_range(0.15, 0.92)
	base.params["dune_lee_depth"] = dune_rng.randf_range(0.04, 0.58)
	base.params["dune_direction_degrees"] = dune_rng.randf_range(0.0, 360.0)
	base.params["dune_height_exponent"] = dune_rng.randf_range(0.82, 1.16)
	_sync_bound_controls()
	status.emit("Randomized dune pattern, amount, and shaping.")
	_emit_change(true)


func _previous_seed() -> void:
	if _seed_history.is_empty():
		status.emit("No earlier seed this session.")
		return
	preset.master_seed = _seed_history.pop_back()
	_seed_field.text = str(preset.master_seed)
	_emit_change(true)


func show_statistics(stats: Dictionary) -> void:
	_stats_label.text = "seed %d  ·  %s triangles  ·  %d materials  ·  %d layers" % [
		preset.master_seed,
		String.num_int64(int(stats.get("triangles", 0))),
		int(stats.get("materials", 0)),
		int(stats.get("layers", 0)),
	]


# --- official library --------------------------------------------------------


func current_tile_id() -> String:
	return _tile_id_field.text.strip_edges() if _tile_id_field != null else ""


func manifest_for(tile_id: String) -> TileLibraryManifest:
	return _library.official_manifest(tile_id) if _library != null else null


func can_bake_current() -> bool:
	return _library != null \
		and _library.can_mutate_official() \
		and current_manifest != null \
		and current_manifest.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL \
		and not current_tile_id().is_empty()


func select_tile(tile_id: String) -> bool:
	# The library is loaded once when the panel opens and refreshed by every CRUD
	# operation. Reloading all manifests here put synchronous disk I/O on every
	# catalog click, even though selection cannot change library membership.
	var selected := _library.official_manifest(tile_id)
	if selected == null:
		status.emit("Tile '%s' has no official manifest." % tile_id)
		return false
	current_manifest = selected
	var loaded := _library.load_recipe(current_manifest)
	_recipe_editable = loaded != null
	if loaded != null:
		preset = loaded
	elif preset == null:
		preset = TileKitPreset.reference_clean_grass()
	_sync_manifest_fields()
	_sync_recipe_controls()
	return true


func _sync_manifest_fields() -> void:
	if current_manifest == null or _tile_id_field == null:
		return
	_suppress = true
	_tile_id_field.text = current_manifest.tile_id
	_preset_name.text = current_manifest.display_name
	_family_field.text = current_manifest.family
	_visibility_field.select([
		TileLibraryManifest.VISIBILITY_ACTIVE,
		TileLibraryManifest.VISIBILITY_PREVIEW,
		TileLibraryManifest.VISIBILITY_HIDDEN,
	].find(current_manifest.visibility))
	var official_target := _library.official_manifest(current_manifest.tile_id)
	_tile_id_field.editable = (
		not current_manifest.is_official()
		and (official_target == null or not official_target.is_official())
	)
	if preset != null:
		_seed_field.text = str(preset.master_seed)
		_separate_tiles.set_pressed_no_signal(preset.separate_tiles)
	var source_note := (
		"Editable procedural recipe"
		if current_manifest.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL
		else "Imported geometry · manifest metadata only until replaced procedurally"
	)
	_manifest_status.text = "%s · revision %d · %s · %s" % [
		current_manifest.lifecycle,
		current_manifest.revision,
		current_manifest.visibility,
		source_note,
	]
	_suppress = false
	_sync_mutation_controls()


func _sync_recipe_controls() -> void:
	if preset == null:
		return
	for control in _procedural_controls:
		control.visible = _recipe_editable
	_rebuild_capability_ui()
	_separate_tiles.disabled = not _recipe_editable
	for control: Control in _bound_controls:
		if control is BaseButton:
			(control as BaseButton).disabled = not _recipe_editable
		elif control is Slider:
			(control as Slider).editable = _recipe_editable
	for row in _layer_rows.values():
		for child in (row as HBoxContainer).get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = not _recipe_editable


func _sync_mutation_controls() -> void:
	if _library == null:
		return
	var read_only := not _library.can_mutate_official()
	for button in _mutation_buttons:
		button.tooltip_text = (
			"Official content is read-only in release builds." if read_only else ""
		)
	var official_target := (
		_library.official_manifest(current_manifest.tile_id)
		if current_manifest != null else null
	)
	var can_overwrite := official_target != null and official_target.is_official()
	_draft_button.disabled = read_only or current_manifest == null
	_publish_button.disabled = read_only or current_manifest == null or can_overwrite
	_overwrite_button.disabled = read_only or not can_overwrite
	_archive_button.disabled = (
		read_only
		or current_manifest == null
		or current_manifest.lifecycle != TileLibraryManifest.LIFECYCLE_PUBLISHED
	)
	_delete_button.disabled = (
		read_only
		or current_manifest == null
		or current_manifest.resource_path.is_empty()
	)
	if _bake_button != null:
		_bake_button.disabled = not can_bake_current()
	if read_only and _manifest_status != null:
		_manifest_status.text += " · RELEASE READ-ONLY"


func _new_tile() -> void:
	var template_id := String(_template_select.get_item_metadata(
		_template_select.selected
	))
	var base := TileTemplateLibrary.instantiate(template_id)
	if base == null:
		status.emit("Could not create the selected generic template.")
		return
	preset = base
	current_manifest = _library.new_manifest_from(
		base, "", base.preset_name
	)
	_recipe_editable = true
	_sync_manifest_fields()
	_sync_recipe_controls()
	_tile_id_field.editable = true
	_tile_id_field.grab_focus()
	status.emit(
		(
			"New tile from the %s template. Give it a stable ID, then Save Draft "
			+ "or Publish New."
		) % TileTemplateLibrary.display_name(template_id)
	)
	_emit_change(true)


func _working_manifest_from_fields() -> TileLibraryManifest:
	var working := (
		current_manifest.duplicate_manifest()
		if current_manifest != null
		else _library.new_manifest_from(preset)
	)
	working.tile_id = _tile_id_field.text.strip_edges()
	working.display_name = _preset_name.text.strip_edges()
	working.family = _family_field.text.strip_edges()
	working.visibility = [
		TileLibraryManifest.VISIBILITY_ACTIVE,
		TileLibraryManifest.VISIBILITY_PREVIEW,
		TileLibraryManifest.VISIBILITY_HIDDEN,
	][_visibility_field.selected]
	if working.connection_group.is_empty() or not working.is_official():
		working.connection_group = working.tile_id
	working.separate_tiles = preset != null and preset.separate_tiles
	return working


func _request_operation(operation: String) -> void:
	_pending_operation = operation
	var working := _working_manifest_from_fields()
	var action: String = String({
		"draft": "Save draft",
		"publish": "Publish new official tile",
		"overwrite": "Overwrite official tile",
		"archive": "Archive official tile",
		"delete": "Permanently hard-delete tile",
	}.get(operation, operation))
	_confirmation.title = String(action)
	_confirmation.dialog_text = "%s\n\n%s (%s)" % [
		action, working.display_name, working.tile_id,
	]
	if operation == "delete":
		_confirmation.dialog_text += (
			"\n\nThis removes its manifest, procedural recipe, and generated bake. "
			+ "References will block deletion; Archive is safer after launch."
		)
	elif operation in ["publish", "overwrite"]:
		_confirmation.dialog_text += (
			"\n\nThe recipe will be baked under this stable ID and the validated "
			+ "runtime catalog will be recompiled."
		)
	_confirmation.popup_centered(Vector2i(560, 300))
	_confirmation.get_ok_button().grab_focus()


func _execute_pending_operation() -> void:
	var working := _working_manifest_from_fields()
	var result: Dictionary
	match _pending_operation:
		"draft":
			result = _library.save_draft(working, preset)
		"publish":
			result = _library.publish_new(working, preset)
		"overwrite":
			result = _library.overwrite(working, preset)
		"archive":
			result = _library.archive(working.tile_id)
		"delete":
			result = (
				_library.delete_draft(current_manifest)
				if _library.is_user_draft(current_manifest)
				else _library.hard_delete(working.tile_id)
			)
		_:
			return
	_pending_operation = ""
	if not bool(result.get("ok", false)):
		var errors: PackedStringArray = result.get("errors", PackedStringArray())
		status.emit("Tile Library: %s" % "; ".join(errors))
		return
	current_manifest = result.get("manifest", null) as TileLibraryManifest
	if current_manifest == null:
		current_manifest = _library.official_manifest(working.tile_id)
	_sync_manifest_fields()
	status.emit("Tile Library operation completed for %s." % working.tile_id)
	library_changed.emit(working.tile_id)


## Kept as a compatibility entry point for existing panel tests/callers.
func _save_preset() -> void:
	_request_operation("draft")
