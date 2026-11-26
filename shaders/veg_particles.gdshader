shader_type particles;
render_mode disable_velocity, disable_force;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splatmap : filter_linear, repeat_disable;
uniform sampler2D fieldmap : filter_nearest, repeat_disable;
uniform sampler2D deformmap : filter_linear, repeat_disable;
uniform float spacing = 0.5;
uniform int side = 100;
uniform int mode = 0; // 0 grass, 1 wheat, 2 sunflower
uniform vec3 cam_pos;
uniform float water_level = 4.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
vec2 huv(vec2 xz) { return (xz + 1024.5) / 2049.0; }
vec2 suv(vec2 xz) { return (xz + 1024.0) / 2048.0; }

void place(uint index, inout mat4 xf, inout vec4 custom, inout bool active) {
	int ix = int(index) % side;
	int iz = int(index) / side;
	vec2 origin = floor(cam_pos.xz / spacing) * spacing;
	vec2 p = origin + (vec2(float(ix), float(iz)) - float(side) * 0.5) * spacing;
	vec2 cell = floor(p / spacing + 0.5);
	float h1 = hash(cell);
	float h2 = hash(cell + 17.31);
	float h3 = hash(cell + 41.7);
	p += (vec2(h1, h2) - 0.5) * spacing * 0.95;
	float h = texture(heightmap, huv(p)).r;
	float hx = texture(heightmap, huv(p + vec2(1.0, 0.0))).r;
	float hz = texture(heightmap, huv(p + vec2(0.0, 1.0))).r;
	float slope = length(vec2(hx - h, hz - h));
	vec4 sp = texture(splatmap, suv(p));
	float fld = texture(fieldmap, suv(p)).r * 255.0;
	float rut = texture(deformmap, suv(p)).r;
	float keep = 0.0;
	float sc = 1.0;
	if (mode == 0) {
		float dens = vnoise(p * 0.15) * 0.7 + vnoise(p * 0.9) * 0.3;
		keep = step(sp.r + sp.g * 1.2 + sp.b * 1.5 + sp.a * 2.0, 0.35) * step(fld, 0.5) * step(water_level + 0.6, h) * step(slope, 0.55) * step(0.28, dens + h3 * 0.15);
		sc = mix(0.55, 1.35, dens) * (0.8 + h3 * 0.4);
	} else if (mode == 1) {
		keep = (abs(fld - 1.0) < 0.5 ? 1.0 : 0.0) * step(sp.g + sp.r, 0.2);
		sc = 0.85 + h3 * 0.3;
	} else {
		keep = (abs(fld - 2.0) < 0.5 ? 1.0 : 0.0) * step(sp.g + sp.r, 0.2) * step(0.12, fract(p.x * 0.7));
		sc = 0.8 + h3 * 0.35;
	}
	keep *= 1.0 - smoothstep(0.15, 0.4, rut);
	float r = float(side) * spacing * 0.5;
	float d = length(p - cam_pos.xz);
	float fade = 1.0 - smoothstep(r * 0.7, r * 0.98, d);
	if (mode == 0) { fade *= step(h3, 0.25 + 0.75 * (1.0 - smoothstep(r * 0.3, r * 0.9, d))); }
	sc *= keep * fade;
	float a = h1 * 6.2831;
	if (mode == 2) { a = 1.2 + (h1 - 0.5) * 0.6; }
	mat3 rot = mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
	xf = mat4(vec4(rot[0] * sc, 0.0), vec4(rot[1] * sc, 0.0), vec4(rot[2] * sc, 0.0), vec4(p.x, h - rut * 0.2 - 0.02, p.y, 1.0));
	custom = vec4(h1, h2, h3, 0.0);
	active = sc > 0.001;
}

void start() { place(INDEX, TRANSFORM, CUSTOM, ACTIVE); COLOR = vec4(1.0); }
void process() { place(INDEX, TRANSFORM, CUSTOM, ACTIVE); COLOR = vec4(1.0); }
