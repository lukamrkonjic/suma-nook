shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;
// A single quiet halo underneath the portal. It supports the silhouette in
// darkness without turning the host tile into a glowing puddle.

uniform vec3 aura_color : source_color = vec3(0.080, 0.760, 0.780);
uniform vec3 accent_color : source_color = vec3(0.430, 0.280, 0.720);
uniform float phase = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 0.55;

void fragment() {
	vec2 point = (UV - 0.5) * 2.0;
	float radius = length(point);
	float angle = atan(point.y, point.x);
	float time = TIME * 0.24 + phase;
	float edge = 0.76 + sin(angle * 3.0 + time) * 0.025;
	float halo = smoothstep(edge + 0.13, edge - 0.04, radius)
		* smoothstep(edge - 0.18, edge - 0.04, radius);
	vec3 color = mix(aura_color, accent_color, step(0.0, sin(angle * 2.0 - time)) * 0.20);
	ALBEDO = color;
	EMISSION = color * intensity;
	ALPHA = halo * 0.12 * intensity;
}
