class_name CreatureSemanticShells
extends Node3D
## Renders a creature as bounded, closed procedural mesh parts.
##
## Each compact sphere/tapered-capsule source becomes one native mesh built on
## first pose. Animation then updates transforms only. This removes iterative
## SDF projection, buried seed charts, false interiors, cross-part color bleed,
## and per-frame mesh uploads while retaining the existing procedural pose math.

const SURFACE_SHADER := preload(
	"res://assets/materials/creature_semantic_surface.gdshader"
)
const RADIAL_SEGMENTS := 14
const CAP_RINGS := 4
const PATTERN_MODES := {
	"none": 0, "stripes": 1, "speckle": 2, "patches": 3, "bands": 4,
}

var _layout: Array[Dictionary] = []
var _shape_nodes: Array[MeshInstance3D] = []
var _base_lengths: Array[float] = []
var _base_radii: Array[float] = []
var _source_shape_count := 0
var _shared_material: ShaderMaterial


func build(layout: Array[Dictionary], coat: Dictionary, _outline_width: float) -> void:
	if not _shape_nodes.is_empty():
		return
	_layout = layout.duplicate(true)
	_shared_material = _surface_material(coat)
	var assigned_indices := {}
	for entry in _layout:
		var source_indices: Array = entry.get("indices", []) as Array
		assert(
			not source_indices.is_empty(),
			"Semantic creature parts need at least one source shape"
		)
		for source_index_value in source_indices:
			var source_index := int(source_index_value)
			assert(
				not assigned_indices.has(source_index),
				"Source shape %d was assigned to multiple semantic parts"
				% source_index
			)
			assigned_indices[source_index] = true
			_source_shape_count = maxi(
				_source_shape_count, source_index + 1
			)
	assert(
		assigned_indices.size() == _source_shape_count,
		"Semantic creature layout must assign each source shape exactly once"
	)
	_shape_nodes.resize(_source_shape_count)
	_base_lengths.resize(_source_shape_count)
	_base_radii.resize(_source_shape_count)

	for entry in _layout:
		var pivot := Node3D.new()
		pivot.name = String(entry.get("name", "Part"))
		add_child(pivot)
		var source_indices: Array = entry.get("indices", []) as Array
		for shape_slot in source_indices.size():
			var source_index := int(source_indices[shape_slot])
			var surface := MeshInstance3D.new()
			surface.name = "Surface" if shape_slot == 0 else "Surface%02d" % shape_slot
			surface.material_override = _shared_material
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			surface.extra_cull_margin = 0.08
			pivot.add_child(surface)
			_shape_nodes[source_index] = surface


func update_shapes(
	shape_a: PackedVector4Array,
	shape_b: PackedVector4Array,
	colors: PackedVector4Array,
	radii_b: PackedFloat32Array
) -> void:
	assert(
		shape_a.size() == _source_shape_count,
		"Semantic layout assigned %d shapes but pose supplied %d"
		% [_source_shape_count, shape_a.size()]
	)
	for source_index in _source_shape_count:
		var endpoint_a := Vector3(
			shape_a[source_index].x,
			shape_a[source_index].y,
			shape_a[source_index].z
		)
		var endpoint_b := Vector3(
			shape_b[source_index].x,
			shape_b[source_index].y,
			shape_b[source_index].z
		)
		var radius_a := maxf(shape_a[source_index].w, 0.0005)
		var radius_b := maxf(radii_b[source_index], 0.0005)
		var axis := endpoint_b - endpoint_a
		var axis_length := axis.length()
		var surface := _shape_nodes[source_index]
		if surface.mesh == null:
			surface.mesh = _build_local_mesh(
				axis_length,
				radius_a,
				radius_b,
				colors[source_index]
			)
			_base_lengths[source_index] = maxf(axis_length, 0.0001)
			_base_radii[source_index] = radius_a
		_update_shape_transform(
			surface,
			endpoint_a,
			endpoint_b,
			radius_a,
			_base_lengths[source_index],
			_base_radii[source_index]
		)


func part_names() -> PackedStringArray:
	var result := PackedStringArray()
	for entry in _layout:
		result.append(String(entry.get("name", "")))
	return result


func source_shape_count() -> int:
	return _source_shape_count


func max_shapes_per_part() -> int:
	var result := 0
	for entry in _layout:
		var source_indices: Array = entry.get("indices", []) as Array
		result = maxi(result, source_indices.size())
	return result


func _update_shape_transform(
	surface: MeshInstance3D,
	endpoint_a: Vector3,
	endpoint_b: Vector3,
	radius_a: float,
	base_length: float,
	base_radius: float
) -> void:
	var axis := endpoint_b - endpoint_a
	var axis_length := axis.length()
	var radial_scale := radius_a / maxf(base_radius, 0.0001)
	if axis_length <= 0.0001:
		surface.transform = Transform3D(Basis.IDENTITY, endpoint_a)
		surface.scale = Vector3.ONE * radial_scale
		return
	var axis_y := axis / axis_length
	var helper := Vector3.RIGHT if absf(axis_y.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var axis_x := helper.cross(axis_y).normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	surface.transform = Transform3D(
		Basis(axis_x, axis_y, axis_z).orthonormalized(),
		(endpoint_a + endpoint_b) * 0.5
	)
	surface.scale = Vector3(
		radial_scale,
		axis_length / maxf(base_length, 0.0001),
		radial_scale
	)


func _build_local_mesh(
	axis_length: float,
	radius_a: float,
	radius_b: float,
	color_value: Vector4
) -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var vertex_colors: Array[Color] = []
	var indices: Array[int] = []
	var endpoint_a := Vector3.DOWN * axis_length * 0.5
	var endpoint_b := Vector3.UP * axis_length * 0.5
	var color := Color(color_value.x, color_value.y, color_value.z, 1.0)

	for cap_ring in range(CAP_RINGS + 1):
		var angle := lerpf(-PI * 0.5, 0.0, float(cap_ring) / float(CAP_RINGS))
		_append_ring(
			vertices, normals, vertex_colors,
			endpoint_a + Vector3.UP * sin(angle) * radius_a,
			cos(angle) * radius_a, angle, color
		)
	_append_ring(
		vertices, normals, vertex_colors,
		endpoint_b, radius_b, 0.0, color
	)
	for cap_ring in range(1, CAP_RINGS + 1):
		var angle := lerpf(0.0, PI * 0.5, float(cap_ring) / float(CAP_RINGS))
		_append_ring(
			vertices, normals, vertex_colors,
			endpoint_b + Vector3.UP * sin(angle) * radius_b,
			cos(angle) * radius_b, angle, color
		)

	var ring_count := CAP_RINGS * 2 + 2
	for ring_index in range(ring_count - 1):
		var row := ring_index * (RADIAL_SEGMENTS + 1)
		var next_row := row + RADIAL_SEGMENTS + 1
		for segment in RADIAL_SEGMENTS:
			var a := row + segment
			var b := a + 1
			var c := next_row + segment
			var d := c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(vertex_colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_ring(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	vertex_colors: Array[Color],
	center: Vector3,
	radius: float,
	cap_angle: float,
	color: Color
) -> void:
	var axial_normal := sin(cap_angle)
	var radial_normal := cos(cap_angle)
	for segment in range(RADIAL_SEGMENTS + 1):
		var azimuth := TAU * float(segment) / float(RADIAL_SEGMENTS)
		var radial := Vector3(cos(azimuth), 0.0, sin(azimuth))
		vertices.append(center + radial * radius)
		normals.append((radial * radial_normal + Vector3.UP * axial_normal).normalized())
		vertex_colors.append(color)


func _surface_material(coat: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter(
		"pattern_mode",
		int(PATTERN_MODES.get(String(coat.get("pattern", "none")), 0))
	)
	material.set_shader_parameter("pattern_scale", float(coat.get("pattern_scale", 24.0)))
	material.set_shader_parameter(
		"pattern_color", Color(String(coat.get("pattern_color", "#FFFFFF")))
	)
	material.set_shader_parameter("pattern_strength", float(coat.get("strength", 0.0)))
	material.set_shader_parameter("ruffle_amount", float(coat.get("ruffle", 0.0)))
	material.set_shader_parameter("ruffle_speed", float(coat.get("ruffle_speed", 2.2)))
	material.set_shader_parameter("strand_strength", float(coat.get("strands", 0.0)))
	material.set_shader_parameter("coat_gloss", float(coat.get("gloss", 0.0)))
	return material
