shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

const int SWEEP_COUNT = 6;
const int LIGHT_COUNT = 4;

uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 mist_color : source_color = vec3(0.88, 0.87, 0.81);
uniform float mist_density : hint_range(0.0, 2.0) = 0.68;
uniform float noise_scale : hint_range(0.02, 0.35) = 0.095;
uniform vec2 wind = vec2(0.025, -0.018);
uniform vec3 coverage_center = vec3(0.0);
uniform float coverage_radius = 38.0;
uniform float layer_phase = 0.0;
uniform float layer_opacity = 0.12;
uniform float layer_scale = 1.0;
uniform vec4 sweep_from_to[SWEEP_COUNT];
uniform vec4 sweep_meta[SWEEP_COUNT];
uniform vec4 light_position_radius[LIGHT_COUNT];
uniform vec4 light_color_energy[LIGHT_COUNT];

varying vec3 world_position;


float distance_to_segment(vec2 point, vec2 segment_from, vec2 segment_to) {
	vec2 direction = segment_to - segment_from;
	float length_squared = dot(direction, direction);
	float along = 0.0;
	if (length_squared > 0.00001) {
		along = clamp(dot(point - segment_from, direction) / length_squared, 0.0, 1.0);
	}
	return length(point - (segment_from + direction * along));
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Both texture coordinates and motion are defined in world units. Camera
	// movement therefore changes only which texels are visible; it never
	// rebuilds, reprojects, or slides the mist field.
	vec2 base_uv = world_position.xz * noise_scale * 0.16;
	vec2 drift = wind * TIME * 0.35;
	vec2 phase_offset = vec2(layer_phase * 0.071, layer_phase * -0.053);
	vec2 curl = vec2(
		sin(world_position.z * 0.067 + TIME * 0.11 + layer_phase),
		cos(world_position.x * 0.059 - TIME * 0.09 - layer_phase)
	) * 0.018;
	float broad = texture(
		noise_texture,
		(base_uv + curl) * layer_scale + drift + phase_offset
	).r;
	float crossing = texture(
		noise_texture,
		base_uv * (layer_scale * 2.37) - drift * 0.43
			+ phase_offset.yx * 1.71
	).r;
	float fine = texture(
		noise_texture,
		base_uv * (layer_scale * 4.31) + drift.yx * vec2(-0.24, 0.19)
			- phase_offset * 0.67
	).r;
	float field = broad * 0.61 + crossing * 0.29 + fine * 0.10;
	float wisps = smoothstep(0.46, 0.64, field);
	float ribbons = smoothstep(0.53, 0.70, broad + (crossing - 0.5) * 0.25);
	float shape = pow(
		clamp(wisps * 0.76 + ribbons * 0.24, 0.0, 1.0),
		1.25
	);

	float center_distance = distance(world_position.xz, coverage_center.xz);
	float coverage = 1.0 - smoothstep(
		coverage_radius * 0.82,
		coverage_radius,
		center_distance
	);

	float clearing = 0.0;
	float pushed_rim = 0.0;
	for (int index = 0; index < SWEEP_COUNT; index++) {
		float radius = sweep_meta[index].x;
		float strength = sweep_meta[index].y;
		if (radius <= 0.001 || strength <= 0.001) {
			continue;
		}
		vec4 segment = sweep_from_to[index];
		float segment_distance = distance_to_segment(
			world_position.xz,
			segment.xy,
			segment.zw
		);
		float local_clear = (
			1.0 - smoothstep(radius * 0.42, radius, segment_distance)
		) * strength;
		clearing = max(clearing, local_clear);
		float rim = smoothstep(
			radius * 0.72,
			radius,
			segment_distance
		) * (
			1.0 - smoothstep(radius, radius * 1.52, segment_distance)
		);
		pushed_rim = max(pushed_rim, rim * strength);
	}

	vec3 warm_scatter = vec3(0.0);
	float illuminated_density = 0.0;
	for (int light_index = 0; light_index < LIGHT_COUNT; light_index++) {
		vec4 light_data = light_position_radius[light_index];
		float radius = light_data.w;
		if (radius <= 0.001) {
			continue;
		}
		float light_distance = distance(world_position.xz, light_data.xy);
		float attenuation = 1.0 - smoothstep(radius * 0.18, radius, light_distance);
		vec4 color_energy = light_color_energy[light_index];
		float scatter = attenuation * color_energy.a;
		warm_scatter += color_energy.rgb * scatter;
		illuminated_density += scatter;
	}

	float base_density = mix(0.012, 1.0, shape);
	float alpha = mist_density * layer_opacity * base_density;
	alpha *= coverage;
	alpha *= 1.0 - clearing * 0.72;
	alpha += pushed_rim * mist_density * layer_opacity * 0.20 * coverage;
	alpha += illuminated_density * layer_opacity * 0.035 * coverage;

	// The fixed four-light analytic budget gives lamps and fires a warm halo
	// without enrolling a screen-sized transparent mesh in clustered lighting.
	vec3 final_color = mist_color + warm_scatter * 0.38;
	ALBEDO = min(final_color, vec3(1.65));
	ALPHA = clamp(alpha, 0.0, 0.24);
}
