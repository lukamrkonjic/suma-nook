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
const LAYER_LABELS := {
	"base": "Base",
	"dressing": "Dressing",
	"clutter": "Small Clutter",
	"grass_clusters": "Grass",
}

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
## Tuning controls to resync when the preset changes: control -> [kind, key].
var _bound_controls: Dictionary = {}
## Dune-only rows stay out of the way for grass, paving, and legacy presets.
var _dune_controls: Array[Control] = []
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

	# Layer rows.
	add_child(_section("LAYERS"))
	for kind: String in LAYER_LABELS:
		add_child(_layer_row(kind))

	# The handful of parameters that shape the look most; everything else
	# lives in the preset resource for deep edits.
	add_child(_section("TUNING"))
	_slider("Grass spacing", "grass_clusters", "carpet_spacing", 0.16, 0.34)
	_slider("Grass gaps", "grass_clusters", "carpet_skip_fraction", 0.0, 0.35)
	_slider("Grass height", "grass_clusters", "height_multiplier", 0.6, 1.5)
	_slider("Grass width", "grass_clusters", "width_multiplier", 0.6, 1.5)
	_slider("Dressing scale", "dressing", "scale_multiplier", 0.5, 1.6)
	_slider("Clutter scale", "clutter", "scale_multiplier", 0.5, 1.6)
	_checkbox("Blobs may overlap", "dressing", "allow_overlap", true)

	# Source-inspired sand/snow relief. The two study presets opt into this
	# explicitly, so the established procedural presets remain untouched while
	# their replacement look is being judged.
	var dune_heading := _section("SCULPTED DUNES")
	add_child(dune_heading)
	_dune_controls.append(dune_heading)
	_dune_controls.append(_slider(
		"Dune strength", "base", "relief_amplitude", 0.005, 0.180))
	_dune_controls.append(_slider(
		"Dune scale", "base", "dune_scale", 0.35, 1.25))
	_dune_controls.append(_slider(
		"Dune amount", "base", "dune_amount", 0.0, 1.0))
	_dune_controls.append(_slider(
		"Dune softness", "base", "dune_softness", 0.0, 1.0))
	_dune_controls.append(_slider(
		"Irregularity", "base", "dune_irregularity", 0.0, 1.0))
	_dune_controls.append(_slider(
		"Lee shoulder", "base", "dune_lee_depth", 0.0, 1.0))
	_dune_controls.append(_slider(
		"Wind direction", "base", "dune_direction_degrees", 0.0, 360.0, 1.0))
	var randomize_dunes := _button("Randomize Dunes", true)
	randomize_dunes.name = "TileKitRandomizeDunes"
	randomize_dunes.tooltip_text = (
		"Create a new deterministic dune pattern and vary its shaping controls."
	)
	randomize_dunes.pressed.connect(_randomize_dunes)
	add_child(randomize_dunes)
	_dune_controls.append(randomize_dunes)
	_sync_dune_controls()

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


func _layer_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var eye := CheckBox.new()
	eye.text = "👁"
	eye.tooltip_text = "Show this layer in the preview"
	eye.button_pressed = true
	eye.toggled.connect(func(on: bool) -> void:
		var layer := preset.layer_of_kind(kind)
		if layer != null:
			layer.enabled = on
			_emit_change(true))
	row.add_child(eye)
	var lock := CheckBox.new()
	lock.text = "🔒"
	lock.tooltip_text = "Locked layers survive Randomize All untouched"
	lock.toggled.connect(func(on: bool) -> void:
		# Locking snapshots the layer's current stream so later master-seed
		# changes cannot move it — same rule as TileKitGenerator.set_layer_locked.
		var layer := preset.layer_of_kind(kind)
		if layer == null:
			return
		if on:
			layer.stream_snapshot = TileKitGenerator.layer_stream(
				preset.master_seed, layer)
		else:
			layer.stream_snapshot = 0
		layer.locked = on)
	row.add_child(lock)
	var label := _kit.label(LAYER_LABELS[kind], 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if kind != "base":
		var reroll := _button("Randomize")
		reroll.pressed.connect(func() -> void:
			var layer := preset.layer_of_kind(kind)
			if layer == null or layer.locked:
				status.emit("%s is locked." % LAYER_LABELS[kind])
				return
			layer.seed_offset += 1
			_emit_change(true))
		row.add_child(reroll)
	_layer_rows[kind] = row
	return row


func _checkbox(label_text: String, kind: String, key: String,
		fallback: bool) -> void:
	var box := CheckBox.new()
	box.text = label_text
	var layer := preset.layer_of_kind(kind)
	box.button_pressed = bool(layer.value(key, fallback)) if layer != null else fallback
	box.toggled.connect(func(on: bool) -> void:
		var target := preset.layer_of_kind(kind)
		if target != null and not _suppress:
			target.params[key] = on
			_emit_change(true))
	add_child(box)
	_bound_controls[box] = [kind, key]


func _slider(label_text: String, kind: String, key: String,
		minimum: float, maximum: float, step := 0.005) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TileKitSliderRow_%s_%s" % [kind, key]
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var label := _kit.label(label_text, 12)
	label.custom_minimum_size.x = 108.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "TileKitSlider_%s_%s" % [kind, key]
	slider.tooltip_text = label_text
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var layer := preset.layer_of_kind(kind)
	slider.value = float(layer.value(key, minimum)) if layer != null else minimum
	slider.value_changed.connect(func(value: float) -> void:
		var target := preset.layer_of_kind(kind)
		if target != null and not _suppress:
			target.params[key] = value
			_emit_change(false))
	row.add_child(slider)
	_bound_controls[slider] = [kind, key]
	return row


## Repoints every tuning control at the freshly selected preset, silently —
## without this, controls keep showing the previous preset's values and the
## first touch stomps the new preset with stale numbers.
func _sync_bound_controls() -> void:
	_suppress = true
	for control: Control in _bound_controls:
		var binding: Array = _bound_controls[control]
		var layer := preset.layer_of_kind(String(binding[0]))
		if layer == null:
			continue
		if control is HSlider:
			var slider := control as HSlider
			slider.set_value_no_signal(clampf(
				float(layer.value(String(binding[1]), slider.min_value)),
				slider.min_value, slider.max_value))
		elif control is CheckBox:
			(control as CheckBox).set_pressed_no_signal(
				bool(layer.value(String(binding[1]), true)))
	_suppress = false


func _sync_dune_controls() -> void:
	var base := preset.layer_of_kind("base")
	var show_dunes := base != null \
		and String(base.value("relief_style", "none")) == "sculpted_dunes" \
		and _recipe_editable
	for control in _dune_controls:
		control.visible = show_dunes


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
	_sync_bound_controls()
	_sync_dune_controls()
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
