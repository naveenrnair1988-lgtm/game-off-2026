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

// eyes: height of the eye line, half the distance between the eyes, x of the point between them
uniform float eye = 0.92;
uniform float eye_dx = 0.017;
uniform float eye_cx = 0.0;
uniform float blink = 0.0;            // 0 open .. 1 shut
uniform float brow = 0.0;             // -1 frown .. 1 raised

// arms (standing characters only): where the arm leaves the body, low and high, as |x| / h;
// the heights between which that boundary slides; shoulder (x / h, height) and elbow height
uniform bool arms = false;
uniform vec2 arm_b = vec2(0.125, 0.085);
uniform vec2 arm_h = vec2(0.56, 0.80);
uniform vec2 shoulder = vec2(0.10, 0.80);
uniform float elbow = 0.62;
uniform float arm_low = 0.40;       // below this it is coat, not arm
uniform vec2 arm_l = vec2(0.0);       // shoulder swing, elbow bend (radians, forward)
uniform vec2 arm_r = vec2(0.0);

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
	float mask0 = smoothstep(depth * 0.25, depth * 0.7, p.z - head_c.y) * smoothstep(neck, neck + 0.02, hn);
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

	// eyelids: the skin above each eye comes down over it; brows ride up or down
	float head_u = (1.0 - neck) * h;
	float open = head_u * 0.050;
	float lash = eye + 0.5 * open / h;
	float ex = abs(abs(p.x - head_c.x - eye_cx * h) - eye_dx * h);
	float we = (1.0 - smoothstep(head_u * 0.085, head_u * 0.15, ex)) * mask0;
	float lid = smoothstep(eye - 0.6 * open / h, lash, hn) * (1.0 - smoothstep(lash + 0.3 * open / h, lash + 2.4 * open / h, hn));
	p.y -= we * lid * blink * open * 1.05;
	float bw = smoothstep(lash, lash + 0.8 * open / h, hn) * (1.0 - smoothstep(lash + 2.2 * open / h, lash + 4.5 * open / h, hn));
	float bx = 1.0 - smoothstep(head_u * 0.30, head_u * 0.50, abs(p.x - head_c.x - eye_cx * h));
	p.y += bw * bx * mask0 * brow * open * 0.55;

	// arms: bend at the elbow, then swing from the shoulder (both forward)
	if (arms) {
		float cx = head_c.x;
		float side = sign(p.x - cx);
		float ax = abs(p.x - cx) / h;
		float b = mix(arm_b.x, arm_b.y, smoothstep(arm_h.x, arm_h.y, hn));
		float wa = smoothstep(b - 0.010, b + 0.014, ax) * (1.0 - smoothstep(shoulder.y - 0.01, shoulder.y + 0.03, hn)) * smoothstep(arm_low - 0.012, arm_low + 0.004, hn);
		vec2 a = side > 0.0 ? arm_r : arm_l;
		float wel = wa * (1.0 - smoothstep(elbow - 0.03, elbow + 0.03, hn));
		float ce = cos(-a.y * wel), se = sin(-a.y * wel);
		vec2 e0 = vec2(y0 + elbow * h, head_c.y);
		vec2 q = p.yz - e0;
		p.yz = e0 + vec2(q.x * ce - q.y * se, q.x * se + q.y * ce);
		n.yz = vec2(n.y * ce - n.z * se, n.y * se + n.z * ce);
		float cs = cos(-a.x * wa), ss = sin(-a.x * wa);
		vec2 s0 = vec2(y0 + shoulder.y * h, head_c.y);
		q = p.yz - s0;
		p.yz = s0 + vec2(q.x * cs - q.y * ss, q.x * ss + q.y * cs);
		n.yz = vec2(n.y * cs - n.z * ss, n.y * ss + n.z * cs);
	}

	// breathing: the front of the chest swells a little
	float wc = smoothstep(waist, waist + 0.12, hn) * (1.0 - smoothstep(neck - 0.07, neck, hn));
	// (a function of position only: moving along the normal would open cracks at UV seams)
	p.z += wc * breathe * 0.004 * h * smoothstep(-0.01 * h, 0.05 * h, p.z - head_c.y);

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
