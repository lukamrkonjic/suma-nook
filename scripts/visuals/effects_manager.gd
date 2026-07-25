class_name EffectsManager
extends Node3D
## Small pooled world-space effects: particle bursts from fx meshes, the
## fishing bobber + ripples, reward arcs, vegetation shakes, placement dust.

var assets: AssetLibrary
var _bobber: Node3D
var _bobber_tween: Tween


func setup(asset_library: AssetLibrary) -> void:
	assets = asset_library
	_bobber = assets.instantiate("equip_bobber")
	_bobber.visible = false
	add_child(_bobber)


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


func placement_poof(point: Vector3, kind: String) -> void:
	burst("fx_leaf" if kind == "grass" else "fx_smoke_puff", point + Vector3(0, 0.15, 0), 7, 1.6)


func _fade_out(node: Node3D, seconds: float) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		mesh_instance.transparency = 0.35
		var tween := mesh_instance.create_tween()
		tween.tween_property(mesh_instance, "transparency", 1.0, seconds)
