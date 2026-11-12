shader_type spatial;
// Two-bone "puppet" rig done in the vertex shader, for static scanned characters.
// A torso bend above the waist, a head turn above the neck, and a jaw that drops with the voice.
// Heights are normalised 0..1 over the mesh's own bounding box (y0, h).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_orm = false;
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

uniform float y0 = -1.0;
uniform float h = 2.0;
uniform float waist = 0.55;
uniform float neck = 0.87;
uniform float mouth = 0.905;      // height of the line between the lips
uniform float chin = 0.87;        // height of the bottom of the chin
uniform vec2 head_c = vec2(0.0);  // x,z of the neck pivot in mesh space
uniform float face_z = 0.0;       // z of the face surface (front), mesh space

uniform vec3 torso_rot = vec3(0.0);   // pitch, yaw, roll (radians)
uniform vec3 head_rot = vec3(0.0);
uniform float jaw = 0.0;              // 0..1
uniform float breathe = 0.0;          // -1..1

varying float gap;

mat3 euler(vec3 r) {
	float cx = cos(r.x), sx = sin(r.x), cy = cos(r.y), sy = sin(r.y), cz = cos(r.z), sz = sin(r.z);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, sz, 0.0), vec3(-sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	return ry * rx * rz;
}

void vertex() {
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	float hn = (p.y - y0) / h;

	// jaw: the band between chin and lips, on the front of the head, drops
	float ws = 1.0 - smoothstep(mouth - 0.005, mouth + 0.001, hn);
	float depth = face_z - head_c.y;
	float mask = smoothstep(depth * 0.25, depth * 0.7, p.z - head_c.y);
	mask *= 1.0 - smoothstep(depth * 0.40, depth * 0.85, abs(p.x - head_c.x));
	mask *= smoothstep(chin - 0.02, chin - 0.004, hn);
	float wj = ws * mask;
	float amp = (1.0 - neck) * h * 0.027;
	p.y -= wj * jaw * amp;
	p.z -= wj * jaw * amp * 0.3;
	// the stretched strip between the lips reads as the inside of the mouth
	float inner = 1.0 - smoothstep(depth * 0.12, depth * 0.32, abs(p.x - head_c.x));
	gap = 4.0 * ws * (1.0 - ws) * mask * inner * jaw;

	// breathing: chest swells a little, forward
	float wc = smoothstep(waist, waist + 0.12, hn) * (1.0 - smoothstep(neck - 0.07, neck, hn));
	p += n * wc * breathe * 0.0035 * h * max(n.z, 0.0);

	// head
	float wh = smoothstep(neck - 0.012, neck + 0.022, hn);
	vec3 ph = vec3(head_c.x, y0 + neck * h, head_c.y);
	mat3 rh = euler(head_rot);
	p = mix(p, ph + rh * (p - ph), wh);
	n = normalize(mix(n, rh * n, wh));

	// torso (carries the head with it)
	float wt = smoothstep(waist - 0.04, waist + 0.22, hn);
	vec3 pt = vec3(0.0, y0 + waist * h, 0.0);
	mat3 rt = euler(torso_rot * wt);
	p = pt + rt * (p - pt);
	n = normalize(rt * n);

	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = mix(a.rgb * tint, vec3(0.09, 0.03, 0.03), clamp(gap * 1.5, 0.0, 0.85));
	if (use_orm) {
		vec3 o = texture(orm_tex, UV).rgb;
		ROUGHNESS = o.g * rough;
		METALLIC = o.b * metal;
	} else {
		ROUGHNESS = rough;
		METALLIC = metal;
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
