extends RefCounted
class_name MatLib
## Shared material library for generated buildings / trees, keyed by Blender material name.

static var _cache := {}
const T := "res://assets/textures/"

# key: [albedo tex (or ""), normal tex, tint, metres per tile, roughness, metallic]
const DEFS := {
	"plaster_white": ["plaster", "plaster", Color(0.95, 0.94, 0.9), 2.5, 0.92, 0.0],
	"plaster_blue": ["plaster_paint", "plaster", Color(0.5, 0.66, 0.88), 2.5, 0.9, 0.0],
	"plaster_yellow": ["plaster_paint", "plaster", Color(0.96, 0.84, 0.52), 2.5, 0.9, 0.0],
	"plaster_pink": ["plaster_paint", "plaster", Color(0.92, 0.74, 0.68), 2.5, 0.9, 0.0],
	"plaster_green": ["plaster_paint", "plaster", Color(0.66, 0.8, 0.62), 2.5, 0.9, 0.0],
	"bricks": ["bricks", "bricks", Color(0.85, 0.62, 0.55), 1.6, 0.9, 0.0],
	"bricks_white": ["bricks", "bricks", Color(1.0, 0.97, 0.9), 1.6, 0.9, 0.0],
	"concrete": ["concrete", "concrete", Color(0.78, 0.77, 0.74), 3.0, 0.92, 0.0],
	"facade_panel": ["", "", Color(1, 1, 1), 0.0, 0.9, 0.0],
	"slate": ["concrete", "tin", Color(0.62, 0.63, 0.62), 1.6, 0.85, 0.0],
	"tin": ["tin", "tin", Color(0.9, 0.9, 0.9), 2.5, 0.6, 0.5],
	"tin_green": ["metal_grey", "tin", Color(0.3, 0.55, 0.38), 2.0, 0.55, 0.3],
	"tin_red": ["metal_grey", "tin", Color(0.6, 0.22, 0.15), 2.0, 0.55, 0.3],
	"tiles": ["tiles", "tiles", Color(1, 1, 1), 2.0, 0.8, 0.0],
	"wood": ["planks", "planks", Color(1, 1, 1), 2.0, 0.85, 0.0],
	"wood_dark": ["planks", "planks", Color(0.55, 0.45, 0.38), 2.0, 0.85, 0.0],
	"wood_blue": ["planks", "planks", Color(0.55, 0.7, 1.0), 2.0, 0.85, 0.0],
	"wood_green": ["planks", "planks", Color(0.6, 0.85, 0.6), 2.0, 0.85, 0.0],
	"metal": ["metal_grey", "metal_paint", Color(0.5, 0.52, 0.55), 2.0, 0.5, 0.6],
	"metal_red": ["metal_grey", "metal_paint", Color(0.75, 0.12, 0.08), 2.0, 0.45, 0.4],
	"metal_white": ["metal_grey", "metal_paint", Color(1.05, 1.05, 1.05), 2.0, 0.45, 0.3],
	"metal_yellow": ["metal_grey", "metal_paint", Color(1.0, 0.75, 0.12), 2.0, 0.5, 0.3],
	"metal_blue": ["metal_grey", "metal_paint", Color(0.22, 0.38, 0.8), 2.0, 0.5, 0.3],
	"rust": ["rust", "rust", Color(1, 1, 1), 2.0, 0.85, 0.4],
	"glass": ["", "", Color(0.08, 0.1, 0.12), 1.0, 0.05, 0.5],
	"gold": ["", "", Color(0.95, 0.72, 0.3), 1.0, 0.3, 1.0],
	"dome_blue": ["", "", Color(0.18, 0.42, 0.78), 1.0, 0.35, 0.6],
	"gravel_pad": ["gravel", "gravel", Color(0.9, 0.88, 0.85), 3.0, 0.95, 0.0],
	"asphalt_pad": ["asphalt", "asphalt", Color(0.8, 0.8, 0.8), 4.0, 0.85, 0.0],
	"rubber": ["", "", Color(0.04, 0.04, 0.04), 1.0, 0.9, 0.0],
	"bark": ["bark", "bark", Color(0.9, 0.85, 0.8), 1.2, 0.95, 0.0],
	"bark_birch": ["plaster", "bark", Color(0.95, 0.95, 0.9), 1.0, 0.8, 0.0],
	"hay": ["", "", Color(0.86, 0.74, 0.42), 1.0, 0.95, 0.0],
	"apples": ["", "", Color(0.78, 0.12, 0.08), 1.0, 0.5, 0.0],
	"dirt_pile": ["gravel", "gravel", Color(0.72, 0.6, 0.48), 3.0, 0.95, 0.0],
	"lamp": ["", "", Color(1, 0.96, 0.85), 1.0, 0.5, 0.0],
}
const LEAVES := {
	"leaves": Color(0.25, 0.42, 0.14), "leaves_dark": Color(0.16, 0.3, 0.11), "leaves_light": Color(0.42, 0.58, 0.2),
	"needles": Color(0.1, 0.22, 0.1), "leaves_willow": Color(0.42, 0.56, 0.3), "leaves_apple": Color(0.3, 0.5, 0.18),
}
const UV_TEX := ["window_khata", "window_plain", "door_wood", "gate_steel"]


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material = _make(key)
	_cache[key] = m
	return m


static func _make(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # generated geometry is often single-sided
	if key.begins_with("sign_"):
		m.albedo_texture = load(T + "signs/%s.png" % key.substr(5))
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.5
		m.roughness = 0.6
		return m
	if key in UV_TEX:
		m.albedo_texture = load(T + key + ".png")
		m.roughness = 0.7
		if key == "gate_steel":
			m.metallic = 0.4
		return m
	if key == "facade_panel":
		m.albedo_texture = load(T + "facade_panel.png")
		m.uv1_scale = Vector3(1.0 / 3.2, 1.0 / 2.8, 1)
		m.roughness = 0.9
		return m
	if LEAVES.has(key):
		m.albedo_color = LEAVES[key]
		m.roughness = 0.85
		m.backlight_enabled = true
		m.backlight = Color(0.2, 0.3, 0.08)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.albedo_texture = load(T + "plaster_c.jpg")
		m.uv1_scale = Vector3(0.6, 0.6, 1)
		return m
	if not DEFS.has(key):
		return null
	var d: Array = DEFS[key]
	if d[0] != "":
		m.albedo_texture = load(T + d[0] + "_c.jpg")
	if d[1] != "":
		m.normal_enabled = true
		m.normal_texture = load(T + d[1] + "_n.jpg")
		m.normal_scale = 0.8
	m.albedo_color = d[2]
	if d[3] > 0.0:
		m.uv1_scale = Vector3(1.0 / d[3], 1.0 / d[3], 1)
	m.roughness = d[4]
	m.metallic = d[5]
	if key == "lamp":
		m.emission_enabled = true
		m.emission = Color(1, 0.95, 0.8)
		m.emission_energy_multiplier = 2.0
	if key == "glass":
		m.metallic_specular = 0.9
	return m


## Replace imported materials on every mesh under `root`.
static func apply(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in range(m.mesh.get_surface_count()):
			var src := m.mesh.surface_get_material(s)
			if src == null:
				continue
			var nm := get_mat(src.resource_name)
			if nm:
				m.set_surface_override_material(s, nm)


## Replace materials directly on a Mesh resource (used for MultiMesh trees).
static func apply_mesh(mesh: Mesh) -> void:
	for s in range(mesh.get_surface_count()):
		var src := mesh.surface_get_material(s)
		if src:
			var nm := get_mat(src.resource_name)
			if nm:
				mesh.surface_set_material(s, nm)
