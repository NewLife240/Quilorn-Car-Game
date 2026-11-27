extends Node
## Long-drive performance soak test. Drives the car along asphalt roads for `dur` seconds
## and logs the worst frame time, script times and object counts every 5 s.
##   godot --headless --path . res://tests/perf_drive.tscn -- dur=300 [rain] [night] [vid=kombi] [ts=30] [wild] [alldirt] [cond=48] [dump]
var world: World
var v: Vehicle
var dur := 300.0
var vid := "kombi"
var rain := false
var night := false
var wild := false
var kinds := ["asphalt"]
var cond := 80.0
var road_pts: Array = []
var road_i := 0
var t := 0.0
var started := false
var _last_us := 0
var _worst_ms := 0.0
var _frames := 0
var _log_t := 0.0
var _phys_us := 0
var _phys_worst := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("dur="): dur = float(a.substr(4))
		if a.begins_with("vid="): vid = a.substr(4)
		if a == "rain": rain = true
		if a == "night": night = true
		if a == "wild": wild = true
		if a == "alldirt": kinds = ["asphalt", "dirt", "gravel"]
		if a.begins_with("cond="): cond = float(a.substr(5))
		if a.begins_with("ts="): Game.time_scale = float(a.substr(3))
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if night:
		Game.minutes = 22.0 * 60.0
	_pick_road(0)
	v = world.spawn_vehicle(vid, Transform3D.IDENTITY)
	_teleport()
	v.install_default_parts(cond, cond)
	v.fuel = 60
	v.oil = 4
	v.coolant = 6
	v.auto_gearbox = true
	world.player.enter_vehicle(v)
	v.auto_gearbox = true
	Input.action_press("ignition")
	_last_us = Time.get_ticks_usec()


func _pick_road(idx: int) -> void:
	var roads: Array = world.data.roads.filter(func(r): return r.kind in kinds and r.pts.size() > 30)
	road_pts = roads[idx % roads.size()].pts
	road_i = 4
	# skip points near the map edge
	while road_i < road_pts.size() - 10 and (absf(road_pts[road_i][0]) > 990.0 or absf(road_pts[road_i][2]) > 990.0):
		road_i += 1


func _teleport() -> void:
	var p: Array = road_pts[road_i]
	var q: Array = road_pts[road_i + 3]
	var pos := Vector3(p[0], world.terrain.height_at(p[0], p[2]) + 1.0, p[2])
	var dir := (Vector3(q[0], 0, q[2]) - Vector3(p[0], 0, p[2])).normalized()
	v.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.reset_physics_interpolation()


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_worst_ms = maxf(_worst_ms, ms)
	_frames += 1


func _physics_process(dt: float) -> void:
	if v == null:
		return
	t += dt
	if rain:
		world._weather_target = 1.0
		world.weather = 1.0
		world._weather_timer = 999.0
	if not started and (v.running or t > 5.0):
		Input.action_release("ignition")
		Input.action_press("forward", 0.8)
		started = true
	var vp := v.global_position
	while road_i < road_pts.size() - 1 and Vector2(road_pts[road_i][0] - vp.x, road_pts[road_i][2] - vp.z).length() < 9.0:
		road_i += 1
	if road_i >= road_pts.size() - 4 or absf(vp.x) > 1000.0 or absf(vp.z) > 1000.0:
		_pick_road(randi())
		_teleport()
	var tp := Vector3(road_pts[road_i][0], vp.y, road_pts[road_i][2])
	var loc := v.to_local(tp)
	var steer := clampf(loc.x * 0.25, -1, 1)
	if wild:
		steer = clampf(steer + sin(t * 0.7) * 0.5, -1, 1)
		if randf() < 0.002: v.camera_mode = 1 - v.camera_mode; v._set_camera()
	Input.action_release("left"); Input.action_release("right")
	if steer > 0.05: Input.action_press("right", steer)
	elif steer < -0.05: Input.action_press("left", -steer)
	# keep a sane cruising speed
	if v.speed_kmh > (120.0 if wild else 70.0):
		Input.action_release("forward")
	elif started:
		Input.action_press("forward", 1.0 if wild else 0.8)
	_log_t += dt
	if _log_t >= 5.0:
		_log_t = 0.0
		print("PERF t=%.0f frames=%d worst_frame=%.1fms process=%.2fms physics=%.2fms nodes=%d objects=%d res=%d spd=%.0f gear=%s weather=%.2f day=%s pos=(%.0f,%.0f)" % [
			t, _frames, _worst_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), v.speed_kmh, v.gear_text(), world.weather, Game.clock_text(), vp.x, vp.z])
		var awake := 0
		for vv in world.vehicles:
			if not vv.sleeping: awake += 1
		var items_awake := 0
		for c in world.dynamic_root.get_children():
			if c is RigidBody3D and not (c is Vehicle) and not c.sleeping: items_awake += 1
		print("   vehicles=%d awake=%d items_awake=%d" % [world.vehicles.size(), awake, items_awake])
		_frames = 0
		_worst_ms = 0.0
	if OS.get_cmdline_user_args().has("dump") and t > 15.0 and t - dt <= 15.0:
		world.perf_watch.dump("test")
	if t > dur:
		print("DONE")
		get_tree().quit()
