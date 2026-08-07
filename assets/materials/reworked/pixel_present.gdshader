shader_type canvas_item;
// Suma Nook pixel-look pass — ported from Imota's pixel presentation
// (imota-idle: shaders/palette_snap.gdshader colour treatment + the
// integer-block RenderViewportPresenter idea, collapsed into one
// full-screen pass so Suma's scene tree and picking stay untouched).
//
// Runs on a ColorRect in a CanvasLayer BELOW the HUD: the 3D world is
// snapped to an integer pixel grid (exact blocks, nearest-neighbour — no
// fractional stretch, the stable pixel grid), then optionally posterized
// on HSV so hue stays continuous and only value/saturation step into flat
// cel bands (Imota's default treatment: crisp, no speckle, never muddy).
// UI layers above render at native resolution and stay crisp.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 8.0) = 3.0;   // window px per block
uniform float posterize_strength : hint_range(0.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.5, 1.8) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float value_steps : hint_range(2.0, 24.0) = 10.0;  // brightness bands
uniform float sat_steps : hint_range(2.0, 16.0) = 7.0;     // saturation bands
uniform float painterly_strength : hint_range(0.0, 1.0) = 0.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.0;
uniform float local_contrast_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.0;
uniform float crest_strength : hint_range(0.0, 1.0) = 0.0;
uniform float relief_strength : hint_range(0.0, 1.0) = 0.0;
uniform float highlight_glow_strength : hint_range(0.0, 1.0) = 0.0;
// Bound from semantic palette tokens by PixelLook. Neutral fallbacks keep
// this shader from becoming a second authored color source.
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 highlight_tint = vec3(1.0);

// A restrained 2x2 ordered pattern, repeated per presented world-pixel.
// Painterly mode uses it only near colour-ramp transitions; it must never
// become the all-over checkerboard of the discarded handheld prototype.
float bayer2(vec2 pixel_coord) {
	vec2 p = mod(floor(pixel_coord), 2.0);
	float rank = 0.0;
	if (p.y < 0.5) {
		rank = p.x < 0.5 ? 0.0 : 2.0;
	} else {
		rank = p.x < 0.5 ? 3.0 : 1.0;
	}
	return rank / 4.0 - 0.375;
}

// RGB<->HSV so we can quantize value/saturation while leaving hue continuous.
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float luminance(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 linear_to_display(vec3 color) {
	color = clamp(color, vec3(0.0), vec3(1.0));
	return mix(
		color * 12.92,
		1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), color)
	);
}

vec3 display_to_linear(vec3 color) {
	return mix(
		color / 12.92,
		pow((color + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), color)
	);
}

vec3 sample_display(vec2 uv) {
	return linear_to_display(texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb);
}

float grade_luminance(float value) {
	return clamp(((value - 0.5) * contrast + 0.5) * brightness, 0.0, 1.0);
}

void fragment() {
	// Snap to the block grid: every block samples one nearest-neighbour texel
	// at its centre, so blocks are exact and stable.
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 block = vec2(max(pixel_size, 1.0));
	vec2 uv = (floor(SCREEN_UV * resolution / block) + 0.5) * block / resolution;
	vec4 src = texture(screen_tex, uv);
	// With HDR 2D the screen sample arrives linear while this pass's grade
	// and posterize math (and its output convention) are sRGB-domain; encode
	// the sample so behavior matches the pre-HDR pipeline exactly.
	src.rgb = linear_to_display(src.rgb);

	// Colour grade (Imota's palette_snap grade, defaults neutral).
	float luma = luminance(src.rgb);
	src.rgb = mix(vec3(luma), src.rgb, saturation);
	src.rgb = (src.rgb - vec3(0.5)) * contrast + vec3(0.5);
	src.rgb *= brightness;
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));

	// Recover restrained form depth before quantization. Four neighboring
	// presented blocks provide a stable, low-frequency shape field: darker
	// pockets receive contact weight, brighter crests catch a warm glaze, and
	// an upper-left relief cue separates planes without drawing outlines.
	float painted_luma = luminance(src.rgb);
	if (painterly_strength > 0.001) {
		vec2 neighbor_step = block / resolution;
		float luma_left = grade_luminance(luminance(sample_display(uv - vec2(neighbor_step.x, 0.0))));
		float luma_right = grade_luminance(luminance(sample_display(uv + vec2(neighbor_step.x, 0.0))));
		float luma_up = grade_luminance(luminance(sample_display(uv - vec2(0.0, neighbor_step.y))));
		float luma_down = grade_luminance(luminance(sample_display(uv + vec2(0.0, neighbor_step.y))));
		float neighborhood_luma = (
			painted_luma * 2.0 + luma_left + luma_right + luma_up + luma_down
		) / 6.0;
		float local_detail = clamp(painted_luma - neighborhood_luma, -0.24, 0.24);
		float cavity = smoothstep(0.012, 0.18, max(-local_detail, 0.0));
		float crest = smoothstep(0.014, 0.18, max(local_detail, 0.0));
		vec2 form_gradient = vec2(
			luma_right - luma_left,
			luma_down - luma_up
		) * 0.5;
		float directional_relief = clamp(
			dot(form_gradient, normalize(vec2(-0.62, -0.78))),
			-0.18,
			0.18
		);
		src.rgb *= 1.0 + local_detail * local_contrast_strength;
		src.rgb *= 1.0 - cavity * cavity_strength * 0.10;
		src.rgb *= 1.0 + crest * crest_strength * 0.045;
		src.rgb *= 1.0 + directional_relief * relief_strength;
	}

	// Palette-bound forest shadows and warm highlights keep the treatment
	// cohesive with Earthwood without pushing every dark into teal.
	float shadow_weight = (1.0 - smoothstep(0.12, 0.62, painted_luma)) * painterly_strength;
	float light_weight = smoothstep(0.58, 0.96, painted_luma) * painterly_strength;
	vec3 shadow_filter = shadow_tint / max(max(shadow_tint.r, shadow_tint.g), max(shadow_tint.b, 0.001));
	vec3 highlight_filter = highlight_tint / max(max(highlight_tint.r, highlight_tint.g), max(highlight_tint.b, 0.001));
	vec3 earthy_shadow = clamp(src.rgb * mix(vec3(1.0), shadow_filter, 0.22), vec3(0.0), vec3(1.0));
	vec3 warm_light = clamp(src.rgb * mix(vec3(1.0), highlight_filter, 0.16), vec3(0.0), vec3(1.0));
	src.rgb = mix(src.rgb, earthy_shadow, shadow_weight * 0.28);
	src.rgb = mix(src.rgb, warm_light, light_weight * 0.22);
	float highlight_glow = pow(smoothstep(0.66, 0.98, painted_luma), 2.0);
	src.rgb += highlight_tint * highlight_glow * highlight_glow_strength * 0.035;
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));

	// Posterize value and saturation into broad painted clusters. Hue stays
	// continuous so grass, stone, snow, fire, and water retain their identity.
	vec3 hsv = rgb2hsv(src.rgb);
	float ordered = bayer2(floor(FRAGCOORD.xy / block));
	float value_dither = ordered * dither_strength / max(value_steps, 1.0);
	float saturation_dither = ordered * dither_strength / max(sat_steps, 1.0);
	hsv.z = floor(clamp(hsv.z + value_dither, 0.0, 1.0) * value_steps + 0.5) / value_steps;
	hsv.y = floor(clamp(hsv.y + saturation_dither, 0.0, 1.0) * sat_steps + 0.5) / sat_steps;
	vec3 quantized = hsv2rgb(hsv);
	vec3 result = mix(src.rgb, quantized, posterize_strength);
	// The math above runs in sRGB display space; the hdr_2d buffer this pass
	// writes into is linear (the display blit applies the encode), so decode
	// the result back to linear.
	result = display_to_linear(result);
	COLOR = vec4(result, src.a);
}
