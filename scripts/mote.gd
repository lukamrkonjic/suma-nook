extends Node3D
class_name Mote

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
		seed_node.position.y = 0.80 + sin(_state_time * 2.6 + variant) * 0.055
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
	body_root.name = "MoteBody"
	body_root.position.y = _base_body_y
	add_child(body_root)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 0.60
	body_mesh.radial_segments = 9
	body_mesh.rings = 5
	body.mesh = body_mesh
	var body_colors := [Color("#91b76f"), Color("#b190c2"), Color("#d39a61")]
	body.material_override = Factory.material("mote_body_%d" % variant, body_colors[variant])
	body_root.add_child(body)
	# Original visitor silhouettes: sprout hood, curled ears, or sunny bonnet.
	match variant:
		0:
			var hood := MeshInstance3D.new()
			var hood_mesh := CylinderMesh.new()
			hood_mesh.top_radius = 0.05
			hood_mesh.bottom_radius = 0.38
			hood_mesh.height = 0.36
			hood_mesh.radial_segments = 8
			hood.mesh = hood_mesh
			hood.material_override = Factory.material("mote_hood", Color("#9fb52e"))
			hood.position.y = 0.27
			body_root.add_child(hood)
		1:
			for side: float in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var ear_mesh := SphereMesh.new()
				ear_mesh.radius = 0.16
				ear_mesh.height = 0.22
				ear_mesh.radial_segments = 7
				ear_mesh.rings = 3
				ear.mesh = ear_mesh
				ear.material_override = Factory.material("mote_root_ear", Color("#c3683a"))
				ear.position = Vector3(side * 0.30, 0.13, 0)
				ear.rotation.z = side * 0.6
				ear.scale = Vector3(0.55, 1.2, 0.45)
				body_root.add_child(ear)
		2:
			var cap := MeshInstance3D.new()
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius = 0.08
			cap_mesh.bottom_radius = 0.42
			cap_mesh.height = 0.20
			cap_mesh.radial_segments = 9
			cap.mesh = cap_mesh
			cap.material_override = Factory.material("mote_cap", Color("#e59a32"))
			cap.position.y = 0.32
			body_root.add_child(cap)
	# Simple faces stay readable without competing with the diorama.
	for x: float in [-0.105, 0.105]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.055
		eye_mesh.radial_segments = 6
		eye_mesh.rings = 3
		eye.mesh = eye_mesh
		eye.material_override = Factory.material("mote_eye", Color("#44362d"))
		eye.position = Vector3(x, 0.06, -0.31)
		body_root.add_child(eye)
	_build_seed()


func _build_seed() -> void:
	seed_node = Node3D.new()
	seed_node.name = "CarriedCoin"
	seed_node.position = Vector3(0.36, 0.75, -0.06)
	body_root.add_child(seed_node)
	var coin := MeshInstance3D.new()
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.155
	coin_mesh.bottom_radius = 0.155
	coin_mesh.height = 0.065
	coin_mesh.radial_segments = 16
	coin.mesh = coin_mesh
	var token := Factory.coin_color(token_id)
	coin.material_override = Factory.material("coin_%s" % token_id, token, token.lightened(0.10))
	coin.rotation.x = PI * 0.5
	seed_node.add_child(coin)
	var stamp := MeshInstance3D.new()
	var stamp_mesh := CylinderMesh.new()
	stamp_mesh.top_radius = 0.064
	stamp_mesh.bottom_radius = 0.064
	stamp_mesh.height = 0.070
	stamp_mesh.radial_segments = 12
	stamp.mesh = stamp_mesh
	stamp.material_override = Factory.material("coin_stamp_%s" % token_id, token.lightened(0.30))
	stamp.rotation.x = PI * 0.5
	stamp.position.z = -0.012
	seed_node.add_child(stamp)
	var light := OmniLight3D.new()
	light.light_color = token
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
