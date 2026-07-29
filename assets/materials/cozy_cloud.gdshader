shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_disabled;

uniform vec4 cloud_top : source_color = vec4(0.98, 0.965, 0.92, 1.0);
uniform vec4 cloud_bottom : source_color = vec4(0.54, 0.60, 0.65, 1.0);

varying float puff_height;
varying float puff_tint;
varying float lobe_height;

void vertex() {
	// SphereMesh vertices span -0.5..0.5 before their per-puff transform.
	// Keeping the gradient in puff-local space gives every lobe a softly
	// shaded underside even though the whole sky uses one MultiMesh draw.
	puff_height = VERTEX.y;
	puff_tint = mix(0.94, 1.025, INSTANCE_CUSTOM.r);
	lobe_height = INSTANCE_CUSTOM.g;
}

void fragment() {
	float sunward = smoothstep(-0.48, 0.42, puff_height);
	vec3 volume_color = mix(cloud_bottom.rgb, cloud_top.rgb, sunward);
	// Lower lobes form the cool, weighty cloud base; the raised domes catch
	// the warm miniature-studio key light.
	float lobe_light = mix(0.76, 1.05, lobe_height);
	ALBEDO = volume_color * puff_tint * lobe_light;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
