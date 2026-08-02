shader_type canvas_item;
// Screen-space vertical background gradient for the mist preset, with very
// sparse soft star points. Draws behind the 3D diorama via BG_CANVAS.
// Clouds are NOT drawn here: the volumetric void-cloud ocean below the
// island is world-space fog, so the backdrop stays a calm open wash.

uniform vec4 top_color : source_color = vec4(1.0);
uniform vec4 mid_color : source_color = vec4(1.0);
uniform vec4 bottom_color : source_color = vec4(1.0);
uniform vec4 centre_glow_color : source_color = vec4(1.0);
uniform vec3 shooting_star_trail_color : source_color = vec3(1.0);
uniform vec3 shooting_star_head_color : source_color = vec3(1.0);
uniform vec3 mist_star_color : source_color = vec3(1.0);
uniform float mote_density : hint_range(0.0, 1.0) = 0.14;
uniform float stars_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shooting_star_active = 0.0;
uniform vec2 shooting_star_start = vec2(0.28, 0.18);
uniform vec2 shooting_star_direction = vec2(0.24, 0.14);
uniform float shooting_star_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shooting_star_length = 0.095;
uniform float shooting_star_width = 0.0012;
uniform float shooting_star_intensity = 0.6;
uniform float shooting_star_aspect = 1.7778;

float hash21(vec2 p) {
	return fract(
		sin(dot(p, vec2(127.1, 311.7)))
		* 43758.5453123
	);
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

void fragment() {
	float t = UV.y;
	vec3 col;
	if (t < 0.5) {
		col = mix(top_color.rgb, mid_color.rgb, t * 2.0);
	} else {
		col = mix(mid_color.rgb, bottom_color.rgb, (t - 0.5) * 2.0);
	}
	float aspect = (
		SCREEN_PIXEL_SIZE.y
		/ max(SCREEN_PIXEL_SIZE.x, 0.000001)
	);
	vec2 radial_uv = UV - vec2(0.58, 0.34);
	radial_uv.x *= aspect * 0.64;
	radial_uv.y *= 1.08;
	float centre_glow = exp(-dot(radial_uv, radial_uv) * 3.1);
	col = mix(
		col,
		centre_glow_color.rgb,
		centre_glow * 0.16
	);

	vec2 mote_grid = UV * vec2(38.0, 22.0);
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
	col += centre_glow_color.rgb * mote * (
		0.18 + centre_glow * 0.2
	);
	if (stars_amount > 0.0) {
		vec2 grid = UV * vec2(42.0, 24.0);
		vec2 cell = floor(grid);
		vec2 f = fract(grid);
		float h = hash21(cell);
		if (h > 1.0 - stars_amount * 0.12) {
			vec2 star_pos = vec2(fract(h * 34.7), fract(h * 91.3)) * 0.6 + 0.2;
			float d = length(f - star_pos);
			col = mix(col, mist_star_color, smoothstep(0.06, 0.0, d) * 0.75);
		}
	}
	col += shooting_star_radiance(UV);
	// With hdr_2d the canvas buffer is linear and BG_CANVAS feeds it to the
	// 3D pass as-is, which matches how these authored values behaved before
	// hdr_2d — no conversion needed.
	COLOR = vec4(col, 1.0);
}
