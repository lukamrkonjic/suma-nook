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
uniform vec3 centre_glow_color : source_color = vec3(1.0, 0.88, 0.65);
uniform vec3 cloud_highlight_color : source_color = vec3(1.0, 0.92, 0.82);
uniform vec3 cloud_shadow_color : source_color = vec3(0.62, 0.55, 0.56);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.84;
uniform float cloud_density : hint_range(0.0, 1.5) = 1.0;
uniform float cloud_speed : hint_range(-0.05, 0.05) = 0.0015;
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

	// Procedural floating-diorama atmosphere. The centre stays open around the
	// island while soft cumulus banks grow from the lower corners. No image
	// texture is sampled: layered value noise shapes the broad mass and Worley
	// cells create rounded puffs.
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 radial_uv = SCREEN_UV - vec2(0.58, 0.34);
	radial_uv.x *= aspect * 0.64;
	radial_uv.y *= 1.08;
	float centre_glow = exp(-dot(radial_uv, radial_uv) * 3.1);
	color = mix(
		color,
		centre_glow_color,
		centre_glow * 0.19
	);

	vec2 cloud_p = vec2(
		(SCREEN_UV.x - 0.5) * aspect,
		SCREEN_UV.y
	);
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
	float cloud_field = cloud_bank_field(SCREEN_UV, aspect);
	float upper_field = cloud_bank_field(
		SCREEN_UV + vec2(0.008, 0.025),
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
	float top_lighting = 1.0 - smoothstep(
		0.58,
		1.08,
		SCREEN_UV.y
	);
	float cloud_light = clamp(
		0.08 + top_lighting * 0.78 + cloud_inner * 0.04
		+ puff_light * 0.08 + (lighting_noise - 0.5) * 0.14,
		0.0,
		1.0
	);
	vec3 cloud_color = mix(
		cloud_shadow_color,
		cloud_highlight_color,
		cloud_light
	);
	color = mix(color, cloud_color, cloud_mask);
	float sculpted_upper_light = smoothstep(
		0.025,
		0.26,
		max(upper_field - cloud_field, 0.0)
	) * cloud_mask;
	color = mix(
		color,
		cloud_highlight_color,
		sculpted_upper_light * 0.72
	);
	float silver_lining = (
		cloud_mask * (1.0 - cloud_inner) * top_lighting
	);
	color += (
		cloud_highlight_color * silver_lining * 0.12
	);

	vec2 mote_grid = SCREEN_UV * vec2(38.0, 22.0);
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
