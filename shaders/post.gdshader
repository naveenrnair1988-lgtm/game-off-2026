shader_type canvas_item;
// Full-screen cinematic post: works on GL Compatibility and web.
// grade → vignette → grain → chromatic aberration (Voice) → letterbox.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float voice : hint_range(0.0, 1.0) = 0.0;      // 0 sober, 1 the Voice (tweened)
uniform float letterbox : hint_range(0.0, 0.2) = 0.085; // fraction of height per bar
uniform float grain_amount : hint_range(0.0, 0.2) = 0.045;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.38;
uniform float time_seed = 0.0;

// 3x3 grades (warm tungsten noir / cold cyan)
const mat3 SOBER_GRADE = mat3(
	vec3(1.10, 0.02, 0.00),
	vec3(0.04, 0.94, 0.02),
	vec3(0.00, 0.02, 0.78));
const mat3 VOICE_GRADE = mat3(
	vec3(0.72, 0.04, 0.02),
	vec3(0.02, 0.98, 0.08),
	vec3(0.06, 0.10, 1.18));

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// chromatic aberration grows with distance from centre, only in Voice
	vec2 d = (uv - 0.5);
	float ca = voice * 0.006 * dot(d, d) * 4.0;
	float r = texture(screen_tex, uv + d * ca).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - d * ca).b;
	vec3 col = vec3(r, g, b);

	// grade
	mat3 grade = SOBER_GRADE * (1.0 - voice) + VOICE_GRADE * voice;
	col = grade * col;

	// contrast S-curve
	col = mix(col, smoothstep(0.0, 1.0, col), 0.2);

	// desaturate a touch in Voice
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), voice * 0.25);

	// vignette
	float v = 1.0 - vignette_amount * smoothstep(0.25, 1.1, length(d) * 1.6);
	col *= v;

	// film grain (animated)
	float n = hash(uv * vec2(1920.0, 1080.0) + vec2(time_seed * 37.0, time_seed * 11.0));
	col += (n - 0.5) * grain_amount * (1.0 + voice * 0.8);

	// letterbox
	float bar = step(letterbox, uv.y) * step(uv.y, 1.0 - letterbox);
	col *= bar;

	COLOR = vec4(col, 1.0);
}
