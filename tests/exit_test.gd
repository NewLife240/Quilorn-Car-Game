extends Node
## Getting out of the car (headless, pass/fail):  godot --headless --path . res://tests/exit_test.tscn
## Drives the starter Kombi with the engine running, then:
##  1. tries to get out at speed: refused, the player stays inside;
##  2. brakes until getting out is allowed, gets out: the car stops within a few metres;
##  3. drives again, stops on a slope, gets out with the engine idling: the car stays put.
## Before the fix the car kept coasting in gear with nobody inside and rolled 100+ m away.
const Check = preload("res://tests/check.gd")
var c: Check
var world: World
var v: Vehicle
var pl: Player

func _ready() -> void:
	c = Check.new("exit", get_tree(), 120.0)
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await _frames(2)
	world.traffic.process_mode = Node.PROCESS_MODE_DISABLED
	for b in world.traffic.find_children("*", "CollisionObject3D", true, false):
		(b as CollisionObject3D).collision_layer = 0
	var pts: Array = world.data.roads[0].pts
	var p: Array = pts[60]
	var q: Array = pts[64]
	var pos := Vector3(p[0], world.terrain.height_at(p[0], p[2]) + 1.0, p[2])
	var dir := (Vector3(q[0], 0, q[2]) - Vector3(p[0], 0, p[2])).normalized()
	v = world.spawn_vehicle("kombi", Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
	v.install_default_parts(48, 48)
	v.fuel = 30
	pl = world.player
	pl.enter_vehicle(v)
	v.auto_gearbox = true
	await _frames(60)
	Input.action_press("ignition")
	for i in 240:
		await _frames(1)
		if v.running: break
	Input.action_release("ignition")
	if not c.ok(v.running, "engine started"):
		c.finish()
		return
	# 1 + 2: get out at speed
	await _drive(240)
	print("AT SPEED: %.1f km/h gear %s" % [v.speed_kmh, v.gear_text()])
	pl.exit_vehicle()
	c.ok(pl.vehicle == v, "can't get out at %.0f km/h" % v.speed_kmh)
	Input.action_press("back")
	for i in 600:
		if v.can_exit(): break
		await _frames(1)
	Input.action_release("back")
	print("SLOWED: %.1f km/h gear %s" % [v.speed_kmh, v.gear_text()])
	pl.exit_vehicle()
	c.ok(pl.vehicle == null, "can get out once slowed to %.1f km/h" % v.speed_kmh)
	await _check_parked("slowed down", 3.0)
	# 3: stop on the road with the brake pedal, get out with the engine idling
	pl.enter_vehicle(v)
	await _frames(10)
	await _drive(120)
	Input.action_press("back")
	for i in 600:
		await _frames(1)
		if v.speed_kmh < 1.0: break
	await _frames(30)
	Input.action_release("back")
	print("STOPPED: %.1f km/h gear %s running %s" % [v.speed_kmh, v.gear_text(), v.running])
	pl.exit_vehicle()
	c.ok(pl.vehicle == null, "can get out of a stopped car")
	await _check_parked("stopped, engine idling", 0.5)
	c.finish()


func _drive(frames: int) -> void:
	Input.action_press("forward")
	await _frames(frames)
	Input.action_release("forward")


## After getting out: the car must stop within `max_m` and then not creep at all.
func _check_parked(what: String, max_m: float) -> void:
	var p0 := v.global_position
	await _frames(240)
	var p1 := v.global_position
	await _frames(600)
	var moved := p0.distance_to(v.global_position)
	var creep := p1.distance_to(v.global_position)
	print("PARKED (%s): moved %.2f m, then %.3f m in 10 s, engine running %s, player %.2f m from car" % [what, moved, creep, v.running, pl.global_position.distance_to(v.global_position)])
	c.ok(moved < max_m, "%s: car stops within %.1f m (moved %.2f m)" % [what, max_m, moved])
	c.ok(creep < 0.1, "%s: car doesn't creep with the handbrake on (%.3f m in 10 s)" % [what, creep])


func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame
