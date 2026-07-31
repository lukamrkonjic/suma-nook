shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled,
	cull_front, shadows_disabled, specular_disabled, fog_disabled;

// Horizon Zero Dawn style volumetric cloud sea, after "The Real-time
// Volumetric Cloudscapes of Horizon Zero Dawn" (Schneider & Vos, SIGGRAPH
// 2015 Advances in Real-time Rendering), adapted to Suma's floating-island
// diorama. One fixed world-space slab below the island is ray-marched:
//
//  - Modeling: a Perlin-Worley base shape (Perlin FBM dilated by inverted
//    Worley FBM, both runtime-baked 3D textures) is multiplied by a height
//    gradient, remapped by a weather coverage field, then eroded at cloud
//    edges by high-frequency Worley detail whose sample position is
//    distorted with 2D curl noise (atmospheric turbulence). Detail is
//    inverted near cloud bases so bottoms turn whispy while tops billow.
//  - Lighting: Beer's law extinction toward the sun (5 cone samples plus
//    one distant sample for inter-cloud shadows), the Henyey-Greenstein
//    phase for silver linings, the view-gated "powder" term for the dark
//    edges seen away from the sun, and sky ambient that grows with height.
//  - Rendering: cheap samples at large steps until the ray enters a cloud
//    isosurface, then a step back and full-detail samples; after several
//    consecutive zero-density samples the march relaxes back to cheap
//    steps. The march exits early once transmittance is spent, is clamped
//    by scene depth, and fades into the atmosphere colour over distance.
//
// The slab never follows the camera, so zooming or orbiting can never
// recompose the cloudscape - only perspective changes, as in the talk.

uniform sampler3D base_perlin_noise : filter_linear, repeat_disable;
uniform sampler3D base_worley_noise : filter_linear, repeat_disable;
uniform sampler3D detail_worley_noise : filter_linear, repeat_disable;
uniform sampler2D curl_noise : filter_linear, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;

uniform vec3 slab_min = vec3(-84.0, -18.6, -84.0);
uniform vec3 slab_max = vec3(84.0, -7.1, 84.0);
uniform int view_steps = 44;

uniform float extinction = 1.5;
uniform float light_absorption = 0.62;
uniform float rain_absorption = 0.0;
uniform float density_gain = 1.6;

uniform float base_world_scale = 152.0;
uniform float worley_world_scale = 34.0;
uniform float detail_world_scale = 8.5;
uniform float curl_world_scale = 46.0;
uniform float curl_strength = 2.6;
uniform float erosion_strength = 0.52;

uniform float coverage_world_scale = 70.0;
uniform float coverage_bias = 0.56;
uniform float horizon_openness = 0.85;
uniform float tone_world_scale = 110.0;
uniform float tone_spread : hint_range(0.0, 0.5) = 0.20;

uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_time = 0.0;
uniform float wind_base_speed = 0.55;
uniform float wind_detail_speed = 1.35;
uniform float wind_top_skew = 5.0;

uniform vec3 sun_direction = vec3(-0.35, 0.65, -0.30);
uniform vec3 crown_color : source_color = vec3(1.0, 0.995, 0.965);
uniform vec3 light_color : source_color = vec3(1.0, 0.94, 0.82);
uniform vec3 shade_color : source_color = vec3(0.815, 0.77, 0.745);
uniform vec3 rim_color : source_color = vec3(1.0, 0.79, 0.50);
uniform vec3 atmosphere_color : source_color = vec3(0.935, 0.90, 0.815);
uniform float mist_opacity : hint_range(0.0, 1.0) = 0.97;
uniform float sun_energy = 2.1;
uniform float ambient_energy = 1.12;
uniform float powder_strength = 0.58;
uniform float silver_intensity = 0.50;
uniform float forward_scattering = 0.32;
// World-radial fade measured from the island centre, NOT from the camera:
// zooming may never dissolve the sea, only true distance may.
uniform float fade_start = 40.0;
uniform float fade_end = 62.0;

varying vec3 world_position;

float remap(
	float value,
	float old_min,
	float old_max,
	float new_min,
	float new_max
) {
	float span = max(old_max - old_min, 0.0001);
	return clamp(
		new_min + (value - old_min) / span * (new_max - new_min),
		min(new_min, new_max),
		max(new_min, new_max)
	);
}

// Mirrored repeat keeps runtime-baked (non-tiling) noise seamless: the
// field reflects instead of wrapping, and wind drift plus erosion hide the
// reflection lines. Offsets move the mirror seams away from the island.
vec3 mirrored3(vec3 uvw) {
	uvw += vec3(17.37, 9.21, 23.55);
	return 1.0 - abs(1.0 - 2.0 * fract(uvw * 0.5));
}

vec2 mirrored2(vec2 uv) {
	uv += vec2(11.83, 27.49);
	return 1.0 - abs(1.0 - 2.0 * fract(uv * 0.5));
}

float hash12(vec2 point) {
	vec3 fold = fract(vec3(point.xyx) * 0.1031);
	fold += dot(fold, fold.yzx + 33.33);
	return fract((fold.x + fold.y) * fold.z);
}

float henyey_greenstein(float cos_angle, float eccentricity) {
	float g2 = eccentricity * eccentricity;
	return (1.0 - g2)
		/ pow(1.0 + g2 - 2.0 * eccentricity * cos_angle, 1.5);
}

float height_fraction(vec3 point) {
	return clamp(
		(point.y - slab_min.y) / max(slab_max.y - slab_min.y, 0.001),
		0.0,
		1.0
	);
}

// Weather signal (HZD drives this from a weather simulation texture; here
// it is a slowly drifting 2D field). The sea concentrates around and
// below the island; far coverage recedes so the upper sky stays open and
// the cloudscape reads bottom-heavy, like the reference.
float coverage_at(vec2 xz) {
	vec2 sample_uv = (
		xz + wind_direction * (wind_time * wind_base_speed * 0.33)
	) / coverage_world_scale;
	float field = texture(
		base_perlin_noise,
		vec3(mirrored2(sample_uv), 0.36)
	).r;
	float coverage = clamp(
		coverage_bias + (field - 0.5) * 0.85,
		0.0,
		1.0
	);
	coverage *= 1.0
		- smoothstep(40.0, 64.0, length(xz)) * horizon_openness;
	return coverage;
}

// Tonal layering: a huge slow field assigns each cloud mass its own
// brightness, so some banks read sunlit-white while others sit in a
// gentle warm shadow, exactly like the layered masses of the reference.
// It drifts with the same wind term as coverage, so a mass keeps its
// tone while it lives.
float mass_tone_at(vec2 xz) {
	vec2 sample_uv = (
		xz + wind_direction * (wind_time * wind_base_speed * 0.33)
	) / tone_world_scale;
	float field = texture(
		base_perlin_noise,
		vec3(mirrored2(sample_uv + vec2(31.7, 8.9)), 0.71)
	).r;
	return mix(1.0 - tone_spread, 1.0 + tone_spread * 0.55, field);
}

float sample_density(vec3 point, float coverage, bool full_detail) {
	if (coverage <= 0.004) {
		return 0.0;
	}
	float height = height_fraction(point);
	vec3 sample_point = point;
	sample_point.xz -= wind_direction * (wind_time * wind_base_speed);
	sample_point.xz -= wind_direction * (height * wind_top_skew);

	// Base shape: Perlin dilated by inverted Worley billows, shaped by a
	// stratocumulus height gradient (whispy base, dense body, round tops).
	float perlin = texture(
		base_perlin_noise,
		mirrored3(sample_point / base_world_scale)
	).r;
	float billow = 1.0 - texture(
		base_worley_noise,
		mirrored3(sample_point / worley_world_scale)
	).r;
	float base_shape = remap(perlin, billow - 1.0, 1.0, 0.0, 1.0);
	float gradient = smoothstep(0.02, 0.14, height)
		* smoothstep(1.0, 0.32, height);
	base_shape *= gradient;

	float shaped = remap(base_shape, 1.0 - coverage, 1.0, 0.0, 1.0)
		* coverage;
	// Sharpen toward solid interiors: cotton reads as billows with dense
	// hearts and crisp scalloped edges, never as translucent mist.
	shaped = smoothstep(0.06, 0.34, shaped);
	if (shaped <= 0.0001 || !full_detail) {
		return shaped * density_gain;
	}

	// Edge erosion: curl-distorted high-frequency Worley, inverted at the
	// base for whisps, eating only the low-density shell of each cloud.
	vec2 curl = texture(
		curl_noise,
		(sample_point.xz + height * 9.0) / curl_world_scale
	).rg * 2.0 - 1.0;
	vec3 detail_point = sample_point;
	detail_point.xz += curl * curl_strength * (1.0 - height * 0.72);
	detail_point.y -= wind_time * wind_detail_speed;
	float detail_billow = 1.0 - texture(
		detail_worley_noise,
		mirrored3(detail_point / detail_world_scale)
	).r;
	float detail_modifier = mix(
		1.0 - detail_billow,
		detail_billow,
		clamp(height * 3.2, 0.0, 1.0)
	);
	shaped = remap(
		shaped,
		detail_modifier * erosion_strength,
		1.0,
		0.0,
		1.0
	);
	return shaped * density_gain;
}

// 5 samples in a cone toward the sun plus one distant sample to catch
// shadows cast by far clouds, exactly as in the talk. Light samples always
// use the cheap (no-detail) density: the talk switches to cheap samples
// once alpha builds, and the diorama scale makes the difference invisible.
float light_march(vec3 point, vec3 to_sun) {
	vec3 kernel[5] = vec3[5](
		vec3(0.30, 0.30, -0.20),
		vec3(-0.35, 0.22, 0.28),
		vec3(0.16, -0.30, 0.34),
		vec3(-0.24, 0.10, -0.38),
		vec3(0.38, 0.16, 0.22)
	);
	float step_length = (slab_max.y - slab_min.y) / 5.0;
	float optical_depth = 0.0;
	for (int i = 0; i < 5; i++) {
		vec3 cone_point = point
			+ to_sun * step_length * (float(i) + 0.5)
			+ kernel[i] * step_length * float(i) * 0.42;
		optical_depth += sample_density(
			cone_point,
			coverage_at(cone_point.xz),
			false
		) * step_length;
	}
	vec3 far_point = point + to_sun * step_length * 9.0;
	optical_depth += sample_density(
		far_point,
		coverage_at(far_point.xz),
		false
	) * step_length * 2.0;
	return optical_depth;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 camera = CAMERA_POSITION_WORLD;
	vec3 ray = normalize(world_position - camera);

	// World-space slab intersection.
	vec3 safe_ray = vec3(
		abs(ray.x) < 0.00001 ? 0.00001 : ray.x,
		abs(ray.y) < 0.00001 ? 0.00001 : ray.y,
		abs(ray.z) < 0.00001 ? 0.00001 : ray.z
	);
	vec3 inverse_ray = 1.0 / safe_ray;
	vec3 to_min = (slab_min - camera) * inverse_ray;
	vec3 to_max = (slab_max - camera) * inverse_ray;
	vec3 near_planes = min(to_min, to_max);
	vec3 far_planes = max(to_min, to_max);
	float t_enter = max(
		max(near_planes.x, near_planes.y),
		max(near_planes.z, 0.0)
	);
	float t_exit = min(
		far_planes.x,
		min(far_planes.y, far_planes.z)
	);

	// Clamp the march against the opaque scene so the island, cliffs and
	// props correctly occlude clouds behind them while clouds in front of
	// distant geometry still draw.
	float depth_raw = texture(scene_depth, SCREEN_UV).r;
	vec4 view_point = INV_PROJECTION_MATRIX
		* vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	if (abs(view_point.w) > 0.00001) {
		view_point.xyz /= view_point.w;
		float scene_distance = length(view_point.xyz);
		t_exit = min(t_exit, scene_distance);
	}
	t_exit = min(t_exit, 120.0);
	if (t_exit <= t_enter) {
		discard;
	}

	float thickness = slab_max.y - slab_min.y;
	float vertical = max(abs(ray.y), 0.22);
	float full_step = max(
		thickness / float(max(view_steps, 8)) / vertical,
		0.14
	);
	float cheap_step = full_step * 2.6;

	vec3 to_sun = normalize(sun_direction);
	float cos_angle = dot(ray, to_sun);
	// Normalised dual-lobe phase: forward silver lining plus a faint
	// backscatter so away-from-sun faces never go dead.
	float phase = mix(
		henyey_greenstein(cos_angle, forward_scattering),
		henyey_greenstein(cos_angle, -0.10),
		0.35
	) * 0.785;
	float silver = pow(clamp(cos_angle, 0.0, 1.0), 6.0)
		* silver_intensity;
	float away_from_sun = clamp(-cos_angle * 0.5 + 0.5, 0.0, 1.0);
	float absorption = light_absorption + rain_absorption;

	float t = t_enter + full_step * hash12(FRAGCOORD.xy);
	float transmittance = 1.0;
	vec3 radiance = vec3(0.0);
	float weight_total = 0.0;
	float weighted_distance = 0.0;
	bool cheap_mode = true;
	int zero_run = 0;

	for (int i = 0; i < 220; i++) {
		if (t >= t_exit || transmittance <= 0.012) {
			break;
		}
		vec3 point = camera + ray * t;
		float coverage = coverage_at(point.xz);

		if (cheap_mode) {
			float probe = sample_density(point, coverage, false);
			if (probe > 0.0001) {
				// Entered the isosurface: step back, go full detail.
				cheap_mode = false;
				t = max(t - full_step * 1.5, t_enter);
				continue;
			}
			t += cheap_step;
			continue;
		}

		float density = sample_density(point, coverage, true);
		if (density <= 0.0001) {
			zero_run += 1;
			if (zero_run >= 6) {
				cheap_mode = true;
				zero_run = 0;
			}
			t += full_step;
			continue;
		}
		zero_run = 0;

		float light_depth = light_march(point, to_sun);
		float beer = exp(-light_depth * absorption);
		float powder = 1.0 - exp(-light_depth * absorption * 2.0);
		float powder_term = mix(
			1.0,
			powder,
			powder_strength * (0.35 + 0.65 * away_from_sun)
		);
		float height = height_fraction(point);
		// Sky ambient grows with height and dims where the sun march found
		// thick material above - creases shade, crowns stay luminous.
		float ambient_occlusion = 0.45
			+ 0.55 * exp(-light_depth * 0.22);
		vec3 ambient = mix(
			shade_color,
			crown_color,
			smoothstep(0.05, 0.95, height)
		) * (ambient_energy * ambient_occlusion);
		vec3 sun_term = light_color
			* (sun_energy * beer * powder_term * phase);
		vec3 rim_term = rim_color * (silver * beer);
		vec3 scattered = (ambient + sun_term + rim_term)
			* mass_tone_at(point.xz);

		float step_extinction = density * extinction * full_step;
		float step_transmittance = exp(-step_extinction);
		vec3 integrated = scattered * (1.0 - step_transmittance);
		radiance += transmittance * integrated;
		float weight = transmittance * (1.0 - step_transmittance);
		weight_total += weight;
		weighted_distance += weight * t;
		transmittance *= step_transmittance;
		t += full_step;
	}

	float alpha_raw = 1.0 - transmittance;
	if (alpha_raw < 0.004) {
		discard;
	}
	float mean_distance = weighted_distance / max(weight_total, 0.0001);
	vec3 color = radiance / max(alpha_raw, 0.004);

	// Atmospheric attenuation over depth, per the talk: distant clouds
	// dissolve into the sky wash. Distance is measured radially from the
	// island in world space so zoom cannot fade the sea, and the fade
	// completes before the slab boundary could ever read as a box edge.
	vec3 mean_point = camera + ray * mean_distance;
	float atmosphere = smoothstep(
		fade_start,
		fade_end,
		length(mean_point.xz)
	);
	color = mix(color, atmosphere_color, atmosphere * 0.9);
	float alpha = alpha_raw * mist_opacity * (1.0 - atmosphere);

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
