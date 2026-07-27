class_name PlacementPreview
extends RefCounted
## Presents the actual held visual above its resolved landing point.
## Invalid placement is communicated on the held model itself so stacked pieces
## cannot occlude the feedback. Unlike the original flat-red replacement, a
## restrained overlay preserves authored materials, shading, and detail.

var indicator: MeshInstance3D
var lift_height: float
var invalid_overlay: StandardMaterial3D
var _invalid_overlay_meshes: Dictionary = {}
var _invalid_shader_materials: Dictionary = {}

const WATER_INVALID_STRENGTH := 0.68


func _init(parent: Node3D, tile_size: float) -> void:
	lift_height = maxf(0.14, tile_size * 0.12)
	invalid_overlay = StandardMaterial3D.new()
	invalid_overlay.albedo_color = Color(1.0, 0.08, 0.045, 0.24)
	invalid_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invalid_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	invalid_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	invalid_overlay.render_priority = 1

	# Retain the node as a compatibility boundary for tests and tooling. Invalid
	# feedback now belongs to the held model and cannot be hidden by upper tiles.
	indicator = MeshInstance3D.new()
	indicator.name = "PlacementLandingIndicator"
	indicator.visible = false
	parent.add_child(indicator)


func prepare_held_visual(ghost: Node3D) -> void:
	if ghost == null:
		return
	_invalid_overlay_meshes.clear()
	_invalid_shader_materials.clear()
	var meshes: Array[MeshInstance3D] = []
	if ghost is MeshInstance3D:
		meshes.append(ghost as MeshInstance3D)
	for child in ghost.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		# Water vertices are displaced by their shader. A generic duplicate
		# would remain flat while the real surface waves through it, leaving
		# irregular blue patches in an invalid preview. Give this held instance
		# a local shader material and tint the animated geometry directly.
		if mesh_instance.has_meta("placement_water_surface"):
			var water_material := (
				mesh_instance.material_override as ShaderMaterial
			)
			if water_material != null:
				var held_water_material := (
					water_material.duplicate() as ShaderMaterial
				)
				held_water_material.resource_local_to_scene = true
				held_water_material.set_shader_parameter(
					"placement_invalid_strength",
					0.0
				)
				mesh_instance.material_override = held_water_material
				_invalid_shader_materials[mesh_instance] = held_water_material
			mesh_instance.transparency = 0.0
			continue
		var overlay_mesh := MeshInstance3D.new()
		overlay_mesh.name = "InvalidPlacementOverlay"
		overlay_mesh.mesh = mesh_instance.mesh
		overlay_mesh.material_override = invalid_overlay
		overlay_mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		overlay_mesh.layers = mesh_instance.layers
		overlay_mesh.visible = false
		overlay_mesh.set_meta("placement_invalid_overlay", true)
		mesh_instance.add_child(overlay_mesh)
		_invalid_overlay_meshes[mesh_instance] = overlay_mesh
		# MeshInstance3D.transparency is a global fade layered over the asset's
		# authored materials. Keep it neutral and leave every material override
		# supplied by the tile/structure factories untouched.
		mesh_instance.transparency = 0.0
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func set_validity(ghost: Node3D, valid: bool) -> void:
	if ghost == null:
		return
	ghost.set_meta("placement_valid", valid)
	for mesh_variant in _invalid_overlay_meshes:
		var mesh_instance := mesh_variant as MeshInstance3D
		var overlay_mesh := (
			_invalid_overlay_meshes[mesh_variant] as MeshInstance3D
		)
		if (
			mesh_instance == null
			or overlay_mesh == null
			or not is_instance_valid(mesh_instance)
			or not is_instance_valid(overlay_mesh)
		):
			continue
		mesh_instance.transparency = 0.0 if valid else 0.08
		overlay_mesh.visible = not valid
	for mesh_variant in _invalid_shader_materials:
		var mesh_instance := mesh_variant as MeshInstance3D
		var shader_material := (
			_invalid_shader_materials[mesh_variant] as ShaderMaterial
		)
		if (
			mesh_instance == null
			or shader_material == null
			or not is_instance_valid(mesh_instance)
		):
			continue
		shader_material.set_shader_parameter(
			"placement_invalid_strength",
			0.0 if valid else WATER_INVALID_STRENGTH
		)


func lifted_position(landing_position: Vector3) -> Vector3:
	return landing_position + Vector3.UP * lift_height


func sync_indicator(_world: Vector3, _show: bool, _valid: bool) -> void:
	indicator.visible = false


func hide_indicator() -> void:
	indicator.visible = false
