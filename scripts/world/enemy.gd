class_name Enemy
extends CharacterBody3D
## Scene-side enemy actor: readable telegraphs, short encounters, no home
## invasion (leashed to its landmark). Health/loot resolve in CombatManager.

signal died(slot_id: String)

enum Phase { IDLE, CHASE, TELEGRAPH, STRIKE, RECOVER, DEAD }

var core: GameCore
var definition: Defs.EnemyDefinition
var landmark_id: String
var slot_id: String
var home_point: Vector3
var leash_radius := 7.0
var player: PlayerController

var phase: Phase = Phase.IDLE
var _phase_timer := 0.0
var _visual: Node3D
var _telegraph_ring: MeshInstance3D


func setup(game_core: GameCore, assets: AssetLibrary, enemy_def: Defs.EnemyDefinition, owning_landmark: String, slot: String, spawn_point: Vector3, target: PlayerController) -> void:
	core = game_core
	definition = enemy_def
	landmark_id = owning_landmark
	slot_id = slot
	home_point = spawn_point
	player = target
	position = spawn_point
	add_to_group("enemies")

	_visual = assets.instantiate(enemy_def.asset_id)
	add_child(_visual)
	if enemy_def.guardian:
		_visual.scale = Vector3.ONE * 1.15

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.0
	shape.shape = capsule
	shape.position.y = 0.5
	add_child(shape)

	_telegraph_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.62
	_telegraph_ring.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.6, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_ring.material_override = mat
	_telegraph_ring.position.y = 0.06
	_telegraph_ring.visible = false
	add_child(_telegraph_ring)


func _physics_process(delta: float) -> void:
	if phase == Phase.DEAD or player == null:
		return
	_phase_timer -= delta
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	match phase:
		Phase.IDLE:
			velocity = Vector3.ZERO
			if distance < 5.0 and global_position.distance_to(home_point) < leash_radius:
				phase = Phase.CHASE
		Phase.CHASE:
			if distance <= definition.attack_range:
				_begin_telegraph()
			elif global_position.distance_to(home_point) > leash_radius:
				_return_home(delta)
			else:
				velocity = to_player.normalized() * definition.move_speed
				_face(to_player)
		Phase.TELEGRAPH:
			velocity = Vector3.ZERO
			_face(to_player)
			if _phase_timer <= 0.0:
				_strike(distance)
		Phase.STRIKE:
			velocity = Vector3.ZERO
			if _phase_timer <= 0.0:
				phase = Phase.RECOVER
				_phase_timer = definition.recover_seconds
		Phase.RECOVER:
			velocity = Vector3.ZERO
			if _phase_timer <= 0.0:
				phase = Phase.CHASE
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	move_and_slide()


func _begin_telegraph() -> void:
	phase = Phase.TELEGRAPH
	_phase_timer = definition.telegraph_seconds
	_telegraph_ring.visible = true
	_telegraph_ring.scale = Vector3.ONE * 0.5
	var tween := _telegraph_ring.create_tween()
	tween.tween_property(_telegraph_ring, "scale", Vector3.ONE, definition.telegraph_seconds).set_trans(Tween.TRANS_QUAD)
	if core != null:
		get_tree().call_group("audio_bridge", "play_event", "enemy_telegraph")


func _strike(distance: float) -> void:
	_telegraph_ring.visible = false
	phase = Phase.STRIKE
	_phase_timer = 0.25
	var lunge := _visual.create_tween()
	lunge.tween_property(_visual, "position:z", -0.3, 0.08)
	lunge.tween_property(_visual, "position:z", 0.0, 0.14)
	if definition.ranged:
		_fire_projectile()
	elif distance <= definition.attack_range + 0.35:
		player.take_hit(definition.damage)


func _fire_projectile() -> void:
	var projectile := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.11
	ball.height = 0.22
	projectile.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.5, 0.2)
	projectile.material_override = mat
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector3(0, 0.7, 0)
	var target := player.global_position + Vector3(0, 0.5, 0)
	var tween := projectile.create_tween()
	tween.tween_property(projectile, "global_position", target, 0.5).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		if is_instance_valid(player) and projectile.global_position.distance_to(player.global_position + Vector3(0, 0.5, 0)) < 0.8:
			player.take_hit(definition.damage)
		projectile.queue_free())


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 0.2)


func _return_home(_delta: float) -> void:
	var to_home := home_point - global_position
	to_home.y = 0.0
	if to_home.length() < 0.3:
		phase = Phase.IDLE
		velocity = Vector3.ZERO
	else:
		velocity = to_home.normalized() * definition.move_speed


func take_player_hit() -> void:
	if phase == Phase.DEAD:
		return
	var remaining := core.combat.damage_enemy(landmark_id, slot_id, definition.guardian)
	var flash := _visual.create_tween()
	flash.tween_property(_visual, "scale", _visual.scale * 1.12, 0.05)
	flash.tween_property(_visual, "scale", _visual.scale, 0.1)
	if remaining <= 0:
		_die()


func _die() -> void:
	phase = Phase.DEAD
	_telegraph_ring.visible = false
	var tween := _visual.create_tween()
	tween.set_parallel()
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "rotation:y", _visual.rotation.y + 3.0, 0.35)
	tween.chain().tween_callback(func():
		died.emit(slot_id)
		queue_free())


func reset_to_home() -> void:
	position = home_point
	phase = Phase.IDLE
	velocity = Vector3.ZERO
	_telegraph_ring.visible = false
