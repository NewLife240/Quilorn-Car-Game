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
var dur := -1.0
var real := false
var vmax := 999.0
var shot_dir := ""
var shot_at: Array = []
var tp := false
var v_warm := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vid="): vid = a.substr(4)
		if a.begins_with("where="): where = a.substr(6)
		if a == "shots": shots = true
		if a.begins_with("cond="): cond = float(a.substr(5))
		if a.begins_with("i="): start_i = int(a.substr(2))
		if a.begins_with("dur="): dur = float(a.substr(4))
		if a == "real": real = true
		if a.begins_with("vmax="): vmax = float(a.substr(5))
		if a.begins_with("shot="): shot_dir = a.substr(5)
		if a.begins_with("shot_at="):
			for x in a.substr(8).split(","): shot_at.append(float(x))
		if a == "tp": tp = true
		if a == "warm": v_warm = true
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
	if "notraffic" in OS.get_cmdline_user_args():
		world.traffic.process_mode = Node.PROCESS_MODE_DISABLED
		world.traffic.visible = false
		for b in world.traffic.find_children("*", "CollisionObject3D", true, false):
			(b as CollisionObject3D).collision_layer = 0
	var pos := Vector3(p[0], world.terrain.height_at(p[0], p[2]) + 1.0, p[2])
	var dir := (Vector3(q[0], 0, q[2]) - Vector3(p[0], 0, p[2])).normalized()
	v = world.spawn_vehicle(vid, Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
	v.install_default_parts(cond, cond)
	if not real:
		v.fuel = 30
		v.oil = 4
		v.coolant = 6
	else:
		v.fuel = 30
	world.player.enter_vehicle(v)
	if v_warm:
		v.temp = 85.0  # skip the warm-up so short runs show the steady-state temperature
	if tp:
		v.camera_mode = 1
		v._set_camera()
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
			# cruise: ease off above vmax, and stop at the end of the road instead of driving into the scenery
			Input.action_press("forward", 1.0 if v.speed_kmh < vmax else 0.25)
			if road_i >= road_pts.size() - 2:
				print("END OF ROAD at t=%.0f" % t)
				t = 1e9
			if t > (dur if dur > 0.0 else (25.0 if where == "road" else 20.0)):
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
	# screenshots at given drive times (phase 3), e.g. shot=/tmp/out shot_at=10,30 (needs a display, not --headless)
	if shot_dir != "" and phase == 3 and not shot_at.is_empty() and t >= shot_at[0]:
		shot_at.pop_front()
		DirAccess.make_dir_recursive_absolute(shot_dir)
		var img := get_viewport().get_texture().get_image()
		var fn := "%s/%s_%s_c%d_t%d.png" % [shot_dir, vid, where, int(cond), int(t)]
		img.save_png(fn)
		print("SHOT ", fn)
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
		print("ENG temp=%.1f pwr=%.2f misfires=%d oil=%.2f cool=%.2f eng=%.1f gbx=%.1f rad=%.1f plugs=%.1f tyre0=%.1f odo=%.0f" % [v.temp, v.power_factor, v.misfire_count, v.oil, v.coolant, v.slots.engine.cond(), v.slots.gearbox.cond(), v.slots.radiator.cond(), v.slots.spark_plugs.cond(), v.wheels[0].slot.cond(), v.odometer])
		print("t=%.0f ph=%d spd=%.1f rpm=%d gear=%s clutch=%.2f thr=%.2f fz0=%.0f sink=%.2f mud=%.2f slip=%.1f comp=%.2f y=%.2f up=%.2f" % [t, phase, v.speed_kmh, v.engine_rpm, v.gear_text(), v.clutch, v.throttle_eff, w0.fz, w0.sink, w0.surface.get("mud", 0.0), w0.slip, w0.comp, v.global_position.y, v.global_basis.y.y])
