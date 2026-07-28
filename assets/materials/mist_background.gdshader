shader_type canvas_item;
// Screen-space vertical background gradient for the mist preset, with very
// sparse soft star points. Draws behind the 3D diorama via BG_CANVAS.

uniform vec4 top_color : source_color = vec4(0.7059, 0.7765, 0.7725, 1.0);
uniform vec4 mid_color : source_color = vec4(0.7255, 0.8, 0.7765, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.7333, 0.8157, 0.7922, 1.0);
uniform float stars_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float t = UV.y;
	vec3 col;
	if (t < 0.5) {
		col = mix(top_color.rgb, mid_color.rgb, t * 2.0);
	} else {
		col = mix(mid_color.rgb, bottom_color.rgb, (t - 0.5) * 2.0);
	}
	if (stars_amount > 0.0) {
		vec2 grid = UV * vec2(42.0, 24.0);
		vec2 cell = floor(grid);
		vec2 f = fract(grid);
		float h = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		if (h > 1.0 - stars_amount * 0.12) {
			vec2 star_pos = vec2(fract(h * 34.7), fract(h * 91.3)) * 0.6 + 0.2;
			float d = length(f - star_pos);
			col = mix(col, vec3(0.96, 0.98, 0.96), smoothstep(0.06, 0.0, d) * 0.75);
		}
	}
	// With HDR 2D enabled this rect's output is decoded sRGB->linear twice on
	// its way to the 3D pipeline: once when written into the linear 2D buffer
	// and once when BG_CANVAS samples that buffer as the 3D background
	// (verified by measurement). Encode twice so the authored color lands in
	// the 3D pass unchanged, preserving the look this preset was tuned under.
	vec3 encoded = col;
	for (int i = 0; i < 2; i++) {
		encoded = mix(
			encoded * 12.92,
			1.055 * pow(max(encoded, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
			step(vec3(0.0031308), encoded)
		);
	}
	COLOR = vec4(encoded, 1.0);
}
