shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// The ground under the grass. Deliberately the plainest shader in the project.
//
// All of the surface's colour is baked into vertex COLOR by the chunk builder,
// which samples one continuous world-space tone field. That is the whole point:
// a texture — any texture — has a UV layout, and a UV layout has to be assigned
// per cell, which is exactly how the logical grid gets drawn back onto the
// screen. Vertex colour has no such anchor, so a tone region crosses cell and
// chunk boundaries without anything to reveal them.
//
// No normal map and no gloss for the same reason: both would add a second,
// higher-frequency surface detail whose seams would not line up with the
// geometry's, and both would fight the soft matte read the field is going for.
//
// Roughness and specular are uniforms only so a designer can retune the whole
// field's sheen from the material without editing shader source; the defaults
// are the authored values.

uniform float surface_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.14;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = surface_roughness;
	SPECULAR = surface_specular;
}
