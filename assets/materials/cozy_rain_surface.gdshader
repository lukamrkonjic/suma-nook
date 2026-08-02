shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

const int FOOTSTEP_COUNT = 4;

uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 wet_color : source_color = vec3(1.0);
uniform vec3 ripple_color : source_color = vec3(1.0);
uniform float wetness : hint_range(0.0, 1.5) = 0.8;
uniform float puddle_amount : hint_range(0.0, 1.5) = 0.72;
uniform float ripple_amount : hint_range(0.0, 1.5) = 0.85;
uniform vec3 coverage_center = vec3(0.0);
uniform float coverage_radius = 38.0;
uniform float effect_time = 0.0;
uniform vec4 footstep_ripples[FOOTSTEP_COUNT];
uniform vec4 wake_from_to = vec4(0.0);
uniform vec2 wake_meta = vec2(0.0);

varying vec3 world_position;


float hash12(vec2 point) {
	vec3 fract_point = fract(vec3(point.xyx) * 0.1031);
	fract_point += dot(fract_point, fract_point.yzx + 33.33);
	return fract((fract_point.x + fract_point.y) * fract_point.z);
}


vec2 hash22(vec2 point) {
	float first = hash12(point);
	float second = hash12(point + vec2(17.17, 43.71));
	return vec2(first, second);
}


float distance_to_segment(vec2 point, vec2 segment_from, vec2 segment_to) {
	vec2 direction = segment_to - segment_from;
	float length_squared = dot(direction, direction);
	float along = 0.0;
	if (length_squared > 0.00001) {
		along = clamp(dot(point - segment_from, direction) / length_squared, 0.0, 1.0);
	}
	return length(point - (segment_from + direction * along));
}


float impact_ripple(vec2 point, float cell_size, float rate, vec2 seed_offset) {
	vec2 grid_position = point / cell_size;
	vec2 cell = floor(grid_position);
	vec2 random_offset = (hash22(cell + seed_offset) - 0.5) * 0.28;
	vec2 local = (fract(grid_position) - 0.5 - random_offset) * cell_size;
	float phase = fract(effect_time * rate + hash12(cell + seed_offset * 2.3));
	float radius = phase * cell_size * 0.29;
	float distance_from_ring = abs(length(local) - radius);
	float width = mix(0.018, 0.055, phase);
	float ring = 1.0 - smoothstep(width, width * 2.4, distance_from_ring);
	float life = smoothstep(0.03, 0.12, phase) * (1.0 - smoothstep(0.62, 0.98, phase));
	return ring * life;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 point = world_position.xz;
	float opaque_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	if (opaque_depth >= 0.99999) {
		discard;
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, opaque_depth);
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position.xyz /= view_position.w;
	vec3 opaque_world_position = (
		INV_VIEW_MATRIX * vec4(view_position.xyz, 1.0)
	).xyz;
	// The overlay belongs only to the ground/water plane immediately beneath
	// it. This removes rings from the empty backdrop and from distant geometry.
	if (abs(opaque_world_position.y - world_position.y) > 0.28) {
		discard;
	}
	float center_distance = distance(point, coverage_center.xz);
	float coverage = 1.0 - smoothstep(
		coverage_radius * 0.84,
		coverage_radius,
		center_distance
	);

	// A mostly calm wet film with irregular world-anchored pooled patches.
	// Mipmapped texture samples keep it stable while the isometric camera
	// scrolls; no screen texture or temporal history is involved.
	float broad = texture(noise_texture, point * 0.014 + vec2(0.17, 0.41)).r;
	float detail = texture(noise_texture, point * 0.041 + vec2(0.63, 0.09)).r;
	float pool_field = broad * 0.76 + detail * 0.24;
	float pools = smoothstep(0.48, 0.69, pool_field) * puddle_amount;
	float shallow_flow = (
		sin(dot(point, vec2(0.73, 0.41)) * 2.1 + effect_time * 0.42)
		* 0.5 + 0.5
	) * pools;

	// Two sparse deterministic impact fields. Every visible ripple is derived
	// from its world cell and time, so there are no per-tile or per-drop nodes.
	float impacts = impact_ripple(point, 2.35, 0.61, vec2(3.0, 7.0));
	impacts += impact_ripple(point, 3.65, 0.43, vec2(19.0, 2.0)) * 0.62;
	impacts *= ripple_amount * mix(0.34, 1.0, pools);

	float foot_rings = 0.0;
	for (int index = 0; index < FOOTSTEP_COUNT; index++) {
		vec4 footstep = footstep_ripples[index];
		float age = effect_time - footstep.z;
		if (footstep.w <= 0.001 || age < 0.0 || age > 1.05) {
			continue;
		}
		float phase = age / 1.05;
		float radius = phase * 0.72;
		float ring_distance = abs(distance(point, footstep.xy) - radius);
		float ring = 1.0 - smoothstep(0.025, 0.075, ring_distance);
		foot_rings += ring * (1.0 - phase) * footstep.w;
	}

	float wake = 0.0;
	if (wake_meta.y > 0.001) {
		float wake_distance = distance_to_segment(
			point,
			wake_from_to.xy,
			wake_from_to.zw
		);
		wake = (
			1.0 - smoothstep(wake_meta.x * 0.35, wake_meta.x, wake_distance)
		) * wake_meta.y;
	}

	float view_fresnel = pow(
		1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0),
		2.0
	);
	float film_alpha = wetness * (0.008 + pools * 0.12 + shallow_flow * 0.02);
	float highlight = impacts * 0.50 + foot_rings * 0.78 + wake * 0.16;
	vec3 reflected_tint = mix(wet_color, ripple_color, clamp(
		view_fresnel * 0.34 + highlight,
		0.0,
		1.0
	));
	ALBEDO = reflected_tint;
	ALPHA = clamp(
		(film_alpha + highlight * 0.16) * coverage,
		0.0,
		0.27
	);
}
