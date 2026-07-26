extends RefCounted
## Disposable runtime adapter for the Modly experiment.
##
## It converts each imported BaseMaterial3D to a palette shader while retaining
## the generated albedo as a semantic/detail mask and retaining its normal map.
## No texture or GLB is modified, and no production registry is involved.

const REPAINT_SHADER := preload(
	"res://tests/modly_blender_smoothing/palette_repaint.gdshader"
)

const FOLIAGE_PROFILES := {
	"pine": ["pine_deep", "pine_medium", "pine_light"],
	"leaf": ["leaf_olive", "leaf_medium", "leaf_bright"],
}
const WOOD_PROFILE := ["wood_primary", "wood_light", "wood_highlight"]


static func apply_to_tree(
	root: Node,
	materials: MaterialLibrary,
	foliage_profile := "leaf"
) -> Dictionary:
	var foliage_keys: Array = FOLIAGE_PROFILES.get(
		foliage_profile,
		FOLIAGE_PROFILES["leaf"]
	)
	var report := {
		"mesh_count": 0,
		"surface_count": 0,
		"albedo_textures_retained": 0,
		"normal_maps_retained": 0,
		"profile": foliage_profile,
	}

	var mesh_instances: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		mesh_instances.append(root as MeshInstance3D)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		mesh_instances.append(child as MeshInstance3D)

	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue
		report["mesh_count"] += 1
		for surface_index in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.get_active_material(surface_index)
			if not original is BaseMaterial3D:
				continue
			var imported := original as BaseMaterial3D
			var repaint := ShaderMaterial.new()
			repaint.shader = REPAINT_SHADER
			repaint.resource_name = "%s_suma_palette_repaint" % foliage_profile

			if imported.albedo_texture != null:
				repaint.set_shader_parameter("source_albedo", imported.albedo_texture)
				report["albedo_textures_retained"] += 1
			if imported.normal_texture != null:
				repaint.set_shader_parameter("source_normal", imported.normal_texture)
				repaint.set_shader_parameter("use_normal_map", true)
				report["normal_maps_retained"] += 1

			repaint.set_shader_parameter(
				"foliage_shadow",
				_material_color(materials, String(foliage_keys[0]))
			)
			repaint.set_shader_parameter(
				"foliage_mid",
				_material_color(materials, String(foliage_keys[1]))
			)
			repaint.set_shader_parameter(
				"foliage_light",
				_material_color(materials, String(foliage_keys[2]))
			)
			repaint.set_shader_parameter(
				"wood_shadow",
				_material_color(materials, String(WOOD_PROFILE[0]))
			)
			repaint.set_shader_parameter(
				"wood_mid",
				_material_color(materials, String(WOOD_PROFILE[1]))
			)
			repaint.set_shader_parameter(
				"wood_light",
				_material_color(materials, String(WOOD_PROFILE[2]))
			)
			mesh_instance.set_surface_override_material(surface_index, repaint)
			report["surface_count"] += 1

	return report


static func _material_color(materials: MaterialLibrary, key: String) -> Color:
	var material := materials.material(key)
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	return materials.palette.color(key)
