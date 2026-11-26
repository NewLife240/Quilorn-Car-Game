extends Node
var world: World
func _ready() -> void:
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in 3: await get_tree().physics_frame
	var car: Vehicle = world.vehicles.filter(func(v): return v.owned)[0]
	var pl: Player = world.player
	var bat: Item = null
	for c in world.dynamic_root.get_children():
		if c is Item and c.item_id == "battery" and c.shop_price == 0: bat = c
	# stand 1.6m from the battery slot, look at it
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
	pl._grab(bat)
	for i in 3: await get_tree().physics_frame
	pl._process(0.016)
	print("HOLDING battery: hint='", pl.hint, "'")
	pl._on_grab()
	print("INSTALLED: ", slot.is_installed(), " bolts ", slot.bolts)
	Input.action_press("tighten")
	for i in 150: 
		pl._process(0.016)
	Input.action_release("tighten")
	print("AFTER R hold: bolts ", slot.bolts, "/", slot.max_bolts(), " hint='", pl.hint, "'")
	# hood area & door
	pl.global_position = car.global_position + (-car.global_basis.z) * 2.6 + Vector3.UP * 0.0
	var hood: Vector3 = (car.find_child("Interact_hood", true, false) as Node3D).global_position
	var d2 := (hood - (pl.global_position + Vector3.UP * 1.65)).normalized()
	pl.set_look(atan2(-d2.x, -d2.z), asin(d2.y))
	for i in 3: await get_tree().physics_frame
	pl._process(0.016)
	print("hood dist=", (pl.global_position + Vector3.UP * 1.65).distance_to(hood), " hood_open=", car.hood_open)
	print("HOOD: hint='", pl.hint, "' target=", pl._target)
	get_tree().quit()
