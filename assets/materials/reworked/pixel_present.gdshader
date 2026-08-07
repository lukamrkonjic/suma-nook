shader_type canvas_item;
// Legacy optional pixel/cel presentation. Ultra-realistic mode hides this
// CanvasLayer entirely, leaving the native HDR PBR image untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 8.0) = 3.0;
uniform float posterize_strength : hint_range(0.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.5, 1.8) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float value_steps : hint_range(2.0, 24.0) = 10.0;
uniform float sat_steps : hint_range(2.0, 16.0) = 7.0;


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
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 block = vec2(max(pixel_size, 1.0));
	vec2 uv = (floor(SCREEN_UV * resolution / block) + 0.5) * block / resolution;
	vec4 src = texture(screen_tex, uv);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	src.rgb = mix(vec3(luma), src.rgb, saturation);
	src.rgb = (src.rgb - vec3(0.5)) * contrast + vec3(0.5);
	src.rgb = clamp(src.rgb * brightness, vec3(0.0), vec3(1.0));
	vec3 hsv = rgb2hsv(src.rgb);
	hsv.z = floor(hsv.z * value_steps + 0.5) / value_steps;
	hsv.y = floor(hsv.y * sat_steps + 0.5) / sat_steps;
	COLOR = vec4(mix(src.rgb, hsv2rgb(hsv), posterize_strength), src.a);
}
