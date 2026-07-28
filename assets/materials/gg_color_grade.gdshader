shader_type canvas_item;
render_mode blend_disabled;
// Faithful port of Garden Galaxy's camera color pipeline: Unity
// Post-Processing Stack v2, PP_MainCamera profile (HDR grading mode,
// Neutral tonemapper). Math and constants transcribed from PPv2 sources
// (Lut2DBaker.shader / Colors.hlsl / ColorUtilities.cs). Chain, in order:
// scene * postExposure -> contrast in LogC around ACEScc midgray ->
// white balance in LMS -> saturation around Rec.709 luma -> Neutral tonemap.
// Runs on the HDR screen buffer (hdr_2d) with the Environment tonemapper set
// to LINEAR so Godot's own pipeline stays out of the way.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float post_exposure = 1.231144; // 2^(0.3 EV)
uniform vec3 color_balance = vec3(1.007913, 1.010796, 0.900904); // temp +10, tint -7
uniform float grade_contrast = 1.35;    // PPv2 contrast 35
uniform float grade_saturation = 1.06;  // PPv2 saturation 6
uniform int tonemapper = 1;             // 0 = none, 1 = Neutral
uniform float effect_weight = 1.0;      // volume weight; 1 = full GG grade

const float ACEScc_MIDGRAY = 0.4135884;
// Alexa LogC (El 1000) parameters, as used by PPv2 for HDR LUT space.
const float LOGC_A = 5.555556;
const float LOGC_B = 0.047996;
const float LOGC_C = 0.244161;
const float LOGC_D = 0.386036;

const mat3 LIN_2_LMS_MAT = mat3(
	vec3(0.390405, 0.0708416, 0.0231082),
	vec3(0.549941, 0.963172, 0.128021),
	vec3(0.00892632, 0.00135775, 0.936245)
);
const mat3 LMS_2_LIN_MAT = mat3(
	vec3(2.85847, -0.210182, -0.0418120),
	vec3(-1.62879, 1.15820, -0.118169),
	vec3(-0.0248910, 0.000324281, 1.06867)
);

vec3 linear_to_logc(vec3 x) {
	return LOGC_C * log(LOGC_A * x + LOGC_B) / log(10.0) + LOGC_D;
}

vec3 logc_to_linear(vec3 x) {
	return (pow(vec3(10.0), (x - LOGC_D) / LOGC_C) - LOGC_B) / LOGC_A;
}

vec3 neutral_curve(vec3 x) {
	const float a = 0.2;
	const float b = 0.29;
	const float c = 0.24;
	const float d = 0.272;
	const float e = 0.02;
	const float f = 0.3;
	return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
}

vec3 neutral_tonemap(vec3 x) {
	const float white_level = 5.3;
	vec3 white_scale = vec3(1.0) / neutral_curve(vec3(white_level));
	x = neutral_curve(x * white_scale);
	x *= white_scale; // whiteClip = 1.0
	return x;
}

void fragment() {
	vec3 color = texture(screen_tex, SCREEN_UV).rgb;
	vec3 graded = max(color * post_exposure, vec3(0.0));

	// PPv2 LogGradeHDR: contrast in LogC space.
	vec3 log_c = linear_to_logc(graded);
	log_c = (log_c - ACEScc_MIDGRAY) * grade_contrast + ACEScc_MIDGRAY;
	graded = max(logc_to_linear(log_c), vec3(0.0));

	// PPv2 LinearGradeHDR: white balance in LMS, then saturation.
	graded = LMS_2_LIN_MAT * ((LIN_2_LMS_MAT * graded) * color_balance);
	float luma = dot(graded, vec3(0.2126729, 0.7151522, 0.0721750));
	graded = vec3(luma) + grade_saturation * (graded - vec3(luma));
	graded = max(graded, vec3(0.0));

	if (tonemapper == 1) {
		graded = neutral_tonemap(graded);
	}
	graded = clamp(graded, vec3(0.0), vec3(1.0));
	graded = mix(clamp(color, vec3(0.0), vec3(1.0)), graded, effect_weight);

	// Canvas output is treated as sRGB and decoded into the linear 2D buffer,
	// so encode here; the final blit's encode then lands on exactly this
	// value. (Verified numerically against the reference grade chain.)
	vec3 encoded = mix(
		graded * 12.92,
		1.055 * pow(graded, vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), graded)
	);
	COLOR = vec4(encoded, 1.0);
}
