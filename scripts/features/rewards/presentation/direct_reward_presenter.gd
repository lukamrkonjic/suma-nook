class_name DirectRewardPresenter
extends WorldBudRewardPresenter
## A vase already owns the shell-breaking ceremony. This presenter reveals the
## granted world piece directly, avoiding the visually confusing vase-inside-
## another-capsule sequence while retaining the shared bounded reward queue.


func _build_bud(profile: Defs.RewardRevealProfileDefinition) -> Node3D:
	var glint := Node3D.new()
	glint.name = "VaseRewardGlint"
	var material := assets.materials.material(profile.glow_material)
	for index in 6:
		var ray_mesh := PrismMesh.new()
		ray_mesh.size = Vector3(0.035, 0.34, 0.035)
		var ray := MeshInstance3D.new()
		ray.name = "RewardRay"
		ray.mesh = ray_mesh
		ray.material_override = material
		ray.position.y = 0.12
		ray.rotation = Vector3(0.0, TAU * float(index) / 6.0, PI * 0.5)
		glint.add_child(ray)
	return glint
