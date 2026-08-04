shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Quiet moss nap for the broad clay-sculpted forest-floor tile. The geometry
// remains completely still: only a very low-amplitude, low-frequency change in
// diffuse value suggests fibers turning in a breeze. There is deliberately no
// texture grain, normal noise, vertex wobble, gloss, or gelatin deformation.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.98;
uniform float specular_val : hint_range(0.0, 1.0) = 0.10;
uniform float nap_strength : hint_range(0.0, 0.05) = 0.012;
uniform float nap_scale : hint_range(0.1, 8.0) = 1.65;
uniform float nap_speed : hint_range(0.0, 1.0) = 0.075;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.16;
uniform float rim_tint_amount : hint_range(0.0, 1.0) = 0.72;

varying vec3 world_pos;
varying float top_facing;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	top_facing = smoothstep(0.42, 0.88, world_normal.y);
}

void fragment() {
	float phase = TIME * nap_speed;
	// Two wide crossing flows avoid stripes. Their tiny amplitude reads as a
	// changing velvet nap, never as a painted pattern in a still frame.
	float flow_a = sin(
		world_pos.x * nap_scale
		+ sin(world_pos.z * nap_scale * 0.72 - phase) * 0.62
		+ phase
	);
	float flow_b = sin(
		(world_pos.x * -0.54 + world_pos.z * 0.84) * nap_scale * 0.78
		- phase * 0.73
	);
	float nap = (flow_a * 0.62 + flow_b * 0.38) * nap_strength * top_facing;
	ALBEDO = clamp(albedo.rgb * (1.0 + nap), vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	SPECULAR = specular_val;
	RIM = rim_amount * mix(0.28, 1.0, top_facing);
	RIM_TINT = rim_tint_amount;
}
