extends SceneTree
## Fast structural check that does not require a rendered viewport.

const SdfBlendShellScript := preload("res://scripts/player/sdf_blend_shell.gd")


func _init() -> void:
	var shell := SdfBlendShellScript.new()
	shell.call("build", 14)
	var shell_mesh := shell.mesh as ArrayMesh
	assert(shell_mesh != null, "SDF shell must build an ArrayMesh")
	assert(shell_mesh.get_surface_count() == 1, "SDF shell must stay one draw surface")
	assert(shell.call("shape_count") == 14, "SDF shell must retain the requested shape budget")
	print(
		"SDF SHELL CONTRACT PASSED — %d vertices, one surface"
		% shell_mesh.surface_get_array_len(0)
	)
	shell.free()
	quit(0)
