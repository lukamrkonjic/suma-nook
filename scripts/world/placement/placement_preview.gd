class_name PlacementPreview
extends RefCounted
## Owns placement preview styling and the grid-aligned footprint indicator.
## It deliberately does not decide whether a placement is legal.

var indicator: MeshInstance3D
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D


func _init(parent: Node3D, tile_size: float) -> void:
	valid_material = _material(Color(0.65, 0.85, 0.55, 0.55))
	invalid_material = _material(Color(0.85, 0.5, 0.42, 0.5))
	indicator = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(tile_size * 0.96, tile_size * 0.96)
	indicator.mesh = plane
	indicator.visible = false
	parent.add_child(indicator)


func apply_ghost_material(ghost: Node3D, valid: bool) -> void:
	if ghost == null:
		return
	var material := valid_material if valid else invalid_material
	for child in ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)


func sync_indicator(world: Vector3, show: bool, valid: bool) -> void:
	indicator.visible = show
	indicator.position = world + Vector3(0, 0.03, 0)
	indicator.rotation.y = 0.0
	indicator.material_override = valid_material if valid else invalid_material


func hide_indicator() -> void:
	indicator.visible = false


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
