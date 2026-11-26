extends Node
## Assembly & economy integration test (headless).
var world: World
var car: Vehicle
var step := 0
var t := 0.0

func _ready() -> void:
	Game.new_game = true
	Game.money = 1800
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for v in world.vehicles:
		if v.owned:
			car = v
	print("CAR ", car.vid, " missing=", car.missing_parts(), " can_run=", car.can_run())
	var items := []
	for c in world.dynamic_root.get_children():
		if c is Item: items.append(c.item_id)
	print("ITEMS ", items)
	print("JOBS ", world.economy.jobs.size(), " industries ", world.economy.industries.keys(), " consumers ", world.economy.consumers.keys())
	print("ZONES ", world.economy._zones.size(), " IPS ", world.props.ips.map(func(i): return i.name))
	var forsale := world.vehicles.filter(func(v): return not v.owned).map(func(v): return "%s ₴%d" % [v.vid, v.for_sale_price])
	print("MARKET ", forsale)

func _physics_process(dt: float) -> void:
	if car == null: return
	t += dt
	match step:
		0:
			# install every lying part into the matching slot (like the player would)
			for c in world.dynamic_root.get_children():
				if c is Item and DB.is_part(c.item_id):
					for s in car.slots.values():
						if s.can_accept(c.item_id):
							s.install(c.data, 0)
							c.queue_free()
							break
			print("after install missing=", car.missing_parts())
			# not tightened: loose bolts
			print("battery tight? ", car.slots.battery.is_tight(), " q=", car.slots.battery.quality())
			for s in car.slots.values():
				while s.tighten(): pass
			print("all tight. can_run (fuel %.1f) = %s" % [car.fuel, car.can_run()])
			car.add_fluid("fuel", 10.0)
			step = 1; t = 0
			world.player.enter_vehicle(car)
			Input.action_press("ignition")
		1:
			if car.running or t > 5.0:
				Input.action_release("ignition")
				print("ENGINE RUNNING=", car.running, " after %.2fs battery=%.1f" % [t, car.battery_charge()])
				step = 2; t = 0
		2:
			step = 9
			# remove carburettor: must loosen first
			var s: PartSlot = car.slots.carburetor
			print("air filter installed on carb? ", car.has("air_filter"))
			while s.loosen(): pass
			print("carb children installed: ", s.has_children_installed())
			if not s.has_children_installed():
				var d := s.remove()
				print("removed carb cond=", d.cond)
			await get_tree().create_timer(0.5).timeout
			print("engine running after carb removed: ", car.running)
			# economy smoke test
			var eco = world.economy
			var j: Dictionary = eco.jobs[0]
			eco.accept_job(j.id)
			print("accepted ", j)
			Game.save_game()
			print("SAVED ok, size=", FileAccess.get_file_as_string(Game.SAVE_PATH).length())
			# reload from save
			Game.new_game = false
			var w2: World = load("res://scenes/game.tscn").instantiate()
			world.queue_free()
			await get_tree().process_frame
			add_child(w2)
			await get_tree().physics_frame
			var owned := w2.vehicles.filter(func(v): return v.owned)
			print("RELOADED vehicles=", w2.vehicles.size(), " owned=", owned.size(), " carb installed=", owned[0].has("carburetor"), " jobs active=", w2.economy.active.size())
			step = 3
		3:
			print("DONE")
			get_tree().quit()
