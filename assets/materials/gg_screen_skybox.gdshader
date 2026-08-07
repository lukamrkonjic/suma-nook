shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Garden Galaxy's "Custom/Screen Skybox" backdrop, drawn inside the 3D pass
// on the far plane in linear radiance. Suma uses one uninterrupted theme
// colour here; the sparse animated sparkle field remains above that wash.
// Reference values:
// _YOffset 0.69, _Exponent2 0.25, _SparkleOn 1, _SparkleIntensity 10,
// _SparkleThreshold 0.965, _SparkleSoftness 0.01, _SparkleSpeed 0.002.
// The theme controller pushes the selected flat colour into every anchor.
// Clouds are NOT drawn here: the volumetric void-cloud ocean is world-space
// geometry-composited fog, so this backdrop deliberately accepts fog (no
// fog_disabled) and keeps the sky an open, calm wash.

uniform vec3 color0 : source_color = vec3(1.0);
uniform vec3 color1 : source_color = vec3(1.0);
// Retained as compatibility parameters for old resources and transitions;
// the lighting rig now supplies the same flat colour to every anchor.
uniform vec3 zenith_color : source_color = vec3(1.0);
uniform vec3 horizon_accent_color : source_color = vec3(1.0);
uniform float sparkle_amount = 1.0;      // 0 disables the sparkle field
uniform float sparkle_intensity = 10.0;
uniform float sparkle_threshold = 0.965;
uniform float sparkle_softness = 0.01;
uniform float sparkle_speed = 0.002;
uniform vec3 centre_glow_color : source_color = vec3(1.0);
uniform vec3 shooting_star_trail_color : source_color = vec3(1.0);
uniform vec3 shooting_star_head_color : source_color = vec3(1.0);
uniform vec3 night_star_color : source_color = vec3(1.0);
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
	vec3 cool_trail = shooting_star_trail_color * (core + glow);
	vec3 warm_head = shooting_star_head_color * head * 0.55;
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
	float mean_luminance = dot(
		color0,
		vec3(0.2126, 0.7152, 0.0722)
	);
	float daylight = smoothstep(0.24, 0.74, mean_luminance);
	vec3 color = color0;

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
	color += centre_glow_color * mote * 0.20;

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
		// The starfield blooms after dark: brighter, slightly cool-white,
		// while daytime keeps only faint warm glints.
		float night_amount = 1.0 - daylight;
		vec3 star_tint = mix(vec3(1.0), night_star_color, night_amount);
		float star_boost = mix(1.0, 2.2, night_amount);
		color += star_tint * gate * twinkle * spot
			* sparkle_intensity * 0.02 * sparkle_amount * star_boost;
	}
	color += shooting_star_radiance(uv);

	ALBEDO = color;
}
