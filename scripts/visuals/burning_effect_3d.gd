class_name BurningEffect3D
extends Node3D
## Complete reusable presentation for a burning prop.
##
## The flame animation and the heated-fuel overlay share one visibility/state
## root. Fuel can be selected by authored node names, or by a compact radial
## region when an imported prop combines logs and stones in one mesh.

const AnimatedFireScript := preload("res://scripts/visuals/animated_fire_3d.gd")
const FUEL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform vec4 burn_color : source_color = vec4(0.86, 0.22, 0.08, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.52;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.32;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.06;
uniform bool use_region = false;
uniform float region_radius = 0.3;
uniform float region_min_y = -10.0;
uniform float region_max_y = 10.0;
uniform float region_softness = 0.035;

varying vec3 mesh_position;

void vertex() {
	mesh_position = VERTEX;
	// Keep the transparent warmth layer just above the authored surface.
	VERTEX += NORMAL * 0.0012;
}

void fragment() {
	float mask = 1.0;
	if (use_region) {
		float radial = 1.0 - smoothstep(
			max(0.0, region_radius - region_softness),
			region_radius,
			length(mesh_position.xz)
		);
		float lower = smoothstep(
			region_min_y,
			region_min_y + region_softness,
			mesh_position.y
		);
		float upper = 1.0 - smoothstep(
			region_max_y - region_softness,
			region_max_y,
			mesh_position.y
		);
		mask = radial * lower * upper;
	}
	float pulse = 1.0 + (
		sin(TIME * 2.1 + mesh_position.x * 17.0 + mesh_position.z * 13.0)
		* pulse_amount
	);
	ALBEDO = burn_color.rgb;
	EMISSION = burn_color.rgb * emission_strength * pulse;
	ROUGHNESS = 0.88;
	ALPHA = tint_strength * mask;
}
"""

var _flame: AnimatedFire3D
var _fuel_overlays: Array[MeshInstance3D] = []


func configure(
	material_library: MaterialLibrary,
	profile: Dictionary,
	authored_visual: Node3D
) -> void:
	_flame = AnimatedFireScript.new()
	_flame.name = "AnimatedFire"
	_flame.configure(material_library, profile)
	var offset_data: Array = profile.get("offset", [])
	if offset_data.size() >= 3:
		_flame.position = Vector3(
			float(offset_data[0]),
			float(offset_data[1]),
			float(offset_data[2])
		)
	add_child(_flame)
	var fuel_profile: Dictionary = profile.get("fuel", {})
	if fuel_profile.is_empty():
		fuel_profile = _default_fuel_profile(profile, _flame.position.y)
	_add_fuel_overlays(authored_visual, fuel_profile)


func bind_light(light: OmniLight3D) -> void:
	if _flame != null:
		_flame.bind_light(light)


func set_burning(active: bool) -> void:
	visible = active
	if _flame != null:
		_flame.set_burning(active)


func _default_fuel_profile(
	fire_profile: Dictionary,
	fire_base_y: float
) -> Dictionary:
	var width := float(fire_profile.get("width", 0.56))
	var height := float(fire_profile.get("height", 0.58))
	return {
		"region_radius": width * 0.46,
		"region_min_y": maxf(0.0, fire_base_y - height * 0.36),
		"region_max_y": fire_base_y + height * 0.22,
		"region_softness": maxf(0.018, width * 0.055),
		"color": "#a53a29",
		"tint": 0.3,
		"emission": 0.07,
		"pulse": 0.03,
	}


func _add_fuel_overlays(
	authored_visual: Node3D,
	fuel_profile: Dictionary
) -> void:
	if authored_visual == null or fuel_profile.is_empty():
		return
	var targets: Array[MeshInstance3D] = []
	var node_names: Array = fuel_profile.get("nodes", [])
	if node_names.is_empty():
		targets = _mesh_instances(authored_visual)
	else:
		for node_name in node_names:
			var candidate := authored_visual.find_child(
				String(node_name),
				true,
				false
			)
			if candidate is MeshInstance3D:
				targets.append(candidate as MeshInstance3D)
	if targets.is_empty():
		push_warning(
			"BurningEffect3D found no fuel geometry below %s."
			% authored_visual.name
		)
		return

	var material := _fuel_material(fuel_profile)
	for target in targets:
		if target.mesh == null:
			continue
		var overlay := MeshInstance3D.new()
		overlay.name = "BurningFuel_%s" % target.name
		overlay.mesh = target.mesh
		overlay.transform = _transform_below_root(target, authored_visual)
		overlay.material_override = material
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		overlay.extra_cull_margin = 0.01
		add_child(overlay)
		_fuel_overlays.append(overlay)


func _fuel_material(profile: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FUEL_SHADER
	material.shader = shader
	material.set_shader_parameter(
		"burn_color",
		Color(String(profile.get("color", "#d94f2f")))
	)
	material.set_shader_parameter(
		"tint_strength",
		float(profile.get("tint", 0.52))
	)
	material.set_shader_parameter(
		"emission_strength",
		float(profile.get("emission", 0.32))
	)
	material.set_shader_parameter(
		"pulse_amount",
		float(profile.get("pulse", 0.06))
	)
	var radius := float(profile.get("region_radius", -1.0))
	material.set_shader_parameter("use_region", radius > 0.0)
	material.set_shader_parameter("region_radius", maxf(0.01, radius))
	material.set_shader_parameter(
		"region_min_y",
		float(profile.get("region_min_y", -10.0))
	)
	material.set_shader_parameter(
		"region_max_y",
		float(profile.get("region_max_y", 10.0))
	)
	material.set_shader_parameter(
		"region_softness",
		maxf(0.001, float(profile.get("region_softness", 0.035)))
	)
	return material


static func _mesh_instances(root: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result


static func _transform_below_root(
	node: Node3D,
	root: Node3D
) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
