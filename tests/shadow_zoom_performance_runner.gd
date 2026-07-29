extends Node
## Extreme 20-70 smooth-zoom benchmark for the fixed shadow envelope.
## Run with --maxed-world for 10,000 tiles and 10,000 models.

const SAVE_PATH := "user://shadow_zoom_performance_save.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Shadow zoom performance runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.lighting.set_weather("day")
	await _settle(180)

	var result := await _sample_zoom(5.0)
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["world"] = _main.renderer.debug_stats()
	result["directional_light"] = (
		_main.lighting.runtime_manifest()["directional_light"]
	)
	print("SHADOW_ZOOM_PERFORMANCE_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if bool(result["stable_envelope"]) else 1)


func _sample_zoom(seconds: float) -> Dictionary:
	var frame_times: Array[float] = []
	var shadow_distances: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var next_zoom_change := 0.0
	var zoomed_out := false
	var zoom_changes := 0
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
		if elapsed >= next_zoom_change:
			zoomed_out = not zoomed_out
			_main.camera_rig._size_target = 70.0 if zoomed_out else 20.0
			_main.camera_rig.zoom_changed.emit(_main.camera_rig._size_target)
			next_zoom_change += 1.0
			zoom_changes += 1
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - previous) / 1000.0)
		previous = now
		shadow_distances.append(float(
			_main.lighting.runtime_manifest()["directional_light"]["shadow_max_distance"]
		))
	frame_times.sort()
	shadow_distances.sort()
	var total := 0.0
	for value in frame_times:
		total += value
	var average := total / maxf(1.0, frame_times.size())
	var p95_index := clampi(
		int(floor(float(frame_times.size() - 1) * 0.95)),
		0,
		maxi(0, frame_times.size() - 1)
	)
	var p99_index := clampi(
		int(floor(float(frame_times.size() - 1) * 0.99)),
		0,
		maxi(0, frame_times.size() - 1)
	)
	var minimum_shadow: float = shadow_distances.front()
	var maximum_shadow: float = shadow_distances.back()
	return {
		"label": "fixed_shadow_extreme_zoom",
		"sample_frames": frame_times.size(),
		"average_frame_ms": snappedf(average, 0.001),
		"average_fps": snappedf(1000.0 / maxf(average, 0.001), 0.1),
		"p95_frame_ms": snappedf(frame_times[p95_index], 0.001),
		"p99_frame_ms": snappedf(frame_times[p99_index], 0.001),
		"engine_fps_at_end": Engine.get_frames_per_second(),
		"zoom_range": [20.0, 70.0],
		"zoom_changes": zoom_changes,
		"shadow_distance_min": minimum_shadow,
		"shadow_distance_max": maximum_shadow,
		"stable_envelope": is_equal_approx(minimum_shadow, maximum_shadow),
		"draw_calls_at_end": Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		),
	}


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame
