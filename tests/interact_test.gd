extends Node
## Player interaction test (headless, pass/fail):  godot --headless --path . res://tests/interact_test.tscn
## Looks at the empty battery slot, carries the battery over, installs it, holds R to tighten it,
## then looks at the hood and checks the prompt.
const Check = preload("res://tests/check.gd")
var c: Check
var world: World

func _ready() -> void:
	c = Check.new("interact", get_tree(), 90.0)
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in 3: await get_tree().physics_frame
	var car: Vehicle = world.vehicles.filter(func(v): return v.owned)[0]
	var pl: Player = world.player
	var bat: Item = null
	for it in world.dynamic_root.get_children():
		if it is Item and it.item_id == "battery" and it.shop_price == 0: bat = it
	if not c.ok(bat != null, "a free battery lies in the garage"):
		c.finish()
		return
	# stand 1.4 m from the battery slot, look at it
	var slot: PartSlot = car.slots.battery
	var target := slot.global_position
	var from := target + car.global_basis.x * 1.4 + Vector3.UP * 0.9
	from.y = maxf(from.y, target.y + 0.5)
	pl.global_position = from - Vector3.UP * 1.65
	var d := (target - from).normalized()
	pl.set_look(atan2(-d.x, -d.z), asin(d.y))
	for i in 3: await get_tree().physics_frame
	pl._process(0.016)
	print("LOOK AT SLOT (no item): target=", pl._target, " hint='", pl.hint, "' info='", pl.info, "'")
	c.ok(pl._target == slot, "crosshair finds the empty battery slot")
	c.ok(pl.hint.begins_with("Needs:"), "empty slot says what it needs ('%s')" % pl.hint)
	# pick the battery up (bring it to the hands first: an item further than 3 m away is dropped)
	pl._grab(bat)
	for i in 3:
		bat.global_position = pl.hold_point.global_position
		await get_tree().physics_frame
	pl._process(0.016)
	print("HOLDING battery: hint='", pl.hint, "'")
	c.ok(pl.held == bat, "player holds the battery")
	c.ok(pl.hint.contains("Install"), "holding the battery over the slot offers to install it ('%s')" % pl.hint)
	pl._on_grab()
	c.ok(slot.is_installed(), "battery installed by clicking")
	c.ok(pl.held == null, "hands are empty after installing")
	c.ok(slot.bolts == 0, "battery starts with loose bolts")
	Input.action_press("tighten")
	for i in 150:
		pl._process(0.016)
	Input.action_release("tighten")
	print("AFTER R hold: bolts ", slot.bolts, "/", slot.max_bolts(), " hint='", pl.hint, "'")
	c.ok(slot.max_bolts() > 0 and slot.is_tight(), "holding R tightens every bolt (%d/%d)" % [slot.bolts, slot.max_bolts()])
	# hood
	pl.global_position = car.global_position + (-car.global_basis.z) * 2.6
	var hood_node := car.find_child("Interact_hood", true, false) as Node3D
	if not c.ok(hood_node != null, "car has a hood interaction area"):
		c.finish()
		return
	var hood := hood_node.global_position
	var d2 := (hood - (pl.global_position + Vector3.UP * 1.65)).normalized()
	pl.set_look(atan2(-d2.x, -d2.z), asin(d2.y))
	for i in 3: await get_tree().physics_frame
	pl._process(0.016)
	print("HOOD: hint='", pl.hint, "' target=", pl._target, " hood_open=", car.hood_open)
	c.ok(pl._target == hood_node, "crosshair finds the hood")
	c.ok(pl.hint == ("[E] Close hood" if car.hood_open else "[E] Open hood"), "hood prompt matches its state ('%s')" % pl.hint)
	c.finish()
