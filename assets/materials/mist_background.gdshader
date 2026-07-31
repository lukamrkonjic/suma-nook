shader_type canvas_item;
// Screen-space vertical background gradient for the mist preset, with very
// sparse soft star points. Draws behind the 3D diorama via BG_CANVAS.

uniform vec4 top_color : source_color = vec4(0.7059, 0.7765, 0.7725, 1.0);
uniform vec4 mid_color : source_color = vec4(0.7255, 0.8, 0.7765, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.7333, 0.8157, 0.7922, 1.0);
uniform vec4 centre_glow_color : source_color = vec4(1.0, 0.9412, 0.8157, 1.0);
uniform vec4 cloud_highlight_color : source_color = vec4(1.0, 0.92, 0.82, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.62, 0.55, 0.56, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.82;
uniform float cloud_density : hint_range(0.0, 1.5) = 0.96;
uniform float cloud_speed : hint_range(-0.05, 0.05) = 0.0015;
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

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x),
		mix(
			hash21(cell + vec2(0.0, 1.0)),
			hash21(cell + vec2(1.0)),
			local.x
		),
		local.y
	);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	mat2 rotation = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(p) * amplitude;
		p = rotation * p * 2.03 + vec2(11.7, 7.9);
		amplitude *= 0.5;
	}
	return sum / 0.9375;
}

vec2 hash22(vec2 p) {
	return fract(
		sin(vec2(
			dot(p, vec2(127.1, 311.7)),
			dot(p, vec2(269.5, 183.3))
		)) * 43758.5453
	);
}

float worley(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 2.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash22(cell + neighbor);
			nearest = min(
				nearest,
				length(neighbor + point - local)
			);
		}
	}
	return 1.0 - clamp(nearest, 0.0, 1.0);
}

float cloud_envelope(vec2 p) {
	float side_bank = smoothstep(0.25, 0.67, abs(p.x));
	side_bank *= smoothstep(0.4, 0.6, p.y);
	float lower_bank = smoothstep(0.69, 0.94, p.y) * 0.96;
	return max(side_bank, lower_bank);
}

float soft_ellipse(
	vec2 p,
	vec2 center,
	vec2 radius
) {
	float distance_to_edge = length((p - center) / radius);
	return 1.0 - smoothstep(0.72, 1.0, distance_to_edge);
}

float cumulus_cluster(
	vec2 uv,
	vec2 center,
	float size,
	float aspect,
	vec2 seed
) {
	vec2 p = (uv - center) / size;
	p.x *= aspect;
	float shape = soft_ellipse(
		p,
		vec2(0.0, 0.16),
		vec2(0.72, 0.28)
	);
	shape = max(shape, soft_ellipse(
		p, vec2(-0.5, 0.05), vec2(0.34, 0.34)
	));
	shape = max(shape, soft_ellipse(
		p, vec2(-0.22, -0.12), vec2(0.42, 0.46)
	));
	shape = max(shape, soft_ellipse(
		p, vec2(0.12, -0.22), vec2(0.48, 0.55)
	));
	shape = max(shape, soft_ellipse(
		p, vec2(0.47, -0.04), vec2(0.37, 0.4)
	));
	shape = max(shape, soft_ellipse(
		p, vec2(0.7, 0.12), vec2(0.28, 0.27)
	));
	float edge_detail = fbm(p * 3.15 + seed);
	return clamp(shape * (0.84 + edge_detail * 0.24), 0.0, 1.0);
}

float cloud_bank_field(vec2 uv, float aspect) {
	float field = max(
		cumulus_cluster(
			uv,
			vec2(-0.02, 0.9),
			0.25,
			aspect,
			vec2(2.7, 5.1)
		),
		cumulus_cluster(
			uv,
			vec2(1.03, 0.88),
			0.27,
			aspect,
			vec2(-3.2, 8.4)
		)
	);
	field = max(
		field,
		cumulus_cluster(
			uv,
			vec2(0.5, 1.12),
			0.31,
			aspect,
			vec2(7.3, -4.2)
		) * 0.72
	);
	return field;
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

	vec2 cloud_p = vec2((UV.x - 0.5) * aspect, UV.y);
	cloud_p.x += TIME * cloud_speed;
	float silhouette_noise = fbm(
		cloud_p * vec2(3.0, 3.7)
		+ vec2(TIME * cloud_speed * 5.0, 3.1)
	);
	float lighting_noise = fbm(
		cloud_p * vec2(1.65, 2.05) + vec2(-2.6, 8.4)
	);
	vec2 cloud_warp = vec2(
		silhouette_noise - 0.5,
		fbm(
			cloud_p * vec2(2.5, 3.1)
			+ vec2(8.2, -5.7)
		) - 0.5
	) * 0.034;
	vec2 density_p = cloud_p + cloud_warp;
	float broad = fbm(
		density_p * vec2(1.75, 2.3) + vec2(-4.2, 2.8)
	);
	float cloud_field = cloud_bank_field(UV, aspect);
	float upper_field = cloud_bank_field(
		UV + vec2(0.008, 0.025),
		aspect
	);
	cloud_field *= (
		0.84 + broad * 0.2 + cloud_density * 0.08
	);
	upper_field *= (
		0.84 + broad * 0.2 + cloud_density * 0.08
	);
	float cloud_mask = smoothstep(
		0.2,
		0.68,
		cloud_field
	) * cloud_opacity;
	float cloud_inner = smoothstep(0.68, 0.92, cloud_field);
	float puff_light = pow(
		worley(
			density_p * vec2(4.2, 5.25)
			+ vec2(7.4, -3.6)
		),
		1.35
	);
	float top_lighting = 1.0 - smoothstep(0.58, 1.08, UV.y);
	float cloud_light = clamp(
		0.08 + top_lighting * 0.78 + cloud_inner * 0.04
		+ puff_light * 0.08 + (lighting_noise - 0.5) * 0.14,
		0.0,
		1.0
	);
	vec3 cloud_color = mix(
		cloud_shadow_color.rgb,
		cloud_highlight_color.rgb,
		cloud_light
	);
	col = mix(col, cloud_color, cloud_mask);
	float sculpted_upper_light = smoothstep(
		0.025,
		0.26,
		max(upper_field - cloud_field, 0.0)
	) * cloud_mask;
	col = mix(
		col,
		cloud_highlight_color.rgb,
		sculpted_upper_light * 0.72
	);
	col += cloud_highlight_color.rgb * (
		cloud_mask * (1.0 - cloud_inner)
		* top_lighting * 0.1
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
			col = mix(col, vec3(0.96, 0.98, 0.96), smoothstep(0.06, 0.0, d) * 0.75);
		}
	}
	col += shooting_star_radiance(UV);
	// With hdr_2d the canvas buffer is linear and BG_CANVAS feeds it to the
	// 3D pass as-is, which matches how these authored values behaved before
	// hdr_2d — no conversion needed.
	COLOR = vec4(col, 1.0);
}
