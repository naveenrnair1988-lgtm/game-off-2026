shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Cheap atmosphere: additive light cones under the pendant lamps and soft halos around bulbs.
// mode 0 = cone (a tapered cylinder), mode 1 = halo (a billboarded quad).

uniform int mode = 0;
uniform vec3 color : source_color = vec3(1.0, 0.76, 0.5);
uniform float strength = 1.0;
varying float along;

void vertex() {
	along = UV.y;
	if (mode == 1) {
		// face the camera
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(INV_VIEW_MATRIX[0].xyz) * length(MODEL_MATRIX[0].xyz), 0.0), vec4(normalize(INV_VIEW_MATRIX[1].xyz) * length(MODEL_MATRIX[1].xyz), 0.0), vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	}
}

void fragment() {
	float a;
	if (mode == 1) {
		float d = length(UV - 0.5) * 2.0;
		a = pow(max(1.0 - d, 0.0), 2.6);
	} else {
		// brightest through the middle of the cone, nothing at its silhouette, fading with distance from the lamp
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a = pow(facing, 2.2) * pow(1.0 - along, 1.6) * smoothstep(0.0, 0.06, along);
	}
	ALBEDO = color * strength * a;
}
