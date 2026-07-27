extends Node3D
## Standalone, player-only animation authoring utility. The interaction model is
## adapted from C:/Dev/imota-idle/tools/rig_editor, but the dependencies are not:
## this app works directly with Suma's Skeleton3D and Godot Animation resources.

const TARGET_PREVIEW_HEIGHT := 1.72
const DEFAULT_IDLE_NAME := "idle"
const DEFAULT_WALK_NAME := "walk"
const PANEL := Color("#202631")
const PANEL_DEEP := Color("#171b24")
const FIELD := Color("#2a313e")
const FIELD_HOVER := Color("#343d4c")
const ACCENT := Color("#dcae62")
const ACCENT_BRIGHT := Color("#f4cf85")
const TEXT := Color("#e3e6ec")
const TEXT_DIM := Color("#9099a8")
const DANGER := Color("#d36a70")

var _model_path := ""
var _walk_path := ""
var _animation_source_directory := ""
var _model_root: Node3D
var _model_holder: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _animation_library: AnimationLibrary
var _animations: Dictionary = {}
var _current_clip := ""
var _time := 0.0
var _playing := false
var _speed := 1.0
var _updating_ui := false
var _selected_bone := ""
var _selected_bone_index := -1
var _selected_track := -1
var _selected_key := -1
var _pending_rotation := Quaternion.IDENTITY

var _camera: Camera3D
var _camera_yaw := 0.58
var _camera_pitch := -0.20
var _camera_distance := 4.7
var _camera_focus := Vector3(0.0, 0.30, 0.0)
var _orbiting := false
var _bone_marker: MeshInstance3D

var _theme: Theme
var _clip_list: ItemList
var _bone_tree: Tree
var _bone_search: LineEdit
var _timeline: PlayerAnimationTimeline
var _timeline_scroll: ScrollContainer
var _play_button: Button
var _time_label: Label
var _scrubber: HSlider
var _length_spin: SpinBox
var _loop_check: CheckBox
var _rotation_spins: Array[SpinBox] = []
var _bone_name_label: Label
var _status: Label
var _source_label: Label
var _new_name: LineEdit
var _load_player_dialog: FileDialog
var _load_clip_dialog: FileDialog
var _help_dialog: AcceptDialog


func _ready() -> void:
	_resolve_default_paths()
	_build_stage()
	_build_ui()
	_set_status("Loading Suma's current player…")
	if not _load_player_glb(_model_path):
		_set_status("Could not load the default player. Use Load player GLB.", true)
		return
	_load_default_clips()
	if _animations.has(DEFAULT_IDLE_NAME):
		_select_clip(DEFAULT_IDLE_NAME)
	elif not _animations.is_empty():
		_select_clip(str(_animations.keys()[0]))
	_populate_bones()
	var args := OS.get_cmdline_user_args()
	if "--selftest" in args:
		_run_selftest()
	elif "--shot" in args:
		_capture_validation_shot()
	else:
		_set_status(
			"Ready — choose a clip, pose a bone, insert a key, then export."
		)


func _process(_delta: float) -> void:
	if _playing and not _current_clip.is_empty():
		var animation := _current_animation()
		if animation != null and _animation_player != null:
			_time = clampf(
				_animation_player.current_animation_position,
				0.0,
				animation.length
			)
			if (
				animation.loop_mode == Animation.LOOP_NONE
				and not _animation_player.is_playing()
			):
				_time = animation.length
				_playing = false
				_play_button.text = "Play"
			_refresh_transport(false)
	_update_bone_marker()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_play()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			_help_dialog.popup_centered(Vector2i(650, 600))
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(2.3, _camera_distance - 0.25)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(8.0, _camera_distance + 0.25)
			_update_camera()
	if event is InputEventMouseMotion and _orbiting:
		_camera_yaw -= event.relative.x * 0.008
		_camera_pitch = clampf(
			_camera_pitch - event.relative.y * 0.008,
			-1.0,
			0.35
		)
		_update_camera()
		get_viewport().set_input_as_handled()


func _resolve_default_paths() -> void:
	var repository_root := ProjectSettings.globalize_path("res://../..").simplify_path()
	var profile_path := repository_root.path_join(
		"assets/player/current_player_profile.tres"
	)
	var profile_text := FileAccess.get_file_as_string(profile_path)
	var model_resource_path := _profile_string(
		profile_text,
		"model_resource_path",
		"res://assets/3d/reworked/suma_player.glb"
	)
	var walk_source_path := _profile_string(
		profile_text,
		"walk_source_path",
		"res://art_source/animation_sources/player_walk.glb"
	)
	_model_path = _repository_resource_path(repository_root, model_resource_path)
	_walk_path = _repository_resource_path(repository_root, walk_source_path)
	_animation_source_directory = repository_root.path_join(
		"art_source/animation_sources"
	).simplify_path()


func _profile_string(text: String, key: String, fallback: String) -> String:
	for source_line in text.split("\n"):
		var line := source_line.strip_edges()
		if not line.begins_with("%s = " % key):
			continue
		var parts := line.split("\"")
		if parts.size() >= 2:
			return String(parts[1])
	return fallback


func _repository_resource_path(repository_root: String, resource_path: String) -> String:
	return repository_root.path_join(
		resource_path.trim_prefix("res://")
	).simplify_path()


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#272d37")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9e0eb")
	env.ambient_light_energy = 0.24
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("#fff0d1")
	sun.light_energy = 0.52
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	fill.light_color = Color("#b7c9ed")
	fill.light_energy = 0.10
	fill.shadow_enabled = false
	add_child(fill)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(7.0, 7.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#343b47")
	floor_material.roughness = 0.92
	floor_mesh.material = floor_material
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.position.y = -0.012
	add_child(floor)

	_model_holder = Node3D.new()
	_model_holder.name = "PlayerPreview"
	add_child(_model_holder)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.40
	_camera.current = true
	add_child(_camera)
	_update_camera()

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.032
	marker_mesh.height = 0.064
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = ACCENT_BRIGHT
	marker_material.emission_enabled = true
	marker_material.emission = ACCENT
	marker_material.emission_energy_multiplier = 1.8
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mesh.material = marker_material
	_bone_marker = MeshInstance3D.new()
	_bone_marker.mesh = marker_mesh
	_bone_marker.visible = false
	add_child(_bone_marker)


func _build_ui() -> void:
	_theme = _make_theme()
	var ui := CanvasLayer.new()
	add_child(ui)

	var top := PanelContainer.new()
	top.theme = _theme
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58.0
	ui.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top.add_child(top_row)
	var title := Label.new()
	title.text = "SUMA  ·  PLAYER ANIMATION STUDIO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT_BRIGHT)
	title.custom_minimum_size.x = 320.0
	top_row.add_child(title)
	top_row.add_child(_button("Load player GLB", _show_load_player))
	top_row.add_child(_button("Import animation GLB", _show_load_clip))
	_source_label = Label.new()
	_source_label.text = "No player loaded"
	_source_label.clip_text = true
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label.add_theme_color_override("font_color", TEXT_DIM)
	top_row.add_child(_source_label)
	top_row.add_child(_button("Help  F1", func() -> void:
		_help_dialog.popup_centered(Vector2i(650, 600))
	))

	var left := PanelContainer.new()
	left.theme = _theme
	left.position = Vector2(12.0, 70.0)
	left.size = Vector2(270.0, 500.0)
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 70.0
	left.offset_bottom = -302.0
	ui.add_child(left)
	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", 8)
	left.add_child(left_v)
	left_v.add_child(_section_title("CLIPS"))
	var clip_hint := Label.new()
	clip_hint.text = "Current player + compatible Mixamo sources"
	clip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clip_hint.add_theme_color_override("font_color", TEXT_DIM)
	left_v.add_child(clip_hint)
	_clip_list = ItemList.new()
	_clip_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_clip_list.item_selected.connect(func(index: int) -> void:
		_select_clip(_clip_list.get_item_text(index))
	)
	left_v.add_child(_clip_list)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "new clip name"
	left_v.add_child(_new_name)
	var clip_actions := HBoxContainer.new()
	clip_actions.add_child(_button("Duplicate", _duplicate_current_clip))
	clip_actions.add_child(_button("Export .tres", _export_current_clip, true))
	left_v.add_child(clip_actions)
	left_v.add_child(_button("Normalize in-place", _make_current_clip_in_place))

	var right := PanelContainer.new()
	right.theme = _theme
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -350.0
	right.offset_right = -12.0
	right.offset_top = 70.0
	right.offset_bottom = -302.0
	ui.add_child(right)
	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 8)
	right.add_child(right_v)
	right_v.add_child(_section_title("BONE POSE"))
	_bone_search = LineEdit.new()
	_bone_search.placeholder_text = "Filter bones…"
	_bone_search.text_changed.connect(func(_value: String) -> void:
		_populate_bones()
	)
	right_v.add_child(_bone_search)
	_bone_tree = Tree.new()
	_bone_tree.hide_root = true
	_bone_tree.custom_minimum_size.y = 170.0
	_bone_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bone_tree.item_selected.connect(_on_bone_tree_selected)
	right_v.add_child(_bone_tree)
	_bone_name_label = Label.new()
	_bone_name_label.text = "No bone selected"
	_bone_name_label.add_theme_color_override("font_color", ACCENT_BRIGHT)
	right_v.add_child(_bone_name_label)
	var axes := ["X  pitch", "Y  yaw", "Z  roll"]
	for axis_index in 3:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = axes[axis_index]
		label.custom_minimum_size.x = 72.0
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -360.0
		spin.max_value = 360.0
		spin.step = 0.1
		spin.suffix = "°"
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(_value: float) -> void:
			_on_pose_rotation_changed()
		)
		row.add_child(spin)
		_rotation_spins.append(spin)
		right_v.add_child(row)
	var key_actions := HBoxContainer.new()
	key_actions.add_child(_button("Insert / update key", _insert_rotation_key, true))
	key_actions.add_child(_button("Delete key", _delete_selected_key, false, true))
	right_v.add_child(key_actions)
	right_v.add_child(_section_title("CLIP"))
	var length_row := HBoxContainer.new()
	var length_label := Label.new()
	length_label.text = "Length"
	length_label.custom_minimum_size.x = 72.0
	length_row.add_child(length_label)
	_length_spin = SpinBox.new()
	_length_spin.min_value = 0.05
	_length_spin.max_value = 60.0
	_length_spin.step = 0.01
	_length_spin.suffix = " s"
	_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_length_spin.value_changed.connect(_on_length_changed)
	length_row.add_child(_length_spin)
	right_v.add_child(length_row)
	_loop_check = CheckBox.new()
	_loop_check.text = "Loop animation"
	_loop_check.toggled.connect(_on_loop_toggled)
	right_v.add_child(_loop_check)

	var bottom := PanelContainer.new()
	bottom.theme = _theme
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 292.0
	bottom.offset_right = -360.0
	bottom.offset_top = -292.0
	bottom.offset_bottom = -12.0
	ui.add_child(bottom)
	var bottom_v := VBoxContainer.new()
	bottom_v.add_theme_constant_override("separation", 5)
	bottom.add_child(bottom_v)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 7)
	bottom_v.add_child(transport)
	_play_button = _button("▶  Play", _toggle_play, true)
	transport.add_child(_play_button)
	transport.add_child(_button("■  Stop", _stop))
	_time_label = Label.new()
	_time_label.text = "0.00 / 0.00"
	_time_label.custom_minimum_size.x = 105.0
	transport.add_child(_time_label)
	_scrubber = HSlider.new()
	_scrubber.min_value = 0.0
	_scrubber.max_value = 1.0
	_scrubber.step = 0.001
	_scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrubber.value_changed.connect(_on_scrubber_changed)
	transport.add_child(_scrubber)
	var speed_label := Label.new()
	speed_label.text = "Speed"
	transport.add_child(speed_label)
	var speed_spin := SpinBox.new()
	speed_spin.min_value = 0.1
	speed_spin.max_value = 3.0
	speed_spin.step = 0.1
	speed_spin.value = 1.0
	speed_spin.value_changed.connect(func(value: float) -> void:
		_speed = value
		if _animation_player != null:
			_animation_player.speed_scale = _speed
	)
	transport.add_child(speed_spin)
	_timeline_scroll = ScrollContainer.new()
	_timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_timeline_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_v.add_child(_timeline_scroll)
	_timeline = PlayerAnimationTimeline.new()
	_timeline.seek_requested.connect(_seek)
	_timeline.bone_selected.connect(_select_bone)
	_timeline.key_selected.connect(_on_timeline_key_selected)
	_timeline_scroll.add_child(_timeline)

	_status = Label.new()
	_status.theme = _theme
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 16.0
	_status.offset_right = -16.0
	_status.offset_top = -31.0
	_status.offset_bottom = -7.0
	_status.add_theme_color_override("font_color", TEXT_DIM)
	ui.add_child(_status)

	_load_player_dialog = _file_dialog("Load Suma player GLB", ["*.glb ; GLB model"])
	_load_player_dialog.file_selected.connect(func(path: String) -> void:
		_load_replacement_player(path)
	)
	ui.add_child(_load_player_dialog)
	_load_clip_dialog = _file_dialog(
		"Import compatible animation GLB",
		["*.glb ; GLB animation"]
	)
	_load_clip_dialog.file_selected.connect(func(path: String) -> void:
		_import_clip_glb(path)
	)
	ui.add_child(_load_clip_dialog)
	_help_dialog = AcceptDialog.new()
	_help_dialog.theme = _theme
	_help_dialog.title = "Suma Player Animation Studio"
	_help_dialog.dialog_text = """PLAYER-ONLY WORKFLOW

1. Pick idle or walk on the left, or import a Mixamo-compatible GLB.
2. Scrub or play the clip with the bottom transport.
3. Pick a bone in the right panel or click one of its timeline rows.
4. Edit the bone's local rotation and insert/update a key at the playhead.
5. Export writes a non-destructive .tres into this app's exports folder.

Every clip is normalized in-place automatically. Net horizontal root travel is
removed while vertical gait and cyclic hip sway are preserved.

VIEWPORT
Middle-drag: orbit
Wheel: zoom
Space: play / pause
F1: this help

TIMELINE
Click ruler/row: scrub
Click diamond: select key
Wheel over timeline: zoom time

The source GLBs are never overwritten. This standalone project is ignored by
Suma's main Godot resource scan and has no game runtime dependency."""
	ui.add_child(_help_dialog)


func _load_replacement_player(path: String) -> void:
	_clear_player()
	if _load_player_glb(path):
		_model_path = path
		_animations.clear()
		_load_default_clips()
		_refresh_clip_list()
		_populate_bones()
		if not _animations.is_empty():
			_select_clip(str(_animations.keys()[0]))


func _load_player_glb(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_set_status("Player GLB not found: %s" % path, true)
		return false
	var generated := _generate_external_glb_scene(path)
	if generated == null:
		return false
	_model_root = generated as Node3D
	_model_holder.add_child(_model_root)
	_skeleton = _find_first_of_type(_model_root, "Skeleton3D") as Skeleton3D
	_animation_player = (
		_find_first_of_type(_model_root, "AnimationPlayer") as AnimationPlayer
	)
	if _skeleton == null or _animation_player == null:
		_set_status("The GLB must contain a Skeleton3D and AnimationPlayer.", true)
		_clear_player()
		return false
	_animation_library = _animation_player.get_animation_library("")
	if _animation_library == null:
		_animation_library = AnimationLibrary.new()
		_animation_player.add_animation_library("", _animation_library)
	_animation_player.callback_mode_process = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	_animation_player.active = true
	for animation_name in _animation_player.get_animation_list():
		if animation_name == "RESET":
			continue
		_animation_player.play(animation_name)
		_animation_player.seek(0.0, true)
		break
	_fit_player_to_stage()
	_source_label.text = path
	_source_label.tooltip_text = path
	return true


func _load_default_clips() -> void:
	if _animation_player == null:
		return
	var names := _animation_player.get_animation_list()
	for animation_name in names:
		if animation_name == "RESET":
			continue
		var friendly := DEFAULT_IDLE_NAME if _animations.is_empty() else str(animation_name)
		_add_clip(friendly, _animation_player.get_animation(animation_name))
		if friendly == DEFAULT_IDLE_NAME:
			(_animations[friendly] as Animation).loop_mode = Animation.LOOP_LINEAR
	if FileAccess.file_exists(_walk_path):
		_import_clip_glb(_walk_path, DEFAULT_WALK_NAME, false)
	_import_default_action_clips()
	_refresh_clip_list()


func _import_default_action_clips() -> void:
	if not DirAccess.dir_exists_absolute(_animation_source_directory):
		return
	var directory := DirAccess.open(_animation_source_directory)
	if directory == null:
		return
	var filenames := directory.get_files()
	filenames.sort()
	for filename in filenames:
		if (
			not filename.begins_with("player_")
			or filename.get_extension().to_lower() != "glb"
		):
			continue
		var path := _animation_source_directory.path_join(filename)
		if path.simplify_path() == _walk_path.simplify_path():
			continue
		var clip_name := filename.get_basename().trim_prefix("player_").to_snake_case()
		_import_clip_glb(path, clip_name, false)


func _import_clip_glb(
	path: String,
	forced_name := "",
	select_after := true
) -> void:
	if _skeleton == null:
		_set_status("Load the player before importing an animation.", true)
		return
	var generated := _generate_external_glb_scene(path)
	if generated == null:
		return
	var source_player := (
		_find_first_of_type(generated, "AnimationPlayer") as AnimationPlayer
	)
	if source_player == null or source_player.get_animation_list().is_empty():
		generated.queue_free()
		_set_status("No animation was found in %s" % path, true)
		return
	var source_names := source_player.get_animation_list()
	var source_name := ""
	for candidate in source_names:
		if candidate != "RESET":
			source_name = candidate
			break
	if source_name.is_empty():
		generated.queue_free()
		_set_status("The GLB only contains RESET; there is no usable clip.", true)
		return
	var desired := (
		forced_name
		if not forced_name.is_empty()
		else path.get_file().get_basename().to_snake_case()
	)
	desired = _unique_clip_name(desired)
	var clip := source_player.get_animation(source_name).duplicate(true) as Animation
	clip.resource_name = desired
	if _clip_loops_by_default(desired):
		clip.loop_mode = Animation.LOOP_LINEAR
	_validate_animation_bones(clip)
	_add_clip(desired, clip)
	generated.queue_free()
	_refresh_clip_list()
	if select_after:
		_select_clip(desired)
	_set_status("Imported %s from %s" % [desired, path.get_file()])


func _clip_loops_by_default(clip_name: String) -> bool:
	return clip_name in [DEFAULT_IDLE_NAME, DEFAULT_WALK_NAME, "fish_wait", "chop"]


func _add_clip(name: String, source: Animation) -> void:
	if source == null or _animation_library == null:
		return
	var clip := source.duplicate(true) as Animation
	clip.resource_name = name
	_normalize_animation_in_place(clip)
	if _animation_library.has_animation(name):
		_animation_library.remove_animation(name)
	_animation_library.add_animation(name, clip)
	_animations[name] = clip


func _select_clip(name: String) -> void:
	if not _animations.has(name):
		return
	_current_clip = name
	_time = 0.0
	_playing = false
	var animation := _current_animation()
	_animation_player.play(name)
	_animation_player.pause()
	_animation_player.seek(0.0, true)
	_timeline.set_animation(animation)
	_timeline.set_playhead(0.0)
	_updating_ui = true
	_length_spin.value = animation.length
	_loop_check.button_pressed = animation.loop_mode != Animation.LOOP_NONE
	_scrubber.value = 0.0
	_updating_ui = false
	_play_button.text = "▶  Play"
	_refresh_clip_list()
	_apply_time()


func _current_animation() -> Animation:
	return _animations.get(_current_clip) as Animation


func _apply_time() -> void:
	var animation := _current_animation()
	if animation == null or _animation_player == null:
		return
	_time = clampf(_time, 0.0, animation.length)
	if _animation_player.assigned_animation != _current_clip:
		_animation_player.play(_current_clip)
	_animation_player.pause()
	_animation_player.seek(_time, true)
	_refresh_transport(true)


func _refresh_transport(sync_pose_fields: bool) -> void:
	var animation := _current_animation()
	if animation == null:
		return
	_timeline.set_playhead(_time)
	_updating_ui = true
	_scrubber.value = _time / maxf(animation.length, 0.001)
	_time_label.text = "%.3f / %.3f" % [_time, animation.length]
	_updating_ui = false
	if sync_pose_fields:
		_sync_rotation_fields_from_pose()


func _seek(value: float) -> void:
	_playing = false
	_play_button.text = "▶  Play"
	_time = value
	_apply_time()


func _toggle_play() -> void:
	var animation := _current_animation()
	if animation == null or _animation_player == null:
		return
	if _playing:
		_time = _animation_player.current_animation_position
		_animation_player.pause()
		_playing = false
	else:
		if _time >= animation.length:
			_time = 0.0
		_animation_player.speed_scale = _speed
		if _animation_player.assigned_animation == _current_clip:
			_animation_player.play()
		else:
			_animation_player.play(_current_clip)
		_animation_player.seek(_time, true)
		_playing = true
	_play_button.text = "Ⅱ  Pause" if _playing else "▶  Play"


func _stop() -> void:
	_playing = false
	_time = 0.0
	_play_button.text = "▶  Play"
	_apply_time()


func _on_scrubber_changed(value: float) -> void:
	if _updating_ui:
		return
	var animation := _current_animation()
	if animation != null:
		_seek(value * animation.length)


func _on_length_changed(value: float) -> void:
	if _updating_ui:
		return
	var animation := _current_animation()
	if animation == null:
		return
	animation.length = value
	_time = minf(_time, value)
	_timeline.refresh()
	_apply_time()


func _on_loop_toggled(enabled: bool) -> void:
	if _updating_ui:
		return
	var animation := _current_animation()
	if animation != null:
		animation.loop_mode = (
			Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE
		)


func _populate_bones() -> void:
	if _bone_tree == null:
		return
	_bone_tree.clear()
	var root := _bone_tree.create_item()
	if _skeleton == null:
		return
	var filter := _bone_search.text.strip_edges().to_lower()
	var items: Dictionary = {}
	for bone_index in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(bone_index)
		if not filter.is_empty() and not bone_name.to_lower().contains(filter):
			continue
		var parent_index := _skeleton.get_bone_parent(bone_index)
		var parent_item: TreeItem = items.get(parent_index, root)
		var item := _bone_tree.create_item(parent_item)
		item.set_text(0, bone_name.trim_prefix("mixamorig"))
		item.set_metadata(0, bone_name)
		items[bone_index] = item


func _on_bone_tree_selected() -> void:
	var selected := _bone_tree.get_selected()
	if selected != null:
		_select_bone(str(selected.get_metadata(0)))


func _select_bone(bone_name: String) -> void:
	if _skeleton == null:
		return
	var index := _skeleton.find_bone(bone_name)
	if index < 0:
		return
	_selected_bone = bone_name
	_selected_bone_index = index
	_selected_track = -1
	_selected_key = -1
	_bone_name_label.text = bone_name.trim_prefix("mixamorig")
	_timeline.set_selected_bone(bone_name)
	_sync_rotation_fields_from_pose()
	_bone_marker.visible = true


func _sync_rotation_fields_from_pose() -> void:
	if _skeleton == null or _selected_bone_index < 0:
		return
	_pending_rotation = _skeleton.get_bone_pose_rotation(_selected_bone_index)
	var degrees := _pending_rotation.get_euler() * 180.0 / PI
	_updating_ui = true
	for axis_index in 3:
		_rotation_spins[axis_index].value = degrees[axis_index]
	_updating_ui = false


func _on_pose_rotation_changed() -> void:
	if _updating_ui or _skeleton == null or _selected_bone_index < 0:
		return
	_playing = false
	if _animation_player != null:
		_animation_player.pause()
	_play_button.text = "▶  Play"
	var radians := Vector3(
		deg_to_rad(_rotation_spins[0].value),
		deg_to_rad(_rotation_spins[1].value),
		deg_to_rad(_rotation_spins[2].value)
	)
	_pending_rotation = Quaternion.from_euler(radians)
	_skeleton.set_bone_pose_rotation(_selected_bone_index, _pending_rotation)


func _insert_rotation_key() -> void:
	var animation := _current_animation()
	if animation == null or _selected_bone_index < 0:
		_set_status("Select a clip and bone first.", true)
		return
	var track_index := _find_bone_track(
		animation,
		_selected_bone,
		Animation.TYPE_ROTATION_3D
	)
	if track_index < 0:
		track_index = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(
			track_index,
			NodePath(_skeleton_track_prefix(animation) + ":" + _selected_bone)
		)
		animation.track_set_interpolation_type(
			track_index,
			Animation.INTERPOLATION_LINEAR
		)
	var existing := animation.track_find_key(
		track_index,
		_time,
		Animation.FIND_MODE_APPROX
	)
	if existing >= 0:
		animation.track_set_key_value(
			track_index,
			existing,
			_pending_rotation
		)
		_selected_key = existing
	else:
		_selected_key = animation.track_insert_key(
			track_index,
			_time,
			_pending_rotation,
			1.0
		)
	_selected_track = track_index
	_timeline.refresh()
	_timeline.select_key(_selected_track, _selected_key)
	_set_status(
		"Keyed %s at %.3f s" % [
			_selected_bone.trim_prefix("mixamorig"),
			_time,
		]
	)


func _delete_selected_key() -> void:
	var animation := _current_animation()
	if (
		animation == null
		or _selected_track < 0
		or _selected_key < 0
		or _selected_track >= animation.get_track_count()
		or _selected_key >= animation.track_get_key_count(_selected_track)
	):
		_set_status("Select a key diamond first.", true)
		return
	animation.track_remove_key(_selected_track, _selected_key)
	_selected_key = -1
	_timeline.refresh()
	_set_status("Deleted the selected key.")


func _on_timeline_key_selected(track_index: int, key_index: int) -> void:
	var animation := _current_animation()
	if animation == null:
		return
	_selected_track = track_index
	_selected_key = key_index
	var path := String(animation.track_get_path(track_index))
	if path.contains(":"):
		_select_bone(path.get_slice(":", 1))
		_selected_track = track_index
		_selected_key = key_index
		_timeline.select_key(track_index, key_index)


func _duplicate_current_clip() -> void:
	var source := _current_animation()
	if source == null:
		return
	var requested := _new_name.text.strip_edges().to_snake_case()
	if requested.is_empty():
		requested = _current_clip + "_edit"
	var name := _unique_clip_name(requested)
	_add_clip(name, source)
	_new_name.clear()
	_refresh_clip_list()
	_select_clip(name)
	_set_status("Created editable duplicate: %s" % name)


func _make_current_clip_in_place() -> void:
	var animation := _current_animation()
	if animation == null:
		return
	var changed_tracks := _normalize_animation_in_place(animation)
	_apply_time()
	if changed_tracks > 0:
		_set_status(
			"Removed horizontal root travel from %s without flattening its motion."
			% _current_clip
		)
	else:
		_set_status("%s is already in-place." % _current_clip)


func _normalize_animation_in_place(animation: Animation) -> int:
	var changed_tracks := 0
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not _is_root_motion_track(animation, track_index):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2:
			continue
		var first := animation.track_get_key_value(track_index, 0) as Vector3
		var last := animation.track_get_key_value(
			track_index,
			key_count - 1
		) as Vector3
		var horizontal_travel := Vector2(last.x - first.x, last.z - first.z)
		if horizontal_travel.length_squared() <= 0.00000001:
			continue
		var first_time := animation.track_get_key_time(track_index, 0)
		var last_time := animation.track_get_key_time(track_index, key_count - 1)
		var duration := maxf(last_time - first_time, 0.000001)
		for key_index in key_count:
			var key_time := animation.track_get_key_time(track_index, key_index)
			var ratio := clampf((key_time - first_time) / duration, 0.0, 1.0)
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			value.x -= horizontal_travel.x * ratio
			value.z -= horizontal_travel.y * ratio
			animation.track_set_key_value(track_index, key_index, value)
		changed_tracks += 1
	return changed_tracks


func _is_root_motion_track(animation: Animation, track_index: int) -> bool:
	var path := String(animation.track_get_path(track_index))
	if not path.contains(":"):
		return true
	var target := path.get_slice(":", 1).to_lower()
	return (
		target.contains("hips")
		or target.contains("pelvis")
		or target == "root"
		or target.ends_with("root")
	)


func _export_current_clip() -> void:
	var animation := _current_animation()
	if animation == null:
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://exports")
	)
	var safe_name := _current_clip.to_snake_case()
	var destination := "res://exports/%s.tres" % safe_name
	var export_animation := animation.duplicate(true) as Animation
	export_animation.resource_name = safe_name
	var error := ResourceSaver.save(export_animation, destination)
	if error == OK:
		_set_status(
			"Exported %s" % ProjectSettings.globalize_path(destination)
		)
	else:
		_set_status("Export failed with error %d." % error, true)


func _refresh_clip_list() -> void:
	if _clip_list == null:
		return
	_clip_list.clear()
	var names := _animations.keys()
	names.sort()
	for name in names:
		var index := _clip_list.add_item(str(name))
		if str(name) == _current_clip:
			_clip_list.select(index)


func _find_bone_track(
	animation: Animation,
	bone_name: String,
	type: Animation.TrackType
) -> int:
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != type:
			continue
		if String(animation.track_get_path(track_index)).ends_with(":" + bone_name):
			return track_index
	return -1


func _skeleton_track_prefix(animation: Animation) -> String:
	for track_index in animation.get_track_count():
		var path := String(animation.track_get_path(track_index))
		if path.contains(":"):
			return path.get_slice(":", 0)
	var root_node := _animation_player.get_node(_animation_player.root_node)
	return str(root_node.get_path_to(_skeleton))


func _validate_animation_bones(animation: Animation) -> void:
	var missing: Array[String] = []
	for track_index in animation.get_track_count():
		var path := String(animation.track_get_path(track_index))
		if not path.contains(":"):
			continue
		var bone_name := path.get_slice(":", 1)
		if bone_name.begins_with("mixamorig") and _skeleton.find_bone(bone_name) < 0:
			missing.append(bone_name)
	if not missing.is_empty():
		_set_status(
			"Imported with %d tracks targeting missing bones." % missing.size(),
			true
		)


func _unique_clip_name(base: String) -> String:
	var clean := base.strip_edges().to_snake_case()
	if clean.is_empty():
		clean = "animation"
	if not _animations.has(clean):
		return clean
	var suffix := 2
	while _animations.has("%s_%d" % [clean, suffix]):
		suffix += 1
	return "%s_%d" % [clean, suffix]


func _fit_player_to_stage() -> void:
	_model_root.scale = Vector3.ONE
	_model_root.position = Vector3.ZERO
	var bounds := _visual_bounds(_model_root)
	if bounds.size.y <= 0.001:
		return
	var scale_factor := TARGET_PREVIEW_HEIGHT / bounds.size.y
	_model_root.scale = Vector3.ONE * scale_factor
	# Mixamo's clip moves the hips from the centered bind into its animated
	# ground-relative pose. Ground against the animated toe, preserving the sole
	# thickness measured from the bind mesh, just like Suma's in-game player.
	_model_root.rotation.y = 0.0
	_model_root.position.y = _animated_ground_offset(bounds, scale_factor)


func _animated_ground_offset(bounds: AABB, preview_scale: float) -> float:
	if _skeleton == null or _animation_player == null:
		return -bounds.position.y * preview_scale
	var skeleton_to_model := (
		_model_root.global_transform.affine_inverse() * _skeleton.global_transform
	)
	var lowest_rest_y := INF
	var animated_y_for_lowest := 0.0
	for bone_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var rest_y := (
			skeleton_to_model * _skeleton.get_bone_global_rest(bone_index).origin
		).y
		if rest_y < lowest_rest_y:
			lowest_rest_y = rest_y
			animated_y_for_lowest = (
				skeleton_to_model * _skeleton.get_bone_global_pose(bone_index).origin
			).y
	if is_inf(lowest_rest_y):
		return -bounds.position.y * preview_scale
	var sole_margin := bounds.position.y - lowest_rest_y
	var animated_mesh_min_y := animated_y_for_lowest + sole_margin
	return -animated_mesh_min_y * preview_scale


func _visual_bounds(node: Node3D) -> AABB:
	var has_bounds := false
	var result := AABB()
	var root_inverse := node.global_transform.affine_inverse()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := root_inverse * mesh_instance.global_transform
		var transformed := local * mesh_instance.get_aabb()
		if not has_bounds:
			result = transformed
			has_bounds = true
		else:
			result = result.merge(transformed)
	return result


func _update_bone_marker() -> void:
	if _skeleton == null or _selected_bone_index < 0:
		_bone_marker.visible = false
		return
	_bone_marker.visible = true
	var pose := _skeleton.get_bone_global_pose(_selected_bone_index)
	_bone_marker.global_position = _skeleton.to_global(pose.origin)


func _update_camera() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		-sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	) * _camera_distance
	_camera.global_position = _camera_focus + offset
	_camera.look_at(_camera_focus, Vector3.UP)


func _generate_external_glb_scene(path: String) -> Node:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		_set_status("GLB import failed (%d): %s" % [error, path], true)
		return null
	var generated := document.generate_scene(state)
	if generated == null:
		_set_status("Godot could not generate a scene from %s" % path, true)
	return generated


func _clear_player() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null
	_skeleton = null
	_animation_player = null
	_animation_library = null
	_animations.clear()
	_current_clip = ""


func _find_first_of_type(node: Node, class_name_value: String) -> Node:
	if node.is_class(class_name_value):
		return node
	for child in node.get_children():
		var found := _find_first_of_type(child, class_name_value)
		if found != null:
			return found
	return null


func _show_load_player() -> void:
	_load_player_dialog.current_path = _model_path
	_load_player_dialog.popup_centered_ratio(0.75)


func _show_load_clip() -> void:
	_load_clip_dialog.current_path = _walk_path
	_load_clip_dialog.popup_centered_ratio(0.75)


func _capture_validation_shot() -> void:
	if _animations.has(DEFAULT_WALK_NAME):
		_select_clip(DEFAULT_WALK_NAME)
		_seek(minf(0.42, _current_animation().length))
	_select_bone("mixamorigRightArm")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://screenshots")
	)
	var image := get_viewport().get_texture().get_image()
	var output := "res://screenshots/player_animation_studio.png"
	var error := image.save_png(output)
	print(
		"STUDIO_SHOT ",
		ProjectSettings.globalize_path(output),
		" ERROR=",
		error
	)
	get_tree().quit(error)


func _run_selftest() -> void:
	assert(_model_root != null, "default player did not load")
	assert(_skeleton != null, "default player has no skeleton")
	assert(_skeleton.get_bone_count() >= 34, "Mixamo skeleton is incomplete")
	assert(_animations.has(DEFAULT_IDLE_NAME), "idle clip was not loaded")
	assert(_animations.has(DEFAULT_WALK_NAME), "walk clip was not loaded")
	for clip_name in _animations:
		_assert_animation_in_place(
			_animations[clip_name] as Animation,
			str(clip_name)
		)
	_select_clip(DEFAULT_IDLE_NAME)
	var idle_start := _time
	_toggle_play()
	await get_tree().create_timer(0.08).timeout
	var idle_native_position := _animation_player.current_animation_position
	assert(_playing, "idle preview stopped during native playback")
	assert(
		_animation_player.is_playing()
			and idle_native_position > idle_start + 0.01,
		"idle preview is not using AnimationPlayer's native clock"
	)
	_process(0.0)
	assert(
		absf(_time - idle_native_position) < 0.02,
		"studio transport drifted away from native animation playback"
	)
	_toggle_play()
	_select_clip(DEFAULT_WALK_NAME)
	_select_bone("mixamorigRightArm")
	assert(_selected_bone_index >= 0, "right arm bone is missing")
	_seek(0.0)
	var arm_at_start := _skeleton.get_bone_pose_rotation(_selected_bone_index)
	_seek(minf(0.42, _current_animation().length))
	var arm_during_walk := _skeleton.get_bone_pose_rotation(_selected_bone_index)
	assert(
		not arm_at_start.is_equal_approx(arm_during_walk),
		"walk clip does not drive the preview skeleton"
	)
	_time = minf(0.123, _current_animation().length)
	_pending_rotation = _skeleton.get_bone_pose_rotation(_selected_bone_index)
	_insert_rotation_key()
	var rotation_track := _find_bone_track(
		_current_animation(),
		"mixamorigRightArm",
		Animation.TYPE_ROTATION_3D
	)
	assert(rotation_track >= 0, "right arm rotation track is missing")
	assert(
		_current_animation().track_find_key(
			rotation_track,
			_time,
			Animation.FIND_MODE_APPROX
		) >= 0,
		"test key was not inserted"
	)
	_make_current_clip_in_place()
	_assert_animation_in_place(_current_animation(), _current_clip)
	var test_path := "user://player_animation_studio_selftest.tres"
	var exported := _current_animation().duplicate(true) as Animation
	assert(ResourceSaver.save(exported, test_path) == OK, "selftest export failed")
	var reloaded := ResourceLoader.load(test_path) as Animation
	assert(reloaded != null, "selftest export did not reload")
	assert(
		reloaded.get_track_count() == _current_animation().get_track_count(),
		"reloaded track count changed"
	)
	print(
		"STUDIO_SELFTEST_OK bones=",
		_skeleton.get_bone_count(),
		" clips=",
		_animations.keys(),
		" walk_tracks=",
		_current_animation().get_track_count()
	)
	get_tree().quit(0)


func _assert_animation_in_place(animation: Animation, clip_name: String) -> void:
	for track_index in animation.get_track_count():
		if (
			animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D
			or not _is_root_motion_track(animation, track_index)
			or animation.track_get_key_count(track_index) < 2
		):
			continue
		var first := animation.track_get_key_value(track_index, 0) as Vector3
		var last := animation.track_get_key_value(
			track_index,
			animation.track_get_key_count(track_index) - 1
		) as Vector3
		assert(
			absf(last.x - first.x) < 0.0001
				and absf(last.z - first.z) < 0.0001,
			"%s retains horizontal root travel on %s"
			% [clip_name, animation.track_get_path(track_index)]
		)


func _set_status(message: String, error := false) -> void:
	print(("STUDIO_ERROR " if error else "STUDIO ") + message)
	if _status != null:
		_status.text = message
		_status.add_theme_color_override(
			"font_color",
			DANGER if error else TEXT_DIM
		)


func _section_title(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _button(
	label: String,
	callback: Callable,
	primary := false,
	danger := false
) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	if primary:
		button.add_theme_color_override("font_color", PANEL_DEEP)
		button.add_theme_stylebox_override(
			"normal",
			_style_box(ACCENT, 7.0, 9.0)
		)
		button.add_theme_stylebox_override(
			"hover",
			_style_box(ACCENT_BRIGHT, 7.0, 9.0)
		)
	elif danger:
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_stylebox_override(
			"normal",
			_style_box(DANGER.darkened(0.24), 7.0, 9.0)
		)
		button.add_theme_stylebox_override(
			"hover",
			_style_box(DANGER, 7.0, 9.0)
		)
	button.pressed.connect(callback)
	return button


func _file_dialog(title: String, filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.use_native_dialog = true
	return dialog


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_color", "SpinBox", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_stylebox("panel", "PanelContainer", _style_box(PANEL, 9.0, 10.0))
	theme.set_stylebox("normal", "Button", _style_box(FIELD, 7.0, 9.0))
	theme.set_stylebox("hover", "Button", _style_box(FIELD_HOVER, 7.0, 9.0))
	theme.set_stylebox("pressed", "Button", _style_box(ACCENT.darkened(0.25), 7.0, 9.0))
	theme.set_stylebox("normal", "LineEdit", _style_box(FIELD, 6.0, 8.0))
	theme.set_stylebox("focus", "LineEdit", _outline_box(FIELD, ACCENT, 6.0, 8.0))
	theme.set_stylebox("normal", "SpinBox", _style_box(FIELD, 6.0, 8.0))
	theme.set_stylebox("focus", "SpinBox", _outline_box(FIELD, ACCENT, 6.0, 8.0))
	theme.set_stylebox("panel", "ItemList", _style_box(PANEL_DEEP, 6.0, 5.0))
	theme.set_stylebox("selected", "ItemList", _style_box(ACCENT.darkened(0.38), 5.0, 5.0))
	theme.set_stylebox("panel", "Tree", _style_box(PANEL_DEEP, 6.0, 5.0))
	theme.set_stylebox("selected", "Tree", _style_box(ACCENT.darkened(0.38), 5.0, 4.0))
	return theme


func _style_box(color: Color, radius: float, content_margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = int(radius)
	box.corner_radius_top_right = int(radius)
	box.corner_radius_bottom_left = int(radius)
	box.corner_radius_bottom_right = int(radius)
	box.content_margin_left = content_margin
	box.content_margin_right = content_margin
	box.content_margin_top = content_margin
	box.content_margin_bottom = content_margin
	return box


func _outline_box(
	color: Color,
	border_color: Color,
	radius: float,
	content_margin: float
) -> StyleBoxFlat:
	var box := _style_box(color, radius, content_margin)
	box.border_color = border_color
	box.border_width_left = 1
	box.border_width_right = 1
	box.border_width_top = 1
	box.border_width_bottom = 1
	return box
