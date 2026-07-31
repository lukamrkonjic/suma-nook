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
const PIGEON_RIG_SCENE := preload(
	"res://characters/mascots/pigeon_mascot.tscn"
)
const PIGEON_BLEND_PATH := (
	"res://art_source/characters/pigeon/pigeon_rigify_source.blend"
)
const PROCESSOR_PATH := "res://tools/clothing_lab/process_clothing.py"
const BLENDER_PATH := "C:\\Software\\Blender\\blender.exe"
const PLAYER_PROFILE_PATH := "res://assets/player/current_player_profile.tres"
const PREVIEW_POSES := [
	{"label": "Rest / T-pose (fitting)", "clip": ""},
	{"label": "Idle — relaxed", "clip": "idle_relaxed"},
	{"label": "Walk — loop", "clip": "walk"},
	{"label": "Chop — loop", "clip": "chop"},
	{"label": "Fishing — cast", "clip": "fish_cast"},
	{"label": "Fishing — wait", "clip": "fish_wait"},
]
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
const LANDMARK_PICK_RADIUS := 30.0
const LANDMARK_NUDGE_STEP := 0.002
const LANDMARK_FINE_NUDGE_STEP := 0.0005
const DETAIL_BRUSH_RADIUS_MIN := 0.008
const DETAIL_BRUSH_RADIUS_MAX := 0.080
const DETAIL_BRUSH_DEFAULT_RADIUS := 0.032
const DETAIL_BRUSH_DAB_SPACING := 0.28
const DETAIL_SMOOTH_ITERATIONS := 32
const DETAIL_SMOOTH_RELAXATION := 0.55
const LANDMARK_GROUP_ORDER := [
	"Head & torso",
	"Left arm",
	"Right arm",
	"Left leg",
	"Right leg",
]
const LANDMARK_GROUPS := {
	"Head & torso": [
		"center.crown",
		"center.head",
		"center.face",
		"center.neck",
		"center.chest",
		"center.abdomen",
		"center.waist",
		"center.hips",
	],
	"Left arm": [
		"left.clavicle",
		"left.shoulder",
		"left.elbow",
		"left.wrist",
		"left.hand",
	],
	"Right arm": [
		"right.clavicle",
		"right.shoulder",
		"right.elbow",
		"right.wrist",
		"right.hand",
	],
	"Left leg": [
		"left.hip",
		"left.knee",
		"left.ankle",
		"left.foot",
		"left.toe",
	],
	"Right leg": [
		"right.hip",
		"right.knee",
		"right.ankle",
		"right.foot",
		"right.toe",
	],
}
const LANDMARK_ORDER := [
	"center.crown",
	"center.head",
	"center.face",
	"center.neck",
	"center.chest",
	"center.abdomen",
	"center.waist",
	"center.hips",
	"left.clavicle",
	"left.shoulder",
	"left.elbow",
	"left.wrist",
	"left.hand",
	"right.clavicle",
	"right.shoulder",
	"right.elbow",
	"right.wrist",
	"right.hand",
	"left.hip",
	"left.knee",
	"left.ankle",
	"left.foot",
	"left.toe",
	"right.hip",
	"right.knee",
	"right.ankle",
	"right.foot",
	"right.toe",
]
const LANDMARK_BONES := {
	"center.head": "mixamorigHead",
	"center.neck": "mixamorigNeck",
	"center.chest": "mixamorigSpine2",
	"center.abdomen": "mixamorigSpine1",
	"center.waist": "mixamorigSpine",
	"center.hips": "mixamorigHips",
	"left.clavicle": "mixamorigLeftShoulder",
	"left.shoulder": "mixamorigLeftArm",
	"left.elbow": "mixamorigLeftForeArm",
	"left.wrist": "mixamorigLeftHand",
	"left.hand": "mixamorigLeftHandIndex1",
	"right.clavicle": "mixamorigRightShoulder",
	"right.shoulder": "mixamorigRightArm",
	"right.elbow": "mixamorigRightForeArm",
	"right.wrist": "mixamorigRightHand",
	"right.hand": "mixamorigRightHandIndex1",
	"left.hip": "mixamorigLeftUpLeg",
	"left.knee": "mixamorigLeftLeg",
	"left.ankle": "mixamorigLeftFoot",
	"left.toe": "mixamorigLeftToeBase",
	"right.hip": "mixamorigRightUpLeg",
	"right.knee": "mixamorigRightLeg",
	"right.ankle": "mixamorigRightFoot",
	"right.toe": "mixamorigRightToeBase",
}
const LANDMARK_DISPLAY_NAMES := {
	"center.crown": "Hat anchor (top of head)",
	"center.head": "Head pivot (base of skull)",
	"center.face": "Face attachment center",
	"center.neck": "Neck joint (head/neck seam)",
	"center.chest": "Upper chest (sternum)",
	"center.abdomen": "Mid torso (ribcage)",
	"center.waist": "Lower torso (waist)",
	"center.hips": "Pelvis center (body root)",
	"left.clavicle": "Clavicle root",
	"left.shoulder": "Shoulder joint",
	"left.elbow": "Elbow joint",
	"left.wrist": "Wrist joint",
	"left.hand": "Hand center",
	"right.clavicle": "Clavicle root",
	"right.shoulder": "Shoulder joint",
	"right.elbow": "Elbow joint",
	"right.wrist": "Wrist joint",
	"right.hand": "Hand center",
	"left.hip": "Hip joint (leg socket)",
	"left.knee": "Knee joint",
	"left.ankle": "Ankle joint",
	"left.foot": "Foot center",
	"left.toe": "Toe base",
	"right.hip": "Hip joint (leg socket)",
	"right.knee": "Knee joint",
	"right.ankle": "Ankle joint",
	"right.foot": "Foot center",
	"right.toe": "Toe base",
}
const FIT_SCALAR_KEYS := [
	"torso_width",
	"torso_depth",
	"top_section_scale",
	"middle_section_scale",
	"bottom_section_scale",
	"sleeve_lift",
	"sleeve_length",
	"sleeve_room",
	"shoulder_lift",
	"cuff_radius",
	"cuff_forward",
	"surface_smoothing",
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
var _pair_center_controls_root: Control
var _drag_handles: Dictionary = {}
var _revert_buttons: Dictionary = {}
var _field_baselines: Dictionary = {}
var _clothing_list: ItemList
var _body_option: OptionButton
var _rig_subject_option: OptionButton
var _pigeon_rig_tools: VBoxContainer
var _pigeon_bone_option: OptionButton
var _pigeon_rotation_controls: Array[SpinBox] = []
var _pigeon_show_bones: CheckBox
var _pigeon_skeleton: Skeleton3D
var _pigeon_rig_overlay: MeshInstance3D
var _pigeon_base_rotations: Dictionary = {}
var _pigeon_bone_offsets: Dictionary = {}
var _pigeon_control_sync := false
var _pigeon_mode := false
var _source_path: LineEdit
var _status: RichTextLabel
var _file_dialog: FileDialog
var _ui_root: Control
var _preview_hidden_regions: CheckBox
var _body_view_option: OptionButton
var _body_opacity := 0.6
var _preview_mode_option: OptionButton
var _preview_pose_option: OptionButton
var _preview_speed_slider: HSlider
var _preview_speed_label: Label
var _surface_smoothing_slider: HSlider
var _surface_smoothing_label: Label
var _detail_erase_button: Button
var _detail_brush_radius_slider: HSlider
var _detail_brush_radius_label: Label
var _detail_brush_strength_slider: HSlider
var _detail_brush_strength_label: Label
var _detail_brush_clear_button: Button
var _detail_brush_cursor: MeshInstance3D
var _detail_erase_enabled := false
var _detail_painting := false
var _detail_stroke_snapshot: Dictionary = {}
var _detail_last_dab_source := Vector3(INF, INF, INF)
var _detail_brush_radius := DETAIL_BRUSH_DEFAULT_RADIUS
var _detail_brush_strength := 1.0
var _show_equipped_clothing: CheckBox
var _lock_scale_proportions: CheckBox
var _accept_final_check: CheckBox
var _save_draft_button: Button
var _bind_button: Button
var _open_review_button: Button
var _publish_button: Button
var _raw_preview: MeshInstance3D
var _raw_source_root: Node
var _raw_source_mesh: ArrayMesh
var _raw_surface_arrays: Array = []
var _raw_deformed_vertices: Array[PackedVector3Array] = []
var _bound_smoothing_sources: Dictionary = {}
var _preview_source_path := ""
var _fit_revision := 0
var _preview_revision := -1
var _final_preview_root: Node3D
var _final_output_revision := -1
var _final_output_path := ""
var _final_geometry_changed := false
var _underlayer_preview: MeshInstance3D
var _preview_ground_bounds := AABB()
var _has_preview_ground_bounds := false
var _landmarks: Dictionary = {}
var _default_landmarks: Dictionary = {}
var _marker_root: Node3D
var _marker_nodes: Dictionary = {}
var _marker_toggle: CheckBox
var _marker_edit_button: Button
var _marker_editor: VBoxContainer
var _marker_group_option: OptionButton
var _marker_option: OptionButton
var _marker_mirror: CheckBox
var _marker_editing := false
var _marker_visibility_before_edit := true
var _garment_visibility_before_marker_edit := true
var _body_mask_preview_before_marker_edit := true
var _clothing_slot_visibility_before_marker_edit: Dictionary = {}
var _selected_marker_key := "center.head"
var _marker_drag_key := ""
var _marker_drag_plane := Plane()
var _marker_drag_snapshot: Dictionary = {}
var _marker_drag_origin := Vector3.ZERO
var _marker_drag_screen_origin := Vector2.ZERO
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
	# Run after the character AnimationPlayer so the separate staged garment
	# skeleton receives this frame's pose, not the previous frame's pose.
	process_priority = 10
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
	if not _selected_preview_clip().is_empty():
		_ground_preview_character()
	_sync_final_output_pose()
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
		_end_detail_erase_stroke(true)
		_redo()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("undo", true):
		_end_field_drag(true)
		_end_detail_erase_stroke(true)
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
		if (
			mouse_button.button_index == MOUSE_BUTTON_LEFT
			and not mouse_button.pressed
			and _detail_painting
		):
			_end_detail_erase_stroke(true)
			get_viewport().set_input_as_handled()
			return
		if (
			mouse_button.button_index == MOUSE_BUTTON_LEFT
			and not mouse_button.pressed
			and not _marker_drag_key.is_empty()
		):
			_end_marker_drag(true)
			get_viewport().set_input_as_handled()
			return
		if (
			_detail_erase_enabled
			and mouse_button.button_index == MOUSE_BUTTON_LEFT
			and mouse_button.pressed
			and _is_preview_point(mouse_button.position)
			and _begin_detail_erase_stroke(mouse_button.position)
		):
			get_viewport().set_input_as_handled()
			return
		if (
			_marker_editing
			and mouse_button.button_index == MOUSE_BUTTON_LEFT
			and mouse_button.pressed
			and _is_preview_point(mouse_button.position)
			and _begin_marker_drag(mouse_button.position)
		):
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
	if mouse_motion != null and _detail_erase_enabled:
		if _detail_painting:
			_continue_detail_erase_stroke(mouse_motion.position)
			get_viewport().set_input_as_handled()
			return
		_update_detail_brush_cursor(mouse_motion.position)
	if mouse_motion != null and not _marker_drag_key.is_empty():
		_drag_marker(mouse_motion.position)
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
		if _detail_painting:
			_end_detail_erase_stroke(false)
			get_viewport().set_input_as_handled()
			return
		if _detail_erase_enabled:
			_set_detail_erase_mode(false)
			get_viewport().set_input_as_handled()
			return
		if not _marker_drag_key.is_empty():
			_end_marker_drag(false)
			get_viewport().set_input_as_handled()
			return
		if _marker_editing:
			_set_marker_edit_mode(false)
			get_viewport().set_input_as_handled()
			return
		_end_orbit()
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_end_field_drag(false)
	_end_detail_erase_stroke(false)
	_end_marker_drag(false)
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
	_rig_subject_option = _option_row(left_content, "Rig subject")
	_rig_subject_option.add_item("Human clothing rig")
	_rig_subject_option.set_item_metadata(0, "human")
	_rig_subject_option.add_item("Surma pigeon · Rigify bird")
	_rig_subject_option.set_item_metadata(1, "pigeon")
	_rig_subject_option.item_selected.connect(_on_rig_subject_selected)
	_build_pigeon_rig_tools(left_content)
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
			# Rigid hats and accessories are fitted by their named sockets,
			# not by the body-weight copy pipeline. They remain selectable in
			# the Appearance controls without being misrepresented as a
			# skinned Clothing Lab garment.
			if (
				definition.attachment_type
				!= CharacterPartDefinition.ATTACHMENT_SKINNED
			):
				continue
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
	locked_pose.text = "FIT CALCULATIONS  ·  REST / T-POSE  [LOCKED]"
	locked_pose.tooltip_text = (
		"Fitting, landmarks, weight-copy, and binding always use the canonical "
		+ "rest pose. The animation dropdown changes only the visual preview."
	)
	locked_pose.add_theme_color_override("font_color", Color("#b8df91"))
	right_shell.add_child(locked_pose)
	_preview_pose_option = _option_row(right_shell, "Pose / animation")
	for pose in PREVIEW_POSES:
		_preview_pose_option.add_item(String(pose["label"]))
		_preview_pose_option.set_item_metadata(
			_preview_pose_option.item_count - 1,
			String(pose["clip"]),
		)
	_preview_pose_option.tooltip_text = (
		"Preview the character and bound Final Output in useful poses. "
		+ "This never changes the saved rest-pose fit."
	)
	_preview_pose_option.item_selected.connect(_on_preview_pose_selected)
	var speed_row := HBoxContainer.new()
	right_shell.add_child(speed_row)
	var speed_title := Label.new()
	speed_title.text = "Animation speed"
	speed_title.custom_minimum_size.x = 112
	speed_row.add_child(speed_title)
	_preview_speed_slider = HSlider.new()
	_preview_speed_slider.min_value = 0.1
	_preview_speed_slider.max_value = 2.0
	_preview_speed_slider.step = 0.05
	_preview_speed_slider.value = 1.0
	_preview_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_speed_slider.tooltip_text = (
		"Changes visual preview playback only; fitting remains locked to "
		+ "the canonical rest pose."
	)
	_preview_speed_slider.value_changed.connect(_on_preview_speed_changed)
	speed_row.add_child(_preview_speed_slider)
	_preview_speed_label = Label.new()
	_preview_speed_label.text = "1.00×"
	_preview_speed_label.custom_minimum_size.x = 52
	_preview_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_row.add_child(_preview_speed_label)
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

	_separator(right_content, "Preview controls")
	_show_equipped_clothing = CheckBox.new()
	_show_equipped_clothing.text = "Show equipped clothing"
	_show_equipped_clothing.tooltip_text = (
		"Temporarily hide the selected garment without changing equipment "
		+ "or saved fit data."
	)
	_show_equipped_clothing.button_pressed = true
	_show_equipped_clothing.toggled.connect(
		func(_visible: bool) -> void:
			_apply_garment_preview_visibility()
	)
	right_content.add_child(_show_equipped_clothing)
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
	_marker_toggle = CheckBox.new()
	_marker_toggle.text = "Full-body clothing rig markers"
	_marker_toggle.button_pressed = true
	_marker_toggle.toggled.connect(
		func(_visible: bool) -> void:
			_update_marker_visibility()
	)
	right_content.add_child(_marker_toggle)
	_note(
		right_content,
		"Head/torso · complete arms · hips/legs · ankles/feet",
	)

	_marker_edit_button = _button(
		"Edit rig markers", func() -> void:
			_set_marker_edit_mode(_marker_edit_button.button_pressed)
	)
	_marker_edit_button.toggle_mode = true
	_marker_edit_button.tooltip_text = (
		"Drag the fitting dots to the centers of the T-pose joints. "
		+ "This adjusts reusable body-profile fitting anchors; it does not "
		+ "move or deform the Skeleton3D."
	)
	right_content.add_child(_marker_edit_button)
	_build_marker_editor(right_content)

	_separator(right_content, "Whole garment transform")
	_pair_center_controls_root = VBoxContainer.new()
	_pair_center_controls_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_content.add_child(_pair_center_controls_root)
	_note(
		_pair_center_controls_root,
		"Paired footwear: Position X/Y move the shoes in opposite mirrored "
		+ "directions; Z moves both vertically. Pair center moves both shoes "
		+ "together.",
	)
	_add_vector_controls(
		_pair_center_controls_root,
		"Pair center (m)",
		"pair_center",
		-0.50,
		0.50,
		0.001,
	)
	_add_vector_controls(
		right_content, "Position (m)", "position", -0.25, 0.25, 0.001
	)
	_add_vector_controls(
		right_content, "Rotation (°)", "rotation", -180.0, 180.0, 0.25
	)
	_lock_scale_proportions = CheckBox.new()
	_lock_scale_proportions.text = "Lock XYZ scale proportions"
	_lock_scale_proportions.tooltip_text = (
		"When enabled, changing any scale axis multiplies all three axes "
		+ "by the same factor, preserving the garment's current proportions."
	)
	_lock_scale_proportions.button_pressed = true
	right_content.add_child(_lock_scale_proportions)
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
	_separator(right_content, "Top / middle / bottom shaping")
	_note(
		right_content,
		"Scale each garment cross-section without changing its height. "
		+ "The sections blend smoothly, so no horizontal seam is created.",
	)
	_add_fit_control(
		right_content,
		"Top section scale",
		"top_section_scale",
		0.60,
		1.50,
		0.005,
	)
	_add_fit_control(
		right_content,
		"Middle section scale",
		"middle_section_scale",
		0.60,
		1.50,
		0.005,
	)
	_add_fit_control(
		right_content,
		"Bottom section scale",
		"bottom_section_scale",
		0.60,
		1.50,
		0.005,
	)
	_add_fit_control(right_content, "Sleeve lift (m)", "sleeve_lift", -0.08, 0.12, 0.001)
	_add_fit_control(right_content, "Sleeve length", "sleeve_length", 0.75, 1.20, 0.005)
	_add_fit_control(right_content, "Sleeve room", "sleeve_room", 0.90, 1.80, 0.005)
	_add_fit_control(right_content, "Shoulder lift (m)", "shoulder_lift", -0.04, 0.10, 0.001)
	_add_fit_control(right_content, "Cuff opening", "cuff_radius", 0.85, 1.30, 0.005)
	_add_fit_control(right_content, "Cuff forward (m)", "cuff_forward", -0.04, 0.04, 0.001)
	_add_fit_control(
		right_content,
		"Surface smoothing",
		"surface_smoothing",
		0.0,
		1.0,
		0.01,
	)
	_add_surface_smoothing_slider(right_content)
	_build_detail_eraser(right_content)
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
	_separator(sticky, "Workflow · save → build → review → publish")
	_save_draft_button = _button(
		"1. Save Fit + Rig Draft",
		_save_resources,
	)
	_save_draft_button.tooltip_text = (
		"Save editable garment fitting, hidden body regions, and global rig "
		+ "markers. This never changes the in-game garment."
	)
	sticky.add_child(_save_draft_button)
	_bind_button = _button(
		"2. Build Final Output · Copy Weights + Bind",
		_bind_and_export,
	)
	_bind_button.tooltip_text = (
		"Runs Blender in REST/T-pose, nearest-face copies body weights, "
		+ "and exports the staged Final Output. Fit warnings never block this."
	)
	sticky.add_child(_bind_button)
	_preview_mode_option = _option_row(sticky, "3. Preview")
	_preview_mode_option.add_item("Editable Raw Fit")
	_preview_mode_option.add_item("Bound / Animated Garment")
	_preview_mode_option.set_item_disabled(1, true)
	_preview_mode_option.tooltip_text = (
		"Raw Fit is editable and stays in T-pose. Bound / Animated Garment uses "
		+ "the live skeleton; a newly built Bound Final Output takes priority "
		+ "over the currently published bound garment."
	)
	_preview_mode_option.item_selected.connect(_on_preview_mode_selected)
	_open_review_button = _button(
		"3. Open Final Review in Blender · Optional",
		_open_final_review_in_blender,
	)
	sticky.add_child(_open_review_button)
	_accept_final_check = CheckBox.new()
	_accept_final_check.text = "3. I reviewed this Final Output · Recommended"
	_accept_final_check.tooltip_text = (
		"Recommended review note only. It is never a publishing gate; clicking "
		+ "Publish is the final confirmation."
	)
	_accept_final_check.disabled = true
	_accept_final_check.toggled.connect(
		func(_accepted: bool) -> void:
			_validate()
	)
	sticky.add_child(_accept_final_check)
	_publish_button = _button(
		"4. Publish Final Output to Game",
		_publish_final_output,
	)
	_publish_button.tooltip_text = (
		"Publish the currently built Final Output. Visual fit diagnostics are "
		+ "advisory and never disable this action."
	)
	sticky.add_child(_publish_button)
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


func _build_pigeon_rig_tools(parent: Control) -> void:
	_pigeon_rig_tools = VBoxContainer.new()
	_pigeon_rig_tools.visible = false
	_pigeon_rig_tools.add_theme_constant_override("separation", 6)
	parent.add_child(_pigeon_rig_tools)
	_separator(_pigeon_rig_tools, "Pigeon bird rig")
	_note(
		_pigeon_rig_tools,
		"Live Rigify deformation skeleton. Select a DEF bone, pose it here, "
		+ "or open the editable Blender source for structural rig work.",
	)
	_pigeon_bone_option = _option_row(_pigeon_rig_tools, "Active bone")
	_pigeon_bone_option.item_selected.connect(_on_pigeon_bone_selected)
	for axis_name in ["X rotation", "Y rotation", "Z rotation"]:
		var row := HBoxContainer.new()
		_pigeon_rig_tools.add_child(row)
		var label := Label.new()
		label.text = axis_name
		label.custom_minimum_size.x = 112
		row.add_child(label)
		var control := SpinBox.new()
		control.min_value = -180.0
		control.max_value = 180.0
		control.step = 1.0
		control.suffix = "°"
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.value_changed.connect(_on_pigeon_rotation_changed)
		row.add_child(control)
		_pigeon_rotation_controls.append(control)
	_pigeon_show_bones = CheckBox.new()
	_pigeon_show_bones.text = "Show live bone overlay"
	_pigeon_show_bones.button_pressed = true
	_pigeon_show_bones.toggled.connect(
		func(visible: bool) -> void:
			if _pigeon_rig_overlay != null:
				_pigeon_rig_overlay.visible = visible
	)
	_pigeon_rig_tools.add_child(_pigeon_show_bones)
	var reset_row := HBoxContainer.new()
	_pigeon_rig_tools.add_child(reset_row)
	var reset_bone := _button("Reset bone", _reset_selected_pigeon_bone)
	reset_bone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_row.add_child(reset_bone)
	var reset_pose := _button("Reset all", _reset_all_pigeon_bones)
	reset_pose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_row.add_child(reset_pose)
	var open_blender := _button(
		"Open Pigeon Rigify Source in Blender",
		_open_pigeon_rig_in_blender,
	)
	open_blender.tooltip_text = (
		"Open the editable bird rig source. Export the finished GLB back to "
		+ "assets/characters/pigeon/pigeon.glb."
	)
	_pigeon_rig_tools.add_child(open_blender)


func _on_rig_subject_selected(index: int) -> void:
	var subject := String(_rig_subject_option.get_item_metadata(index))
	if subject == "pigeon":
		_show_pigeon_rig_subject()
	else:
		_restore_human_rig_subject()


func _show_pigeon_rig_subject() -> void:
	_pigeon_mode = true
	_clear_pigeon_rig_state()
	if _character != null:
		remove_child(_character)
		_character.queue_free()
		_character = null
	_character = PIGEON_RIG_SCENE.instantiate() as Node3D
	_character.name = "PigeonRigSubject"
	add_child(_character)
	_character.visible = true
	var controller := _character.get_node_or_null("MascotController") as Node
	if controller != null:
		controller.set_process(false)
		controller.set_physics_process(false)
	_pigeon_skeleton = _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if _pigeon_skeleton == null:
		_set_status("error", "Pigeon Rigify skeleton could not be loaded.")
		return
	_character.position = Vector3.ZERO
	# Clothing Lab's front camera looks along the humanoid +Z convention; the
	# bird asset is authored facing -Z. Rotate only this preview root.
	_character.rotation.y = PI
	var bounds := _visual_bounds(_character)
	_character.position.y = -bounds.position.y
	_cache_preview_ground_bounds()
	_cache_pigeon_bone_pose()
	_populate_pigeon_bone_option()
	_build_pigeon_bone_overlay()
	_set_human_lab_controls_enabled(false)
	_pigeon_rig_tools.visible = true
	_focus_character()
	_set_status(
		"ok",
		"Surma pigeon loaded with %d Rigify bones. Select a DEF bone or open the Blender source."
		% _pigeon_skeleton.get_bone_count(),
	)


func _restore_human_rig_subject() -> void:
	if not _pigeon_mode:
		return
	_pigeon_mode = false
	_clear_pigeon_rig_state()
	_pigeon_rig_tools.visible = false
	_set_human_lab_controls_enabled(true)
	# The previous assembler still owns weak references to the human parts that
	# were removed when the pigeon became the subject. Start a clean assembly
	# when returning instead of asking it to clear already-freed nodes.
	assembler = CharacterAssembler.new()
	super._rebuild()
	_force_rest_pose()
	_cache_preview_ground_bounds()
	_apply_body_mask()
	_refresh_landmark_markers()
	_restore_preview_pose()
	_set_status("ok", "Human clothing rig restored.")


func _set_human_lab_controls_enabled(enabled: bool) -> void:
	if _body_option != null:
		_body_option.disabled = not enabled
	for option in _slot_options.values():
		(option as OptionButton).disabled = not enabled
	if _clothing_list != null:
		_clothing_list.mouse_filter = (
			Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		)
		_clothing_list.modulate.a = 1.0 if enabled else 0.45
	if _source_path != null:
		_source_path.editable = enabled
	for control in [
		_preview_pose_option,
		_preview_speed_slider,
		_save_draft_button,
		_bind_button,
		_open_review_button,
		_publish_button,
	]:
		if control is BaseButton:
			(control as BaseButton).disabled = not enabled
		elif control is Slider:
			(control as Slider).editable = enabled
	if not enabled and _preview_pose_option != null:
		_preview_pose_option.select(0)


func _cache_pigeon_bone_pose() -> void:
	_pigeon_base_rotations.clear()
	_pigeon_bone_offsets.clear()
	for bone_index in _pigeon_skeleton.get_bone_count():
		_pigeon_base_rotations[bone_index] = (
			_pigeon_skeleton.get_bone_pose_rotation(bone_index)
		)
		_pigeon_bone_offsets[bone_index] = Vector3.ZERO


func _populate_pigeon_bone_option() -> void:
	_pigeon_bone_option.clear()
	for bone_index in _pigeon_skeleton.get_bone_count():
		var bone_name := _pigeon_skeleton.get_bone_name(bone_index)
		if not bone_name.begins_with("DEF-"):
			continue
		_pigeon_bone_option.add_item(bone_name.trim_prefix("DEF-"))
		_pigeon_bone_option.set_item_metadata(
			_pigeon_bone_option.item_count - 1,
			bone_index,
		)
	if _pigeon_bone_option.item_count > 0:
		var initial_option := 0
		var left_wing_index := _pigeon_skeleton.find_bone("DEF-Wing.L")
		for option_index in _pigeon_bone_option.item_count:
			if int(
				_pigeon_bone_option.get_item_metadata(option_index)
			) == left_wing_index:
				initial_option = option_index
				break
		_pigeon_bone_option.select(initial_option)
		_on_pigeon_bone_selected(initial_option)


func _selected_pigeon_bone_index() -> int:
	if _pigeon_bone_option == null or _pigeon_bone_option.selected < 0:
		return -1
	return int(
		_pigeon_bone_option.get_item_metadata(_pigeon_bone_option.selected)
	)


func _on_pigeon_bone_selected(_index: int) -> void:
	var bone_index := _selected_pigeon_bone_index()
	if bone_index < 0:
		return
	var degrees: Vector3 = _pigeon_bone_offsets.get(
		bone_index,
		Vector3.ZERO,
	)
	_pigeon_control_sync = true
	for axis in mini(3, _pigeon_rotation_controls.size()):
		_pigeon_rotation_controls[axis].value = degrees[axis]
	_pigeon_control_sync = false
	_refresh_pigeon_bone_overlay()


func _on_pigeon_rotation_changed(_value: float) -> void:
	if _pigeon_control_sync or _pigeon_skeleton == null:
		return
	var bone_index := _selected_pigeon_bone_index()
	if bone_index < 0:
		return
	var degrees := Vector3(
		_pigeon_rotation_controls[0].value,
		_pigeon_rotation_controls[1].value,
		_pigeon_rotation_controls[2].value,
	)
	_pigeon_bone_offsets[bone_index] = degrees
	var radians := Vector3(
		deg_to_rad(degrees.x),
		deg_to_rad(degrees.y),
		deg_to_rad(degrees.z),
	)
	var base: Quaternion = _pigeon_base_rotations.get(
		bone_index,
		Quaternion.IDENTITY,
	)
	_pigeon_skeleton.set_bone_pose_rotation(
		bone_index,
		base * Quaternion.from_euler(radians),
	)
	_refresh_pigeon_bone_overlay()


func _reset_selected_pigeon_bone() -> void:
	var bone_index := _selected_pigeon_bone_index()
	if bone_index < 0 or _pigeon_skeleton == null:
		return
	_pigeon_bone_offsets[bone_index] = Vector3.ZERO
	_pigeon_skeleton.set_bone_pose_rotation(
		bone_index,
		_pigeon_base_rotations.get(bone_index, Quaternion.IDENTITY),
	)
	_on_pigeon_bone_selected(_pigeon_bone_option.selected)


func _reset_all_pigeon_bones() -> void:
	if _pigeon_skeleton == null:
		return
	for bone_index in _pigeon_base_rotations:
		_pigeon_skeleton.set_bone_pose_rotation(
			bone_index,
			_pigeon_base_rotations[bone_index],
		)
		_pigeon_bone_offsets[bone_index] = Vector3.ZERO
	_on_pigeon_bone_selected(_pigeon_bone_option.selected)


func _build_pigeon_bone_overlay() -> void:
	if _pigeon_skeleton == null:
		return
	_pigeon_rig_overlay = MeshInstance3D.new()
	_pigeon_rig_overlay.name = "PigeonRigBoneOverlay"
	_pigeon_rig_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pigeon_rig_overlay.extra_cull_margin = 2.0
	_pigeon_skeleton.add_child(_pigeon_rig_overlay)
	_refresh_pigeon_bone_overlay()


func _refresh_pigeon_bone_overlay() -> void:
	if _pigeon_skeleton == null or _pigeon_rig_overlay == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ff5b9d")
	material.no_depth_test = true
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for bone_index in _pigeon_skeleton.get_bone_count():
		var parent_index := _pigeon_skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		lines.surface_add_vertex(
			_pigeon_skeleton.get_bone_global_pose(parent_index).origin
		)
		lines.surface_add_vertex(
			_pigeon_skeleton.get_bone_global_pose(bone_index).origin
		)
	lines.surface_end()
	_pigeon_rig_overlay.mesh = lines
	_pigeon_rig_overlay.visible = (
		_pigeon_show_bones == null or _pigeon_show_bones.button_pressed
	)


func _clear_pigeon_rig_state() -> void:
	if _pigeon_rig_overlay != null and is_instance_valid(_pigeon_rig_overlay):
		_pigeon_rig_overlay.queue_free()
	_pigeon_rig_overlay = null
	_pigeon_skeleton = null
	_pigeon_base_rotations.clear()
	_pigeon_bone_offsets.clear()
	if _pigeon_bone_option != null:
		_pigeon_bone_option.clear()


func _open_pigeon_rig_in_blender() -> void:
	var blend_path := ProjectSettings.globalize_path(PIGEON_BLEND_PATH)
	if not FileAccess.file_exists(blend_path):
		_set_status("error", "Pigeon Rigify .blend source is missing.")
		return
	if not FileAccess.file_exists(BLENDER_PATH):
		_set_status("error", "Blender was not found at %s." % BLENDER_PATH)
		return
	var process_id := OS.create_process(
		BLENDER_PATH,
		PackedStringArray([blend_path]),
		true,
	)
	if process_id <= 0:
		_set_status("error", "Could not open the pigeon Rigify source.")
	else:
		_set_status(
			"ok",
			"Opened pigeon Rigify source in Blender (process %d)." % process_id,
		)


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


func _build_marker_editor(parent: Control) -> void:
	_marker_editor = VBoxContainer.new()
	_marker_editor.visible = false
	_marker_editor.add_theme_constant_override("separation", 5)
	parent.add_child(_marker_editor)
	_marker_group_option = _option_row(_marker_editor, "Body section")
	for group_name in LANDMARK_GROUP_ORDER:
		_marker_group_option.add_item(group_name)
		_marker_group_option.set_item_metadata(
			_marker_group_option.item_count - 1, group_name
		)
	_marker_group_option.item_selected.connect(
		func(index: int) -> void:
			_populate_marker_option(
				String(_marker_group_option.get_item_metadata(index))
			)
	)
	_marker_option = _option_row(_marker_editor, "Active joint")
	_marker_option.item_selected.connect(
		func(index: int) -> void:
			_select_landmark_marker(
				String(_marker_option.get_item_metadata(index))
			)
	)
	_populate_marker_option(LANDMARK_GROUP_ORDER[0])
	_marker_mirror = CheckBox.new()
	_marker_mirror.text = "Mirror opposite side"
	_marker_mirror.button_pressed = true
	_marker_mirror.tooltip_text = (
		"Move the matching left/right joint symmetrically."
	)
	_marker_editor.add_child(_marker_mirror)
	var nudge_grid := GridContainer.new()
	nudge_grid.columns = 3
	_marker_editor.add_child(nudge_grid)
	for axis_spec: Array in [
		["X", Vector3.RIGHT],
		["Y", Vector3.UP],
		["Z", Vector3.BACK],
	]:
		var axis_direction: Vector3 = axis_spec[1]
		var axis_label := Label.new()
		axis_label.text = String(axis_spec[0])
		axis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nudge_grid.add_child(axis_label)
		var negative := _button(
			"−", _nudge_selected_marker.bind(-axis_direction)
		)
		negative.tooltip_text = "Nudge -%s" % axis_spec[0]
		negative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nudge_grid.add_child(negative)
		var positive := _button(
			"+", _nudge_selected_marker.bind(axis_direction)
		)
		positive.tooltip_text = "Nudge +%s" % axis_spec[0]
		positive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nudge_grid.add_child(positive)
	var reset_markers := _button(
		"Reset markers to skeleton", _reset_landmarks_to_skeleton
	)
	reset_markers.tooltip_text = (
		"Discard custom anchors for this body and re-measure its rest-pose bones."
	)
	_marker_editor.add_child(reset_markers)
	_note(
		_marker_editor,
		"LMB drag a dot · hold X, Y, or Z while dragging to lock that axis · "
		+ "MMB orbit. Use the nudge buttons with keyboard/controller; "
		+ "hold Shift for fine steps.",
	)


func _populate_marker_option(group_name: String) -> void:
	if _marker_option == null:
		return
	var marker_keys := LANDMARK_GROUPS.get(group_name, []) as Array
	_marker_option.clear()
	if marker_keys.is_empty():
		return
	if not marker_keys.has(_selected_marker_key):
		_selected_marker_key = String(marker_keys[0])
	for marker_key in marker_keys:
		var parts := String(marker_key).split(".", false, 1)
		_marker_option.add_item(
			String(
				LANDMARK_DISPLAY_NAMES.get(
					marker_key,
					parts[1].replace("_", " ").capitalize(),
				)
			)
		)
		_marker_option.set_item_metadata(
			_marker_option.item_count - 1, marker_key
		)
		if String(marker_key) == _selected_marker_key:
			_marker_option.select(_marker_option.item_count - 1)
	_refresh_marker_selection_visuals()


func _landmark_group_for_key(marker_key: String) -> String:
	for group_name in LANDMARK_GROUP_ORDER:
		if (LANDMARK_GROUPS[group_name] as Array).has(marker_key):
			return group_name
	return LANDMARK_GROUP_ORDER[0]


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
			func(
				_value: float,
				control_key := key,
				component_index := axis_index,
			) -> void:
				_on_vector_changed(control_key, component_index)
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


func _add_surface_smoothing_slider(parent: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = "Live smooth shading"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_surface_smoothing_slider = HSlider.new()
	_surface_smoothing_slider.min_value = 0.0
	_surface_smoothing_slider.max_value = 1.0
	_surface_smoothing_slider.step = 0.01
	_surface_smoothing_slider.value = (
		_fit.surface_smoothing if _fit != null else 0.0
	)
	_surface_smoothing_slider.custom_minimum_size.x = 132
	_surface_smoothing_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface_smoothing_slider.tooltip_text = (
		"Blends only the garment's lighting normals in real time. "
		+ "It never changes the silhouette, fit, UVs, skin weights, "
		+ "or animation-safe topology."
	)
	_surface_smoothing_slider.drag_started.connect(_begin_history_batch)
	_surface_smoothing_slider.drag_ended.connect(
		func(_value_changed: bool) -> void:
			_end_history_batch()
	)
	_surface_smoothing_slider.value_changed.connect(
		func(value: float) -> void:
			var spin := _fit_controls.get(
				"surface_smoothing"
			) as SpinBox
			if spin != null:
				spin.value = value
			_update_surface_smoothing_readout(value)
	)
	row.add_child(_surface_smoothing_slider)
	_surface_smoothing_label = Label.new()
	_surface_smoothing_label.custom_minimum_size.x = 42
	_surface_smoothing_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	row.add_child(_surface_smoothing_label)
	var smoothing_spin := _fit_controls.get(
		"surface_smoothing"
	) as SpinBox
	if smoothing_spin != null:
		smoothing_spin.value_changed.connect(
			func(value: float) -> void:
				_surface_smoothing_slider.set_value_no_signal(value)
				_update_surface_smoothing_readout(value)
		)
	_update_surface_smoothing_readout(
		_surface_smoothing_slider.value
	)


func _update_surface_smoothing_readout(value: float) -> void:
	if _surface_smoothing_label != null:
		_surface_smoothing_label.text = "%d%%" % roundi(value * 100.0)


func _build_detail_eraser(parent: Control) -> void:
	_separator(parent, "Surface detail eraser")
	_note(
		parent,
		"Paint over raised buttons or decorations in Rest/T-pose. "
		+ "The brush relaxes them into fixed surrounding fabric and samples "
		+ "that fabric's color. Sideways cloth drift, seams, and garment "
		+ "borders stay protected.",
	)
	_detail_erase_button = _button(
		"Erase details with brush",
		func() -> void:
			_set_detail_erase_mode(_detail_erase_button.button_pressed)
	)
	_detail_erase_button.toggle_mode = true
	_detail_erase_button.tooltip_text = (
		"Enter the non-destructive detail brush. Left-drag over raised "
		+ "geometry; middle-drag still orbits."
	)
	parent.add_child(_detail_erase_button)

	var radius_row := HBoxContainer.new()
	parent.add_child(radius_row)
	var radius_title := Label.new()
	radius_title.text = "Brush radius"
	radius_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_row.add_child(radius_title)
	_detail_brush_radius_slider = HSlider.new()
	_detail_brush_radius_slider.min_value = DETAIL_BRUSH_RADIUS_MIN
	_detail_brush_radius_slider.max_value = DETAIL_BRUSH_RADIUS_MAX
	_detail_brush_radius_slider.step = 0.001
	_detail_brush_radius_slider.value = _detail_brush_radius
	_detail_brush_radius_slider.custom_minimum_size.x = 120
	_detail_brush_radius_slider.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	_detail_brush_radius_slider.value_changed.connect(
		func(value: float) -> void:
			_detail_brush_radius = value
			_refresh_detail_eraser_ui()
	)
	radius_row.add_child(_detail_brush_radius_slider)
	_detail_brush_radius_label = Label.new()
	_detail_brush_radius_label.custom_minimum_size.x = 54
	_detail_brush_radius_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	radius_row.add_child(_detail_brush_radius_label)

	var strength_row := HBoxContainer.new()
	parent.add_child(strength_row)
	var strength_title := Label.new()
	strength_title.text = "Smoothing strength"
	strength_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_row.add_child(strength_title)
	_detail_brush_strength_slider = HSlider.new()
	_detail_brush_strength_slider.min_value = 0.1
	_detail_brush_strength_slider.max_value = 1.0
	_detail_brush_strength_slider.step = 0.05
	_detail_brush_strength_slider.value = _detail_brush_strength
	_detail_brush_strength_slider.custom_minimum_size.x = 120
	_detail_brush_strength_slider.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	_detail_brush_strength_slider.value_changed.connect(
		func(value: float) -> void:
			_detail_brush_strength = value
			_refresh_detail_eraser_ui()
	)
	strength_row.add_child(_detail_brush_strength_slider)
	_detail_brush_strength_label = Label.new()
	_detail_brush_strength_label.custom_minimum_size.x = 46
	_detail_brush_strength_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	strength_row.add_child(_detail_brush_strength_label)

	_detail_brush_clear_button = _button(
		"Clear all erased details",
		_clear_detail_erase_strokes,
	)
	_detail_brush_clear_button.tooltip_text = (
		"Restore every brushed detail on this clothing item. "
		+ "This operation can be undone."
	)
	parent.add_child(_detail_brush_clear_button)
	_refresh_detail_eraser_ui()


func _refresh_detail_eraser_ui() -> void:
	var stroke_count := (
		_fit.detail_erase_strokes.size() if _fit != null else 0
	)
	if _detail_erase_button != null:
		_detail_erase_button.set_pressed_no_signal(_detail_erase_enabled)
		_detail_erase_button.text = (
			"Done erasing details"
			if _detail_erase_enabled
			else "Erase details with brush"
		)
		_detail_erase_button.text += "  ·  %d dabs" % stroke_count
	if _detail_brush_radius_label != null:
		_detail_brush_radius_label.text = (
			"%d mm" % roundi(_detail_brush_radius * 1000.0)
		)
	if _detail_brush_strength_label != null:
		_detail_brush_strength_label.text = (
			"%d%%" % roundi(_detail_brush_strength * 100.0)
		)
	if _detail_brush_clear_button != null:
		_detail_brush_clear_button.disabled = stroke_count == 0


func _set_detail_erase_mode(enabled: bool) -> void:
	if enabled and (_fit == null or _raw_preview == null):
		if _detail_erase_button != null:
			_detail_erase_button.set_pressed_no_signal(false)
		return
	if enabled and _marker_editing:
		_set_marker_edit_mode(false)
	_detail_erase_enabled = enabled
	_detail_painting = false
	_detail_stroke_snapshot.clear()
	_detail_last_dab_source = Vector3(INF, INF, INF)
	if enabled:
		if _preview_pose_option != null:
			_preview_pose_option.select(0)
			_on_preview_pose_selected(0)
		if _preview_mode_option != null:
			_preview_mode_option.select(0)
			_on_preview_mode_selected(0)
		if _show_equipped_clothing != null:
			_show_equipped_clothing.set_pressed_no_signal(true)
		_apply_garment_preview_visibility()
	else:
		_hide_detail_brush_cursor()
	_update_marker_visibility()
	_refresh_detail_eraser_ui()


func _clear_detail_erase_strokes() -> void:
	if _fit == null or _fit.detail_erase_strokes.is_empty():
		return
	_end_detail_erase_stroke(true)
	_record_history_before_change()
	_fit.detail_erase_strokes.clear()
	_preview_fit()
	_refresh_detail_eraser_ui()


func _begin_detail_erase_stroke(screen_position: Vector2) -> bool:
	if not _detail_erase_enabled or _fit == null:
		return false
	var pick := _pick_raw_garment(screen_position)
	if pick.is_empty():
		_hide_detail_brush_cursor()
		return false
	_detail_painting = true
	_detail_stroke_snapshot = _capture_fit_snapshot()
	_detail_last_dab_source = Vector3(INF, INF, INF)
	_append_detail_erase_dab(pick)
	return true


func _continue_detail_erase_stroke(screen_position: Vector2) -> void:
	if not _detail_painting:
		return
	var pick := _pick_raw_garment(screen_position)
	if pick.is_empty():
		_hide_detail_brush_cursor()
		return
	_update_detail_brush_cursor_from_pick(pick)
	var center: Vector3 = pick.get("source_position", Vector3.ZERO)
	var source_radius := _detail_source_radius()
	if (
		not is_finite(_detail_last_dab_source.x)
		or center.distance_to(_detail_last_dab_source)
		>= source_radius * DETAIL_BRUSH_DAB_SPACING
	):
		_append_detail_erase_dab(pick)


func _end_detail_erase_stroke(commit: bool) -> void:
	if not _detail_painting:
		return
	var before := _detail_stroke_snapshot.duplicate(true)
	_detail_painting = false
	_detail_stroke_snapshot.clear()
	_detail_last_dab_source = Vector3(INF, INF, INF)
	if not commit and not before.is_empty():
		_apply_fit_snapshot(before)
	elif (
		commit
		and not before.is_empty()
		and before != _capture_fit_snapshot()
	):
		_push_undo_snapshot(before)
	_refresh_detail_eraser_ui()


func _append_detail_erase_dab(pick: Dictionary) -> void:
	if _fit == null:
		return
	var source_center: Vector3 = pick.get(
		"source_position", Vector3.ZERO
	)
	var source_normal: Vector3 = pick.get(
		"source_normal", Vector3.BACK
	)
	var source_radius := _detail_source_radius()
	var sample := _detail_fabric_sample(
		source_center, source_normal, source_radius
	)
	var fabric_normal: Vector3 = sample.get(
		"fabric_normal", source_normal
	)
	var stroke := {
		"version": 2,
		"selection": "small_source_components",
		"center": [
			source_center.x,
			source_center.y,
			source_center.z,
		],
		"normal": [
			fabric_normal.x,
			fabric_normal.y,
			fabric_normal.z,
		],
		"radius": source_radius,
		"strength": _detail_brush_strength,
		"target_offset": float(sample.get("target_offset", 0.0)),
		"sample_uv": sample.get("sample_uv", [0.0, 0.0]),
	}
	_fit.detail_erase_strokes.append(stroke)
	_detail_last_dab_source = source_center
	_preview_fit()
	_refresh_detail_eraser_ui()
	_update_detail_brush_cursor_from_pick(pick)


func _detail_source_radius() -> float:
	if _fit == null:
		return _detail_brush_radius
	var average_scale := (
		absf(_fit.scale.x)
		+ absf(_fit.scale.y)
		+ absf(_fit.scale.z)
	) / 3.0
	return _detail_brush_radius / maxf(average_scale, 0.001)


func _detail_fabric_sample(
	center: Vector3,
	normal: Vector3,
	radius: float,
) -> Dictionary:
	var source_surfaces: Array[PackedVector3Array] = []
	for source_arrays in _raw_surface_arrays:
		var arrays := source_arrays as Array
		source_surfaces.append(arrays[Mesh.ARRAY_VERTEX])
	var source_normals := _calculate_surface_smoothing_normals(
		_raw_surface_arrays,
		source_surfaces,
		1.0,
	)
	var component_extent_limit := _detail_component_extent_limit(radius)
	var fabric_vertices: Dictionary = {}
	var compact_detail_positions: Dictionary = {}
	for surface_component_data in _detail_source_component_data():
		var surface_index := int(surface_component_data["surface"])
		var source_arrays := (
			_raw_surface_arrays[surface_index] as Array
		)
		var source_vertices: PackedVector3Array = (
			source_arrays[Mesh.ARRAY_VERTEX]
		)
		for component in surface_component_data["components"]:
			var minimum: Vector3 = component["minimum"]
			var maximum: Vector3 = component["maximum"]
			var extent := maximum - minimum
			var maximum_extent := maxf(
				extent.x, maxf(extent.y, extent.z)
			)
			if maximum_extent <= component_extent_limit:
				for vertex_index in component["vertices"]:
					compact_detail_positions[
						_detail_position_key(
							source_vertices[int(vertex_index)]
						)
					] = true
				continue
			for vertex_index in component["vertices"]:
				fabric_vertices[
					"%d:%d" % [surface_index, int(vertex_index)]
				] = true
	var all_candidates: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	for surface_index in _raw_surface_arrays.size():
		var arrays := _raw_surface_arrays[surface_index] as Array
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals := PackedVector3Array()
		if surface_index < source_normals.size():
			normals = source_normals[surface_index]
		for vertex_index in vertices.size():
			var delta := vertices[vertex_index] - center
			var projection := delta.dot(normal)
			var tangent := (delta - normal * projection).length()
			if tangent < radius * 0.58 or tangent > radius * 1.30:
				continue
			var candidate_normal := normal
			if vertex_index < normals.size():
				candidate_normal = normals[vertex_index].normalized()
				if candidate_normal.dot(normal) < 0.0:
					candidate_normal = -candidate_normal
			var candidate := {
				"position": vertices[vertex_index],
				"projection": projection,
				"ring_error": absf(tangent - radius * 0.88),
				"normal": candidate_normal,
				"uv": (
					uvs[vertex_index]
					if vertex_index < uvs.size()
					else Vector2.ZERO
				),
			}
			all_candidates.append(candidate)
			if (
				fabric_vertices.has(
					"%d:%d" % [surface_index, vertex_index]
				)
				and not compact_detail_positions.has(
					_detail_position_key(vertices[vertex_index])
				)
			):
				candidates.append(candidate)
	if candidates.is_empty():
		candidates = all_candidates
	if candidates.is_empty():
		return {
			"fabric_normal": normal,
			"target_offset": 0.0,
			"sample_uv": [0.0, 0.0],
		}
	# A closed garment also has reverse/inside vertices inside the same brush
	# cylinder. Sampling those pulls the repair plane into the garment and
	# turns a flattened button into a visible dent. Keep only the outer cloth
	# band closest to the picked surface before averaging its plane or UV.
	var outermost_projection := -INF
	for candidate in candidates:
		outermost_projection = maxf(
			outermost_projection,
			float(candidate["projection"]),
		)
	var outer_band_floor := (
		outermost_projection - maxf(radius * 0.65, 0.01)
	)
	var outer_candidates: Array[Dictionary] = []
	for candidate in candidates:
		if float(candidate["projection"]) >= outer_band_floor:
			outer_candidates.append(candidate)
	if outer_candidates.size() >= 3:
		candidates = outer_candidates
	var normal_sum := Vector3.ZERO
	var normal_weight := 0.0
	for candidate in candidates:
		var candidate_normal: Vector3 = candidate["normal"]
		var alignment := maxf(candidate_normal.dot(normal), 0.0)
		if alignment < 0.25:
			continue
		var weight := alignment / maxf(
			float(candidate["ring_error"]) + radius * 0.08,
			0.000001,
		)
		normal_sum += candidate_normal * weight
		normal_weight += weight
	var fabric_normal := normal
	if normal_weight > 0.0 and normal_sum.length_squared() > 0.000001:
		fabric_normal = normal_sum.normalized()
	var projections: Array[float] = []
	for candidate in candidates:
		var position: Vector3 = candidate["position"]
		var projection := (position - center).dot(fabric_normal)
		candidate["projection"] = projection
		projections.append(projection)
	projections.sort()
	var target_offset := projections[projections.size() / 2]
	var best := candidates[0]
	var best_score := INF
	for candidate in candidates:
		var score := (
			absf(float(candidate["projection"]) - target_offset) * 4.0
			+ float(candidate["ring_error"])
		)
		if score < best_score:
			best_score = score
			best = candidate
	var sample_uv: Vector2 = best["uv"]
	return {
		"fabric_normal": fabric_normal,
		"target_offset": target_offset,
		"sample_uv": [sample_uv.x, sample_uv.y],
	}


func _detail_source_component_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface_index in _raw_surface_arrays.size():
		var arrays := _raw_surface_arrays[surface_index] as Array
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var neighbors: Array = []
		neighbors.resize(vertices.size())
		for vertex_index in vertices.size():
			neighbors[vertex_index] = []
		var triangle_count := (
			indices.size() / 3
			if not indices.is_empty()
			else vertices.size() / 3
		)
		for triangle_index in triangle_count:
			var triangle := PackedInt32Array()
			for corner in 3:
				triangle.append(
					indices[triangle_index * 3 + corner]
					if not indices.is_empty()
					else triangle_index * 3 + corner
				)
			if (
				triangle[0] >= vertices.size()
				or triangle[1] >= vertices.size()
				or triangle[2] >= vertices.size()
			):
				continue
			for edge in [
				Vector2i(triangle[0], triangle[1]),
				Vector2i(triangle[1], triangle[2]),
				Vector2i(triangle[2], triangle[0]),
			]:
				var forward := neighbors[edge.x] as Array
				if edge.y not in forward:
					forward.append(edge.y)
				var reverse := neighbors[edge.y] as Array
				if edge.x not in reverse:
					reverse.append(edge.x)
		var visited := PackedByteArray()
		visited.resize(vertices.size())
		var components: Array[Dictionary] = []
		for seed in vertices.size():
			if visited[seed] != 0:
				continue
			var stack := [seed]
			visited[seed] = 1
			var component_vertices := PackedInt32Array()
			var minimum := Vector3(INF, INF, INF)
			var maximum := Vector3(-INF, -INF, -INF)
			while not stack.is_empty():
				var current := int(stack.pop_back())
				component_vertices.append(current)
				minimum = minimum.min(vertices[current])
				maximum = maximum.max(vertices[current])
				for neighbor in neighbors[current]:
					var neighbor_index := int(neighbor)
					if visited[neighbor_index] != 0:
						continue
					visited[neighbor_index] = 1
					stack.append(neighbor_index)
			components.append({
				"vertices": component_vertices,
				"minimum": minimum,
				"maximum": maximum,
			})
		result.append({
			"surface": surface_index,
			"components": components,
		})
	return result


func _detail_position_key(point: Vector3) -> String:
	return "%d:%d:%d" % [
		roundi(point.x * 100000.0),
		roundi(point.y * 100000.0),
		roundi(point.z * 100000.0),
	]


func _detail_position_adjacency() -> Dictionary:
	var result: Dictionary = {}
	for source_arrays in _raw_surface_arrays:
		var arrays := source_arrays as Array
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_count := (
			indices.size() / 3
			if not indices.is_empty()
			else vertices.size() / 3
		)
		for triangle_index in triangle_count:
			var triangle := PackedInt32Array()
			for corner in 3:
				triangle.append(
					indices[triangle_index * 3 + corner]
					if not indices.is_empty()
					else triangle_index * 3 + corner
				)
			if (
				triangle[0] >= vertices.size()
				or triangle[1] >= vertices.size()
				or triangle[2] >= vertices.size()
			):
				continue
			for edge in [
				Vector2i(triangle[0], triangle[1]),
				Vector2i(triangle[1], triangle[2]),
				Vector2i(triangle[2], triangle[0]),
			]:
				var first_key := _detail_position_key(vertices[edge.x])
				var second_key := _detail_position_key(vertices[edge.y])
				if not result.has(first_key):
					result[first_key] = []
				if not result.has(second_key):
					result[second_key] = []
				var first_neighbors := result[first_key] as Array
				var second_neighbors := result[second_key] as Array
				if second_key not in first_neighbors:
					first_neighbors.append(second_key)
				if first_key not in second_neighbors:
					second_neighbors.append(first_key)
	return result


func _detail_component_extent_limit(radius: float) -> float:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var has_vertices := false
	for source_arrays in _raw_surface_arrays:
		var arrays := source_arrays as Array
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
			has_vertices = true
	if not has_vertices:
		return radius * 2.20
	var garment_extent_vector := maximum - minimum
	var garment_extent := maxf(
		garment_extent_vector.x,
		maxf(garment_extent_vector.y, garment_extent_vector.z),
	)
	return clampf(
		radius * 2.20,
		garment_extent * 0.10,
		garment_extent * 0.18,
	)


func _detail_erased_source_arrays() -> Dictionary:
	var vertices_by_surface: Array[PackedVector3Array] = []
	var uvs_by_surface: Array[PackedVector2Array] = []
	var erased_vertex_masks: Array[PackedByteArray] = []
	for source_arrays in _raw_surface_arrays:
		var arrays := source_arrays as Array
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		vertices_by_surface.append(vertices.duplicate())
		uvs_by_surface.append(uvs.duplicate())
		var erased_mask := PackedByteArray()
		erased_mask.resize(vertices.size())
		erased_vertex_masks.append(erased_mask)
	if _fit == null:
		return {
			"vertices": vertices_by_surface,
			"uvs": uvs_by_surface,
			"erased_vertex_masks": erased_vertex_masks,
		}
	var component_data := _detail_source_component_data()
	var position_adjacency := _detail_position_adjacency()
	var source_positions_by_key: Dictionary = {}
	for source_arrays in _raw_surface_arrays:
		var arrays := source_arrays as Array
		var source_vertices: PackedVector3Array = (
			arrays[Mesh.ARRAY_VERTEX]
		)
		for source_point in source_vertices:
			source_positions_by_key[
				_detail_position_key(source_point)
			] = source_point
	for stroke in _fit.detail_erase_strokes:
		var center_data: Array = stroke.get("center", [])
		var normal_data: Array = stroke.get("normal", [])
		var uv_data: Array = stroke.get("sample_uv", [])
		if (
			center_data.size() != 3
			or normal_data.size() != 3
			or uv_data.size() != 2
		):
			continue
		var center := Vector3(
			float(center_data[0]),
			float(center_data[1]),
			float(center_data[2]),
		)
		var normal := Vector3(
			float(normal_data[0]),
			float(normal_data[1]),
			float(normal_data[2]),
		).normalized()
		var radius := maxf(float(stroke.get("radius", 0.0)), 0.0001)
		var component_extent_limit := _detail_component_extent_limit(radius)
		var strength := clampf(
			float(stroke.get("strength", 1.0)), 0.0, 1.0
		)
		var target_offset := float(stroke.get("target_offset", 0.0))
		# The surrounding jacket is the reference surface, not editable brush
		# clay. Only geometry visibly raised above that sampled plane belongs
		# to the decoration. This dead-zone is what keeps the coat silhouette,
		# seams, folds, and ordinary fabric curvature completely stationary.
		var detail_height_threshold := maxf(radius * 0.06, 0.002)
		var component_aware: bool = (
			int(stroke.get("version", 1)) >= 2
			and String(stroke.get("selection", ""))
			== "small_source_components"
		)
		var applied_height_threshold := (
			0.0002 if component_aware else detail_height_threshold
		)
		var selected_positions: Dictionary = {}
		if component_aware:
			for surface_component_data in component_data:
				var source_surface_index := int(
					surface_component_data["surface"]
				)
				var source_arrays := (
					_raw_surface_arrays[source_surface_index] as Array
				)
				var source_vertices: PackedVector3Array = (
					source_arrays[Mesh.ARRAY_VERTEX]
				)
				for component in surface_component_data["components"]:
					var minimum: Vector3 = component["minimum"]
					var maximum: Vector3 = component["maximum"]
					var extent := maximum - minimum
					var maximum_extent := maxf(
						extent.x, maxf(extent.y, extent.z)
					)
					if maximum_extent > component_extent_limit:
						continue
					var intersects_raised_detail := false
					for component_vertex_index in component["vertices"]:
						var point := source_vertices[
							int(component_vertex_index)
						]
						var delta := point - center
						var projection := delta.dot(normal)
						var tangent := (
							delta - normal * projection
						).length()
						if (
							tangent <= radius * 1.05
							and projection
							> target_offset + applied_height_threshold
						):
							intersects_raised_detail = true
							break
					if not intersects_raised_detail:
						continue
					for component_vertex_index in component["vertices"]:
						selected_positions[
							_detail_position_key(
								source_vertices[
									int(component_vertex_index)
								]
							)
						] = true
		var smoothed_positions := selected_positions.duplicate()
		if component_aware:
			for selected_key in selected_positions:
				for neighbor_key in position_adjacency.get(
					selected_key, []
				):
					if not source_positions_by_key.has(neighbor_key):
						continue
					var neighbor_point: Vector3 = (
						source_positions_by_key[neighbor_key]
					)
					var neighbor_delta := neighbor_point - center
					var neighbor_projection := neighbor_delta.dot(normal)
					var neighbor_tangent := (
						neighbor_delta - normal * neighbor_projection
					).length()
					if neighbor_tangent <= radius * 1.25:
						smoothed_positions[neighbor_key] = true
		var sample_uv := Vector2(
			float(uv_data[0]), float(uv_data[1])
		)
		var stroke_start_positions: Dictionary = {}
		if component_aware:
			for surface_index in vertices_by_surface.size():
				var vertices := vertices_by_surface[surface_index]
				var source_arrays := (
					_raw_surface_arrays[surface_index] as Array
				)
				var source_vertices: PackedVector3Array = (
					source_arrays[Mesh.ARRAY_VERTEX]
				)
				for vertex_index in vertices.size():
					stroke_start_positions[
						_detail_position_key(
							source_vertices[vertex_index]
						)
					] = vertices[vertex_index]
		for surface_index in vertices_by_surface.size():
			var vertices := vertices_by_surface[surface_index]
			var uvs := uvs_by_surface[surface_index]
			var erased_mask := erased_vertex_masks[surface_index]
			var source_arrays := (
				_raw_surface_arrays[surface_index] as Array
			)
			var source_vertices: PackedVector3Array = (
				source_arrays[Mesh.ARRAY_VERTEX]
			)
			for vertex_index in vertices.size():
				var source_point := source_vertices[vertex_index]
				var source_key := _detail_position_key(source_point)
				if (
					component_aware
					and not smoothed_positions.has(source_key)
				):
					continue
				var source_delta := source_point - center
				var source_projection := source_delta.dot(normal)
				var tangent_delta := (
					source_delta - normal * source_projection
				)
				var tangent_distance := tangent_delta.length()
				var current_projection := (
					vertices[vertex_index] - center
				).dot(normal)
				# Once a compact detail component is selected, repaint and
				# smooth the complete component. Restrict only the geometric
				# displacement to the brush radius. This removes the button's
				# surviving sidewall ring without pulling adjacent cloth.
				if component_aware:
					erased_mask[vertex_index] = 1
					if vertex_index < uvs.size():
						uvs[vertex_index] = uvs[vertex_index].lerp(
							sample_uv, strength
						)
					if not selected_positions.has(source_key):
						continue
				if (
					tangent_distance
					>= radius * (1.20 if component_aware else 1.0)
				):
					continue
				if (
					current_projection
					<= target_offset + applied_height_threshold
				):
					continue
				var weight := strength
				if not component_aware:
					var normalized_distance := tangent_distance / radius
					var falloff := (
						1.0
						- normalized_distance * normalized_distance
						* (3.0 - 2.0 * normalized_distance)
					)
					weight = clampf(strength * falloff, 0.0, 1.0)
				vertices[vertex_index] -= (
					normal
					* (current_projection - target_offset)
					* weight
				)
				erased_mask[vertex_index] = 1
				if (
					not component_aware
					and vertex_index < uvs.size()
					and weight > 0.12
				):
					uvs[vertex_index] = uvs[vertex_index].lerp(
						sample_uv, weight
					)
			vertices_by_surface[surface_index] = vertices
			uvs_by_surface[surface_index] = uvs
			erased_vertex_masks[surface_index] = erased_mask
		if component_aware and not smoothed_positions.is_empty():
			# Repaint complete triangles touching the repair. UVs are
			# per-corner in the baked GLB; leaving even one old corner causes
			# a bright/dark rim through interpolation.
			for surface_index in vertices_by_surface.size():
				var source_arrays := (
					_raw_surface_arrays[surface_index] as Array
				)
				var source_vertices: PackedVector3Array = (
					source_arrays[Mesh.ARRAY_VERTEX]
				)
				var indices: PackedInt32Array = (
					source_arrays[Mesh.ARRAY_INDEX]
				)
				var uvs := uvs_by_surface[surface_index]
				var triangle_count := (
					indices.size() / 3
					if not indices.is_empty()
					else source_vertices.size() / 3
				)
				for triangle_index in triangle_count:
					var triangle := PackedInt32Array()
					var touches_repair := false
					for corner in 3:
						var vertex_index := (
							indices[triangle_index * 3 + corner]
							if not indices.is_empty()
							else triangle_index * 3 + corner
						)
						triangle.append(vertex_index)
						if (
							vertex_index < source_vertices.size()
							and smoothed_positions.has(
								_detail_position_key(
									source_vertices[vertex_index]
								)
							)
						):
							touches_repair = true
					if not touches_repair:
						continue
					for vertex_index in triangle:
						if int(vertex_index) < uvs.size():
							uvs[int(vertex_index)] = uvs[
								int(vertex_index)
							].lerp(sample_uv, strength)
				uvs_by_surface[surface_index] = uvs

			# Relax only the detail plus one local neighbor ring. Everything
			# outside this set is an immutable cloth anchor, so the button
			# smooths into the coat rather than collapsing into a planar dent.
			var current_positions: Dictionary = {}
			for surface_index in vertices_by_surface.size():
				var vertices := vertices_by_surface[surface_index]
				var source_arrays := (
					_raw_surface_arrays[surface_index] as Array
				)
				var source_vertices: PackedVector3Array = (
					source_arrays[Mesh.ARRAY_VERTEX]
				)
				for vertex_index in vertices.size():
					current_positions[
						_detail_position_key(
							source_vertices[vertex_index]
						)
					] = vertices[vertex_index]
			var relaxation := DETAIL_SMOOTH_RELAXATION * strength
			for _iteration in DETAIL_SMOOTH_ITERATIONS:
				var updates: Dictionary = {}
				for smooth_key in smoothed_positions:
					var neighbors: Array = position_adjacency.get(
						smooth_key, []
					)
					if neighbors.is_empty():
						continue
					var average := Vector3.ZERO
					var sample_count := 0
					for neighbor_key in neighbors:
						if not current_positions.has(neighbor_key):
							continue
						average += current_positions[neighbor_key]
						sample_count += 1
					if sample_count == 0:
						continue
					average /= float(sample_count)
					updates[smooth_key] = (
						current_positions[smooth_key] as Vector3
					).lerp(average, relaxation)
				for smooth_key in updates:
					current_positions[smooth_key] = updates[smooth_key]
			# The useful edit is relief removal along the fabric normal.
			# Unbounded Laplacian relaxation can instead drag sparse vertices
			# sideways across the coat. Cap those two displacement components
			# independently so a button vanishes without smearing the panel.
			var normal_cap := radius * 0.45 * strength
			var tangent_cap := radius * 0.15 * strength
			for smooth_key in smoothed_positions:
				if (
					not current_positions.has(smooth_key)
					or not stroke_start_positions.has(smooth_key)
				):
					continue
				var start: Vector3 = stroke_start_positions[smooth_key]
				var delta: Vector3 = current_positions[smooth_key] - start
				var normal_amount := clampf(
					delta.dot(normal), -normal_cap, normal_cap
				)
				var tangent := delta - normal * delta.dot(normal)
				if tangent.length() > tangent_cap:
					tangent = tangent.normalized() * tangent_cap
				current_positions[smooth_key] = (
					start + normal * normal_amount + tangent
				)
			for surface_index in vertices_by_surface.size():
				var vertices := vertices_by_surface[surface_index]
				var erased_mask := erased_vertex_masks[surface_index]
				var source_arrays := (
					_raw_surface_arrays[surface_index] as Array
				)
				var source_vertices: PackedVector3Array = (
					source_arrays[Mesh.ARRAY_VERTEX]
				)
				for vertex_index in vertices.size():
					var source_key := _detail_position_key(
						source_vertices[vertex_index]
					)
					if not smoothed_positions.has(source_key):
						continue
					vertices[vertex_index] = current_positions[source_key]
					erased_mask[vertex_index] = 1
				vertices_by_surface[surface_index] = vertices
				erased_vertex_masks[surface_index] = erased_mask
	return {
		"vertices": vertices_by_surface,
		"uvs": uvs_by_surface,
		"erased_vertex_masks": erased_vertex_masks,
	}


func _update_detail_brush_cursor(screen_position: Vector2) -> void:
	if not _detail_erase_enabled:
		_hide_detail_brush_cursor()
		return
	var pick := _pick_raw_garment(screen_position)
	if pick.is_empty():
		_hide_detail_brush_cursor()
		return
	_update_detail_brush_cursor_from_pick(pick)


func _update_detail_brush_cursor_from_pick(pick: Dictionary) -> void:
	if _raw_preview == null or not is_instance_valid(_raw_preview):
		return
	if (
		_detail_brush_cursor == null
		or not is_instance_valid(_detail_brush_cursor)
	):
		_detail_brush_cursor = MeshInstance3D.new()
		_detail_brush_cursor.name = "DetailEraserCursor"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 32
		torus.ring_segments = 8
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.25, 0.92, 0.86, 0.92)
		material.emission_enabled = true
		material.emission = Color(0.18, 0.80, 0.75)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.render_priority = 127
		torus.material = material
		_detail_brush_cursor.mesh = torus
		_detail_brush_cursor.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_raw_preview.add_child(_detail_brush_cursor)
	var local_position: Vector3 = pick.get(
		"local_position", Vector3.ZERO
	)
	var local_normal: Vector3 = pick.get(
		"local_normal", Vector3.BACK
	)
	_detail_brush_cursor.position = (
		local_position + local_normal.normalized() * 0.001
	)
	_detail_brush_cursor.basis = Basis(
		Quaternion(Vector3.UP, local_normal.normalized())
	).scaled(Vector3.ONE * _detail_brush_radius)
	_detail_brush_cursor.visible = true


func _hide_detail_brush_cursor() -> void:
	if (
		_detail_brush_cursor != null
		and is_instance_valid(_detail_brush_cursor)
	):
		_detail_brush_cursor.visible = false


func _pick_raw_garment(screen_position: Vector2) -> Dictionary:
	if (
		_raw_preview == null
		or not is_instance_valid(_raw_preview)
		or not _raw_preview.visible
		or _raw_deformed_vertices.is_empty()
	):
		return {}
	var camera := _active_preview_camera()
	if camera == null:
		return {}
	var inverse := _raw_preview.global_transform.affine_inverse()
	var ray_origin := (
		inverse * camera.project_ray_origin(screen_position)
	)
	var ray_direction := (
		inverse.basis * camera.project_ray_normal(screen_position)
	).normalized()
	var best_distance := INF
	var best := {}
	for surface_index in _raw_surface_arrays.size():
		if surface_index >= _raw_deformed_vertices.size():
			continue
		var arrays := _raw_surface_arrays[surface_index] as Array
		var vertices := _raw_deformed_vertices[surface_index]
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_count := (
			indices.size() / 3
			if not indices.is_empty()
			else vertices.size() / 3
		)
		for triangle_index in triangle_count:
			var a_index := (
				indices[triangle_index * 3]
				if not indices.is_empty()
				else triangle_index * 3
			)
			var b_index := (
				indices[triangle_index * 3 + 1]
				if not indices.is_empty()
				else triangle_index * 3 + 1
			)
			var c_index := (
				indices[triangle_index * 3 + 2]
				if not indices.is_empty()
				else triangle_index * 3 + 2
			)
			if (
				a_index >= vertices.size()
				or b_index >= vertices.size()
				or c_index >= vertices.size()
			):
				continue
			var hit := _ray_triangle_barycentric(
				ray_origin,
				ray_direction,
				vertices[a_index],
				vertices[b_index],
				vertices[c_index],
			)
			if hit.x < 0.0 or hit.x >= best_distance:
				continue
			best_distance = hit.x
			var weights := Vector3(1.0 - hit.y - hit.z, hit.y, hit.z)
			var local_position := (
				vertices[a_index] * weights.x
				+ vertices[b_index] * weights.y
				+ vertices[c_index] * weights.z
			)
			var source_position := (
				source_vertices[a_index] * weights.x
				+ source_vertices[b_index] * weights.y
				+ source_vertices[c_index] * weights.z
			)
			var local_normal := (
				(vertices[b_index] - vertices[a_index]).cross(
					vertices[c_index] - vertices[a_index]
				)
			).normalized()
			var source_normal := (
				(source_vertices[b_index] - source_vertices[a_index]).cross(
					source_vertices[c_index] - source_vertices[a_index]
				)
			).normalized()
			if local_normal.dot(ray_direction) > 0.0:
				local_normal = -local_normal
				source_normal = -source_normal
			best = {
				"surface": surface_index,
				"local_position": local_position,
				"local_normal": local_normal,
				"source_position": source_position,
				"source_normal": source_normal,
			}
	return best


func _ray_triangle_barycentric(
	ray_origin: Vector3,
	ray_direction: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3,
) -> Vector3:
	var edge_ab := b - a
	var edge_ac := c - a
	var perpendicular := ray_direction.cross(edge_ac)
	var determinant := edge_ab.dot(perpendicular)
	if absf(determinant) < 0.0000001:
		return Vector3(-1.0, 0.0, 0.0)
	var inverse_determinant := 1.0 / determinant
	var origin_delta := ray_origin - a
	var u := origin_delta.dot(perpendicular) * inverse_determinant
	if u < 0.0 or u > 1.0:
		return Vector3(-1.0, 0.0, 0.0)
	var cross_delta := origin_delta.cross(edge_ab)
	var v := ray_direction.dot(cross_delta) * inverse_determinant
	if v < 0.0 or u + v > 1.0:
		return Vector3(-1.0, 0.0, 0.0)
	var distance := edge_ac.dot(cross_delta) * inverse_determinant
	if distance <= 0.00001:
		return Vector3(-1.0, 0.0, 0.0)
	return Vector3(distance, u, v)


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
		"pair_center_position": _fit.pair_center_position,
		"position": _fit.position,
		"rotation_degrees": _fit.rotation_degrees,
		"scale": _fit.scale,
		"torso_width": _fit.torso_width,
		"torso_depth": _fit.torso_depth,
		"top_section_scale": _fit.top_section_scale,
		"middle_section_scale": _fit.middle_section_scale,
		"bottom_section_scale": _fit.bottom_section_scale,
		"sleeve_lift": _fit.sleeve_lift,
		"sleeve_length": _fit.sleeve_length,
		"sleeve_room": _fit.sleeve_room,
		"shoulder_lift": _fit.shoulder_lift,
		"cuff_radius": _fit.cuff_radius,
		"cuff_forward": _fit.cuff_forward,
		"surface_smoothing": _fit.surface_smoothing,
		"detail_erase_strokes": _fit.detail_erase_strokes.duplicate(true),
		"hidden_regions": _fit.hidden_regions.duplicate(),
		"landmarks": _landmarks.duplicate(true),
	}


func _apply_fit_snapshot(snapshot: Dictionary) -> void:
	if _fit == null or snapshot.is_empty():
		return
	_history_restoring = true
	_fit.pair_center_position = snapshot.get(
		"pair_center_position",
		Vector3.ZERO,
	)
	_fit.position = snapshot["position"]
	_fit.rotation_degrees = snapshot["rotation_degrees"]
	_fit.scale = snapshot["scale"]
	for property_name in FIT_SCALAR_KEYS:
		_fit.set(property_name, snapshot[property_name])
	_fit.detail_erase_strokes.clear()
	for stroke in snapshot.get("detail_erase_strokes", []):
		_fit.detail_erase_strokes.append(
			(stroke as Dictionary).duplicate(true)
		)
	_fit.hidden_regions = snapshot["hidden_regions"].duplicate()
	_landmarks = (
		snapshot.get("landmarks", _landmarks) as Dictionary
	).duplicate(true)
	_store_landmarks_in_body_profile()
	_history_restoring = false
	_refresh_ui_from_fit()
	_refresh_landmark_markers()
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
		"pair_center":
			vector = _fit.pair_center_position
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
	if slot == CharacterSlots.SHOES:
		fit.garment_class = "footwear"
	elif slot == CharacterSlots.BOTTOM:
		fit.garment_class = "lower_body"
	else:
		fit.garment_class = "upper_body"
	var default_regions: Array[String] = []
	if fit.garment_class == "footwear":
		default_regions.assign(["foot_l", "foot_r"])
	elif fit.garment_class == "lower_body":
		default_regions.assign([
			"hips",
			"thigh_l",
			"knee_l",
			"shin_l",
			"thigh_r",
			"knee_r",
			"shin_r",
		])
	else:
		default_regions.assign(DEFAULT_JACKET_REGIONS)
	for region in default_regions:
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
	_select_clothing_list_part(part.part_id)


func _select_clothing_list_part(part_id: String) -> void:
	if _clothing_list == null:
		return
	for index in _clothing_list.item_count:
		if String(_clothing_list.get_item_metadata(index)) == part_id:
			_clothing_list.select(index)
			_clothing_list.ensure_current_is_visible()
			return


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
	_cache_preview_ground_bounds()
	_ground_preview_character()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	_load_raw_preview(_fit.source_file)
	_restore_preview_pose()
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
	_cache_preview_ground_bounds()
	_ground_preview_character()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	_load_raw_preview(_fit.source_file)
	_restore_preview_pose()
	_validate()


func _on_appearance_selected(slot: String, index: int) -> void:
	var option := _slot_options.get(slot) as OptionButton
	if option == null:
		return
	var part_id := String(option.get_item_metadata(index))
	var replacement: CharacterPartDefinition
	if part_id.is_empty():
		replacement = null
	else:
		var path := String(_part_paths.get(part_id, ""))
		replacement = load(path) as CharacterPartDefinition
		if replacement == null:
			return
	if (
		replacement != null
		and slot in CLOTHING_SLOTS
		and replacement.attachment_type
		== CharacterPartDefinition.ATTACHMENT_SKINNED
	):
		# Appearance and editing selection are one state for skinned garments.
		# Otherwise the bound character equips the new part while Rest/T-pose
		# keeps drawing the previous raw garment in the same slot.
		_select_clothing_part(replacement)
		_select_clothing_list_part(replacement.part_id)
		_refresh_ui_from_fit()
		_validate()
		return
	_replace_part_in_preset(slot, replacement)
	_rebuild()
	_force_rest_pose()
	_cache_preview_ground_bounds()
	_ground_preview_character()
	_measure_rest_landmarks()
	_refresh_landmark_markers()
	_apply_body_mask()
	if _fit != null and _selected_part_is_equipped():
		_load_raw_preview(_fit.source_file)
	else:
		_apply_garment_preview_visibility()
	_restore_preview_pose()
	_refresh_ui_from_fit()
	_validate()


func _refresh_ui_from_fit() -> void:
	if _fit == null:
		return
	_source_path.text = _fit.source_file
	_fit.symmetric = true
	if _pair_center_controls_root != null:
		_pair_center_controls_root.visible = (
			_fit.garment_class == "footwear"
		)
	_set_vector_controls("pair_center", _fit.pair_center_position)
	_set_vector_controls("position", _fit.position)
	_set_vector_controls("rotation", _fit.rotation_degrees)
	_set_vector_controls("scale", _fit.scale)
	for key in _fit_controls:
		(_fit_controls[key] as SpinBox).set_value_no_signal(
			float(_fit.get(key))
		)
	if _surface_smoothing_slider != null:
		_surface_smoothing_slider.set_value_no_signal(
			_fit.surface_smoothing
		)
		_update_surface_smoothing_readout(_fit.surface_smoothing)
	_refresh_detail_eraser_ui()
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
		option.select(0)
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


func _on_vector_changed(key: String, axis_index: int = -1) -> void:
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
		"pair_center":
			_fit.pair_center_position = value
		"position":
			_fit.position = value
		"rotation":
			_fit.rotation_degrees = value
		"scale":
			if (
				_lock_scale_proportions != null
				and _lock_scale_proportions.button_pressed
				and axis_index >= 0
				and axis_index < 3
			):
				_fit.scale = _proportional_scale_for_axis(
					axis_index, value[axis_index], controls
				)
				_set_vector_controls("scale", _fit.scale)
			else:
				_fit.scale = value
	_preview_fit()
	_update_revert_buttons()


func _proportional_scale_for_axis(
	axis_index: int,
	requested_value: float,
	controls: Array,
) -> Vector3:
	var current := _fit.scale
	var current_axis: float = current[axis_index]
	if absf(current_axis) <= 0.000001:
		return current
	var factor := requested_value / current_axis
	for component_index in 3:
		var component_value: float = current[component_index]
		if absf(component_value) <= 0.000001:
			continue
		var spin := controls[component_index] as SpinBox
		if spin == null:
			continue
		factor = clampf(
			factor,
			spin.min_value / component_value,
			spin.max_value / component_value,
		)
	return current * factor


func _preview_fit() -> void:
	if _fit == null or _raw_preview == null:
		_validate()
		return
	_fit.symmetric = true
	_fit_revision += 1
	_invalidate_final_output()
	_update_raw_preview_mesh()
	_apply_live_bound_surface_smoothing()
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
	if _marker_editing:
		return
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
		not _marker_editing
		and _preview_hidden_regions != null
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
	_refresh_underlayer_preview()


func _refresh_underlayer_preview() -> void:
	if _underlayer_preview != null and is_instance_valid(_underlayer_preview):
		_underlayer_preview.visible = false
		_underlayer_preview.queue_free()
	_underlayer_preview = null
	if (
		_character == null
		or _fit == null
		or _fit.hidden_regions.is_empty()
		or _marker_editing
		or _preview_hidden_regions == null
		or not _preview_hidden_regions.button_pressed
	):
		return
	var body_mesh := _character.find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	var skeleton := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if body_mesh == null or skeleton == null:
		return
	var material_sources: Array[MeshInstance3D] = []
	if _raw_preview != null and is_instance_valid(_raw_preview):
		material_sources.append(_raw_preview)
	elif _final_preview_root != null and is_instance_valid(_final_preview_root):
		for child in _final_preview_root.find_children(
			"*", "MeshInstance3D", true, false
		):
			material_sources.append(child as MeshInstance3D)
	if material_sources.is_empty():
		return
	_underlayer_preview = ClothingUnderlayerBuilder.build(
		body_mesh,
		skeleton,
		_fit.hidden_regions,
		material_sources,
		"ClothingLabUnderlayerPreview",
		0.0012,
	)
	if _underlayer_preview == null:
		return
	skeleton.add_child(_underlayer_preview)
	_underlayer_preview.visible = false
	_apply_garment_preview_visibility()


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


func _cache_preview_ground_bounds() -> void:
	_has_preview_ground_bounds = false
	if _character == null:
		return
	_preview_ground_bounds = _visual_bounds(_character)
	_has_preview_ground_bounds = true


## Preview clips carry an authored Mixamo hips baseline and natural vertical
## gait. Keep that motion inside the skeleton while translating the character
## root just enough for the lowest animated toe to remain on the stage.
func _ground_preview_character() -> void:
	if _character == null:
		return
	if not _has_preview_ground_bounds:
		_cache_preview_ground_bounds()
	if not _has_preview_ground_bounds:
		return
	var skeleton := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if skeleton == null:
		_character.position.y = -_preview_ground_bounds.position.y
		return
	var skeleton_to_character := (
		_character.global_transform.affine_inverse()
		* skeleton.global_transform
	)
	var lowest_rest_y := INF
	var lowest_animated_y := INF
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := skeleton.find_bone(toe_name)
		if toe_index < 0:
			continue
		var rest_y := (
			skeleton_to_character
			* skeleton.get_bone_global_rest(toe_index)
		).origin.y
		var animated_y := (
			skeleton_to_character
			* skeleton.get_bone_global_pose(toe_index)
		).origin.y
		lowest_rest_y = minf(lowest_rest_y, rest_y)
		lowest_animated_y = minf(lowest_animated_y, animated_y)
	if is_inf(lowest_rest_y) or is_inf(lowest_animated_y):
		_character.position.y = -_preview_ground_bounds.position.y
		return
	var sole_margin := _preview_ground_bounds.position.y - lowest_rest_y
	_character.position.y = -(lowest_animated_y + sole_margin)


func _restore_preview_pose() -> void:
	_ensure_preview_animations()
	if _preview_pose_option == null:
		_force_rest_pose()
		return
	_on_preview_pose_selected(_preview_pose_option.selected)


func _ensure_preview_animations() -> void:
	if _character == null:
		return
	var animation_player := _character.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	var skeleton := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	var profile := load(PLAYER_PROFILE_PATH) as PlayerAssetProfile
	if animation_player == null or skeleton == null or profile == null:
		return
	animation_player.callback_mode_process = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	animation_player.active = true
	if _preview_speed_slider != null:
		animation_player.speed_scale = _preview_speed_slider.value
	var library := animation_player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library("", library)
	if animation_player.has_animation(profile.idle_clip_name):
		animation_player.get_animation(profile.idle_clip_name).loop_mode = (
			Animation.LOOP_LINEAR
		)
	var sources: Dictionary = {
		profile.walk_clip_name: profile.walk_animation,
	}
	for action_name in profile.action_animations:
		sources[String(action_name)] = profile.action_animations[action_name]
	for clip_name in sources:
		var source := sources[clip_name] as Animation
		if source == null:
			continue
		var clip := source.duplicate(true) as Animation
		clip.resource_name = String(clip_name)
		# A clothing preview is easier to inspect when every selection repeats.
		clip.loop_mode = Animation.LOOP_LINEAR
		_retarget_preview_animation(clip, animation_player, skeleton)
		PlayerAnimationUtils.normalize_in_place(clip, profile.hips_bone)
		if library.has_animation(StringName(clip_name)):
			library.remove_animation(StringName(clip_name))
		library.add_animation(StringName(clip_name), clip)


func _retarget_preview_animation(
	animation: Animation,
	animation_player: AnimationPlayer,
	skeleton: Skeleton3D,
) -> void:
	var animation_root := animation_player.get_node_or_null(
		animation_player.root_node
	)
	if animation_root == null:
		return
	var skeleton_path := animation_root.get_path_to(skeleton)
	for track_index in animation.get_track_count():
		var source_path := String(animation.track_get_path(track_index))
		if not source_path.contains(":"):
			continue
		var bone_name := source_path.get_slice(":", 1)
		if skeleton.find_bone(bone_name) < 0:
			continue
		animation.track_set_path(
			track_index,
			NodePath("%s:%s" % [skeleton_path, bone_name]),
		)


func _on_preview_pose_selected(index: int) -> void:
	if _preview_pose_option == null or _character == null:
		return
	if index < 0 or index >= _preview_pose_option.item_count:
		return
	var clip_name := String(_preview_pose_option.get_item_metadata(index))
	if _marker_editing and not clip_name.is_empty():
		_set_marker_edit_mode(false)
	if clip_name.is_empty():
		_force_rest_pose()
		_ground_preview_character()
		if _preview_mode_option != null:
			_preview_mode_option.select(0)
		if _final_preview_root != null and is_instance_valid(_final_preview_root):
			var final_skeleton := _final_preview_root.find_child(
				"Skeleton3D", true, false
			) as Skeleton3D
			if final_skeleton != null:
				final_skeleton.reset_bone_poses()
	else:
		_ensure_preview_animations()
		var animation_player := _character.find_child(
			"AnimationPlayer", true, false
		) as AnimationPlayer
		if animation_player != null and animation_player.has_animation(clip_name):
			animation_player.play(clip_name)
			animation_player.seek(0.0, true)
			_ground_preview_character()
		if _preview_mode_option != null and _bound_preview_available():
			_preview_mode_option.set_item_disabled(1, false)
			_preview_mode_option.select(1)
	_apply_garment_preview_visibility()
	_update_marker_visibility()
	_validate()


func _on_preview_speed_changed(value: float) -> void:
	if _preview_speed_label != null:
		_preview_speed_label.text = "%.2f×" % value
	if _character == null:
		return
	var animation_player := _character.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	if animation_player != null:
		animation_player.speed_scale = value


func _selected_preview_clip() -> String:
	if _preview_pose_option == null:
		return ""
	var index := _preview_pose_option.selected
	if index < 0 or index >= _preview_pose_option.item_count:
		return ""
	return String(_preview_pose_option.get_item_metadata(index))


func _sync_final_output_pose() -> void:
	if (
		_selected_preview_clip().is_empty()
		or _character == null
		or _final_preview_root == null
		or not is_instance_valid(_final_preview_root)
	):
		return
	var source := _character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	var target := _final_preview_root.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	if source == null or target == null:
		return
	for target_index in target.get_bone_count():
		var source_index := source.find_bone(target.get_bone_name(target_index))
		if source_index < 0:
			continue
		target.set_bone_pose_position(
			target_index, source.get_bone_pose_position(source_index)
		)
		target.set_bone_pose_rotation(
			target_index, source.get_bone_pose_rotation(source_index)
		)
		target.set_bone_pose_scale(
			target_index, source.get_bone_pose_scale(source_index)
		)


func _measure_rest_landmarks() -> void:
	_landmarks.clear()
	_default_landmarks.clear()
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
	_default_landmarks = {
		"center": {},
		"left": {},
		"right": {},
	}
	for marker_key in LANDMARK_BONES:
		var parts := String(marker_key).split(".", false, 1)
		if parts.size() != 2:
			continue
		var bone_index := skeleton.find_bone(String(LANDMARK_BONES[marker_key]))
		if bone_index < 0:
			continue
		var points := _default_landmarks[parts[0]] as Dictionary
		points[parts[1]] = (
			skeleton_to_character
			* skeleton.get_bone_global_rest(bone_index).origin
		)
		_default_landmarks[parts[0]] = points

	var center := _default_landmarks["center"] as Dictionary
	var head_position: Vector3 = center.get("head", Vector3(0.0, 0.3, 0.0))
	var body_profile := _active_body_profile()
	if body_profile != null and body_profile.face_sockets.has("HatSocket"):
		center["crown"] = body_profile.face_sockets["HatSocket"]
	else:
		center["crown"] = head_position + Vector3.UP * 0.16
	if body_profile != null and body_profile.face_sockets.has("FaceRoot"):
		center["face"] = body_profile.face_sockets["FaceRoot"]
	else:
		center["face"] = head_position + Vector3(0.0, 0.08, 0.08)
	_default_landmarks["center"] = center

	for side in ["left", "right"]:
		var points := _default_landmarks[side] as Dictionary
		if points.has("ankle") and points.has("toe"):
			points["foot"] = (
				(points["ankle"] as Vector3).lerp(points["toe"] as Vector3, 0.55)
			)
		_default_landmarks[side] = points

	_landmarks = _default_landmarks.duplicate(true)
	if body_profile == null:
		return
	_migrate_profile_landmarks_to_character_space(body_profile)
	for marker_key in body_profile.clothing_landmarks:
		var parts := String(marker_key).split(".", false, 1)
		if parts.size() != 2 or not _landmarks.has(parts[0]):
			continue
		# Profiles saved by the original arm-only editor called the elbow
		# "forearm". Migrate that metadata without carrying the ambiguity into
		# the global full-body rig.
		if parts[1] == "forearm":
			parts[1] = "elbow"
		var points := _landmarks[parts[0]] as Dictionary
		if points.has(parts[1]):
			points[parts[1]] = body_profile.clothing_landmarks[marker_key]


func _migrate_profile_landmarks_to_character_space(
	body_profile: CharacterBodyProfile,
) -> void:
	if not _profile_landmarks_use_blender_axes(body_profile):
		return
	# Clothing Lab edits and renders markers in the Godot character's local
	# space (+Y up). The fitting processor alone uses Blender's +Z-up basis.
	# Some early profile saves accidentally persisted the processor values;
	# migrate the complete set as one basis change so authored offsets survive.
	for marker_key in body_profile.clothing_landmarks.keys():
		var processor_point: Vector3 = (
			body_profile.clothing_landmarks[marker_key]
		)
		body_profile.clothing_landmarks[marker_key] = Vector3(
			processor_point.x,
			processor_point.z,
			-processor_point.y,
		)


func _profile_landmarks_use_blender_axes(
	body_profile: CharacterBodyProfile,
) -> bool:
	if (
		body_profile == null
		or body_profile.clothing_landmarks.size() < 3
		or _default_landmarks.is_empty()
	):
		return false
	var direct_error := 0.0
	var converted_error := 0.0
	var sample_count := 0
	for marker_key in LANDMARK_ORDER:
		if not body_profile.clothing_landmarks.has(marker_key):
			continue
		var parts := String(marker_key).split(".", false, 1)
		if parts.size() != 2 or not _default_landmarks.has(parts[0]):
			continue
		var default_points := _default_landmarks[parts[0]] as Dictionary
		if not default_points.has(parts[1]):
			continue
		var stored_point: Vector3 = (
			body_profile.clothing_landmarks[marker_key]
		)
		var converted_point := Vector3(
			stored_point.x,
			stored_point.z,
			-stored_point.y,
		)
		var rest_point: Vector3 = default_points[parts[1]]
		direct_error += stored_point.distance_squared_to(rest_point)
		converted_error += converted_point.distance_squared_to(rest_point)
		sample_count += 1
	if sample_count < 3:
		return false
	# Require both a strong relative win and a meaningful absolute win. This
	# prevents unusual but valid artist-authored offsets from being "fixed".
	return (
		converted_error < direct_error * 0.45
		and direct_error - converted_error > 0.01
	)


func _refresh_landmark_markers() -> void:
	if _marker_root != null and is_instance_valid(_marker_root):
		_marker_root.queue_free()
	_marker_nodes.clear()
	if _character == null or _landmarks.is_empty():
		return
	_marker_root = Node3D.new()
	_marker_root.name = "ClothingLandmarkMarkers"
	_character.add_child(_marker_root)
	_update_marker_visibility()
	var colors := {
		"crown": Color("#f08fc7"),
		"head": Color("#cf8cff"),
		"face": Color("#ff9e81"),
		"neck": Color("#ffd27a"),
		"chest": Color("#a5df85"),
		"abdomen": Color("#7fcf9a"),
		"waist": Color("#64c6b5"),
		"hips": Color("#63aee6"),
		"clavicle": Color("#f0d26e"),
		"shoulder": Color("#ffbc62"),
		"elbow": Color("#75d5d0"),
		"wrist": Color("#d7ed9b"),
		"hand": Color("#ee88a8"),
		"hip": Color("#74aee8"),
		"knee": Color("#9a8ee8"),
		"ankle": Color("#66c7c1"),
		"foot": Color("#76bede"),
		"toe": Color("#ed8bad"),
	}
	for marker_key in LANDMARK_ORDER:
		var parts := String(marker_key).split(".", false, 1)
		if parts.size() != 2 or not _landmarks.has(parts[0]):
			continue
		var points := _landmarks[parts[0]] as Dictionary
		if not points.has(parts[1]):
			continue
		var marker := MeshInstance3D.new()
		marker.name = "RigMarker_%s_%s" % [parts[0], parts[1]]
		marker.set_meta("landmark_key", marker_key)
		var base_color: Color = colors.get(parts[1], Color.WHITE)
		marker.set_meta("base_color", base_color)
		var sphere := SphereMesh.new()
		sphere.radius = 0.018
		sphere.height = 0.036
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = base_color
		material.emission_enabled = true
		material.emission = base_color
		# Transparent-pass + no depth test makes fitting landmarks a true
		# editor overlay: the body and garment can never cover them.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.render_priority = 127
		sphere.material = material
		marker.mesh = sphere
		marker.position = points[parts[1]]
		marker.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_marker_root.add_child(marker)
		_marker_nodes[marker_key] = marker
	_refresh_marker_selection_visuals()


func _active_body_profile() -> CharacterBodyProfile:
	if preset == null or preset.body_profile == null:
		return null
	for body_profile in _body_profiles:
		if body_profile.profile_id == preset.body_profile.profile_id:
			return body_profile
	return preset.body_profile


func _store_landmarks_in_body_profile() -> void:
	var body_profile := _active_body_profile()
	if body_profile == null:
		return
	body_profile.clothing_landmarks.clear()
	for side in _landmarks:
		for marker_name in (_landmarks[side] as Dictionary):
			body_profile.clothing_landmarks[
				"%s.%s" % [side, marker_name]
			] = (_landmarks[side] as Dictionary)[marker_name]


func _set_marker_edit_mode(enabled: bool) -> void:
	if enabled and _detail_erase_enabled:
		_set_detail_erase_mode(false)
	var was_editing := _marker_editing
	if enabled and _preview_pose_option != null:
		_preview_pose_option.select(0)
		_on_preview_pose_selected(0)
	_marker_editing = enabled
	if enabled and not was_editing:
		if _marker_toggle != null:
			_marker_visibility_before_edit = _marker_toggle.button_pressed
		_set_marker_clothing_isolation(true)
	elif not enabled and was_editing:
		_set_marker_clothing_isolation(false)
	if _marker_edit_button != null:
		_marker_edit_button.set_pressed_no_signal(enabled)
		_marker_edit_button.text = (
			"Done editing rig markers" if enabled else "Edit rig markers"
		)
	if _marker_editor != null:
		_marker_editor.visible = enabled
	if _marker_toggle != null:
		_marker_toggle.disabled = enabled
		if enabled:
			_marker_toggle.set_pressed_no_signal(true)
		else:
			_marker_toggle.set_pressed_no_signal(
				_marker_visibility_before_edit
			)
	_update_marker_visibility()
	if enabled:
		_select_landmark_marker(_selected_marker_key)
	elif not _marker_drag_key.is_empty():
		_end_marker_drag(true)


func _update_marker_visibility() -> void:
	if _marker_root == null:
		return
	_marker_root.visible = (
		not _detail_erase_enabled
		and (
			_marker_editing
			or (
				_selected_preview_clip().is_empty()
				and (
					_marker_toggle == null
					or _marker_toggle.button_pressed
				)
			)
		)
	)


func _set_marker_clothing_isolation(enabled: bool) -> void:
	if enabled:
		_clothing_slot_visibility_before_marker_edit.clear()
		for slot in CLOTHING_SLOTS:
			var equipped := assembler.equipped_node(slot)
			if equipped == null:
				continue
			_clothing_slot_visibility_before_marker_edit[slot] = (
				equipped.visible
			)
			assembler.set_slot_visible(slot, false)
		if _show_equipped_clothing != null:
			_garment_visibility_before_marker_edit = (
				_show_equipped_clothing.button_pressed
			)
			_show_equipped_clothing.set_pressed_no_signal(false)
			_show_equipped_clothing.disabled = true
		if _preview_hidden_regions != null:
			_body_mask_preview_before_marker_edit = (
				_preview_hidden_regions.button_pressed
			)
			_preview_hidden_regions.set_pressed_no_signal(false)
			_preview_hidden_regions.disabled = true
	else:
		for slot in _clothing_slot_visibility_before_marker_edit:
			assembler.set_slot_visible(
				slot,
				bool(_clothing_slot_visibility_before_marker_edit[slot]),
			)
		_clothing_slot_visibility_before_marker_edit.clear()
		if _show_equipped_clothing != null:
			_show_equipped_clothing.set_pressed_no_signal(
				_garment_visibility_before_marker_edit
			)
			_show_equipped_clothing.disabled = false
		if _preview_hidden_regions != null:
			_preview_hidden_regions.set_pressed_no_signal(
				_body_mask_preview_before_marker_edit
			)
			_preview_hidden_regions.disabled = false
	_apply_garment_preview_visibility()
	_apply_body_mask()


func _select_landmark_marker(marker_key: String) -> void:
	if not _marker_nodes.has(marker_key):
		return
	_selected_marker_key = marker_key
	var group_name := _landmark_group_for_key(marker_key)
	if _marker_group_option != null:
		for group_index in _marker_group_option.item_count:
			if (
				String(_marker_group_option.get_item_metadata(group_index))
				== group_name
			):
				if _marker_group_option.selected != group_index:
					_marker_group_option.select(group_index)
					_populate_marker_option(group_name)
				break
	if _marker_option != null:
		for index in _marker_option.item_count:
			if String(_marker_option.get_item_metadata(index)) == marker_key:
				_marker_option.select(index)
				break
	_refresh_marker_selection_visuals()


func _refresh_marker_selection_visuals() -> void:
	for marker_key in _marker_nodes:
		var marker := _marker_nodes[marker_key] as MeshInstance3D
		if marker == null:
			continue
		var selected: bool = String(marker_key) == _selected_marker_key
		marker.scale = Vector3.ONE * (1.35 if selected else 1.0)
		var sphere := marker.mesh as SphereMesh
		var material := (
			sphere.material as StandardMaterial3D
			if sphere != null
			else null
		)
		if material == null:
			continue
		var base_color: Color = marker.get_meta("base_color", Color.WHITE)
		material.albedo_color = (
			base_color.lightened(0.22) if selected else base_color
		)
		material.emission = material.albedo_color


func _pick_landmark_marker(screen_position: Vector2) -> String:
	if (
		not _marker_editing
		or _marker_root == null
		or not _marker_root.visible
	):
		return ""
	var camera := _active_preview_camera()
	if camera == null:
		return ""
	var best_key := ""
	var best_distance := LANDMARK_PICK_RADIUS
	for marker_key in _marker_nodes:
		var marker := _marker_nodes[marker_key] as MeshInstance3D
		if (
			marker == null
			or not marker.visible
			or camera.is_position_behind(marker.global_position)
		):
			continue
		var distance := camera.unproject_position(
			marker.global_position
		).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best_key = marker_key
	return best_key


func _begin_marker_drag(screen_position: Vector2) -> bool:
	var marker_key := _pick_landmark_marker(screen_position)
	if marker_key.is_empty():
		return false
	var marker := _marker_nodes[marker_key] as MeshInstance3D
	var camera := _active_preview_camera()
	if marker == null or camera == null:
		return false
	_select_landmark_marker(marker_key)
	_marker_drag_key = marker_key
	_marker_drag_origin = marker.position
	_marker_drag_screen_origin = screen_position
	_marker_drag_plane = Plane(
		-camera.global_basis.z.normalized(), marker.global_position
	)
	_marker_drag_snapshot = _capture_fit_snapshot()
	return true


func _drag_marker(screen_position: Vector2) -> void:
	if _marker_drag_key.is_empty() or _character == null:
		return
	var camera := _active_preview_camera()
	if camera == null:
		return
	var hit: Variant = _marker_drag_plane.intersects_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position),
	)
	if hit == null:
		return
	var local_position := (
		_character.global_transform.affine_inverse() * (hit as Vector3)
	)
	local_position = _axis_constrained_marker_position(
		camera, screen_position, local_position
	)
	_set_landmark_position(_marker_drag_key, local_position)
	_preview_fit()


func _held_marker_drag_axis() -> Vector3:
	if Input.is_key_pressed(KEY_X):
		return Vector3.RIGHT
	if Input.is_key_pressed(KEY_Y):
		return Vector3.UP
	if Input.is_key_pressed(KEY_Z):
		return Vector3.BACK
	return Vector3.ZERO


func _axis_constrained_marker_position(
	camera: Camera3D,
	screen_position: Vector2,
	unconstrained_position: Vector3,
) -> Vector3:
	var axis := _held_marker_drag_axis()
	if axis == Vector3.ZERO or _character == null:
		return unconstrained_position

	# Project the selected character-space axis into screen space, then project
	# the pointer motion onto that line. This gives the familiar DCC behavior
	# at any orbit angle while guaranteeing the other two coordinates remain
	# bit-for-bit unchanged.
	const SAMPLE_LENGTH := 0.2
	var origin_world := _character.global_transform * _marker_drag_origin
	var axis_world := (
		_character.global_transform
		* (_marker_drag_origin + axis * SAMPLE_LENGTH)
	)
	var origin_screen := camera.unproject_position(origin_world)
	var axis_screen := camera.unproject_position(axis_world) - origin_screen
	var distance_along_axis := 0.0
	if axis_screen.length_squared() > 1.0:
		distance_along_axis = (
			(screen_position - _marker_drag_screen_origin).dot(
				axis_screen.normalized()
			)
			* SAMPLE_LENGTH
			/ axis_screen.length()
		)
	else:
		# When looking exactly down the locked axis it has no screen-space
		# direction. Keep it usable with a predictable horizontal/vertical
		# depth gesture scaled to the preview camera.
		var viewport_height := maxf(
			1.0, get_viewport().get_visible_rect().size.y
		)
		var pointer_delta := screen_position - _marker_drag_screen_origin
		distance_along_axis = (
			(pointer_delta.x - pointer_delta.y)
			* camera.size
			/ viewport_height
		)
	return _marker_drag_origin + axis * distance_along_axis


func _end_marker_drag(commit: bool) -> void:
	if _marker_drag_key.is_empty():
		return
	var before := _marker_drag_snapshot.duplicate(true)
	_marker_drag_key = ""
	_marker_drag_origin = Vector3.ZERO
	_marker_drag_screen_origin = Vector2.ZERO
	_marker_drag_snapshot.clear()
	if not commit:
		if not before.is_empty():
			_apply_fit_snapshot(before)
		return
	if not before.is_empty() and before != _capture_fit_snapshot():
		_push_undo_snapshot(before)


func _set_landmark_position(marker_key: String, position: Vector3) -> void:
	var parts := marker_key.split(".", false, 1)
	if parts.size() != 2 or not _landmarks.has(parts[0]):
		return
	var points := _landmarks[parts[0]] as Dictionary
	if not points.has(parts[1]):
		return
	points[parts[1]] = position
	_landmarks[parts[0]] = points
	if (
		parts[0] in ["left", "right"]
		and (_marker_mirror == null or _marker_mirror.button_pressed)
	):
		var opposite_side := "right" if parts[0] == "left" else "left"
		var opposite_points := _landmarks.get(opposite_side, {}) as Dictionary
		if opposite_points.has(parts[1]):
			opposite_points[parts[1]] = Vector3(
				-position.x, position.y, position.z
			)
			_landmarks[opposite_side] = opposite_points
	_store_landmarks_in_body_profile()
	for key in _marker_nodes:
		var key_parts := String(key).split(".", false, 1)
		var marker := _marker_nodes[key] as MeshInstance3D
		if (
			key_parts.size() == 2
			and marker != null
			and _landmarks.has(key_parts[0])
		):
			marker.position = (
				_landmarks[key_parts[0]] as Dictionary
			).get(key_parts[1], marker.position)


func _nudge_selected_marker(direction: Vector3) -> void:
	if not _marker_editing or not _marker_nodes.has(_selected_marker_key):
		return
	var parts := _selected_marker_key.split(".", false, 1)
	var points := _landmarks.get(parts[0], {}) as Dictionary
	if not points.has(parts[1]):
		return
	var step := (
		LANDMARK_FINE_NUDGE_STEP
		if Input.is_key_pressed(KEY_SHIFT)
		else LANDMARK_NUDGE_STEP
	)
	_begin_history_batch()
	_set_landmark_position(
		_selected_marker_key,
		(points[parts[1]] as Vector3) + direction * step,
	)
	_preview_fit()
	_end_history_batch()


func _reset_landmarks_to_skeleton() -> void:
	if _default_landmarks.is_empty():
		return
	_begin_history_batch()
	_landmarks = _default_landmarks.duplicate(true)
	var body_profile := _active_body_profile()
	if body_profile != null:
		body_profile.clothing_landmarks.clear()
	_refresh_landmark_markers()
	_preview_fit()
	_end_history_batch()


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
		# Keep existing garment processors compatible with configs produced by
		# the old arm-only editor while the canonical UI uses the correct name.
		if converted.has("elbow"):
			converted["forearm"] = converted["elbow"]
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
		_detail_brush_cursor = null
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
	if _selected_part_is_equipped():
		assembler.set_slot_visible(_selected_part.slot, false)
	if _marker_editing:
		for slot in CLOTHING_SLOTS:
			assembler.set_slot_visible(slot, false)
	_apply_garment_preview_visibility()
	_refresh_underlayer_preview()
	_focus_character()
	_validate()


func _invalidate_final_output() -> void:
	_final_output_revision = -1
	_final_output_path = ""
	_final_geometry_changed = false
	if _accept_final_check != null:
		_accept_final_check.set_pressed_no_signal(false)
		_accept_final_check.disabled = true
	if _final_preview_root != null and is_instance_valid(_final_preview_root):
		_final_preview_root.queue_free()
		_final_preview_root = null
	if _preview_mode_option != null:
		var live_bound_available := _live_bound_preview_available()
		_preview_mode_option.set_item_disabled(1, not live_bound_available)
		if not live_bound_available:
			_preview_mode_option.select(0)
	_apply_garment_preview_visibility()


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
	_restore_preview_pose()
	_sync_final_output_pose()
	_validate()
	return true


func _on_preview_mode_selected(index: int) -> void:
	if index == 1 and not _bound_preview_available():
		_preview_mode_option.select(0)
		index = 0
	var show_final := (
		index == 1
		and _final_preview_root != null
		and is_instance_valid(_final_preview_root)
	)
	if _accept_final_check != null:
		_accept_final_check.disabled = not show_final
	_apply_garment_preview_visibility()
	_validate()


func _live_bound_preview_available() -> bool:
	if not _selected_part_is_equipped():
		return false
	var equipped := assembler.equipped_part(_selected_part.slot)
	return (
		equipped != null
		and equipped.part_id == _selected_part.part_id
		and assembler.equipped_node(_selected_part.slot) != null
	)


func _selected_part_is_equipped() -> bool:
	if _selected_part == null or preset == null:
		return false
	var equipped := preset.part_in_slot(_selected_part.slot)
	return (
		equipped != null
		and equipped.part_id == _selected_part.part_id
	)


func _bound_preview_available() -> bool:
	return (
		(
			_final_preview_root != null
			and is_instance_valid(_final_preview_root)
		)
		or _live_bound_preview_available()
	)


func _apply_garment_preview_visibility() -> void:
	var garment_visible := (
		not _marker_editing
		and (
			_show_equipped_clothing == null
			or _show_equipped_clothing.button_pressed
		)
	)
	var wants_bound := (
		_preview_mode_option != null
		and _preview_mode_option.selected == 1
	)
	if not _selected_preview_clip().is_empty():
		wants_bound = true
	var show_final := (
		garment_visible
		and wants_bound
		and _final_preview_root != null
		and is_instance_valid(_final_preview_root)
	)
	var show_live_bound := (
		garment_visible
		and wants_bound
		and not show_final
		and _live_bound_preview_available()
	)
	var selected_equipped := _selected_part_is_equipped()
	if selected_equipped:
		assembler.set_slot_visible(_selected_part.slot, show_live_bound)
	var show_raw := garment_visible and not wants_bound and selected_equipped
	if _raw_preview != null and is_instance_valid(_raw_preview):
		_raw_preview.visible = show_raw
	if _final_preview_root != null and is_instance_valid(_final_preview_root):
		_final_preview_root.visible = show_final
	if _underlayer_preview != null and is_instance_valid(_underlayer_preview):
		_underlayer_preview.visible = (
			garment_visible
			and not show_live_bound
			and (show_raw or show_final)
			and _preview_hidden_regions != null
			and _preview_hidden_regions.button_pressed
		)


func _mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size()
	return total


func _section_scale_at_height(
	height: float,
	minimum_height: float,
	maximum_height: float,
) -> float:
	if _fit == null:
		return 1.0
	var height_range := maximum_height - minimum_height
	if height_range <= 0.000001:
		return _fit.middle_section_scale
	var normalized := clampf(
		(height - minimum_height) / height_range,
		0.0,
		1.0,
	)
	if normalized <= 0.5:
		var blend := _smooth_section_blend(normalized * 2.0)
		return lerpf(
			_fit.bottom_section_scale,
			_fit.middle_section_scale,
			blend,
		)
	var blend := _smooth_section_blend((normalized - 0.5) * 2.0)
	return lerpf(
		_fit.middle_section_scale,
		_fit.top_section_scale,
		blend,
	)


func _smooth_section_blend(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _scaled_surface_height_bounds(
	surfaces: Array[PackedVector3Array],
) -> Vector2:
	var minimum_height := INF
	var maximum_height := -INF
	for surface in surfaces:
		for point in surface:
			minimum_height = minf(minimum_height, point.y)
			maximum_height = maxf(maximum_height, point.y)
	if is_inf(minimum_height) or is_inf(maximum_height):
		return Vector2.ZERO
	return Vector2(minimum_height, maximum_height)


func _update_raw_preview_mesh() -> void:
	if _raw_preview == null or _raw_source_mesh == null or _fit == null:
		return
	var endpoint_before := 0.0
	var scaled_surfaces: Array[PackedVector3Array] = []
	var detail_source := _detail_erased_source_arrays()
	var detail_vertices := (
		detail_source.get("vertices", []) as Array
	)
	var detail_uvs := detail_source.get("uvs", []) as Array
	var detail_erased_masks := (
		detail_source.get("erased_vertex_masks", []) as Array
	)
	for surface_index in _raw_surface_arrays.size():
		var source_vertices: PackedVector3Array = (
			detail_vertices[surface_index]
		)
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
	var height_bounds := _scaled_surface_height_bounds(scaled_surfaces)

	if _fit.garment_class != "upper_body":
		var direct_surfaces: Array[PackedVector3Array] = []
		for scaled in scaled_surfaces:
			var deformed := scaled.duplicate()
			for vertex_index in deformed.size():
				var point := deformed[vertex_index]
				var section_scale := _section_scale_at_height(
					point.y,
					height_bounds.x,
					height_bounds.y,
				)
				point.x *= _fit.torso_width * section_scale
				point.z *= _fit.torso_depth * section_scale
				if _fit.garment_class == "footwear":
					var side := 1.0 if point.x >= 0.0 else -1.0
					point += Vector3(
						side * _fit.position.x,
						_fit.position.z,
						-side * _fit.position.y,
					)
				deformed[vertex_index] = point
			direct_surfaces.append(deformed)
		_commit_raw_preview_mesh(
			direct_surfaces,
			detail_uvs,
			detail_erased_masks,
		)
		return

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
				var section_scale := _section_scale_at_height(
					point.y,
					height_bounds.x,
					height_bounds.y,
				)
				point.x *= _fit.torso_width * section_scale
				point.z *= _fit.torso_depth * section_scale
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
		first_pass[surface_index] = deformed
	var smoothed_normals := _calculate_preview_smoothing_normals(
		first_pass,
		_fit.surface_smoothing,
	)
	var detail_smoothed_normals: Array[PackedVector3Array] = []
	if not detail_erased_masks.is_empty():
		detail_smoothed_normals = _calculate_preview_smoothing_normals(
			first_pass,
			1.0,
		)
		for surface_index in mini(
			smoothed_normals.size(),
			detail_erased_masks.size(),
		):
			if surface_index >= detail_smoothed_normals.size():
				continue
			var normals := smoothed_normals[surface_index]
			var forced_normals := detail_smoothed_normals[surface_index]
			var erased_mask: PackedByteArray = (
				detail_erased_masks[surface_index]
			)
			for vertex_index in mini(
				normals.size(),
				erased_mask.size(),
			):
				if erased_mask[vertex_index] != 0:
					normals[vertex_index] = forced_normals[vertex_index]
			smoothed_normals[surface_index] = normals
	for surface_index in _raw_surface_arrays.size():
		var arrays := (
			(_raw_surface_arrays[surface_index] as Array).duplicate(true)
		)
		var deformed := first_pass[surface_index]
		arrays[Mesh.ARRAY_VERTEX] = deformed
		if surface_index < detail_uvs.size():
			arrays[Mesh.ARRAY_TEX_UV] = detail_uvs[surface_index]
		if surface_index < smoothed_normals.size():
			arrays[Mesh.ARRAY_NORMAL] = smoothed_normals[surface_index]
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
	_raw_preview.position = (
		Vector3(
			_fit.pair_center_position.x,
			_fit.pair_center_position.z,
			-_fit.pair_center_position.y,
		)
		if _fit.garment_class == "footwear"
		else Vector3(
			_fit.position.x,
			_fit.position.z,
			-_fit.position.y,
		)
	)
	_raw_preview.rotation_degrees = Vector3(
		_fit.rotation_degrees.x,
		_fit.rotation_degrees.z,
		-_fit.rotation_degrees.y,
	)
	_preview_revision = _fit_revision


func _commit_raw_preview_mesh(
	deformed_surfaces: Array[PackedVector3Array],
	detail_uvs: Array,
	detail_erased_masks: Array,
) -> void:
	var rebuilt := ArrayMesh.new()
	var smoothed_normals := _calculate_preview_smoothing_normals(
		deformed_surfaces,
		_fit.surface_smoothing,
	)
	if not detail_erased_masks.is_empty():
		var forced_normals := _calculate_preview_smoothing_normals(
			deformed_surfaces,
			1.0,
		)
		for surface_index in mini(
			smoothed_normals.size(),
			detail_erased_masks.size(),
		):
			if surface_index >= forced_normals.size():
				continue
			var normals := smoothed_normals[surface_index]
			var detail_normals := forced_normals[surface_index]
			var erased_mask: PackedByteArray = (
				detail_erased_masks[surface_index]
			)
			for vertex_index in mini(
				normals.size(),
				erased_mask.size(),
			):
				if erased_mask[vertex_index] != 0:
					normals[vertex_index] = detail_normals[vertex_index]
			smoothed_normals[surface_index] = normals
	_raw_deformed_vertices.clear()
	for surface_index in _raw_surface_arrays.size():
		var arrays := (
			(_raw_surface_arrays[surface_index] as Array).duplicate(true)
		)
		var deformed := deformed_surfaces[surface_index]
		arrays[Mesh.ARRAY_VERTEX] = deformed
		if surface_index < detail_uvs.size():
			arrays[Mesh.ARRAY_TEX_UV] = detail_uvs[surface_index]
		if surface_index < smoothed_normals.size():
			arrays[Mesh.ARRAY_NORMAL] = smoothed_normals[surface_index]
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


func _calculate_preview_smoothing_normals(
	surfaces: Array[PackedVector3Array],
	amount: float,
) -> Array[PackedVector3Array]:
	return _calculate_surface_smoothing_normals(
		_raw_surface_arrays,
		surfaces,
		amount,
	)


func _calculate_surface_smoothing_normals(
	source_surface_arrays: Array,
	surfaces: Array[PackedVector3Array],
	amount: float,
) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	# Always author a baseline normal array, including at 0%. Raw imported
	# surfaces may not contain normals; omitting the array at exactly zero
	# makes Godot use a different fallback shading path and causes a visible
	# discontinuity between 0% and 1%.
	amount = clampf(amount, 0.0, 1.0)
	var local_accumulated: Array = []
	var position_groups: Dictionary = {}
	for surface_index in surfaces.size():
		var vertices := surfaces[surface_index]
		var local_normals: Array[Vector3] = []
		local_normals.resize(vertices.size())
		local_normals.fill(Vector3.ZERO)
		local_accumulated.append(local_normals)
		for vertex_index in vertices.size():
			var key := _preview_normal_weld_key(vertices[vertex_index])
			if not position_groups.has(key):
				position_groups[key] = []
			(position_groups[key] as Array).append(
				Vector2i(surface_index, vertex_index)
			)
		var source_arrays := (
			source_surface_arrays[surface_index] as Array
		)
		var indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for triangle_start in range(0, vertices.size() - 2, 3):
				_accumulate_preview_triangle_normal(
					vertices,
					triangle_start,
					triangle_start + 1,
					triangle_start + 2,
					local_normals,
				)
		else:
			for triangle_start in range(0, indices.size() - 2, 3):
				_accumulate_preview_triangle_normal(
					vertices,
					indices[triangle_start],
					indices[triangle_start + 1],
					indices[triangle_start + 2],
					local_normals,
				)
	for surface_index in surfaces.size():
		var vertices := surfaces[surface_index]
		var source_arrays := (
			source_surface_arrays[surface_index] as Array
		)
		var authored := PackedVector3Array()
		if source_arrays[Mesh.ARRAY_NORMAL] != null:
			authored = source_arrays[Mesh.ARRAY_NORMAL]
		var blended := PackedVector3Array()
		blended.resize(vertices.size())
		for vertex_index in vertices.size():
			var local: Vector3 = (
				local_accumulated[surface_index] as Array
			)[vertex_index]
			var original := (
				authored[vertex_index]
				if vertex_index < authored.size()
				else local
			)
			if original.length_squared() <= 0.0000000001:
				original = Vector3.UP
			else:
				original = original.normalized()
			var smooth := Vector3.ZERO
			var group := position_groups.get(
				_preview_normal_weld_key(vertices[vertex_index]),
				[],
			) as Array
			for reference_variant in group:
				var reference := reference_variant as Vector2i
				var neighbor: Vector3 = (
					local_accumulated[reference.x] as Array
				)[reference.y]
				if neighbor.length_squared() <= 0.0000000001:
					continue
				var neighbor_direction := neighbor.normalized()
				# Crease-aware smoothing: blend only similarly oriented
				# cloth faces, never an inner/opposite shell or hard cuff.
				if original.dot(neighbor_direction) >= 0.35:
					smooth += neighbor
			if smooth.length_squared() <= 0.0000000001:
				smooth = original
			else:
				smooth = smooth.normalized()
			var normal := original.lerp(smooth, amount)
			blended[vertex_index] = (
				normal.normalized()
				if normal.length_squared() > 0.0000000001
				else original
			)
		result.append(blended)
	return result


func _accumulate_preview_triangle_normal(
	vertices: PackedVector3Array,
	first_index: int,
	second_index: int,
	third_index: int,
	local_normals: Array[Vector3],
) -> void:
	if (
		first_index < 0
		or second_index < 0
		or third_index < 0
		or first_index >= vertices.size()
		or second_index >= vertices.size()
		or third_index >= vertices.size()
	):
		return
	var normal := (
		vertices[third_index] - vertices[first_index]
	).cross(vertices[second_index] - vertices[first_index])
	if normal.length_squared() <= 0.0000000001:
		return
	for vertex_index in [first_index, second_index, third_index]:
		local_normals[vertex_index] += normal


func _preview_normal_weld_key(point: Vector3) -> Vector3i:
	const NORMAL_WELD_SCALE := 100000.0
	return Vector3i(
		roundi(point.x * NORMAL_WELD_SCALE),
		roundi(point.y * NORMAL_WELD_SCALE),
		roundi(point.z * NORMAL_WELD_SCALE),
	)


func _apply_live_bound_surface_smoothing() -> void:
	if _fit == null or _selected_part == null:
		return
	var garment := assembler.equipped_node(
		_selected_part.slot
	) as MeshInstance3D
	if garment == null or garment.mesh == null:
		return
	var instance_key := garment.get_instance_id()
	if not _bound_smoothing_sources.has(instance_key):
		_bound_smoothing_sources[instance_key] = garment.mesh
	var source := _bound_smoothing_sources[instance_key] as Mesh
	if source == null:
		return
	if _fit.surface_smoothing <= 0.0001:
		garment.mesh = source
		return
	var smoothed := _surface_smoothed_mesh_copy(
		source,
		_fit.surface_smoothing,
	)
	if smoothed != null:
		garment.mesh = smoothed


func _surface_smoothed_mesh_copy(
	source: Mesh,
	amount: float,
) -> ArrayMesh:
	var source_arrays: Array = []
	var surfaces: Array[PackedVector3Array] = []
	for surface_index in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface_index)
		source_arrays.append(arrays)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		surfaces.append(vertices)
	var normals := _calculate_surface_smoothing_normals(
		source_arrays,
		surfaces,
		amount,
	)
	if normals.size() != source.get_surface_count():
		return null
	var rebuilt := ArrayMesh.new()
	rebuilt.resource_name = "%s_SmoothingPreview" % source.resource_name
	for surface_index in source.get_surface_count():
		var arrays := (
			(source_arrays[surface_index] as Array).duplicate(true)
		)
		arrays[Mesh.ARRAY_NORMAL] = normals[surface_index]
		rebuilt.add_surface_from_arrays(
			source.surface_get_primitive_type(surface_index),
			arrays,
		)
		rebuilt.surface_set_material(
			surface_index,
			source.surface_get_material(surface_index),
		)
		rebuilt.surface_set_name(
			surface_index,
			source.surface_get_name(surface_index),
		)
	return rebuilt


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
	var body_profile_error := OK
	var body_profile := _active_body_profile()
	if (
		body_profile != null
		and not body_profile.resource_path.is_empty()
		and "::" not in body_profile.resource_path
	):
		body_profile_error = ResourceSaver.save(
			body_profile, body_profile.resource_path
		)
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
	if (
		fit_error != OK
		or part_error != OK
		or preset_error != OK
		or body_profile_error != OK
	):
		_set_status(
			"error",
			"Save failed (fit %d, part %d, preset %d, body %d)."
			% [
				fit_error,
				part_error,
				preset_error,
				body_profile_error,
			],
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
	var errors := _technical_bind_errors()
	if not errors.is_empty():
		_set_status("error", "ACTION NEEDED\n• " + "\n• ".join(errors))
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
	_validate()


func _publish_final_output() -> void:
	var errors := _technical_publish_errors()
	if not errors.is_empty():
		_set_status("error", "ACTION NEEDED\n• " + "\n• ".join(errors))
		return
	# Clicking Publish is itself the user's explicit acceptance. The review
	# checkbox remains a useful reminder, never a gate.
	if _accept_final_check != null:
		_accept_final_check.set_pressed_no_signal(true)
	if _preview_mode_option != null:
		_preview_mode_option.select(1)
		_on_preview_mode_selected(1)
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
	var technical_errors := _technical_bind_errors()
	var warnings := _fit_diagnostic_warnings()
	if not technical_errors.is_empty():
		_set_status(
			"error",
			"ACTION NEEDED\n• " + "\n• ".join(technical_errors),
		)
		return
	var has_current_final := not (
		_final_preview_root == null
		or not is_instance_valid(_final_preview_root)
		or _final_output_revision != _fit_revision
	)
	var message := ""
	var kind := "warning"
	if not has_current_final:
		message = (
			"READY FOR STEPS 1–2\n"
			+ "Save the editable fit, then build the bound Final Output."
		)
	else:
		var reviewed := (
			_accept_final_check != null
			and _accept_final_check.button_pressed
		)
		if reviewed:
			message = (
				"READY FOR STEP 4\n"
				+ "Final Output reviewed · existing skeleton · publish when ready"
			)
			kind = "ok"
		else:
			message = (
				"FINAL OUTPUT READY\n"
				+ "Preview or open it in Blender, then publish when satisfied. "
				+ "Review is recommended, never required."
			)
	if (
		not _selected_preview_clip().is_empty()
		and not has_current_final
	):
		warnings.append(
			"Build Final Output to preview the garment deforming with animations."
		)
	if not warnings.is_empty():
		message += (
			"\nADVISORY ONLY — NEVER BLOCKING\n• "
			+ "\n• ".join(warnings)
		)
		kind = "warning"
	_set_status(kind, message)


func _technical_bind_errors() -> PackedStringArray:
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
	return errors


## Compatibility name retained for automated tooling. It now contains only
## requirements that make the build technically impossible, never visual-fit
## opinions.
func _hard_validation_errors() -> PackedStringArray:
	return _technical_bind_errors()


func _technical_publish_errors() -> PackedStringArray:
	var errors := PackedStringArray()
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
	return errors


func _final_validation_errors() -> PackedStringArray:
	return _technical_publish_errors()


func _fit_diagnostic_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for warning in _fit_validation_errors():
		if not warnings.has(warning):
			warnings.append(warning)
	if _fit == null:
		return warnings
	for warning in _fit.validation_errors():
		if not warnings.has(warning):
			warnings.append(warning)
	if (
		_fit.hidden_regions.has("hand_l")
		or _fit.hidden_regions.has("hand_r")
	):
		warnings.append(
			"Hands are selected for hiding; keep this only when intentional."
		)
	return warnings


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
