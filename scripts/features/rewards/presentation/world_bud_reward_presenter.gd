class_name WorldBudRewardPresenter
extends Node3D
## Non-modal, bounded-cost reward reveal. Ownership is committed before
## enqueue() is called; this node owns only anticipation, the real reward
## miniature, and collection motion. One scene is active at a time while
## pending duplicate rewards collapse into a single dictionary entry.

signal reveal_started(reward: Dictionary)
signal reward_shown(reward: Dictionary)
signal reveal_finished(reward: Dictionary)

const FAST_FORWARD_SCALE := 6.0
const BACKLOG_FAST_THRESHOLD := 4
const BACKLOG_DURATION_SCALE := 0.42

var registries: Registries
var assets: AssetLibrary
var grid: WorldGrid
var camera: Camera3D
var audio: GameAudio
var _tile_factory: TileVisualFactory
var _structure_factory: StructureVisualFactory
var _queue: Array[Dictionary] = []
var _draining := false
var _active_tween: Tween
var _fast_forward := false


func setup(
	content: Registries,
	asset_library: AssetLibrary,
	world_grid: WorldGrid,
	view_camera: Camera3D,
	game_audio: GameAudio
) -> void:
	registries = content
	assets = asset_library
	grid = world_grid
	camera = view_camera
	audio = game_audio
	_tile_factory = TileVisualFactory.new(assets, grid)
	_structure_factory = StructureVisualFactory.new(assets, grid)


func enqueue(
	reward: Dictionary,
	source_position: Vector3,
	reveal_profile_id: String
) -> void:
	if reward.is_empty() or registries.reward_reveal_profile(reveal_profile_id) == null:
		return
	# Repeated rewards waiting behind the active reveal share one ceremony.
	# This keeps rapid farms bounded without hiding what was actually granted.
	for pending: Dictionary in _queue:
		if (
			String(pending.get("reveal_profile_id", "")) == reveal_profile_id
			and String((pending.get("reward", {}) as Dictionary).get("kind", ""))
				== String(reward.get("kind", ""))
			and String((pending.get("reward", {}) as Dictionary).get("id", ""))
				== String(reward.get("id", ""))
		):
			var combined: Dictionary = pending["reward"]
			combined["amount"] = (
				int(combined.get("amount", 1)) + int(reward.get("amount", 1))
			)
			combined["was_new"] = (
				bool(combined.get("was_new", false))
				or bool(reward.get("was_new", false))
			)
			return
	_queue.append({
		"reward": reward.duplicate(true),
		"source_position": source_position,
		"reveal_profile_id": reveal_profile_id,
	})
	if not _draining:
		_draining = true
		call_deferred("_drain_queue")


func pending_count() -> int:
	return _queue.size() + int(_draining)


func is_revealing() -> bool:
	return _draining


func accelerate() -> void:
	if not _draining:
		return
	_fast_forward = true
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.set_speed_scale(FAST_FORWARD_SCALE)


func _unhandled_input(event: InputEvent) -> void:
	# Controller users can accelerate with the normal world-interact action.
	# The event remains unconsumed so the reveal never blocks harvesting/building.
	if (
		_draining
		and event.is_action_pressed("interact")
		and not event is InputEventMouseButton
	):
		accelerate()


func _drain_queue() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		_fast_forward = false
		await _play_entry(entry)
	_draining = false
	_active_tween = null


func _play_entry(entry: Dictionary) -> void:
	var reward: Dictionary = entry.get("reward", {})
	var profile: Defs.RewardRevealProfileDefinition = (
		registries.reward_reveal_profile(String(entry.get("reveal_profile_id", "")))
	)
	if profile == null:
		return
	var source_position: Vector3 = entry.get("source_position", Vector3.ZERO)
	var seed: int = abs(hash("%s|%s|%d" % [
		reward.get("kind", ""), reward.get("id", ""), pending_count(),
	]))
	var angle := float(seed % 6283) / 1000.0
	var landing := source_position + Vector3(
		cos(angle) * 0.28,
		0.18,
		sin(angle) * 0.28
	)
	var bud := _build_bud(profile)
	bud.position = source_position + Vector3.UP * 0.42
	add_child(bud)
	_bind_pointer_acceleration(bud)
	reveal_started.emit(reward.duplicate(true))
	if audio != null:
		audio.play_event("parcel_appear", -1.0, 1.08)

	var start := bud.position
	var landing_tween := create_tween()
	_active_tween = landing_tween
	_apply_tween_speed(landing_tween)
	landing_tween.tween_method(func(progress: float):
		bud.position = start.lerp(landing, progress)
		bud.position.y += sin(progress * PI) * 0.32
		bud.rotation.y = progress * TAU * 0.72
	, 0.0, 1.0, _duration(profile.landing_seconds)).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	await landing_tween.finished

	var anticipation := create_tween()
	_active_tween = anticipation
	_apply_tween_speed(anticipation)
	anticipation.tween_property(
		bud, "scale", Vector3(1.18, 0.76, 1.18),
		_duration(profile.anticipation_seconds * 0.42)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	anticipation.tween_property(
		bud, "scale", Vector3(0.88, 1.24, 0.88),
		_duration(profile.anticipation_seconds * 0.58)
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await anticipation.finished

	var reveal_root := Node3D.new()
	reveal_root.name = "RevealedReward"
	reveal_root.position = landing + Vector3.UP * 0.2
	reveal_root.scale = Vector3.ONE * 0.04
	add_child(reveal_root)
	var miniature := create_reward_visual(reward, profile.miniature_size)
	reveal_root.add_child(miniature)

	if audio != null:
		audio.play_event("parcel_reveal", 0.0, 1.0)
		if String(reward.get("rarity", "common")) == "rare":
			audio.play_event("reward_rare")
		else:
			audio.play_event("reward_common", -1.0, 1.04)
	reward_shown.emit(reward.duplicate(true))
	var reveal := create_tween()
	_active_tween = reveal
	_apply_tween_speed(reveal)
	reveal.set_parallel()
	reveal.tween_property(
		bud, "scale", Vector3.ONE * 0.04, _duration(profile.reveal_seconds)
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	reveal.tween_property(
		bud, "position:y", bud.position.y + 0.22, _duration(profile.reveal_seconds)
	)
	reveal.tween_property(
		reveal_root, "scale", Vector3.ONE, _duration(profile.reveal_seconds)
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(
		reveal_root, "rotation:y", TAU * 0.82, _duration(profile.reveal_seconds)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await reveal.finished
	bud.queue_free()

	var display_seconds := profile.display_seconds
	if bool(reward.get("was_new", false)):
		display_seconds += profile.new_discovery_bonus_seconds
	if display_seconds > 0.0:
		var display := create_tween()
		_active_tween = display
		_apply_tween_speed(display)
		display.tween_property(
			reveal_root, "rotation:y", reveal_root.rotation.y + 0.34,
			_duration(display_seconds)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await display.finished

	var collect_target := _collection_target(reveal_root.global_position)
	var collect := create_tween()
	_active_tween = collect
	_apply_tween_speed(collect)
	collect.set_parallel()
	collect.tween_property(
		reveal_root, "global_position", collect_target,
		_duration(profile.collect_seconds)
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	collect.tween_property(
		reveal_root, "scale", Vector3.ONE * 0.035,
		_duration(profile.collect_seconds)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await collect.finished
	reveal_root.queue_free()
	reveal_finished.emit(reward.duplicate(true))


func create_reward_visual(
	reward: Dictionary,
	target_size: float = 0.42
) -> Node3D:
	var holder := Node3D.new()
	holder.name = "RewardMiniature"
	var visual: Node3D
	match String(reward.get("kind", "")):
		"tile":
			var tile := registries.tile(String(reward.get("id", "")))
			if tile != null:
				visual = _tile_factory.instantiate_visual(tile, true)
		"structure":
			var structure := registries.structure(String(reward.get("id", "")))
			if structure != null:
				visual = _structure_factory.instantiate_visual(
					structure, false, hash(String(reward.get("id", "")))
				)
	if visual == null:
		visual = _fallback_charm()
	holder.add_child(visual)
	var bounds_data := StructureVisualFactory.local_mesh_bounds(holder)
	if bool(bounds_data.get("found", false)):
		var bounds: AABB = bounds_data["bounds"]
		var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if largest > 0.0001:
			var fit := target_size / largest
			visual.scale *= fit
			visual.position -= (bounds.position + bounds.size * 0.5) * fit
	return holder


func _build_bud(profile: Defs.RewardRevealProfileDefinition) -> Node3D:
	var bud := Node3D.new()
	bud.name = "WorldBud"
	var shell := assets.materials.material(profile.shell_material)
	var accent := assets.materials.material(profile.accent_material)
	if profile.shell_shape == "berry":
		for offset in [
			Vector3(-0.065, 0.0, 0.0), Vector3(0.065, 0.0, 0.0),
			Vector3(0.0, 0.055, -0.045), Vector3(0.0, -0.025, 0.055),
		]:
			var lobe := _sphere(shell, Vector3(0.13, 0.145, 0.13))
			lobe.position = offset
			bud.add_child(lobe)
		var leaf := _sphere(accent, Vector3(0.11, 0.025, 0.055))
		leaf.position = Vector3(0.03, 0.15, 0.0)
		leaf.rotation.z = -0.32
		bud.add_child(leaf)
	else:
		var body := _sphere(shell, Vector3(0.155, 0.19, 0.155))
		bud.add_child(body)
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.11
		cap_mesh.bottom_radius = 0.17
		cap_mesh.height = 0.075
		cap_mesh.radial_segments = 10
		var cap := _mesh(cap_mesh, accent)
		cap.position.y = 0.15
		bud.add_child(cap)
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.018
		stem_mesh.bottom_radius = 0.026
		stem_mesh.height = 0.09
		stem_mesh.radial_segments = 7
		var stem := _mesh(stem_mesh, accent)
		stem.position = Vector3(0.025, 0.225, 0.0)
		stem.rotation.z = -0.18
		bud.add_child(stem)
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = 0.22
	glow_mesh.bottom_radius = 0.22
	glow_mesh.height = 0.008
	glow_mesh.radial_segments = 18
	var glow := _mesh(glow_mesh, assets.materials.material(profile.glow_material))
	glow.name = "BudGlow"
	glow.position.y = -0.205
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bud.add_child(glow)
	return bud


func _bind_pointer_acceleration(bud: Node3D) -> void:
	var area := Area3D.new()
	area.name = "WorldBudInteraction"
	area.collision_layer = 1 << 18
	area.collision_mask = 0
	area.input_ray_pickable = true
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.28
	collision.shape = shape
	area.add_child(collision)
	bud.add_child(area)
	area.input_event.connect(func(
		_camera: Node, event: InputEvent, _position: Vector3,
		_normal: Vector3, _shape_index: int
	):
		if event.is_action_pressed("interact"):
			accelerate()
			get_viewport().set_input_as_handled()
	)


func _fallback_charm() -> Node3D:
	var charm := Node3D.new()
	var body := _sphere(
		assets.materials.material("magic"), Vector3(0.14, 0.18, 0.08)
	)
	charm.add_child(body)
	var center := _sphere(
		assets.materials.material("tilekit_accent_cream"),
		Vector3.ONE * 0.055
	)
	center.position.z = -0.075
	charm.add_child(center)
	return charm


func _sphere(material: Material, size: Vector3) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 5
	var instance := _mesh(sphere, material)
	instance.scale = size * 2.0
	return instance


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance


func _collection_target(fallback: Vector3) -> Vector3:
	if camera == null or not is_instance_valid(camera):
		return fallback + Vector3.UP * 1.2
	var basis := camera.global_transform.basis
	return (
		camera.global_position
		- basis.z * 1.25
		+ basis.x * 0.72
		- basis.y * 0.42
	)


func _duration(seconds: float) -> float:
	var backlog_scale := (
		BACKLOG_DURATION_SCALE
		if _queue.size() >= BACKLOG_FAST_THRESHOLD else 1.0
	)
	var input_scale := 0.2 if _fast_forward else 1.0
	return maxf(0.015, seconds * backlog_scale * input_scale)


func _apply_tween_speed(tween: Tween) -> void:
	if _fast_forward:
		tween.set_speed_scale(FAST_FORWARD_SCALE)
