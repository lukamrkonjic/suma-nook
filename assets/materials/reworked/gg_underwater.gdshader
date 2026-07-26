shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Underwater floor / submerged rock material: matte base + animated caustics
// projected in world space. Caustics fade with depth and never appear above
// the waterline. Cheap: two scrolling interference patterns, no textures.

uniform vec4 albedo : source_color = vec4(0.784, 0.753, 0.682, 1.0);
uniform vec4 caustic_color : source_color = vec4(0.675, 0.808, 0.804, 1.0);   // #ACCECD
uniform float water_level = -0.14;
uniform float caustic_strength = 0.4;
uniform float depth_fade = 1.0;
uniform float roughness_val = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = albedo.rgb;
	float under = water_level - world_pos.y;
	if (under > 0.01) {
		float t = TIME;
		// Two drifting interference patterns, sharpened into cells.
		float a = sin(world_pos.x * 3.4 + t * 0.42) * sin(world_pos.z * 3.1 - t * 0.35);
		float b = sin((world_pos.x + world_pos.z) * 2.3 - t * 0.3) * sin((world_pos.x - world_pos.z) * 2.7 + t * 0.26);
		float c = pow(clamp(a * 0.5 + 0.5, 0.0, 1.0) * clamp(b * 0.5 + 0.5, 0.0, 1.0), 2.2);
		float fade = exp(-under / depth_fade);
		col += caustic_color.rgb * c * caustic_strength * fade;
		// Mild blue-green absorption with depth keeps things aquatic.
		col *= mix(vec3(1.0), vec3(0.82, 0.95, 0.97), clamp(under / (depth_fade * 2.0), 0.0, 0.8));
	}
	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
