shader_type spatial;
render_mode cull_back, alpha_to_coverage, specular_disabled;

// Wind-swaying tuft card: the sprite carpet's material with a gentle
// travelling wave. The sprite's white gradient carries form, `tint`
// carries all hue (the kit's sprite-material contract), and the vertex
// stage leans card tips along the wind while roots stay pinned.
//
// UV.y = 0 at the sprite's TIPS (the card builder's mapping), so the
// sway weight is simply the inverted V squared — a soft whip profile.
// Phase comes from WORLD position: neighbouring tufts and neighbouring
// tiles ride one coherent wave instead of flickering independently.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wind_amplitude = 0.026;
uniform float wind_speed = 1.35;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_spatial_scale = 1.6;
uniform float wind_second_amount = 0.35;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway_weight = 1.0 - UV.y;
	sway_weight *= sway_weight;
	float phase = dot(world.xz, wind_direction) * wind_spatial_scale;
	float wave = sin(TIME * wind_speed + phase)
		+ wind_second_amount
			* sin(TIME * wind_speed * 2.33 + phase * 1.7 + 1.3);
	VERTEX.xz += wind_direction * (wind_amplitude * wave * sway_weight);
}

void fragment() {
	vec4 albedo_sample = texture(albedo_tex, UV) * tint;
	ALBEDO = albedo_sample.rgb;
	ALPHA = albedo_sample.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = 0.30;
	ROUGHNESS = 1.0;
}
