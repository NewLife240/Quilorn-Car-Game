extends Node3D
## Lightweight ambient traffic: kinematic cars following asphalt roads, yielding to obstacles.

const MODELS := ["klasyka", "kombi", "hatch", "sedan", "minivan", "cruiser", "bukhanka", "stepvan", "pickup"]
var cars: Array = []
var world: Node


func setup(w: Node, count: int = 9) -> void:
	world = w
	var roads: Array = []
	for rd in w.data.roads:
		if rd.kind == "asphalt" and rd.pts.size() > 40:
			roads.append(rd)
	for i in range(count):
		var rd: Dictionary = roads[i % roads.size()]
		_spawn(rd, randi_range(5, rd.pts.size() - 6), 1 if randf() < 0.5 else -1)


func _spawn(rd: Dictionary, idx: int, dir: int) -> void:
	var vid: String = MODELS.pick_random()
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	var ps: PackedScene = load("res://assets/vehicles/%s/%s.glb" % [vid, vid])
	var m: Node3D = ps.instantiate()
	for n in ["interior", "steer", "bay", "needle_speed", "needle_rpm", "needle_fuel", "needle_temp"]:
		var c := m.find_child(n, true, false)
		if c:
			c.queue_free()
	body.add_child(m)
	var meta := DB.vehicle_meta(vid)
	var variants: Array = meta.get("variants", [])
	if not variants.is_empty():
		var tex: Texture2D = load("res://assets/vehicles/%s/%s" % [vid, variants.pick_random()])
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if mat and mat.albedo_texture:
					var nm: BaseMaterial3D = mat.duplicate()
					nm.albedo_texture = tex
					nm.cull_mode = BaseMaterial3D.CULL_BACK
					if meta.get("cutout", false):
						nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						nm.alpha_scissor_threshold = 0.5
					mi.set_surface_override_material(s, nm)
	var wheels := []
	var wmesh: PackedScene = load("res://assets/parts/%s.glb" % DB.VEHICLES[vid].wheel)
	for w in meta.wheels:
		var wn: Node3D = wmesh.instantiate()
		var r: float = w.radius
		wn.scale = Vector3(1.0, r / 0.33, r / 0.33)
		if int(w.side) < 0:
			wn.rotation.y = PI
		var piv := Node3D.new()
		piv.position = Vector3(w.pos[0], w.pos[1], w.pos[2])
		piv.add_child(wn)
		body.add_child(piv)
		wheels.append(piv)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(meta.width * 0.9, meta.height * 0.8, meta.length * 0.95)
	cs.shape = bs
	cs.position.y = meta.height * 0.45
	body.add_child(cs)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 600.0
	var lights := []
	var hl_mat := StandardMaterial3D.new()
	hl_mat.emission_enabled = true
	hl_mat.emission = Color(1, 0.92, 0.7)
	hl_mat.emission_energy_multiplier = 4.0
	hl_mat.albedo_color = Color(1, 1, 0.9)
	var r0: float = meta.wheels[0].radius
	for sx in [-1, 1]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(sx * meta.width * 0.3, r0 * 1.9, -meta.length * 0.5 - 0.05)
		sl.spot_range = 35.0
		sl.spot_angle = 30.0
		sl.light_energy = 3.0
		sl.light_color = Color(1.0, 0.92, 0.75)
		sl.shadow_enabled = false
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = 160.0
		sl.distance_fade_length = 40.0
		sl.visible = false
		body.add_child(sl)
		lights.append(sl)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.18, 0.12)
		q.mesh = qm
		q.material_override = hl_mat
		q.position = sl.position + Vector3(0, 0, -0.02)
		q.rotation.y = PI
		q.visible = false
		body.add_child(q)
		lights.append(q)
	add_child(body)
	var car := {"body": body, "pts": rd.pts, "i": float(idx), "dir": dir, "speed": 0.0, "max": randf_range(13.0, 19.0), "wheels": wheels, "lane": 1.9 if rd.w >= 7 else 1.5, "radius": float(meta.wheels[0].radius), "len": float(meta.length), "lights": lights}
	cars.append(car)
	_place(car, 0.0)


func _pt(pts: Array, f: float) -> Vector3:
	var i := clampi(int(f), 0, pts.size() - 2)
	var t := clampf(f - i, 0.0, 1.0)
	var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
	var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
	return a.lerp(b, t)


func _place(c: Dictionary, dt: float) -> void:
	var pts: Array = c.pts
	var p := _pt(pts, c.i)
	var q := _pt(pts, c.i + c.dir * 2.0)
	var fwd := (q - p)
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var pos: Vector3 = p + right * c.lane
	var t: Terrain = world.terrain
	pos.y = t.height_at(pos.x, pos.z) + 0.02
	var front: Vector3 = pos + fwd * c.len * 0.4
	var back: Vector3 = pos - fwd * c.len * 0.4
	var pitch := atan2(t.height_at(front.x, front.z) - t.height_at(back.x, back.z), c.len * 0.8)
	var b := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, pitch)
	(c.body as AnimatableBody3D).global_transform = Transform3D(b, pos)
	for w in c.wheels:
		(w as Node3D).rotation.x -= c.speed * dt / float(c.radius)


func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	for c in cars:
		var body: AnimatableBody3D = c.body
		var fwd := -body.global_basis.z
		var side := fwd.cross(Vector3.UP)
		var target: float = c.max
		# look ahead further when faster: stopping distance at 7 m/s^2 plus a margin
		var look: float = clampf(float(c.speed) * float(c.speed) / 14.0 + 14.0, 14.0, 45.0)
		var nearest := 1e9
		for off in [-0.7, 0.0, 0.7]:
			var from: Vector3 = body.global_position + Vector3.UP * 0.9 + fwd * (float(c.len) * 0.5 + 0.2) + side * off
			var q := PhysicsRayQueryParameters3D.create(from, from + fwd * look, (1 << 1) | (1 << 3) | (1 << 2))
			q.exclude = [body.get_rid()]
			var hit := space.intersect_ray(q)
			if hit:
				nearest = minf(nearest, from.distance_to(hit.position))
		if nearest < 1e8:
			target = 0.0 if nearest < 6.0 else minf(target, sqrt(maxf(0.0, 2.0 * 6.0 * (nearest - 6.0))))
		# slow in curves
		var a := _pt(c.pts, c.i)
		var b := _pt(c.pts, c.i + c.dir * 6.0)
		var e := _pt(c.pts, c.i + c.dir * 12.0)
		var curve := (b - a).normalized().angle_to((e - b).normalized())
		target = minf(target, lerpf(c.max, 7.0, clampf(curve / 0.6, 0, 1)))
		# end of the road: stop, and only turn around / respawn when nobody is looking
		var to_end: float = (c.pts.size() - 2 - c.i) if c.dir > 0 else (c.i - 1.0)
		if to_end < 10.0:
			target = minf(target, maxf(0.0, (to_end - 2.0) * 1.2))
			if to_end < 2.5 and float(c.speed) < 0.3 and body.global_position.distance_to(cam_pos) > 140.0:
				_respawn(c, cam_pos)
				continue
		c.speed = move_toward(c.speed, target, dt * (7.0 if target < c.speed else 2.2))
		var seg := _pt(c.pts, c.i).distance_to(_pt(c.pts, c.i + c.dir))
		c.i = clampf(c.i + c.dir * c.speed * dt / maxf(seg, 0.5), 1.0, c.pts.size() - 2.0)
		_place(c, dt)


func _respawn(c: Dictionary, cam_pos: Vector3) -> void:
	var roads: Array = []
	for rd in world.data.roads:
		if rd.kind == "asphalt" and rd.pts.size() > 40:
			roads.append(rd)
	for attempt in range(12):
		var rd: Dictionary = roads.pick_random()
		var idx := randi_range(5, rd.pts.size() - 6)
		var p := Vector3(rd.pts[idx][0], rd.pts[idx][1], rd.pts[idx][2])
		if p.distance_to(cam_pos) > 180.0:
			c.pts = rd.pts
			c.i = float(idx)
			c.dir = 1 if randf() < 0.5 else -1
			c.lane = 1.9 if rd.w >= 7 else 1.5
			c.speed = 0.0
			_place(c, 0.0)
			(c.body as AnimatableBody3D).reset_physics_interpolation()
			return
	c.dir = -c.dir


func set_night(on: bool) -> void:
	for c in cars:
		for l in c.lights:
			l.visible = on
