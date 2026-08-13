extends SceneTree
## Answers one question per asset: is runtime smoothing actually changing any
## normals, and if not, is position welding the reason?
##
## _blend_normals merges normals across vertices that share a _position_key.
## If the key is finer than the float drift between co-located vertices, every
## corner keeps its own bucket, the blend target equals the authored normal,
## and the model still renders flat no matter how high smoothing is set.

const ASSETS := ["prop_shrooms", "prop_fir", "prop_leafy_bush", "prop_vintage_radio"]


func _init() -> void:
	var palette := load("res://assets/palettes/gg_material_palette.tres") as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))

	for asset_id in ASSETS:
		var profile: Dictionary = assets.edits.profile(asset_id)
		var smoothing := float(profile.get("smoothing", 0.0))
		var authored := load("res://assets/3d/reworked/%s.glb" % asset_id) as PackedScene
		if authored == null:
			print("%s: no source" % asset_id)
			continue
		var root := authored.instantiate()
		var total := 0
		var buckets := {}
		var changed := 0
		var worst := 0.0
		for mesh_instance in _meshes(root):
			var mesh := mesh_instance.mesh as ArrayMesh
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_NORMAL] == null:
					continue
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] != null:
					indices = arrays[Mesh.ARRAY_INDEX]
				total += vertices.size()
				for index in vertices.size():
					buckets["%d:%d:%d" % [
						roundi(vertices[index].x * 100000.0),
						roundi(vertices[index].y * 100000.0),
						roundi(vertices[index].z * 100000.0),
					]] = true
				var blended := assets.edits._blend_normals(
					vertices, normals, indices, smoothing, false
				)
				for index in normals.size():
					var angle := rad_to_deg(normals[index].angle_to(blended[index]))
					if angle > 0.5:
						changed += 1
					worst = maxf(worst, angle)
		root.free()
		print(
			"%-22s smoothing=%.2f verts=%d buckets=%d (%.0f%% merged) moved=%d max_shift=%.1fdeg"
			% [
				asset_id,
				smoothing,
				total,
				buckets.size(),
				100.0 * (1.0 - float(buckets.size()) / maxf(float(total), 1.0)),
				changed,
				worst,
			]
		)
	quit()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
