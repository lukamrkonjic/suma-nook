shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Underwater flora: slow shader sway (stronger toward blade tips, anchored
// bases), caustic shimmer, saturation falling off with depth.

uniform vec4 albedo : source_color = vec4(0.435, 0.647, 0.333, 1.0);
uniform vec4 caustic_color : source_color = vec4(0.675, 0.808, 0.804, 1.0);
uniform float water_level = -0.14;
uniform float sway_strength = 0.06;
uniform float sway_speed = 1.1;
uniform float depth_fade = 1.0;

varying vec3 world_pos;
varying float base_y;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	base_y = origin.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(wp.y - origin.y, 0.0);
	float phase = origin.x * 1.7 + origin.z * 2.3;
	float sway = sin(TIME * sway_speed + phase) * sway_strength * h * h;
	float sway2 = cos(TIME * sway_speed * 0.63 + phase * 1.4) * sway_strength * 0.6 * h * h;
	VERTEX.x += sway;
	VERTEX.z += sway2;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = albedo.rgb;
	float under = water_level - world_pos.y;
	if (under > 0.01) {
		float t = TIME;
		float a = sin(world_pos.x * 3.4 + t * 0.42) * sin(world_pos.z * 3.1 - t * 0.35);
		float c = pow(clamp(a * 0.5 + 0.5, 0.0, 1.0), 2.0);
		col += caustic_color.rgb * c * 0.22 * exp(-under / depth_fade);
		float desat = clamp(under / (depth_fade * 2.5), 0.0, 0.5);
		col = mix(col, vec3(dot(col, vec3(0.333))) * vec3(0.8, 0.95, 0.97), desat);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
