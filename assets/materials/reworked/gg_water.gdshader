shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;
// GG rework water: depth-aware turquoise body derived from the tropical-water
// reference. Three world-space wave bands + scrolling ripple normals,
// exponential depth absorption (shallow reveals the seabed, deep goes nearly
// opaque), true alpha compositing, sparse animated shoreline foam, gentle
// fresnel. World-space everything — no per-tile seams, ever.
//
// IMPORTANT: this must remain genuinely transparent. The previous version
// sampled screen_tex, manually mixed the opaque scene into EMISSION, then drew
// that result on an opaque water mesh. Underwater silhouettes therefore became
// shader-internal color discontinuities that MSAA could not see or smooth.
// Alpha blending leaves those silhouettes in the original antialiased opaque
// pass and composites the water over them without rebuilding their edges.

uniform vec4 shallow_color : source_color = vec4(0.388, 0.757, 0.776, 1.0);   // #63C1C6
uniform vec4 mid_color : source_color = vec4(0.235, 0.671, 0.761, 1.0);       // #3CABC2
uniform vec4 deep_color : source_color = vec4(0.02, 0.416, 0.58, 1.0);        // #056A94
uniform vec4 foam_color : source_color = vec4(0.918, 0.961, 0.945, 1.0);      // #EAF5F1
uniform vec4 sky_color : source_color = vec4(0.906, 0.878, 0.792, 1.0);       // cream env
uniform vec4 caustic_color : source_color = vec4(0.675, 0.808, 0.804, 1.0);
uniform float wave_height = 0.048;
uniform float wave_speed = 1.08;
uniform float surface_shimmer = 0.16;
uniform float depth_falloff = 0.5;      // meters of water for ~63% absorption
uniform float shallow_alpha = 0.8;
uniform float deep_alpha = 0.97;
uniform float foam_width = 0.045;
uniform float water_roughness = 0.42;
uniform float water_specular = 0.18;
// Kept as an art-review control: 1.0 is the shipping, scene-lit response;
// 0.0 reproduces the former self-lit water for controlled comparisons.
uniform float scene_lighting_response : hint_range(0.0, 1.0) = 1.0;
uniform float fresnel_strength = 0.22;
uniform float water_level = -0.14;
// Jello block sides (see the GG reference): pale translucent aqua walls.
uniform vec4 side_top_color : source_color = vec4(0.51, 0.8, 0.81, 1.0);
uniform vec4 side_bottom_color : source_color = vec4(0.275, 0.737, 0.8, 1.0);
uniform float side_opacity = 1.0;
// Placement previews need to preserve the exact animated water silhouette.
// A second static red mesh cannot follow this shader's displaced vertices, so
// held water receives its invalid tint inside the water shader itself.
uniform vec4 placement_invalid_tint : source_color = vec4(1.0, 0.08, 0.045, 1.0);
uniform float placement_invalid_strength : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D depth_tex : hint_depth_texture;

// Fixed-budget, world-space player interaction. Every water chunk shares this
// material, so the same six events cross chunk seams and world size never
// creates more interaction state.
const int INTERACTION_IMPULSE_COUNT = 6;
uniform float interaction_time = 0.0;
uniform vec4 interaction_impulses[INTERACTION_IMPULSE_COUNT];
// xy = surface position, zw = normalized horizontal movement direction.
uniform vec4 interaction_wake = vec4(0.0);
// x = strength, y = trail length, z = body half-width.
uniform vec4 interaction_wake_meta = vec4(0.0);

varying vec3 world_pos;
varying vec3 mesh_normal;
varying float shore_dist;

float wave_h(vec2 p, float t) {
	float h = sin(dot(normalize(vec2(0.8, 0.6)), p) * 2.244 + t * 0.9 * wave_speed) * wave_height;
	h += sin(dot(normalize(vec2(-0.6, 0.8)), p) * 4.833 - t * 1.25 * wave_speed) * wave_height * 0.52;
	h += sin(dot(normalize(vec2(0.26, -0.97)), p) * 7.15 + t * 1.58 * wave_speed) * wave_height * 0.22;
	return h;
}

float interaction_impulse_height(vec2 point) {
	float height = 0.0;
	for (int index = 0; index < INTERACTION_IMPULSE_COUNT; index++) {
		vec4 impulse = interaction_impulses[index];
		float age = interaction_time - impulse.z;
		if (impulse.w <= 0.001 || age < 0.0 || age > 2.2) {
			continue;
		}
		float distance_from_center = distance(point, impulse.xy);
		float front = distance_from_center - age * 1.32;
		float front_envelope = exp(-abs(front) * 8.5);
		float trailing_envelope = exp(-distance_from_center * 1.45)
			* exp(-age * 1.35);
		float leading_crest = sin(front * 12.0) * front_envelope;
		float settling_wave = sin(
			distance_from_center * 15.0 - age * 8.5
		) * trailing_envelope;
		height += (
			leading_crest * 0.075
			+ settling_wave * 0.022
		) * impulse.w * exp(-age * 0.62);
	}
	return height;
}

float interaction_wake_height(vec2 point) {
	float strength = interaction_wake_meta.x;
	if (strength <= 0.001) {
		return 0.0;
	}
	vec2 direction = normalize(interaction_wake.zw + vec2(0.00001, 0.0));
	vec2 side = vec2(-direction.y, direction.x);
	vec2 relative = point - interaction_wake.xy;
	float forward = dot(relative, direction);
	float behind = max(-forward, 0.0);
	float lateral = abs(dot(relative, side));
	float trail = smoothstep(0.02, 0.18, behind)
		* (1.0 - smoothstep(interaction_wake_meta.y * 0.72,
			interaction_wake_meta.y, behind));
	float wing_center = interaction_wake_meta.z + behind * 0.30;
	float wings = (
		1.0 - smoothstep(0.035, 0.15, abs(lateral - wing_center))
	) * trail;
	float body = (
		1.0 - smoothstep(0.12, 0.48, length(relative * vec2(0.72, 1.0)))
	);
	float bow = (
		1.0 - smoothstep(0.04, 0.22, abs(forward - 0.22))
	) * (1.0 - smoothstep(0.08, 0.48, lateral));
	return strength * (
		wings * sin(behind * 13.0) * 0.020
		+ bow * 0.026
		- body * 0.015
	);
}

float interaction_foam(vec2 point) {
	float result = 0.0;
	for (int index = 0; index < INTERACTION_IMPULSE_COUNT; index++) {
		vec4 impulse = interaction_impulses[index];
		float age = interaction_time - impulse.z;
		float life_seconds = mix(
			0.72,
			1.8,
			clamp((impulse.w - 0.08) / 0.92, 0.0, 1.0)
		);
		if (impulse.w <= 0.001 || age < 0.0 || age > life_seconds) {
			continue;
		}
		float phase = age / life_seconds;
		float radius = age * 1.32;
		float ring_distance = abs(distance(point, impulse.xy) - radius);
		float ring = 1.0 - smoothstep(
			mix(0.018, 0.032, phase),
			mix(0.045, 0.085, phase),
			ring_distance
		);
		result += ring * (1.0 - phase) * impulse.w * impulse.w;
	}
	return result;
}

float interaction_wake_foam(vec2 point) {
	float strength = interaction_wake_meta.x;
	if (strength <= 0.001) {
		return 0.0;
	}
	vec2 direction = normalize(interaction_wake.zw + vec2(0.00001, 0.0));
	vec2 side = vec2(-direction.y, direction.x);
	vec2 relative = point - interaction_wake.xy;
	float forward = dot(relative, direction);
	float behind = max(-forward, 0.0);
	float lateral = abs(dot(relative, side));
	float trail = smoothstep(0.03, 0.2, behind)
		* (1.0 - smoothstep(interaction_wake_meta.y * 0.68,
			interaction_wake_meta.y, behind));
	float wing_center = interaction_wake_meta.z + behind * 0.30;
	float wings = (
		1.0 - smoothstep(0.025, 0.105, abs(lateral - wing_center))
	) * trail;
	float bow = (
		1.0 - smoothstep(0.035, 0.14, abs(forward - 0.24))
	) * (1.0 - smoothstep(0.1, 0.42, lateral));
	return (wings * 0.24 + bow * 0.34) * strength;
}

float caustic_layer(vec2 p, float t) {
	float a = sin(p.x + t) + sin(p.y * 1.13 - t * 0.83);
	float b = sin((p.x + p.y) * 0.72 - t * 0.61);
	return pow(clamp(1.0 - abs(a + b * 0.72) * 0.34, 0.0, 1.0), 5.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mesh_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	// <0.5 means the mesh carries no baked shoreline data -> never foam.
	shore_dist = UV2.x < 0.5 ? 999.0 : UV2.x - 1.0;
	// Waves fade out down the skirt so the block bottom stays planted.
	float anchor = clamp(1.0 - (water_level - world_pos.y) * 3.0, 0.0, 1.0);
	float h = (
		wave_h(world_pos.xz, TIME)
		+ interaction_impulse_height(world_pos.xz)
		+ interaction_wake_height(world_pos.xz)
	) * anchor;
	VERTEX.y += h;
	world_pos.y += h;
}

void fragment() {
	float t = TIME;

	// ---- Jello block side faces: continuous aqua wall with a restrained
	// bright lip at the waterline. No depth logic needed.
	if (abs(mesh_normal.y) < 0.5) {
		// A vertical color gradient exposed the individual triangles whenever
		// their wavy top edge changed slope. One calm body color makes adjacent
		// boundary segments read as a single continuous water wall.
		vec3 jello = mix(side_top_color.rgb, side_bottom_color.rgb, 0.38);
		float lip = smoothstep(0.026, 0.0, water_level - world_pos.y);
		vec3 side_col = mix(jello, foam_color.rgb, lip * 0.08);
		side_col = mix(
			side_col,
			placement_invalid_tint.rgb,
			placement_invalid_strength
		);
		ALBEDO = vec3(0.02);
		EMISSION = side_col;
		ALPHA = mix(
			side_opacity,
			max(side_opacity, placement_invalid_tint.a),
			placement_invalid_strength
		);
		ROUGHNESS = 0.34;
		SPECULAR = 0.25;
		METALLIC = 0.0;
	} else {
	// Wave normal from analytic derivatives + two scrolling micro-ripple layers.
	float e = 0.12;
	float hx = wave_h(world_pos.xz + vec2(e, 0.0), t) - wave_h(world_pos.xz - vec2(e, 0.0), t);
	float hz = wave_h(world_pos.xz + vec2(0.0, e), t) - wave_h(world_pos.xz - vec2(0.0, e), t);
	vec2 rip = vec2(
		sin(world_pos.x * 7.3 + world_pos.z * 2.1 + t * 0.7) + sin(world_pos.x * 3.1 - world_pos.z * 5.7 - t * 0.53),
		sin(world_pos.z * 6.7 - world_pos.x * 1.7 - t * 0.61) + sin(world_pos.z * 2.9 + world_pos.x * 4.9 + t * 0.47));
	vec3 n_world = normalize(vec3(-hx / (2.0 * e) - rip.x * 0.018, 1.0, -hz / (2.0 * e) - rip.y * 0.018));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Water depth from the opaque prepass.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float floor_dist = -(vp.z / vp.w);
	float surf_dist = -VERTEX.z;
	// Geometry in front of the surface (a character on the shore) yields a
	// negative difference; treat it as deep so the silhouette cannot flash the
	// bright shallow colour.
	float raw_diff = floor_dist - surf_dist;
	float depth_w = raw_diff <= 0.0 ? depth_falloff * 3.0 : raw_diff;

	// Depth-eased body color (no bands: smooth exponential).
	float dfac = clamp(1.0 - exp(-depth_w / depth_falloff), 0.0, 1.0);
	vec3 body = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.0, 0.5, dfac));
	body = mix(body, deep_color.rgb, smoothstep(0.42, 1.0, dfac));
	float opacity = mix(shallow_alpha, deep_alpha, smoothstep(0.0, 0.85, dfac));

	vec3 col = body;

	// Sparse broken shoreline foam, driven by the BAKED geometric distance to
	// the water region's edge (UV2.x). Deliberately not depth-based: a
	// screen-space depth difference paints a white halo around anything
	// standing in front of, or just under, the surface.
	float foam_noise = sin(world_pos.x * 9.1 + t * 0.9) * sin(world_pos.z * 8.3 - t * 0.7)
		+ sin((world_pos.x + world_pos.z) * 5.7 + t * 0.5);
	float band = foam_width * (0.85 + 0.35 * foam_noise);
	float foam_band = smoothstep(band, band * 0.2, shore_dist);
	// Keep the permanent shoreline almost invisible. Broad noisy white blobs
	// made separate water blocks read like iced tiles; the player-generated
	// contact foam below remains the readable, animated accent.
	float foam = foam_band * clamp(0.12 + 0.16 * foam_noise, 0.0, 0.24);
	float contact_foam = interaction_foam(world_pos.xz)
		+ interaction_wake_foam(world_pos.xz);
	col = mix(
		col,
		foam_color.rgb,
		clamp(foam * 0.16 + contact_foam * 0.075, 0.0, 0.20)
	);

	// Gentle grazing reflection toward the environment tone. Never a mirror.
	float fres = pow(1.0 - clamp(dot(n_world, normalize(-(INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz)), 0.0, 1.0), 5.0);
	col = mix(col, sky_color.rgb, clamp(fres * fresnel_strength, 0.0, 0.3));

	// Water participates in the same daylight as every other surface. The old
	// emission path made it self-lit and disconnected it from ambient/shadow
	// changes; retain scene-lit diffuse color and restrained sun glints.
	float caustic_a = caustic_layer(world_pos.xz * 3.0, t * 0.7);
	float caustic_b = caustic_layer(
		world_pos.xz * 4.7 + vec2(1.7, -2.3),
		-t * 0.46
	);
	float shimmer = caustic_a * caustic_b * surface_shimmer;
	vec3 finished_col = col + caustic_color.rgb * shimmer;
	vec3 display_col = mix(
		finished_col,
		placement_invalid_tint.rgb,
		placement_invalid_strength
	);
	ALBEDO = mix(vec3(0.02), display_col, scene_lighting_response);
	EMISSION = display_col * (1.0 - scene_lighting_response);
	ALPHA = mix(
		opacity,
		max(opacity, placement_invalid_tint.a),
		placement_invalid_strength
	);
	ROUGHNESS = water_roughness;
	SPECULAR = water_specular;
	METALLIC = 0.0;
	}
}
