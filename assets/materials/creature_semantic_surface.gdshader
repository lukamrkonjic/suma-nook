shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, ambient_light_disabled, cull_disabled;

uniform int pattern_mode : hint_range(0, 4) = 0;
uniform float pattern_scale = 24.0;
uniform vec4 pattern_color : source_color = vec4(1.0);
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ruffle_amount = 0.0;
uniform float ruffle_speed = 2.2;
uniform float strand_strength : hint_range(0.0, 1.0) = 0.0;
uniform float coat_gloss : hint_range(0.0, 1.0) = 0.0;

varying vec3 coat_position;


float coat_hash(vec3 point) {
	return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}


float coat_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 offset = fract(point);
	offset = offset * offset * (3.0 - 2.0 * offset);
	float c000 = coat_hash(cell);
	float c100 = coat_hash(cell + vec3(1.0, 0.0, 0.0));
	float c010 = coat_hash(cell + vec3(0.0, 1.0, 0.0));
	float c110 = coat_hash(cell + vec3(1.0, 1.0, 0.0));
	float c001 = coat_hash(cell + vec3(0.0, 0.0, 1.0));
	float c101 = coat_hash(cell + vec3(1.0, 0.0, 1.0));
	float c011 = coat_hash(cell + vec3(0.0, 1.0, 1.0));
	float c111 = coat_hash(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(c000, c100, offset.x), mix(c010, c110, offset.x), offset.y),
		mix(mix(c001, c101, offset.x), mix(c011, c111, offset.x), offset.y),
		offset.z
	);
}


float coat_pattern_mask(vec3 point) {
	if (pattern_mode == 1) {
		float wobble = coat_noise(point * pattern_scale * 0.35) * 2.2;
		return smoothstep(
			0.25, 0.75,
			0.5 + 0.5 * sin((point.y + point.z * 0.8) * pattern_scale + wobble)
		);
	}
	if (pattern_mode == 2) {
		return smoothstep(0.62, 0.78, coat_noise(point * pattern_scale));
	}
	if (pattern_mode == 3) {
		return smoothstep(0.48, 0.62, coat_noise(point * pattern_scale * 0.3));
	}
	if (pattern_mode == 4) {
		float ring = fract(point.y * pattern_scale * 0.5);
		return smoothstep(0.42, 0.5, ring) * smoothstep(1.0, 0.92, ring);
	}
	return 0.0;
}


void vertex() {
	coat_position = VERTEX;
	if (ruffle_amount > 0.0001) {
		float stir = coat_noise(VERTEX * 16.0 + vec3(TIME * ruffle_speed)) - 0.5;
		VERTEX += NORMAL * stir * 2.0 * ruffle_amount;
	}
}


void fragment() {
	vec3 surface_color = COLOR.rgb;
	if (pattern_strength > 0.001) {
		surface_color = mix(
			surface_color,
			pattern_color.rgb,
			coat_pattern_mask(coat_position) * pattern_strength
		);
	}
	if (strand_strength > 0.001) {
		float strand = coat_noise(coat_position * vec3(90.0, 9.0, 90.0));
		surface_color *= 1.0 + (strand - 0.5) * 0.24 * strand_strength;
	}
	float top_facing = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	surface_color *= mix(1.05, 0.95, top_facing);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float ink_rim = smoothstep(0.11, 0.015, facing);
	ALBEDO = mix(surface_color, surface_color * 0.66, ink_rim * 0.28);
	ROUGHNESS = 1.0 - coat_gloss * 0.45;
	SPECULAR = coat_gloss * 0.28;
	METALLIC = 0.0;
	// Fill in place of ambient, weighted toward the camera: the gameplay key
	// light often sits behind characters, and without this bounce term every
	// camera-facing face and limb collapses to one muddy unlit tone.
	EMISSION = ALBEDO * (0.30 + 0.22 * facing);
}


void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0);
	float toon_band = 0.22 * smoothstep(0.10, 0.18, diffuse);
	toon_band += 0.33 * smoothstep(0.52, 0.60, diffuse);
	// Received shadows only deepen the painted tone; a full shadow term
	// crushes faces and limb joints to the emission fill on toy-scale bodies.
	float shade = mix(0.62, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * shade * toon_band;
}
