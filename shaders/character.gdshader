shader_type spatial;
// Skinned characters. The skeleton and the face shape keys move the mesh; this shader only shades it.
// UV2 carries each vertex's place on the face at rest (x off the centre line / height, normalised
// height) and vertex colour red the jaw mask, so the inside of the mouth can be drawn per pixel
// wherever the head has turned to.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_orm = false;
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float mouth = 0.88;       // height of the line between the lips
uniform float jaw = 0.0;          // 0..1, same value as the "jaw" shape key
uniform float rim = 0.45;

varying vec3 orig;

void vertex() {
	orig = vec3(UV2.x, UV2.y, COLOR.r);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float fs = 1.0 - smoothstep(mouth - 0.003, mouth + 0.0005, orig.y);
	float gap = smoothstep(0.08, 0.45, 4.0 * fs * (1.0 - fs)) * smoothstep(0.12, 0.55, orig.z) * smoothstep(0.08, 0.6, jaw);
	ALBEDO = mix(a.rgb * tint, vec3(0.09, 0.03, 0.028), clamp(gap, 0.0, 0.82));
	if (use_orm) {
		vec3 o = texture(orm_tex, UV).rgb;
		ROUGHNESS = max(o.g * rough, 0.55);   // generated skin maps come out glossy
		METALLIC = 0.0;
	} else {
		ROUGHNESS = rough;
		METALLIC = metal;
	}
	// a soft edge light, so a figure separates from the baked room behind it
	RIM = rim;
	RIM_TINT = 0.55;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
