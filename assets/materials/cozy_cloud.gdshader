shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

uniform sampler3D cloud_noise : repeat_enable, filter_linear;
uniform float visibility_fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_direction = vec3(-0.42, 0.82, -0.39);
uniform vec3 crown_color : source_color = vec3(1.0, 0.995, 0.98);
uniform vec3 shade_color : source_color = vec3(0.60, 0.68, 0.78);
uniform float mist_opacity : hint_range(0.0, 1.0) = 0.70;

varying vec3 local_surface;
varying flat vec3 local_camera;
varying flat vec3 local_sun;
varying flat vec3 cloud_seed;


vec3 mirror_tile(vec3 coordinate) {
	return abs(fract(coordinate * 0.5) * 2.0 - 1.0);
}


float ellipsoid_distance(
	vec3 position,
	vec3 center,
	vec3 radius
) {
	vec3 normalized_position = (position - center) / radius;
	return (
		(length(normalized_position) - 1.0)
		* min(min(radius.x, radius.y), radius.z)
	);
}


float smooth_union(float first, float second, float softness) {
	float blend = clamp(
		0.5 + 0.5 * (second - first) / softness,
		0.0,
		1.0
	);
	return mix(second, first, blend) - softness * blend * (1.0 - blend);
}


float cumulus_distance(vec3 position) {
	vec3 variation = cloud_seed * 2.0 - 1.0;
	float shape = ellipsoid_distance(
		position,
		vec3(variation.r * 0.025, -0.16, variation.b * 0.018),
		vec3(
			mix(0.39, 0.45, cloud_seed.r),
			mix(0.17, 0.21, cloud_seed.g),
			mix(0.28, 0.35, cloud_seed.b)
		)
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				-0.285 + variation.g * 0.025,
				-0.055 + cloud_seed.r * 0.035,
				variation.b * 0.045
			),
			vec3(
				mix(0.17, 0.235, cloud_seed.b),
				mix(0.17, 0.25, cloud_seed.r),
				mix(0.18, 0.235, cloud_seed.g)
			)
		),
		0.045
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				-0.13 + variation.r * 0.055,
				0.045 + cloud_seed.g * 0.085,
				0.035 + variation.b * 0.045
			),
			vec3(
				mix(0.205, 0.285, cloud_seed.r),
				mix(0.225, 0.325, cloud_seed.g),
				mix(0.195, 0.265, cloud_seed.b)
			)
		),
		0.052
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				0.085 + variation.r * 0.075,
				0.075 + cloud_seed.r * 0.095,
				-0.055 + variation.b * 0.055
			),
			vec3(
				mix(0.225, 0.295, cloud_seed.g),
				mix(0.255, 0.355, cloud_seed.r),
				mix(0.21, 0.285, cloud_seed.b)
			)
		),
		0.055
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				0.305 + variation.g * 0.025,
				-0.065 + cloud_seed.b * 0.055,
				0.02 + variation.r * 0.04
			),
			vec3(
				mix(0.145, 0.215, cloud_seed.r),
				mix(0.155, 0.235, cloud_seed.b),
				mix(0.16, 0.225, cloud_seed.g)
			)
		),
		0.040
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				-0.09 + variation.g * 0.08,
				-0.005 + cloud_seed.r * 0.065,
				-0.205 + variation.b * 0.03
			),
			vec3(
				mix(0.175, 0.24, cloud_seed.b),
				mix(0.17, 0.245, cloud_seed.g),
				mix(0.15, 0.205, cloud_seed.r)
			)
		),
		0.042
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				0.12 + variation.r * 0.075,
				0.055 + cloud_seed.b * 0.11,
				0.175 + variation.g * 0.035
			),
			vec3(
				mix(0.17, 0.24, cloud_seed.g),
				mix(0.19, 0.29, cloud_seed.b),
				mix(0.145, 0.21, cloud_seed.r)
			)
		),
		0.044
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				mix(-0.22, 0.21, cloud_seed.b),
				0.225 + cloud_seed.r * 0.075,
				-0.01 + variation.g * 0.095
			),
			vec3(
				mix(0.12, 0.185, cloud_seed.r),
				mix(0.145, 0.205, cloud_seed.g),
				mix(0.12, 0.18, cloud_seed.b)
			)
		),
		0.032
	);
	shape = smooth_union(
		shape,
		ellipsoid_distance(
			position,
			vec3(
				mix(0.235, -0.19, cloud_seed.r),
				0.125 + cloud_seed.b * 0.085,
				mix(-0.16, 0.15, cloud_seed.g)
			),
			vec3(
				mix(0.115, 0.17, cloud_seed.b),
				mix(0.13, 0.195, cloud_seed.r),
				mix(0.115, 0.175, cloud_seed.g)
			)
		),
		0.030
	);
	return shape;
}


float cloud_density(vec3 position) {
	float distance_to_cloud = cumulus_distance(position);
	vec3 noise_coordinate = (
		position * vec3(2.15, 2.45, 2.15)
		+ cloud_seed * vec3(4.7, 3.1, 5.3)
	);
	float broad_noise = texture(
		cloud_noise,
		mirror_tile(noise_coordinate)
	).r;
	float fine_noise = texture(
		cloud_noise,
		mirror_tile(
			noise_coordinate * 2.35 + vec3(0.37, 0.61, 0.19)
		)
	).r;
	float erosion = (
		(broad_noise - 0.5) * 0.050
		+ (fine_noise - 0.5) * 0.008
	);
	float flat_base = smoothstep(-0.39, -0.29, position.y);
	return (
		(1.0 - smoothstep(-0.018, 0.030, distance_to_cloud + erosion))
		* flat_base
	);
}


vec2 intersect_unit_box(vec3 ray_origin, vec3 ray_direction) {
	vec3 reciprocal = 1.0 / ray_direction;
	vec3 first = (vec3(-0.5) - ray_origin) * reciprocal;
	vec3 second = (vec3(0.5) - ray_origin) * reciprocal;
	vec3 near_axis = min(first, second);
	vec3 far_axis = max(first, second);
	float near_distance = max(
		max(near_axis.x, near_axis.y),
		near_axis.z
	);
	float far_distance = min(
		min(far_axis.x, far_axis.y),
		far_axis.z
	);
	return vec2(max(near_distance, 0.0), far_distance);
}


float stable_jitter(vec2 pixel) {
	return fract(
		52.9829189
		* fract(dot(pixel, vec2(0.06711056, 0.00583715)))
	);
}


void vertex() {
	local_surface = VERTEX;
	mat4 inverse_model = inverse(MODEL_MATRIX);
	local_camera = (
		inverse_model * vec4(CAMERA_POSITION_WORLD, 1.0)
	).xyz;
	local_sun = normalize(
		(inverse_model * vec4(normalize(sun_direction), 0.0)).xyz
	);
	cloud_seed = INSTANCE_CUSTOM.rgb;
}


void fragment() {
	vec3 ray_direction = normalize(local_surface - local_camera);
	vec2 hit = intersect_unit_box(local_camera, ray_direction);
	if (hit.y <= hit.x || visibility_fade <= 0.001) {
		discard;
	}

	const int VIEW_STEPS = 18;
	float ray_length = hit.y - hit.x;
	float step_length = ray_length / float(VIEW_STEPS);
	float distance_along_ray = (
		hit.x
		+ mix(0.38, 0.62, stable_jitter(FRAGCOORD.xy)) * step_length
	);
	float transmittance = 1.0;
	vec3 accumulated_light = vec3(0.0);

	for (int index = 0; index < VIEW_STEPS; index++) {
		vec3 sample_position = (
			local_camera + ray_direction * distance_along_ray
		);
		float density = cloud_density(sample_position);
		if (density > 0.003) {
			float toward_sun = (
				cloud_density(sample_position + local_sun * 0.055)
				+ cloud_density(sample_position + local_sun * 0.14) * 0.72
			);
			float sunlight = exp(-toward_sun * 1.55);
			float height_light = clamp(
				sample_position.y + 0.42,
				0.0,
				1.0
			);
			float edge_glow = 1.0 - smoothstep(0.10, 0.78, density);
			float light_amount = clamp(
				0.22
				+ sunlight * 0.62
				+ height_light * 0.15
				+ edge_glow * sunlight * 0.18,
				0.0,
				1.0
			);
			vec3 sample_color = mix(
				shade_color,
				crown_color,
				light_amount
			);
			float sample_alpha = (
				1.0 - exp(-density * step_length * 3.0)
			);
			accumulated_light += (
				transmittance * sample_alpha * sample_color
			);
			transmittance *= 1.0 - sample_alpha;
			if (transmittance < 0.025) {
				break;
			}
		}
		distance_along_ray += step_length;
	}

	float alpha = (
		(1.0 - transmittance)
		* visibility_fade
		* mist_opacity
	);
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = accumulated_light / max(1.0 - transmittance, 0.001);
	ALPHA = alpha;
}
