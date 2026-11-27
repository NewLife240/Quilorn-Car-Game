extends Node
## Getting out of the car must not launch it (headless, pass/fail):
##   godot --headless --path . res://tests/exit_test.tscn
## While driving, the player body rides at the car's centre with its capsule off. Getting out used to
## turn the capsule on and then move the player to the door; Jolt moves a kinematic body to its new
## position over the next step, so the capsule swept through the car at ~90 m/s and the car flew
## 150-200 m. Gets out of the starter Kombi at 12 spots around the map (4 of them launched it before
## the fix) and checks that the car's speed never jumps. Rolling down a slope afterwards is fine.
const Check = preload("res://tests/check.gd")
const SPOTS := 12
const MAX_JUMP := 15.0   # m/s change in one physics frame; a launch was 85-115 m/s

func _ready() -> void:
	var c := Check.new("exit", get_tree(), 200.0)
	Game.new_game = true
	var world: World = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await _frames(2)
	world.traffic.process_mode = Node.PROCESS_MODE_DISABLED
	for b in world.traffic.find_children("*", "CollisionObject3D", true, false):
		(b as CollisionObject3D).collision_layer = 0
	var pl: Player = world.player
	var car: Vehicle = world.vehicles.filter(func(v): return v.owned)[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base := car.global_position
	for k in SPOTS:
		var pos := base + Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-150, 150))
		pos.y = world.terrain.height_at(pos.x, pos.z) + 1.0
		car.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_physics_interpolation()
		pl.enter_vehicle(car)
		await _frames(150)
		# press E the way the game does
		await get_tree().process_frame
		_press("interact", true)
		await get_tree().process_frame
		_press("interact", false)
		var jump := 0.0
		var prev := car.linear_velocity
		for i in 60:
			await _frames(1)
			jump = maxf(jump, (car.linear_velocity - prev).length())
			prev = car.linear_velocity
		var gap := Vector2(pl.global_position.x - car.global_position.x, pl.global_position.z - car.global_position.z).length()
		print("SPOT %d: car speed jumped by %.2f m/s at most, now %.1f km/h; player %.2f m from car" % [k, jump, car.linear_velocity.length() * 3.6, gap])
		c.ok(pl.vehicle == null, "spot %d: got out" % k)
		c.ok(jump < MAX_JUMP, "spot %d: car not launched (speed jump %.1f m/s)" % [k, jump])
		if pl.vehicle:
			pl.exit_vehicle()
	c.finish()


func _press(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame
