class_name HarvestPresentationAdapter
extends Node
## Juice only: the domain module remains authoritative and can be tested or
## automated with no scene tree.

signal feedback(kind: String, data: Dictionary)

var module: RefCounted
var renderer: WorldRenderer
var effects: EffectsManager
var audio: GameAudio


func setup(
	harvesting_module: RefCounted,
	world_renderer: WorldRenderer,
	effects_manager: EffectsManager,
	game_audio: GameAudio
) -> void:
	module = harvesting_module
	renderer = world_renderer
	effects = effects_manager
	audio = game_audio
	var adapter_ref: WeakRef = weakref(self)
	module.connect("hit_landed", func(instance_id, hit):
		var adapter := adapter_ref.get_ref() as HarvestPresentationAdapter
		if adapter != null:
			adapter._on_hit_landed(instance_id, hit)
	)
	module.connect("source_state_changed", func(instance_id, state, status):
		var adapter := adapter_ref.get_ref() as HarvestPresentationAdapter
		if adapter != null:
			adapter._on_source_state_changed(instance_id, state, status)
	)


func request_hit(instance_id: int, actor := "player") -> Dictionary:
	return module.call("request_hit", instance_id, actor)


func _on_hit_landed(instance_id: int, hit: Dictionary) -> void:
	# Rejected clicks never reach this presentation signal and stay silent.
	# The lifecycle supplies a presenter id, so host model ids never leak here.
	var presentation := String(hit.get("presentation", "soft_source"))
	if presentation == "berry_cluster":
		_present_berry_gather(instance_id, hit)
	elif presentation == "clay_rock":
		_present_rock_hit(instance_id, hit)
	else:
		_present_tree_hit(instance_id, hit)
	feedback.emit("final" if bool(hit.get("final", false)) else "hit", hit)


func _present_tree_hit(instance_id: int, hit: Dictionary) -> void:
	if audio != null:
		audio.play_event(
			"chop_impact",
			1.5 if bool(hit.get("final", false)) else 0.0,
			0.92 if bool(hit.get("final", false)) else 1.0
		)
	var visual := renderer.structure_node(instance_id)
	var point := (
		visual.global_position + Vector3(0.0, 0.65, 0.0)
		if visual != null else Vector3.ZERO
	)
	effects.flash_structure(instance_id, 0.075 if not hit["final"] else 0.13)
	effects.shake_structure_impact(instance_id, float(hit.get("progress", 0.0)))
	effects.burst(
		"fx_wood_chip", point,
		10 if bool(hit.get("final", false)) else 5 + int(hit.get("hit", 1))
	)
	if bool(hit.get("final", false)):
		effects.fell_structure(instance_id, func():
			renderer.refresh_structure_harvest(instance_id, true)
		)


func _present_berry_gather(instance_id: int, hit: Dictionary) -> void:
	if audio != null:
		audio.play_event("pickup", 0.5 if bool(hit.get("final", false)) else 0.0, 1.08)
	var visual := renderer.structure_node(instance_id)
	var point := (
		visual.global_position + Vector3(0.0, 0.38, 0.0)
		if visual != null else Vector3.ZERO
	)
	effects.flash_structure(instance_id, 0.1)
	effects.shake_structure_impact(instance_id, 0.24)
	effects.burst("fx_leaf", point, 7, 1.45)
	if bool(hit.get("final", false)):
		renderer.refresh_structure_harvest(instance_id, true)


func _present_rock_hit(instance_id: int, hit: Dictionary) -> void:
	if audio != null:
		audio.play_event(
			"place_stone",
			1.0 if bool(hit.get("final", false)) else -1.0,
			0.82 if bool(hit.get("final", false)) else 1.05
		)
	var visual := renderer.structure_node(instance_id)
	var point := (
		visual.global_position + Vector3(0.0, 0.24, 0.0)
		if visual != null else Vector3.ZERO
	)
	effects.flash_structure(instance_id, 0.085 if not hit["final"] else 0.14)
	effects.shake_structure_impact(instance_id, float(hit.get("progress", 0.0)))
	effects.burst(
		"fx_smoke_puff", point,
		9 if bool(hit.get("final", false)) else 3 + int(hit.get("hit", 1)),
		1.5
	)
	if bool(hit.get("final", false)):
		renderer.refresh_structure_harvest(instance_id, true)


func _on_source_state_changed(
	instance_id: int,
	state: String,
	status: Dictionary
) -> void:
	var presentation := String(status.get("presentation", "soft_source"))
	if state == "ready" or presentation != "clay_tree":
		renderer.refresh_structure_harvest(instance_id, true)
	if state == "ready":
		feedback.emit("ready", {
			"instance_id": instance_id,
			"presentation": presentation,
			"status": status.duplicate(true),
		})
