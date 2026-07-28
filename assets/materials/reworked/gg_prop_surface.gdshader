shader_type spatial;
// Diorama surface for opaque palette materials. GG's props read "soft" because
// their painted albedo textures bake a gentle vertical shading ramp (lighter,
// slightly warm tops falling to darker, slightly cool bases) on top of a plain
// Unity Standard response. Suma's semantic materials are flat colors, so this
// shader reproduces that baked ramp analytically over each instance's height
// while keeping the StandardMaterial3D-equivalent PBR inputs.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.72;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float specular_val : hint_range(0.0, 1.0) = 0.5;
// World units of height the ramp spans, measured from the instance origin.
// GG tiles are 1 unit; Suma tiles are 1.35, so spans/amplitudes are scaled
// to match the reference read.
uniform float ramp_height = 1.35;
uniform float ramp_top_lift = 0.10;
uniform float ramp_bottom_drop = 0.16;
// Subtle temperature shift across the ramp: warm tops, cool bases.
uniform vec3 ramp_top_tint = vec3(1.02, 1.0, 0.965);
uniform vec3 ramp_bottom_tint = vec3(0.985, 0.99, 1.02);
// Painted-texture mottling: GG's albedo maps carry soft low-frequency
// blotches; this reproduces that grain in world space so flat fields stop
// reading as solid fills.
uniform float mottle_amount = 0.035;
uniform float mottle_scale = 1.2;

varying float object_height;
varying vec3 world_pos;

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(cell + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(cell + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(cell + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	object_height = world_pos.y - MODEL_MATRIX[3].y;
}

void fragment() {
	float t = smoothstep(0.0, 1.0, clamp(object_height / max(ramp_height, 0.001), 0.0, 1.0));
	float value_shift = mix(-ramp_bottom_drop, ramp_top_lift, t);
	vec3 tint = mix(ramp_bottom_tint, ramp_top_tint, t);
	float grain = value_noise(world_pos.xz * mottle_scale)
		+ 0.5 * value_noise(world_pos.xz * mottle_scale * 2.7);
	value_shift += (grain / 1.5 - 0.5) * 2.0 * mottle_amount;
	ALBEDO = clamp(albedo.rgb * tint * (1.0 + value_shift), vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
	SPECULAR = specular_val;
}
