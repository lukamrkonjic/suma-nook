shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Garden master material: matte stylized PBR shared by every ordinary surface.
// The look lives in the whole pipeline (sun + ambient + AO + bevels); this
// shader only adds a very mild continuous orientation tint — tops a touch
// brighter and warmer, sides cooler, undersides darkest. Never a cel band.

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.18;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec3 top_tint = vec3(1.04, 1.03, 0.98);
uniform vec3 side_tint = vec3(0.96, 0.94, 0.91);
uniform vec3 down_tint = vec3(0.85, 0.83, 0.80);

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = clamp(world_normal.y, -1.0, 1.0);
	vec3 tint;
	if (up >= 0.0) {
		tint = mix(side_tint, top_tint, smoothstep(0.15, 0.85, up));
	} else {
		tint = mix(side_tint, down_tint, smoothstep(0.15, 0.85, -up));
	}
	ALBEDO = albedo.rgb * tint;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}
