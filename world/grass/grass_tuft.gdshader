shader_type spatial;
// cull_disabled, not cull_back: a leaf is a single ribbon with no thickness, so
// back-face culling would erase every blade the camera happens to see from
// behind — roughly half of them, changing as the camera orbits.
//
// The normal is deliberately NOT flipped for back faces. The meshes are
// authored with every normal biased upward regardless of which way its face
// points, so both sides of a blade light identically and a clump shades as one
// soft dome. Flipping would restore exactly the hard per-blade light-and-dark
// that authoring those normals was meant to remove.
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;

// Wind for the instanced grass tufts. Two decisions here carry the whole
// effect, and both are easy to undo by accident:
//
// COLOR.r GATES THE DISPLACEMENT. The tuft meshes are authored with a vertex
// colour ramp in red — 0 at the planted base, rising towards the tips. The wind
// mask is that channel, so base vertices are multiplied by zero and literally
// cannot move. Without the gate the whole instance slides as a rigid island,
// its footprint detaches from the ground it is planted in, and the carpet reads
// as decals skating over the surface rather than as grass growing out of it. A
// tuft may bend; it may never drift.
//
// THE PHASE COMES FROM INSTANCE_CUSTOM.r. Every instance of a given mesh runs
// this identical shader at the identical TIME, so with a shared phase an entire
// field would sway in lockstep — a single rigid sheet, the most artificial
// motion possible. The per-instance random in INSTANCE_CUSTOM.r offsets each
// tuft around the cycle, so neighbours are always slightly out of step while
// the shared travelling wave still carries a coordinated gust across them.
// INSTANCE_CUSTOM.g scales each tuft's amplitude and .b picks its tone, so no
// two neighbours agree about how much they move or exactly what colour they
// are either.

uniform vec4 grass_deep : source_color = vec4(1.0);
uniform vec4 grass_main : source_color = vec4(1.0);
uniform vec4 grass_light : source_color = vec4(1.0);
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wind_speed = 0.72;
uniform float wind_world_scale = 1.10;
uniform float base_wind_strength = 0.004;
uniform float gust_wind_strength = 0.010;
varying float instance_tone;
varying float authored_top_light;

void vertex() {
	vec2 direction = normalize(wind_direction);
	vec2 cross_direction = vec2(-direction.y, direction.x);
	float wind_mask = smoothstep(0.10, 1.0, COLOR.r);
	float instance_phase = INSTANCE_CUSTOM.r * 6.28318530718;
	float instance_amount = clamp(INSTANCE_CUSTOM.g, 0.0, 1.0);
	instance_tone = clamp(INSTANCE_CUSTOM.b, 0.0, 1.0);
	authored_top_light = COLOR.g;
	float broad_wave = sin(TIME * wind_speed + dot(VERTEX.xz, direction) * wind_world_scale + instance_phase);
	float secondary_wave = sin(TIME * wind_speed * 0.47 + dot(VERTEX.xz, cross_direction) * 0.68 + instance_phase * 1.73);
	float gust_wave = sin(TIME * 0.19 + dot(VERTEX.xz, vec2(0.14, -0.11)) + instance_phase * 0.23);
	float gust = smoothstep(0.20, 0.92, gust_wave * 0.5 + 0.5);
	float combined_wave = broad_wave * 0.78 + secondary_wave * 0.22;
	float strength = (base_wind_strength + gust * gust_wind_strength);
	strength *= instance_amount;
	strength *= wind_mask;
	VERTEX.xz += (direction * combined_wave * strength);
	VERTEX.xz += (cross_direction * secondary_wave * strength * 0.16);
	VERTEX.y += (abs(combined_wave) * strength * 0.045);
}

void fragment() {
	vec3 instance_colour = mix(grass_deep.rgb, grass_light.rgb, instance_tone);
	// Widened from 0.93-1.04. A leaf lit flat across its whole span has no
	// form at all, and a field of formless leaves reads as printed camouflage
	// rather than as foliage with depth.
	instance_colour = mix(instance_colour * 0.84, instance_colour * 1.12, authored_top_light);
	ALBEDO = instance_colour;
	ROUGHNESS = 0.93;
	SPECULAR = 0.12;
}
