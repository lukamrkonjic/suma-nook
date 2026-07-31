shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Reconstruction of Garden Galaxy's "Custom/Screen Skybox" backdrop, drawn
// exactly where Unity draws it: inside the 3D pass, on the far plane, in
// linear radiance. Several very broad, slowly drifting gradient fields keep
// the apricot atmosphere alive without ever becoming a readable noise map.
// The sparse animated sparkle field remains above that wash. Reference values:
// _YOffset 0.69, _Exponent2 0.25, _SparkleOn 1, _SparkleIntensity 10,
// _SparkleThreshold 0.965, _SparkleSoftness 0.01, _SparkleSpeed 0.002.
// The theme controller pushes bgColor0/bgColor1 into it on every blend.
// Clouds are NOT drawn here: the volumetric void-cloud ocean is world-space
// geometry-composited fog, so this backdrop deliberately accepts fog (no
// fog_disabled) and keeps the sky an open, calm wash.

uniform vec3 color0 : source_color = vec3(0.906, 0.87623, 0.78265);
uniform vec3 color1 : source_color = vec3(0.90588, 0.87059, 0.81569);
uniform float y_offset = 0.69;
uniform float gradient_exponent = 0.25;
uniform float sparkle_amount = 1.0;      // 0 disables the sparkle field
uniform float sparkle_intensity = 10.0;
uniform float sparkle_threshold = 0.965;
uniform float sparkle_softness = 0.01;
uniform float sparkle_speed = 0.002;
uniform vec3 centre_glow_color : source_color = vec3(1.0, 0.93, 0.80);
uniform float sky_motion_speed : hint_range(0.0, 0.03) = 0.006;
uniform float sky_breath_strength : hint_range(0.0, 0.2) = 0.085;
uniform float mote_density : hint_range(0.0, 1.0) = 0.2;
uniform float shooting_star_active = 0.0;
uniform vec2 shooting_star_start = vec2(0.28, 0.18);
uniform vec2 shooting_star_direction = vec2(0.24, 0.14);
uniform float shooting_star_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shooting_star_length = 0.095;
uniform float shooting_star_width = 0.0012;
uniform float shooting_star_intensity = 0.6;
uniform float shooting_star_aspect = 1.7778;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise_2d(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float bottom = mix(
		hash21(cell),
		hash21(cell + vec2(1.0, 0.0)),
		local.x
	);
	float top = mix(
		hash21(cell + vec2(0.0, 1.0)),
		hash21(cell + vec2(1.0, 1.0)),
		local.x
	);
	return mix(bottom, top, local.y);
}

float broad_sky_field(vec2 point) {
	float value = 0.0;
	float amplitude = 0.55;
	mat2 turn = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise_2d(point) * amplitude;
		point = turn * point * 1.92 + vec2(3.7, 1.9);
		amplitude *= 0.47;
	}
	return value / 1.01;
}

vec3 shooting_star_radiance(vec2 uv) {
	if (shooting_star_active < 0.5) {
		return vec3(0.0);
	}

	vec2 head_uv = shooting_star_start
		+ shooting_star_direction * shooting_star_progress;
	vec2 direction = normalize(vec2(
		shooting_star_direction.x * shooting_star_aspect,
		shooting_star_direction.y
	));
	vec2 delta = vec2(
		(uv.x - head_uv.x) * shooting_star_aspect,
		uv.y - head_uv.y
	);
	float along = dot(delta, direction);
	float side = abs(direction.x * delta.y - direction.y * delta.x);
	float segment = smoothstep(
		-shooting_star_length,
		-shooting_star_length + shooting_star_width * 5.0,
		along
	) * (1.0 - smoothstep(-shooting_star_width, shooting_star_width, along));
	float taper = clamp(1.0 + along / shooting_star_length, 0.0, 1.0);
	float core = (
		1.0 - smoothstep(
			shooting_star_width * 0.18,
			shooting_star_width,
			side
		)
	) * segment * taper;
	float glow = (
		1.0 - smoothstep(
			shooting_star_width,
			shooting_star_width * 4.5,
			side
		)
	) * segment * taper * 0.22;
	float head = 1.0 - smoothstep(
		0.0,
		shooting_star_width * 3.2,
		length(delta)
	);
	float event_fade = smoothstep(0.0, 0.14, shooting_star_progress)
		* (1.0 - smoothstep(0.72, 1.0, shooting_star_progress));
	vec3 cool_trail = vec3(0.82, 0.91, 1.0) * (core + glow);
	vec3 warm_head = vec3(1.0, 0.93, 0.76) * head * 0.55;
	return (cool_trail + warm_head)
		* shooting_star_intensity
		* event_fade;
}

void vertex() {
	// Fullscreen triangle-strip quad pinned to the far plane (reversed-Z:
	// far is depth ~0), so every scene surface depth-tests in front of it.
	POSITION = vec4(VERTEX.xy, 0.00001, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float sky_time = TIME * sky_motion_speed;
	float mean_luminance = dot(
		(color0 + color1) * 0.5,
		vec3(0.2126, 0.7152, 0.0722)
	);
	float daylight = smoothstep(0.24, 0.74, mean_luminance);

	// Two huge fields move in different directions. They bend the vertical
	// gradient into imperceptibly evolving pools rather than laying visible
	// noise over the sky. A full cycle takes minutes at the default speed.
	float field_a = broad_sky_field(
		uv * vec2(1.42, 1.16) + vec2(sky_time, -sky_time * 0.43)
	);
	float field_b = broad_sky_field(
		uv.yx * vec2(1.08, 1.36)
		+ vec2(-sky_time * 0.37, sky_time * 0.59)
		+ 8.3
	);
	// The reference sky reads in three luminous strata: deeper warm
	// cream-peach high up, a bright cream band through the middle, and a
	// pale near-white haze rising from below where distant clouds catch
	// the light. The theme colours are authored to the reference, so they
	// pass through almost untouched; daylight only adds the gentle lift
	// toward the luminous lower band.
	vec3 honey_top = color0;
	vec3 bright_cream = mix(color0, vec3(1.0), 0.14 * daylight);
	vec3 low_haze = mix(color1, vec3(1.0), 0.22 * daylight);
	float band = smoothstep(
		0.0,
		0.5,
		uv.y + (field_a - 0.5) * sky_breath_strength
	);
	vec3 color = mix(honey_top, bright_cream, band);
	float haze_rise = smoothstep(
		0.52,
		1.08,
		uv.y + (field_b - 0.5) * 0.1
	);
	color = mix(
		color,
		low_haze,
		haze_rise * (0.5 + 0.22 * daylight)
	);

	// One broad veiled light pool drifting slowly low through the sky,
	// matching the reference's luminous region beneath the island.
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 sun_position = vec2(
		0.62 + sin(sky_time * 0.73) * 0.05,
		0.52 + cos(sky_time * 0.51) * 0.03
	);
	vec2 radial_uv = uv - sun_position;
	radial_uv.x *= aspect * 0.64;
	radial_uv.y *= 1.08;
	float centre_glow = exp(-dot(radial_uv, radial_uv) * 2.6);
	color = mix(
		color,
		centre_glow_color,
		centre_glow * 0.12 * daylight
	);
	color *= 0.99 + field_a * 0.022 + field_b * 0.010;

	vec2 mote_grid = uv * vec2(38.0, 22.0);
	vec2 mote_cell = floor(mote_grid);
	vec2 mote_local = fract(mote_grid);
	float mote_hash = hash21(mote_cell);
	vec2 mote_pos = vec2(
		fract(mote_hash * 17.13),
		fract(
			mote_hash * 51.71
			+ TIME * (0.006 + mote_hash * 0.006)
		)
	);
	float mote_distance = length(
		(mote_local - mote_pos) * vec2(1.0, 1.35)
	);
	float mote_gate = step(
		1.0 - mote_density * 0.11,
		mote_hash
	);
	float mote = smoothstep(
		0.055,
		0.0,
		mote_distance
	) * mote_gate;
	color += centre_glow_color * mote * (
		0.20 + centre_glow * 0.22
	);

	if (sparkle_amount > 0.0) {
		vec2 cell = floor(uv * vec2(96.0, 54.0));
		float seed = hash21(cell);
		// Only a tiny fraction of cells ever sparkle; each fades in and out
		// on its own slow phase.
		float gate = step(sparkle_threshold, seed);
		float phase = fract(seed * 71.37 + TIME * sparkle_speed * 60.0);
		float twinkle = smoothstep(0.0, 0.5, phase) * smoothstep(1.0, 0.5, phase);
		vec2 local = fract(uv * vec2(96.0, 54.0)) - 0.5;
		float spot = 1.0 - smoothstep(0.0, 0.06 + sparkle_softness * 4.0, length(local));
		color += vec3(1.0) * gate * twinkle * spot * sparkle_intensity * 0.02 * sparkle_amount;
	}
	color += shooting_star_radiance(uv);

	ALBEDO = color;
}
