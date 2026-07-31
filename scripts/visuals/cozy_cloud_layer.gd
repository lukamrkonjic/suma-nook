class_name CozyCloudLayer
extends Node3D
## Fixed-budget field of ray-marched cloud impostors. Every box contains a
## smooth, noise-eroded cumulus volume; the boxes share one MultiMesh draw.
## A second invisible MultiMesh supplies matching low-cost world shadows.

const CLOUD_VOLUME_SHADER: Shader = preload(
	"res://assets/materials/cozy_cloud.gdshader"
)
const CLOUD_ALTITUDE := 22.5
const CLOUD_CELL_SIZE := 9.0
const CLOUD_GRID_RADIUS := 6
const CLOUD_OCCUPANCY := 0.18
const CLOUD_REVEAL_START := 50.0
const CLOUD_REVEAL_END := 60.0
const WIND_METERS_PER_SECOND := Vector2(0.11, 0.045)
const SHADOW_PUFFS_PER_CLOUD := 7
const SHADOW_PROXY_LAYER_NUMBER := 19
const SHADOW_REVEAL_THRESHOLD := 0.42

const SHADOW_LAYOUT := [
	Vector3(0.00, -0.12, 0.00),
	Vector3(-0.29, -0.04, -0.03),
	Vector3(-0.10, 0.08, 0.06),
	Vector3(0.14, 0.04, -0.06),
	Vector3(0.33, -0.04, 0.03),
	Vector3(-0.16, 0.03, -0.20),
	Vector3(0.15, 0.13, 0.17),
]

const SHADOW_SCALE := [
	Vector3(0.47, 0.17, 0.31),
	Vector3(0.23, 0.24, 0.24),
	Vector3(0.27, 0.29, 0.27),
	Vector3(0.29, 0.27, 0.26),
	Vector3(0.20, 0.21, 0.22),
	Vector3(0.21, 0.20, 0.20),
	Vector3(0.20, 0.24, 0.19),
]

var camera_focus: Node3D
var _volumes: MultiMeshInstance3D
var _shadow_puffs: MultiMeshInstance3D
var _volume_material: ShaderMaterial
var _wind_seconds := 0.0
var _camera_distance := 32.0
var _visibility := 0.0
var _shadows_enabled := true
var _cloud_count := 0
var _view_camera: Camera3D
var _shadow_ray_direction := Vector3(-0.42, -0.82, -0.39).normalized()
var _shadow_anchor_cell := Vector2i.ZERO
var _sky_anchor_positions: Dictionary = {}
var _active_center_cell := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_volume_batch()
	_build_shadow_batch()
	_refresh_clouds(true)
	_apply_camera_distance()


func setup(
	focus: Node3D,
	initial_distance := 32.0,
	shadow_ray_direction := Vector3(-0.42, -0.82, -0.39)
) -> void:
	camera_focus = focus
	if shadow_ray_direction.length_squared() > 0.001:
		_shadow_ray_direction = shadow_ray_direction.normalized()
	_view_camera = get_viewport().get_camera_3d()
	if _view_camera != null:
		# Shadow proxies live on a light-visible layer that the gameplay
		# camera never draws. SHADOWS_ONLY remains as a second safeguard.
		_view_camera.set_cull_mask_value(
			SHADOW_PROXY_LAYER_NUMBER,
			false
		)
	set_camera_distance(initial_distance)
	_refresh_clouds(true)


func _process(delta: float) -> void:
	_wind_seconds += delta
	var wind_offset := WIND_METERS_PER_SECOND * _wind_seconds
	global_position = Vector3(wind_offset.x, 0.0, wind_offset.y)
	_refresh_clouds(false)


func _build_volume_batch() -> void:
	_volumes = MultiMeshInstance3D.new()
	_volumes.name = "RaymarchedCottonClouds"
	_volumes.physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)
	_volumes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_volumes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volumes.sorting_offset = 8.0

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_volume_material = ShaderMaterial.new()
	_volume_material.shader = CLOUD_VOLUME_SHADER
	box.material = _volume_material

	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = box
	batch.instance_count = _max_cloud_count()
	batch.visible_instance_count = 0
	_volumes.multimesh = batch
	add_child(_volumes)


func _build_shadow_batch() -> void:
	_shadow_puffs = MultiMeshInstance3D.new()
	_shadow_puffs.name = "CloudShadowCasters"
	_shadow_puffs.physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)
	_shadow_puffs.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_shadow_puffs.layers = 0
	_shadow_puffs.set_layer_mask_value(
		SHADOW_PROXY_LAYER_NUMBER,
		true
	)

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 5
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.30)
	material.roughness = 1.0
	sphere.material = material

	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = sphere
	batch.instance_count = (
		_max_cloud_count() * SHADOW_PUFFS_PER_CLOUD
	)
	batch.visible_instance_count = 0
	_shadow_puffs.multimesh = batch
	add_child(_shadow_puffs)
	_update_shadow_state()


func _max_cloud_count() -> int:
	var diameter := CLOUD_GRID_RADIUS * 2 + 1
	return diameter * diameter


func _refresh_clouds(force: bool) -> void:
	if (
		_volumes == null
		or _volumes.multimesh == null
		or _shadow_puffs == null
		or _shadow_puffs.multimesh == null
	):
		return
	var focus_world := Vector2.ZERO
	if camera_focus != null:
		focus_world = Vector2(
			camera_focus.global_position.x,
			camera_focus.global_position.z
		)
	var wind_offset := WIND_METERS_PER_SECOND * _wind_seconds
	var still_ground_focus := focus_world - wind_offset
	var field_focus := still_ground_focus
	var camera_horizontal := Vector2(1.0, 1.0).normalized()
	if _view_camera != null and camera_focus != null:
		# The visible center of a horizontal cloud plane is not vertically
		# above the player: it is where the camera-to-focus sightline crosses
		# CLOUD_ALTITUDE. Centering the grid there populates the entire screen
		# instead of leaving clouds stranded along its top and bottom edges.
		var focus_height := camera_focus.global_position.y
		var camera_height := (
			_view_camera.global_position.y - focus_height
		)
		if camera_height > 0.1:
			var altitude_fraction := (
				(CLOUD_ALTITUDE - focus_height) / camera_height
			)
			camera_horizontal = Vector2(
				_view_camera.global_position.x - focus_world.x,
				_view_camera.global_position.z - focus_world.y
			)
			field_focus += camera_horizontal * altitude_fraction
	camera_horizontal = camera_horizontal.normalized()
	var screen_right := Vector2(
		camera_horizontal.y,
		-camera_horizontal.x
	)
	_sky_anchor_positions.clear()
	var sky_targets := [
		{
			"position": field_focus + screen_right * 7.5
				+ camera_horizontal * 1.5,
			"scale": 0.82,
		},
		{
			"position": field_focus - screen_right * 8.5
				- camera_horizontal * 1.0,
			"scale": 1.22,
		},
	]
	for target: Dictionary in sky_targets:
		var target_position: Vector2 = target["position"]
		var target_cell := Vector2i(
			roundi(target_position.x / CLOUD_CELL_SIZE),
			roundi(target_position.y / CLOUD_CELL_SIZE)
		)
		_sky_anchor_positions[target_cell] = target
	var center_cell := Vector2i(
		floori(field_focus.x / CLOUD_CELL_SIZE),
		floori(field_focus.y / CLOUD_CELL_SIZE)
	)
	if not force and center_cell == _active_center_cell:
		return
	_active_center_cell = center_cell
	var shadow_drop := (
		CLOUD_ALTITUDE
		- (
			camera_focus.global_position.y
			if camera_focus != null
			else 0.0
		)
	)
	var shadow_travel := (
		shadow_drop / maxf(0.2, -_shadow_ray_direction.y)
	)
	var shadow_source := (
		still_ground_focus
		- Vector2(
			_shadow_ray_direction.x,
			_shadow_ray_direction.z
		) * shadow_travel
	)
	_shadow_anchor_cell = Vector2i(
		roundi(shadow_source.x / CLOUD_CELL_SIZE),
		roundi(shadow_source.y / CLOUD_CELL_SIZE)
	)
	var field_half_extent := (
		CLOUD_CELL_SIZE * float(CLOUD_GRID_RADIUS + 1) + 6.0
	)
	var bounds := AABB(
		Vector3(
			field_focus.x - field_half_extent,
			CLOUD_ALTITUDE - 5.0,
			field_focus.y - field_half_extent
		),
		Vector3(
			field_half_extent * 2.0,
			10.0,
			field_half_extent * 2.0
		)
	)
	_volumes.custom_aabb = bounds
	_shadow_puffs.custom_aabb = bounds

	var cloud_index := 0
	var shadow_index := 0
	for cell_z in range(
		center_cell.y - CLOUD_GRID_RADIUS,
		center_cell.y + CLOUD_GRID_RADIUS + 1
	):
		for cell_x in range(
			center_cell.x - CLOUD_GRID_RADIUS,
			center_cell.x + CLOUD_GRID_RADIUS + 1
		):
			var cell := Vector2i(cell_x, cell_z)
			var shadows_focus := cell == _shadow_anchor_cell
			var anchors_sky := _sky_anchor_positions.has(cell)
			if (
				not shadows_focus
				and not anchors_sky
				and _random01(cell, 0) > CLOUD_OCCUPANCY
			):
				continue
			var jitter := Vector2(
				(_random01(cell, 1) - 0.5) * CLOUD_CELL_SIZE * 0.82,
				(_random01(cell, 2) - 0.5) * CLOUD_CELL_SIZE * 0.82
			)
			var local_center := Vector2(cell) * CLOUD_CELL_SIZE + jitter
			if shadows_focus:
				# This cloud sits up-sun from the focus so its ordinary
				# directional shadow crosses the playable area. It remains
				# world-space and drifts with the same wind as every cloud.
				local_center = shadow_source + jitter * 0.12
			elif anchors_sky:
				var anchor: Dictionary = _sky_anchor_positions[cell]
				var anchor_position: Vector2 = anchor["position"]
				local_center = anchor_position + jitter * 0.12
			# Power curves make compact wisps common without removing the
			# occasional broad mist bank. Independent axes prevent a stamped,
			# uniformly scaled silhouette.
			var cloud_length := lerpf(
				4.2,
				10.4,
				pow(_random01(cell, 4), 1.45)
			)
			var cloud_height := lerpf(
				2.6,
				6.1,
				pow(_random01(cell, 5), 1.6)
			)
			var cloud_width := lerpf(
				3.4,
				8.2,
				pow(_random01(cell, 6), 1.5)
			)
			if anchors_sky:
				var anchor_scale := float(
					_sky_anchor_positions[cell]["scale"]
				)
				cloud_length *= anchor_scale
				cloud_height *= lerpf(0.94, 1.08, anchor_scale - 0.82)
				cloud_width *= anchor_scale
			var heading := _random01(cell, 3) * TAU
			var cloud_basis := Basis(Vector3.UP, heading)
			var origin := Vector3(
				local_center.x,
				CLOUD_ALTITUDE + lerpf(-0.55, 0.70, _random01(cell, 7)),
				local_center.y
			)
			_volumes.multimesh.set_instance_transform(
				cloud_index,
				Transform3D(
					cloud_basis.scaled(
						Vector3(
							cloud_length,
							cloud_height,
							cloud_width
						)
					),
					origin
				)
			)
			_volumes.multimesh.set_instance_custom_data(
				cloud_index,
				Color(
					_random01(cell, 8),
					_random01(cell, 9),
					_random01(cell, 10),
					1.0
				)
			)
			cloud_index += 1

			for puff_index in SHADOW_PUFFS_PER_CLOUD:
				var layout: Vector3 = SHADOW_LAYOUT[puff_index]
				var rotated_offset := cloud_basis * Vector3(
					layout.x * cloud_length,
					layout.y * cloud_height,
					layout.z * cloud_width
				)
				var puff_scale: Vector3 = SHADOW_SCALE[puff_index]
				_shadow_puffs.multimesh.set_instance_transform(
					shadow_index,
					Transform3D(
						cloud_basis.scaled(
							Vector3(
								puff_scale.x * cloud_length,
								puff_scale.y * cloud_height,
								puff_scale.z * cloud_width
							)
						),
						origin + rotated_offset
					)
				)
				shadow_index += 1

	_cloud_count = cloud_index
	_volumes.multimesh.visible_instance_count = cloud_index
	_shadow_puffs.multimesh.visible_instance_count = shadow_index


func _random01(cell: Vector2i, salt: int) -> float:
	var seed := float(cell.x * 127 + cell.y * 311 + salt * 74)
	var value := sin(seed * 0.173) * 43758.5453
	return value - floor(value)


func set_camera_distance(distance: float) -> void:
	_camera_distance = distance
	_apply_camera_distance()


func _apply_camera_distance() -> void:
	_visibility = smoothstep(
		CLOUD_REVEAL_START,
		CLOUD_REVEAL_END,
		_camera_distance
	)
	if _volumes != null:
		_volumes.visible = _visibility > 0.001
	if _volume_material != null:
		_volume_material.set_shader_parameter(
			"visibility_fade",
			_visibility
		)
	_update_shadow_state()


func set_shadows_enabled(enabled: bool) -> void:
	_shadows_enabled = enabled
	_update_shadow_state()


func _update_shadow_state() -> void:
	if _shadow_puffs == null:
		return
	_shadow_puffs.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if (
			_shadows_enabled
			and _visibility >= SHADOW_REVEAL_THRESHOLD
		)
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)


func shadows_enabled() -> bool:
	return _shadows_enabled


func visible_cloud_count() -> int:
	return _cloud_count


func runtime_manifest() -> Dictionary:
	return {
		"implementation": "raymarched_cumulus_impostor_multimesh",
		"clouds": _cloud_count,
		"occupancy": CLOUD_OCCUPANCY,
		"field_center_cell": _active_center_cell,
		"shadow_anchor_cell": _shadow_anchor_cell,
		"sky_anchor_cells": _sky_anchor_positions.keys(),
		"visible_volumes": (
			_cloud_count
			if _volumes != null and _volumes.visible
			else 0
		),
		"shadow_layers": 1 if _shadow_puffs != null else 0,
		"shadow_proxy_camera_layer": SHADOW_PROXY_LAYER_NUMBER,
		"shadow_proxies_camera_hidden": (
			_view_camera != null
			and not _view_camera.get_cull_mask_value(
				SHADOW_PROXY_LAYER_NUMBER
			)
		),
		"shadow_puffs": (
			_shadow_puffs.multimesh.visible_instance_count
			if _shadow_puffs != null and _shadow_puffs.multimesh != null
			else 0
		),
		"raymarch_steps": 16,
		"noise_texture_size": 0,
		"noise_textures": 0,
		"noise_source": "procedural_value_noise_3d",
		"cloud_altitude": CLOUD_ALTITUDE,
		"camera_distance": _camera_distance,
		"visibility_fade": _visibility,
		"shadows_enabled": _shadows_enabled,
		"visible_draw_passes": 1 if _visibility > 0.001 else 0,
		"shadow_draw_passes": (
			1
			if (
				_shadows_enabled
				and _visibility >= SHADOW_REVEAL_THRESHOLD
			)
			else 0
		),
	}
