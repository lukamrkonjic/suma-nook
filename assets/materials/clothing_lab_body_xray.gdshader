shader_type spatial;
render_mode blend_mix, depth_test_disabled, cull_back, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_albedo : source_color = vec4(1.0);
uniform float body_opacity : hint_range(0.05, 1.0) = 0.6;
instance uniform int hide_mask = 0;

varying flat int armor_region;

void vertex() {
	armor_region = int(UV2.x + 0.5);
}

void fragment() {
	if (((hide_mask >> armor_region) & 1) != 0) {
		discard;
	}
	vec4 sampled = texture(albedo_texture, UV) * base_albedo;
	ALBEDO = mix(sampled.rgb, vec3(0.38, 0.78, 0.92), 0.32);
	ROUGHNESS = 0.92;
	SPECULAR = 0.05;
	ALPHA = sampled.a * body_opacity;
}
