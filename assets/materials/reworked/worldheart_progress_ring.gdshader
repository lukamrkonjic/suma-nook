shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;
// One confident stroke: the collection glyph is a separate Label3D so this
// shader only has to communicate stored progress.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.42, 0.72, 0.95, 1.0);
uniform vec4 track_color : source_color = vec4(0.91, 0.89, 0.79, 0.92);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float radius = length(p) * 2.0;
	float ring = smoothstep(0.90, 0.84, radius) * smoothstep(0.60, 0.66, radius);
	float angle = atan(p.x, -p.y);
	float turn = fract(angle / 6.28318530718 + 1.0);
	float filled = 1.0 - step(progress, turn);
	vec4 ring_color = mix(track_color, fill_color, filled);
	vec4 color = ring_color * ring;
	ALBEDO = color.rgb;
	ALPHA = clamp(color.a, 0.0, 1.0);
}
