class_name SdfBlendShell
extends MeshInstance3D
## A single animated mesh surface projected onto the smooth union of a fixed
## number of capsule/sphere distance fields. Motion is supplied as endpoints;
## the shader owns surface fusion, normals, and proximity color blending.

const MAX_SHAPES := 16
const SHADER := preload("res://assets/materials/sdf_blend_shell.gdshader")
const OUTLINE_SHADER := preload("res://assets/materials/sdf_blend_outline.gdshader")

var _material: ShaderMaterial
var _outline_material: ShaderMaterial
var _shape_count := 0


func build(shape_count: int) -> void:
	_shape_count = clampi(shape_count, 1, MAX_SHAPES)
	mesh = _build_seed_mesh(_shape_count)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("shape_count", _shape_count)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("shape_count", _shape_count)
	# A classic inverted-hull next pass cannot be used on the duplicated seed
	# capsules: buried backfaces would paint over the visible blended surface.
	# The fill shader supplies its own SDF-normal contour until the outline gets
	# a dedicated outer envelope.
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Seed vertices live in unit-capsule space around the origin. Their static
	# bounds already exceed the tiny runtime mascot, so shader motion cannot be
	# incorrectly culled.
	extra_cull_margin = 0.5


func update_shapes(
	shape_a: PackedVector4Array,
	shape_b: PackedVector4Array,
	shape_colors: PackedVector4Array
) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("shape_a", _padded(shape_a))
	_material.set_shader_parameter("shape_b", _padded(shape_b))
	_material.set_shader_parameter("shape_color", _padded(shape_colors))
	_outline_material.set_shader_parameter("shape_a", _padded(shape_a))
	_outline_material.set_shader_parameter("shape_b", _padded(shape_b))


func set_neighbors(neighbors: Array) -> void:
	if _material == null:
		return
	var neighbors_a := PackedVector4Array()
	var neighbors_b := PackedVector4Array()
	for source_index in MAX_SHAPES:
		var first := Vector4(-1.0, -1.0, -1.0, -1.0)
		var second := Vector4(-1.0, -1.0, -1.0, -1.0)
		var source_neighbors: Array = (
			neighbors[source_index] if source_index < neighbors.size() else []
		)
		for slot in mini(source_neighbors.size(), 8):
			if slot < 4:
				first[slot] = float(source_neighbors[slot])
			else:
				second[slot - 4] = float(source_neighbors[slot])
		neighbors_a.append(first)
		neighbors_b.append(second)
	_material.set_shader_parameter("shape_neighbors_a", neighbors_a)
	_material.set_shader_parameter("shape_neighbors_b", neighbors_b)
	_outline_material.set_shader_parameter("shape_neighbors_a", neighbors_a)
	_outline_material.set_shader_parameter("shape_neighbors_b", neighbors_b)


func set_outline_width(width: float) -> void:
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_width", width)


func shape_count() -> int:
	return _shape_count


func _padded(source: PackedVector4Array) -> PackedVector4Array:
	var result := PackedVector4Array()
	for index in MAX_SHAPES:
		result.append(source[index] if index < source.size() else Vector4.ZERO)
	return result


func _build_seed_mesh(count: int) -> ArrayMesh:
	var seed := CapsuleMesh.new()
	seed.radius = 1.0
	seed.height = 4.0
	seed.radial_segments = 24
	seed.rings = 10
	var source_arrays: Array = seed.get_mesh_arrays()
	var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]
	var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for shape_index in count:
		var vertex_offset := vertices.size()
		vertices.append_array(source_vertices)
		normals.append_array(source_normals)
		for _vertex_index in source_vertices.size():
			uv2.append(Vector2(float(shape_index), 0.0))
		for source_index in source_indices:
			indices.append(vertex_offset + source_index)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
