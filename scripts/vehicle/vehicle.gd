extends RigidBody3D
class_name Vehicle
## Raycast-wheel vehicle with a simulated drivetrain, modular parts, fluids and mud physics.

signal entered(v: Vehicle)
signal exited(v: Vehicle)

const SUBSTEPS := 6
const G := 9.81

var vid := ""
var def: Dictionary = {}
var meta: Dictionary = {}
var cls := "small"
var model: Node3D
var body_mesh: MeshInstance3D
var hood_node: Node3D
var interior: Node3D
var steer_node: Node3D
var needles := {}
var paint := 0
var owned := true
var for_sale_price := 0

# --- parts / slots
var slots := {}                 # name -> PartSlot
var wheels: Array[Dictionary] = []

# --- driver state
var driver: Node = null
var hood_open := false
var _shell_mats: Array[BaseMaterial3D] = []
var _hood_angle := 0.0
var camera_mode := 0           # 0 first person, 1 third person
var fp_cam: Camera3D
var tp_cam: Camera3D
var _tp_yaw := 0.0
var _tp_pitch := -0.25
var _tp_idle := 0.0
var _steer_base := Basis()
var _steer_axis := Vector3.BACK
var _tp_smooth := Vector3(0, 2, 6)
var _fp_yaw := 0.0
var _fp_pitch := 0.0

# --- inputs
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := 0.0
var steer_angle := 0.0

# --- drivetrain
var gears: Dictionary
var gear := 1                   # index into ratios: 0 R, 1 N, 2.. forward
var clutch := 0.0
var shift_timer := 0.0
var engine_rpm := 0.0
var engine_omega := 0.0
var running := false
var ignition := 0               # 0 off, 1 on
var cranking := false
var _ign_hold := 0.0
var awd := false
var low_range := false
var diff_lock := false
var auto_gearbox := true
var throttle_eff := 0.0
var misfire := 0.0
var power_factor := 0.0       # combined output multiplier from part condition (debug / HUD)
var misfire_count := 0
var lights_on := false

# --- fluids & status
var fuel := 20.0
var oil := 3.5
var coolant := 5.0
const OIL_CAP := 4.0
const COOLANT_CAP := 6.0
var temp := 20.0
var odometer := 0.0
var speed_kmh := 0.0
var cargo: Array = []           # [{good, units, cond, job}]
var trunk: Array = []           # stored item data dictionaries (parts, cans, tools)
var cargo_cond_hit := 0.0
var _prev_vel := Vector3.ZERO
var _cargo_nodes: Node3D
var _lights: Array[Light3D] = []
var _brake_light: OmniLight3D
var _audio_engine: AudioStreamPlayer3D
var _audio_fx: AudioStreamPlayer3D
var _audio_skid: AudioStreamPlayer3D
var terrain: Terrain
var _ray_params: PhysicsRayQueryParameters3D
var wr := 0.33
var water_level := 4.0
var _interact_hood: Area3D
var _interact_door: Area3D
var _interact_fuel: Area3D
var _wheel_ground := 0
var _rest_t := 0.0


func setup(p_vid: String, p_paint: int = 0) -> void:
	vid = p_vid
	def = DB.VEHICLES[vid]
	meta = DB.vehicle_meta(vid)
	cls = def.cls
	gears = DB.GEARS[def.gears]
	paint = p_paint
	auto_gearbox = Game.settings.auto_gearbox
	awd = def.drive == "awd"
	name = "Vehicle_" + vid
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	can_sleep = true
	continuous_cd = false
	contact_monitor = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	angular_damp = 0.25
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	set_meta("vehicle", true)
	_build_model()
	_build_wheels()
	_build_slots()
	_build_interact_areas()
	_build_lights_audio()
	_build_cameras()
	_cargo_nodes = Node3D.new()
	_cargo_nodes.name = "Cargo"
	add_child(_cargo_nodes)
	recompute_mass()


func _ready() -> void:
	terrain = get_tree().get_first_node_in_group("terrain")
	_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.collision_mask = 1 | (1 << 1)
	_ray_params.exclude = [get_rid()]
	if terrain:
		water_level = terrain.water_level


# ------------------------------------------------------------------ construction
func _build_model() -> void:
	var ps: PackedScene = load("res://assets/vehicles/%s/%s.glb" % [vid, vid])
	model = ps.instantiate()
	model.name = "Model"
	add_child(model)
	body_mesh = model.find_child("body", true, false) as MeshInstance3D
	hood_node = model.find_child("hood", true, false)
	interior = model.find_child("interior", true, false)
	steer_node = model.find_child("steer", true, false)
	for k in ["speed", "rpm", "fuel", "temp"]:
		var n := model.find_child("needle_" + k, true, false)
		if n:
			needles[k] = n
	# materials: everything double-sided (the source models are open single-sided shells:
	# hood underside, engine bay and wheel arches would be see-through otherwise). Only the
	# body shell switches to back-face culling while sitting inside, so you can see out of it.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in range(m.mesh.get_surface_count()):
			var mat := m.mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var nm: BaseMaterial3D = mat.duplicate()
				nm.cull_mode = BaseMaterial3D.CULL_DISABLED
				if m.name.begins_with("body"):
					_shell_mats.append(nm)
				if m.name.begins_with("body") or m.name == "hood":
					nm.roughness = 0.42
					nm.metallic_specular = 0.6
					if meta.get("cutout", false):
						nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						nm.alpha_scissor_threshold = 0.5
				m.set_surface_override_material(s, nm)
	_apply_interior_materials()
	apply_paint(paint)
	# collision: convex hull of the body + bed if any
	var cs := CollisionShape3D.new()
	cs.shape = body_mesh.mesh.create_convex_shape(true, true)
	cs.transform = body_mesh.transform
	add_child(cs)
	var bed := model.find_child("bed", true, false) as MeshInstance3D
	if bed:
		var cb := CollisionShape3D.new()
		cb.shape = bed.mesh.create_convex_shape(true, true)
		cb.transform = bed.transform
		add_child(cb)
	if interior:
		interior.visible = false
	if steer_node:
		steer_node.visible = false
	for n in needles.values():
		n.visible = false


func _apply_interior_materials() -> void:
	if interior == null:
		return
	var mi := interior as MeshInstance3D
	var fabric := StandardMaterial3D.new()
	fabric.albedo_texture = load("res://assets/textures/fabric_c.jpg")
	fabric.normal_enabled = true
	fabric.normal_texture = load("res://assets/textures/fabric_n.jpg")
	fabric.uv1_triplanar = true
	fabric.uv1_scale = Vector3(3, 3, 3)
	fabric.albedo_color = Color(0.75, 0.6, 0.55)
	var gauge := StandardMaterial3D.new()
	gauge.albedo_texture = _gauge_texture()
	gauge.emission_enabled = true
	gauge.emission = Color(0.12, 0.1, 0.06)
	for s in range(mi.mesh.get_surface_count()):
		var mname := String(mi.mesh.surface_get_material(s).resource_name) if mi.mesh.surface_get_material(s) else ""
		if mname == "int_fabric":
			mi.set_surface_override_material(s, fabric)
		elif mname == "gauge":
			mi.set_surface_override_material(s, gauge)


static var _gauge_tex: Texture2D


func _gauge_texture() -> Texture2D:
	if _gauge_tex:
		return _gauge_tex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.08, 0.08))
	for a in range(0, 271, 27):
		var ang := deg_to_rad(225.0 - a)
		for r in range(46, 58):
			img.set_pixel(64 + int(cos(ang) * r), 64 - int(sin(ang) * r), Color(0.95, 0.95, 0.9))
	for a in range(0, 271, 9):
		var ang := deg_to_rad(225.0 - a)
		for r in range(52, 58):
			img.set_pixel(64 + int(cos(ang) * r), 64 - int(sin(ang) * r), Color(0.8, 0.8, 0.75))
	_gauge_tex = ImageTexture.create_from_image(img)
	return _gauge_tex


func apply_paint(idx: int) -> void:
	paint = idx
	var variants: Array = meta.get("variants", [])
	if variants.is_empty() or body_mesh == null:
		return
	var tex: Texture2D = load("res://assets/vehicles/%s/%s" % [vid, variants[idx % variants.size()]])
	for target in [body_mesh, hood_node]:
		var m := target as MeshInstance3D
		if m == null:
			continue
		for s in range(m.mesh.get_surface_count()):
			var mat := m.get_surface_override_material(s) as BaseMaterial3D
			if mat and mat.albedo_texture:
				mat.albedo_texture = tex


func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _build_wheels() -> void:
	var susp: float = def.susp
	var n: int = meta.wheels.size()
	var rmax := 0.0
	for w in meta.wheels:
		rmax = maxf(rmax, w.radius)
	wr = rmax
	var axles := {}
	for w in meta.wheels:
		axles[int(w.axle)] = true
	var n_axles := axles.size()
	var m_share: float = def.mass / n
	var k: float = (m_share * G) / (0.42 * susp) * float(def.spring)
	for i in range(n):
		var w: Dictionary = meta.wheels[i]
		var pos := _v3(w.pos)
		var wd := {
			"i": i, "center": pos, "top": pos + Vector3.UP * susp * 0.58, "susp": susp, "radius": float(w.radius),
			"width": float(w.width), "axle": int(w.axle), "side": int(w.side), "steer": int(w.axle) == 0,
			"k": k, "c": 2.0 * 0.38 * sqrt(k * m_share), "comp": 0.0, "omega": 0.0, "spin": 0.0,
			"grounded": false, "fz": 0.0, "sink": 0.0, "slip": 0.0, "surface": {}, "contact": Vector3.ZERO,
			"normal": Vector3.UP, "fx": 0.0, "fy": 0.0, "visual": null, "rear": int(w.axle) == n_axles - 1 or (n_axles > 2 and int(w.axle) > 0),
			"driven_rwd": int(w.axle) > 0, "vlong": 0.0, "dist": susp * 0.58 + float(w.radius),
		}
		var vis := Node3D.new()
		vis.name = "WheelVis%d" % i
		add_child(vis)
		vis.position = pos
		wd.visual = vis
		var hub := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.1
		cm.height = 0.08
		hub.mesh = cm
		hub.rotation.z = PI / 2
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.25, 0.22, 0.2)
		hm.metallic = 0.8
		hub.material_override = hm
		vis.add_child(hub)
		wheels.append(wd)


func _bay() -> AABB:
	var mn := _v3(meta.bay.min)
	var mx := _v3(meta.bay.max)
	var a := Vector3(minf(mn.x, mx.x), minf(mn.y, mx.y), minf(mn.z, mx.z))
	var b := Vector3(maxf(mn.x, mx.x), maxf(mn.y, mx.y), maxf(mn.z, mx.z))
	return AABB(a, b - a)


func _add_slot(sname: String, pos: Vector3, size: Vector3, parent: PartSlot = null, hood := true) -> PartSlot:
	var s := PartSlot.new()
	s.setup(sname, self, size)
	s.needs_hood = hood
	if parent:
		parent.mount.add_child(s)
		s.parent_slot = parent
		parent.child_slots.append(s)
	else:
		add_child(s)
	s.position = pos
	s.changed.connect(_on_slot_changed)
	slots[sname] = s
	return s


func _build_slots() -> void:
	var b := _bay()
	var y0 := b.position.y
	var h := b.size.y
	var zf := b.position.z
	var zr := b.end.z
	var lb := b.size.z
	var es := 1.0 if cls == "small" else 1.25
	var fit := clampf((h - 0.02) / (0.66 * es), 0.55, 1.0)
	var engine := _add_slot("engine", Vector3(0, y0 + 0.02, zf + lb * 0.55), Vector3(0.4, 0.55, 0.5) * es * fit)
	engine.model_scale = Vector3.ONE * fit
	engine.mount.position = Vector3.ZERO
	var eh := 0.66 * es * fit
	var gb := _add_slot("gearbox", Vector3(0, y0 + 0.02, zr - 0.12), Vector3(0.36, 0.34, 0.4) * es)
	gb.model_scale = Vector3.ONE * minf(1.0, fit + 0.1)
	var rad := _add_slot("radiator", Vector3(0, y0 + 0.02, zf + 0.07), Vector3(minf(0.66, b.size.x - 0.06), minf(0.46, h - 0.04), 0.12))
	rad.model_scale = Vector3(minf(1.0, (b.size.x - 0.08) / 0.64), minf(1.0, (h - 0.06) / 0.46), 1.0)
	_add_slot("battery", Vector3(b.end.x - 0.15, y0 + h * 0.3, zr - 0.26), Vector3(0.26, 0.22, 0.2))
	_add_slot("ignition_coil", Vector3(b.position.x + 0.09, y0 + h * 0.4, zf + lb * 0.35), Vector3(0.1, 0.18, 0.1))
	var s: float = fit * es
	var carb := _add_slot("carburetor", Vector3(-0.23 * s, 0.5 * s, 0.0), Vector3(0.14, 0.16, 0.14), engine)
	_add_slot("air_filter", Vector3(0, 0.145, 0), Vector3(0.3, 0.1, 0.3), carb)
	_add_slot("spark_plugs", Vector3(0, 0.62 * s, -0.04), Vector3(0.18, 0.1, 0.08), engine)
	_add_slot("alternator", Vector3(0.19 * s, 0.3 * s, -0.17 * s), Vector3(0.16, 0.18, 0.16), engine)
	_add_slot("starter", Vector3(-0.18 * s, 0.1 * s, 0.17 * s), Vector3(0.12, 0.12, 0.22), engine)
	# under-body parts
	var rear_z := -1e9
	for w in wheels:
		rear_z = maxf(rear_z, w.center.z)
	var tank := _add_slot("fuel_tank", Vector3(0, wr * 0.55, rear_z + 0.55 if cls == "small" else rear_z - 1.2), Vector3(0.84, 0.3, 0.5), null, false)
	if cls == "big":
		tank.position.x = -0.75
	var ex := _add_slot("exhaust", Vector3(0.35, wr * 0.45, rear_z - 0.05), Vector3(0.26, 0.24, 0.9), null, false)
	ex.model_rot = Vector3(0, 0, 0)
	# wheels
	for w in wheels:
		var ws := _add_slot("wheel%d" % w.i, Vector3.ZERO, Vector3(w.width + 0.1, w.radius * 2.0, w.radius * 2.0), null, false)
		remove_child(ws)
		w.visual.add_child(ws)
		ws.position = Vector3.ZERO
		var sc: float = w.radius / 0.33
		ws.model_scale = Vector3(clampf(w.width / 0.2, 0.8, 1.6), sc, sc)
		if w.side < 0:
			ws.model_rot = Vector3(0, PI, 0)
		w.slot = ws
	for sl in slots.values():
		sl.update_enabled()


func _build_interact_areas() -> void:
	var b := _bay()
	_interact_hood = _mk_area("hood", Vector3(0, b.end.y + 0.02, b.get_center().z), Vector3(b.size.x + 0.1, 0.32, b.size.z + 0.05))
	if hood_node:
		var xf := _interact_hood.transform
		remove_child(_interact_hood)
		hood_node.add_child(_interact_hood)
		_interact_hood.transform = hood_node.transform.affine_inverse() * model.transform.affine_inverse() * xf
	var seat := _v3(meta.seat)
	var W: float = meta.width
	_interact_door = _mk_area("door", Vector3(-W * 0.5, seat.y + 0.35, seat.z), Vector3(0.35, 1.1, 1.1))
	var rear_z := 0.0
	for w in wheels:
		rear_z = maxf(rear_z, w.center.z)
	_interact_fuel = _mk_area("fuel_cap", Vector3(-W * 0.5, wr * 2.2, rear_z + 0.15), Vector3(0.3, 0.35, 0.4))
	var rp := _v3(meta.rear)
	_mk_area("trunk", Vector3(0, maxf(wr * 2.4, rp.y + 0.3), rp.z - 0.45), Vector3(W * 0.7, 0.6, 0.5))


func _mk_area(kind: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = "Interact_" + kind
	a.collision_layer = 1 << 4
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.position = pos
	a.set_meta("vehicle_action", kind)
	a.set_meta("vehicle_ref", self)
	add_child(a)
	return a


func _build_lights_audio() -> void:
	var front_z := 1e9
	for w in wheels:
		front_z = minf(front_z, w.center.z)
	var L: float = meta.length
	var W: float = meta.width
	for sx in [-1, 1]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(sx * W * 0.32, wr * 1.9, -L * 0.5 + 0.05)
		sl.spot_range = 70.0
		sl.spot_angle = 32.0
		sl.spot_attenuation = 0.6
		sl.light_energy = 6.0
		sl.light_color = Color(1.0, 0.93, 0.78)
		sl.shadow_enabled = sx < 0
		sl.visible = false
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = 120.0
		add_child(sl)
		_lights.append(sl)
	_brake_light = OmniLight3D.new()
	_brake_light.position = Vector3(0, wr * 2.0, L * 0.5 + 0.2)
	_brake_light.light_color = Color(1, 0.1, 0.05)
	_brake_light.omni_range = 3.0
	_brake_light.light_energy = 0.0
	add_child(_brake_light)
	_audio_engine = AudioStreamPlayer3D.new()
	var es: AudioStreamOggVorbis = load("res://assets/sounds/Car2_Engine_Loop.ogg" if cls == "big" else "res://assets/sounds/Car_Engine_Loop.ogg").duplicate()
	es.loop = true
	_audio_engine.stream = es
	_audio_engine.unit_size = 8.0
	_audio_engine.max_db = 3.0
	_audio_engine.position = _bay().get_center()
	add_child(_audio_engine)
	_audio_fx = AudioStreamPlayer3D.new()
	_audio_fx.unit_size = 6.0
	add_child(_audio_fx)
	_audio_skid = AudioStreamPlayer3D.new()
	add_child(_audio_skid)


func _build_cameras() -> void:
	fp_cam = Camera3D.new()
	fp_cam.name = "FPCam"
	fp_cam.position = _v3(meta.eye)
	fp_cam.near = 0.03
	fp_cam.far = 3000.0
	fp_cam.top_level = true
	fp_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(fp_cam)
	tp_cam = Camera3D.new()
	tp_cam.name = "TPCam"
	tp_cam.top_level = true
	tp_cam.near = 0.1
	tp_cam.far = 3000.0
	tp_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(tp_cam)


func play_fx(path: String, vol := 0.0) -> void:
	_audio_fx.stream = load(path)
	_audio_fx.volume_db = vol
	_audio_fx.play()


# ------------------------------------------------------------------ parts helpers
func slot_q(sname: String) -> float:
	var s: PartSlot = slots.get(sname)
	return s.quality() if s else 0.0


func has(sname: String) -> bool:
	var s: PartSlot = slots.get(sname)
	return s != null and s.is_installed()


func engine_def() -> Dictionary:
	return DB.part(slots.engine.part_id()) if has("engine") else {}


func battery_charge() -> float:
	return float(slots.battery.data.get("charge", 0.0)) if has("battery") else 0.0


func _battery_add(v: float) -> void:
	if has("battery"):
		var d: Dictionary = slots.battery.data
		d.charge = clampf(float(d.get("charge", 0.0)) + v, 0.0, 100.0 * slots.battery.cond() / 100.0 + 0.001)


func _on_slot_changed(_s: PartSlot) -> void:
	recompute_mass()
	if not has("engine") and running:
		_stall("")
	if not has("fuel_tank"):
		fuel = 0.0


func recompute_mass() -> void:
	var m: float = def.mass
	var com := Vector3(0, wr * 1.25, 0)
	var wsum := m
	var front_z := 0.0
	var rear_z := 0.0
	for w in wheels:
		front_z = minf(front_z, w.center.z)
		rear_z = maxf(rear_z, w.center.z)
	com.z = (front_z + rear_z) * 0.5
	com *= m
	for s in slots.values():
		if s.is_installed():
			var pm: float = DB.part(s.part_id()).get("mass", 5.0)
			m += pm
			com += s.global_position * 0.0 + (to_local(s.global_position) if is_inside_tree() else s.position) * pm
			wsum += pm
	for c in cargo:
		var gm: float = DB.GOODS[c.good].mass * c.units
		m += gm
		var cg: Dictionary = meta.get("cargo") if meta.get("cargo") else {}
		var cpos := _v3(cg.c) if cg.has("c") else Vector3(0, wr * 2, rear_z)
		com += cpos * gm
		wsum += gm
	m += fuel * 0.75
	for d in trunk:
		m += float(DB.part(d.id).get("mass", 2.0))
	mass = m
	var c := com / wsum
	c.y = minf(c.y, wr * 1.45)
	center_of_mass = c
	var L: float = meta.length
	var W: float = meta.width
	var H: float = meta.height * 0.7
	inertia = Vector3(m / 12.0 * (H * H + L * L), m / 12.0 * (W * W + L * L), m / 12.0 * (W * W + H * H)) * 1.05
	# springs follow the real load
	var share := m / wheels.size()
	for w in wheels:
		w.k = (share * G) / (0.42 * w.susp) * float(def.spring)
		w.c = 2.0 * 0.4 * sqrt(w.k * share)


# ------------------------------------------------------------------ driver
func enter(p: Node) -> void:
	driver = p
	can_sleep = false
	sleeping = false
	camera_mode = 0
	_fp_yaw = 0.0
	_fp_pitch = 0.0
	_tp_yaw = 0.0
	auto_gearbox = Game.settings.auto_gearbox
	_set_camera()
	entered.emit(self)
	play_fx("res://assets/sounds/Car_Door_Close.ogg", -6)


func exit_vehicle() -> Vector3:
	var p := driver
	driver = null
	can_sleep = true
	in_throttle = 0.0
	in_brake = 0.0
	in_steer = 0.0
	in_handbrake = 1.0 if speed_kmh < 3.0 else 0.0
	fp_cam.current = false
	tp_cam.current = false
	_set_shell_cull(false)
	if interior:
		interior.visible = false
		steer_node.visible = false
		for n in needles.values():
			n.visible = false
	exited.emit(self)
	play_fx("res://assets/sounds/Car_Door_Open.ogg", -6)
	# find exit position
	var cands := [_v3(meta.exit), _v3(meta.exit) * Vector3(-1, 1, 1), _v3(meta.rear), Vector3(0, meta.height + 0.6, 0)]
	for c in cands:
		var gp: Vector3 = global_transform * c
		if terrain:
			gp.y = maxf(gp.y, terrain.height_at(gp.x, gp.z) + 0.2)
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.7
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, gp + Vector3.UP * 0.95)
		q.collision_mask = 1 | 2
		if get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return gp
	return global_transform * Vector3(0, meta.height + 0.5, 0)


func _set_shell_cull(inside: bool) -> void:
	for m in _shell_mats:
		m.cull_mode = BaseMaterial3D.CULL_BACK if inside else BaseMaterial3D.CULL_DISABLED


func _set_camera() -> void:
	var fp := camera_mode == 0
	_set_shell_cull(fp)
	fp_cam.current = fp
	tp_cam.current = not fp
	fp_cam.fov = Game.settings.fov
	tp_cam.fov = Game.settings.fov
	if interior:
		interior.visible = fp
		steer_node.visible = fp
		for n in needles.values():
			n.visible = fp


func toggle_hood() -> void:
	hood_open = not hood_open
	play_fx("res://assets/sounds/Car_Hood_Open.ogg" if hood_open else "res://assets/sounds/Car_Hood_Close.ogg", -4)
	for s in slots.values():
		s.update_enabled()


func _unhandled_input(event: InputEvent) -> void:
	if driver == null or Game.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Game.settings.sensitivity * 0.01
		var inv := -1.0 if Game.settings.invert_y else 1.0
		if camera_mode == 0:
			_fp_yaw = clampf(_fp_yaw - event.relative.x * sens, -2.6, 2.6)
			_fp_pitch = clampf(_fp_pitch - event.relative.y * sens * inv, -1.2, 1.0)
		else:
			_tp_yaw -= event.relative.x * sens
			_tp_pitch = clampf(_tp_pitch - event.relative.y * sens * inv, -1.2, 0.5)
			_tp_idle = 0.0
	if event.is_action_pressed("camera"):
		camera_mode = 1 - camera_mode
		_set_camera()
	elif event.is_action_pressed("lights"):
		lights_on = not lights_on
	elif event.is_action_pressed("horn"):
		if battery_charge() > 2:
			play_fx("res://assets/sounds/Car_Horn.ogg", -2)
	elif event.is_action_pressed("diff_lock"):
		diff_lock = not diff_lock
		Game.notify("Differential lock " + ("ON" if diff_lock else "OFF"))
	elif event.is_action_pressed("drive_mode"):
		_cycle_drive_mode()
	elif event.is_action_pressed("gearbox_mode"):
		auto_gearbox = not auto_gearbox
		Game.settings.auto_gearbox = auto_gearbox
		Game.notify("Gearbox: " + ("Automatic" if auto_gearbox else "Manual"))
	elif event.is_action_pressed("shift_up") and not auto_gearbox:
		_shift(gear + 1)
	elif event.is_action_pressed("shift_down") and not auto_gearbox:
		_shift(gear - 1)
	elif event.is_action_pressed("reset_vehicle"):
		reset_upright()


func _cycle_drive_mode() -> void:
	if not def.get("can_awd", false) and not def.get("low", false):
		Game.notify("This vehicle has no transfer case")
		return
	if def.drive == "awd":
		low_range = not low_range if def.get("low", false) else false
	elif not awd:
		awd = true
		low_range = false
	elif awd and not low_range and def.get("low", false):
		low_range = true
	else:
		awd = false
		low_range = false
	Game.notify("Drive: " + drive_mode_text())


func drive_mode_text() -> String:
	var s: String = "AWD" if awd else def.drive.to_upper()
	if low_range:
		s += " LOW"
	return s


func gear_text() -> String:
	if gear == 0:
		return "R"
	if gear == 1:
		return "N"
	return str(gear - 1)


var _grind_msg_ms := -100000


func _shift(g: int) -> void:
	var ratios: Array = gears.ratios
	g = clampi(g, 0, ratios.size() - 1)
	if g == gear:
		return
	if not has("gearbox"):
		return
	# grinding into reverse at speed
	if g == 0 and speed_kmh > 8.0:
		var now := Time.get_ticks_msec()
		if now - _grind_msg_ms > 2500:
			_grind_msg_ms = now
			Game.notify("Gears grind! Stop before reverse", "warn")
		return
	gear = g
	shift_timer = 0.28 if auto_gearbox else 0.2


func reset_upright() -> void:
	if speed_kmh > 5.0:
		return
	var t := global_transform
	var fwd := -t.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var p := t.origin
	if terrain:
		p.y = terrain.height_at(p.x, p.z) + 1.0
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


# ------------------------------------------------------------------ simulation
func _read_input(delta: float) -> void:
	if driver == null or Game.ui_open:
		in_throttle = move_toward(in_throttle, 0.0, delta * 4)
		in_brake = 0.0
		in_steer = move_toward(in_steer, 0.0, delta * 3)
		return
	var thr := Input.get_action_strength("forward")
	var brk := Input.get_action_strength("back")
	var st := Input.get_action_strength("right") - Input.get_action_strength("left")
	in_handbrake = Input.get_action_strength("handbrake")
	var fwd_speed := -linear_velocity.dot(global_basis.z)
	if auto_gearbox:
		if gear == 0:
			# in reverse: S is throttle, W brakes then selects drive
			var t2 := brk
			brk = thr
			thr = t2
			if brk > 0.1 and fwd_speed > -0.5:
				_shift(2)
		elif brk > 0.1 and absf(fwd_speed) < 0.6 and speed_kmh < 6.0 and thr < 0.05:
			# only once (nearly) stopped: rolling back down a hill or sliding sideways, S just brakes
			# (it used to try reverse every frame there and spam "Gears grind!")
			_shift(0)
			brk = 0.0
		elif thr > 0.05 and gear == 1:
			_shift(2)
	in_throttle = move_toward(in_throttle, thr, delta * 5.0)
	in_brake = move_toward(in_brake, brk, delta * 7.0)
	var steer_speed := 2.4 if absf(st) > 0.01 else 3.5
	in_steer = move_toward(in_steer, st, delta * steer_speed)
	# ignition: tap F toggles, hold F cranks
	if Input.is_action_pressed("ignition"):
		_ign_hold += delta
		if _ign_hold > 0.3 and not running:
			if ignition == 0:
				ignition = 1
			cranking = true
	else:
		if _ign_hold > 0.0 and _ign_hold <= 0.3:
			if running:
				_stall("Engine off")
				ignition = 0
			else:
				ignition = 1 - ignition
				if ignition == 1:
					play_fx("res://assets/sounds/Car_Parking_Brake.ogg", -14)
		_ign_hold = 0.0
		cranking = false


func _torque_curve(rpm: float, e: Dictionary) -> float:
	var peak: float = e.rpm_peak
	var red: float = e.redline
	var t: float
	if rpm < peak:
		t = lerpf(0.55, 1.0, sqrt(clampf(rpm / peak, 0.0, 1.0)))
	else:
		t = lerpf(1.0, 0.72, clampf((rpm - peak) / (red - peak), 0.0, 1.0))
	return t * float(e.torque)


func can_run() -> bool:
	return has("engine") and slots.engine.cond() > 0.5 and has("carburetor") and has("fuel_tank") and fuel > 0.05 \
		and has("ignition_coil") and has("spark_plugs") and (battery_charge() > 1.0 or (running and has("alternator")))


func _stall(msg: String) -> void:
	if running:
		running = false
		play_fx("res://assets/sounds/Car_Engine_Turning_Off.ogg", -4)
		if msg != "" and driver:
			Game.notify(msg, "warn")


func _physics_process(dt: float) -> void:
	if wheels.is_empty():
		return
	_read_input(dt)
	_update_hood(dt)
	if driver == null and not running and not cranking:
		if sleeping:
			return
		if linear_velocity.length() < 0.06 and angular_velocity.length() < 0.06 and _wheel_ground >= wheels.size() - 1:
			_rest_t += dt
			if _rest_t > 1.5:
				sleeping = true
				return
		else:
			_rest_t = 0.0
	else:
		_rest_t = 0.0
		if sleeping:
			sleeping = false
	var e := engine_def()
	var ratios: Array = gears.ratios
	# ---------- steering
	var spd := linear_velocity.length()
	speed_kmh = spd * 3.6
	var steer_max := deg_to_rad(def.steer) * lerpf(1.0, 0.32, clampf(spd / 28.0, 0.0, 1.0))
	steer_angle = -in_steer * steer_max
	# ---------- engine: starter & ignition
	var bat := battery_charge()
	if ignition == 1:
		_battery_add(-0.01 * dt)
	if lights_on and bat > 3.0:
		_battery_add(-0.03 * dt)
	var starter_t := 0.0
	if cranking and not running:
		if has("starter") and bat > 8.0 and has("engine"):
			starter_t = 70.0 * float(DB.part(slots.starter.part_id()).get("crank", 1.0)) * float(DB.part(slots.battery.part_id()).get("crank", 1.0)) * slot_q("starter") * (1.0 if cls == "small" else 3.5) * clampf(bat / 40.0, 0.3, 1.0)
			_battery_add(-1.4 * dt)
			if engine_rpm > 140.0 and can_run():
				var p := 0.35 + 1.6 * slot_q("ignition_coil") * slot_q("spark_plugs") * clampf(slot_q("carburetor") + 0.2, 0.0, 1.0)
				if randf() < p * dt * 2.0:
					running = true
					cranking = false
					play_fx("res://assets/sounds/Car_Engine_Start_Up.ogg" if cls == "small" else "res://assets/sounds/Car2_Engine_Start_Up.ogg", -2)
		elif bat <= 8.0 and has("battery"):
			if Engine.get_physics_frames() % 120 == 0 and driver:
				Game.notify("Battery is flat", "warn")
	if running and (ignition == 0 or not can_run()):
		_stall("Engine died")
	# ---------- clutch / auto gearbox
	shift_timer = maxf(0.0, shift_timer - dt)
	var ratio: float = ratios[gear] * float(gears.final) * (float(gears.low) if low_range else 1.0)
	var idle: float = e.get("idle", 800.0)
	var red: float = e.get("redline", 6000.0)
	var driven: Array = []
	for w in wheels:
		var is_drv: bool = awd or (def.drive == "rwd" and w.driven_rwd) or (def.drive == "fwd" and w.axle == 0)
		if is_drv and w.slot.is_installed():
			driven.append(w)
	var wheel_avg := 0.0
	for w in driven:
		wheel_avg += w.omega
	wheel_avg = wheel_avg / maxf(1.0, driven.size())
	var shaft_rpm := absf(wheel_avg * ratio) * 60.0 / TAU
	if gear == 1 or shift_timer > 0.0 or not has("gearbox") or driven.is_empty():
		clutch = 0.0
	else:
		var slow := shaft_rpm < idle * 1.15
		if slow:
			var target := smoothstep(idle * 0.95, idle + 1100.0, engine_rpm) if in_throttle > 0.04 else 0.0
			clutch = move_toward(clutch, target, dt * 4.0)
		else:
			clutch = move_toward(clutch, 1.0, dt * 5.0)
	if auto_gearbox and gear >= 2 and shift_timer <= 0.0 and running:
		var peak: float = e.get("rpm_peak", red * 0.6)
		var up_rpm := lerpf(peak * 0.95, maxf(peak * 1.2, red * 0.78), in_throttle)
		var drv_slip := 0.0
		for w in driven:
			drv_slip = maxf(drv_slip, absf(w.omega * w.radius - w.get("vlong", 0.0)))
		if engine_rpm > up_rpm and gear < ratios.size() - 1 and clutch > 0.9 and (drv_slip < 2.5 or engine_rpm > red * 0.97) and speed_kmh > (gear - 1) * 7.0:
			_shift(gear + 1)
		elif engine_rpm < idle * 1.35 and gear > 2:
			_shift(gear - 1)
		elif in_throttle > 0.85 and gear > 2 and engine_rpm < red * 0.45:
			# kickdown only when the lower gear lands well below the upshift point (no gear hunting)
			var nr: float = ratios[gear - 1] * float(gears.final) * (float(gears.low) if low_range else 1.0)
			if absf(wheel_avg * nr) * 60.0 / TAU < maxf(peak * 1.2, red * 0.78) * 0.85:
				_shift(gear - 1)
	# ---------- suspension & contact
	var space := get_world_3d().direct_space_state
	var gb := global_basis
	var up := gb.y
	var com_g := global_transform * center_of_mass
	_wheel_ground = 0
	var n := wheels.size()
	var m_share := mass / n
	var fwd_speed := -linear_velocity.dot(gb.z)
	for w in wheels:
		var has_wheel: bool = w.slot.is_installed()
		var r: float = w.radius if has_wheel else 0.13
		var origin: Vector3 = global_transform * w.top
		var reach: float = w.susp + r + w.sink + 0.05
		_ray_params.from = origin
		_ray_params.to = origin - up * reach
		var hit := space.intersect_ray(_ray_params)
		var prev: float = w.comp
		w.grounded = false
		w.fz = 0.0
		if hit:
			var d: float = origin.distance_to(hit.position)
			var comp := clampf(w.susp + r - (d + w.sink), 0.0, w.susp + 0.15)
			var cv := (comp - prev) / dt
			var fs: float = w.k * comp + w.c * cv * (1.0 if cv > 0.0 else 1.3)
			if comp > w.susp:
				fs += w.k * 12.0 * (comp - w.susp)
			fs = maxf(fs, 0.0)
			w.comp = comp
			w.dist = d + w.sink
			w.grounded = true
			w.fz = fs
			w.contact = hit.position
			w.normal = hit.normal
			var is_terrain: bool = hit.collider != null and hit.collider.has_meta("terrain")
			if is_terrain and terrain:
				w.surface = terrain.surface(hit.position.x, hit.position.z)
			else:
				w.surface = {"kind": Terrain.Surface.CONCRETE, "mud": 0.0, "friction": 0.95, "rut": 0.0, "asphalt": 1.0}
			apply_force(up * fs, hit.position - global_position)
			_wheel_ground += 1
		else:
			w.comp = 0.0
			w.dist = w.susp + r
	# anti-roll per axle
	var axl := {}
	for w in wheels:
		axl.get_or_add(w.axle, []).append(w)
	for a in axl.values():
		if a.size() == 2:
			var diff: float = a[0].comp - a[1].comp
			var kr: float = a[0].k * 0.55
			if a[0].grounded:
				apply_force(up * diff * kr, (global_transform * a[0].top) - global_position)
			if a[1].grounded:
				apply_force(-up * diff * kr, (global_transform * a[1].top) - global_position)
	# ---------- engine torque (base, per tick)
	var e_ok := has("engine")
	var tmax: float = e.get("torque", 100.0)
	var e_inertia: float = e.get("inertia", 0.2)
	var power_mult := 0.0
	if e_ok:
		# each part's penalty is mild on its own: they multiply together, so a car with every part
		# at ~50% keeps ~70% of its power (was ~50% plus constant misfires on the starter Kombi)
		power_mult = (0.7 + 0.3 * slot_q("engine")) * (0.92 + 0.08 * slot_q("air_filter") if has("air_filter") else 0.9) \
			* (0.94 if not has("exhaust") else 1.0) * clampf(0.8 + 0.2 * slot_q("carburetor"), 0.0, 1.0)
		if oil < 0.5:
			power_mult *= 0.7
		for sn in ["carburetor", "air_filter", "spark_plugs", "ignition_coil", "exhaust"]:
			if has(sn):
				power_mult *= float(DB.part(slots[sn].part_id()).get("power", 1.0))
	power_factor = power_mult
	# misfires from worn plugs / carb / coil
	misfire = move_toward(misfire, 0.0, dt * 6.0)
	if running:
		# parts above ~75% never misfire; below that the rate climbs to ~2/s with everything dead
		var bad := _misfire_bad(slot_q("spark_plugs")) * 0.6 + _misfire_bad(slot_q("carburetor")) * 0.4 + _misfire_bad(slot_q("ignition_coil")) * 0.3
		if randf() < bad * dt * 1.5:
			misfire = 1.0
			misfire_count += 1
	# idle governor
	var idle_thr := 0.0
	if running:
		idle_thr = clampf((idle - engine_rpm) / idle * 2.5 + 0.06, 0.0, 0.45)
	throttle_eff = clampf(maxf(in_throttle if driver else 0.0, idle_thr), 0.0, 1.0) if running else 0.0
	if engine_rpm > red or (shift_timer > 0.0 and gear >= 2 and auto_gearbox):
		throttle_eff = idle_thr if running else 0.0
	# ---------- tyre forces with substeps
	var dts := dt / SUBSTEPS
	var brake_t := in_brake * (1900.0 if cls == "small" else 14000.0)
	var hb_t := in_handbrake * (2600.0 if cls == "small" else 16000.0)
	if driver == null and speed_kmh < 3.0:
		hb_t = maxf(hb_t, 1500.0 if cls == "small" else 9000.0)
	var lat := {}
	for w in wheels:
		var wd := w as Dictionary
		wd.fx = 0.0
		if not wd.grounded:
			continue
		var c: Vector3 = wd.contact
		var nrm: Vector3 = wd.normal
		var rot := Basis(up, steer_angle) if wd.steer else Basis.IDENTITY
		var fwd := (rot * -gb.z)
		fwd = (fwd - nrm * fwd.dot(nrm)).normalized()
		var right := fwd.cross(nrm)
		var v := linear_velocity + angular_velocity.cross(c - com_g)
		wd.vlong = v.dot(fwd)
		wd.vlat = v.dot(right)
		wd.fwd = fwd
		wd.right = right
		var part_def := DB.part(wd.slot.part_id()) if wd.slot.is_installed() else {}
		var sf: Dictionary = wd.surface
		var mud: float = sf.get("mud", 0.0)
		var grip_type: float = 1.0
		if not part_def.is_empty():
			grip_type = lerpf(float(part_def.grip_road) if sf.get("asphalt", 0.0) > 0.5 else float(part_def.grip_dirt), float(part_def.grip_mud), mud)
			grip_type *= 0.55 + 0.45 * clampf(wd.slot.cond() / 70.0, 0.0, 1.0)
		else:
			grip_type = 0.5
		wd.mu = float(sf.get("friction", 0.8)) * grip_type
		# mud sinking: heavier load and wheelspin dig in
		var fz_nom: float = m_share * G
		var target_sink: float = mud * 0.13 * sqrt(clampf(wd.fz / fz_nom, 0.2, 2.5)) + float(sf.get("rut", 0.0)) * 0.2
		var spin_slip: float = absf(wd.omega * wd.radius - wd.vlong)
		if mud > 0.2 and spin_slip > 1.0:
			target_sink += minf(spin_slip * 0.03, 0.18) * mud
		target_sink = minf(target_sink, wd.radius * 0.55)
		wd.sink = move_toward(wd.sink, target_sink, dt * (0.12 if target_sink > wd.sink else 0.35))
		# rolling resistance & mud drag
		var crr: float = 0.014 + mud * 0.07 + wd.sink * 0.55
		var fr: float = -signf(wd.vlong) * minf(wd.fz * crr, absf(wd.vlong) * m_share / dt * 0.5)
		apply_force(fwd * fr, c - global_position)
		# lateral
		var alpha := atan2(wd.vlat, maxf(absf(wd.vlong), 2.0))
		var fy: float = -_pacejka(alpha, 7.5, 1.45, 0.15) * wd.mu * wd.fz
		var fy_cap: float = absf(wd.vlat) * m_share / dt * 0.9
		fy = clampf(fy, -fy_cap, fy_cap)
		lat[wd.i] = fy
		# ruts
		if terrain and mud > 0.15 and (absf(wd.vlong) > 0.4 or spin_slip > 1.0):
			terrain.paint_rut(c.x, c.z, (0.004 + spin_slip * 0.004) * mud * clampf(wd.fz / fz_nom, 0.3, 2.0))
	# drivetrain substeps (typed arrays: avoids dictionary access in the hot loop)
	var n_w := wheels.size()
	var om := PackedFloat32Array()
	var rr := PackedFloat32Array()
	var vl := PackedFloat32Array()
	var muz := PackedFloat32Array()
	var iw := PackedFloat32Array()
	var tb := PackedFloat32Array()
	var isd := PackedByteArray()
	var gr := PackedByteArray()
	var fxs := PackedFloat32Array()
	om.resize(n_w)
	rr.resize(n_w)
	vl.resize(n_w)
	muz.resize(n_w)
	iw.resize(n_w)
	tb.resize(n_w)
	fxs.resize(n_w)
	isd.resize(n_w)
	gr.resize(n_w)
	var n_drv := 0
	var i_wheel_sum := 0.0
	for i in range(n_w):
		var wd: Dictionary = wheels[i]
		om[i] = wd.omega
		rr[i] = wd.radius
		vl[i] = wd.get("vlong", 0.0)
		gr[i] = 1 if wd.grounded else 0
		muz[i] = float(wd.get("mu", 0.8)) * float(wd.fz) if wd.grounded else 0.0
		iw[i] = _wheel_inertia(wd)
		var b := brake_t * (0.62 if wd.axle == 0 else 0.38)
		if wd.rear:
			b += hb_t
		tb[i] = b
		var d := driven.has(wd)
		isd[i] = 1 if d else 0
		if d:
			n_drv += 1
			i_wheel_sum += iw[i]
	var i_s := i_wheel_sum / maxf(ratio * ratio, 0.0001)
	# a worn gearbox/clutch slips under full load instead of never engaging
	var cap := tmax * 1.8 * clutch * lerpf(0.7, 1.0, clampf(slot_q("gearbox"), 0.0, 1.0))
	var base_t := _torque_curve(engine_rpm, e) * throttle_eff * power_mult * (1.0 - misfire * 0.7) if running else 0.0
	for _s in range(SUBSTEPS):
		var avg := 0.0
		for i in range(n_w):
			if isd[i]:
				avg += om[i]
		avg = avg / maxf(1, n_drv)
		var shaft_w := avg * ratio
		var omega_rpm := engine_rpm * TAU / 60.0
		var t_eng := base_t
		if engine_rpm > 10.0:
			t_eng -= (0.04 * tmax + engine_rpm * 0.0035 * tmax / 100.0) * (1.0 - throttle_eff * 0.8)
		if not running and engine_rpm > 0.0:
			t_eng -= tmax * 0.15
		if engine_rpm < 330.0:
			t_eng += starter_t
		var t_c := 0.0
		if clutch > 0.001 and n_drv > 0 and absf(ratio) > 0.01:
			var need := (omega_rpm - shaft_w) / (dts * (1.0 / e_inertia + 1.0 / i_s))
			t_c = clampf(need, -cap, cap)
		omega_rpm = maxf(omega_rpm + (t_eng - t_c) / e_inertia * dts, 0.0)
		engine_rpm = omega_rpm * 60.0 / TAU
		var t_wheel := t_c * ratio / maxf(1, n_drv)
		for i in range(n_w):
			var r := rr[i]
			var fx := 0.0
			if gr[i]:
				var slip := om[i] * r - vl[i]
				var kappa := slip / maxf(absf(vl[i]), 3.0)
				var bx := 12.0 * kappa
				# C=1.45: a spinning tyre keeps ~80% of its peak grip (real tyres), not ~55%
				fx = sin(1.45 * atan(bx - 0.1 * (bx - atan(bx)))) * muz[i]
				# stability: the tyre can't push harder than what cancels the slip within this substep
				var lim := absf(slip) * iw[i] / (r * r * dts)
				fx = clampf(fx, -lim, lim)
			var td := t_wheel if isd[i] else 0.0
			var w_new := om[i] + (td - fx * r) / iw[i] * dts
			var dw := tb[i] / iw[i] * dts
			if dw > 0.0:
				if absf(w_new) <= dw:
					w_new = 0.0
				else:
					w_new -= signf(w_new) * dw
			om[i] = w_new
			fxs[i] += fx / SUBSTEPS
		if n_drv > 1:
			var a2 := 0.0
			for i in range(n_w):
				if isd[i]:
					a2 += om[i]
			a2 /= n_drv
			# locked: wheels turn together; open: a little internal friction (real diffs aren't ideal)
			var k := 0.8 if diff_lock else 0.02
			for i in range(n_w):
				if isd[i]:
					om[i] = lerpf(om[i], a2, k)
	for i in range(n_w):
		wheels[i].omega = om[i]
		wheels[i].fx = fxs[i]
	# apply longitudinal + lateral with friction circle
	for w in wheels:
		var wd := w as Dictionary
		if not wd.grounded:
			wd.omega *= 0.995
			continue
		var fx: float = wd.fx
		var fy: float = lat.get(wd.i, 0.0)
		var lim: float = wd.mu * wd.fz * 1.05
		var mag := sqrt(fx * fx + fy * fy)
		if mag > lim and mag > 0.0:
			var sc := lim / mag
			fy *= sc
			fx = fx * maxf(sc, 0.8)
		wd.slip = absf(wd.omega * wd.radius - wd.vlong) + absf(wd.vlat) * 0.5
		apply_force(wd.fwd * fx + wd.right * fy, wd.contact - global_position)
	# ---------- aero & water
	var drag := -linear_velocity * spd * 0.38 * (1.0 if cls == "small" else 2.2)
	apply_central_force(drag)
	var depth := water_level - global_position.y
	if depth > -0.2:
		apply_central_force(-linear_velocity * mass * 0.6 * clampf(depth + 0.2, 0.0, 1.5))
		if depth > _bay().position.y + 0.25 and running:
			_stall("Engine flooded with water!")
	# ---------- parked: keep still
	if spd < 0.25 and _wheel_ground >= 3 and (driver == null or (in_throttle < 0.05 and (in_brake > 0.1 or in_handbrake > 0.1 or gear == 1 or clutch < 0.05))):
		linear_velocity *= 0.85
		angular_velocity *= 0.85
	# ---------- running costs
	_simulate_engine_state(dt, red)
	_impact_check(dt)
	odometer += spd * dt
	if driver:
		Game.stats.km += spd * dt / 1000.0


func _wheel_inertia(w: Dictionary) -> float:
	if not w.slot.is_installed():
		return 0.4
	var pm: float = DB.part(w.slot.part_id()).get("mass", 15.0)
	return maxf(0.6, 0.55 * pm * w.radius * w.radius + 0.25)


func _misfire_bad(q: float) -> float:
	return clampf((0.75 - q) / 0.75, 0.0, 1.0)


func _pacejka(x: float, b: float, c: float, e: float) -> float:
	var bx := b * x
	return sin(c * atan(bx - e * (bx - atan(bx))))


func _simulate_engine_state(dt: float, red: float) -> void:
	var load_f := throttle_eff * engine_rpm / red if running else 0.0
	if running:
		var e := engine_def()
		fuel = maxf(0.0, fuel - float(e.get("fuel_use", 1.0)) * (0.0002 + 0.009 * load_f) * dt)
		oil = maxf(0.0, oil - (0.00002 + 0.00008 * load_f) * dt * (1.0 + (1.0 - slot_q("engine")) * 3.0))
		if has("alternator") and engine_rpm > 900.0:
			_battery_add(0.06 * slot_q("alternator") * float(DB.part(slots.alternator.part_id()).get("charge", 1.0)) * dt)
		# wear
		var wmul := dt / 3600.0 * 8.0
		for sn in ["engine", "carburetor", "air_filter", "spark_plugs", "ignition_coil", "alternator", "gearbox", "exhaust", "radiator"]:
			var s: PartSlot = slots.get(sn)
			if s and s.is_installed():
				var wr_: float = DB.part(s.part_id()).get("wear", 0.2)
				var extra := 1.0
				if sn == "engine":
					if oil < 1.0:
						extra += (1.0 - oil) * 40.0
					if temp > 110.0:
						extra += (temp - 110.0) * 2.0
					if not has("air_filter"):
						extra += 2.0
				if s.bolts == 0:
					extra *= 2.0
				s.data.cond = maxf(0.0, float(s.data.cond) - wr_ * (0.3 + load_f) * extra * wmul * 100.0 / 100.0)
		if fuel <= 0.0:
			_stall("Out of fuel!")
		if has("engine") and slots.engine.cond() <= 0.5:
			_stall("Engine seized!")
	# tyre wear by distance
	for w in wheels:
		if w.slot.is_installed() and w.grounded:
			var tw: float = DB.part(w.slot.part_id()).get("wear", 0.4)
			w.slot.data.cond = maxf(0.0, float(w.slot.data.cond) - (absf(w.vlong) * 0.0000015 + w.slip * 0.00002) * tw * dt * 100.0)
	# temperature
	var ambient := 18.0
	var heat := (0.35 + 2.4 * load_f) if running else 0.0
	var cool := (0.016 + 0.03 * clampf(speed_kmh / 70.0, 0.0, 1.0))
	if has("radiator"):
		# a worn radiator loses some capacity (clogged fins), low coolant only hurts below half full;
		# multiplying raw condition by fill level made a 50% radiator boil on a flat road
		var rad_f := 0.25 + 0.75 * sqrt(slot_q("radiator"))
		var fill_f := clampf(coolant / (COOLANT_CAP * 0.5), 0.0, 1.0)
		cool *= clampf(rad_f * fill_f, 0.04, 1.0) * float(DB.part(slots.radiator.part_id()).get("cooling", 1.0))
	else:
		cool *= 0.04
	if temp < 88.0:
		cool *= 0.15
	temp += (heat - cool * (temp - ambient)) * dt * 0.9
	if running and coolant > 0.0:
		coolant = maxf(0.0, coolant - (0.0006 if slot_q("radiator") < 0.3 else 0.0) * dt)
	if temp > 125.0 and running:
		_stall("Engine overheated!")


func _impact_check(dt: float) -> void:
	var acc := (linear_velocity - _prev_vel).length() / dt
	_prev_vel = linear_velocity
	if acc > 70.0 and dt > 0.0:
		var sev := clampf((acc - 70.0) / 200.0, 0.0, 1.0)
		play_fx("res://assets/sounds/ui/crash.ogg", lerpf(-10.0, 2.0, sev))
		if not cargo.is_empty():
			for c in cargo:
				c.cond = maxf(0.0, float(c.cond) - sev * 25.0)
			if driver:
				Game.notify("Cargo damaged! (%d%%)" % int(cargo[0].cond), "warn")
		if has("radiator") and sev > 0.3:
			slots.radiator.data.cond = maxf(0.0, slots.radiator.cond() - sev * 20.0)


func _update_hood(dt: float) -> void:
	if hood_node:
		var target := 1.15 if hood_open else 0.0
		_hood_angle = move_toward(_hood_angle, target, dt * 2.5)
		hood_node.rotation.x = _hood_angle


func _process(dt: float) -> void:
	# visuals: wheels, steering wheel, needles, lights, audio
	for w in wheels:
		var vis: Node3D = w.visual
		var r: float = w.radius if w.slot.is_installed() else 0.13
		var d: float = w.dist
		vis.position = w.top + Vector3.DOWN * (d - r)
		w.spin = fmod(w.spin + w.omega * dt, TAU)
		var yaw := steer_angle if w.steer else 0.0
		vis.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -w.spin)
	if steer_node and steer_node.visible:
		if _steer_base == Basis():
			_steer_base = steer_node.basis
			_steer_axis = (_v3(meta.eye) - _v3(meta.steer)).normalized()
		steer_node.basis = Basis(_steer_axis, -in_steer * 2.2) * _steer_base
	if needles.size() > 0 and driver:
		var e := engine_def()
		var red: float = e.get("redline", 6000.0)
		_needle("speed", clampf(speed_kmh / 160.0, 0, 1))
		_needle("rpm", clampf(engine_rpm / 8000.0, 0, 1))
		_needle("fuel", clampf(fuel / float(def.fuel_cap), 0, 1))
		_needle("temp", clampf((temp - 40.0) / 90.0, 0, 1))
	var lit := lights_on and battery_charge() > 3.0
	for l in _lights:
		l.visible = lit
	_brake_light.light_energy = 1.5 if (in_brake > 0.1 and battery_charge() > 2.0) else (0.3 if lit else 0.0)
	# audio
	if running:
		if not _audio_engine.playing:
			_audio_engine.play()
		var base := 900.0 if cls == "small" else 700.0
		_audio_engine.pitch_scale = clampf(engine_rpm / base * 0.55, 0.45, 3.2) * (0.92 if misfire > 0.5 else 1.0)
		_audio_engine.volume_db = lerpf(-10.0, 0.0, throttle_eff) + (4.0 if not has("exhaust") else 0.0)
	elif cranking and engine_rpm > 50:
		if not _audio_engine.playing:
			_audio_engine.play()
		_audio_engine.pitch_scale = 0.35 + 0.1 * sin(Time.get_ticks_msec() * 0.04)
		_audio_engine.volume_db = -14.0
	else:
		if _audio_engine.playing:
			_audio_engine.stop()
	# cameras
	if driver:
		if camera_mode == 0:
			var look := Basis(Vector3.UP, _fp_yaw) * Basis(Vector3.RIGHT, _fp_pitch)
			if Input.is_action_pressed("look_back"):
				look = Basis(Vector3.UP, PI * 0.95)
			var bx := get_global_transform_interpolated()
			fp_cam.global_transform = bx * Transform3D(look, _v3(meta.eye))
		else:
			_update_tp_cam(dt)


func _needle(k: String, t: float) -> void:
	if needles.has(k):
		needles[k].rotation.z = deg_to_rad(135.0 - t * 270.0) if k in ["speed", "rpm"] else deg_to_rad(60.0 - t * 120.0)


func _update_tp_cam(dt: float) -> void:
	_tp_idle += dt
	var L: float = meta.length
	var dist := L * 1.25 + 2.5
	var ix := get_global_transform_interpolated()
	var heading := atan2(ix.basis.z.x, ix.basis.z.z)
	if _tp_idle > 1.6 and speed_kmh > 4.0:
		var target_yaw := 0.0
		_tp_yaw = lerp_angle(_tp_yaw, target_yaw, dt * 1.6)
		_tp_pitch = lerpf(_tp_pitch, -0.22, dt * 1.0)
	var yaw := heading + _tp_yaw
	var pivot: Vector3 = ix.origin + Vector3.UP * (meta.height * 0.75 + 0.4)
	var dir := Vector3(sin(yaw) * cos(_tp_pitch), -sin(_tp_pitch), cos(yaw) * cos(_tp_pitch))
	var want: Vector3 = pivot + dir * dist
	var q := PhysicsRayQueryParameters3D.create(pivot, want, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		want = hit.position - dir * 0.3
	if terrain:
		want.y = maxf(want.y, terrain.height_at(want.x, want.z) + 0.5)
	# smooth only the orbit distance/height, never lag behind the car (prevents jitter while accelerating)
	_tp_smooth = _tp_smooth.lerp(want - pivot, clampf(dt * 10.0, 0, 1)) if _tp_smooth.distance_to(want - pivot) < 15.0 else want - pivot
	tp_cam.global_position = pivot + _tp_smooth
	tp_cam.look_at(pivot, Vector3.UP)


# ------------------------------------------------------------------ cargo
func cargo_capacity() -> int:
	return int(def.cargo)


func cargo_units() -> int:
	var u := 0
	for c in cargo:
		u += int(c.units)
	return u


func can_carry(good: String) -> bool:
	var kind: String = DB.GOODS[good].kind
	return kind in def.kinds


func add_cargo(good: String, units: int, job_id: int = -1) -> void:
	cargo.append({"good": good, "units": units, "cond": 100.0, "job": job_id})
	_rebuild_cargo_visual()
	recompute_mass()


func take_cargo(job_id: int) -> Dictionary:
	for i in range(cargo.size()):
		if int(cargo[i].job) == job_id:
			var c: Dictionary = cargo[i]
			cargo.remove_at(i)
			_rebuild_cargo_visual()
			recompute_mass()
			return c
	return {}


func take_good(good: String, units: int) -> int:
	var taken := 0
	for i in range(cargo.size() - 1, -1, -1):
		if cargo[i].good == good and int(cargo[i].job) == -1 and taken < units:
			var t := mini(units - taken, int(cargo[i].units))
			cargo[i].units -= t
			taken += t
			if int(cargo[i].units) <= 0:
				cargo.remove_at(i)
	_rebuild_cargo_visual()
	recompute_mass()
	return taken


func _rebuild_cargo_visual() -> void:
	for c in _cargo_nodes.get_children():
		c.queue_free()
	var cg = meta.get("cargo")
	if cg == null or not (cg is Dictionary):
		return
	var center := _v3(cg.c)
	var size := _v3(cg.s)
	var idx := 0
	var total := cargo_units()
	for c in cargo:
		var good: Dictionary = DB.GOODS[c.good]
		for u in range(int(c.units)):
			var ps: PackedScene = load(good.mesh)
			var n: Node3D = ps.instantiate()
			var cols := 2
			var rows := maxi(1, int(ceil(float(cargo_capacity()) / cols)))
			var cx := idx % cols
			var cz := (idx / cols) % rows
			var layer := idx / (cols * rows)
			if good.kind == "logs":
				n.position = center + Vector3(-size.x * 0.3 + (idx % 4) * size.x * 0.2, 0.18 + (idx / 4) * 0.33, 0)
			else:
				n.position = center + Vector3((cx - 0.5) * size.x * 0.5, layer * 0.65, (cz - (rows - 1) * 0.5) * (size.z / rows))
				n.scale = Vector3.ONE * clampf(minf(size.x * 0.45, size.z / rows * 0.9) / 0.62, 0.4, 1.4)
			_cargo_nodes.add_child(n)
			idx += 1
	_cargo_nodes.visible = total > 0


func fuel_capacity() -> float:
	var m := 1.0
	if has("fuel_tank"):
		m = float(DB.part(slots.fuel_tank.part_id()).get("capacity_mult", 1.0))
	return float(def.fuel_cap) * m


# ------------------------------------------------------------------ trunk
func trunk_capacity_kg() -> float:
	return 60.0 + float(def.cargo) * 90.0


func trunk_mass() -> float:
	var m := 0.0
	for d in trunk:
		m += float(DB.part(d.id).get("mass", 2.0))
	return m


func trunk_store(it: Item) -> bool:
	var pm: float = DB.part(it.item_id).get("mass", 2.0)
	if trunk_mass() + pm > trunk_capacity_kg():
		Game.notify("Trunk is full (%.0f / %.0f kg)" % [trunk_mass(), trunk_capacity_kg()], "warn")
		return false
	var d := it.data.duplicate(true)
	d.id = it.item_id
	trunk.append(d)
	recompute_mass()
	play_fx("res://assets/sounds/Car_Trunk_Open.ogg", -8)
	return true


func trunk_take() -> Dictionary:
	if trunk.is_empty():
		return {}
	var d: Dictionary = trunk.pop_back()
	recompute_mass()
	play_fx("res://assets/sounds/Car_Trunk_Open.ogg", -8)
	return d


func trunk_text() -> String:
	if trunk.is_empty():
		return "Trunk: empty"
	var names := []
	for d in trunk:
		names.append(DB.part(d.id).get("name", d.id))
	return "Trunk (%.0f/%.0f kg): %s" % [trunk_mass(), trunk_capacity_kg(), ", ".join(names)]


# ------------------------------------------------------------------ fluids
func add_fluid(kind: String, amount: float) -> float:
	match kind:
		"fuel":
			if not has("fuel_tank"):
				return 0.0
			var a := minf(amount, fuel_capacity() - fuel)
			fuel += a
			return a
		"oil":
			if not has("engine"):
				return 0.0
			var a := minf(amount, OIL_CAP - oil)
			oil += a
			return a
		"coolant":
			if not has("radiator"):
				return 0.0
			var a := minf(amount, COOLANT_CAP - coolant)
			coolant += a
			return a
	return 0.0


# ------------------------------------------------------------------ value & save
func value() -> int:
	var v: float = float(def.price) * 0.35
	for s in slots.values():
		if s.is_installed():
			var p: Dictionary = DB.part(s.part_id())
			v += float(p.price) * (0.25 + 0.6 * s.cond() / 100.0)
	return int(v)


func missing_parts() -> Array:
	var out := []
	for sn in slots.keys():
		if not slots[sn].is_installed():
			out.append(sn)
	return out


func install_default_parts(cond_min: float = 85.0, cond_max: float = 100.0, missing: Array = []) -> void:
	var map := {"engine": def.engine, "gearbox": "gearbox" if cls == "small" else "gearbox_heavy", "radiator": "radiator", "battery": "battery",
		"ignition_coil": "ignition_coil", "fuel_tank": "fuel_tank", "exhaust": "exhaust", "carburetor": "carburetor",
		"air_filter": "air_filter", "spark_plugs": "spark_plugs", "alternator": "alternator", "starter": "starter"}
	var order := ["engine", "gearbox", "radiator", "battery", "ignition_coil", "fuel_tank", "exhaust", "carburetor", "air_filter", "spark_plugs", "alternator", "starter"]
	for sn in order:
		if sn in missing:
			continue
		var d := {"id": map[sn], "cond": randf_range(cond_min, cond_max)}
		if sn == "battery":
			d.charge = randf_range(55.0, 95.0)
		slots[sn].install(d, DB.part(map[sn]).bolts)
	for w in wheels:
		if ("wheel%d" % w.i) in missing:
			continue
		w.slot.install({"id": def.wheel, "cond": randf_range(cond_min, cond_max)}, DB.part(def.wheel).bolts)
	fuel = float(def.fuel_cap) * randf_range(0.15, 0.4)
	oil = OIL_CAP * randf_range(0.7, 1.0)
	coolant = COOLANT_CAP * randf_range(0.7, 1.0)


func save_state() -> Dictionary:
	var s := {}
	for k in slots.keys():
		s[k] = slots[k].save_state()
	return {
		"vid": vid, "paint": paint, "xf": var_to_str(global_transform), "slots": s, "fuel": fuel, "oil": oil, "coolant": coolant,
		"temp": temp, "odo": odometer, "cargo": cargo, "trunk": trunk, "owned": owned, "awd": awd, "low": low_range, "price": for_sale_price,
	}


func load_state(d: Dictionary) -> void:
	global_transform = str_to_var(d.xf)
	for k in d.slots.keys():
		if slots.has(k) and not d.slots[k].data.is_empty():
			pass
	# install parents before children
	var order := ["engine", "carburetor"]
	for k in order:
		if d.slots.has(k) and not (d.slots[k].data as Dictionary).is_empty():
			slots[k].install(d.slots[k].data, int(d.slots[k].bolts))
	for k in d.slots.keys():
		if k in order or not slots.has(k):
			continue
		if not (d.slots[k].data as Dictionary).is_empty():
			slots[k].install(d.slots[k].data, int(d.slots[k].bolts))
	fuel = d.fuel
	oil = d.oil
	coolant = d.coolant
	temp = d.get("temp", 20.0)
	odometer = d.get("odo", 0.0)
	cargo = d.get("cargo", [])
	trunk = d.get("trunk", [])
	owned = d.get("owned", true)
	awd = d.get("awd", awd)
	low_range = d.get("low", false)
	for_sale_price = int(d.get("price", 0))
	_rebuild_cargo_visual()
	recompute_mass()
