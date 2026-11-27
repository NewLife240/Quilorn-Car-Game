extends Node
## Assembly, economy and save/load integration test (headless, pass/fail):
##   godot --headless --path . res://tests/assembly_test.tscn
## Builds the half-assembled starter car from the parts in the garage, starts it,
## takes the carburettor off again, accepts a job, saves, reloads and checks the save kept it all.
## The player's own savegame is backed up first and put back at the end.
const Check = preload("res://tests/check.gd")
var c: Check
var world: World
var car: Vehicle
var step := 0
var t := 0.0
var _backup: PackedByteArray
var _had_save := false

func _ready() -> void:
	c = Check.new("assembly", get_tree(), 120.0)
	_had_save = FileAccess.file_exists(Game.SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_bytes(Game.SAVE_PATH)
	Game.new_game = true
	Game.money = 1800
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for v in world.vehicles:
		if v.owned:
			car = v
	if not c.ok(car != null, "new game has an owned starter car"):
		c.finish()
		return
	print("CAR ", car.vid, " missing=", car.missing_parts(), " can_run=", car.can_run())
	c.ok(not car.missing_parts().is_empty(), "starter car is missing parts")
	c.ok(not car.can_run(), "starter car cannot run before assembly")
	var items := []
	for it in world.dynamic_root.get_children():
		if it is Item: items.append(it.item_id)
	print("ITEMS ", items)
	for need in ["battery", "carburetor", "spark_plugs"]:
		c.ok(need in items, "garage has a %s lying around" % need)
	c.ok(world.economy.jobs.size() > 0, "economy offers jobs (%d)" % world.economy.jobs.size())
	c.ok(world.economy.industries.size() > 0, "economy has industries")
	var forsale := world.vehicles.filter(func(v): return not v.owned)
	c.ok(forsale.size() > 0, "car market has cars for sale (%d)" % forsale.size())
	for v in forsale:
		c.ok(v.for_sale_price > 0, "%s for sale has a price (%d)" % [v.vid, v.for_sale_price])

func _physics_process(dt: float) -> void:
	if car == null or c.done: return
	t += dt
	match step:
		0:
			# install every free part lying in the garage into the matching slot (like the player would);
			# shop and junkyard items cost money, so they are left alone
			for it in world.dynamic_root.get_children():
				if it is Item and it.shop_price <= 0 and DB.is_part(it.item_id):
					for s in car.slots.values():
						if s.can_accept(it.item_id):
							s.install(it.data, 0)
							it.queue_free()
							break
			# the garage has no air filter: the player buys one, which is not part of this test
			c.ok(car.missing_parts() == ["air_filter"], "free garage parts fill every slot but the air filter (%s)" % [car.missing_parts()])
			if car.slots.air_filter.can_accept("air_filter"):
				car.slots.air_filter.install({"id": "air_filter", "cond": 100.0}, 0)
			c.ok(car.missing_parts().is_empty(), "no missing parts after fitting a bought air filter (%s)" % [car.missing_parts()])
			# not tightened yet: loose bolts lower the quality
			c.ok(not car.slots.battery.is_tight(), "freshly installed battery is not tight")
			var q_loose: float = car.slots.battery.quality()
			for s in car.slots.values():
				while s.tighten(): pass
			c.ok(car.slots.battery.is_tight(), "battery tight after tightening")
			c.ok(car.slots.battery.quality() > q_loose, "tight battery works better than a loose one (%.2f > %.2f)" % [car.slots.battery.quality(), q_loose])
			c.ok(car.can_run(), "assembled car can run")
			car.add_fluid("fuel", 10.0)
			step = 1; t = 0
			world.player.enter_vehicle(car)
			Input.action_press("ignition")
		1:
			if car.running or t > 5.0:
				Input.action_release("ignition")
				c.ok(car.running, "engine starts (%.2f s, battery %.1f)" % [t, car.battery_charge()])
				step = 2; t = 0
		2:
			step = 9   # the rest is async; keep this branch from running again
			await _remove_carb_and_reload()
			c.finish()

func _remove_carb_and_reload() -> void:
	# carburettor: the air filter sits on it, so it must come off first, and bolts must be loosened
	var carb: PartSlot = car.slots.carburetor
	var filt: PartSlot = car.slots.air_filter
	c.ok(carb.has_children_installed(), "air filter is mounted on the carburettor")
	c.ok(carb.bolts > 0, "carburettor is bolted on")
	while filt.loosen(): pass
	var fd := filt.remove()
	c.ok(not fd.is_empty(), "air filter removed")
	while carb.loosen(): pass
	c.ok(not carb.has_children_installed(), "carburettor free after removing the air filter")
	var d := carb.remove()
	c.ok(d.get("id", "") != "", "carburettor removed (cond %.0f)" % float(d.get("cond", 0)))
	await get_tree().create_timer(0.5).timeout
	c.ok(not car.running, "engine stops without a carburettor")
	# put it back so the save has a complete car
	carb.install(d, 0)
	while carb.tighten(): pass
	if not fd.is_empty():
		filt.install(fd, 0)
		while filt.tighten(): pass
	# economy
	var eco = world.economy
	var j: Dictionary = eco.jobs[0]
	c.ok(eco.accept_job(j.id), "accept job %d (%s)" % [j.id, j.good])
	c.ok(eco.active.size() == 1, "one active job")
	var money_before: int = Game.money
	Game.save_game()
	var size := FileAccess.get_file_as_string(Game.SAVE_PATH).length()
	c.ok(size > 1000, "save written (%d bytes)" % size)
	# reload from the save into a fresh world
	Game.new_game = false
	world.queue_free()
	car = null
	world = null
	await get_tree().process_frame
	var w2: World = load("res://scenes/game.tscn").instantiate()
	add_child(w2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	world = w2
	_restore_save()
	var owned := w2.vehicles.filter(func(v): return v.owned)
	print("RELOADED vehicles=", w2.vehicles.size(), " owned=", owned.size(), " jobs active=", w2.economy.active.size())
	if c.ok(owned.size() == 1, "one owned car after reload"):
		car = owned[0]
		c.ok(car.has("carburetor"), "reloaded car has its carburettor")
		c.ok(car.missing_parts().is_empty(), "reloaded car is complete (%s)" % [car.missing_parts()])
		c.ok(car.slots.battery.is_tight(), "reloaded battery is still tight")
	c.ok(w2.economy.active.size() == 1, "active job survives reload")
	c.ok(Game.money == money_before, "money survives reload (%d)" % Game.money)

func _restore_save() -> void:
	# put the player's own save back
	if _had_save:
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	elif FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
