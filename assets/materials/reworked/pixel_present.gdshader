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
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));
	src.rgb = mix(
		src.rgb * 12.92,
		1.055 * pow(src.rgb, vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), src.rgb)
	);

	// Colour grade (Imota's palette_snap grade, defaults neutral).
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	src.rgb = mix(vec3(luma), src.rgb, saturation);
	src.rgb = (src.rgb - vec3(0.5)) * contrast + vec3(0.5);
	src.rgb *= brightness;
	src.rgb = clamp(src.rgb, vec3(0.0), vec3(1.0));

	// Posterize in HSV: keep hue, step value + saturation into flat bands.
	vec3 hsv = rgb2hsv(src.rgb);
	hsv.z = floor(hsv.z * value_steps + 0.5) / value_steps;
	hsv.y = floor(hsv.y * sat_steps + 0.5) / sat_steps;
	vec3 quantized = hsv2rgb(hsv);
	vec3 result = mix(src.rgb, quantized, posterize_strength);
	// The math above runs in sRGB display space; the hdr_2d buffer this pass
	// writes into is linear (the display blit applies the encode), so decode
	// the result back to linear.
	result = mix(
		result / 12.92,
		pow((result + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), result)
	);
	COLOR = vec4(result, src.a);
}
