extends Node
## Automated driving test: run with  godot --headless --path . res://tests/drive_test.tscn -- vid=kombi
var world: World
var v: Vehicle
var t := 0.0
var phase := 0
var log_t := 0.0
var vid := "kombi"
var where := "road"
var shots := false
var road_pts: Array = []
var road_i := 0
var cond := 100.0
var start_i := -1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vid="): vid = a.substr(4)
		if a.begins_with("where="): where = a.substr(6)
		if a == "shots": shots = true
		if a.begins_with("cond="): cond = float(a.substr(5))
		if a.begins_with("i="): start_i = int(a.substr(2))
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pts: Array = world.data.roads[0].pts
	var p: Array = pts[60]
	var q: Array = pts[64]
	if where == "mud":
		pts = world.data.roads[8].pts
		var si := 40 if start_i < 0 else start_i
		p = pts[si]
		q = pts[si + 4]
	road_i = 60 if where == "road" else (40 if start_i < 0 else start_i)
	if where == "hill":
		# steepest stretch of road anywhere on the map, start 40 m before it
		var best := 0.0
		for r in world.data.roads:
			if r.kind == "dirt": continue
			var rp: Array = r.pts
			for i in range(8, rp.size() - 10):
				var a2: Array = rp[i]
				var b2: Array = rp[i + 6]
				var hd := world.terrain.height_at(b2[0], b2[2]) - world.terrain.height_at(a2[0], a2[2])
				var dd := Vector2(b2[0] - a2[0], b2[2] - a2[2]).length()
				if dd > 1.0 and hd / dd > best:
					best = hd / dd
					pts = rp
					road_i = i - 6
		p = pts[road_i]
		q = pts[road_i + 2]
		print("HILL grade %.1f%%" % (best * 100.0))
	road_pts = pts
	var pos := Vector3(p[0], world.terrain.height_at(p[0], p[2]) + 1.0, p[2])
	var dir := (Vector3(q[0], 0, q[2]) - Vector3(p[0], 0, p[2])).normalized()
	v = world.spawn_vehicle(vid, Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
	v.install_default_parts(cond, cond)
	v.fuel = 30
	v.oil = 4
	v.coolant = 6
	world.player.enter_vehicle(v)
	print("SPAWN ", vid, " at ", pos, " mass ", v.mass, " surface ", world.terrain.surface(pos.x, pos.z))

func _physics_process(dt: float) -> void:
	if v == null: return
	t += dt
	match phase:
		0:
			if t > 1.0:
				Input.action_press("ignition"); phase = 1; t = 0
		1:
			if v.running or t > 4.0:
				Input.action_release("ignition"); print("STARTED=", v.running, " after ", t, "s rpm ", v.engine_rpm); phase = 2; t = 0
		2:
			if t > 1.0: Input.action_press("forward"); phase = 3; t = 0
		3:
			if t > (25.0 if where == "road" else 20.0):
				Input.action_release("forward"); Input.action_press("back"); phase = 4; t = 0
				if where == "mud":
					print("toggle awd+low+difflock")
					v.awd = true; v.low_range = true; v.diff_lock = true
					Input.action_release("back"); Input.action_press("forward"); phase = 6; t = 0
		4:
			if v.speed_kmh < 1.0 or t > 12.0:
				print("STOPPED in ", t, "s"); Input.action_release("back"); phase = 5; t = 0
		5:
			if t > 2.0:
				print("DONE"); get_tree().quit()
		6:
			if t > 15.0:
				print("DONE"); get_tree().quit()
	# pure-pursuit steering along the road
	var vp := v.global_position
	while road_i < road_pts.size() - 1 and Vector2(road_pts[road_i][0] - vp.x, road_pts[road_i][2] - vp.z).length() < 9.0:
		road_i += 1
	var tp := Vector3(road_pts[road_i][0], vp.y, road_pts[road_i][2])
	var loc := v.to_local(tp)
	var steer := clampf(loc.x * 0.25, -1, 1)
	Input.action_release("left"); Input.action_release("right")
	if steer > 0.05: Input.action_press("right", steer)
	elif steer < -0.05: Input.action_press("left", -steer)
	log_t += dt
	if log_t > 1.0:
		log_t = 0
		var w0: Dictionary = v.wheels[0]
		var ws := ""
		for w in v.wheels:
			ws += " [%d g%d w*r=%.1f vl=%.1f fz=%.0f fx=%.0f]" % [w.i, int(w.grounded), w.omega * w.radius, w.get("vlong", 0.0), w.fz, w.fx]
		print(ws)
		print("PERF process=%.2fms physics=%.2fms objects=%d nodes=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		print("t=%.0f ph=%d spd=%.1f rpm=%d gear=%s clutch=%.2f thr=%.2f fz0=%.0f sink=%.2f mud=%.2f slip=%.1f comp=%.2f y=%.2f up=%.2f" % [t, phase, v.speed_kmh, v.engine_rpm, v.gear_text(), v.clutch, v.throttle_eff, w0.fz, w0.sink, w0.surface.get("mud", 0.0), w0.slip, w0.comp, v.global_position.y, v.global_basis.y.y])
