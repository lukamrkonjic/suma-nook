shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;
// A small glow-poly portal: the near-black hole remains the dominant read,
// while a few broad, faceted colour currents give it a magical identity.

uniform vec3 hole_color : source_color = vec3(0.008, 0.014, 0.026);
uniform vec3 deep_color : source_color = vec3(0.035, 0.110, 0.250);
uniform vec3 blue_color : source_color = vec3(0.090, 0.350, 0.760);
uniform vec3 aqua_color : source_color = vec3(0.080, 0.820, 0.790);
uniform vec3 lilac_color : source_color = vec3(0.520, 0.330, 0.800);
uniform vec3 glint_color : source_color = vec3(0.650, 0.980, 0.940);
uniform float swirl_speed : hint_range(0.0, 4.0) = 0.42;
uniform float glow_strength : hint_range(0.0, 8.0) = 1.15;
uniform float pulse_boost : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec2 point = (UV - 0.5) * 2.0;
	float time = TIME * swirl_speed;
	float angle = atan(point.y, point.x);
	float radius = length(point);

	// A restrained, slightly asymmetrical 10-sided silhouette. The two slow
	// waves move the vertices just enough to keep the object alive.
	float sector = 6.28318530718 / 10.0;
	float local_angle = mod(angle + 3.14159265359, sector) - sector * 0.5;
	float polygon_radius = radius * cos(local_angle) / cos(sector * 0.5);
	float edge = 0.835
		+ sin(angle * 3.0 + time * 0.70) * 0.022
		+ sin(angle * 5.0 - time * 0.46) * 0.012;
	float alpha = smoothstep(0.025, -0.018, polygon_radius - edge);

	// Quantised, broad currents. There is no painterly noise: every tone is a
	// deliberate flat plane that belongs beside the game's low-poly models.
	float flow = 0.5 + 0.5 * sin(angle * 2.0 + radius * 5.4 - time * 0.72);
	flow += sin(angle * 3.0 - radius * 3.1 + time * 0.41) * 0.16;
	flow = floor(clamp(flow, 0.0, 0.999) * 4.0) / 3.0;
	vec3 current = mix(blue_color, aqua_color, step(0.50, flow));
	current = mix(current, lilac_color, step(0.82, flow));

	float core_edge = 0.38 + sin(angle * 3.0 - time * 0.52) * 0.018;
	float current_mask = smoothstep(core_edge - 0.04, core_edge + 0.055, radius);
	current_mask *= 1.0 - smoothstep(edge - 0.12, edge - 0.025, polygon_radius);
	vec3 color = mix(hole_color, deep_color, smoothstep(0.12, core_edge, radius) * 0.30);
	color = mix(color, current, current_mask * 0.88);

	// One clean luminous lip, kept thin so it never becomes a neon puddle.
	float lip = smoothstep(0.075, 0.018, abs(polygon_radius - (edge - 0.045)));
	color = mix(color, glint_color, lip * 0.62);
	float breathe = 0.92 + sin(time * 1.8) * 0.05 + pulse_boost;
	ALBEDO = color;
	EMISSION = color * glow_strength * breathe + glint_color * lip * 0.32;
	ALPHA = alpha;
}
