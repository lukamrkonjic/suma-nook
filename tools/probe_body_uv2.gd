extends SceneTree

func _initialize() -> void:
	var instance := (load("res://assets/3d/reworked/player_male_mannequin.glb") as PackedScene).instantiate()
	var mesh_instance := instance.find_child("PlayerMaleBody", true, false) as MeshInstance3D
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	if uv2 == null:
		print("UV2_MISSING")
	else:
		var ids := {}
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bounds_by_id := {}
		for index in uv2.size():
			var region_id := int(round((uv2[index] as Vector2).x))
			ids[region_id] = true
			if not bounds_by_id.has(region_id):
				bounds_by_id[region_id] = AABB(
					vertices[index], Vector3.ZERO
				)
			else:
				bounds_by_id[region_id] = (
					bounds_by_id[region_id] as AABB
				).expand(vertices[index])
		print("UV2_PRESENT distinct_region_ids=", ids.keys().size(), " ids=", ids.keys())
		print("UV2_NECK_BOUNDS ", bounds_by_id.get(1, AABB()))
	instance.free()
	quit(0)
