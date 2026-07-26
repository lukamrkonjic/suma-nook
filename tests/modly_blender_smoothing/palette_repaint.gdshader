shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back, depth_draw_opaque;

// The Modly atlas is retained only as a semantic mask and source of low-frequency
// surface shading. Its preview hues are replaced by Suma Nook palette ramps.
uniform sampler2D source_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_map = false;

uniform vec4 foliage_shadow : source_color;
uniform vec4 foliage_mid : source_color;
uniform vec4 foliage_light : source_color;
uniform vec4 wood_shadow : source_color;
uniform vec4 wood_mid : source_color;
uniform vec4 wood_light : source_color;

uniform float foliage_threshold = 0.0;
uniform float foliage_softness = 0.025;
uniform float texture_detail = 0.18;
uniform float normal_strength = 0.72;
uniform float surface_roughness = 0.88;
uniform float surface_specular = 0.18;


vec3 three_color_ramp(float value, vec3 shadow_color, vec3 middle_color, vec3 light_color) {
	float lower = smoothstep(0.02, 0.52, value);
	float upper = smoothstep(0.48, 0.98, value);
	return mix(mix(shadow_color, middle_color, lower), light_color, upper);
}


void fragment() {
	vec3 source = texture(source_albedo, UV).rgb;
	float source_value = max(source.r, max(source.g, source.b));

	// Both test atlases encode foliage with a positive green dominance and wood
	// with a red/brown dominance. A soft boundary avoids colored seam halos.
	float red_green_energy = max(source.r + source.g, 0.025);
	float green_dominance = (source.g - source.r) / red_green_energy;
	float foliage_mask = smoothstep(
		foliage_threshold - foliage_softness,
		foliage_threshold + foliage_softness,
		green_dominance
	);

	float foliage_value = smoothstep(0.035, 0.62, source.g);
	float wood_value = smoothstep(0.025, 0.58, source_value);
	vec3 foliage = three_color_ramp(
		foliage_value,
		foliage_shadow.rgb,
		foliage_mid.rgb,
		foliage_light.rgb
	);
	vec3 wood = three_color_ramp(
		wood_value,
		wood_shadow.rgb,
		wood_mid.rgb,
		wood_light.rgb
	);

	// Retain restrained variation from the generated atlas without allowing its
	// original preview color cast to leak back into the game.
	float source_luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float detail = mix(1.0 - texture_detail, 1.0 + texture_detail, smoothstep(0.04, 0.7, source_luma));
	ALBEDO = mix(wood, foliage, foliage_mask) * detail;
	ROUGHNESS = surface_roughness;
	SPECULAR = surface_specular;

	if (use_normal_map) {
		NORMAL_MAP = texture(source_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
