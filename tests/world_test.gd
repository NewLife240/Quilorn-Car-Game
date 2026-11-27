extends Node
## Map layout test (headless, pass/fail):  godot --headless --path . res://tests/world_test.tscn
## Every building stands on flat ground at its own height and can be driven to from the nearest
## road without a wall in the way, and things bought in a shop land outside where you can see them.
const Check = preload("res://tests/check.gd")
const SKIP := ["fence_run", "power_pole", "street_lamp", "wreck", "spawn_player"]
# walls of the shop buildings in building space (Godot axes, front = -Z), from tools/bl_buildings.py
const SHOP_WALLS := {
	"shop_general": AABB(Vector3(-5.0, 0, -3.5), Vector3(10.0, 3.4, 7.0)),   # village shop
	"shop_gas": AABB(Vector3(-3.5, 0, 7.0), Vector3(7.0, 3.2, 4.0)),         # gas station kiosk
	"shop_parts": AABB(Vector3(-7.0, 0, -5.0), Vector3(14.0, 4.5, 10.0)),    # auto parts store
}
const MAX_DRIVE_SLOPE := 0.35   # steepest 2 m step on the way from the road to a building (~19 degrees)
var c: Check
var world: World


func _ready() -> void:
	c = Check.new("world", get_tree(), 120.0)
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in 3: await get_tree().physics_frame
	var t: Terrain = world.terrain
	var road_pts: Array = []
	for rd in world.data.roads:
		for q in rd.pts:
			road_pts.append([Vector2(q[0], q[2]), float(rd.w) * 0.5])
	var n := 0
	var floating := []
	var walled := []
	var worst := 0.0
	for o in world.data.objects:
		if o.kind in SKIP:
			continue
		n += 1
		var b := Vector2(o.x, o.z)
		if absf(t.height_at(o.x, o.z) - float(o.y)) > 0.15:
			floating.append("%s (%.0f,%.0f) ground %.2f vs %.2f" % [o.kind, o.x, o.z, t.height_at(o.x, o.z), o.y])
		# straight line from the nearest road edge towards the building, up to its lot
		var best: Array = road_pts[0]
		for rp in road_pts:
			if (rp[0] as Vector2).distance_squared_to(b) < (best[0] as Vector2).distance_squared_to(b):
				best = rp
		var r: Vector2 = best[0]
		var L := r.distance_to(b)
		var u := (b - r) / maxf(L, 0.01)
		var s := float(best[1]) + 0.5
		var step := 0.0
		while s + 2.0 < L - 4.0:
			var p0 := r + u * s
			var p1 := r + u * (s + 2.0)
			step = maxf(step, absf(t.height_at(p1.x, p1.y) - t.height_at(p0.x, p0.y)) / 2.0)
			s += 1.0
		worst = maxf(worst, step)
		if step > MAX_DRIVE_SLOPE:
			walled.append("%s (%.0f,%.0f) slope %.2f" % [o.kind, o.x, o.z, step])
	print("buildings checked: ", n, "  steepest approach: %.2f" % worst)
	for f in floating: print("    floating/buried: ", f)
	for f in walled: print("    hard to reach:   ", f)
	c.ok(floating.is_empty(), "every building stands on the ground (%d off)" % floating.size())
	c.ok(walled.is_empty(), "every building can be driven to from the road (%d behind a bank)" % walled.size())
	await _check_shops()
	c.finish()


func _check_shops() -> void:
	var eco = world.economy
	var shops := 0
	for ip in world.props.ips:
		if not (ip.name in ["shop_general", "shop_gas", "shop_parts"]):
			continue
		var ipmap := {}
		for ip2 in world.props.ips:
			if ip2.obj == ip.obj:
				ipmap[ip2.name] = ip2
		var at: Vector3 = eco._pickup_point(ipmap, ip.node, ip.name)
		Game.money = 100000
		var before := world.dynamic_root.get_child_count()
		eco.buy_shop_item("spark_plugs" if ip.name != "shop_parts" else "air_filter", at)
		var it: Node3D = world.dynamic_root.get_child(world.dynamic_root.get_child_count() - 1)
		if not c.ok(world.dynamic_root.get_child_count() == before + 1, "%s at (%.0f,%.0f): bought item spawned" % [ip.name, ip.obj.x, ip.obj.z]):
			continue
		for i in 90: await get_tree().physics_frame
		var p := it.global_position
		var counter := (ip.node as Node3D).global_position
		# building-space position: is it inside the shop's walls? (collision is streamed around the
		# player, so this is checked against the walls' box from tools/bl_buildings.py instead)
		var bld := (ip.node as Node3D).get_parent() as Node3D
		var lp := bld.global_transform.affine_inverse() * p
		var walls: AABB = SHOP_WALLS[ip.name]
		var inside := lp.x > walls.position.x - 0.3 and lp.x < walls.end.x + 0.3 and lp.z > walls.position.z - 0.3 and lp.z < walls.end.z + 0.3
		var ground := world.terrain.height_at(p.x, p.z)
		print("  %s item at building-local (%.1f, %.1f), ground %.2f vs item %.2f, %.1f m from counter" % [ip.name, lp.x, lp.z, ground, p.y, p.distance_to(counter)])
		c.ok(not inside, "%s at (%.0f,%.0f): bought item is outside the shop walls" % [ip.name, ip.obj.x, ip.obj.z])
		c.ok(absf(p.y - ground) < 0.8 and p.distance_to(counter) < 7.0, "%s: bought item lies on the ground next to the shop" % ip.name)
		shops += 1
	c.ok(shops >= 3, "checked %d shop counters" % shops)
