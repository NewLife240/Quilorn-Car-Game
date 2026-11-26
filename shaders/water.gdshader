shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.04, 0.12, 0.13);
uniform vec3 shallow : source_color = vec3(0.18, 0.3, 0.25);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D normal_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float flow = 0.6;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz * 0.08;
	vec3 n1 = texture(normal_a, uv + vec2(0.0, TIME * 0.03 * flow)).rgb;
	vec3 n2 = texture(normal_a, uv * 1.7 + vec2(TIME * 0.02, -TIME * 0.025 * flow)).rgb;
	vec3 n = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float depth = clamp((VERTEX.z - vpos.z), 0.0, 20.0);
	float t = 1.0 - exp(-depth * 0.6);
	vec3 refr = texture(screen_tex, SCREEN_UV + n.xy * 0.02 * t).rgb;
	vec3 col = mix(refr * shallow * 2.2, deep, t);
	float foam = 1.0 - smoothstep(0.0, 0.35, depth);
	ALBEDO = mix(col, vec3(0.75, 0.78, 0.72), foam * 0.4);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(0.35 + t * 0.65, 0.0, 1.0);
}
