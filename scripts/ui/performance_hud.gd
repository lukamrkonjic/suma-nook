class_name PerformanceHud
extends CanvasLayer
## Lightweight in-game profiler. F3 toggles it in debug builds; the panel
## samples engine counters at 4 Hz so observing performance does not become a
## meaningful source of frame cost itself.

const SAMPLE_INTERVAL := 0.25
const BYTES_PER_MIB := 1024.0 * 1024.0

var core: GameCore
var renderer: WorldRenderer
var _panel: PanelContainer
var _label: Label
var _sample_accum := 0.0
var _smoothed_frame_ms := 0.0


func setup(game_core: GameCore, world_renderer: WorldRenderer) -> void:
	core = game_core
	renderer = world_renderer
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	set_process(true)


func toggle() -> bool:
	visible = not visible
	if visible:
		_refresh()
	return visible


func show_profiler() -> void:
	visible = true
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	var frame_ms := delta * 1000.0
	_smoothed_frame_ms = (
		frame_ms
		if _smoothed_frame_ms <= 0.0
		else lerpf(_smoothed_frame_ms, frame_ms, 0.12)
	)
	_sample_accum += delta
	if _sample_accum < SAMPLE_INTERVAL:
		return
	_sample_accum = 0.0
	_refresh()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PerformancePanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -350.0
	_panel.offset_top = 18.0
	_panel.offset_right = -18.0
	_panel.offset_bottom = 340.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.032, 0.90)
	style.border_color = Color(0.45, 0.78, 0.51, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 13.0
	style.content_margin_right = 13.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.name = "PerformanceReadout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", ThemeDB.fallback_font)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.88, 0.96, 0.88))
	_label.add_theme_constant_override("line_spacing", 2)
	_panel.add_child(_label)


func _refresh() -> void:
	if _label == null or core == null or renderer == null:
		return
	var stats := renderer.debug_stats()
	var fps := Engine.get_frames_per_second()
	var logic_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	))
	var objects := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
	))
	var primitives := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
	))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var static_mib := Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MIB
	var video_mib := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MIB
	_label.text = "\n".join([
		"F3  PERFORMANCE  [%s]" % String(stats.get("mode", "legacy")).to_upper(),
		"FPS %4d   FRAME %6.2f ms" % [fps, _smoothed_frame_ms],
		"CPU logic %5.2f ms   physics %5.2f ms" % [logic_ms, physics_ms],
		"DRAWS %6d   OBJECTS %6d" % [draws, objects],
		"TRIS/PRIMS %10d" % primitives,
		"NODES %7d   ORPHANS %4d" % [nodes, orphans],
		"RAM %7.1f MiB   VRAM %7.1f MiB" % [static_mib, video_mib],
		"",
		"WORLD tiles %d   models %d" % [
			core.grid.total_tile_count(),
			int(stats.get("models", 0)),
		],
		"RENDER INSTANCES %d" % int(stats.get("instances", 0)),
		"CHUNKS %d   BATCHES %d" % [
			int(stats.get("chunks", 0)),
			int(stats.get("batches", 0)),
		],
		"COLLIDERS %d   WATER %d   LIGHTS %d" % [
			int(stats.get("collision_chunks", 0)),
			int(stats.get("water_chunks", 0)),
			int(stats.get("warm_lights", 0)),
		],
	])
