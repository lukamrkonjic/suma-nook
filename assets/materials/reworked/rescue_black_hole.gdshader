shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled;
// Donut County-style rescue hole: a flat, matte, near-black disc lying on
// the surface. The permanent Worldheart is an overlay object: it must remain
// above its host tile and tile dressing instead of z-fighting or disappearing.

uniform vec3 hole_color : source_color = vec3(1.0);
uniform vec3 rim_color : source_color = vec3(1.0);
uniform float rim_width = 0.1;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float rim = smoothstep(1.0 - rim_width * 2.0, 1.0 - rim_width, r)
		* (1.0 - smoothstep(1.0 - rim_width, 1.0, r));
	vec3 color = mix(hole_color, rim_color, rim * 0.8);
	// Solid core so it truly swallows what sinks behind it; soft outer lip.
	float alpha = 1.0 - smoothstep(0.93, 1.0, r);
	ALBEDO = color;
	ALPHA = alpha;
}
