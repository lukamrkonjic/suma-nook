extends SceneTree
## Checks whether the jacket mesh surfaces actually carry bone/weight arrays.


func _initialize() -> void:
	for path in [
		"res://assets/characters/parts/top_jacket_cozy.glb",
		"res://assets/3d/reworked/player_male_mannequin.glb",
	]:
		var instance := (load(path) as PackedScene).instantiate()
		for child in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			var mesh := mesh_instance.mesh
			print("MESH ", path.get_file(), " / ", mesh_instance.name,
				" surfaces=", mesh.get_surface_count())
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var bones: Variant = arrays[Mesh.ARRAY_BONES]
				var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
				print(
					"  surface ", surface,
					" bones=", "null" if bones == null else str(bones.size()),
					" weights=", "null" if weights == null else str(weights.size()),
					" vertices=", arrays[Mesh.ARRAY_VERTEX].size()
				)
		instance.free()
	_dump_sample_weights()
	print("ARRAY_PROBE_DONE")
	quit(0)


## What are the sleeve tips and hem actually weighted to?
func _dump_sample_weights() -> void:
	var instance := (
		load("res://assets/characters/parts/top_jacket_cozy.glb") as PackedScene
	).instantiate()
	var mesh_instance := instance.find_child(
		"*", true, false
	) as MeshInstance3D
	if mesh_instance == null:
		for child in instance.find_children(
			"*", "MeshInstance3D", true, false
		):
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		push_error("Jacket bundle contains no MeshInstance3D")
		instance.free()
		return
	var skin := mesh_instance.skin
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var samples := {
		"left_cuff": _extreme(vertices, Vector3(1, 0, 0)),
		"right_cuff": _extreme(vertices, Vector3(-1, 0, 0)),
		"hem_bottom": _extreme(vertices, Vector3(0, -1, 0)),
		"collar_top": _extreme(vertices, Vector3(0, 1, 0)),
	}
	for label in samples:
		var index: int = samples[label]
		var report := "WEIGHTS %s v=%s :" % [
			label, vertices[index]
		]
		for influence in 4:
			var bind := bones[index * 4 + influence]
			var weight := weights[index * 4 + influence]
			if weight > 0.001:
				report += " %s=%.3f" % [skin.get_bind_name(bind), weight]
		print(report)
	instance.free()


func _extreme(vertices: PackedVector3Array, direction: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for index in vertices.size():
		var dot := vertices[index].dot(direction)
		if dot > best_dot:
			best_dot = dot
			best = index
	return best
