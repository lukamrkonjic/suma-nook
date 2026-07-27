shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Authored character textures can contain preview lighting. This restrained
// palette pass keeps their color readable under Suma's real sun without
// flattening the mesh into an unshaded cut-out.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_albedo : source_color = vec4(1.0);
uniform vec4 palette_tint : source_color = vec4(1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float value_scale : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float specular_value : hint_range(0.0, 1.0) = 0.14;
// Per-instance armor coverage. UV2.x contains the semantic triangle-region id
// baked by tools/bake_player_armor_regions.js.
instance uniform int hide_mask = 0;

varying flat int armor_region;

void vertex() {
	armor_region = int(UV2.x + 0.5);
}

void fragment() {
	if (((hide_mask >> armor_region) & 1) != 0) {
		discard;
	}
	vec3 source = texture(albedo_texture, UV).rgb * base_albedo.rgb;
	float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
	vec3 styled = mix(vec3(luminance), source, saturation);
	ALBEDO = clamp(styled * palette_tint.rgb * value_scale, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
}
