class_name CozyCloudLayer
extends Node3D
## Fixed-budget, high-altitude cloud field. The puffs are one MultiMesh draw,
## and that same geometry supplies soft world shadows through the existing sun.
## The camera climbs through the cloud altitude only at wide zoom, so close
## gameplay stays clear without a screen-space visibility trick.

const CLOUD_SHADER: Shader = preload("res://assets/materials/cozy_cloud.gdshader")

const CLOUD_ALTITUDE := 22.5
const CLOUD_CELL_SIZE := 7.5
const CLOUD_GRID_RADIUS := 5
const PUFFS_PER_CLOUD := 7
const WIND_METERS_PER_SECOND := Vector2(0.11, 0.045)

const PUFF_LAYOUT := [
	Vector3(0.00, 0.08, 0.00),
	Vector3(-0.23, -0.06, 0.03),
	Vector3(0.23, -0.05, -0.02),
	Vector3(-0.08, 0.23, -0.15),
	Vector3(0.10, 0.28, 0.14),
	Vector3(-0.36, -0.11, -0.07),
	Vector3(0.36, -0.12, 0.08),
]

const PUFF_SCALE := [
	Vector3(0.52, 0.67, 0.52),
	Vector3(0.47, 0.54, 0.49),
	Vector3(0.49, 0.57, 0.47),
	Vector3(0.43, 0.72, 0.42),
	Vector3(0.45, 0.78, 0.44),
	Vector3(0.38, 0.43, 0.40),
	Vector3(0.39, 0.45, 0.39),
]

var camera_focus: Node3D
var _puffs: MultiMeshInstance3D
var _wind_seconds := 0.0
var _camera_distance := 32.0
var _shadows_enabled := true
var _visible_cloud_count := 0
var _active_center_cell := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_puff_batch()
	_refresh_clouds(true)


func setup(focus: Node3D, initial_distance := 32.0) -> void:
	camera_focus = focus
	set_camera_distance(initial_distance)
	_refresh_clouds(true)


func _process(delta: float) -> void:
	_wind_seconds += delta
	var wind_offset := WIND_METERS_PER_SECOND * _wind_seconds
	global_position = Vector3(wind_offset.x, 0.0, wind_offset.y)
	_refresh_clouds(false)


func _build_puff_batch() -> void:
	_puffs = MultiMeshInstance3D.new()
	_puffs.name = "CloudPuffs"
	_puffs.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_puffs.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	sphere.material = material

	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = sphere
	batch.instance_count = (
		(2 * CLOUD_GRID_RADIUS + 1)
		* (2 * CLOUD_GRID_RADIUS + 1)
		* PUFFS_PER_CLOUD
	)
	batch.visible_instance_count = 0
	_puffs.multimesh = batch
	add_child(_puffs)


func _refresh_clouds(force: bool) -> void:
	if _puffs == null or _puffs.multimesh == null:
		return
	var focus_world := Vector2.ZERO
	if camera_focus != null:
		focus_world = Vector2(
			camera_focus.global_position.x,
			camera_focus.global_position.z
		)

	var wind_offset := WIND_METERS_PER_SECOND * _wind_seconds
	var still_focus := focus_world - wind_offset
	var center_cell := Vector2i(
		floori(still_focus.x / CLOUD_CELL_SIZE),
		floori(still_focus.y / CLOUD_CELL_SIZE)
	)
	if not force and center_cell == _active_center_cell:
		return
	_active_center_cell = center_cell
	_puffs.custom_aabb = AABB(
		Vector3(still_focus.x - 48.0, CLOUD_ALTITUDE - 5.0, still_focus.y - 48.0),
		Vector3(96.0, 11.0, 96.0)
	)

	var puff_index := 0
	_visible_cloud_count = 0
	for cell_z in range(
		center_cell.y - CLOUD_GRID_RADIUS,
		center_cell.y + CLOUD_GRID_RADIUS + 1
	):
		for cell_x in range(
			center_cell.x - CLOUD_GRID_RADIUS,
			center_cell.x + CLOUD_GRID_RADIUS + 1
		):
			var cell := Vector2i(cell_x, cell_z)
			# The camera sees only a narrow slice of this altitude. A 58%
			# occupancy puts one to three clusters in a far-zoom frame while
			# retaining broad calm gaps and preventing visible pop-in.
			if _random01(cell, 0) > 0.58:
				continue
			var jitter := Vector2(
				(_random01(cell, 1) - 0.5) * CLOUD_CELL_SIZE * 0.48,
				(_random01(cell, 2) - 0.5) * CLOUD_CELL_SIZE * 0.48
			)
			# Instances stay in procedural world coordinates. The parent node
			# supplies the tiny continuous wind transform on the render side,
			# so normal frames upload one Node3D transform rather than hundreds
			# of MultiMesh instance transforms.
			var local_center := Vector2(cell) * CLOUD_CELL_SIZE + jitter
			var heading := _random01(cell, 3) * TAU
			var cloud_length := lerpf(4.2, 7.0, _random01(cell, 4))
			var cloud_width := lerpf(2.6, 4.1, _random01(cell, 5))
			var cloud_height := lerpf(1.9, 2.8, _random01(cell, 6))
			var altitude_jitter := lerpf(-0.65, 0.8, _random01(cell, 7))
			var cloud_basis := Basis(Vector3.UP, heading)

			for puff in PUFFS_PER_CLOUD:
				var layout: Vector3 = PUFF_LAYOUT[puff]
				var rotated_offset := cloud_basis * Vector3(
					layout.x * cloud_length,
					layout.y * cloud_height,
					layout.z * cloud_width
				)
				var puff_size: Vector3 = PUFF_SCALE[puff]
				var scale := Vector3(
					puff_size.x * cloud_width,
					puff_size.y * cloud_height,
					puff_size.z * cloud_width
				)
				var transform := Transform3D(
					cloud_basis.scaled(scale),
					Vector3(
						local_center.x,
						CLOUD_ALTITUDE + altitude_jitter,
						local_center.y
					) + rotated_offset
				)
				_puffs.multimesh.set_instance_transform(puff_index, transform)
				_puffs.multimesh.set_instance_custom_data(
					puff_index,
					Color(
						_random01(cell, 20 + puff),
						clampf((layout.y + 0.14) / 0.42, 0.0, 1.0),
						0.0,
						0.0
					)
				)
				puff_index += 1
			_visible_cloud_count += 1
	_puffs.multimesh.visible_instance_count = puff_index


func _random01(cell: Vector2i, salt: int) -> float:
	# Float hash avoids depending on engine/global RNG state, so the sky remains
	# stable across saves and unrelated gameplay random draws.
	var seed := float(cell.x * 127 + cell.y * 311 + salt * 74)
	var value := sin(seed * 0.173) * 43758.5453
	return value - floor(value)


func set_camera_distance(distance: float) -> void:
	_camera_distance = distance


func set_shadows_enabled(enabled: bool) -> void:
	_shadows_enabled = enabled
	if _puffs != null:
		_puffs.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


func shadows_enabled() -> bool:
	return _shadows_enabled


func visible_cloud_count() -> int:
	return _visible_cloud_count


func runtime_manifest() -> Dictionary:
	return {
		"implementation": "single_multimesh",
		"clouds": _visible_cloud_count,
		"visible_puffs": (
			_puffs.multimesh.visible_instance_count
			if _puffs != null and _puffs.multimesh != null
			else 0
		),
		"cloud_altitude": CLOUD_ALTITUDE,
		"camera_distance": _camera_distance,
		"shadows_enabled": _shadows_enabled,
		"visible_draw_passes": 1,
		"shadow_draw_passes": 1 if _shadows_enabled else 0,
	}
