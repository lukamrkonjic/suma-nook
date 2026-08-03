class_name TileV2Validate
extends RefCounted
## Automated mesh validation for generated V2 tiles: geometry defects are
## caught as data, never argued from renders.


## Returns human-readable issues; empty = clean.
static func validate(mesh: ArrayMesh, label: String) -> PackedStringArray:
	var issues := PackedStringArray()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tag := "%s[s%d]" % [label, surface]
		if normals.size() != vertices.size():
			issues.append("%s: normal count mismatch" % tag)
			continue
		var bad_position := 0
		var bad_normal := 0
		for index in vertices.size():
			if not (is_finite(vertices[index].x) and is_finite(vertices[index].y)
					and is_finite(vertices[index].z)):
				bad_position += 1
			var length := normals[index].length()
			if not is_finite(length) or absf(length - 1.0) > 0.02:
				bad_normal += 1
		if bad_position > 0:
			issues.append("%s: %d non-finite vertices" % [tag, bad_position])
		if bad_normal > 0:
			issues.append("%s: %d non-unit/non-finite normals" % [tag, bad_normal])
		var degenerate := 0
		var inverted := 0
		var triangle_count := indices.size() / 3
		for triangle in triangle_count:
			var a := vertices[indices[triangle * 3]]
			var b := vertices[indices[triangle * 3 + 1]]
			var c := vertices[indices[triangle * 3 + 2]]
			# Repo convention: rendered-face normal of clockwise front faces
			# is (c-a)×(b-a).
			var face := (c - a).cross(b - a)
			var area2 := face.length()
			if area2 < 0.0000000002:
				degenerate += 1
				continue
			face /= area2
			for corner in 3:
				if normals[indices[triangle * 3 + corner]].dot(face) < -0.15:
					inverted += 1
					break
		if degenerate > 0:
			issues.append("%s: %d degenerate triangles" % [tag, degenerate])
		if inverted > 0:
			issues.append("%s: %d triangles disagree with vertex normals"
				% [tag, inverted])
	return issues
