extends Node
## Same-world A/B profiler for the fixed interaction math. Run with
## --maxed-world to exercise 10,000 tiles and 10,000 placed models.

const SAVE_PATH := "user://water_interaction_performance_save.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.8).timeout
	if not _main._gameplay_started:
		push_error("Water performance runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	await _settle(150)

	var system := _main.effects.water_interaction
	var baseline := await _sample("water_interaction_idle", 2.0)
	# Freeze gameplay ownership while holding the shader at its maximum state;
	# otherwise the non-swimming stress-world player correctly decays the wake
	# before the A/B sample starts.
	system.set_process(false)
	var surface := Vector3(
		_main.player.global_position.x,
		_main.core.registries.tunef("water_level_y", -0.14),
		_main.player.global_position.z
	)
	for index in WaterInteractionSystem.IMPULSE_COUNT:
		var offset := Vector3(
			cos(TAU * index / float(WaterInteractionSystem.IMPULSE_COUNT)),
			0.0,
			sin(TAU * index / float(WaterInteractionSystem.IMPULSE_COUNT))
		) * 0.35
		system._write_impulse(surface + offset, 1.0)
	system._wake_strength = 1.0
	system._update_wake(surface)
	var active := await _sample("water_interaction_max_active", 2.0)
	var result := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"world": _main.renderer.debug_stats(),
		"idle": baseline,
		"active": active,
		"average_frame_delta_ms": (
			float(active["average_frame_ms"])
			- float(baseline["average_frame_ms"])
		),
		"water_interaction": system.runtime_manifest(),
	}
	print("WATER_INTERACTION_PERFORMANCE_RESULT ", JSON.stringify(result))
	get_tree().quit(0)


func _sample(label: String, seconds: float) -> Dictionary:
	var frame_times: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - previous) / 1000.0)
		previous = now
	frame_times.sort()
	var total := 0.0
	for value in frame_times:
		total += value
	var average := total / maxf(1.0, frame_times.size())
	var p95_index := clampi(
		int(floor(float(frame_times.size() - 1) * 0.95)),
		0,
		maxi(0, frame_times.size() - 1)
	)
	return {
		"label": label,
		"sample_frames": frame_times.size(),
		"average_frame_ms": snappedf(average, 0.001),
		"average_fps": snappedf(1000.0 / maxf(average, 0.001), 0.1),
		"p95_frame_ms": snappedf(frame_times[p95_index], 0.001),
		"engine_fps_at_end": Engine.get_frames_per_second(),
		"draw_calls_at_end": Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		),
	}


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame
