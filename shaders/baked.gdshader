shader_type spatial;
render_mode unshaded;
// The static room. Its lighting was path-traced in Blender (tools/bake_room.py) into three
// lightmaps, one per group of lights, so the game can still dim, tint and switch them:
//   lamps  - the pendants, desk lamp and shelf strips (baked white, tinted here by the palette)
//   accent - the neon sign and the street through the blinds (baked in colour)
//   head   - the police headlights through the blinds
// Surface colour is the same world-space triplanar texture the room always used.

uniform sampler2D lm_lamps : filter_linear, repeat_disable;
uniform sampler2D lm_accent : filter_linear, repeat_disable;
uniform sampler2D lm_head : filter_linear, repeat_disable;
uniform vec3 lm_scale = vec3(1.0);            // decode scale for lamps, accent, head

uniform vec3 lamp_col = vec3(1.0, 0.76, 0.5);
uniform float accent_gain = 1.0;
uniform float head_gain = 0.0;
uniform vec3 ambient = vec3(0.02);
uniform float exposure = 1.0;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool use_normal = false;
uniform bool triplanar = true;
uniform float tile = 1.0;                     // repeats per metre
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_scale = 1.0;
uniform float rough = 0.8;
uniform float metal = 0.0;

uniform vec3 lamp_pos[6];
uniform int lamp_count = 0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 decode(sampler2D t, vec2 uv, float s) {
	vec3 c = texture(t, uv).rgb;
	return c * c * s;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * tile;
	vec3 base = tint;
	vec3 nd = n;
	if (use_tex) {
		if (triplanar) {
			base *= texture(albedo_tex, vec2(p.z, -p.y)).rgb * w.x + texture(albedo_tex, vec2(p.x, p.z)).rgb * w.y + texture(albedo_tex, vec2(p.x, -p.y)).rgb * w.z;
		} else {
			base *= texture(albedo_tex, UV).rgb;
		}
	}
	if (use_normal && triplanar) {
		vec2 tx = texture(normal_tex, vec2(p.z, -p.y)).xy * 2.0 - 1.0;
		vec2 ty = texture(normal_tex, vec2(p.x, p.z)).xy * 2.0 - 1.0;
		vec2 tz = texture(normal_tex, vec2(p.x, -p.y)).xy * 2.0 - 1.0;
		nd = normalize(n + normal_scale * (vec3(0.0, -tx.y, tx.x) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x, -tz.y, 0.0) * w.z));
	}

	vec3 lamps = decode(lm_lamps, UV2, lm_scale.x);
	vec3 light = lamps * lamp_col + decode(lm_accent, UV2, lm_scale.y) * accent_gain + decode(lm_head, UV2, lm_scale.z) * head_gain + ambient;
	// a soft shoulder, so table tops under a lamp keep their grain instead of burning out
	light = light / (1.0 + 0.22 * dot(light, vec3(0.3, 0.6, 0.1)));

	// relief and highlights from the nearest lamps: the lightmap has no direction of its own
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float relief = 0.0;
	float wsum = 0.0;
	vec3 spec = vec3(0.0);
	float shin = mix(220.0, 8.0, sqrt(rough));
	for (int i = 0; i < lamp_count; i++) {
		vec3 l = lamp_pos[i] - wpos;
		float d2 = dot(l, l);
		l *= inversesqrt(d2);
		float a = 1.0 / (1.0 + d2);
		float ng = max(dot(n, l), 0.0);
		relief += a * (max(dot(nd, l), 0.0) - ng);
		wsum += a * max(ng, 0.15);
		vec3 hv = normalize(l + v);
		spec += a * pow(max(dot(nd, hv), 0.0), shin) * step(0.0, dot(n, l));
	}
	float lum = dot(lamps, vec3(0.3, 0.6, 0.1));
	float detail = clamp(1.0 + 0.9 * relief / max(wsum, 1e-3), 0.55, 1.6);
	vec3 f0 = mix(vec3(0.04), base, metal);
	float occl = clamp(lum * 6.0, 0.0, 1.0);
	vec3 col = base * (1.0 - 0.6 * metal) * light * detail;
	col += f0 * spec * (1.0 - rough) * (1.0 - rough) * (shin * 0.04 + 0.5) * lamp_col * occl * 2.0;
	// metals also mirror the room a little, so brass does not go dead in the dark
	col += base * metal * (light * 0.6 + lamp_col * 0.05) * pow(1.0 - max(dot(nd, v), 0.0), 2.0);
	ALBEDO = col * exposure;
}
