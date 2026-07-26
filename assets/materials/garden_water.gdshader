shader_type spatial;
render_mode cull_back, depth_draw_always;
// Stylized still water: muted blue-green, moderately opaque, softly moving
// two-tone surface. No refraction, no realistic normals, no mirror sheen.

uniform vec4 base_color : source_color = vec4(0.4745, 0.5765, 0.5451, 1.0);
uniform vec4 deep_color : source_color = vec4(0.3804, 0.4745, 0.4392, 1.0);
uniform vec4 lit_color : source_color = vec4(0.5686, 0.6667, 0.6314, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.82;
uniform float roughness : hint_range(0.0, 1.0) = 0.48;
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform float wave_scale = 1.0;
uniform float wave_speed = 0.12;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float band_a = sin(world_pos.x * 2.1 * wave_scale + t * 2.3) * sin(world_pos.z * 1.7 * wave_scale - t * 1.8);
	float band_b = sin((world_pos.x + world_pos.z) * 3.4 * wave_scale + t * 2.9);
	float lit_mix = smoothstep(-0.15, 1.0, band_a * 0.6 + band_b * 0.4);
	vec3 col = mix(mix(deep_color.rgb, base_color.rgb, 0.78), lit_color.rgb, lit_mix * 0.38);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
}
