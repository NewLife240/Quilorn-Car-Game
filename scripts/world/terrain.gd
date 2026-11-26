extends Node3D
class_name Terrain
## Heightmap terrain: GPU-displaced LOD chunks, Jolt heightfield collision,
## CPU-side surface queries for tyre physics and deformable mud ruts.

const N := 2049
const HALF := 1024
const WS := 2048
const CHUNK := 128
const LODS := [[128, 0.0, 190.0], [64, 190.0, 420.0], [32, 420.0, 900.0], [16, 900.0, 3200.0]]

enum Surface { GRASS, ASPHALT, GRAVEL, MUD, FIELD, ROCK, CONCRETE }

var heights: PackedFloat32Array
var splat: PackedByteArray
var fields: PackedByteArray
var deform_img: Image
var deform_tex: ImageTexture
var deform_dirty := false
var _deform_timer := 0.0
var material: ShaderMaterial
var water_level := 4.0
var wetness := 0.0
var body: StaticBody3D
var _chunks: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("terrain")


func build(view_distance: float = 1.0) -> void:
	var f := FileAccess.open("res://assets/world/height.bin", FileAccess.READ)
	heights = f.get_buffer(N * N * 4).to_float32_array()
	splat = FileAccess.open("res://assets/world/splat.bin", FileAccess.READ).get_buffer(WS * WS * 4)
	fields = FileAccess.open("res://assets/world/fields.bin", FileAccess.READ).get_buffer(WS * WS)

	var himg := Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())
	var simg := Image.create_from_data(WS, WS, false, Image.FORMAT_RGBA8, splat)
	var fimg := Image.create_from_data(WS, WS, false, Image.FORMAT_R8, fields)
	deform_img = Image.create(WS, WS, false, Image.FORMAT_R8)
	deform_tex = ImageTexture.create_from_image(deform_img)

	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("heightmap", ImageTexture.create_from_image(himg))
	material.set_shader_parameter("splatmap", ImageTexture.create_from_image(simg))
	material.set_shader_parameter("fieldmap", ImageTexture.create_from_image(fimg))
	material.set_shader_parameter("deformmap", deform_tex)
	material.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo.png"))
	material.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_normal.png"))
	material.set_shader_parameter("water_level", water_level)

	# collision
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.set_meta("terrain", true)

	_build_chunks(view_distance)


func _grid_mesh(n: int, size: float) -> ArrayMesh:
	# n quads per side, plus a skirt ring (COLOR.r = 1) to hide LOD cracks
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / n
	var h := size * 0.5
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var w := n + 3  # with skirt border
	for j in range(w):
		for i in range(w):
			var ii := clampi(i - 1, 0, n)
			var jj := clampi(j - 1, 0, n)
			var sk := 1.0 if (i == 0 or j == 0 or i == w - 1 or j == w - 1) else 0.0
			verts.append(Vector3(-h + ii * step, 0.0, -h + jj * step))
			cols.append(Color(sk, 0, 0))
	for j in range(w - 1):
		for i in range(w - 1):
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_chunks(vd: float) -> void:
	var meshes := []
	for l in LODS:
		meshes.append(_grid_mesh(l[0], CHUNK))
	var cnt := WS / CHUNK
	for cz in range(cnt):
		for cx in range(cnt):
			var x0 := cx * CHUNK - HALF
			var z0 := cz * CHUNK - HALF
			var hmin := 1e9
			var hmax := -1e9
			for sz in range(0, CHUNK + 1, 8):
				for sx in range(0, CHUNK + 1, 8):
					var hh := heights[(z0 + HALF + sz) * N + (x0 + HALF + sx)]
					hmin = minf(hmin, hh)
					hmax = maxf(hmax, hh)
			for li in range(LODS.size()):
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[li]
				mi.material_override = material
				mi.position = Vector3(x0 + CHUNK * 0.5, hmin, z0 + CHUNK * 0.5)
				mi.custom_aabb = AABB(Vector3(-CHUNK * 0.5 - 1, -4, -CHUNK * 0.5 - 1), Vector3(CHUNK + 2, hmax - hmin + 6, CHUNK + 2))
				mi.visibility_range_begin = LODS[li][1] * vd if li > 0 else 0.0
				mi.visibility_range_end = LODS[li][2] * vd if li < LODS.size() - 1 else 0.0
				mi.visibility_range_begin_margin = 0.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if li < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("lod", li)
				add_child(mi)
				_chunks.append(mi)


func set_view_distance(vd: float) -> void:
	for mi in _chunks:
		var li: int = mi.get_meta("lod")
		mi.visibility_range_begin = LODS[li][1] * vd if li > 0 else 0.0
		mi.visibility_range_end = LODS[li][2] * vd if li < LODS.size() - 1 else 0.0


func set_wetness(w: float) -> void:
	wetness = w
	if material:
		material.set_shader_parameter("wetness", w)


# ------------------------------------------------------------------ queries
func height_at(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, N - 1.001)
	var fz := clampf(z + HALF, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + N], heights[i + N + 1], tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## returns Vector4(asphalt, gravel, mud, field) in 0..1
func splat_at(x: float, z: float) -> Vector4:
	var ix := clampi(int(x + HALF), 0, WS - 1)
	var iz := clampi(int(z + HALF), 0, WS - 1)
	var i := (iz * WS + ix) * 4
	return Vector4(splat[i] / 255.0, splat[i + 1] / 255.0, splat[i + 2] / 255.0, splat[i + 3] / 255.0)


func field_at(x: float, z: float) -> int:
	var ix := clampi(int(x + HALF), 0, WS - 1)
	var iz := clampi(int(z + HALF), 0, WS - 1)
	return fields[iz * WS + ix]


func rut_at(x: float, z: float) -> float:
	var ix := clampi(int(x + HALF), 0, WS - 1)
	var iz := clampi(int(z + HALF), 0, WS - 1)
	return deform_img.get_pixel(ix, iz).r


## Paint a rut. strength 0..1 per call; only where the ground is soft.
func paint_rut(x: float, z: float, strength: float) -> void:
	var ix := int(x + HALF)
	var iz := int(z + HALF)
	if ix < 1 or iz < 1 or ix >= WS - 1 or iz >= WS - 1:
		return
	var c := deform_img.get_pixel(ix, iz).r
	var nv := minf(1.0, c + strength)
	if nv - c < 0.004:
		return
	deform_img.set_pixel(ix, iz, Color(nv, 0, 0))
	# soften neighbours a bit so ruts read as troughs
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = Vector2i(ix, iz) + o
		var cc := deform_img.get_pixelv(p).r
		deform_img.set_pixelv(p, Color(maxf(cc, nv * 0.45), 0, 0))
	deform_dirty = true


func _process(delta: float) -> void:
	_deform_timer += delta
	if deform_dirty and _deform_timer > 0.25:
		_deform_timer = 0.0
		deform_dirty = false
		deform_tex.update(deform_img)


## Surface parameters at a point: [kind, mud(0..1), friction, softness]
func surface(x: float, z: float) -> Dictionary:
	var s := splat_at(x, z)
	var rut := rut_at(x, z)
	var mud := clampf(s.z + rut * 0.5 + wetness * 0.25 * (1.0 - s.x) * (1.0 - s.y * 0.6), 0.0, 1.0)
	var kind := Surface.GRASS
	if s.x > 0.5:
		kind = Surface.ASPHALT
	elif mud > 0.45:
		kind = Surface.MUD
	elif s.y > 0.5:
		kind = Surface.GRAVEL
	elif s.w > 0.5:
		kind = Surface.FIELD
	var fr := 0.72
	match kind:
		Surface.ASPHALT: fr = 1.0 - wetness * 0.2
		Surface.GRAVEL: fr = 0.78
		Surface.FIELD: fr = 0.62
		Surface.MUD: fr = 0.55
		_: fr = 0.7 - wetness * 0.1
	return {"kind": kind, "mud": mud * (1.0 - s.x), "friction": fr, "rut": rut, "asphalt": s.x}


func save_state() -> Dictionary:
	return {"deform": Marshalls.raw_to_base64(deform_img.get_data().compress(FileAccess.COMPRESSION_ZSTD)), "deform_size": deform_img.get_data().size()}


func load_state(d: Dictionary) -> void:
	if d.has("deform"):
		var raw: PackedByteArray = Marshalls.base64_to_raw(d.deform)
		var data := raw.decompress(int(d.deform_size), FileAccess.COMPRESSION_ZSTD)
		if data.size() == WS * WS:
			deform_img = Image.create_from_data(WS, WS, false, Image.FORMAT_R8, data)
			deform_tex.update(deform_img)
