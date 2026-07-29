extends Node
## Same-world A/B profiler for rain surface, ripple, and walking budgets.
## Run with --maxed-world for 10,000 tiles and 10,000 models.

const SAVE_PATH := "user://rain_performance_save.json"

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
		push_error("Rain performance runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	await _settle(180)

	var rain := _main.lighting.rain_profile
	var authored := [
		rain.rain_surface_wetness,
		rain.rain_puddle_amount,
		rain.rain_ripple_amount,
		rain.rain_walk_splash_amount,
	]
	rain.rain_surface_wetness = 0.0
	rain.rain_puddle_amount = 0.0
	rain.rain_ripple_amount = 0.0
	rain.rain_walk_splash_amount = 0.0
	_main.lighting.apply_profile(rain)
	await get_tree().create_timer(0.8).timeout
	var streaks_only := await _sample("rain_streaks_only", 2.5)

	rain.rain_surface_wetness = authored[0]
	rain.rain_puddle_amount = authored[1]
	rain.rain_ripple_amount = authored[2]
	rain.rain_walk_splash_amount = authored[3]
	_main.lighting.apply_profile(rain)
	await get_tree().create_timer(0.8).timeout
	var complete := await _sample("rain_complete", 2.5)
	var scrolling := await _sample_scroll(3.0)
	var result := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"world": _main.renderer.debug_stats(),
		"streaks_only": streaks_only,
		"complete": complete,
		"scrolling": scrolling,
		"rain_surface": _main.lighting.runtime_manifest()["rain_surface"],
		"average_frame_delta_ms": (
			float(complete["average_frame_ms"])
			- float(streaks_only["average_frame_ms"])
		),
	}
	print("RAIN_PERFORMANCE_RESULT ", JSON.stringify(result))
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
	return _sample_result(label, frame_times)


func _sample_scroll(seconds: float) -> Dictionary:
	var frame_times: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var next_zoom_change := 0.0
	var zoomed_out := false
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
		if elapsed >= next_zoom_change:
			zoomed_out = not zoomed_out
			_main.camera_rig._size_target = 42.0 if zoomed_out else 20.0
			_main.camera_rig.zoom_changed.emit(_main.camera_rig._size_target)
			next_zoom_change += 0.75
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - previous) / 1000.0)
		previous = now
	var result := _sample_result("rain_scroll", frame_times)
	result["zoom_range"] = [20.0, 42.0]
	result["zoom_changes"] = 4
	return result


func _sample_result(label: String, frame_times: Array[float]) -> Dictionary:
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
	var p99_index := clampi(
		int(floor(float(frame_times.size() - 1) * 0.99)),
		0,
		maxi(0, frame_times.size() - 1)
	)
	return {
		"label": label,
		"sample_frames": frame_times.size(),
		"average_frame_ms": snappedf(average, 0.001),
		"average_fps": snappedf(1000.0 / maxf(average, 0.001), 0.1),
		"p95_frame_ms": snappedf(frame_times[p95_index], 0.001),
		"p99_frame_ms": snappedf(frame_times[p99_index], 0.001),
		"engine_fps_at_end": Engine.get_frames_per_second(),
		"draw_calls_at_end": Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		),
	}


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame
