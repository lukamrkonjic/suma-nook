extends SceneTree
## Prints the imported jacket GLB's structure and skin binding details.


func _initialize() -> void:
	var scene := load(
		"res://assets/characters/parts/top_jacket_cozy.glb"
	) as PackedScene
	var instance := scene.instantiate()
	_dump(instance, 0)
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		print("MESH ", mesh_instance.name)
		print("  skeleton_path=", mesh_instance.skeleton)
		print("  has_skin=", mesh_instance.skin != null)
		if mesh_instance.skin != null:
			var skin := mesh_instance.skin
			print("  bind_count=", skin.get_bind_count())
			for bind_index in mini(skin.get_bind_count(), 5):
				print(
					"  bind[", bind_index, "] name='",
					skin.get_bind_name(bind_index),
					"' bone=", skin.get_bind_bone(bind_index)
				)
	instance.free()
	print("JACKET_GLB_PROBE_DONE")
	quit(0)


func _dump(node: Node, depth: int) -> void:
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]")
	for child in node.get_children():
		_dump(child, depth + 1)
