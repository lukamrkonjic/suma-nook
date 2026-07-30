class_name EffectsManager
extends Node3D
## Small effects: world-space particles, bobber + ripples, reward arcs,
## vegetation shakes, placement dust, and screen-space click confirmation.

var assets: AssetLibrary
var _bobber: Node3D
var _bobber_tween: Tween
var _click_layer: CanvasLayer
var water_interaction: WaterInteractionSystem
var ground_impacts: GroundImpactEffects


func setup(asset_library: AssetLibrary) -> void:
	assets = asset_library
	_click_layer = CanvasLayer.new()
	_click_layer.name = "ClickFeedbackLayer"
	_click_layer.layer = 200
	add_child(_click_layer)
	_bobber = assets.instantiate("equip_bobber")
	_bobber.visible = false
	add_child(_bobber)


func bind_water_interaction(
	game_core: GameCore,
	player_controller: PlayerController
) -> void:
	if water_interaction != null:
		water_interaction.queue_free()
	water_interaction = WaterInteractionSystem.new()
	water_interaction.name = "WaterInteraction"
	add_child(water_interaction)
	water_interaction.setup(
		assets.materials.material("water") as ShaderMaterial,
		game_core,
		player_controller
	)


func bind_ground_impacts(
	game_core: GameCore,
	player_controller: PlayerController,
	game_audio: GameAudio
) -> void:
	if ground_impacts != null:
		ground_impacts.queue_free()
	ground_impacts = GroundImpactEffects.new()
	ground_impacts.name = "GroundImpacts"
	add_child(ground_impacts)
	ground_impacts.setup(
		game_core,
		player_controller,
		game_audio,
		assets.materials.palette
	)


func show_bobber(point: Vector3) -> void:
	_bobber.visible = true
	_bobber.position = point + Vector3(0, 1.4, 0)
	if _bobber_tween != null and _bobber_tween.is_valid():
		_bobber_tween.kill()
	_bobber_tween = create_tween()
	_bobber_tween.tween_property(_bobber, "position", point, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_bobber_tween.tween_property(_bobber, "position:y", point.y + 0.03, 0.5).set_trans(Tween.TRANS_SINE)
	_bobber_tween.tween_property(_bobber, "position:y", point.y, 0.5).set_trans(Tween.TRANS_SINE)
	_bobber_tween.set_loops()


func bobber_dip() -> void:
	if _bobber_tween != null and _bobber_tween.is_valid():
		_bobber_tween.kill()
	_bobber_tween = create_tween()
	_bobber_tween.tween_property(_bobber, "position:y", _bobber.position.y - 0.16, 0.09).set_trans(Tween.TRANS_QUAD)
	_bobber_tween.tween_property(_bobber, "position:y", _bobber.position.y, 0.14).set_trans(Tween.TRANS_BOUNCE)


func hide_bobber() -> void:
	if _bobber != null:
		_bobber.visible = false


func ripple(point: Vector3) -> void:
	var ring := assets.instantiate("fx_ripple_ring")
	add_child(ring)
	ring.position = Vector3(point.x, point.y + 0.03, point.z)
	ring.scale = Vector3.ONE * 0.3
	var tween := ring.create_tween()
	tween.set_parallel()
	tween.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "position:y", ring.position.y + 0.02, 0.8)
	tween.chain().tween_callback(ring.queue_free)
	_fade_out(ring, 0.8)


## Arc a small reward mote from the water/tree to the player; awaitable so the
## caller resolves rewards exactly at landing.
func arc_reward(from: Vector3, to: Vector3) -> void:
	var mote := assets.instantiate("fx_spark")
	add_child(mote)
	mote.position = from
	var mid := (from + to) * 0.5 + Vector3(0, 1.6, 0)
	var tween := mote.create_tween()
	var along := func(t: float) -> void:
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		mote.position = a.lerp(b, t)
	tween.tween_method(along, 0.0, 1.0, 0.5)
	await tween.finished
	mote.queue_free()


## Catch-and-release is an experience, not a pickup: a tiny stylized fish arcs
## to the keeper, pauses just long enough to read, then splashes home.
func catch_and_release(from: Vector3, reveal_at: Vector3) -> void:
	var fish := Node3D.new()
	fish.name = "CatchAndReleaseFish"
	add_child(fish)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.16
	body_mesh.height = 0.28
	body.mesh = body_mesh
	body.scale = Vector3(1.45, 0.75, 0.72)
	body.rotation.z = PI * 0.5
	body.material_override = assets.materials.material("gold")
	fish.add_child(body)
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.18, 0.14, 0.05)
	tail.mesh = tail_mesh
	tail.position.x = -0.2
	tail.rotation.z = PI * 0.25
	tail.material_override = assets.materials.material("fabric_accent")
	fish.add_child(tail)
	fish.position = from
	fish.scale = Vector3.ONE * 0.2
	var midpoint := (from + reveal_at) * 0.5 + Vector3(0, 1.45, 0)
	var tween := fish.create_tween()
	tween.set_parallel()
	tween.tween_property(fish, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var arc_in := func(t: float) -> void:
		var a := from.lerp(midpoint, t)
		var b := midpoint.lerp(reveal_at, t)
		fish.position = a.lerp(b, t)
	tween.tween_method(arc_in, 0.0, 1.0, 0.48)
	await tween.finished
	await get_tree().create_timer(0.42).timeout
	var release_mid := (reveal_at + from) * 0.5 + Vector3(0, 0.75, 0)
	tween = fish.create_tween()
	var arc_out := func(t: float) -> void:
		var a := reveal_at.lerp(release_mid, t)
		var b := release_mid.lerp(from, t)
		fish.position = a.lerp(b, t)
	tween.tween_method(arc_out, 0.0, 1.0, 0.36).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(fish, "scale", Vector3.ONE * 0.25, 0.36)
	await tween.finished
	fish.queue_free()
	ripple(from)


func burst(fx_asset: String, point: Vector3, count: int, up_bias := 2.4) -> void:
	for i in count:
		var chip := assets.instantiate(fx_asset)
		add_child(chip)
		chip.position = point
		chip.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4) * up_bias * 0.5, randf_range(-1, 1)).normalized()
		var distance := randf_range(0.4, 0.9)
		var tween := chip.create_tween()
		tween.set_parallel()
		tween.tween_property(chip, "position", point + dir * distance + Vector3(0, -0.4, 0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation", chip.rotation + Vector3(2, 3, 1), 0.55)
		tween.tween_property(chip, "scale", Vector3.ONE * 0.2, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(chip.queue_free)


func fire_ignition(point: Vector3, fire_width := 0.56) -> void:
	var count := maxi(8, roundi(14.0 * fire_width / 0.56))
	burst("fx_spark", point + Vector3.UP * 0.08, count, 3.2)


func fire_extinguish(point: Vector3, fire_width := 0.56) -> void:
	var smoke_material := StandardMaterial3D.new()
	smoke_material.albedo_color = Color(0.48, 0.46, 0.42, 0.5)
	smoke_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	)
	smoke_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_material.roughness = 1.0
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.radial_segments = 7
	puff_mesh.rings = 4
	var puff_count := maxi(5, roundi(8.0 * fire_width / 0.56))
	for index in puff_count:
		var angle := TAU * float(index) / float(puff_count)
		var puff := MeshInstance3D.new()
		puff.name = "ExtinguishSmoke"
		puff.mesh = puff_mesh
		puff.material_override = smoke_material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var radius := fire_width * randf_range(0.02, 0.18)
		puff.position = point + Vector3(
			cos(angle) * radius,
			randf_range(0.02, 0.1),
			sin(angle) * radius
		)
		puff.scale = Vector3.ONE * fire_width * randf_range(0.08, 0.13)
		puff.transparency = 0.22
		add_child(puff)
		var delay := float(index) * 0.025
		var rise := fire_width * randf_range(0.62, 0.95)
		var spread := Vector3(
			randf_range(-0.18, 0.18) * fire_width,
			rise,
			randf_range(-0.18, 0.18) * fire_width
		)
		var target_scale := Vector3(
			randf_range(0.3, 0.42),
			randf_range(0.22, 0.34),
			randf_range(0.28, 0.4)
		) * fire_width
		var motion := puff.create_tween()
		motion.tween_interval(delay)
		motion.tween_property(
			puff,
			"position",
			puff.position + spread,
			0.78
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		motion.parallel().tween_property(
			puff,
			"scale",
			target_scale,
			0.72
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var fade := puff.create_tween()
		fade.tween_interval(delay + 0.16)
		fade.tween_property(
			puff,
			"transparency",
			1.0,
			0.58
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		fade.tween_callback(puff.queue_free)


func shake_vegetation(coord: Vector2i) -> void:
	var renderer := get_parent().find_child("WorldRenderer", false, false) as WorldRenderer
	if renderer == null:
		return
	var node := renderer.tile_node(coord)
	if node == null or node.get_child_count() == 0:
		return
	var visual := node.get_child(0) as Node3D
	var tween := visual.create_tween()
	tween.tween_property(visual, "rotation:z", 0.03, 0.06)
	tween.tween_property(visual, "rotation:z", -0.02, 0.08)
	tween.tween_property(visual, "rotation:z", 0.0, 0.1)


func shake_structure(instance_id: int) -> void:
	var renderer := get_parent().find_child("WorldRenderer", false, false) as WorldRenderer
	if renderer == null:
		return
	var visual := renderer.structure_node(instance_id)
	if visual == null:
		return
	var base_rotation := visual.rotation.z
	var tween := visual.create_tween()
	tween.tween_property(visual, "rotation:z", base_rotation + 0.035, 0.06)
	tween.tween_property(visual, "rotation:z", base_rotation - 0.025, 0.08)
	tween.tween_property(visual, "rotation:z", base_rotation, 0.1)


func placement_poof(point: Vector3, kind: String) -> void:
	burst("fx_leaf" if kind == "grass" else "fx_smoke_puff", point + Vector3(0, 0.15, 0), 7, 1.6)


## A quiet screen-space confirmation at the literal cursor position. A thin
## halo carries visibility while the dot/cross remains small and understated.
func click_marker(screen_position: Vector2, interactive: bool) -> void:
	if _click_layer == null:
		return
	var marker := Node2D.new()
	marker.name = "ClickMarkerAction" if interactive else "ClickMarkerDot"
	marker.position = screen_position
	_click_layer.add_child(marker)

	var halo := Node2D.new()
	halo.name = "Halo"
	halo.scale = Vector2.ONE * 0.5
	halo.add_child(_marker_ring(8.0, Color(1.0, 0.95, 0.82, 0.48 if interactive else 0.4), 1.25))
	if interactive:
		halo.add_child(_marker_ring(11.0, Color(1.0, 0.9, 0.7, 0.24), 0.9))
	marker.add_child(halo)

	var glyph := Node2D.new()
	glyph.name = "Glyph"
	glyph.scale = Vector2.ONE * 0.82
	marker.add_child(glyph)
	var ink := Color(1.0, 0.95, 0.84, 0.96)
	var shadow := Color(0.12, 0.09, 0.05, 0.24)
	glyph.add_child(_marker_disc(3.7, shadow))
	glyph.add_child(_marker_disc(2.65, ink))
	if interactive:
		glyph.add_child(_marker_ring(6.2, Color(0.12, 0.09, 0.05, 0.18), 3.0))
		glyph.add_child(_marker_ring(6.0, Color(1.0, 0.9, 0.68, 0.94), 1.35))

	var halo_tween := halo.create_tween()
	halo_tween.set_parallel()
	halo_tween.tween_property(halo, "scale", Vector2.ONE * 1.45, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	halo_tween.tween_property(halo, "modulate:a", 0.0, 0.36).set_trans(Tween.TRANS_QUAD)

	var glyph_tween := glyph.create_tween()
	glyph_tween.tween_property(glyph, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	glyph_tween.tween_interval(0.1)
	glyph_tween.tween_property(glyph, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
	glyph_tween.tween_callback(marker.queue_free)


func _marker_ring(radius: float, color: Color, width: float) -> Line2D:
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for index in 25:
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 24.0) * radius)
	ring.points = points
	ring.width = width
	ring.default_color = color
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.antialiased = true
	return ring


func _marker_disc(radius: float, color: Color) -> Polygon2D:
	var disc := Polygon2D.new()
	var points := PackedVector2Array()
	for index in 16:
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 16.0) * radius)
	disc.polygon = points
	disc.color = color
	return disc


func _fade_out(node: Node3D, seconds: float) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		mesh_instance.transparency = 0.35
		var tween := mesh_instance.create_tween()
		tween.tween_property(mesh_instance, "transparency", 1.0, seconds)
