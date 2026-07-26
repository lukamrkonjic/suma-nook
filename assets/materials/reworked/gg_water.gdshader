shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;
// GG rework water: depth-aware turquoise body derived from the tropical-water
// reference. Two low-amplitude Gerstner-style waves + scrolling ripple normals,
// exponential depth absorption (shallow reveals the seabed, deep goes nearly
// opaque), restrained screen-space refraction, sparse animated shoreline foam,
// gentle fresnel. World-space everything — no per-tile seams, ever.

uniform vec4 shallow_color : source_color = vec4(0.388, 0.757, 0.776, 1.0);   // #63C1C6
uniform vec4 mid_color : source_color = vec4(0.235, 0.671, 0.761, 1.0);       // #3CABC2
uniform vec4 deep_color : source_color = vec4(0.02, 0.416, 0.58, 1.0);        // #056A94
uniform vec4 foam_color : source_color = vec4(0.918, 0.961, 0.945, 1.0);      // #EAF5F1
uniform vec4 sky_color : source_color = vec4(0.906, 0.878, 0.792, 1.0);       // cream env
uniform float wave_height = 0.032;
uniform float depth_falloff = 0.5;      // meters of water for ~63% absorption
uniform float shallow_alpha = 0.8;
uniform float deep_alpha = 0.97;
uniform float refraction_strength = 0.012;
uniform float foam_width = 0.13;
uniform float water_roughness = 0.24;
uniform float water_specular = 0.32;
uniform float fresnel_strength = 0.22;
uniform float water_level = -0.14;
// Jello block sides (see the GG reference): pale translucent aqua walls.
uniform vec4 side_top_color : source_color = vec4(0.51, 0.8, 0.81, 1.0);
uniform vec4 side_bottom_color : source_color = vec4(0.275, 0.737, 0.8, 1.0);
uniform float side_opacity = 0.88;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture;

varying vec3 world_pos;
varying vec3 mesh_normal;
varying float shore_dist;

float wave_h(vec2 p, float t) {
	float h = sin(dot(normalize(vec2(0.8, 0.6)), p) * 2.244 + t * 0.9) * wave_height;
	h += sin(dot(normalize(vec2(-0.6, 0.8)), p) * 4.833 - t * 1.25) * wave_height * 0.5;
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mesh_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	// <0.5 means the mesh carries no baked shoreline data -> never foam.
	shore_dist = UV2.x < 0.5 ? 999.0 : UV2.x - 1.0;
	// Waves fade out down the skirt so the block bottom stays planted.
	float anchor = clamp(1.0 - (water_level - world_pos.y) * 3.0, 0.0, 1.0);
	float h = wave_h(world_pos.xz, TIME) * anchor;
	VERTEX.y += h;
	world_pos.y += h;
}

void fragment() {
	float t = TIME;

	// ---- Jello block side faces: translucent aqua wall, subtle vertical
	// gradient, thin bright lip at the waterline. No depth logic needed.
	if (abs(mesh_normal.y) < 0.5) {
		float down01 = clamp((water_level - world_pos.y) / 0.45, 0.0, 1.0);
		vec3 jello = mix(side_top_color.rgb, side_bottom_color.rgb, down01);
		vec3 wall_bg = texture(screen_tex, SCREEN_UV).rgb;
		vec3 side_col = mix(wall_bg, jello, side_opacity);
		float lip = smoothstep(0.05, 0.0, water_level - world_pos.y);
		side_col = mix(side_col, foam_color.rgb, lip * 0.35);
		ALBEDO = vec3(0.02);
		EMISSION = side_col;
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

	// Restrained refraction of the scene beneath.
	vec2 refr_uv = SCREEN_UV + n_world.xz * refraction_strength;
	float refr_raw = texture(depth_tex, refr_uv).r;
	vec4 rvp = INV_PROJECTION_MATRIX * vec4(refr_uv * 2.0 - 1.0, refr_raw, 1.0);
	if (-(rvp.z / rvp.w) < surf_dist) {
		refr_uv = SCREEN_UV;  // don't pull foreground objects underwater
	}
	vec3 under = texture(screen_tex, refr_uv).rgb;
	vec3 col = mix(under, body, opacity);

	// Sparse broken shoreline foam, driven by the BAKED geometric distance to
	// the water region's edge (UV2.x). Deliberately not depth-based: a
	// screen-space depth difference paints a white halo around anything
	// standing in front of, or just under, the surface.
	float foam_noise = sin(world_pos.x * 9.1 + t * 0.9) * sin(world_pos.z * 8.3 - t * 0.7)
		+ sin((world_pos.x + world_pos.z) * 5.7 + t * 0.5);
	float band = foam_width * (0.85 + 0.35 * foam_noise);
	float foam_band = smoothstep(band, band * 0.2, shore_dist);
	float foam = foam_band * clamp(0.35 + 0.4 * foam_noise, 0.0, 1.0);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 0.4));

	// Gentle grazing reflection toward the environment tone. Never a mirror.
	float fres = pow(1.0 - clamp(dot(n_world, normalize(-(INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz)), 0.0, 1.0), 5.0);
	col = mix(col, sky_color.rgb, clamp(fres * fresnel_strength, 0.0, 0.3));

	// The composed color is pre-compensated for the tonemap (palette stores
	// inverted values), so emit it directly; a small dark ALBEDO keeps the
	// sun's specular glint riding on the waves.
	ALBEDO = vec3(0.02);
	EMISSION = col;
	ROUGHNESS = water_roughness;
	SPECULAR = water_specular;
	METALLIC = 0.0;
	}
}
