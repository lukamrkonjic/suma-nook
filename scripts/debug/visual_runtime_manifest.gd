extends SceneTree
## Instantiates the real game and exports all live visual controls to JSON.
##
## Run:
## godot --headless --path . --script scripts/debug/visual_runtime_manifest.gd \
##   -- --out=C:/path/visual_runtime_manifest.json \
##   --save=user://visual_manifest_throwaway.json

const PROFILE_FIELDS := [
	"profile_id", "background_color", "ambient_color", "ambient_energy",
	"ambient_gradient_enabled", "ambient_sky_color", "ambient_equator_color",
	"ambient_ground_color", "background_gradient", "gradient_top", "gradient_mid",
	"gradient_bottom", "stars_enabled", "sun_color", "sun_energy", "sun_specular",
	"sun_pitch_deg", "sun_yaw_deg", "shadow_opacity", "shadow_blur",
	"sun_angular_distance", "shadow_bias", "shadow_normal_bias", "ssao_enabled",
	"ssao_intensity", "ssao_radius", "ssao_power", "ssao_detail", "ssao_horizon",
	"ssao_sharpness", "glow_enabled", "glow_intensity", "glow_hdr_threshold",
	"glow_bloom", "exposure", "tonemap", "contrast", "saturation", "fog_enabled",
	"brightness",
	"fog_color", "fog_density", "rain_enabled", "motes_enabled",
	"leaves_enabled", "snow_enabled", "blossoms_enabled", "spores_enabled",
	"local_light_multiplier",
]


func _init() -> void:
	call_deferred("_export")


func _export() -> void:
	var output_path := "user://visual_runtime_manifest.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")

	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate() as Main
	root.add_child(main)
	await process_frame
	await process_frame
	if not main._gameplay_started:
		var creator := main.find_child("Creator", true, false)
		if creator != null:
			creator.queue_free()
		var profile := PlayerProfile.new()
		profile.display_name = "Visual Manifest"
		main.core.new_game(profile)
		main.renderer.rebuild_all()
		main.player_visual.apply_profile(profile)
		main.player.position = profile.position
		main.camera_rig.restore_gameplay_zoom()
		main._start_gameplay(true)
	await process_frame
	await process_frame

	var profiles := {}
	for entry in [
		["day", main.lighting.day_profile],
		["mist", main.lighting.mist_profile],
		["rain", main.lighting.rain_profile],
		["leaves", main.lighting.leaves_profile],
		["snow", main.lighting.snow_profile],
		["blossom", main.lighting.blossom_profile],
	]:
		profiles[entry[0]] = _profile_manifest(entry[1])

	var manifest := {
		"schema_version": 1,
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"project": {
			"name": ProjectSettings.get_setting("application/config/name"),
			"engine": Engine.get_version_info(),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		},
		"clean_room_scope": {
			"implementation": "Original Suma Nook cross-engine equivalents using independently observed high-level behavior and safe measurements.",
			"not_copied": [
				"Garden Galaxy source code",
				"textures, meshes, shaders, materials, audio, icons, or animations",
				"proprietary animation curves or keyframes",
			],
			"reference_values_not_observed": [
				"live Garden Galaxy material property blocks",
				"complete live post-processing property blocks",
				"complete live particle curve modules and semantic family mapping",
				"runtime-instantiated Garden Galaxy prefab overrides",
			],
		},
		"safe_reference_measurements": {
			"camera": {
				"projection": "perspective",
				"fov_degrees": 15.0,
				"near_clip": 5.0,
				"far_clip": 100.0,
				"default_distance": 40.0,
				"distance_limits": [40.0, 70.0],
				"zoom_step": 5.0,
				"pitch_degrees": -40.0,
				"orbit_step_degrees": 90.0,
				"orbit_speed_degrees_per_second": 360.0,
				"pan_damping_per_second": 10.0,
			},
			"lighting": {
				"reference_direction": Vector3(-0.2113, -0.9063, -0.3660),
				"reference_color": Color(1.0, 1.0, 0.992),
				"reference_intensity": 1.0,
				"reference_shadow_bias": 0.08,
				"reference_shadow_normal_bias": 0.02,
				"reference_shadow_near_plane": 0.2,
			},
			"ambient_gradient": {
				"sky": Color(0.8, 0.741, 0.769),
				"equator": Color(0.651, 0.420, 0.373),
				"ground": Color(0.859, 0.8, 0.722),
				"intensity": 1.0,
				"day_fog_enabled": false,
			},
			"reflection_probe": {
				"mode": "realtime",
				"resolution": 128,
				"intensity": 1.0,
				"bounces": 1,
				"size": Vector3(50.0, 15.0, 50.0),
				"box_projection": false,
			},
			"animation_timings": {
				"theme_transition_seconds": 1.0,
				"placement_wobble_degrees": 2.5,
				"placement_beats_seconds": [0.02, 0.02],
				"reveal_seconds": 0.5,
				"reveal_queue_spacing_seconds": 0.1,
				"gift_reveal_seconds": 0.15,
			},
			"particle_metadata": {
				"confirmed_system": {
					"duration": 5.0,
					"looping": true,
					"prewarm": true,
					"maximum_particles": 100,
					"lifetime_range": [5.0, 10.0],
					"emission_per_second": 5.0,
					"cone_angle_degrees": 25.0,
					"cone_radius": 1.0,
					"cone_length": 5.0,
					"simulation_space": "local",
					"semantic_family": "not observed",
				},
			},
		},
		"camera": main.camera_rig.runtime_manifest(),
		"lighting_environment_post_and_particles": main.lighting.runtime_manifest(),
		"weather_profiles": profiles,
		"materials": main.materials.material_parameter_manifest(),
		"animations": {
			"player": main.player_visual.animation_manifest(),
			"world": main.renderer.animation_manifest(),
			"parcel_reveal": main.parcel_reveal.animation_manifest(),
		},
		"saved_runtime_state": {
			"view": main.core.view_state,
			"visual": main.core.visual_state,
		},
		"instantiated_scene_values": _scene_manifest(main),
	}

	var absolute_path := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write visual manifest: %s" % FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(_json_value(manifest), "\t"))
	file.close()
	print("VISUAL RUNTIME MANIFEST SAVED: " + absolute_path)
	quit(0)


func _profile_manifest(profile: VisualStyleProfile) -> Dictionary:
	var result := {"resource_path": profile.resource_path}
	for field in PROFILE_FIELDS:
		result[field] = profile.get(field)
	return result


func _scene_manifest(scene_root: Node) -> Dictionary:
	var nodes: Array = []
	var class_counts := {}
	var queue: Array[Node] = [scene_root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		var node_class: String = node.get_class()
		class_counts[node_class] = int(class_counts.get(node_class, 0)) + 1
		var record := {
			"path": String(scene_root.get_path_to(node)),
			"name": node.name,
			"class": node_class,
		}
		if node is Node3D:
			var spatial := node as Node3D
			record["position"] = spatial.position
			record["rotation_degrees"] = spatial.rotation_degrees
			record["scale"] = spatial.scale
			record["visible"] = spatial.visible
		if node is Light3D:
			var light := node as Light3D
			record["light"] = {
				"color": light.light_color,
				"energy": light.light_energy,
				"specular": light.light_specular,
				"shadow_enabled": light.shadow_enabled,
			}
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			var surfaces: Array = []
			if mesh_instance.mesh != null:
				for surface in mesh_instance.mesh.get_surface_count():
					var material := mesh_instance.get_active_material(surface)
					surfaces.append({
						"index": surface,
						"material_name": material.resource_name if material != null else "",
						"material_class": material.get_class() if material != null else "",
					})
			record["mesh"] = {
				"class": mesh_instance.mesh.get_class() if mesh_instance.mesh != null else "",
				"resource_path": mesh_instance.mesh.resource_path if mesh_instance.mesh != null else "",
				"surfaces": surfaces,
			}
		nodes.append(record)
		for child in node.get_children():
			queue.append(child)
	return {"class_counts": class_counts, "nodes": nodes}


func _json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary := {}
			for key in value:
				dictionary[String(key)] = _json_value(value[key])
			return dictionary
		TYPE_ARRAY:
			var array: Array = []
			for item in value:
				array.append(_json_value(item))
			return array
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var packed_array: Array = []
			for item in value:
				packed_array.append(_json_value(item))
			return packed_array
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_AABB:
			return {"position": _json_value(value.position), "size": _json_value(value.size)}
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return {"class": value.get_class(), "resource_path": value.resource_path}
			return {"class": value.get_class()}
		_:
			return value
