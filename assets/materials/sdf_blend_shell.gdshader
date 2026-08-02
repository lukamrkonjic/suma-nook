shader_type spatial;
// Ambient is disabled so the shadow side is a flat fill (EMISSION below)
// instead of a soft gradient — parts read as solid painted colors.
render_mode diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

// Fixed-size arrays keep this shader mobile-friendly and make the per-character
// cost predictable. The current mascot uses fifteen of the sixteen slots.
const int MAX_SHAPES = 16;
const int PROJECTION_STEPS = 5;

uniform int shape_count : hint_range(1, 16) = 1;
uniform vec4 shape_a[MAX_SHAPES]; // endpoint A.xyz, radius
uniform vec4 shape_b[MAX_SHAPES]; // endpoint B.xyz, blend radius
uniform vec4 shape_color[MAX_SHAPES];
uniform vec4 shape_neighbors_a[MAX_SHAPES];
uniform vec4 shape_neighbors_b[MAX_SHAPES];

varying vec3 blended_color;


vec3 safe_normalize(vec3 value, vec3 fallback) {
	float length_squared = dot(value, value);
	if (length_squared > 0.0000001) {
		return value * inversesqrt(length_squared);
	}
	return fallback;
}


float capsule_distance(vec3 point, vec3 endpoint_a, vec3 endpoint_b, float radius) {
	vec3 segment = endpoint_b - endpoint_a;
	float segment_length_squared = dot(segment, segment);
	if (segment_length_squared < 0.0000001) {
		return length(point - endpoint_a) - radius;
	}
	float along = clamp(
		dot(point - endpoint_a, segment) / segment_length_squared,
		0.0,
		1.0
	);
	return length(point - (endpoint_a + segment * along)) - radius;
}


float shape_distance(vec3 point, int shape_index) {
	return capsule_distance(
		point,
		shape_a[shape_index].xyz,
		shape_b[shape_index].xyz,
		shape_a[shape_index].w
	);
}


vec4 capsule_sample(vec3 point, int shape_index) {
	vec3 endpoint_a = shape_a[shape_index].xyz;
	vec3 endpoint_b = shape_b[shape_index].xyz;
	vec3 segment = endpoint_b - endpoint_a;
	float segment_length_squared = dot(segment, segment);
	float along = 0.0;
	if (segment_length_squared >= 0.0000001) {
		along = clamp(
			dot(point - endpoint_a, segment) / segment_length_squared,
			0.0,
			1.0
		);
	}
	vec3 offset = point - (endpoint_a + segment * along);
	float offset_length = max(length(offset), 0.00001);
	return vec4(
		offset / offset_length,
		offset_length - shape_a[shape_index].w
	);
}


int neighbor_index(int source_index, int slot) {
	float encoded = -1.0;
	if (slot < 4) {
		encoded = shape_neighbors_a[source_index][slot];
	} else {
		encoded = shape_neighbors_b[source_index][slot - 4];
	}
	return int(encoded);
}


vec4 shell_sample(vec3 point, int source_index) {
	// Every seed evaluates the shapes in exactly the same order. This is what
	// makes overlapping capsules converge onto one identical surface instead of
	// leaving a faint ring where two independently evaluated shells meet.
	vec4 sample_value = capsule_sample(point, 0);
	for (int next_index = 1; next_index < MAX_SHAPES; next_index++) {
		if (next_index >= shape_count) {
			break;
		}
		vec4 next_sample = capsule_sample(point, next_index);
		float blend_radius = max(
			min(shape_b[next_index].w, shape_b[next_index - 1].w),
			0.0001
		);
		float weight = clamp(
			0.5 + 0.5 * (next_sample.w - sample_value.w) / blend_radius,
			0.0,
			1.0
		);
		sample_value.xyz = safe_normalize(
		mix(next_sample.xyz, sample_value.xyz, weight),
		sample_value.xyz
	);
		sample_value.w = (
			mix(next_sample.w, sample_value.w, weight)
			- blend_radius * weight * (1.0 - weight)
		);
	}
	return sample_value;
}


vec3 shell_color(vec3 point, int source_index) {
	float distance_value = shape_distance(point, 0);
	vec3 color_value = shape_color[0].rgb;
	for (int next_index = 1; next_index < MAX_SHAPES; next_index++) {
		if (next_index >= shape_count) {
			break;
		}
		float next_distance = shape_distance(point, next_index);
		// Colors cross over inside a much narrower band than the geometry
		// blend, so every part reads as one solid fill with a crisp edge.
		float blend_radius = max(
			min(shape_b[next_index].w, shape_b[next_index - 1].w) * 0.35,
			0.0001
		);
		float weight = clamp(
			0.5 + 0.5 * (next_distance - distance_value) / blend_radius,
			0.0,
			1.0
		);
		color_value = mix(shape_color[next_index].rgb, color_value, weight);
		distance_value = (
			mix(next_distance, distance_value, weight)
			- blend_radius * weight * (1.0 - weight)
		);
	}
	return color_value;
}


vec3 capsule_seed_position(vec3 seed, int source_index) {
	vec3 endpoint_a = shape_a[source_index].xyz;
	vec3 endpoint_b = shape_b[source_index].xyz;
	float radius = shape_a[source_index].w;
	vec3 axis = endpoint_b - endpoint_a;
	float axis_length = length(axis);
	if (axis_length < 0.0001) {
		return endpoint_a + safe_normalize(seed, vec3(0.0, 1.0, 0.0)) * radius;
	}

	vec3 axis_direction = axis / axis_length;
	vec3 helper = (
		abs(axis_direction.y) < 0.92
		? vec3(0.0, 1.0, 0.0)
		: vec3(1.0, 0.0, 0.0)
	);
	vec3 tangent = safe_normalize(cross(helper, axis_direction), vec3(1.0, 0.0, 0.0));
	vec3 bitangent = safe_normalize(cross(axis_direction, tangent), vec3(0.0, 0.0, 1.0));
	float axial_seed = clamp(seed.y, -1.0, 1.0);
	vec3 radial_seed = vec3(seed.x, seed.y - axial_seed, seed.z);
	vec3 centerline = mix(
		endpoint_a,
		endpoint_b,
		axial_seed * 0.5 + 0.5
	);
	return centerline + radius * (
		tangent * radial_seed.x
		+ axis_direction * radial_seed.y
		+ bitangent * radial_seed.z
	);
}


float min_shape_distance(vec3 point) {
	float result = shape_distance(point, 0);
	for (int next_index = 1; next_index < MAX_SHAPES; next_index++) {
		if (next_index >= shape_count) {
			break;
		}
		result = min(result, shape_distance(point, next_index));
	}
	return result;
}


void vertex() {
	int source_index = clamp(int(UV2.x + 0.5), 0, MAX_SHAPES - 1);
	vec3 projected = capsule_seed_position(VERTEX, source_index);
	vec3 normal_value = vec3(0.0, 1.0, 0.0);

	for (int projection_step = 0; projection_step < PROJECTION_STEPS; projection_step++) {
		vec4 sample_value = shell_sample(projected, source_index);
		normal_value = sample_value.xyz;
		projected -= normal_value * clamp(sample_value.w, -0.045, 0.045);
	}

	normal_value = shell_sample(projected, source_index).xyz;

	// Every overlap region is covered by the charts of all shapes that blend
	// there, which z-fights as faint creases. Charts whose own shape is not
	// the closest surface owner tuck themselves slightly under the skin, so
	// exactly one chart renders the visible surface.
	// The wide ramp keeps the sink wall so gentle that it never reads as a
	// ledge or catches the ink rim.
	float own_distance = shape_distance(projected, source_index);
	float owner_distance = min_shape_distance(projected);
	float buried = clamp((own_distance - owner_distance - 0.002) / 0.012, 0.0, 1.0);
	projected -= normal_value * buried * 0.005;

	VERTEX = projected;
	NORMAL = normal_value;
	blended_color = shell_color(projected, source_index);
}


void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float ink_rim = smoothstep(0.11, 0.015, facing);
	ALBEDO = mix(blended_color, blended_color * 0.66, ink_rim * 0.28);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	// Uniform fill in place of ambient: the unlit side is one flat tone.
	EMISSION = ALBEDO * 0.34;
}


void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0);
	float toon_band = 0.30 * smoothstep(0.10, 0.18, diffuse);
	toon_band += 0.42 * smoothstep(0.52, 0.60, diffuse);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * toon_band;
}
