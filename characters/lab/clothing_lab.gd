class_name ClothingLab
extends CharacterLab
## Standalone, beginner-friendly fitting room for skinned clothing.
##
## The center always renders the complete modular character.  UI edits explicit
## ClothingFitSettings; "Copy Body Weights + Bind" runs the deterministic
## Blender processor and never creates an independent runtime skeleton.

const DEFAULT_SOURCE := "C:\\Users\\Luka\\Downloads\\jacket.glb"
const FIT_RESOURCE_PATH := (
	"res://assets/characters/parts/fits/top_jacket_cozy_fit.tres"
)
const PART_RESOURCE_PATH := (
	"res://assets/characters/parts/defs/top_jacket_cozy.tres"
)
const CONFIG_PATH := (
	"res://art_source/imported/jacket_default/clothing_lab_fit.json"
)
const OUTPUT_PATH := "res://assets/characters/parts/top_jacket_cozy.glb"
const REPORT_PATH := (
	"res://art_source/imported/jacket_default/clothing_lab_report.json"
)
const REVIEW_BLEND_PATH := (
	"res://art_source/characters/review/clothing_lab_review.blend"
)
const PROCESSOR_PATH := "res://tools/clothing_lab/process_clothing.py"
const BLENDER_PATH := "C:\\Software\\Blender\\blender.exe"
const PLAYER_SHADER := preload(
	"res://assets/materials/player_character.gdshader"
)
const BODY_XRAY_SHADER := preload(
	"res://assets/materials/clothing_lab_body_xray.gdshader"
)
const DEFAULT_SCALE := Vector3(0.528005, 0.597675, 0.504159)
const CUFF_GAP_BEFORE_HAND := 0.006
const CUFF_CENTER_TOLERANCE := 0.018
const CUFF_ENDPOINT_TOLERANCE := 0.012
const CLEARANCE_TOLERANCE := 0.002
const ORBIT_DISTANCE := 2.6
const ORBIT_MOUSE_SENSITIVITY := 0.004
const ORBIT_CONTROLLER_SPEED := 1.6
const ORBIT_PITCH_LIMIT := deg_to_rad(89.5)
const ORBIT_PIVOT := Vector3(0.0, 0.48, 0.0)
const FIT_SCALAR_KEYS := [
	"torso_width",
	"torso_depth",
	"sleeve_lift",
	"sleeve_length",
	"sleeve_room",
	"shoulder_lift",
	"cuff_radius",
	"cuff_forward",
]
const CLOTHING_SLOTS := [
	CharacterSlots.TOP_INNER,
	CharacterSlots.TOP_OUTER,
	CharacterSlots.BOTTOM,
	CharacterSlots.SHOES,
	CharacterSlots.GLOVES,
	CharacterSlots.HEADWEAR,
]
const DEFAULT_JACKET_REGIONS := [
	"chest", "abdomen",
	"upper_chest_l", "upper_chest_r",
	"clavicle_l", "clavicle_r",
	"shoulder_l", "shoulder_r",
	"shoulder_cap_l", "shoulder_cap_r",
	"armpit_l", "armpit_r",
	"upper_arm_l", "upper_arm_r",
	"upper_arm_inner_l", "upper_arm_inner_r",
	"forearm_l", "forearm_r",
]

var _fit: ClothingFitSettings
var _selected_part: CharacterPartDefinition
var _part_paths: Dictionary = {}
var _parts_by_slot: Dictionary = {}
var _body_profiles: Array[CharacterBodyProfile] = []
var _slot_options: Dictionary = {}
var _region_checks: Dictionary = {}
var _vector_controls: Dictionary = {}
var _fit_controls: Dictionary = {}
var _numeric_controls: Dictionary = {}
var _drag_handles: Dictionary = {}
var _revert_buttons: Dictionary = {}
var _field_baselines: Dictionary = {}
var _clothing_list: ItemList
var _body_option: OptionButton
var _source_path: LineEdit
var _status: RichTextLabel
var _file_dialog: FileDialog
var _ui_root: Control
var _preview_hidden_regions: CheckBox
var _body_view_option: OptionButton
var _body_opacity := 0.6
var _preview_mode_option: OptionButton
var _accept_final_check: CheckBox
var _raw_preview: MeshInstance3D
var _raw_source_root: Node
var _raw_source_mesh: ArrayMesh
var _raw_surface_arrays: Array = []
var _raw_deformed_vertices: Array[PackedVector3Array] = []
var _preview_source_path := ""
var _fit_revision := 0
var _preview_revision := -1
var _final_preview_root: Node3D
var _final_output_revision := -1
var _final_output_path := ""
var _final_geometry_changed := false
var _landmarks: Dictionary = {}
var _marker_root: Node3D
var _camera_buttons: HBoxContainer
var _new_clothing_dialog: ConfirmationDialog
var _new_name: LineEdit
var _new_slot: OptionButton
var _new_source: LineEdit
var _orbiting := false
var _last_pointer := Vector2.ZERO
var _orbit_camera: Camera3D
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _undo_button: Button
var _redo_button: Button
var _history_restoring := false
var _history_batch_depth := 0
var _history_batch_snapshot: Dictionary = {}
var _field_drag_spin: SpinBox
var _field_drag_key := ""
var _field_drag_pointer := Vector2.ZERO
var _field_drag_snapshot: Dictionary = {}


func _ready() -> void:
	super._ready()
	_force_rest_pose()
	_prepare_preview_cameras()
	_measure_rest_landmarks()
	if _warning_label != null:
		_warning_label.visible = false
	_load_catalog()
	_build_clothing_ui()
	_select_default_clothing()
	_refresh_ui_from_fit()
	_apply_body_mask()
	_refresh_landmark_markers()
	_validate()
	var input_service := InputDeviceService.shared()
	if input_service != null:
		input_service.focus_first(_ui_root, _body_option)


func _process(delta: float) -> void:
	super._process(delta)
	if _character == null or _orbit_camera == null:
		return
	var orbit_input := Vector2(
		Input.get_axis("look_left", "look_right"),
		Input.get_axis("look_up", "look_down"),
	)
	if orbit_input.length_squared() > 0.0025:
		_orbit_preview(
			orbit_input * delta * ORBIT_CONTROLLER_SPEED
		)


## Preview navigation must run before Control._gui_input. The lab UI uses a
## full-screen root Control, so relying on _unhandled_input makes real pointer
## events disappear behind that layer even when the visible center is empty.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("redo", true):
		_end_field_drag(true)
		_redo()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("undo", true):
		_end_field_drag(true)
		_undo()
		get_viewport().set_input_as_handled()
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if (
			_field_drag_spin != null
			and mouse_button.button_index == MOUSE_BUTTON_LEFT
			and not mouse_button.pressed
		):
			_end_field_drag(true)
			get_viewport().set_input_as_handled()
			return
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_button.pressed and _is_preview_point(mouse_button.position):
				_begin_orbit(mouse_button.position)
			elif not mouse_button.pressed:
				_end_orbit()
			get_viewport().set_input_as_handled()
			return
		if (
			mouse_button.pressed
			and _is_preview_point(mouse_button.position)
			and mouse_button.button_index in [
				MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_DOWN,
			]
		):
			_zoom_preview(
				1
				if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP
				else -1
			)
			get_viewport().set_input_as_handled()
			return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _field_drag_spin != null:
		_drag_numeric_field(mouse_motion)
		get_viewport().set_input_as_handled()
		return
	if mouse_motion != null and _orbiting:
		_orbit_preview(
			-mouse_motion.relative * ORBIT_MOUSE_SENSITIVITY
		)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if _field_drag_spin != null:
			_cancel_field_drag()
			get_viewport().set_input_as_handled()
			return
		_end_orbit()
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_end_field_drag(false)
	_end_orbit()


func _load_catalog() -> void:
	_parts_by_slot.clear()
	_part_paths.clear()
	for slot in CharacterSlots.ALL:
		_parts_by_slot[slot] = []
	for file_name in DirAccess.get_files_at(
		"res://assets/characters/parts/defs"
	):
		if not file_name.ends_with(".tres"):
			continue
		var path := "res://assets/characters/parts/defs/%s" % file_name
		var part := load(path) as CharacterPartDefinition
		if part == null:
			continue
		(_parts_by_slot[part.slot] as Array).append(part)
		_part_paths[part.part_id] = path
	for slot in _parts_by_slot:
		(_parts_by_slot[slot] as Array).sort_custom(
			func(a: CharacterPartDefinition, b: CharacterPartDefinition) -> bool:
				return a.display_name.naturalnocasecmp_to(b.display_name) < 0
		)
	_body_profiles.clear()
	for file_name in DirAccess.get_files_at(
		"res://assets/characters/body_profiles"
	):
		if not file_name.ends_with(".tres"):
			continue
		var profile := load(
			"res://assets/characters/body_profiles/%s" % file_name
		) as CharacterBodyProfile
		if profile != null:
			_body_profiles.append(profile)


func _build_clothing_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ClothingLabUI"
	add_child(canvas)
	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_ui_root)

	var left := _panel(Vector2(12, 12), Vector2(342, -12), false)
	_ui_root.add_child(left)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)
	var left_content := VBoxContainer.new()
	left_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_content.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_content)
	_title(left_content, "CLOTHING LAB")
	_note(
		left_content,
		"Full character preview · source-preserving fit · same live skeleton",
	)
	_body_option = _option_row(left_content, "Body profile")
	for body_profile in _body_profiles:
		_body_option.add_item(body_profile.profile_id)
	_body_option.item_selected.connect(_on_body_selected)
	_separator(left_content, "Appearance")
	for slot in CharacterSlots.ALL:
		var options := _parts_by_slot.get(slot, []) as Array
		if options.is_empty():
			continue
		var option := _option_row(left_content, slot.capitalize())
		option.add_item("None")
		option.set_item_metadata(0, "")
		for part in options:
			var definition := part as CharacterPartDefinition
			option.add_item(definition.display_name)
			option.set_item_metadata(option.item_count - 1, definition.part_id)
		option.item_selected.connect(
			func(index: int, selected_slot := slot) -> void:
				_on_appearance_selected(selected_slot, index)
		)
		_slot_options[slot] = option

	_separator(left_content, "Clothing assets")
	var new_clothing := _button("＋ New clothing…", _open_new_clothing_dialog)
	left_content.add_child(new_clothing)
	_clothing_list = ItemList.new()
	_clothing_list.custom_minimum_size = Vector2(0, 145)
	_clothing_list.select_mode = ItemList.SELECT_SINGLE
	left_content.add_child(_clothing_list)
	for slot in CLOTHING_SLOTS:
		for part in _parts_by_slot.get(slot, []):
			var definition := part as CharacterPartDefinition
			var index := _clothing_list.add_item(definition.display_name)
			_clothing_list.set_item_metadata(index, definition.part_id)
	_clothing_list.item_selected.connect(_on_clothing_selected)

	_source_path = LineEdit.new()
	_source_path.text = DEFAULT_SOURCE
	_source_path.placeholder_text = "C:\\path\\to\\garment.glb"
	_source_path.tooltip_text = "External GLB source copied into art_source."
	_source_path.text_submitted.connect(
		func(path: String) -> void:
			_load_raw_preview(path)
	)
	_source_path.focus_exited.connect(
		func() -> void:
			_load_raw_preview(_source_path.text)
	)
	left_content.add_child(_source_path)
	var import_row := HBoxContainer.new()
	left_content.add_child(import_row)
	var browse := _button("Browse…", _open_file_dialog)
	browse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(browse)
	var import_button := _button("Import source", _import_source)
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(import_button)
	_note(
		left_content,
		"Import preserves the GLB. Fit and weight-copy happen only when you press Bind.",
	)

	var right := _panel(Vector2(-406, 12), Vector2(-12, -12), true)
	_ui_root.add_child(right)
	var right_shell := VBoxContainer.new()
	right_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_shell.add_theme_constant_override("separation", 8)
	right.add_child(right_shell)
	_title(right_shell, "FIT & BIND")
	var locked_pose := Label.new()
	locked_pose.text = "FIT POSE  ·  REST / T-POSE  [LOCKED]"
	locked_pose.tooltip_text = (
		"Fitting is always done against the canonical immutable rest pose."
	)
	locked_pose.add_theme_color_override("font_color", Color("#b8df91"))
	right_shell.add_child(locked_pose)
	var history_row := HBoxContainer.new()
	right_shell.add_child(history_row)
	_undo_button = _button("Undo  Ctrl+Z", _undo)
	_undo_button.tooltip_text = "Undo the last fit, coverage, or auto-fit edit."
	_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_row.add_child(_undo_button)
	_redo_button = _button("Redo  Ctrl+Y", _redo)
	_redo_button.tooltip_text = (
		"Redo the last undone edit. Ctrl+Shift+Z also works."
	)
	_redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_row.add_child(_redo_button)
	_update_history_buttons()
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_shell.add_child(right_scroll)
	var right_content := VBoxContainer.new()
	right_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_content.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_content)

	_separator(right_content, "Preview diagnostics")
	_preview_mode_option = _option_row(right_content, "Preview mode")
	_preview_mode_option.add_item("Raw Fit")
	_preview_mode_option.add_item("Final Output")
	_preview_mode_option.set_item_disabled(1, true)
	_preview_mode_option.item_selected.connect(
		_on_preview_mode_selected
	)
	_preview_hidden_regions = CheckBox.new()
	_preview_hidden_regions.text = "Live Preview Hidden Regions"
	_preview_hidden_regions.tooltip_text = (
		"Shows coverage edits on the body immediately. Turn off temporarily "
		+ "to inspect the complete body under the garment."
	)
	_preview_hidden_regions.button_pressed = true
	_preview_hidden_regions.toggled.connect(
		func(_enabled: bool) -> void:
			_apply_body_mask()
			_validate()
	)
	right_content.add_child(_preview_hidden_regions)
	_body_view_option = _option_row(right_content, "Body view")
	for view_name in ["Solid", "X-ray 60%", "Wireframe"]:
		_body_view_option.add_item(view_name)
	_body_view_option.item_selected.connect(_on_body_view_selected)
	var opacity_row := HBoxContainer.new()
	right_content.add_child(opacity_row)
	var opacity_label := Label.new()
	opacity_label.text = "X-ray opacity"
	opacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_row.add_child(opacity_label)
	var opacity_slider := HSlider.new()
	opacity_slider.min_value = 0.1
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.05
	opacity_slider.value = _body_opacity
	opacity_slider.custom_minimum_size.x = 150
	opacity_slider.value_changed.connect(
		func(value: float) -> void:
			_body_opacity = value
			if (
				_body_view_option != null
				and _body_view_option.selected == 1
			):
				_apply_body_mask()
	)
	opacity_row.add_child(opacity_slider)
	var marker_toggle := CheckBox.new()
	marker_toggle.text = "Shoulder / forearm / wrist markers"
	marker_toggle.button_pressed = true
	marker_toggle.toggled.connect(
		func(visible: bool) -> void:
			if _marker_root != null:
				_marker_root.visible = visible
	)
	right_content.add_child(marker_toggle)
	_note(
		right_content,
		"Orange shoulder · cyan forearm · green wrist · pink hand",
	)

	_separator(right_content, "Whole garment transform")
	_add_vector_controls(
		right_content, "Position (m)", "position", -0.25, 0.25, 0.001
	)
	_add_vector_controls(
		right_content, "Rotation (°)", "rotation", -180.0, 180.0, 0.25
	)
	_add_vector_controls(
		right_content, "Scale", "scale", 0.05, 2.0, 0.005
	)
	var symmetry_label := Label.new()
	symmetry_label.text = "Sleeve and cuff controls are always bilateral."
	symmetry_label.modulate = Color(0.72, 0.82, 0.70)
	right_content.add_child(symmetry_label)
	var reset_button := _button("Reset transform + fit", _reset_fit)
	right_content.add_child(reset_button)

	_separator(right_content, "Simple fit controls")
	_add_fit_control(right_content, "Torso width", "torso_width", 0.85, 1.25, 0.005)
	_add_fit_control(right_content, "Torso depth", "torso_depth", 0.85, 1.25, 0.005)
	_add_fit_control(right_content, "Sleeve lift (m)", "sleeve_lift", -0.08, 0.12, 0.001)
	_add_fit_control(right_content, "Sleeve length", "sleeve_length", 0.75, 1.20, 0.005)
	_add_fit_control(right_content, "Sleeve room", "sleeve_room", 0.90, 1.80, 0.005)
	_add_fit_control(right_content, "Shoulder lift (m)", "shoulder_lift", -0.04, 0.10, 0.001)
	_add_fit_control(right_content, "Cuff opening", "cuff_radius", 0.85, 1.30, 0.005)
	_add_fit_control(right_content, "Cuff forward (m)", "cuff_forward", -0.04, 0.04, 0.001)
	var presets := HBoxContainer.new()
	right_content.add_child(presets)
	for preset_name in ["Snug", "Relaxed", "Long sleeves"]:
		var preset_button := _button(
			preset_name,
			_apply_fit_preset.bind(preset_name),
		)
		preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(preset_button)
	var alignment_row := HBoxContainer.new()
	right_content.add_child(alignment_row)
	var center_cuffs := _button("Auto Center Cuffs", _auto_center_cuffs)
	center_cuffs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment_row.add_child(center_cuffs)
	var align_tpose := _button("Align To T-pose", _align_to_tpose)
	align_tpose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment_row.add_child(align_tpose)
	var auto_clear := _button("Auto Clear Body", _auto_clear_body)
	right_content.add_child(auto_clear)

	_separator(right_content, "Body regions hidden by clothing")
	_note(
		right_content,
		"Hands stay visible by default. Select a hand only when the garment truly covers it.",
	)
	var region_actions := HBoxContainer.new()
	right_content.add_child(region_actions)
	for action_name in ["Recommended", "Both arms", "None"]:
		var region_button := _button(
			action_name, _apply_region_preset.bind(action_name)
		)
		region_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		region_actions.add_child(region_button)
	_add_region_group(
		right_content,
		"Torso",
		["neck", "chest", "abdomen", "hips", "upper_chest_l", "upper_chest_r"],
	)
	_add_region_group(
		right_content,
		"Left arm",
		[
			"clavicle_l", "shoulder_l", "shoulder_cap_l", "armpit_l",
			"upper_arm_l", "upper_arm_inner_l", "forearm_l", "hand_l",
		],
	)
	_add_region_group(
		right_content,
		"Right arm",
		[
			"clavicle_r", "shoulder_r", "shoulder_cap_r", "armpit_r",
			"upper_arm_r", "upper_arm_inner_r", "forearm_r", "hand_r",
		],
	)
	_add_region_group(
		right_content,
		"Lower body",
		[
			"thigh_l", "knee_l", "shin_l", "foot_l",
			"thigh_r", "knee_r", "shin_r", "foot_r",
		],
	)

	var sticky := VBoxContainer.new()
	sticky.add_theme_constant_override("separation", 6)
	right_shell.add_child(sticky)
	var bind_button := _button(
		"Copy Body Weights + Bind Existing Skeleton",
		_bind_and_export,
	)
	bind_button.tooltip_text = (
		"Runs Blender in REST/T-pose, nearest-face copies body weights, "
		+ "and exports without animations or a second runtime skeleton."
	)
	sticky.add_child(bind_button)
	var open_blend := _button(
		"Open Final Review in Blender",
		_open_final_review_in_blender,
	)
	sticky.add_child(open_blend)
	_accept_final_check = CheckBox.new()
	_accept_final_check.text = "I reviewed and accept this exact Final Output"
	_accept_final_check.disabled = true
	_accept_final_check.toggled.connect(
		func(_accepted: bool) -> void:
			_validate()
	)
	sticky.add_child(_accept_final_check)
	var save_button := _button("Save Draft Fit", _save_resources)
	sticky.add_child(save_button)
	var publish_button := _button(
		"Accept Final Output + Save for In-game",
		_publish_final_output,
	)
	sticky.add_child(publish_button)
	_status = RichTextLabel.new()
	_status.custom_minimum_size = Vector2(0, 88)
	_status.bbcode_enabled = true
	_status.scroll_active = true
	sticky.add_child(_status)

	var footer := Label.new()
	footer.text = (
		"MMB: orbit  ·  Wheel: zoom  ·  Right stick: orbit  ·  "
		+ "Esc/B: close  ·  D-pad/Tab + Accept: UI"
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.position = Vector2(-350, -42)
	footer.size = Vector2(700, 30)
	_ui_root.add_child(footer)
	_build_camera_toolbar()

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.add_filter("*.glb", "glTF Binary")
	_file_dialog.file_selected.connect(
		func(path: String) -> void:
			_source_path.text = path
			_load_raw_preview(path)
	)
	_ui_root.add_child(_file_dialog)
	_build_new_clothing_dialog()


func _panel(top_left: Vector2, bottom_right: Vector2, anchor_right: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(
		Control.PRESET_RIGHT_WIDE if anchor_right else Control.PRESET_LEFT_WIDE
	)
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.062, 0.95)
	style.border_color = Color(0.42, 0.55, 0.40, 0.9)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _title(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("#d7ed9b"))
	parent.add_child(label)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.76, 0.80, 0.74)
	parent.add_child(label)


func _separator(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#e9bb75"))
	parent.add_child(label)


func _option_row(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 112
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button


func _add_vector_controls(
	parent: Control,
	label_text: String,
	key: String,
	minimum: float,
	maximum: float,
	step: float,
) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var controls: Array[SpinBox] = []
	for axis_index in 3:
		var axis_name: String = ["X", "Y", "Z"][axis_index]
		var field_key := "%s.%s" % [key, axis_name.to_lower()]
		var row := HBoxContainer.new()
		parent.add_child(row)
		var axis_label := Label.new()
		axis_label.text = axis_name
		axis_label.custom_minimum_size.x = 18
		row.add_child(axis_label)
		var axis := SpinBox.new()
		axis.min_value = minimum
		axis.max_value = maximum
		axis.step = step
		axis.allow_greater = false
		axis.allow_lesser = false
		axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis.value_changed.connect(
			func(_value: float, control_key := key) -> void:
				_on_vector_changed(control_key)
		)
		var handle := _numeric_drag_handle(axis, field_key)
		row.add_child(handle)
		row.add_child(axis)
		var revert := _numeric_revert_button(field_key)
		row.add_child(revert)
		controls.append(axis)
		_numeric_controls[field_key] = axis
	_vector_controls[key] = controls


func _add_fit_control(
	parent: Control,
	label_text: String,
	key: String,
	minimum: float,
	maximum: float,
	step: float,
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size.x = 108
	spin.value_changed.connect(
		func(value: float, property_name := key) -> void:
			if _fit != null:
				_record_history_before_change()
				_fit.set(property_name, value)
				_preview_fit()
				_update_revert_buttons()
	)
	var handle := _numeric_drag_handle(spin, key)
	row.add_child(handle)
	row.add_child(spin)
	var revert := _numeric_revert_button(key)
	row.add_child(revert)
	_fit_controls[key] = spin
	_numeric_controls[key] = spin


func _numeric_drag_handle(spin: SpinBox, field_key: String) -> Button:
	var handle := Button.new()
	handle.text = "↔"
	handle.custom_minimum_size = Vector2(30, 0)
	handle.focus_mode = Control.FOCUS_ALL
	handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	handle.tooltip_text = (
		"Drag horizontally to change this value. "
		+ "Shift = fine, Ctrl = coarse."
	)
	handle.gui_input.connect(
		_on_numeric_handle_input.bind(spin, field_key, handle)
	)
	_drag_handles[field_key] = handle
	return handle


func _numeric_revert_button(field_key: String) -> Button:
	var revert := Button.new()
	revert.text = "↶"
	revert.custom_minimum_size = Vector2(30, 0)
	revert.focus_mode = Control.FOCUS_ALL
	revert.tooltip_text = "Revert this field to its last loaded/saved value."
	revert.pressed.connect(_revert_numeric_field.bind(field_key))
	revert.disabled = true
	_revert_buttons[field_key] = revert
	return revert


func _on_numeric_handle_input(
	event: InputEvent,
	spin: SpinBox,
	field_key: String,
	handle: Button,
) -> void:
	var mouse_button := event as InputEventMouseButton
	if (
		mouse_button == null
		or mouse_button.button_index != MOUSE_BUTTON_LEFT
		or not mouse_button.pressed
	):
		return
	_begin_field_drag(spin, field_key, handle.get_global_mouse_position())
	handle.accept_event()


func _begin_field_drag(
	spin: SpinBox,
	field_key: String,
	pointer_position: Vector2,
) -> void:
	if _field_drag_spin != null:
		_end_field_drag(true)
	_field_drag_spin = spin
	_field_drag_key = field_key
	_field_drag_pointer = pointer_position
	_field_drag_snapshot = _capture_fit_snapshot()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _drag_numeric_field(motion: InputEventMouseMotion) -> void:
	if _field_drag_spin == null:
		return
	var speed := 1.0
	if motion.shift_pressed:
		speed = 0.1
	elif motion.ctrl_pressed or motion.meta_pressed:
		speed = 10.0
	_field_drag_spin.value = clampf(
		_field_drag_spin.value
		+ motion.relative.x * _field_drag_spin.step * speed,
		_field_drag_spin.min_value,
		_field_drag_spin.max_value,
	)


func _end_field_drag(commit: bool) -> void:
	if _field_drag_spin == null:
		return
	var before := _field_drag_snapshot.duplicate(true)
	_field_drag_spin = null
	_field_drag_key = ""
	_field_drag_snapshot.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_field_drag_pointer)
	if (
		commit
		and not before.is_empty()
		and before != _capture_fit_snapshot()
	):
		_push_undo_snapshot(before)
	_update_revert_buttons()


func _cancel_field_drag() -> void:
	if _field_drag_spin == null:
		return
	var before := _field_drag_snapshot.duplicate(true)
	_end_field_drag(false)
	if not before.is_empty():
		_apply_fit_snapshot(before)


func _capture_fit_snapshot() -> Dictionary:
	if _fit == null:
		return {}
	return {
		"position": _fit.position,
		"rotation_degrees": _fit.rotation_degrees,
		"scale": _fit.scale,
		"torso_width": _fit.torso_width,
		"torso_depth": _fit.torso_depth,
		"sleeve_lift": _fit.sleeve_lift,
		"sleeve_length": _fit.sleeve_length,
		"sleeve_room": _fit.sleeve_room,
		"shoulder_lift": _fit.shoulder_lift,
		"cuff_radius": _fit.cuff_radius,
		"cuff_forward": _fit.cuff_forward,
		"hidden_regions": _fit.hidden_regions.duplicate(),
	}


func _apply_fit_snapshot(snapshot: Dictionary) -> void:
	if _fit == null or snapshot.is_empty():
		return
	_history_restoring = true
	_fit.position = snapshot["position"]
	_fit.rotation_degrees = snapshot["rotation_degrees"]
	_fit.scale = snapshot["scale"]
	for property_name in FIT_SCALAR_KEYS:
		_fit.set(property_name, snapshot[property_name])
	_fit.hidden_regions = snapshot["hidden_regions"].duplicate()
	_history_restoring = false
	_refresh_ui_from_fit()
	_apply_body_mask()
	_preview_fit()
	_update_revert_buttons()
	_update_history_buttons()


func _record_history_before_change() -> void:
	if (
		_fit == null
		or _history_restoring
		or _history_batch_depth > 0
		or _field_drag_spin != null
	):
		return
	_push_undo_snapshot(_capture_fit_snapshot())


func _push_undo_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	if _undo_stack.is_empty() or _undo_stack.back() != snapshot:
		_undo_stack.append(snapshot.duplicate(true))
		if _undo_stack.size() > 100:
			_undo_stack.pop_front()
	_redo_stack.clear()
	_update_history_buttons()


func _begin_history_batch() -> void:
	if _history_batch_depth == 0:
		_history_batch_snapshot = _capture_fit_snapshot()
	_history_batch_depth += 1


func _end_history_batch() -> void:
	if _history_batch_depth <= 0:
		return
	_history_batch_depth -= 1
	if _history_batch_depth > 0:
		return
	var before := _history_batch_snapshot.duplicate(true)
	_history_batch_snapshot.clear()
	if not before.is_empty() and before != _capture_fit_snapshot():
		_push_undo_snapshot(before)


func _undo() -> void:
	if _undo_stack.is_empty() or _fit == null:
		return
	var current := _capture_fit_snapshot()
	var previous: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(current)
	_apply_fit_snapshot(previous)
	_update_history_buttons()


func _redo() -> void:
	if _redo_stack.is_empty() or _fit == null:
		return
	var current := _capture_fit_snapshot()
	var next: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(current)
	_apply_fit_snapshot(next)
	_update_history_buttons()


func _reset_history() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_history_batch_depth = 0
	_history_batch_snapshot.clear()
	_capture_field_baselines()
	_update_history_buttons()


func _update_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = _undo_stack.is_empty()
	if _redo_button != null:
		_redo_button.disabled = _redo_stack.is_empty()


func _capture_field_baselines() -> void:
	_field_baselines.clear()
	for field_key in _numeric_controls:
		_field_baselines[field_key] = _numeric_field_value(field_key)
	_update_revert_buttons()


func _numeric_field_value(field_key: String) -> float:
	if _fit == null:
		return 0.0
	if field_key.find(".") < 0:
		return float(_fit.get(field_key))
	var parts := field_key.split(".", false, 1)
	var vector := Vector3.ZERO
	match parts[0]:
		"position":
			vector = _fit.position
		"rotation":
			vector = _fit.rotation_degrees
		"scale":
			vector = _fit.scale
	match parts[1]:
		"x":
			return vector.x
		"y":
			return vector.y
		"z":
			return vector.z
	return 0.0


func _revert_numeric_field(field_key: String) -> void:
	if (
		not _field_baselines.has(field_key)
		or not _numeric_controls.has(field_key)
	):
		return
	var spin := _numeric_controls[field_key] as SpinBox
	spin.value = float(_field_baselines[field_key])


func _update_revert_buttons() -> void:
	for field_key in _revert_buttons:
		var revert := _revert_buttons[field_key] as Button
		revert.disabled = (
			not _field_baselines.has(field_key)
			or is_equal_approx(
				_numeric_field_value(field_key),
				float(_field_baselines[field_key]),
			)
		)


func _add_region_group(
	parent: Control,
	title: String,
	regions: Array,
) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	parent.add_child(group)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", Color("#d7ed9b"))
	group.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	group.add_child(grid)
	for region_variant in regions:
		var region := String(region_variant)
		var check := CheckBox.new()
		check.text = region.replace("_", " ").capitalize()
		check.tooltip_text = region
		check.toggled.connect(
			func(_enabled: bool, selected_region := region) -> void:
				_on_region_toggled(selected_region)
		)
		_region_checks[region] = check
		grid.add_child(check)


func _apply_region_preset(preset_name: String) -> void:
	if _fit == null:
		return
	_begin_history_batch()
	_fit.hidden_regions.clear()
	match preset_name:
		"Recommended":
			for region in DEFAULT_JACKET_REGIONS:
				_fit.hidden_regions.append(region)
		"Both arms":
			for region in PlayerArmorRegions.names():
				if (
					region.ends_with("_l")
					or region.ends_with("_r")
				) and (
					"arm" in region
					or "shoulder" in region
					or "clavicle" in region
					or "armpit" in region
					or "forearm" in region
				):
					_fit.hidden_regions.append(region)
	_refresh_ui_from_fit()
	_enable_live_hide_preview()
	_apply_body_mask()
	_validate()
	_end_history_batch()


func _prepare_preview_cameras() -> void:
	if not _cameras.has("side"):
		_add_camera(
			"side",
			Vector3(2.6, 0.55, 0.0),
			Vector3(0.0, 0.48, 0.0),
			1.18,
		)
	for camera_name in ["front", "three_quarter", "side"]:
		var camera := _cameras.get(camera_name) as Camera3D
		if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			camera.size = 1.18 if camera_name != "three_quarter" else 1.26
	_orbit_camera = Camera3D.new()
	_orbit_camera.name = "Camera_orbit"
	_orbit_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_orbit_camera.size = 1.18
	_orbit_camera.near = 0.02
	add_child(_orbit_camera)
	_cameras["orbit"] = _orbit_camera
	_set_camera_view("+Z")


func _build_camera_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-370, 12)
	panel.size = Vector2(740, 42)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.062, 0.90)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	_ui_root.add_child(panel)
	_camera_buttons = HBoxContainer.new()
	_camera_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_camera_buttons)
	for view_name in ["+X", "-X", "+Y", "-Y", "+Z", "-Z", "3Q"]:
		var button := _button(
			view_name, _set_camera_view.bind(view_name)
		)
		button.custom_minimum_size.x = 46 if view_name != "3Q" else 52
		button.tooltip_text = _axis_view_tooltip(view_name)
		_camera_buttons.add_child(button)
	for label in ["−", "+"]:
		var zoom_button := _button(
			label, _zoom_preview.bind(-1 if label == "−" else 1)
		)
		zoom_button.custom_minimum_size.x = 42
		_camera_buttons.add_child(zoom_button)
	var full := _button("Full Body", _focus_character)
	_camera_buttons.add_child(full)
	var garment := _button("Garment", _focus_garment)
	_camera_buttons.add_child(garment)


func _set_camera_view(view_name: String) -> void:
	match view_name:
		"+X", "Side":
			_snap_axis_view(Vector3.RIGHT)
		"-X":
			_snap_axis_view(Vector3.LEFT)
		"+Y":
			_snap_axis_view(Vector3.UP)
		"-Y":
			_snap_axis_view(Vector3.DOWN)
		"+Z", "Front":
			_snap_axis_view(Vector3.BACK)
		"-Z":
			_snap_axis_view(Vector3.FORWARD)
		"3Q":
			_orbit_yaw = deg_to_rad(40.6)
			_orbit_pitch = deg_to_rad(15.0)
			_update_orbit_camera()


func _axis_view_tooltip(view_name: String) -> String:
	return {
		"+X": "Right view (look toward -X)",
		"-X": "Left view (look toward +X)",
		"+Y": "Top view (look toward -Y)",
		"-Y": "Bottom view (look toward +Y)",
		"+Z": "Front view (look toward -Z)",
		"-Z": "Back view (look toward +Z)",
		"3Q": "Reset to three-quarter view",
	}.get(view_name, view_name)


func _snap_axis_view(direction: Vector3) -> void:
	var normalized := direction.normalized()
	_orbit_yaw = atan2(normalized.x, normalized.z)
	_orbit_pitch = asin(clampf(normalized.y, -1.0, 1.0))
	_update_orbit_camera()


func _orbit_preview(delta_radians: Vector2) -> void:
	_orbit_yaw = wrapf(_orbit_yaw + delta_radians.x, -PI, PI)
	_orbit_pitch = clampf(
		_orbit_pitch - delta_radians.y,
		-ORBIT_PITCH_LIMIT,
		ORBIT_PITCH_LIMIT,
	)
	_update_orbit_camera()


func _update_orbit_camera() -> void:
	if _orbit_camera == null:
		return
	var cos_pitch := cos(_orbit_pitch)
	var direction := Vector3(
		sin(_orbit_yaw) * cos_pitch,
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos_pitch,
	).normalized()
	var camera_position := ORBIT_PIVOT + direction * ORBIT_DISTANCE
	var camera_up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.999:
		camera_up = (
			Vector3.FORWARD
			if direction.y > 0.0
			else Vector3.BACK
		)
	_orbit_camera.look_at_from_position(
		camera_position,
		ORBIT_PIVOT,
		camera_up,
	)
	_activate_camera("orbit")


func _begin_orbit(pointer_position: Vector2) -> void:
	_orbiting = true
	_last_pointer = pointer_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_orbit() -> void:
	if not _orbiting:
		return
	_orbiting = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_last_pointer)


func _active_preview_camera() -> Camera3D:
	for camera_name in _cameras:
		var camera := _cameras[camera_name] as Camera3D
		if camera != null and camera.current:
			return camera
	return _cameras.get("front") as Camera3D


func _zoom_preview(direction: int) -> void:
	var camera := _active_preview_camera()
	if camera == null:
		return
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = clampf(camera.size * (0.88 if direction > 0 else 1.12), 0.42, 2.0)


func _focus_character() -> void:
	var camera := _active_preview_camera()
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = (
			1.18 if camera.name != "Camera_three_quarter" else 1.26
		)


func _focus_garment() -> void:
	var camera := _active_preview_camera()
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = 0.68


func _build_new_clothing_dialog() -> void:
	_new_clothing_dialog = ConfirmationDialog.new()
	_new_clothing_dialog.title = "New Clothing"
	_new_clothing_dialog.size = Vector2i(520, 330)
	_new_clothing_dialog.confirmed.connect(_create_new_clothing)
	_ui_root.add_child(_new_clothing_dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_new_clothing_dialog.add_child(content)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "Display name, e.g. Forest Cardigan"
	content.add_child(_new_name)
	_new_slot = _option_row(content, "Slot")
	for slot in CLOTHING_SLOTS:
		_new_slot.add_item(slot.capitalize())
		_new_slot.set_item_metadata(_new_slot.item_count - 1, slot)
	_new_source = LineEdit.new()
	_new_source.placeholder_text = "C:\\path\\to\\garment.glb"
	_new_source.text = DEFAULT_SOURCE
	content.add_child(_new_source)
	_note(
		content,
		"Creates a persistent CharacterPartDefinition and fit resource. "
		+ "Bind once to create its in-game scene.",
	)


func _open_new_clothing_dialog() -> void:
	_new_clothing_dialog.popup_centered()
	_new_name.grab_focus()


func _create_new_clothing() -> void:
	var display_name := _new_name.text.strip_edges()
	var source := _new_source.text.strip_edges()
	if display_name.is_empty() or not FileAccess.file_exists(source):
		_set_status("error", "New clothing needs a name and valid source GLB.")
		return
	var part_id := display_name.to_snake_case()
	if part_id.is_empty():
		_set_status("error", "Could not derive a resource id from that name.")
		return
	var slot := String(_new_slot.get_item_metadata(_new_slot.selected))
	var source_resource := (
		"res://art_source/imported/clothing_lab/%s_source.glb" % part_id
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(source_resource.get_base_dir())
	)
	var copy_error := DirAccess.copy_absolute(
		source, ProjectSettings.globalize_path(source_resource)
	)
	if copy_error != OK:
		_set_status("error", "Could not copy source GLB (error %d)." % copy_error)
		return
	var fit := ClothingFitSettings.new()
	fit.source_file = source_resource
	fit.body_profile_id = (
		preset.body_profile.profile_id
		if preset != null and preset.body_profile != null
		else "body_male"
	)
	for region in DEFAULT_JACKET_REGIONS:
		fit.hidden_regions.append(region)
	var part := CharacterPartDefinition.new()
	part.part_id = part_id
	part.display_name = display_name
	part.slot = slot
	part.attachment_type = CharacterPartDefinition.ATTACHMENT_SKINNED
	part.compatible_body_profiles = PackedStringArray([fit.body_profile_id])
	part.clothing_fit = fit
	part.hidden_regions = fit.hidden_regions.duplicate()
	var fit_path := (
		"res://assets/characters/parts/fits/%s_fit.tres" % part_id
	)
	var part_path := (
		"res://assets/characters/parts/defs/%s.tres" % part_id
	)
	ResourceSaver.save(fit, fit_path)
	ResourceSaver.save(part, part_path)
	_part_paths[part_id] = part_path
	if not _parts_by_slot.has(slot):
		_parts_by_slot[slot] = []
	(_parts_by_slot[slot] as Array).append(part)
	var item := _clothing_list.add_item(display_name)
	_clothing_list.set_item_metadata(item, part_id)
	_clothing_list.select(item)
	_select_clothing_part(part)
	_refresh_ui_from_fit()


func _select_default_clothing() -> void:
	var part := load(PART_RESOURCE_PATH) as CharacterPartDefinition
	if part == null:
		return
	_select_clothing_part(part)
	for index in _clothing_list.item_count:
		if String(_clothing_list.get_item_metadata(index)) == part.part_id:
			_clothing_list.select(index)
			break


func _select_clothing_part(part: CharacterPartDefinition) -> void:
	_selected_part = part
	_fit = part.clothing_fit
	if _fit == null:
		_fit = ClothingFitSettings.new()
		_fit.source_file = (
			"res://art_source/imported/jacket_default/jacket_source.glb"
		)
		for region in DEFAULT_JACKET_REGIONS:
			_fit.hidden_regions.append(region)
		part.clothing_fit = _fit
	_replace_part_in_preset(part.slot, part)
	_rebuild()
	_force_rest_pose()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	_load_raw_preview(_fit.source_file)
	_reset_history()


func _replace_part_in_preset(
	slot: String,
	replacement: CharacterPartDefinition,
) -> void:
	if preset == null:
		return
	var next_parts: Array[CharacterPartDefinition] = []
	for part in preset.parts:
		if part != null and part.slot != slot:
			next_parts.append(part)
	if replacement != null:
		next_parts.append(replacement)
	preset.parts = next_parts


func _on_clothing_selected(index: int) -> void:
	var part_id := String(_clothing_list.get_item_metadata(index))
	var path := String(_part_paths.get(part_id, ""))
	var part := load(path) as CharacterPartDefinition
	if part == null:
		return
	_select_clothing_part(part)
	_refresh_ui_from_fit()
	_validate()


func _on_body_selected(index: int) -> void:
	if index < 0 or index >= _body_profiles.size() or preset == null:
		return
	preset.body_profile = _body_profiles[index]
	if _fit != null:
		_fit.body_profile_id = preset.body_profile.profile_id
	_rebuild()
	_force_rest_pose()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	_load_raw_preview(_fit.source_file)
	_validate()


func _on_appearance_selected(slot: String, index: int) -> void:
	var option := _slot_options.get(slot) as OptionButton
	if option == null:
		return
	var part_id := String(option.get_item_metadata(index))
	if part_id.is_empty():
		_replace_part_in_preset(slot, null)
	else:
		var path := String(_part_paths.get(part_id, ""))
		_replace_part_in_preset(slot, load(path) as CharacterPartDefinition)
	_rebuild()
	_force_rest_pose()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	if _fit != null:
		_load_raw_preview(_fit.source_file)


func _refresh_ui_from_fit() -> void:
	if _fit == null:
		return
	_source_path.text = _fit.source_file
	_fit.symmetric = true
	_set_vector_controls("position", _fit.position)
	_set_vector_controls("rotation", _fit.rotation_degrees)
	_set_vector_controls("scale", _fit.scale)
	for key in _fit_controls:
		(_fit_controls[key] as SpinBox).set_value_no_signal(
			float(_fit.get(key))
		)
	for region in _region_checks:
		(_region_checks[region] as CheckBox).set_pressed_no_signal(
			_fit.hidden_regions.has(region)
		)
	if preset != null and preset.body_profile != null:
		for index in _body_profiles.size():
			if (
				_body_profiles[index].profile_id
				== preset.body_profile.profile_id
			):
				_body_option.select(index)
				break
	for slot in _slot_options:
		var option := _slot_options[slot] as OptionButton
		var selected := preset.part_in_slot(slot) if preset != null else null
		for index in option.item_count:
			if (
				selected != null
				and String(option.get_item_metadata(index)) == selected.part_id
			):
				option.select(index)
				break
	_update_revert_buttons()


func _set_vector_controls(key: String, value: Vector3) -> void:
	var controls := _vector_controls.get(key, []) as Array
	if controls.size() != 3:
		return
	(controls[0] as SpinBox).set_value_no_signal(value.x)
	(controls[1] as SpinBox).set_value_no_signal(value.y)
	(controls[2] as SpinBox).set_value_no_signal(value.z)


func _on_vector_changed(key: String) -> void:
	if _fit == null:
		return
	_record_history_before_change()
	var controls := _vector_controls.get(key, []) as Array
	var value := Vector3(
		(controls[0] as SpinBox).value,
		(controls[1] as SpinBox).value,
		(controls[2] as SpinBox).value,
	)
	match key:
		"position":
			_fit.position = value
		"rotation":
			_fit.rotation_degrees = value
		"scale":
			_fit.scale = value
	_preview_fit()
	_update_revert_buttons()


func _preview_fit() -> void:
	if _fit == null or _raw_preview == null:
		_validate()
		return
	_fit.symmetric = true
	_fit_revision += 1
	_invalidate_final_output()
	_update_raw_preview_mesh()
	_validate()


func _reset_fit() -> void:
	if _fit == null:
		return
	_begin_history_batch()
	_fit.reset_fit()
	_refresh_ui_from_fit()
	_preview_fit()
	_end_history_batch()


func _apply_fit_preset(preset_name: String) -> void:
	if _fit == null:
		return
	_begin_history_batch()
	match preset_name:
		"Snug":
			_fit.torso_width = 0.96
			_fit.torso_depth = 0.96
			_fit.cuff_radius = 1.02
		"Relaxed":
			_fit.torso_width = 1.07
			_fit.torso_depth = 1.08
			_fit.cuff_radius = 1.12
		"Long sleeves":
			_fit.sleeve_length = 1.08
			_fit.cuff_radius = 1.08
	_refresh_ui_from_fit()
	_preview_fit()
	_end_history_batch()


func _on_region_toggled(region: String) -> void:
	if _fit == null:
		return
	_record_history_before_change()
	var selected := (_region_checks[region] as CheckBox).button_pressed
	if selected and not _fit.hidden_regions.has(region):
		_fit.hidden_regions.append(region)
	elif not selected:
		_fit.hidden_regions.remove_at(_fit.hidden_regions.find(region))
	_fit_revision += 1
	_invalidate_final_output()
	_enable_live_hide_preview()
	_apply_body_mask()
	_validate()


func _enable_live_hide_preview() -> void:
	if (
		_preview_hidden_regions != null
		and not _preview_hidden_regions.button_pressed
	):
		_preview_hidden_regions.set_pressed_no_signal(true)


func _apply_body_mask() -> void:
	if _character == null or _fit == null:
		return
	var regions: Array[String] = []
	if (
		_preview_hidden_regions != null
		and _preview_hidden_regions.button_pressed
	):
		for region in _fit.hidden_regions:
			regions.append(region)
	var mask := PlayerArmorRegions.mask_for(regions)
	var body_mesh := _character.find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	if body_mesh != null:
		_ensure_body_mask_material(body_mesh)
		body_mesh.set_instance_shader_parameter("hide_mask", mask)


func _ensure_body_mask_material(body_mesh: MeshInstance3D) -> void:
	if body_mesh.mesh == null:
		return
	var use_xray := (
		_body_view_option != null
		and _body_view_option.selected == 1
	)
	var desired_shader := BODY_XRAY_SHADER if use_xray else PLAYER_SHADER
	for surface_index in body_mesh.mesh.get_surface_count():
		var current := body_mesh.get_surface_override_material(surface_index)
		if (
			current is ShaderMaterial
			and (current as ShaderMaterial).shader == desired_shader
		):
			continue
		var source := body_mesh.mesh.surface_get_material(surface_index)
		if not source is BaseMaterial3D:
			continue
		var base := source as BaseMaterial3D
		var styled := ShaderMaterial.new()
		styled.shader = desired_shader
		styled.set_shader_parameter("albedo_texture", base.albedo_texture)
		styled.set_shader_parameter("base_albedo", base.albedo_color)
		if not use_xray:
			styled.set_shader_parameter("palette_tint", Color.WHITE)
			styled.set_shader_parameter("saturation", 1.0)
			styled.set_shader_parameter("value_scale", 1.0)
			styled.set_shader_parameter("roughness_value", 0.9)
			styled.set_shader_parameter("specular_value", 0.14)
		else:
			styled.set_shader_parameter("body_opacity", _body_opacity)
		body_mesh.set_surface_override_material(surface_index, styled)


func _on_body_view_selected(index: int) -> void:
	get_viewport().debug_draw = (
		Viewport.DEBUG_DRAW_WIREFRAME
		if index == 2
		else Viewport.DEBUG_DRAW_DISABLED
	)
	var body_mesh := (
		_character.find_child("PlayerMaleBody", true, false) as MeshInstance3D
		if _character != null
		else null
	)
	if body_mesh != null:
		for surface_index in body_mesh.mesh.get_surface_count():
			body_mesh.set_surface_override_material(surface_index, null)
	_apply_body_mask()


func _force_rest_pose() -> void:
	if _character == null:
		return
	var animation_player := _character.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	if animation_player != null:
		animation_player.stop()
	var skeleton := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if skeleton == null:
		return
	skeleton.reset_bone_poses()


func _measure_rest_landmarks() -> void:
	_landmarks.clear()
	if _character == null:
		return
	var skeleton := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if skeleton == null:
		return
	var skeleton_to_character := (
		_character.global_transform.affine_inverse()
		* skeleton.global_transform
	)
	for side_name in ["Left", "Right"]:
		var points := {}
		for marker_name in ["Shoulder", "ForeArm", "Wrist", "Hand"]:
			var bone_name := ""
			match marker_name:
				"Shoulder":
					bone_name = "mixamorig%sArm" % side_name
				"ForeArm":
					bone_name = "mixamorig%sForeArm" % side_name
				"Wrist":
					bone_name = "mixamorig%sHand" % side_name
				"Hand":
					bone_name = "mixamorig%sHandIndex1" % side_name
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index < 0:
				continue
			points[marker_name.to_lower()] = (
				skeleton_to_character
				* skeleton.get_bone_global_rest(bone_index).origin
			)
		_landmarks[side_name.to_lower()] = points


func _refresh_landmark_markers() -> void:
	if _marker_root != null and is_instance_valid(_marker_root):
		_marker_root.queue_free()
	if _character == null or _landmarks.is_empty():
		return
	_marker_root = Node3D.new()
	_marker_root.name = "ClothingLandmarkMarkers"
	_character.add_child(_marker_root)
	var colors := {
		"shoulder": Color("#ffbc62"),
		"forearm": Color("#75d5d0"),
		"wrist": Color("#d7ed9b"),
		"hand": Color("#ee88a8"),
	}
	for side in _landmarks:
		var points := _landmarks[side] as Dictionary
		for marker_name in points:
			var marker := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.013
			sphere.height = 0.026
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = colors.get(marker_name, Color.WHITE)
			material.emission_enabled = true
			material.emission = material.albedo_color
			# Transparent-pass + no depth test makes fitting landmarks a true
			# editor overlay: the body and garment can never cover them.
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.no_depth_test = true
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			material.render_priority = 127
			sphere.material = material
			marker.mesh = sphere
			marker.position = points[marker_name]
			marker.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			_marker_root.add_child(marker)


func _landmarks_for_processor() -> Dictionary:
	var result := {}
	for side in _landmarks:
		var converted := {}
		for marker_name in (_landmarks[side] as Dictionary):
			var godot_point: Vector3 = (
				_landmarks[side] as Dictionary
			)[marker_name]
			# Godot (+Y up, -Z back) -> Blender (+Z up, +Y back).
			converted[marker_name] = [
				godot_point.x,
				-godot_point.z,
				godot_point.y,
			]
		result[side] = converted
	return result


func _load_raw_preview(path: String) -> void:
	if _fit == null or path.strip_edges().is_empty():
		return
	var requested := path.strip_edges()
	var absolute := (
		ProjectSettings.globalize_path(requested)
		if requested.begins_with("res://")
		else requested
	)
	if not FileAccess.file_exists(absolute):
		_preview_source_path = ""
		_validate()
		return
	_invalidate_final_output()
	if _raw_preview != null and is_instance_valid(_raw_preview):
		_raw_preview.queue_free()
		_raw_preview = null
	if _raw_source_root != null and is_instance_valid(_raw_source_root):
		_raw_source_root.queue_free()
		_raw_source_root = null

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(absolute, state)
	if error != OK:
		_set_status(
			"error", "Could not parse raw GLB for preview (error %d)." % error
		)
		_preview_source_path = ""
		return
	_raw_source_root = document.generate_scene(state)
	if _raw_source_root == null:
		_set_status("error", "Raw GLB generated no preview scene.")
		_preview_source_path = ""
		return
	var candidates: Array[MeshInstance3D] = []
	if _raw_source_root is MeshInstance3D:
		candidates.append(_raw_source_root as MeshInstance3D)
	for child in _raw_source_root.find_children(
		"*", "MeshInstance3D", true, false
	):
		candidates.append(child as MeshInstance3D)
	if candidates.is_empty():
		_set_status("error", "Raw GLB contains no mesh.")
		_preview_source_path = ""
		_raw_source_root.free()
		_raw_source_root = null
		return
	var selected := candidates[0]
	var selected_vertices := _mesh_vertex_count(selected.mesh)
	for candidate in candidates:
		var vertex_count := _mesh_vertex_count(candidate.mesh)
		if vertex_count > selected_vertices:
			selected = candidate
			selected_vertices = vertex_count
	var parent := selected.get_parent()
	if parent != null:
		parent.remove_child(selected)
	_raw_source_root.free()
	_raw_source_root = null
	_raw_preview = selected
	_raw_preview.name = "RawClothingPreview_%s" % (
		_selected_part.part_id if _selected_part != null else "new"
	)
	_raw_preview.skin = null
	_raw_preview.skeleton = NodePath()
	_raw_preview.transform = Transform3D.IDENTITY
	_character.add_child(_raw_preview)
	_raw_source_mesh = _raw_preview.mesh as ArrayMesh
	_raw_surface_arrays.clear()
	if _raw_source_mesh == null:
		_set_status("error", "Raw GLB preview mesh is not editable.")
		_preview_source_path = ""
		return
	for surface_index in _raw_source_mesh.get_surface_count():
		_raw_surface_arrays.append(
			_raw_source_mesh.surface_get_arrays(surface_index)
		)
	_preview_source_path = requested
	_fit.source_file = requested
	_source_path.text = requested
	_fit_revision += 1
	_update_raw_preview_mesh()
	if _selected_part != null:
		assembler.set_slot_visible(_selected_part.slot, false)
	_focus_character()
	_validate()


func _invalidate_final_output() -> void:
	_final_output_revision = -1
	_final_output_path = ""
	_final_geometry_changed = false
	if _accept_final_check != null:
		_accept_final_check.set_pressed_no_signal(false)
		_accept_final_check.disabled = true
	if _preview_mode_option != null:
		_preview_mode_option.set_item_disabled(1, true)
		_preview_mode_option.select(0)
	if _final_preview_root != null and is_instance_valid(_final_preview_root):
		_final_preview_root.queue_free()
		_final_preview_root = null
	if _raw_preview != null and is_instance_valid(_raw_preview):
		_raw_preview.visible = true


func _load_final_output_preview(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		_set_status("error", "Final Output GLB is missing.")
		return false
	if _final_preview_root != null and is_instance_valid(_final_preview_root):
		_final_preview_root.queue_free()
		_final_preview_root = null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(absolute, state)
	if error != OK:
		_set_status(
			"error",
			"Could not parse Final Output GLB (error %d)." % error,
		)
		return false
	var generated := document.generate_scene(state) as Node3D
	if generated == null:
		_set_status("error", "Final Output GLB generated no scene.")
		return false
	generated.name = "FinalOutputReview"
	generated.transform = Transform3D.IDENTITY
	_character.add_child(generated)
	_final_preview_root = generated
	for child in generated.find_children("*", "AnimationPlayer", true, false):
		(child as AnimationPlayer).stop()
	for child in generated.find_children("*", "Skeleton3D", true, false):
		(child as Skeleton3D).reset_bone_poses()
	_final_output_path = path
	_final_output_revision = _fit_revision
	_final_geometry_changed = true
	if _preview_mode_option != null:
		_preview_mode_option.set_item_disabled(1, false)
		_preview_mode_option.select(1)
	if _accept_final_check != null:
		_accept_final_check.set_pressed_no_signal(false)
		_accept_final_check.disabled = false
	_on_preview_mode_selected(1)
	_validate()
	return true


func _on_preview_mode_selected(index: int) -> void:
	var show_final := (
		index == 1
		and _final_preview_root != null
		and is_instance_valid(_final_preview_root)
	)
	if _accept_final_check != null:
		_accept_final_check.disabled = not show_final
		if not show_final:
			# Acceptance is deliberately tied to looking at the exact
			# generated mesh. Returning to Raw Fit requires a fresh review.
			_accept_final_check.set_pressed_no_signal(false)
	if _raw_preview != null and is_instance_valid(_raw_preview):
		_raw_preview.visible = not show_final
	if _final_preview_root != null and is_instance_valid(_final_preview_root):
		_final_preview_root.visible = show_final
	_validate()


func _mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size()
	return total


func _update_raw_preview_mesh() -> void:
	if _raw_preview == null or _raw_source_mesh == null or _fit == null:
		return
	var endpoint_before := 0.0
	var scaled_surfaces: Array[PackedVector3Array] = []
	for source_arrays in _raw_surface_arrays:
		var source_vertices: PackedVector3Array = (
			source_arrays as Array
		)[Mesh.ARRAY_VERTEX]
		var scaled := PackedVector3Array()
		scaled.resize(source_vertices.size())
		for vertex_index in source_vertices.size():
			var source := source_vertices[vertex_index]
			var point := Vector3(
				source.x * _fit.scale.x,
				source.y * _fit.scale.z,
				source.z * _fit.scale.y,
			)
			scaled[vertex_index] = point
			endpoint_before = maxf(endpoint_before, absf(point.x))
		scaled_surfaces.append(scaled)

	var shoulder_target := Vector3(0.130, 0.100, -0.024)
	var wrist_target := Vector3(0.270, 0.0525, -0.0142)
	var landmark_samples := 0
	for side in ["left", "right"]:
		var points := _landmarks.get(side, {}) as Dictionary
		if points.has("shoulder") and points.has("wrist"):
			var shoulder: Vector3 = points["shoulder"]
			shoulder_target += Vector3(
				absf(shoulder.x), shoulder.y, shoulder.z
			)
			var wrist: Vector3 = points["wrist"]
			wrist_target += Vector3(
				absf(wrist.x), wrist.y, wrist.z
			)
			landmark_samples += 1
	if landmark_samples > 0:
		shoulder_target = (
			(shoulder_target - Vector3(0.130, 0.100, -0.024))
			/ landmark_samples
		)
		wrist_target = (
			(wrist_target - Vector3(0.270, 0.0525, -0.0142))
			/ landmark_samples
		)
	var shoulder_x := shoulder_target.x
	var sleeve_root := maxf(shoulder_x - 0.015, 0.09)
	var source_cuff_points := PackedVector3Array()
	for scaled in scaled_surfaces:
		for point in scaled:
			if absf(point.x) >= endpoint_before - 0.030:
				source_cuff_points.append(point)
	var source_cuff_center := Vector2.ZERO
	if not source_cuff_points.is_empty():
		var source_minimum := Vector2(INF, INF)
		var source_maximum := Vector2(-INF, -INF)
		for point in source_cuff_points:
			source_minimum = source_minimum.min(Vector2(point.y, point.z))
			source_maximum = source_maximum.max(Vector2(point.y, point.z))
		source_cuff_center = (source_minimum + source_maximum) * 0.5
	var target_endpoint := wrist_target.x - CUFF_GAP_BEFORE_HAND
	var landmark_length_scale := (
		(target_endpoint - sleeve_root)
		/ maxf(endpoint_before - sleeve_root, 0.001)
	)
	var effective_length := landmark_length_scale * _fit.sleeve_length
	var landmark_lift := wrist_target.y - source_cuff_center.x
	var landmark_depth := wrist_target.z - source_cuff_center.y
	var first_pass: Array[PackedVector3Array] = []
	var cuff_points := PackedVector3Array()
	var endpoint_after := (
		sleeve_root
		+ (endpoint_before - sleeve_root) * effective_length
	)
	var cuff_start := endpoint_after - 0.030
	for scaled in scaled_surfaces:
		var deformed := PackedVector3Array()
		deformed.resize(scaled.size())
		for vertex_index in scaled.size():
			var point := scaled[vertex_index]
			var x := absf(point.x)
			var sign_x := 1.0 if point.x >= 0.0 else -1.0
			if x < sleeve_root:
				point.x *= _fit.torso_width
				point.z *= _fit.torso_depth
			else:
				var ramp := clampf(
					(x - sleeve_root)
					/ maxf(endpoint_before - sleeve_root, 0.001),
					0.0,
					1.0,
				)
				var shoulder_weight := (
					1.0
					- clampf(
						(x - maxf(sleeve_root - 0.030, 0.075))
						/ maxf(
							endpoint_before
							- maxf(sleeve_root - 0.030, 0.075),
							0.001,
						),
						0.0,
						1.0,
					)
				)
				point.x = sign_x * (
					sleeve_root
					+ (x - sleeve_root) * effective_length
				)
				point.y += (
					landmark_lift + _fit.sleeve_lift
				) * ramp
				point.y += _fit.shoulder_lift * shoulder_weight
				point.z += (
					landmark_depth - _fit.cuff_forward
				) * ramp
				var sleeve_center := Vector2(
					lerpf(shoulder_target.y, wrist_target.y, ramp),
					lerpf(shoulder_target.z, wrist_target.z, ramp),
				)
				point.y = (
					sleeve_center.x
					+ (point.y - sleeve_center.x) * _fit.sleeve_room
				)
				point.z = (
					sleeve_center.y
					+ (point.z - sleeve_center.y) * _fit.sleeve_room
				)
			deformed[vertex_index] = point
			if absf(point.x) >= cuff_start:
				cuff_points.append(point)
		first_pass.append(deformed)

	var cuff_center := Vector2.ZERO
	if not cuff_points.is_empty():
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point in cuff_points:
			minimum.x = minf(minimum.x, point.z)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.z)
			maximum.y = maxf(maximum.y, point.y)
		cuff_center = (minimum + maximum) * 0.5

	var rebuilt := ArrayMesh.new()
	_raw_deformed_vertices.clear()
	for surface_index in _raw_surface_arrays.size():
		var arrays := (
			(_raw_surface_arrays[surface_index] as Array).duplicate(true)
		)
		var deformed := first_pass[surface_index]
		if not cuff_points.is_empty():
			for vertex_index in deformed.size():
				var point := deformed[vertex_index]
				if absf(point.x) < cuff_start:
					continue
				point.z = (
					cuff_center.x
					+ (point.z - cuff_center.x) * _fit.cuff_radius
				)
				point.y = (
					cuff_center.y
					+ (point.y - cuff_center.y) * _fit.cuff_radius
				)
				deformed[vertex_index] = point
		arrays[Mesh.ARRAY_VERTEX] = deformed
		rebuilt.add_surface_from_arrays(
			_raw_source_mesh.surface_get_primitive_type(surface_index),
			arrays,
		)
		rebuilt.surface_set_material(
			surface_index,
			_raw_source_mesh.surface_get_material(surface_index),
		)
		_raw_deformed_vertices.append(deformed)
	_raw_preview.mesh = rebuilt
	_raw_preview.position = Vector3(
		_fit.position.x, _fit.position.z, -_fit.position.y
	)
	_raw_preview.rotation_degrees = Vector3(
		_fit.rotation_degrees.x,
		_fit.rotation_degrees.z,
		-_fit.rotation_degrees.y,
	)
	_preview_revision = _fit_revision


func _current_cuff_metrics() -> Dictionary:
	var result := {}
	if _raw_preview == null or _raw_deformed_vertices.is_empty():
		return result
	for side in ["left", "right"]:
		var sign_x := 1.0 if side == "left" else -1.0
		var endpoint := -INF
		for vertices in _raw_deformed_vertices:
			for point in vertices:
				endpoint = maxf(endpoint, sign_x * point.x)
		var ring: Array[Vector3] = []
		for vertices in _raw_deformed_vertices:
			for point in vertices:
				if sign_x * point.x >= endpoint - 0.008:
					ring.append(_raw_preview.transform * point)
		if ring.is_empty():
			continue
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for point in ring:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		var center := (minimum + maximum) * 0.5
		result[side] = {
			"center": center,
			"endpoint": maxf(
				absf(minimum.x), absf(maximum.x)
			),
			"radius_y": (maximum.y - minimum.y) * 0.5,
			"radius_z": (maximum.z - minimum.z) * 0.5,
		}
	return result


func _auto_center_cuffs() -> void:
	if _fit == null or _raw_preview == null:
		return
	var metrics := _current_cuff_metrics()
	if metrics.size() < 2:
		_set_status("error", "Raw sleeve openings could not be measured.")
		return
	var lift_delta := 0.0
	var forward_delta := 0.0
	var length_ratio := 0.0
	var sample_count := 0
	for side in ["left", "right"]:
		var cuff := metrics.get(side, {}) as Dictionary
		var landmarks := _landmarks.get(side, {}) as Dictionary
		if cuff.is_empty() or not landmarks.has("wrist"):
			continue
		var center: Vector3 = cuff["center"]
		var wrist: Vector3 = landmarks["wrist"]
		lift_delta += wrist.y - center.y
		# cuff_forward is source +Y, which maps to Godot -Z.
		forward_delta += -(wrist.z - center.z)
		var target_endpoint := absf(wrist.x) - CUFF_GAP_BEFORE_HAND
		var current_endpoint := float(cuff["endpoint"])
		length_ratio += (
			(target_endpoint - 0.115)
			/ maxf(current_endpoint - 0.115, 0.001)
		)
		sample_count += 1
	if sample_count == 0:
		return
	_begin_history_batch()
	_fit.sleeve_lift += lift_delta / sample_count
	_fit.cuff_forward += forward_delta / sample_count
	_fit.sleeve_length *= length_ratio / sample_count
	_refresh_ui_from_fit()
	_preview_fit()
	_end_history_batch()


func _align_to_tpose() -> void:
	if _fit == null:
		return
	_begin_history_batch()
	_fit.rotation_degrees = Vector3.ZERO
	_fit.symmetric = true
	_refresh_ui_from_fit()
	_update_raw_preview_mesh()
	_auto_center_cuffs()
	_end_history_batch()


func _auto_clear_body() -> void:
	if _fit == null or _raw_preview == null:
		return
	_begin_history_batch()
	_align_to_tpose()
	for _attempt in 48:
		if _approximate_clearance_errors().is_empty():
			_refresh_ui_from_fit()
			_validate()
			_end_history_batch()
			return
		_fit.sleeve_room = minf(_fit.sleeve_room + 0.015, 1.80)
		_fit.shoulder_lift = minf(
			_fit.shoulder_lift + 0.0025, 0.10
		)
		_preview_fit()
	_refresh_ui_from_fit()
	_validate()
	_end_history_batch()


func _fit_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _raw_preview == null:
		errors.append("No raw source preview is loaded.")
		return errors
	if _preview_source_path != _fit.source_file:
		errors.append("Preview is stale: it is not displaying the selected source.")
	if _preview_revision != _fit_revision:
		errors.append("Preview is stale: fit controls have not reached the mesh.")
	var metrics := _current_cuff_metrics()
	for side in ["left", "right"]:
		var cuff := metrics.get(side, {}) as Dictionary
		var landmarks := _landmarks.get(side, {}) as Dictionary
		if cuff.is_empty() or not landmarks.has("wrist"):
			errors.append("%s cuff/wrist landmark is unavailable." % side.capitalize())
			continue
		var center: Vector3 = cuff["center"]
		var wrist: Vector3 = landmarks["wrist"]
		var center_error := Vector2(
			center.y - wrist.y, center.z - wrist.z
		).length()
		var target_endpoint := absf(wrist.x) - CUFF_GAP_BEFORE_HAND
		var endpoint_error := absf(
			float(cuff["endpoint"]) - target_endpoint
		)
		if center_error > CUFF_CENTER_TOLERANCE:
			errors.append(
				"%s cuff center is %.1f mm from wrist."
				% [side.capitalize(), center_error * 1000.0]
			)
		if endpoint_error > CUFF_ENDPOINT_TOLERANCE:
			errors.append(
				"%s cuff end is %.1f mm from the before-hand target."
				% [side.capitalize(), endpoint_error * 1000.0]
			)
	errors.append_array(_approximate_clearance_errors())
	return errors


func _approximate_clearance_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _character == null or _raw_preview == null:
		return errors
	var body_mesh := _character.find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	if body_mesh == null or body_mesh.mesh == null:
		errors.append("Body surface is unavailable for clearance validation.")
		return errors
	var body_points := PackedVector3Array()
	for surface_index in body_mesh.mesh.get_surface_count():
		var arrays := body_mesh.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for point in vertices:
			body_points.append(body_mesh.transform * point)
	var garment_points := PackedVector3Array()
	for vertices in _raw_deformed_vertices:
		for point in vertices:
			garment_points.append(_raw_preview.transform * point)

	var failed_stations := PackedStringArray()
	for station in [0.105, 0.125, 0.140, 0.150, 0.190, 0.225, 0.250]:
		var garment_ring := PackedVector3Array()
		var body_ring := PackedVector3Array()
		for point in garment_points:
			if absf(absf(point.x) - station) <= 0.012:
				garment_ring.append(point)
		for point in body_points:
			if (
				absf(absf(point.x) - station) <= 0.008
				and point.y > -0.01
				and point.y < 0.13
			):
				body_ring.append(point)
		if garment_ring.size() < 4 or body_ring.size() < 4:
			continue
		var garment_min := Vector2(INF, INF)
		var garment_max := Vector2(-INF, -INF)
		var body_min := Vector2(INF, INF)
		var body_max := Vector2(-INF, -INF)
		for point in garment_ring:
			garment_min = garment_min.min(Vector2(point.y, point.z))
			garment_max = garment_max.max(Vector2(point.y, point.z))
		for point in body_ring:
			body_min = body_min.min(Vector2(point.y, point.z))
			body_max = body_max.max(Vector2(point.y, point.z))
		if (
			garment_min.x > body_min.x - CLEARANCE_TOLERANCE
			or garment_min.y > body_min.y - CLEARANCE_TOLERANCE
			or garment_max.x < body_max.x + CLEARANCE_TOLERANCE
			or garment_max.y < body_max.y + CLEARANCE_TOLERANCE
		):
			failed_stations.append("%.3f" % station)
	if not failed_stations.is_empty():
		errors.append(
			"Approximate sleeve/body clearance fails at |X| = %s m."
			% ", ".join(failed_stations)
		)
	return errors


func _open_file_dialog() -> void:
	_file_dialog.popup_centered_ratio(0.72)


func _import_source() -> void:
	if _fit == null:
		return
	var external_path := _source_path.text.strip_edges()
	var readable_path := (
		ProjectSettings.globalize_path(external_path)
		if external_path.begins_with("res://")
		else external_path
	)
	if not FileAccess.file_exists(readable_path):
		_set_status("error", "Source GLB does not exist:\n%s" % external_path)
		return
	var destination := (
		"res://art_source/imported/clothing_lab/%s_source.glb"
		% _selected_part.part_id
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(destination.get_base_dir())
	)
	if not external_path.begins_with("res://"):
		var error := DirAccess.copy_absolute(
			external_path,
			ProjectSettings.globalize_path(destination),
		)
		if error != OK:
			_set_status("error", "Could not import GLB (error %d)." % error)
			return
	else:
		destination = external_path
	_fit.source_file = destination
	_source_path.text = destination
	_load_raw_preview(destination)
	_set_status(
		"ok",
		"Source imported unchanged. Adjust fit, then press Copy Body Weights + Bind.",
	)
	_validate()


func _save_resources(publish_to_game := false) -> bool:
	if _fit == null or _selected_part == null:
		return false
	_fit.body_profile_id = (
		preset.body_profile.profile_id
		if preset != null and preset.body_profile != null
		else "body_male"
	)
	var fit_error := ResourceSaver.save(_fit, _current_fit_path())
	var part_error := OK
	var preset_error := OK
	if publish_to_game:
		_selected_part.clothing_fit = _fit
		_selected_part.hidden_regions = _fit.hidden_regions.duplicate()
		part_error = ResourceSaver.save(
			_selected_part, _current_part_path()
		)
		if preset != null and not preset.resource_path.is_empty():
			preset_error = ResourceSaver.save(
				preset, preset.resource_path
			)
	if fit_error != OK or part_error != OK or preset_error != OK:
		_set_status(
			"error",
			"Save failed (fit %d, part %d, preset %d)."
			% [fit_error, part_error, preset_error],
		)
		return false
	_write_config_json()
	_capture_field_baselines()
	_set_status(
		"ok",
		(
			"Published accepted Final Output to in-game resources."
			if publish_to_game
			else "Saved draft fit. In-game output is unchanged."
		),
	)
	return true


func _write_config_json() -> bool:
	if _fit == null:
		return false
	var config_path := _current_config_path()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(config_path.get_base_dir())
	)
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		_set_status("error", "Could not write %s." % config_path)
		return false
	var data := _fit.to_json_data()
	data["landmarks"] = _landmarks_for_processor()
	file.store_string(JSON.stringify(data, "\t"))
	return true


func _bind_and_export() -> void:
	if not _save_resources(false):
		return
	var errors := _hard_validation_errors()
	if not errors.is_empty():
		_set_status("error", "\n".join(errors))
		return
	var arguments := PackedStringArray([
		"--background",
		"--factory-startup",
		"--python",
		ProjectSettings.globalize_path(PROCESSOR_PATH),
		"--",
		"--config",
		ProjectSettings.globalize_path(_current_config_path()),
		"--output",
		ProjectSettings.globalize_path(_current_staging_output_path()),
		"--report",
		ProjectSettings.globalize_path(_current_report_path()),
		"--review-blend",
		ProjectSettings.globalize_path(_current_review_blend_path()),
	])
	_set_status("working", "Blender is copying body weights and binding…")
	var output: Array = []
	var exit_code := OS.execute(BLENDER_PATH, arguments, output, true)
	if exit_code != 0:
		_set_status(
			"error",
			"Bind failed (exit %d).\n%s" % [exit_code, "\n".join(output)],
		)
		return
	if not _load_final_output_preview(_current_staging_output_path()):
		return
	_set_status(
		"warning",
		(
			"FINAL OUTPUT REVIEW REQUIRED\n"
			+ "The processor changed geometry and weights. "
			+ "Inspect this exact staged GLB, then explicitly accept it."
		),
	)


func _publish_final_output() -> void:
	var errors := _final_validation_errors()
	if not errors.is_empty():
		_set_status("error", "BLOCKED\n• " + "\n• ".join(errors))
		return
	var production_path := _current_output_path()
	var staging_absolute := ProjectSettings.globalize_path(
		_final_output_path
	)
	var production_absolute := ProjectSettings.globalize_path(
		production_path
	)
	DirAccess.make_dir_recursive_absolute(
		production_absolute.get_base_dir()
	)
	var copy_error := DirAccess.copy_absolute(
		staging_absolute, production_absolute
	)
	if copy_error != OK:
		_set_status(
			"error",
			"Could not publish Final Output (error %d)." % copy_error,
		)
		return
	if not _finalize_generated_scene(production_path):
		return
	if not _save_resources(true):
		return
	_validate()


func _open_final_review_in_blender() -> void:
	var blend_path := ProjectSettings.globalize_path(
		_current_review_blend_path()
	)
	if not FileAccess.file_exists(blend_path):
		_set_status(
			"error",
			"Bind first; no Final Review .blend exists yet.",
		)
		return
	var process_id := OS.create_process(
		BLENDER_PATH, PackedStringArray([blend_path]), true
	)
	if process_id <= 0:
		_set_status("error", "Could not open Blender Final Review.")
	else:
		_set_status(
			"working",
			"Opened the exact Final Review scene in Blender.",
		)


func _finalize_generated_scene(glb_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(glb_path)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(absolute, state)
	if error != OK:
		_set_status(
			"error",
			"GLB was built, but its runtime scene could not be generated.",
		)
		return false
	var root := document.generate_scene(state)
	if root == null:
		_set_status("error", "Built GLB generated an empty runtime scene.")
		return false
	var packed := PackedScene.new()
	error = packed.pack(root)
	root.free()
	if error != OK:
		_set_status("error", "Could not pack the built garment scene.")
		return false
	var scene_path := (
		# Binary PackedScene keeps the exact runtime-generated glTF scene
		# without expanding embedded mesh/image bytes into a huge text file.
		"res://assets/characters/parts/generated/%s.scn"
		% _selected_part.part_id
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(scene_path.get_base_dir())
	)
	error = ResourceSaver.save(packed, scene_path)
	if error != OK:
		_set_status("error", "Could not save generated garment scene.")
		return false
	_selected_part.scene = load(scene_path) as PackedScene
	ResourceSaver.save(_selected_part, _current_part_path())
	return true


func _validate() -> void:
	if _status == null:
		return
	var errors := _hard_validation_errors()
	var warnings := PackedStringArray()
	if _fit != null:
		for fit_error in _fit.validation_errors():
			if not errors.has(fit_error):
				errors.append(fit_error)
		if (
			_fit.hidden_regions.has("hand_l")
			or _fit.hidden_regions.has("hand_r")
		):
			warnings.append(
				"Hands are selected for hiding; keep this only when intentional."
			)
	if not errors.is_empty():
		_set_status("error", "BLOCKED\n• " + "\n• ".join(errors))
	elif (
		_final_preview_root == null
		or not is_instance_valid(_final_preview_root)
		or _final_output_revision != _fit_revision
	):
		var message := (
			"FIT READY TO BIND\n"
			+ "This is the editable Raw Fit, not the in-game mesh."
		)
		if not warnings.is_empty():
			message += "\n• " + "\n• ".join(warnings)
		_set_status("warning", message)
	elif (
		_accept_final_check == null
		or not _accept_final_check.button_pressed
		or _preview_mode_option == null
		or _preview_mode_option.selected != 1
	):
		_set_status(
			"warning",
			(
				"FINAL OUTPUT REVIEW REQUIRED\n"
				+ "Processor geometry/weights differ from Raw Fit. "
				+ "Review Final Output and accept it explicitly."
			),
		)
	else:
		_set_status(
			"ok",
			(
				"READY FOR GAME\nExact Final Output accepted · "
				+ "existing 34-bone skeleton · hands visible"
			),
		)


func _hard_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _fit == null:
		errors.append("No clothing fit selected.")
		return errors
	var source_path := _fit.source_file
	var absolute := (
		ProjectSettings.globalize_path(source_path)
		if source_path.begins_with("res://")
		else source_path
	)
	if source_path.is_empty() or not FileAccess.file_exists(absolute):
		errors.append("Select or import a valid source GLB.")
	if preset == null or preset.body_profile == null:
		errors.append("Select a body profile.")
	if _selected_part == null:
		errors.append("Select a clothing item.")
	for fit_error in _fit_validation_errors():
		if not errors.has(fit_error):
			errors.append(fit_error)
	return errors


func _final_validation_errors() -> PackedStringArray:
	var errors := _hard_validation_errors()
	if (
		_final_preview_root == null
		or not is_instance_valid(_final_preview_root)
	):
		errors.append("Bind and load the exact Final Output first.")
	elif _final_output_revision != _fit_revision:
		errors.append(
			"Final Output is stale; re-bind after the latest fit change."
		)
	if _final_output_path.is_empty():
		errors.append("Final Output path is unavailable.")
	if _preview_mode_option == null or _preview_mode_option.selected != 1:
		errors.append("Switch to Final Output before accepting it.")
	if (
		_accept_final_check == null
		or not _accept_final_check.button_pressed
	):
		errors.append("Explicitly accept the reviewed Final Output.")
	return errors


func _set_status(kind: String, message: String) -> void:
	if _status == null:
		return
	var color: String = {
		"ok": "#b8df91",
		"warning": "#f0c27b",
		"working": "#9ed4ee",
		"error": "#f38c7d",
	}.get(kind, "#d8d8d8")
	_status.text = "[color=%s]%s[/color]" % [color, message]


func _is_preview_point(point: Vector2) -> bool:
	return point.x > 360.0 and point.x < get_viewport().get_visible_rect().size.x - 420.0


func _current_fit_path() -> String:
	if _selected_part == null:
		return FIT_RESOURCE_PATH
	return (
		"res://assets/characters/parts/fits/%s_fit.tres"
		% _selected_part.part_id
	)


func _current_part_path() -> String:
	if _selected_part == null:
		return PART_RESOURCE_PATH
	return String(
		_part_paths.get(_selected_part.part_id, PART_RESOURCE_PATH)
	)


func _current_config_path() -> String:
	if (
		_selected_part == null
		or _selected_part.part_id == "top_jacket_cozy"
	):
		return CONFIG_PATH
	return (
		"res://art_source/imported/clothing_lab/%s_fit.json"
		% _selected_part.part_id
	)


func _current_output_path() -> String:
	if (
		_selected_part != null
		and _selected_part.scene != null
		and _selected_part.scene.resource_path.ends_with(".glb")
	):
		return _selected_part.scene.resource_path
	if _selected_part != null:
		return (
			"res://assets/characters/parts/%s.glb"
			% _selected_part.part_id
		)
	return OUTPUT_PATH


func _current_staging_output_path() -> String:
	if (
		_selected_part == null
		or _selected_part.part_id == "top_jacket_cozy"
	):
		return (
			"res://art_source/imported/jacket_default/"
			+ "top_jacket_cozy_final_review.glb"
		)
	return (
		"res://art_source/imported/clothing_lab/"
		+ "%s_final_review.glb" % _selected_part.part_id
	)


func _current_report_path() -> String:
	if (
		_selected_part == null
		or _selected_part.part_id == "top_jacket_cozy"
	):
		return REPORT_PATH
	return (
		"res://art_source/imported/clothing_lab/%s_report.json"
		% _selected_part.part_id
	)


func _current_review_blend_path() -> String:
	if (
		_selected_part == null
		or _selected_part.part_id == "top_jacket_cozy"
	):
		return REVIEW_BLEND_PATH
	return (
		"res://art_source/characters/review/%s_clothing_lab.blend"
		% _selected_part.part_id
	)
