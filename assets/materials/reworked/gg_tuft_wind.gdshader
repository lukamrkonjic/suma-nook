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
// The exact ground-plane colour: card bases dissolve into it so tufts
// grow OUT of the tile instead of sitting on it as stickers.
uniform vec4 ground_color : source_color = vec4(0.455, 0.522, 0.306, 1.0);
uniform float ground_blend_start = 0.45;
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
	// UV.y = 1 at the card base: fully ground-coloured there, fading to
	// the pure tuft tint by `ground_blend_start` so the lower gradient IS
	// the ground and every tuft blends into the plane it stands on.
	float ground_mix = smoothstep(ground_blend_start, 1.0, UV.y);
	ALBEDO = mix(albedo_sample.rgb, ground_color.rgb, ground_mix);
	ALPHA = albedo_sample.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = 0.30;
	ROUGHNESS = 1.0;
}
