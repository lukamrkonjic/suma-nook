extends Node
## Runtime render-path audit — reports what the RUNNING game actually uses,
## not what project.godot claims. Written to docs/visual_rework/SMOOTHNESS_AUDIT.md
## by tools/run_smoothness_audit.sh.

func _ready() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var win := get_window()
	var lines: Array[String] = []
	lines.append("renderer=%s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	lines.append("window_size=%s" % str(DisplayServer.window_get_size()))
	lines.append("window_size_real_px=%s" % str(DisplayServer.window_get_size_with_decorations()))
	lines.append("screen_scale=%s" % str(DisplayServer.screen_get_scale()))
	lines.append("viewport_size=%s" % str(vp.get_visible_rect().size))
	lines.append("viewport_render_target_size=%s" % str(vp.size))
	lines.append("window_content_scale_mode=%d" % win.content_scale_mode)
	lines.append("window_content_scale_size=%s" % str(win.content_scale_size))
	lines.append("window_content_scale_factor=%s" % str(win.content_scale_factor))
	lines.append("scaling_3d_mode=%d (0=bilinear,1=fsr,2=fsr2)" % vp.scaling_3d_mode)
	lines.append("scaling_3d_scale=%s" % str(vp.scaling_3d_scale))
	lines.append("msaa_3d=%d (0=off,1=2x,2=4x,3=8x)" % vp.msaa_3d)
	lines.append("msaa_2d=%d" % vp.msaa_2d)
	lines.append("screen_space_aa=%d (0=off,1=fxaa)" % vp.screen_space_aa)
	lines.append("use_taa=%s" % str(vp.use_taa))
	lines.append("use_debanding=%s" % str(vp.use_debanding))
	lines.append("anisotropic_filtering_level=%s" % str(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level")))
	lines.append("texture_default_filter=%s" % str(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")))
	lines.append("directional_shadow_size=%s" % str(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")))
	lines.append("soft_shadow_filter_quality=%s" % str(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")))
	lines.append("positional_shadow_atlas_size=%s" % str(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size")))
	lines.append("mesh_lod_threshold=%s" % str(vp.mesh_lod_threshold))
	lines.append("lod_change_threshold_setting=%s" % str(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels")))

	# Walk the live scene for the sun + mesh shading facts.
	var sun := _find_first(get_tree().root, "DirectionalLight3D") as DirectionalLight3D
	if sun:
		lines.append("sun.shadow_enabled=%s" % str(sun.shadow_enabled))
		lines.append("sun.directional_shadow_mode=%d (0=ortho,1=2split,2=4split)" % sun.directional_shadow_mode)
		lines.append("sun.directional_shadow_max_distance=%s" % str(sun.directional_shadow_max_distance))
		lines.append("sun.directional_shadow_blend_splits=%s" % str(sun.directional_shadow_blend_splits))
		lines.append("sun.light_angular_distance=%s" % str(sun.light_angular_distance))
		lines.append("sun.shadow_bias=%s / normal_bias=%s" % [str(sun.shadow_bias), str(sun.shadow_normal_bias)])
		lines.append("sun.shadow_blur=%s / opacity=%s" % [str(sun.shadow_blur), str(sun.shadow_opacity)])
	var cam := vp.get_camera_3d()
	if cam:
		lines.append("camera.projection=%d size=%s near=%s far=%s" % [cam.projection, str(cam.size), str(cam.near), str(cam.far)])

	var meshes := get_tree().root.find_children("*", "MeshInstance3D", true, false)
	var lod_used := 0
	var flat_surfaces := 0
	var total_surfaces := 0
	var no_normals := 0
	var no_tangents := 0
	for m: MeshInstance3D in meshes:
		if m.mesh == null:
			continue
		if m.lod_bias != 1.0:
			lod_used += 1
		for si in m.mesh.get_surface_count():
			total_surfaces += 1
			var fmt: int = m.mesh.surface_get_format(si)
			if not (fmt & Mesh.ARRAY_FORMAT_NORMAL):
				no_normals += 1
			if not (fmt & Mesh.ARRAY_FORMAT_TANGENT):
				no_tangents += 1
			var mat := m.get_surface_override_material(si)
			if mat == null:
				mat = m.mesh.surface_get_material(si)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				flat_surfaces += 1
	lines.append("mesh_instances=%d surfaces=%d" % [meshes.size(), total_surfaces])
	lines.append("surfaces_without_normals=%d" % no_normals)
	lines.append("surfaces_without_tangents=%d" % no_tangents)
	lines.append("unshaded_surfaces=%d" % flat_surfaces)
	lines.append("meshinstances_with_custom_lod_bias=%d" % lod_used)

	for line in lines:
		print("AUDIT| " + line)
	get_tree().quit()


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found:
			return found
	return null
