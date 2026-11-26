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
	var qq := PhysicsRayQueryParameters3D.create(pl.cam.global_position, hood, 1 | 4 | 16)
	qq.collide_with_areas = true
	qq.exclude = [pl.get_rid()]
	var hh := pl.get_world_3d().direct_space_state.intersect_ray(qq)
	print("ray to hood hits: ", hh.get("collider"), " at ", hh.get("position"), " hood at ", hood, " cam ", pl.cam.global_position)
	pl.ray.force_raycast_update()
	print("mask=", pl.ray.collision_mask, " areas=", pl.ray.collide_with_areas, " bodies=", pl.ray.collide_with_bodies, " from_inside=", pl.ray.hit_from_inside, " cam=", pl.cam.global_position, " raypos=", pl.ray.global_position)
	print("raycast colliding=", pl.ray.is_colliding(), " col=", pl.ray.get_collider(), " ray_to=", pl.ray.to_global(pl.ray.target_position), " enabled=", pl.ray.enabled, " cam fwd=", -pl.cam.global_basis.z, " dir=", d2)
	print("hood dist=", (pl.global_position + Vector3.UP * 1.65).distance_to(hood), " hood_open=", car.hood_open)
	var q3 := PhysicsRayQueryParameters3D.create(pl.cam.global_position, pl.cam.global_position - pl.cam.global_basis.z * 2.8, 21)
	q3.collide_with_areas = true
	q3.exclude = [pl.get_rid()]
	print("fwd ray: ", pl.get_world_3d().direct_space_state.intersect_ray(q3))
	pl._update_target()
	print("after direct update: ", pl._target)
	print("HOOD: hint='", pl.hint, "' target=", pl._target)
	get_tree().quit()
