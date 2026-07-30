shader_type canvas_item;
// Screen-space vertical background gradient for the mist preset, with very
// sparse soft star points. Draws behind the 3D diorama via BG_CANVAS.

uniform vec4 top_color : source_color = vec4(0.7059, 0.7765, 0.7725, 1.0);
uniform vec4 mid_color : source_color = vec4(0.7255, 0.8, 0.7765, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.7333, 0.8157, 0.7922, 1.0);
uniform float stars_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shooting_star_active = 0.0;
uniform vec2 shooting_star_start = vec2(0.28, 0.18);
uniform vec2 shooting_star_direction = vec2(0.24, 0.14);
uniform float shooting_star_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shooting_star_length = 0.095;
uniform float shooting_star_width = 0.0012;
uniform float shooting_star_intensity = 0.6;
uniform float shooting_star_aspect = 1.7778;

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
	col += shooting_star_radiance(UV);
	// With hdr_2d the canvas buffer is linear and BG_CANVAS feeds it to the
	// 3D pass as-is, which matches how these authored values behaved before
	// hdr_2d — no conversion needed.
	COLOR = vec4(col, 1.0);
}
