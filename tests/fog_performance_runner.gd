extends Node
## Same-world A/B profiler for the bounded world-space mist layers.
## Run with --maxed-world so Main builds 10,000 tiles and 10,000 models.

const SAVE_PATH := "user://fog_performance_save.json"

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
		push_error("Fog performance runner requires --maxed-world.")
		get_tree().quit(1)
		return
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	await _settle(180)

	# Isolate the mist renderer from the weather profile: both samples use the
	# exact same sun, post-processing, particles, and material state.
	_main.lighting.set_weather("mist")
	await get_tree().create_timer(1.2).timeout
	var mist_profile := _main.lighting.mist_profile
	var authored_density := mist_profile.ground_fog_density
	mist_profile.ground_fog_density = 0.0
	_main.lighting.apply_profile(mist_profile)
	await get_tree().create_timer(0.8).timeout
	var layers_off := await _sample("mist_layers_off", 2.5)
	mist_profile.ground_fog_density = authored_density
	_main.lighting.apply_profile(mist_profile)
	await get_tree().create_timer(0.8).timeout
	var mist := await _sample("mist_layers_on", 2.5)
	var mist_scroll := await _sample_scroll(3.0)
	var result := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"world": _main.renderer.debug_stats(),
		"mist_layers_off": layers_off,
		"mist": mist,
		"mist_scroll": mist_scroll,
		"fog": _main.lighting.runtime_manifest()["fog"],
		"average_frame_delta_ms": (
			float(mist["average_frame_ms"])
			- float(layers_off["average_frame_ms"])
		),
	}
	print("FOG_PERFORMANCE_RESULT ", JSON.stringify(result))
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
		"objects_at_end": Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		),
		"primitives_at_end": Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		),
	}


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
		"label": "mist_scroll",
		"sample_frames": frame_times.size(),
		"average_frame_ms": snappedf(average, 0.001),
		"average_fps": snappedf(1000.0 / maxf(average, 0.001), 0.1),
		"p95_frame_ms": snappedf(frame_times[p95_index], 0.001),
		"p99_frame_ms": snappedf(frame_times[p99_index], 0.001),
		"zoom_range": [20.0, 42.0],
		"zoom_changes": 4,
	}


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame
