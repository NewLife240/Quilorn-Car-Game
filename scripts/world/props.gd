extends Node3D
## Places buildings, trees, grass and crops. Exposes interaction points from building models ("IP_*" nodes).

const TREE_CHUNK := 256.0
const RANGE_SMALL := ["fence_run", "well", "bus_stop", "power_pole", "shed", "wreck", "monument"]
const RANGE_BIG := ["khrushchevka", "grain_elevator", "church", "warehouse", "furniture_factory", "flour_mill", "cowshed"]
var _tree_bodies: Array[RID] = []
var _trunk_shape: RID
var world: Node
var objects: Array = []
var ips: Array = []                 # [{name, node, kind, obj}]
var _tree_mmis: Array[MultiMeshInstance3D] = []
var _grass: Array[GPUParticles3D] = []
var _grass_base := {}


func find_object(kind: String) -> Dictionary:
	for o in objects:
		if o.kind == kind:
			return o
	return {}


func find_objects(kind: String) -> Array:
	return objects.filter(func(o): return o.kind == kind)


func build(w: Node) -> void:
	world = w
	objects = w.data.objects
	_build_buildings()
	_build_trees()
	_build_vegetation_particles()


# ------------------------------------------------------------------ buildings
func _build_buildings() -> void:
	var cache := {}
	for o in objects:
		var kind: String = o.kind
		if kind in ["spawn_player"]:
			continue
		var path := "res://assets/buildings/%s.glb" % kind
		if not ResourceLoader.exists(path):
			continue
		if not cache.has(kind):
			cache[kind] = load(path)
		var inst: Node3D = cache[kind].instantiate()
		inst.name = "%s_%d" % [kind, objects.find(o)]
		var y: float = o.y
		inst.transform = Transform3D(Basis(Vector3.UP, o.rot), Vector3(o.x, y, o.z))
		if kind == "fence_run":
			inst.scale = Vector3(float(o.get("length", 18.0)) / 18.0, 1, 1)
		add_child(inst)
		MatLib.apply(inst)
		o["node"] = inst
		var vr := 700.0
		if kind in RANGE_SMALL:
			vr = 260.0
		elif kind in RANGE_BIG:
			vr = 1600.0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.visibility_range_end = vr
			if kind in RANGE_SMALL:
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "fence_run" else m.cast_shadow
			m.visibility_range_end_margin = 50.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for n in inst.find_children("IP_*", "", true, false):
			ips.append({"name": String(n.name).substr(3), "node": n, "obj": o})


# ------------------------------------------------------------------ trees
func _build_trees() -> void:
	var trees: Array = JSON.parse_string(FileAccess.open("res://assets/world/trees.json", FileAccess.READ).get_as_text())
	var types := {}
	for t in trees:
		types[t[3]] = true
	var meshes := {}
	for ty in types.keys():
		var p := "res://assets/nature/%s.glb" % ty
		if ResourceLoader.exists(p):
			var sc: Node3D = load(p).instantiate()
			var mi := sc.find_children("*", "MeshInstance3D", true, false)
			if mi.size() > 0:
				meshes[ty] = (mi[0] as MeshInstance3D).mesh
				MatLib.apply_mesh(meshes[ty])
			sc.free()
	# bucket by chunk & type
	var buckets := {}
	for t in trees:
		if not meshes.has(t[3]):
			continue
		var key := Vector3i(int(floor(t[0] / TREE_CHUNK)), int(floor(t[2] / TREE_CHUNK)), 0)
		var bk: Dictionary = buckets.get_or_add(key, {})
		(bk.get_or_add(t[3], []) as Array).append(t)
	_trunk_shape = PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(_trunk_shape, {"radius": 0.3, "height": 5.0})
	var space := get_world_3d().space
	for key in buckets.keys():
		var center := Vector3((key.x + 0.5) * TREE_CHUNK, 0, (key.y + 0.5) * TREE_CHUNK)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_tree_bodies.append(body)
		for ty in buckets[key].keys():
			var arr: Array = buckets[key][ty]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[ty]
			mm.instance_count = arr.size()
			for i in range(arr.size()):
				var t: Array = arr[i]
				var s: float = t[4]
				var p := Vector3(t[0], world.terrain.height_at(t[0], t[2]) - 0.15, t[2])
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t[5]).scaled(Vector3(s, s, s)), p - center))
				if ty != "apple":
					PhysicsServer3D.body_add_shape(body, _trunk_shape, Transform3D(Basis.IDENTITY, p + Vector3.UP * 2.5))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			mmi.visibility_range_end = 1300.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)
			_tree_mmis.append(mmi)


func _exit_tree() -> void:
	for b in _tree_bodies:
		PhysicsServer3D.free_rid(b)
	_tree_bodies.clear()
	if _trunk_shape.is_valid():
		PhysicsServer3D.free_rid(_trunk_shape)


# ------------------------------------------------------------------ grass & crops (GPU particles placed around the camera)
func _build_vegetation_particles() -> void:
	var t: Terrain = world.terrain
	var specs := [
		{"name": "grass", "mesh": _grass_mesh(0.42, 0.6, Color(1, 1, 1), "res://assets/textures/grass_blades.png"), "spacing": 0.5, "radius": 42.0, "mode": 0},
		{"name": "wheat", "mesh": _grass_mesh(0.95, 0.7, Color(1, 1, 1), "res://assets/textures/wheat_blades.png"), "spacing": 0.42, "radius": 48.0, "mode": 1},
		{"name": "sunflower", "mesh": _sunflower_mesh(), "spacing": 0.7, "radius": 75.0, "mode": 2},
	]
	for sp in specs:
		var gp := GPUParticles3D.new()
		gp.name = sp.name
		var side := int(sp.radius * 2.0 / sp.spacing)
		gp.amount = side * side
		gp.lifetime = 1.0
		gp.explosiveness = 1.0
		gp.fixed_fps = 0
		gp.interpolate = false
		gp.fract_delta = false
		gp.local_coords = false
		gp.visibility_aabb = AABB(Vector3(-sp.radius, -200, -sp.radius), Vector3(sp.radius * 2, 400, sp.radius * 2))
		var pm := ShaderMaterial.new()
		pm.shader = load("res://shaders/veg_particles.gdshader")
		pm.set_shader_parameter("heightmap", t.material.get_shader_parameter("heightmap"))
		pm.set_shader_parameter("splatmap", t.material.get_shader_parameter("splatmap"))
		pm.set_shader_parameter("fieldmap", t.material.get_shader_parameter("fieldmap"))
		pm.set_shader_parameter("deformmap", t.material.get_shader_parameter("deformmap"))
		pm.set_shader_parameter("spacing", sp.spacing)
		pm.set_shader_parameter("side", side)
		pm.set_shader_parameter("mode", sp.mode)
		pm.set_shader_parameter("water_level", t.water_level)
		gp.process_material = pm
		gp.draw_pass_1 = sp.mesh
		gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gp)
		_grass.append(gp)
		_grass_base[gp] = sp


func _grass_mesh(h: float, w: float, col: Color, tex: String) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(3):
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var lean := Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * 0.05
		var quad := [[-d, Vector2(0, 1)], [d, Vector2(1, 1)], [d + Vector3.UP * h + lean, Vector2(1, 0)], [-d, Vector2(0, 1)], [d + Vector3.UP * h + lean, Vector2(1, 0)], [-d + Vector3.UP * h + lean, Vector2(0, 0)]]
		for v in quad:
			st.set_uv(v[1])
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.add_vertex(v[0])
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("base_color", col)
	mat.set_shader_parameter("tex", load(tex))
	mat.set_shader_parameter("use_tex", true)
	m.surface_set_material(0, mat)
	return m


func _sunflower_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.3, 0.45, 0.15)
	var leaf := Color(0.25, 0.42, 0.12)
	var petal := Color(0.98, 0.78, 0.08)
	var disc := Color(0.25, 0.15, 0.05)
	var H := 1.6
	_quad(st, Vector3(-0.03, 0, 0), Vector3(0.03, 0, 0), Vector3(0.03, H, 0), Vector3(-0.03, H, 0), stem)
	_quad(st, Vector3(0, 0, -0.03), Vector3(0, 0, 0.03), Vector3(0, H, 0.03), Vector3(0, H, -0.03), stem)
	for k in range(3):
		var a := k * 2.1
		var y := 0.5 + k * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		_quad(st, Vector3(0, y, 0), d * 0.3 + Vector3(0, y + 0.05, 0) + d.cross(Vector3.UP) * 0.1, d * 0.38 + Vector3(0, y + 0.1, 0), d * 0.3 + Vector3(0, y + 0.05, 0) - d.cross(Vector3.UP) * 0.1, leaf)
	# head facing +z (east-ish after random rotation) tilted down a bit
	var c := Vector3(0, H, 0.06)
	var n := 10
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector3(cos(a0), sin(a0), 0) * 0.12
		var p1 := c + Vector3(cos(a1), sin(a1), 0) * 0.12
		_tri(st, c + Vector3(0, 0, 0.02), p0, p1, disc)
		var q0 := c + Vector3(cos(a0), sin(a0), -0.02) * 0.24
		var q1 := c + Vector3(cos(a1), sin(a1), -0.02) * 0.24
		var mid := c + Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), -0.01) * 0.3
		_tri(st, p0, mid, p1, petal)
		_tri(st, p0, q0, mid, petal)
		_tri(st, p1, mid, q1, petal)
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("base_color", Color(1, 1, 1))
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("sway", 0.03)
	m.surface_set_material(0, mat)
	return m


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		st.set_color(col)
		st.set_uv(Vector2(0.5, 1.0 - clampf(v.y / 1.6, 0, 1)))
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


func apply_settings(s: Dictionary) -> void:
	var g: float = s.grass
	for gp in _grass:
		var sp: Dictionary = _grass_base[gp]
		gp.visible = g > 0.05
		var mul := clampf(g, 0.2, 1.6)
		var radius: float = sp.radius * sqrt(mul)
		var side := int(radius * 2.0 / sp.spacing)
		if sp.mode == 0:
			side = int(radius * 2.0 / sp.spacing)
		gp.amount = side * side
		(gp.process_material as ShaderMaterial).set_shader_parameter("side", side)
		gp.visibility_aabb = AABB(Vector3(-radius, -200, -radius), Vector3(radius * 2, 400, radius * 2))
		gp.restart()
	var vd: float = s.view_distance
	for m in _tree_mmis:
		m.visibility_range_end = 1300.0 * vd


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for gp in _grass:
		gp.global_position = Vector3(cam.global_position.x, 0, cam.global_position.z)
		(gp.process_material as ShaderMaterial).set_shader_parameter("cam_pos", cam.global_position)
