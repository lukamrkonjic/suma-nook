shader_type spatial;

// Flat-shaded low-poly blade material with a gentle travelling wind.
//
// Opaque and normal-preserving: the mesh supplies per-face normals and the
// shader must never recompute them, because the faceted read IS the style.
// Sway weight comes from the vertex's LOCAL height, so roots stay pinned
// and tips lean — no UV channel needed. Phase comes from WORLD position so
// neighbouring tufts and neighbouring tiles ride one coherent wave.

uniform vec4 albedo : source_color = vec4(0.29, 0.36, 0.20, 1.0);
uniform float sway_reference_height = 0.18;
uniform float wind_amplitude = 0.012;
uniform float wind_speed = 1.25;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_spatial_scale = 1.4;
uniform float wind_second_amount = 0.35;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = clamp(VERTEX.y / sway_reference_height, 0.0, 1.0);
	weight = pow(weight, 1.6);
	float phase = dot(world.xz, wind_direction) * wind_spatial_scale;
	float wave = sin(TIME * wind_speed + phase)
		+ wind_second_amount
			* sin(TIME * wind_speed * 2.31 + phase * 1.7 + 1.3);
	VERTEX.xz += wind_direction * (wind_amplitude * wave * weight);
}

void fragment() {
	// Vertex colour lets a complete meadow share this one wind material:
	// grass gradients, fern leaves, clovers, and flowers stay one draw call.
	// Mesh colour attributes arrive in display space, so decode them just as
	// StandardMaterial3D decodes an albedo swatch.
	ALBEDO = albedo.rgb * pow(vertex_tint.rgb, vec3(2.2));
	// Matches the kit's standard palette material so blades sit in the
	// same lighting response as every other tile surface.
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
