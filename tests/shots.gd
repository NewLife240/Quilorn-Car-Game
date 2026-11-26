extends Node
## Renders a set of screenshots for visual checks.  godot --path . res://tests/shots.tscn -- out=/path
var world: World
var out := "/root/shots"
var views := []
var idx := 0
var timer := 0.0
var frames := 0
var settle := 5
var cam: Camera3D
var car: Vehicle

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game = true
	Game.minutes = 10.5 * 60
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	cam = Camera3D.new()
	cam.far = 3000
	add_child(cam)
	var pts: Array = world.data.roads[0].pts
	var p: Array = pts[230]
	var q: Array = pts[234]
	var pos := Vector3(p[0], world.terrain.height_at(p[0], p[2]) + 0.6, p[2])
	var dir := (Vector3(q[0], 0, q[2]) - Vector3(p[0], 0, p[2])).normalized()
	car = world.spawn_vehicle("klasyka", Transform3D(Basis.looking_at(dir, Vector3.UP), pos), 1)
	car.install_default_parts(90, 100)
	var g: Dictionary = world.props.find_object("garage")
	var home := Vector3(g.x, g.y, g.z)
	var village := world.loc_pos("village")
	var forest := world.loc_pos("lumber")
	var town := world.loc_pos("town")
	var set2 := OS.get_cmdline_user_args().has("set2")
	if OS.get_cmdline_user_args().has("wheels"):
		var row := []
		var k := 0
		for vid2 in ["klasyka", "bobyk", "bukhanka", "kombi"]:
			var pp: Vector3 = pos + dir.cross(Vector3.UP) * (-6.0 + k * 4.0) + dir * 12.0
			pp.y = world.terrain.height_at(pp.x, pp.z) + 0.5
			var vv := world.spawn_vehicle(vid2, Transform3D(Basis.looking_at(dir.cross(Vector3.UP), Vector3.UP), pp), 0)
			vv.install_default_parts(90, 100)
			k += 1
		settle = 40
		var c0: Vector3 = pos + dir * 12.0 + dir * 9.0 + Vector3.UP * 1.6
		views = [["wheels", "cam", c0, pos + dir * 12.0 + Vector3.UP * 0.6]]
		return
	if OS.get_cmdline_user_args().has("fb"):
		var kh: Dictionary = world.props.find_object("khata")
		var kp := Vector3(kh.x, kh.y, kh.z)
		var jk: Dictionary = world.props.find_object("junkyard_office")
		var jp := Vector3(jk.x, jk.y, jk.z)
		var gar: Dictionary = world.props.find_object("garage")
		var gbb := Basis(Vector3.UP, gar.rot)
		var gpp := Vector3(gar.x, gar.y, gar.z)
		var fore := world.loc_pos("lumber")
		views = [
			["fb_yard", "cam", kp + Vector3(22, 9, 22), kp],
			["fb_garage_bench", "cam", gpp + gbb * Vector3(-1.2, 1.9, -1.2), gpp + gbb * Vector3(-3.6, 1.0, -1.6)],
			["fb_junk", "cam", jp + Vector3(6, 3, -9), jp + Vector3(-3, 0.3, -3)],
			["fb_forest_far", "cam", fore + Vector3(420, 60, 420), fore],
			["fb_sunrise", "time", 6.2, kp + Vector3(-30, 3, 0)],
			["fb_night", "time", 22.5, kp + Vector3(10, 4, -25)],
			["fb_map", "ui", 3, null],
		]
		return
	if OS.get_cmdline_user_args().has("ui"):
		views = [["ui_jobs", "ui", 0, null], ["ui_map", "ui", 3, null], ["ui_vehicle", "ui", 4, null], ["ui_shop", "shop", null, null], ["ui_garage", "player", null, null]]
		return
	if OS.get_cmdline_user_args().has("menu"):
		Game.minutes = 19.4 * 60
		world.hud.visible = false
		var ch: Dictionary = world.props.find_object("church")
		var pts2: Array = world.data.roads[3].pts
		var best := 0
		var bd := 1e9
		for i in range(pts2.size()):
			var dd := Vector2(pts2[i][0] - ch.x, pts2[i][2] - ch.z).length()
			if dd < bd:
				bd = dd
				best = i
		var a: Array = pts2[best + 4]
		var b2: Array = pts2[best + 1]
		var cp := Vector3(a[0], world.terrain.height_at(a[0], a[2]) + 0.25, a[2])
		var dr := (Vector3(b2[0], 0, b2[2]) - Vector3(a[0], 0, a[2])).normalized()
		car.global_transform = Transform3D(Basis.looking_at(dr, Vector3.UP), cp)
		car.apply_paint(3)
		var side := dr.cross(Vector3.UP)
		settle = 45
		views = [["menu_bg", "cam", cp + dr * 7.0 + side * 3.2 + Vector3.UP * 1.2, cp + Vector3.UP * 1.0 - dr * 6.0 - side * 2.0]]
		return
	var obj := func(k: String) -> Vector3:
		var o: Dictionary = world.props.find_object(k)
		return Vector3(o.x, o.y, o.z)
	var mudp: Array = world.data.roads[8].pts[40]
	var mudv := Vector3(mudp[0], world.terrain.height_at(mudp[0], mudp[2]), mudp[2])
	if set2:
		var tr := world.spawn_vehicle("truck", Transform3D(Basis.IDENTITY, mudv + Vector3.UP * 1.5), 0)
		tr.install_default_parts(90, 100)
		views = [
			["player_garage", "player", null, null],
			["khata", "cam", obj.call("khata") + Vector3(14, 4, 14), obj.call("khata") + Vector3(0, 2, 0)],
			["gas", "cam", obj.call("gas_station") + Vector3(-14, 5, 16), obj.call("gas_station")],
			["parts", "cam", obj.call("parts_store") + Vector3(-10, 4, 18), obj.call("parts_store") + Vector3(0, 2, 0)],
			["sawmill", "cam", obj.call("sawmill") + Vector3(25, 12, 25), obj.call("sawmill")],
			["truck_mud", "cam", mudv + Vector3(8, 3, 8), mudv + Vector3(0, 1, 0)],
			["church", "cam", obj.call("church") + Vector3(25, 6, 25), obj.call("church") + Vector3(0, 6, 0)],
			["market", "cam", obj.call("car_market") + Vector3(-10, 8, 30), obj.call("car_market")],
		]
		return
	views = [
		["player_garage", "player", null, null],
		["car_tp", "cam", pos + dir.rotated(Vector3.UP, 2.4) * 7 + Vector3.UP * 2.2, pos + Vector3.UP * 0.8],
		["car_fp", "carfp", null, null],
		["village_air", "cam", village + Vector3(-80, 45, 90), village],
		["forest", "cam", forest + Vector3(30, 8, 60), forest],
		["town", "cam", town + Vector3(-120, 40, 140), town],
		["home_air", "cam", home + Vector3(25, 14, 25), home],
		["fields", "cam", Vector3(150, world.terrain.height_at(150, 700) + 6, 700), Vector3(330, world.terrain.height_at(330, 760), 760)],
	]

func _process(dt: float) -> void:
	if views.is_empty(): return
	timer += dt
	frames += 1
	if frames == 1:
		var v: Array = views[idx]
		match v[1]:
			"player":
				world.player.cam.current = true
			"cam":
				cam.global_position = v[2]
				cam.look_at(v[3])
				cam.current = true
			"carfp":
				world.player.enter_vehicle(car)
			"time":
				Game.minutes = v[2] * 60.0
				world._update_daylight()
				cam.global_position = v[3]
				var sd: Vector3 = -world.sun.global_basis.z
				cam.look_at(v[3] - Vector3(sd.x, 0.0, sd.z).normalized() * 50.0 + Vector3.UP * 8.0)
				cam.current = true
			"ui":
				world.hud.close_modal()
				world.hud.close_tablet()
				world.hud.open_tablet(v[2])
			"shop":
				world.hud.close_tablet()
				world.hud.open_shop("parts", Vector3.ZERO)
			"player":
				world.hud.close_modal()
				world.hud.close_tablet()
				world.player.cam.current = true
	if frames >= settle:
		var img := get_viewport().get_texture().get_image()
		img.save_png(out + "/" + views[idx][0] + ".png")
		print("SHOT ", views[idx][0], " fps=", Engine.get_frames_per_second())
		idx += 1
		timer = 0.0
		frames = 0
		if idx >= views.size():
			get_tree().quit()
