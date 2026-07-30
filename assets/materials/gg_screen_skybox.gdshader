shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
// Reconstruction of Garden Galaxy's "Custom/Screen Skybox" backdrop, drawn
// exactly where Unity draws it: inside the 3D pass, on the far plane, in
// linear radiance. A screen-space vertical wash between two near-identical
// creams plus a sparse animated sparkle field. Serialized reference values:
// _YOffset 0.69, _Exponent2 0.25, _SparkleOn 1, _SparkleIntensity 10,
// _SparkleThreshold 0.965, _SparkleSoftness 0.01, _SparkleSpeed 0.002.
// The theme controller pushes bgColor0/bgColor1 into it on every blend.

uniform vec3 color0 : source_color = vec3(0.906, 0.87623, 0.78265);
uniform vec3 color1 : source_color = vec3(0.90588, 0.87059, 0.81569);
uniform float y_offset = 0.69;
uniform float gradient_exponent = 0.25;
uniform float sparkle_amount = 1.0;      // 0 disables the sparkle field
uniform float sparkle_intensity = 10.0;
uniform float sparkle_threshold = 0.965;
uniform float sparkle_softness = 0.01;
uniform float sparkle_speed = 0.002;
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
	// Verified against the live game: the visible field is color0 (its graded
	// value measures (229,225,202) on screen), with color1 bleeding in only
	// near the bottom edge. The 0.25 exponent keeps the blend biased so almost
	// the whole screen reads as color0.
	float up = clamp(1.0 - SCREEN_UV.y + (y_offset - 0.5), 0.0, 1.0);
	vec3 color = mix(color1, color0, pow(up, gradient_exponent));

	if (sparkle_amount > 0.0) {
		vec2 cell = floor(SCREEN_UV * vec2(96.0, 54.0));
		float seed = hash21(cell);
		// Only a tiny fraction of cells ever sparkle; each fades in and out
		// on its own slow phase.
		float gate = step(sparkle_threshold, seed);
		float phase = fract(seed * 71.37 + TIME * sparkle_speed * 60.0);
		float twinkle = smoothstep(0.0, 0.5, phase) * smoothstep(1.0, 0.5, phase);
		vec2 local = fract(SCREEN_UV * vec2(96.0, 54.0)) - 0.5;
		float spot = 1.0 - smoothstep(0.0, 0.06 + sparkle_softness * 4.0, length(local));
		color += vec3(1.0) * gate * twinkle * spot * sparkle_intensity * 0.02 * sparkle_amount;
	}
	color += shooting_star_radiance(SCREEN_UV);

	ALBEDO = color;
}
