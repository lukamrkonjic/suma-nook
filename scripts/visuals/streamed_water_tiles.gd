class_name StreamedWaterTiles
extends Node3D
## Constant-window renderer for WorldWaterField.
##
## Every rendered square comes from an addressable water-tile coordinate. The
## complete ocean is never instantiated: the window snaps around the camera,
## intersects the discovery envelope, and rebuilds only after a chunk crossing
## or an explicit WorldGrid mutation.

const WATER_LEVEL := -0.14
const BED_LEVEL := -0.43

var core: GameCore
var field
var envelope: WorldEnvelope
var anchor: Node3D

var _surface: MeshInstance3D
var _generated_beds: MeshInstance3D
var _water_material: ShaderMaterial
var _bed_material: Material
var _stream_radius := 36
var _snap_cells := 8
var _subdivisions_per_cell := 2
var _bed_inset := 0.006
var _dirty := true
var _window := Rect2i()
var _water_cell_count := 0
var _generated_bed_count := 0


func setup(
	game_core: GameCore,
	water_material: Material,
	bed_material: Material,
	follow_anchor: Node3D = null
) -> void:
	core = game_core
	field = core.water_field
	envelope = core.world_envelope
	anchor = follow_anchor
	_water_material = water_material as ShaderMaterial
	_bed_material = bed_material
	_stream_radius = maxi(
		8,
		core.registries.tunei("ocean_stream_radius_cells", 36)
	)
	_snap_cells = maxi(
		1,
		core.registries.tunei("ocean_snap_cells", 8)
	)
	_subdivisions_per_cell = clampi(
		core.registries.tunei(
			"ocean_surface_subdivisions_per_cell",
			2
		),
		1,
		4
	)
	_bed_inset = clampf(
		core.registries.tunef("ocean_bed_tile_inset", 0.006),
		0.0,
		core.grid.tile_size * 0.16
	)
	_surface = MeshInstance3D.new()
	_surface.name = "WaterTileSurface"
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_generated_beds = MeshInstance3D.new()
	_generated_beds.name = "GeneratedWaterTileBeds"
	_generated_beds.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(_generated_beds)
	core.grid.grid_changed.connect(_mark_dirty)
	field.field_changed.connect(func(_coord: Vector2i): _mark_dirty())
	envelope.bounds_changed.connect(func(_bounds: Rect2i): _mark_dirty())
	_sync_shader_envelope()
	_rebuild_if_needed(true)
	set_process(true)


func set_anchor(follow_anchor: Node3D) -> void:
	anchor = follow_anchor
	_rebuild_if_needed(true)


func _process(_delta: float) -> void:
	visible = not core.grid.cells.is_empty()
	_sync_shader_envelope()
	_rebuild_if_needed()


func _mark_dirty() -> void:
	_dirty = true


func _rebuild_if_needed(force := false) -> void:
	var wanted := _wanted_window()
	if not force and not _dirty and wanted == _window:
		return
	_dirty = false
	_window = wanted
	var water_cells: Array[Vector2i] = field.water_cells_in(
		_window,
		true
	)
	_water_cell_count = water_cells.size()
	var generated_cells: Array[Vector2i] = []
	for coord: Vector2i in water_cells:
		if field.is_generated_water(coord):
			generated_cells.append(coord)
	_generated_bed_count = generated_cells.size()
	_surface.mesh = _build_surface_mesh(water_cells)
	_surface.material_override = _water_material
	_generated_beds.mesh = _build_bed_mesh(generated_cells)
	_generated_beds.material_override = _bed_material
	visible = not core.grid.cells.is_empty()


func _wanted_window() -> Rect2i:
	var center := core.grid.home_cell
	if is_instance_valid(anchor):
		center = core.grid.world_to_cell(anchor.global_position)
	center = Vector2i(
		floori(float(center.x) / float(_snap_cells)) * _snap_cells,
		floori(float(center.y) / float(_snap_cells)) * _snap_cells
	)
	var radius := Vector2i.ONE * _stream_radius
	return Rect2i(
		center - radius,
		Vector2i.ONE * (_stream_radius * 2 + 1)
	).intersection(envelope.bounds().grow(envelope.fade_cells()))


func _build_surface_mesh(cells: Array[Vector2i]) -> ArrayMesh:
	if cells.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var tile_size := core.grid.tile_size
	var subdivisions := _subdivisions_per_cell
	var step := tile_size / float(subdivisions)
	for coord: Vector2i in cells:
		var center := core.grid.cell_to_world(coord)
		var base := vertices.size()
		for iy in subdivisions + 1:
			for ix in subdivisions + 1:
				var point := Vector3(
					center.x - tile_size * 0.5 + ix * step,
					WATER_LEVEL,
					center.z - tile_size * 0.5 + iy * step
				)
				vertices.append(point)
				normals.append(Vector3.UP)
				uvs.append(Vector2(point.x, point.z))
				# Zero means this streaming topology has no baked shoreline
				# foam; player interaction foam remains world-space.
				uv2s.append(Vector2.ZERO)
		for iy in subdivisions:
			for ix in subdivisions:
				var a := base + iy * (subdivisions + 1) + ix
				var b := a + 1
				var c := a + subdivisions + 1
				var d := c + 1
				indices.append_array([a, c, b, b, c, d])
	return _mesh_from_arrays(vertices, normals, uvs, uv2s, indices)


func _build_bed_mesh(cells: Array[Vector2i]) -> ArrayMesh:
	if cells.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := (core.grid.tile_size - _bed_inset) * 0.5
	for coord: Vector2i in cells:
		var center := core.grid.cell_to_world(coord)
		var base := vertices.size()
		vertices.append_array([
			Vector3(center.x - half, BED_LEVEL, center.z - half),
			Vector3(center.x + half, BED_LEVEL, center.z - half),
			Vector3(center.x - half, BED_LEVEL, center.z + half),
			Vector3(center.x + half, BED_LEVEL, center.z + half),
		])
		normals.append_array([
			Vector3.UP,
			Vector3.UP,
			Vector3.UP,
			Vector3.UP,
		])
		uvs.append_array([
			Vector2.ZERO,
			Vector2.RIGHT,
			Vector2.DOWN,
			Vector2.ONE,
		])
		indices.append_array([
			base,
			base + 1,
			base + 2,
			base + 1,
			base + 3,
			base + 2,
		])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _mesh_from_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _sync_shader_envelope() -> void:
	if _water_material == null:
		return
	var world_rect := envelope.world_bounds()
	_water_material.set_shader_parameter("distance_haze_enabled", 1.0)
	_water_material.set_shader_parameter(
		"distance_haze_bounds",
		Vector4(
			world_rect.position.x,
			world_rect.position.y,
			world_rect.end.x,
			world_rect.end.y
		)
	)
	_water_material.set_shader_parameter(
		"distance_haze_width",
		envelope.fade_cells() * core.grid.tile_size
	)


func runtime_manifest() -> Dictionary:
	return {
		"enabled": visible,
		"renderer": "streamed_real_water_tiles",
		"logical_field": field.runtime_manifest(),
		"window": _window,
		"stream_radius_cells": _stream_radius,
		"snap_cells": _snap_cells,
		"surface_subdivisions_per_cell": _subdivisions_per_cell,
		"water_cells_rendered": _water_cell_count,
		"generated_beds_rendered": _generated_bed_count,
		"surface_draw_calls": 1 if _surface.mesh != null else 0,
		"bed_draw_calls": 1 if _generated_beds.mesh != null else 0,
	}
