extends Node
## Frame-time watchdog. Keeps one line of stats per second for the last 90 s and writes a
## report to user://perf_reports/ when the game drops below LOW_FPS for a few seconds
## (or when F9 is pressed). The report shows what the frame was spending its time on.

const LOW_FPS := 15.0
const LOW_SECONDS := 3
const HISTORY := 90
const COOLDOWN := 120.0

var world: Node
var _vp: RID
var _hist: Array[String] = []
var _acc := 0.0
var _frames := 0
var _worst_ms := 0.0
var _gpu_sum := 0.0
var _cpu_sum := 0.0
var _phys_steps_last := 0
var _low_run := 0
var _cooldown := 0.0
var _warmup := 10.0
var _last_us := 0


func setup(w: Node) -> void:
	world = w
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_last_us = Time.get_ticks_usec()
	_phys_steps_last = Engine.get_physics_frames()


func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	_worst_ms = maxf(_worst_ms, (now - _last_us) / 1000.0)
	_last_us = now
	_frames += 1
	_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
	_acc += dt
	_cooldown = maxf(0.0, _cooldown - dt)
	_warmup = maxf(0.0, _warmup - dt)
	if _acc < 1.0:
		return
	var fps := _frames / _acc
	var steps := Engine.get_physics_frames() - _phys_steps_last
	_phys_steps_last = Engine.get_physics_frames()
	_hist.append(_line(fps, steps))
	if _hist.size() > HISTORY:
		_hist.pop_front()
	_acc = 0.0
	_frames = 0
	_worst_ms = 0.0
	_gpu_sum = 0.0
	_cpu_sum = 0.0
	if get_tree().paused or _warmup > 0.0:
		_low_run = 0
		return
	_low_run = _low_run + 1 if fps < LOW_FPS else 0
	if _low_run >= LOW_SECONDS and _cooldown <= 0.0:
		_cooldown = COOLDOWN
		dump("auto: below %d FPS for %d s" % [int(LOW_FPS), LOW_SECONDS])


func _line(fps: float, steps: int) -> String:
	var n := maxf(1.0, _frames)
	var cam := get_viewport().get_camera_3d()
	var p := cam.global_position if cam else Vector3.ZERO
	return "%s fps=%.1f worst=%.0fms gpu=%.1fms render_cpu=%.1fms process=%.1fms physics=%.1fms steps=%d draws=%d prims=%dk vram=%dMB nodes=%d objs=%d weather=%.2f pos=(%.0f,%.0f,%.0f)" % [
		Game.clock_text(), fps, _worst_ms, _gpu_sum / n, _cpu_sum / n,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, steps,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		world.weather if world else 0.0, p.x, p.y, p.z]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		dump("manual (F9)")


func dump(reason: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://perf_reports")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://perf_reports/perf_%s.txt" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("Rusty Roads performance report - " + reason)
	f.store_line("GPU: %s / %s, driver %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	f.store_line("OS: %s, CPU: %s x%d, window %s" % [OS.get_name(), OS.get_processor_name(), OS.get_processor_count(), str(get_viewport().get_visible_rect().size)])
	f.store_line("Settings: " + JSON.stringify(Game.settings))
	f.store_line("")
	f.store_line(_snapshot())
	f.store_line("")
	f.store_line("Last %d seconds (oldest first):" % _hist.size())
	for l in _hist:
		f.store_line(l)
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	print("PERF REPORT: ", abs_path)
	Game.notify("Low FPS - report saved: " + abs_path, "warn")


func _snapshot() -> String:
	if world == null:
		return ""
	var s := []
	var awake := 0
	for v in world.vehicles:
		if not v.sleeping:
			awake += 1
	var items := 0
	var items_awake := 0
	for c in world.dynamic_root.get_children():
		if c is RigidBody3D and not (c is Vehicle):
			items += 1
			if not c.sleeping:
				items_awake += 1
	var pv = Game.player.vehicle if Game.player else null
	s.append("vehicles=%d (simulating %d)  items=%d (awake %d)  traffic=%d" % [world.vehicles.size(), awake, items, items_awake, world.traffic.cars.size()])
	s.append("rain=%s rain_collision=%s wetness=%.2f street_lights_on=%s" % [world.rain.emitting, world.rain_hf.visible, world.terrain.wetness, world.props.street_lights[0].visible if world.props.street_lights.size() > 0 else false])
	if pv:
		s.append("driving %s  speed=%.0f km/h  camera=%s" % [pv.vid, pv.speed_kmh, "first person" if pv.camera_mode == 0 else "third person"])
	s.append("physics: active_objects=%d collision_pairs=%d islands=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	s.append("render: objects=%d  texture_mem=%dMB  buffer_mem=%dMB" % [Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	s.append("static_mem=%dMB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	return "\n".join(s)
