class_name PlayerAnimationTimeline
extends Control
## Compact timeline derived from Imota's custom animation-strip workflow, adapted
## to Godot Skeleton3D animation tracks instead of Imota's procedural pivot rig.

signal seek_requested(time: float)
signal key_selected(track_index: int, key_index: int)
signal bone_selected(bone_name: String)

const LABEL_WIDTH := 184.0
const RULER_HEIGHT := 28.0
const ROW_HEIGHT := 23.0
const KEY_HIT_RADIUS := 8.0
const COLOR_BG := Color("#151922")
const COLOR_ROW := Color("#1c212c")
const COLOR_ROW_ALT := Color("#202631")
const COLOR_GRID := Color(0.35, 0.39, 0.47, 0.24)
const COLOR_TEXT := Color("#c8ced9")
const COLOR_TEXT_DIM := Color("#7f8999")
const COLOR_KEY := Color("#dcae62")
const COLOR_KEY_SELECTED := Color("#fff1b2")
const COLOR_PLAYHEAD := Color("#ef767a")
const COLOR_BONE_SELECTED := Color(0.30, 0.48, 0.67, 0.32)

var animation: Animation
var playhead := 0.0
var pixels_per_second := 260.0
var selected_track := -1
var selected_key := -1
var selected_bone := ""
var rows: Array[Dictionary] = []


func set_animation(value: Animation) -> void:
	animation = value
	selected_track = -1
	selected_key = -1
	_rebuild_rows()


func set_playhead(value: float) -> void:
	playhead = value
	queue_redraw()


func set_selected_bone(value: String) -> void:
	selected_bone = value
	queue_redraw()


func select_key(track_index: int, key_index: int) -> void:
	selected_track = track_index
	selected_key = key_index
	queue_redraw()


func refresh() -> void:
	_rebuild_rows()


func _rebuild_rows() -> void:
	rows.clear()
	if animation == null:
		custom_minimum_size = Vector2(600.0, RULER_HEIGHT + ROW_HEIGHT)
		queue_redraw()
		return
	for track_index in animation.get_track_count():
		var type := animation.track_get_type(track_index)
		if type not in [
			Animation.TYPE_POSITION_3D,
			Animation.TYPE_ROTATION_3D,
			Animation.TYPE_SCALE_3D,
		]:
			continue
		var path := String(animation.track_get_path(track_index))
		var bone_name := path.get_slice(":", 1) if path.contains(":") else path
		var suffix := ""
		match type:
			Animation.TYPE_POSITION_3D:
				suffix = "  · pos"
			Animation.TYPE_SCALE_3D:
				suffix = "  · scale"
			_:
				suffix = ""
		rows.append({
			"track": track_index,
			"bone": bone_name,
			"label": bone_name.trim_prefix("mixamorig") + suffix,
		})
	var width := LABEL_WIDTH + maxf(
		720.0,
		(float(animation.length) + 0.35) * pixels_per_second
	)
	custom_minimum_size = Vector2(
		width,
		RULER_HEIGHT + maxf(1.0, float(rows.size())) * ROW_HEIGHT
	)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if animation == null:
		draw_string(
			get_theme_default_font(),
			Vector2(18.0, 30.0),
			"No animation loaded",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			COLOR_TEXT_DIM
		)
		return
	var visible_rect := get_rect()
	var tick_step := _tick_step()
	var tick := 0.0
	while tick <= animation.length + 0.0001:
		var x := LABEL_WIDTH + tick * pixels_per_second
		draw_line(
			Vector2(x, RULER_HEIGHT - 6.0),
			Vector2(x, size.y),
			COLOR_GRID,
			1.0
		)
		draw_string(
			get_theme_default_font(),
			Vector2(x + 4.0, 18.0),
			"%.2f" % tick,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			COLOR_TEXT_DIM
		)
		tick += tick_step
	for row_index in rows.size():
		var row := rows[row_index]
		var y := RULER_HEIGHT + float(row_index) * ROW_HEIGHT
		var color := COLOR_ROW if row_index % 2 == 0 else COLOR_ROW_ALT
		draw_rect(Rect2(0.0, y, size.x, ROW_HEIGHT), color)
		if str(row["bone"]) == selected_bone:
			draw_rect(
				Rect2(0.0, y, size.x, ROW_HEIGHT),
				COLOR_BONE_SELECTED
			)
		draw_line(
			Vector2(0.0, y + ROW_HEIGHT),
			Vector2(size.x, y + ROW_HEIGHT),
			COLOR_GRID
		)
		draw_string(
			get_theme_default_font(),
			Vector2(10.0, y + 16.0),
			str(row["label"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			LABEL_WIDTH - 16.0,
			12,
			COLOR_TEXT
		)
		var track_index := int(row["track"])
		for key_index in animation.track_get_key_count(track_index):
			var key_time := animation.track_get_key_time(track_index, key_index)
			var key_x := LABEL_WIDTH + key_time * pixels_per_second
			var center := Vector2(key_x, y + ROW_HEIGHT * 0.5)
			var key_color := (
				COLOR_KEY_SELECTED
				if track_index == selected_track and key_index == selected_key
				else COLOR_KEY
			)
			var key_radius := (
				5.2
				if track_index == selected_track and key_index == selected_key
				else 3.7
			)
			var diamond := PackedVector2Array([
				center + Vector2(0.0, -key_radius),
				center + Vector2(key_radius, 0.0),
				center + Vector2(0.0, key_radius),
				center + Vector2(-key_radius, 0.0),
			])
			draw_colored_polygon(diamond, key_color)
	var playhead_x := LABEL_WIDTH + playhead * pixels_per_second
	draw_line(
		Vector2(playhead_x, 0.0),
		Vector2(playhead_x, size.y),
		COLOR_PLAYHEAD,
		2.0
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(playhead_x - 6.0, 0.0),
			Vector2(playhead_x + 6.0, 0.0),
			Vector2(playhead_x, 8.0),
		]),
		COLOR_PLAYHEAD
	)


func _gui_input(event: InputEvent) -> void:
	if animation == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			pixels_per_second = minf(pixels_per_second * 1.16, 900.0)
			_rebuild_rows()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pixels_per_second = maxf(pixels_per_second / 1.16, 70.0)
			_rebuild_rows()
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var click: Vector2 = event.position
		var time := clampf(
			(click.x - LABEL_WIDTH) / pixels_per_second,
			0.0,
			animation.length
		)
		if click.y >= RULER_HEIGHT:
			var row_index := int((click.y - RULER_HEIGHT) / ROW_HEIGHT)
			if row_index >= 0 and row_index < rows.size():
				var row := rows[row_index]
				var track_index := int(row["track"])
				var nearest := -1
				var nearest_distance := KEY_HIT_RADIUS + 1.0
				for key_index in animation.track_get_key_count(track_index):
					var key_x := (
						LABEL_WIDTH
						+ animation.track_get_key_time(track_index, key_index)
						* pixels_per_second
					)
					var distance := absf(click.x - key_x)
					if distance < nearest_distance:
						nearest = key_index
						nearest_distance = distance
				selected_bone = str(row["bone"])
				bone_selected.emit(selected_bone)
				if nearest >= 0:
					selected_track = track_index
					selected_key = nearest
					time = animation.track_get_key_time(track_index, nearest)
					key_selected.emit(track_index, nearest)
		playhead = time
		seek_requested.emit(time)
		queue_redraw()
		accept_event()


func _tick_step() -> float:
	if pixels_per_second >= 500.0:
		return 0.1
	if pixels_per_second >= 220.0:
		return 0.25
	if pixels_per_second >= 110.0:
		return 0.5
	return 1.0
