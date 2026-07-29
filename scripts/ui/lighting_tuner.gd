class_name LightingTuner
extends CanvasLayer
## ReShade-style live lighting cockpit (debug builds; toggled from the pause
## menu's Admin page). Docks bottom-left over the game and edits the ACTIVE
## VisualStyleProfile in place — every slider re-applies the rig immediately,
## so the look can be dialled in while walking around the world. "Copy" puts
## the current values on the clipboard as .tres lines; "Save" writes them back
## to the profile's resource file so the tuning becomes permanent.

signal closed

const SLIDERS := [
	# section, label, field, min, max, step
	["Sun", "Energy", "sun_energy", 0.0, 8.0, 0.05],
	["Sun", "Specular", "sun_specular", 0.0, 1.0, 0.01],
	["Sun", "Pitch", "sun_pitch_deg", -89.0, -5.0, 1.0],
	["Sun", "Yaw", "sun_yaw_deg", -180.0, 180.0, 1.0],
	["Sun", "Softness (disc)", "sun_angular_distance", 0.0, 5.0, 0.05],
	["Shadows", "Opacity", "shadow_opacity", 0.0, 1.0, 0.01],
	["Shadows", "Blur", "shadow_blur", 0.0, 5.0, 0.05],
	["Ambient", "Energy", "ambient_energy", 0.0, 4.0, 0.05],
	["Tone", "Exposure", "exposure", 0.3, 2.0, 0.01],
	["Tone", "AGX white", "agx_white", 2.0, 20.0, 0.25],
	["Tone", "AGX contrast", "agx_contrast", 0.5, 1.8, 0.01],
	["Tone", "Brightness", "brightness", 0.7, 1.3, 0.01],
	["Tone", "Contrast", "contrast", 0.7, 1.5, 0.01],
	["Tone", "Saturation", "saturation", 0.5, 1.8, 0.01],
	["Effects", "SSAO intensity", "ssao_intensity", 0.0, 3.0, 0.02],
	["Effects", "SSAO radius", "ssao_radius", 0.05, 1.0, 0.01],
	["Effects", "SSAO power", "ssao_power", 0.5, 2.5, 0.02],
	["Effects", "SSIL intensity", "ssil_intensity", 0.0, 0.5, 0.01],
	["Effects", "Glow intensity", "glow_intensity", 0.0, 0.6, 0.01],
	["Effects", "Glow threshold", "glow_hdr_threshold", 0.5, 3.0, 0.05],
	["Effects", "Glow bloom", "glow_bloom", 0.0, 0.2, 0.005],
	["Effects", "Local lights", "local_light_multiplier", 0.0, 3.0, 0.05],
	["Fog", "Ground density", "ground_fog_density", 0.0, 2.0, 0.01],
	["Fog", "Layer height", "ground_fog_height", 0.3, 3.5, 0.05],
	["Fog", "Noise scale", "ground_fog_noise_scale", 0.02, 0.35, 0.005],
	["Fog", "Wake radius", "ground_fog_disturbance_radius", 0.3, 1.8, 0.05],
	["Fog", "Close seconds", "ground_fog_close_seconds", 0.25, 4.0, 0.05],
	["Rain", "Surface wetness", "rain_surface_wetness", 0.0, 1.5, 0.02],
	["Rain", "Pooling", "rain_puddle_amount", 0.0, 1.5, 0.02],
	["Rain", "Impact ripples", "rain_ripple_amount", 0.0, 1.5, 0.02],
	["Rain", "Walking splash", "rain_walk_splash_amount", 0.0, 1.5, 0.02],
]
const COLORS := [
	["Sun", "Sun color", "sun_color"],
	["Ambient", "Flat ambient", "ambient_color"],
	["Ambient", "Sky", "ambient_sky_color"],
	["Ambient", "Equator", "ambient_equator_color"],
	["Ambient", "Ground", "ambient_ground_color"],
	["Backdrop", "Background", "background_color"],
	["Fog", "Fog albedo", "fog_color"],
]
const TOGGLES := [
	["Ambient", "Sky gradient fill", "ambient_gradient_enabled"],
	["Effects", "SSAO", "ssao_enabled"],
	["Effects", "SSIL", "ssil_enabled"],
	["Effects", "Glow", "glow_enabled"],
	["Fog", "Localized fog", "fog_enabled"],
]
const TONEMAPS := ["linear", "filmic", "aces", "agx"]
const COPY_FIELDS := [
	"background_color", "ambient_color", "ambient_energy",
	"ambient_gradient_enabled", "ambient_sky_color", "ambient_equator_color",
	"ambient_ground_color", "sun_color", "sun_energy", "sun_specular",
	"sun_pitch_deg", "sun_yaw_deg", "shadow_opacity", "shadow_blur",
	"sun_angular_distance", "ssao_enabled", "ssao_intensity", "ssao_radius",
	"ssao_power", "ssil_enabled", "ssil_intensity", "glow_enabled",
	"glow_intensity", "glow_hdr_threshold", "glow_bloom", "exposure",
	"tonemap", "agx_white", "agx_contrast", "brightness", "contrast",
	"saturation", "local_light_multiplier", "fog_enabled", "fog_color",
	"ground_fog_density", "ground_fog_height", "ground_fog_noise_scale",
	"ground_fog_disturbance_radius", "ground_fog_close_seconds",
	"rain_surface_wetness", "rain_puddle_amount", "rain_ripple_amount",
	"rain_walk_splash_amount",
]

var _lighting: LightingRig
var _kit: UiKit
var _profile_label: Label
var _status: Label
var _sliders: Dictionary = {}
var _pickers: Dictionary = {}
var _checks: Dictionary = {}
var _tonemap_option: OptionButton
var _refreshing := false
var _root: Control
var _input_service: InputDeviceService


func setup(lighting_rig: LightingRig, ui_kit: UiKit) -> void:
	_lighting = lighting_rig
	_kit = ui_kit
	_input_service = InputDeviceService.shared()
	# Above the pause menu (layer 80): the cockpit stays usable with the menu open.
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_lighting.profile_applied.connect(_on_profile_applied)
	refresh()


func focus_default() -> void:
	if visible and _root != null:
		_input_service.focus_first(_root)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("cancel"):
		return
	_input_service.release_focus_in(_root)
	visible = false
	closed.emit()
	get_viewport().set_input_as_handled()


func _on_profile_applied(_profile: VisualStyleProfile) -> void:
	if visible:
		refresh()


func _profile() -> VisualStyleProfile:
	return _lighting.current_profile if _lighting != null else null


func refresh() -> void:
	var profile := _profile()
	if profile == null:
		return
	_refreshing = true
	_profile_label.text = "%s  (%s)" % [profile.profile_id, profile.tonemap]
	for field in _sliders:
		var row: Dictionary = _sliders[field]
		(row["slider"] as HSlider).set_value_no_signal(float(profile.get(field)))
		(row["value"] as Label).text = "%.2f" % float(profile.get(field))
	for field in _pickers:
		(_pickers[field] as ColorPickerButton).color = profile.get(field)
	for field in _checks:
		(_checks[field] as CheckBox).set_pressed_no_signal(bool(profile.get(field)))
	_tonemap_option.selected = maxi(TONEMAPS.find(String(profile.tonemap)), 0)
	_refreshing = false


func _apply() -> void:
	if _refreshing:
		return
	var profile := _profile()
	if profile != null:
		_lighting.apply_profile(profile)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _kit.theme
	add_child(_root)

	var panel := PanelContainer.new()
	panel.name = "LightingTunerPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(12, -74)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _kit.cloud_panel_style())
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var title := _small_label("LIGHTING", 15)
	header.add_child(title)
	_profile_label = _small_label("", 13)
	_profile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_profile_label)
	var copy := _mini_button("Copy")
	copy.pressed.connect(_copy_to_clipboard)
	header.add_child(copy)
	var save := _mini_button("Save")
	save.pressed.connect(_save_to_disk)
	header.add_child(save)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	var current_section := ""
	for spec in SLIDERS:
		current_section = _section(list, String(spec[0]), current_section)
		_slider_row(list, spec)
		for color_spec in COLORS:
			if String(color_spec[0]) == String(spec[0]) and not _pickers.has(String(color_spec[2])):
				_color_row(list, color_spec)
		for toggle_spec in TOGGLES:
			if String(toggle_spec[0]) == String(spec[0]) and not _checks.has(String(toggle_spec[2])):
				_toggle_row(list, toggle_spec)
	current_section = _section(list, "Backdrop", current_section)
	for color_spec in COLORS:
		if not _pickers.has(String(color_spec[2])):
			_color_row(list, color_spec)
	var tone_row := HBoxContainer.new()
	tone_row.add_theme_constant_override("separation", 6)
	list.add_child(tone_row)
	tone_row.add_child(_row_label("Tonemap"))
	_tonemap_option = OptionButton.new()
	for mapper in TONEMAPS:
		_tonemap_option.add_item(mapper)
	_tonemap_option.custom_minimum_size = Vector2(110, 26)
	_tonemap_option.item_selected.connect(func(index: int):
		var profile := _profile()
		if profile != null:
			profile.tonemap = TONEMAPS[index]
			_apply()
	)
	tone_row.add_child(_tonemap_option)

	_status = _small_label("", 12)
	column.add_child(_status)


func _section(list: VBoxContainer, section: String, current: String) -> String:
	if section == current:
		return current
	var label := _small_label(section.to_upper(), 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.53, 0.46))
	list.add_child(label)
	return section


func _slider_row(list: VBoxContainer, spec: Array) -> void:
	var field := String(spec[2])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	row.add_child(_row_label(String(spec[1])))
	var slider := HSlider.new()
	slider.min_value = float(spec[3])
	slider.max_value = float(spec[4])
	slider.step = float(spec[5])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(150, 22)
	row.add_child(slider)
	var value := _small_label("0.00", 12)
	value.custom_minimum_size.x = 44
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_sliders[field] = {"slider": slider, "value": value}
	slider.value_changed.connect(func(new_value: float):
		var profile := _profile()
		if profile == null or _refreshing:
			return
		profile.set(field, new_value)
		value.text = "%.2f" % new_value
		_apply()
	)


func _color_row(list: VBoxContainer, spec: Array) -> void:
	var field := String(spec[2])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	row.add_child(_row_label(String(spec[1])))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(120, 24)
	picker.edit_alpha = false
	row.add_child(picker)
	_pickers[field] = picker
	picker.color_changed.connect(func(new_color: Color):
		var profile := _profile()
		if profile == null or _refreshing:
			return
		profile.set(field, new_color)
		_apply()
	)


func _toggle_row(list: VBoxContainer, spec: Array) -> void:
	var field := String(spec[2])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	row.add_child(_row_label(String(spec[1])))
	var checkbox := CheckBox.new()
	row.add_child(checkbox)
	_checks[field] = checkbox
	checkbox.toggled.connect(func(pressed: bool):
		var profile := _profile()
		if profile == null or _refreshing:
			return
		profile.set(field, pressed)
		_apply()
	)


func _row_label(text: String) -> Label:
	var label := _small_label(text, 13)
	label.custom_minimum_size.x = 118
	return label


func _small_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _kit.font_bold)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", _kit.text_color())
	return label


func _mini_button(text: String) -> Button:
	var button := _kit.button(text)
	button.custom_minimum_size = Vector2(64, 30)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _copy_to_clipboard() -> void:
	var profile := _profile()
	if profile == null:
		return
	var lines: PackedStringArray = []
	for field in COPY_FIELDS:
		var raw = profile.get(field)
		if raw is Color:
			lines.append('%s = Color(%.4f, %.4f, %.4f, 1)' % [field, raw.r, raw.g, raw.b])
		elif raw is String:
			lines.append('%s = "%s"' % [field, raw])
		elif raw is bool:
			lines.append("%s = %s" % [field, "true" if raw else "false"])
		else:
			lines.append("%s = %s" % [field, "%.4f" % float(raw)])
	DisplayServer.clipboard_set("\n".join(lines))
	_status.text = "Profile values copied to clipboard."


func _save_to_disk() -> void:
	var profile := _profile()
	if profile == null:
		return
	if profile.resource_path.is_empty():
		_status.text = "Profile has no resource path — use Copy instead."
		return
	var result := ResourceSaver.save(profile, profile.resource_path)
	_status.text = (
		"Saved to %s" % profile.resource_path if result == OK
		else "Save failed (error %d)." % result
	)
