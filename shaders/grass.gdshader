shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.5, 0.65, 0.3);
uniform bool use_vertex_color = false;
uniform float sway = 0.12;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_tex = false;

varying float tipf;
varying vec3 tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tipf = 1.0 - UV.y;
	float w = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) + 0.5 * sin(TIME * 3.1 + wp.x * 0.9);
	VERTEX.x += w * sway * tipf * tipf;
	VERTEX.z += w * sway * 0.6 * tipf * tipf;
	vec3 c = use_vertex_color ? COLOR.rgb : base_color;
	tint = c * mix(vec3(0.82, 0.86, 0.78), vec3(1.08, 1.05, 0.92), INSTANCE_CUSTOM.x);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float ao = mix(0.5, 1.0, tipf);
	vec3 c = tint;
	if (use_tex) {
		vec4 t = texture(tex, UV);
		if (t.a < 0.5) discard;
		c *= t.rgb * 1.15;
	}
	ALBEDO = c * ao;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
