shader_type spatial;
// Responsive diorama terrain for the two genuinely soft surfaces. The
// material keeps the painted GG-style vertical ramp, then adds a fixed-budget
// world-space footprint field. Every sand or snow tile shares these uniforms:
// cost is bounded by visible vertices, never by island size or tile count.

const int TERRAIN_IMPRINT_COUNT = 12;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float specular_val : hint_range(0.0, 1.0) = 0.18;
uniform float ramp_height = 1.35;
uniform float ramp_top_lift = 0.10;
uniform float ramp_bottom_drop = 0.16;
uniform vec3 ramp_top_tint = vec3(1.02, 1.0, 0.965);
uniform vec3 ramp_bottom_tint = vec3(0.985, 0.99, 1.02);
uniform float mottle_amount = 0.035;
uniform float mottle_scale = 1.2;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rim_tint_amount : hint_range(0.0, 1.0) = 0.6;

// x/y store world X/Z, z stores birth time, and w stores strength.
uniform vec4 terrain_imprints[TERRAIN_IMPRINT_COUNT];
// x/z hold the sole direction. The remaining components are reserved so the
// runtime can keep one compact Vector4 array per field.
uniform vec4 terrain_directions[TERRAIN_IMPRINT_COUNT];
uniform float terrain_time = 0.0;
uniform float terrain_lifetime = 10.0;
uniform float terrain_depth = 0.055;
uniform float terrain_radius = 0.23;
uniform float terrain_rim_height = 0.01;
uniform float terrain_floor_height = 0.004;
uniform vec4 terrain_compressed_tint : source_color = vec4(0.72, 0.68, 0.6, 1.0);
uniform vec4 terrain_rim_tint : source_color = vec4(1.0, 0.98, 0.9, 1.0);

varying float object_height;
varying vec3 world_pos;

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(cell + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(cell + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(cell + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 footprint_shape(
	vec2 point,
	vec4 imprint,
	vec4 direction_data
) {
	vec2 direction = direction_data.xz;
	if (dot(direction, direction) < 0.001) {
		direction = vec2(0.0, -1.0);
	} else {
		direction = normalize(direction);
	}
	vec2 side = vec2(-direction.y, direction.x);
	vec2 delta = point - imprint.xy;
	// A readable stylized sole: longer along the facing direction and narrow
	// across it. This avoids the circular "crater" look.
	return vec2(
		dot(delta, side) / max(terrain_radius * 0.52, 0.001),
		dot(delta, direction) / max(terrain_radius, 0.001)
	);
}

float imprint_fade(vec4 imprint) {
	float age = max(terrain_time - imprint.z, 0.0);
	float life = 1.0 - smoothstep(
		terrain_lifetime * 0.72,
		terrain_lifetime,
		age
	);
	return life * clamp(imprint.w, 0.0, 1.5);
}

void vertex() {
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float original_object_height = original_world.y - MODEL_MATRIX[3].y;
	float depression = 0.0;
	float raised_rim = 0.0;
	for (int index = 0; index < TERRAIN_IMPRINT_COUNT; index++) {
		vec4 imprint = terrain_imprints[index];
		float strength = imprint_fade(imprint);
		if (strength <= 0.001) {
			continue;
		}
		float distance_to_sole = length(
			footprint_shape(original_world.xz, imprint, terrain_directions[index])
		);
		float core = 1.0 - smoothstep(0.25, 0.98, distance_to_sole);
		float rim = smoothstep(0.78, 1.02, distance_to_sole)
			* (1.0 - smoothstep(1.02, 1.34, distance_to_sole));
		depression = max(depression, core * strength);
		raised_rim = max(raised_rim, rim * strength);
	}
	// Side walls keep their authored silhouette. Up-facing relief compresses,
	// with a restrained displaced lip where material has been pushed aside.
	float top_facing = smoothstep(0.42, 0.82, NORMAL.y);
	// The removable relief overlaps a structural cap at y=0. Only vertices
	// that actually belong to the raised blanket/dune may move, and they can
	// never cross through that cap and expose a dark crack.
	float raised_surface = smoothstep(
		0.002,
		0.018,
		original_object_height
	);
	float world_displacement = (
		-depression * terrain_depth
		+ raised_rim * terrain_rim_height
	) * top_facing * raised_surface;
	if (raised_surface > 0.001) {
		world_displacement = max(
			world_displacement,
			terrain_floor_height - original_object_height
		);
	}
	float model_y_scale = max(length(MODEL_MATRIX[1].xyz), 0.001);
	VERTEX.y += world_displacement / model_y_scale;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	object_height = world_pos.y - MODEL_MATRIX[3].y;
}

void fragment() {
	float compressed = 0.0;
	float displaced_rim = 0.0;
	for (int index = 0; index < TERRAIN_IMPRINT_COUNT; index++) {
		vec4 imprint = terrain_imprints[index];
		float strength = imprint_fade(imprint);
		if (strength <= 0.001) {
			continue;
		}
		float distance_to_sole = length(
			footprint_shape(world_pos.xz, imprint, terrain_directions[index])
		);
		float core = 1.0 - smoothstep(0.22, 0.98, distance_to_sole);
		float rim = smoothstep(0.78, 1.02, distance_to_sole)
			* (1.0 - smoothstep(1.02, 1.34, distance_to_sole));
		compressed = max(compressed, core * strength);
		displaced_rim = max(displaced_rim, rim * strength);
	}

	float t = smoothstep(
		0.0,
		1.0,
		clamp(object_height / max(ramp_height, 0.001), 0.0, 1.0)
	);
	float value_shift = mix(-ramp_bottom_drop, ramp_top_lift, t);
	vec3 tint = mix(ramp_bottom_tint, ramp_top_tint, t);
	float grain = value_noise(world_pos.xz * mottle_scale)
		+ 0.5 * value_noise(world_pos.xz * mottle_scale * 2.7);
	value_shift += (grain / 1.5 - 0.5) * 2.0 * mottle_amount;
	vec3 painted = clamp(
		albedo.rgb * tint * (1.0 + value_shift),
		vec3(0.0),
		vec3(1.0)
	);
	painted = mix(
		painted,
		terrain_compressed_tint.rgb,
		clamp(compressed, 0.0, 1.0) * 0.46
	);
	painted = mix(
		painted,
		terrain_rim_tint.rgb,
		clamp(displaced_rim, 0.0, 1.0) * 0.26
	);
	ALBEDO = painted;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
	SPECULAR = specular_val;
	RIM = rim_amount;
	RIM_TINT = rim_tint_amount;
}
