shader_type spatial;
render_mode cull_front, unshaded;

const int MAX_SHAPES = 16;
const int PROJECTION_STEPS = 3;

uniform int shape_count : hint_range(1, 16) = 1;
uniform vec4 shape_a[MAX_SHAPES];
uniform vec4 shape_b[MAX_SHAPES];
uniform vec4 shape_neighbors_a[MAX_SHAPES];
uniform vec4 shape_neighbors_b[MAX_SHAPES];
uniform float outline_width : hint_range(0.0, 0.025) = 0.007;
uniform vec4 outline_color : source_color = vec4(0.12, 0.09, 0.16, 1.0);


vec3 safe_normalize(vec3 value, vec3 fallback) {
	float length_squared = dot(value, value);
	if (length_squared > 0.0000001) {
		return value * inversesqrt(length_squared);
	}
	return fallback;
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
	vec4 sample_value = capsule_sample(point, source_index);
	for (int slot = 0; slot < 8; slot++) {
		int next_index = neighbor_index(source_index, slot);
		if (next_index < 0 || next_index >= shape_count) {
			continue;
		}
		vec4 next_sample = capsule_sample(point, next_index);
		float blend_radius = max(shape_b[next_index].w, 0.0001);
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
	vec3 centerline = mix(endpoint_a, endpoint_b, axial_seed * 0.5 + 0.5);
	return centerline + radius * (
		tangent * radial_seed.x
		+ axis_direction * radial_seed.y
		+ bitangent * radial_seed.z
	);
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
	VERTEX = projected + normal_value * outline_width;
	NORMAL = normal_value;
}


void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
