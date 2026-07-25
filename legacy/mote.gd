extends Node3D
# legacy-disabled class_name Mote

signal path_requested(mote: Mote)
signal seed_launch_requested(mote: Mote, token_id: StringName, world_position: Vector3)
signal departure_requested(mote: Mote)
signal departed(mote: Mote)
signal clicked(mote: Mote)

enum State {
	SPAWNING,
	ARRIVING,
	WANDERING,
	INTERACTING,
	READY_WITH_SEED,
	REWARDING_PLAYER,
	RELAXING,
	LEAVING,
}

const Factory := preload("res://scripts/visual_factory.gd")
const PixelArt := preload("res://scripts/pixel_art.gd")

var variant := 0
var token_id := &"meadow_coin"
var state := State.SPAWNING
var grid: GridManager
var grid_coord := Vector3i.ZERO
var path: Array[Vector3i] = []
var has_seed := true
var seed_node: Node3D
var body_root: Node3D
var area: Area3D
var rng := RandomNumberGenerator.new()
var speed := 1.45
var _state_time := 0.0
var _pause_time := 0.0
var _walk_phase := 0.0
var _base_body_y := 0.48
var _reward_locked := false
var planned_interaction := &""


func setup(
		variant_index: int,
		assigned_token: StringName,
		grid_manager: GridManager,
		start_coord: Vector3i
	) -> void:
	variant = posmod(variant_index, 3)
	token_id = assigned_token
	grid = grid_manager
	grid_coord = Vector3i(start_coord.x, 1, start_coord.z)
	rng.seed = hash("%d:%s:%s" % [variant, token_id, grid_coord])
	_build_visual()
	_build_area()
	position = grid.world_position(grid_coord)
	position.y -= 0.18
	scale = Vector3.ONE * 0.15
	state = State.SPAWNING
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 1.08, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", grid.world_position(grid_coord).y, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		state = State.ARRIVING
		path_requested.emit(self))


func _process(delta: float) -> void:
	_state_time += delta
	if body_root != null and state not in [State.REWARDING_PLAYER, State.LEAVING, State.INTERACTING]:
		body_root.scale.y = 1.0 + sin(_state_time * 2.0 + variant) * 0.025
	if seed_node != null and has_seed:
		seed_node.position.y = 0.36 + sin(_state_time * 2.6 + variant) * 0.045
		seed_node.rotation.y = _state_time * 1.1
	match state:
		State.ARRIVING, State.WANDERING, State.LEAVING:
			_process_path(delta)
		State.READY_WITH_SEED:
			_pause_time -= delta
			if _pause_time <= 0.0:
				_play_rare_idle()
				_pause_time = rng.randf_range(3.0, 6.5)
		State.RELAXING:
			_pause_time -= delta
			if _pause_time <= 0.0:
				departure_requested.emit(self)
				_pause_time = 999.0


func assign_path(new_path: Array[Vector3i], leaving := false) -> void:
	path = new_path.duplicate()
	if not path.is_empty() and path[0] == grid_coord:
		path.pop_front()
	state = State.LEAVING if leaving else (State.ARRIVING if state == State.SPAWNING else State.WANDERING)
	if path.is_empty():
		_on_path_complete()


func _process_path(delta: float) -> void:
	if path.is_empty():
		_on_path_complete()
		return
	var next: Vector3i = path[0]
	if not grid.is_walkable(next):
		path.clear()
		path_requested.emit(self)
		return
	var target := grid.world_position(next)
	var flat_delta := Vector3(target.x - position.x, 0, target.z - position.z)
	if flat_delta.length() > 0.03:
		rotation.y = lerp_angle(rotation.y, atan2(flat_delta.x, flat_delta.z), 1.0 - exp(-11.0 * delta))
	var previous := position
	position = position.move_toward(target, speed * delta)
	_walk_phase += previous.distance_to(position) * 9.0
	body_root.position.y = _base_body_y + absf(sin(_walk_phase)) * 0.13
	body_root.rotation.z = sin(_walk_phase * 0.5) * 0.045
	if position.distance_to(target) < 0.035:
		position = target
		grid_coord = next
		path.pop_front()
		if path.is_empty():
			_on_path_complete()


func _on_path_complete() -> void:
	body_root.position.y = _base_body_y
	body_root.rotation.z = 0.0
	if state == State.LEAVING:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position:y", position.y - 0.2, 0.42)
		tween.chain().tween_callback(func() -> void: departed.emit(self))
	elif has_seed:
		if planned_interaction != &"":
			_play_interaction(planned_interaction)
			planned_interaction = &""
		else:
			state = State.READY_WITH_SEED
			_pause_time = rng.randf_range(2.2, 4.8)
	else:
		state = State.RELAXING
		_pause_time = rng.randf_range(8.0, 15.0)


func collect_seed() -> bool:
	if not has_seed or _reward_locked or state == State.REWARDING_PLAYER:
		return false
	_reward_locked = true
	state = State.REWARDING_PLAYER
	var base_scale := Vector3.ONE
	var tween := create_tween()
	tween.tween_property(body_root, "scale", Vector3(1.10, 0.78, 1.10), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(body_root, "position:y", _base_body_y + 0.45, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(body_root, "scale", Vector3(0.88, 1.18, 0.88), 0.18)
	tween.tween_callback(func() -> void:
		if seed_node != null:
			seed_node.visible = false
		has_seed = false
		seed_launch_requested.emit(self, token_id, global_position + Vector3(0, 1.45, 0)))
	tween.tween_property(body_root, "position:y", _base_body_y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(body_root, "scale", base_scale, 0.18)
	return true


func reward_delivered() -> void:
	state = State.RELAXING
	_reward_locked = false
	_pause_time = rng.randf_range(8.0, 14.0)
	var tween := create_tween()
	tween.tween_property(body_root, "rotation:y", body_root.rotation.y + TAU, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(body_root, "scale", Vector3(1.08, 0.92, 1.08), 0.10)
	tween.tween_property(body_root, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_leaving(path_to_edge: Array[Vector3i]) -> void:
	assign_path(path_to_edge, true)


func plan_interaction(tag: StringName) -> void:
	planned_interaction = tag


func _play_interaction(tag: StringName) -> void:
	state = State.INTERACTING
	var tween := create_tween()
	if tag in [&"sit", &"tea", &"nap"]:
		tween.tween_property(body_root, "scale", Vector3(1.08, 0.72, 1.08), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.65)
		tween.tween_property(body_root, "scale", Vector3.ONE, 0.18)
	elif tag in [&"dance", &"walk_through"]:
		tween.tween_property(body_root, "rotation:y", body_root.rotation.y + TAU, 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(body_root, "rotation:z", 0.16, 0.15)
		tween.tween_property(body_root, "rotation:z", -0.10, 0.18)
		tween.tween_property(body_root, "rotation:z", 0.0, 0.14)
	tween.tween_callback(func() -> void:
		if has_seed:
			state = State.READY_WITH_SEED
			_pause_time = rng.randf_range(2.2, 4.8))


func _play_rare_idle() -> void:
	var choice := rng.randi_range(0, 2)
	var tween := create_tween()
	match choice:
		0:
			tween.tween_property(body_root, "rotation:y", body_root.rotation.y + 0.45, 0.18)
			tween.tween_property(body_root, "rotation:y", body_root.rotation.y - 0.25, 0.26)
		1:
			tween.tween_property(body_root, "position:y", _base_body_y + 0.13, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(body_root, "position:y", _base_body_y, 0.18)
		_:
			tween.tween_property(body_root, "rotation:z", 0.15, 0.16)
			tween.tween_property(body_root, "rotation:z", -0.10, 0.18)
			tween.tween_property(body_root, "rotation:z", 0.0, 0.12)


func _build_visual() -> void:
	body_root = Node3D.new()
	body_root.name = "ForestWispBody"
	body_root.position.y = _base_body_y
	add_child(body_root)
	var body := Sprite3D.new()
	body.name = "PixelWisp"
	body.texture = PixelArt.wisp_texture(variant, false)
	body.pixel_size = 0.042
	body.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body_root.add_child(body)
	_build_seed()


func _build_seed() -> void:
	seed_node = Node3D.new()
	seed_node.name = "CarriedForestLight"
	seed_node.position = Vector3(0.38, 0.40, -0.06)
	body_root.add_child(seed_node)
	var light_sprite := Sprite3D.new()
	light_sprite.texture = PixelArt.light_texture()
	light_sprite.pixel_size = 0.038
	light_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	light_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	light_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	light_sprite.shaded = false
	light_sprite.no_depth_test = true
	seed_node.add_child(light_sprite)
	var light := OmniLight3D.new()
	light.light_color = Color("#f0c45c")
	light.light_energy = 0.55
	light.omni_range = 1.5
	seed_node.add_child(light)


func _build_area() -> void:
	area = Area3D.new()
	area.name = "MoteClickArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("mote", self)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.72
	shape.height = 1.75
	collision.shape = shape
	collision.position.y = 0.62
	area.add_child(collision)
	add_child(area)
	area.input_event.connect(func(
			_camera: Node,
			event: InputEvent,
			_event_position: Vector3,
			_normal: Vector3,
			_shape_index: int
		) -> void:
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			clicked.emit(self)
			get_viewport().set_input_as_handled())
	area.mouse_entered.connect(func() -> void:
		if seed_node != null and has_seed:
			var tween := create_tween()
			tween.tween_property(seed_node, "scale", Vector3.ONE * 1.28, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	area.mouse_exited.connect(func() -> void:
		if seed_node != null:
			var tween := create_tween()
			tween.tween_property(seed_node, "scale", Vector3.ONE, 0.12))
