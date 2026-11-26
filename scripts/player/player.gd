extends CharacterBody3D
class_name Player
## First-person player: walking, carrying items, installing parts, using tools, driving.

const WALK := 4.2
const SPRINT := 7.0
const JUMP := 4.6
const REACH := 2.8

var head: Node3D
var cam: Camera3D
var ray: RayCast3D
var hold_point: Node3D
var held: Item = null
var vehicle: Vehicle = null
var hint := ""
var info := ""
var _yaw := 0.0
var _pitch := 0.0
var _bob := 0.0
var _tool_timer := 0.0
var _use_hold := 0.0
var _ghost_slot: PartSlot = null
var _audio: AudioStreamPlayer3D
var _target: Object = null
var _crouch := 0.0
var _step_acc := 0.0
var _steps: AudioStreamPlayer
var _was_floor := true
var _fall_v := 0.0
var swimming := false
const STEP_SETS := {"ground": ["ground_1", "ground_2"], "wet": ["wet_1", "wet_2", "wet_3"], "wood": ["wood_1", "wood_2", "wood_3", "wood_4"]}
var _step_streams := {}


func _ready() -> void:
	add_to_group("player")
	Game.player = self
	collision_layer = 1 << 3
	collision_mask = 1 | (1 << 1) | (1 << 2)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	cs.shape = cap
	cs.position.y = 0.89
	add_child(cs)
	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 3000.0
	cam.current = true
	cam.top_level = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | (1 << 2) | (1 << 4)
	ray.collide_with_areas = true
	ray.add_exception(self)
	cam.add_child(ray)
	hold_point = Node3D.new()
	hold_point.position = Vector3(0.0, -0.25, -1.1)
	cam.add_child(hold_point)
	_audio = AudioStreamPlayer3D.new()
	add_child(_audio)
	_steps = AudioStreamPlayer.new()
	_steps.max_polyphony = 2
	add_child(_steps)
	for k in STEP_SETS.keys():
		_step_streams[k] = STEP_SETS[k].map(func(n): return load("res://assets/sounds/steps/%s.ogg" % n))
	Game.settings_changed.connect(func(): cam.fov = Game.settings.fov)
	cam.fov = Game.settings.fov


func look_dir() -> Vector3:
	return -cam.global_basis.z


func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	if vehicle:
		if event.is_action_pressed("interact"):
			exit_vehicle()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Game.settings.sensitivity * 0.01
		_yaw -= event.relative.x * s
		_pitch = clampf(_pitch - event.relative.y * s * (-1.0 if Game.settings.invert_y else 1.0), -1.5, 1.5)
	if event.is_action_pressed("grab"):
		_on_grab()
	elif event.is_action_pressed("throw") and held:
		var it := held
		_release()
		it.apply_central_impulse(look_dir() * clampf(it.mass * 6.0, 2.0, 60.0))
	elif event.is_action_pressed("interact"):
		_on_interact()


func _physics_process(dt: float) -> void:
	if vehicle:
		global_position = vehicle.global_position
		return
	rotation.y = _yaw
	head.rotation.x = _pitch
	var input := Vector2(Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("back") - Input.get_action_strength("forward"))
	if Game.ui_open:
		input = Vector2.ZERO
	var heavy := held != null and held.mass > 40.0
	var spd := SPRINT if Input.is_action_pressed("sprint") and not heavy else WALK
	if heavy:
		spd *= 0.55
	_crouch = move_toward(_crouch, 1.0 if Input.is_action_pressed("crouch") and not Game.ui_open else 0.0, dt * 5.0)
	spd *= lerpf(1.0, 0.5, _crouch)
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	# water: wade slowly, swim when deep
	var wl: float = Game.world.terrain.water_level if Game.world else -100.0
	var depth := wl - global_position.y
	swimming = depth > 1.25
	if depth > 0.4:
		spd *= clampf(1.0 - (depth - 0.4) * 0.6, 0.45, 1.0)
	var accel := 12.0 if is_on_floor() or swimming else 2.5
	velocity.x = move_toward(velocity.x, dir.x * spd, accel * spd * dt)
	velocity.z = move_toward(velocity.z, dir.z * spd, accel * spd * dt)
	if swimming:
		var target_y := wl - 1.4
		if Input.is_action_pressed("jump"):
			target_y = wl - 1.1
		velocity.y = clampf((target_y - global_position.y) * 2.5, -2.0, 2.0)
	elif not is_on_floor():
		velocity.y -= 9.81 * dt
		_fall_v = minf(_fall_v, velocity.y)
	elif Input.is_action_just_pressed("jump") and not Game.ui_open:
		velocity.y = JUMP
	move_and_slide()
	if is_on_floor() and not _was_floor and _fall_v < -3.0:
		_play_step(1.0)
	if is_on_floor():
		_fall_v = 0.0
	_was_floor = is_on_floor()
	# push rigid bodies (cars, items)
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb and rb != held:
			var push := -c.get_normal()
			push.y = 0
			if rb is Vehicle:
				rb.apply_impulse(push * 72.0 * dt, c.get_position() - rb.global_position)
			else:
				rb.apply_central_impulse(push * minf(rb.mass, 8.0) * 0.6 * dt)
	# head bob & crouch
	var hv := Vector2(velocity.x, velocity.z).length()
	if (is_on_floor() or swimming) and hv > 0.5:
		_bob += dt * hv * 2.2
		_step_acc += hv * dt
		var stride := 1.9 if hv > 5.0 else 1.45
		if swimming:
			stride = 2.6
		if _step_acc > stride:
			_step_acc = 0.0
			_play_step(clampf(hv / 6.0, 0.4, 1.0))
	head.position.y = lerpf(1.65, 1.05, _crouch) + sin(_bob) * 0.03 * clampf(hv / 4.0, 0, 1)
	# carried item follows the hold point
	if held:
		var tgt := hold_point.global_position
		if held.item_id.begins_with("engine"):
			tgt = global_position + look_dir() * Vector3(1, 0, 1) * 1.3 + Vector3.UP * 0.6
		var d := tgt - held.global_position
		if d.length() > 3.0:
			_release()
		else:
			held.linear_velocity = (d * 14.0).limit_length(14.0)
			held.angular_velocity *= 0.7
			var want := Basis(Vector3.UP, _yaw)
			var diff := (want * held.global_basis.inverse()).get_euler()
			held.angular_velocity = diff * 6.0
	# keep the player out of the world floor if something goes wrong
	var t: Terrain = Game.world.terrain if Game.world else null
	if t and global_position.y < t.height_at(global_position.x, global_position.z) - 2.0:
		global_position.y = t.height_at(global_position.x, global_position.z) + 1.0
		velocity = Vector3.ZERO


func _process(dt: float) -> void:
	# camera follows the interpolated body every rendered frame (smooth at any FPS)
	if not vehicle:
		var o := get_global_transform_interpolated().origin
		cam.global_transform = Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch), o + Vector3.UP * head.position.y)
	if vehicle:
		hint = ""
		info = ""
		return
	_update_target()
	_continuous_actions(dt)


func _update_target() -> void:
	hint = ""
	info = ""
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * REACH, 1 | (1 << 2) | (1 << 4))
	q.collide_with_areas = true
	var ex: Array[RID] = [get_rid()]
	if held:
		ex.append(held.get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = hit.get("collider") if hit else null
	_target = col
	if _ghost_slot:
		_ghost_slot.show_ghost(false)
		_ghost_slot = null
	if held:
		var def := DB.part(held.item_id)
		hint = "[LMB] Drop   [RMB] Throw"
		info = held.display_name()
		if col is PartSlot:
			var s := col as PartSlot
			if s.can_accept(held.item_id):
				s.show_ghost(true)
				_ghost_slot = s
				hint = "[LMB] Install %s" % def.name
			elif def.has("fluid"):
				hint = _fluid_hint(col, def)
			elif def.has("repair") and s.is_installed():
				hint = "[Hold E] Repair %s  (%d%%)" % [DB.part(s.part_id()).name, int(s.cond())]
		elif col is Area3D and col.has_meta("vehicle_action") and col.get_meta("vehicle_action") == "trunk":
			hint = "[E] Put in trunk"
			info = (col.get_meta("vehicle_ref") as Vehicle).trunk_text()
		elif col is Area3D and col.has_meta("vehicle_action") and def.has("fluid"):
			hint = _fluid_hint(col, def)
		elif col is Area3D and col.has_meta("vehicle_action") and def.has("paint"):
			hint = "[Hold E] Repaint the car"
		return
	if col == null:
		return
	if col is PartSlot:
		var s := col as PartSlot
		info = s.describe()
		if s.is_installed():
			var h := []
			if not s.is_tight():
				h.append("[Hold R] Tighten")
			if s.bolts > 0:
				h.append("[Hold T] Loosen")
			if s.bolts == 0:
				h.append("[LMB] Detach" if not s.has_children_installed() else "(remove attached parts first)")
			hint = "  ".join(h)
		else:
			hint = "Needs: %s" % DB.slot_display(s.slot_name)
	elif col is Item:
		var it := col as Item
		info = it.display_name()
		hint = "[LMB] Pick up" if it.shop_price <= 0 else "[E] Buy for ₴%d" % it.shop_price
	elif col is Area3D and col.has_meta("vehicle_action"):
		var v: Vehicle = col.get_meta("vehicle_ref")
		match col.get_meta("vehicle_action"):
			"door":
				info = v.def.name
				if not v.owned:
					hint = "For sale: ₴%d   [E] Buy" % v.for_sale_price
				elif v.global_basis.y.y < 0.4:
					hint = "[E] Flip vehicle back"
				else:
					hint = "[E] Get in"
			"hood":
				hint = "[E] " + ("Close" if v.hood_open else "Open") + (" hood" if v.meta.hood.kind == "hood" else " engine hatch")
			"fuel_cap":
				info = "Fuel %.1f / %.0f L" % [v.fuel, v.def.fuel_cap]
			"trunk":
				info = v.trunk_text()
				hint = "[E] Take out last item" if not v.trunk.is_empty() else ""
	elif col.has_meta("interact_text"):
		hint = "[E] " + str(col.get_meta("interact_text"))
		if col.has_meta("interact_info"):
			info = str(col.get_meta("interact_info"))
		elif col.has_method("get_info"):
			info = col.get_info()


func _fluid_hint(col: Object, def: Dictionary) -> String:
	var kind: String = def.fluid
	var v: Vehicle = null
	var ok := false
	if col is PartSlot:
		v = col.vehicle
		ok = (kind == "oil" and col.slot_name == "engine" and col.is_installed()) or (kind == "coolant" and col.slot_name == "radiator" and col.is_installed()) or (kind == "fuel" and col.slot_name == "fuel_tank" and col.is_installed())
	elif col is Area3D and col.get_meta("vehicle_action") == "fuel_cap":
		v = col.get_meta("vehicle_ref")
		ok = kind == "fuel"
	if ok and float(held.data.get("fill", 0)) > 0.0:
		var lvl := ""
		match kind:
			"fuel": lvl = "%.1f/%.0f L" % [v.fuel, v.def.fuel_cap]
			"oil": lvl = "%.1f/%.1f L" % [v.oil, v.OIL_CAP]
			"coolant": lvl = "%.1f/%.1f L" % [v.coolant, v.COOLANT_CAP]
		return "[Hold E] Pour %s  (%s)" % [kind, lvl]
	return "[LMB] Drop   [RMB] Throw"


func _continuous_actions(dt: float) -> void:
	if Game.ui_open:
		return
	_tool_timer -= dt
	var col := _target
	# wrench
	if col is PartSlot and (col as PartSlot).is_installed() and held == null:
		var s := col as PartSlot
		if Input.is_action_pressed("tighten") and _tool_timer <= 0.0:
			if s.tighten():
				_click()
			_tool_timer = 0.28
		elif Input.is_action_pressed("loosen") and _tool_timer <= 0.0:
			if s.loosen():
				_click()
			_tool_timer = 0.28
	# pouring / repairing (hold E)
	if held and Input.is_action_pressed("interact"):
		var def := DB.part(held.item_id)
		if def.has("fluid") and float(held.data.get("fill", 0)) > 0.0:
			var v: Vehicle = null
			if col is PartSlot:
				v = col.vehicle
			elif col is Area3D and col.has_meta("vehicle_ref"):
				v = col.get_meta("vehicle_ref")
			if v and _fluid_hint(col, def).begins_with("[Hold E]"):
				var rate := 2.0 if def.fluid == "fuel" else 0.6
				var amt := minf(rate * dt, float(held.data.fill))
				var added := v.add_fluid(def.fluid, amt)
				held.data.fill = float(held.data.fill) - added
		elif def.has("paint") and col is Area3D and col.has_meta("vehicle_ref"):
			_use_hold += dt
			if _use_hold > 2.5:
				_use_hold = 0.0
				var pv: Vehicle = col.get_meta("vehicle_ref")
				pv.apply_paint(pv.paint + 1)
				Game.notify("Fresh paint!")
				var it2 := held
				_release()
				it2.queue_free()
		elif def.has("repair") and col is PartSlot and (col as PartSlot).is_installed():
			_use_hold += dt
			if _use_hold > 2.0:
				_use_hold = 0.0
				var s := col as PartSlot
				s.data.cond = minf(100.0, s.cond() + float(def.repair))
				Game.notify("Repaired %s to %d%%" % [DB.part(s.part_id()).name, int(s.cond())])
				var it := held
				_release()
				it.queue_free()
	else:
		_use_hold = 0.0


func _click() -> void:
	_audio.stream = load("res://assets/sounds/ui/wrench.ogg")
	_audio.volume_db = -8
	_audio.pitch_scale = randf_range(1.3, 1.6)
	_audio.play()


func _play_step(strength: float) -> void:
	var kind := "ground"
	var t: Terrain = Game.world.terrain if Game.world else null
	var wl: float = t.water_level if t else -100.0
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.6, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if global_position.y < wl + 0.1:
		kind = "wet"
	elif hit and hit.collider and hit.collider.has_meta("terrain") and t:
		var sf := t.surface(global_position.x, global_position.z)
		if sf.mud > 0.35 or t.wetness > 0.45:
			kind = "wet"
	elif hit and hit.collider and not hit.collider.has_meta("terrain"):
		var n: Node = hit.collider
		var nm := String(n.get_parent().name if n.get_parent() else n.name)
		if nm.begins_with("home_house") or nm.begins_with("khata") or nm.begins_with("sawmill") or nm.begins_with("lumber"):
			kind = "wood"
	var arr: Array = _step_streams[kind]
	_steps.stream = arr.pick_random()
	_steps.pitch_scale = randf_range(0.9, 1.1)
	_steps.volume_db = lerpf(-20.0, -7.0, strength) + (2.0 if kind == "wet" else 0.0)
	_steps.play()


func _on_grab() -> void:
	var col := _target
	if held:
		if _ghost_slot and col == _ghost_slot:
			var s := _ghost_slot
			var it := held
			_release()
			s.install(it.data, 0)
			it.queue_free()
			_click()
			Game.notify("Installed %s - tighten the bolts [R]" % DB.part(s.part_id()).name)
			return
		_release()
		return
	if col is Item:
		var it := col as Item
		if it.shop_price > 0:
			Game.notify("Buy it first [E]")
			return
		_grab(it)
	elif col is PartSlot:
		var s := col as PartSlot
		if s.is_installed() and s.bolts == 0 and not s.has_children_installed():
			var d := s.remove()
			var it := Item.spawn(Game.world.dynamic_root, d.id, d, Transform3D(Basis(Vector3.UP, _yaw), s.global_position + Vector3.UP * 0.1))
			_grab(it)
			_click()
		elif s.is_installed() and s.bolts > 0:
			Game.notify("Loosen the bolts first [T]")


func _grab(it: Item) -> void:
	held = it
	add_collision_exception_with(it)
	it.add_collision_exception_with(self)
	_audio.stream = load("res://assets/sounds/ui/pickup.ogg")
	_audio.volume_db = -10
	_audio.pitch_scale = randf_range(0.9, 1.1)
	_audio.play()
	it.held = true
	it.gravity_scale = 0.0
	it.sleeping = false
	it.collision_mask = 1 | (1 << 1)
	ray.add_exception(it)


func _release() -> void:
	if held == null:
		return
	held.held = false
	remove_collision_exception_with(held)
	held.remove_collision_exception_with(self)
	held.gravity_scale = 1.0
	held.collision_mask = 1 | (1 << 1) | (1 << 2)
	ray.remove_exception(held)
	held = null


func _on_interact() -> void:
	var col := _target
	if col == null:
		return
	if col is Item and (col as Item).shop_price > 0:
		var it := col as Item
		if Game.spend(it.shop_price, "Bought " + DB.part(it.item_id).name):
			it.shop_price = 0
		return
	if col is Area3D and col.has_meta("vehicle_action"):
		var v: Vehicle = col.get_meta("vehicle_ref")
		match col.get_meta("vehicle_action"):
			"trunk":
				if held:
					var it := held
					_release()
					if v.trunk_store(it):
						it.queue_free()
				else:
					var d := v.trunk_take()
					if not d.is_empty():
						var it := Item.spawn(Game.world.dynamic_root, d.id, d, Transform3D(Basis(Vector3.UP, _yaw), (col as Node3D).global_position + Vector3.UP * 0.3))
						_grab(it)
			"door":
				if not v.owned:
					if Game.world.buy_vehicle(v):
						return
					return
				if v.global_basis.y.y < 0.4:
					v.reset_upright()
					return
				if held:
					_release()
				enter_vehicle(v)
			"hood":
				v.toggle_hood()
		return
	if col.has_method("interact"):
		col.interact(self)
	elif col is Node and (col as Node).get_parent() and (col as Node).get_parent().has_method("interact"):
		(col as Node).get_parent().interact(self)


func enter_vehicle(v: Vehicle) -> void:
	vehicle = v
	visible = false
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = true
	velocity = Vector3.ZERO
	v.enter(self)


func exit_vehicle() -> void:
	if vehicle == null:
		return
	var v := vehicle
	var p := v.exit_vehicle()
	vehicle = null
	visible = true
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = false
	global_position = p
	reset_physics_interpolation()
	var f := -v.global_basis.z
	_yaw = atan2(-f.x, -f.z) + PI * 0.5
	_pitch = 0.0
	cam.current = true


func save_state() -> Dictionary:
	return {"pos": var_to_str(global_position), "yaw": _yaw, "vehicle": Game.world.vehicles.find(vehicle) if vehicle else -1}
