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

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
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

	ALBEDO = color;
}
