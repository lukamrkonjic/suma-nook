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
		for value in uv2:
			ids[int(round((value as Vector2).x))] = true
		print("UV2_PRESENT distinct_region_ids=", ids.keys().size(), " ids=", ids.keys())
	instance.free()
	quit(0)
