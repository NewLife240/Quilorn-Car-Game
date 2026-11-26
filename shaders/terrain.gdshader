shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// World is 2048 m, heightmap 2049x2049 (1 sample per metre), centred on origin.
uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splatmap : filter_linear, repeat_disable;   // r asphalt, g gravel, b mud, a field
uniform sampler2D fieldmap : filter_nearest, repeat_disable;  // 1 wheat 2 sunflower 3 plowed
uniform sampler2D deformmap : filter_linear, repeat_disable;  // tyre ruts 0..1
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 0.0;
uniform float water_level = 4.0;
uniform float rut_depth = 0.22;
uniform vec3 grass_tint : source_color = vec3(0.92, 0.98, 0.78);

varying vec3 wpos;
varying float skirt;

const float WS = 2048.0;

vec2 huv(vec2 xz) { return (xz + 1024.0 + 0.5) / (WS + 1.0); }
vec2 suv(vec2 xz) { return (xz + 1024.0) / WS; }

float h_at(vec2 xz) {
	return texture(heightmap, huv(xz)).r - texture(deformmap, suv(xz)).r * rut_depth;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = h_at(w.xz);
	skirt = COLOR.r;
	float under_road = texture(splatmap, suv(w.xz)).r;
	VERTEX.y = h - skirt * 3.0 - under_road * 0.22 - MODEL_MATRIX[3].y;
	wpos = vec3(w.x, h, w.z);
}

// cheap hash noise for variation
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

vec4 layer(int id, vec2 uv) {
	return texture(albedo_arr, vec3(uv, float(id)));
}
vec3 nlayer(int id, vec2 uv) {
	return texture(normal_arr, vec3(uv, float(id))).rgb;
}

void fragment() {
	vec2 xz = wpos.xz;
	// per-pixel normal from heightmap (+ruts)
	float e = 0.75;
	float hl = h_at(xz - vec2(e, 0.0));
	float hr = h_at(xz + vec2(e, 0.0));
	float hd = h_at(xz - vec2(0.0, e));
	float hu = h_at(xz + vec2(0.0, e));
	vec3 n = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	float slope = 1.0 - n.y;

	vec4 sp = texture(splatmap, suv(xz));
	float field = texture(fieldmap, suv(xz)).r * 255.0;
	float rut = texture(deformmap, suv(xz)).r;

	vec2 uv = xz * 0.25;
	vec2 uv2 = xz * 0.071 + vec2(0.37, 0.11);
	float macro = vnoise(xz * 0.02) * 0.6 + vnoise(xz * 0.09) * 0.4;

	// base ground: grass variants
	vec3 g1 = layer(0, uv).rgb * grass_tint;
	vec3 g2 = layer(7, uv2).rgb * vec3(0.85, 0.9, 0.7);
	vec3 g3 = layer(1, uv * 0.8).rgb;
	vec3 col = mix(g1, g2, smoothstep(0.35, 0.75, macro));
	col = mix(col, g3, smoothstep(0.6, 0.9, vnoise(xz * 0.05 + 13.0)) * 0.7);
	vec3 nrm = nlayer(0, uv);
	float rough = 0.95;

	// rock on slopes
	float rk = smoothstep(0.28, 0.45, slope + (macro - 0.5) * 0.1);
	col = mix(col, layer(6, xz * 0.12).rgb * 0.85, rk);
	nrm = mix(nrm, nlayer(6, xz * 0.12), rk);

	// fields
	float fld = sp.a;
	if (fld > 0.01) {
		vec3 soil = layer(2, uv).rgb * vec3(0.62, 0.5, 0.42);
		float furrow = 0.75 + 0.25 * sin(xz.x * 3.1 + xz.y * 0.4);
		soil *= furrow;
		if (field < 2.5) soil = mix(soil, col * vec3(0.95, 0.9, 0.55), 0.35);
		col = mix(col, soil, fld);
		nrm = mix(nrm, nlayer(2, uv), fld);
	}
	// built-up yards: trampled, patchy ground
	if (abs(field - 4.0) < 0.5) {
		float y = 0.55 + 0.3 * vnoise(xz * 0.4);
		col = mix(col, mix(layer(2, uv).rgb, layer(4, uv * 1.3).rgb, 0.4) * 0.9, y);
		nrm = mix(nrm, nlayer(2, uv), y);
	}
	// shore
	float shore = 1.0 - smoothstep(water_level + 0.2, water_level + 1.4, wpos.y);
	col = mix(col, layer(3, uv).rgb * 0.8, shore);

	// gravel / dirt roads
	float gv = sp.g;
	vec3 gcol = mix(layer(4, uv * 1.3).rgb, layer(2, uv).rgb, 0.45 + 0.3 * vnoise(xz * 0.3));
	col = mix(col, gcol, gv);
	nrm = mix(nrm, nlayer(4, uv * 1.3), gv);
	rough = mix(rough, 0.9, gv);

	// mud
	float md = clamp(sp.b * (0.8 + 0.4 * vnoise(xz * 0.5)) + rut * 0.6, 0.0, 1.0);
	md = smoothstep(0.15, 0.6, md);
	vec3 mcol = layer(3, uv).rgb * vec3(0.72, 0.66, 0.6);
	col = mix(col, mcol, md);
	nrm = mix(nrm, nlayer(3, uv), md);
	rough = mix(rough, 0.45, md);

	// asphalt (under the road ribbon, visible at shoulders and far LODs)
	float as = sp.r;
	col = mix(col, layer(5, uv).rgb * 0.8, as);
	nrm = mix(nrm, nlayer(5, uv), as);
	rough = mix(rough, 0.8, as);

	// ruts: darker and wetter
	col *= 1.0 - rut * 0.35;
	rough = mix(rough, 0.3, rut * 0.8);

	// rain wetness
	float wet = wetness * (1.0 - as * 0.4);
	col *= 1.0 - wet * 0.35;
	rough = mix(rough, 0.25, wet * 0.8);

	// tangent-space normal: world normal from heightmap, detail normal from textures
	vec3 wn = n;
	vec3 t = normalize(cross(wn, vec3(0.0, 0.0, 1.0)));
	vec3 b = cross(t, wn);
	vec3 dn = nrm * 2.0 - 1.0;
	vec3 world_n = normalize(t * dn.x * 0.8 + b * dn.y * 0.8 + wn * dn.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
