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

const DEBOUNCE_SECONDS := 0.13
const USER_PRESET_DIR := "user://tile_kit_presets"

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
var _preset_select: OptionButton
var _preset_name: LineEdit
var _separate_tiles: CheckBox
var _layer_rows: Dictionary = {}
## Tuning controls to resync when the preset changes: control -> [kind, key].
var _bound_controls: Dictionary = {}
## Dune-only rows stay out of the way for grass, paving, and legacy presets.
var _dune_controls: Array[Control] = []
var _debounce: SceneTreeTimer
var _suppress := false


func setup(ui_kit: UiKit) -> void:
	_kit = ui_kit
	preset = TileKitPreset.reference_clean_grass()
	_build()


# --- UI ----------------------------------------------------------------------


func _build() -> void:
	add_theme_constant_override("separation", 9)

	add_child(_kit.label("TILE KIT — PROCEDURAL TILE", 14, false, true))
	var intro := _kit.label(
		"Layered deterministic tile generator. Lock what you like, reroll "
		+ "the rest, bake to the game when it sings.", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	# Preset row.
	add_child(_section("PRESET"))
	_preset_select = OptionButton.new()
	_preset_select.custom_minimum_size.y = 38.0
	_preset_select.item_selected.connect(_on_preset_selected)
	add_child(_preset_select)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	add_child(name_row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Preset name…"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_preset_name)
	var save_button := _button("Save", true)
	save_button.pressed.connect(_save_preset)
	name_row.add_child(save_button)
	_refresh_preset_list()

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
	reroll.pressed.connect(_randomize_all)
	seed_row.add_child(reroll)

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
	var bake := _button("Bake To Game", true)
	bake.tooltip_text = "Write baked layer scenes the game loads for this tile"
	bake.pressed.connect(func() -> void: bake_requested.emit())
	add_child(bake)
	var export_button := _button("Export GLB")
	export_button.pressed.connect(func() -> void: export_requested.emit())
	add_child(export_button)

	_stats_label = _kit.label("", 12)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats_label)


func _section(text: String) -> Label:
	var label := _kit.label(text, 12, false, true)
	label.add_theme_color_override("font_color", Color(0.42, 0.46, 0.40))
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
		and String(base.value("relief_style", "none")) == "sculpted_dunes"
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


# --- presets on disk ---------------------------------------------------------


func _refresh_preset_list() -> void:
	_preset_select.clear()
	for built_in in TileKitPreset.built_in_names():
		_preset_select.add_item(built_in)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(USER_PRESET_DIR))
	var directory := DirAccess.open(USER_PRESET_DIR)
	if directory == null:
		return
	for file in directory.get_files():
		if file.ends_with(".tres"):
			_preset_select.add_item(file.trim_suffix(".tres"))


func _on_preset_selected(index: int) -> void:
	var built_ins := TileKitPreset.built_in_names()
	if index < built_ins.size():
		preset = TileKitPreset.make_built_in(_preset_select.get_item_text(index))
	else:
		var path := "%s/%s.tres" % [USER_PRESET_DIR, _preset_select.get_item_text(index)]
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is TileKitPreset:
			preset = loaded
		else:
			status.emit("Could not load %s" % path)
			return
	_suppress = true
	_seed_field.text = str(preset.master_seed)
	_preset_name.text = "" if index < built_ins.size() else preset.preset_name
	_separate_tiles.set_pressed_no_signal(preset.separate_tiles)
	_suppress = false
	_sync_bound_controls()
	_sync_dune_controls()
	_emit_change(true)


func _save_preset() -> void:
	var name_text := _preset_name.text.strip_edges()
	if name_text.is_empty():
		status.emit("Name the preset before saving.")
		return
	preset.preset_name = name_text
	var path := "%s/%s.tres" % [USER_PRESET_DIR, name_text.validate_filename()]
	var error := ResourceSaver.save(preset.duplicate_preset(), path)
	if error != OK:
		status.emit("Save failed: %s" % error_string(error))
		return
	_refresh_preset_list()
	status.emit("Saved preset %s." % name_text)
