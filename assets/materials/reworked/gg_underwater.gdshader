shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Underwater floor / submerged rock material: matte base + animated caustics
// projected in world space. Two overlapping fields, a restrained RGB split,
// and luminance/depth fades keep the light lively without a scene-wide
// projector or texture dependency.

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 caustic_color : source_color = vec4(1.0);
uniform float water_level = -0.14;
uniform float caustic_strength = 0.4;
uniform float depth_fade = 1.0;
uniform float roughness_val = 0.9;

varying vec3 world_pos;

float caustic_field(vec2 p, float t) {
	float a = sin(p.x + t) + sin(p.y * 1.17 - t * 0.82);
	float b = sin((p.x + p.y) * 0.73 - t * 0.57);
	float ridge = 1.0 - abs(a + b * 0.7) * 0.34;
	return pow(clamp(ridge, 0.0, 1.0), 5.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = albedo.rgb;
	float under = water_level - world_pos.y;
	if (under > 0.01) {
		float t = TIME;
		vec2 p = world_pos.xz;
		float red = caustic_field(p * 3.2 + vec2(0.018, 0.0), t * 0.71);
		float green = caustic_field(p * 3.2, t * 0.71);
		float blue = caustic_field(p * 3.2 - vec2(0.018, 0.0), t * 0.71);
		float overlap = caustic_field(
			p * 4.85 + vec2(2.1, -1.4),
			-t * 0.43
		);
		vec3 caustic_rgb = vec3(red, green, blue) * overlap;
		float fade = exp(-under / depth_fade);
		float luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float luminance_fade = 1.0 - smoothstep(0.72, 1.0, luminance);
		col += caustic_color.rgb * caustic_rgb * caustic_strength * fade * luminance_fade;
		// Mild blue-green absorption with depth keeps things aquatic.
		col *= mix(vec3(1.0), vec3(0.82, 0.95, 0.97), clamp(under / (depth_fade * 2.0), 0.0, 0.8));
	}
	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
