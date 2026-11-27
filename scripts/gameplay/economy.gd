extends Node
## Economy & gameplay systems: industries, consumers, delivery jobs, trading, hired routes,
## shops, fuel pumps, car market, junkyard, sleeping, tutorial.

const STORAGE := 80
const FUEL_PRICE := 2.2
const MAX_ACTIVE_JOBS := 3
# --- balance knobs (simulated with tools/economy_sim.py, which reads these constants)
const SMALL_PARCEL_JOBS := 4       # 1-2 unit parcel runs always on the board, so the starter car has work
const DRIVER_WAGE := 600           # per hired driver per day
const DRIVER_HIRE := 500           # one-off hiring fee
const ROUTE_UNITS := 6             # units a hired driver hauls per trip
const ROUTE_LEGS := 2.0            # drivers drive there and back (trip = 30 min + legs * distance / 6 m per min)
const PRICE_FLOOR := 0.5           # oversupplied buyers still pay half the base price
const INDUSTRY_PRICE_CAP := 1.0    # factories buy inputs at no more than base price (no scarcity premium)
const CONSUMER_STOCK_MAX := 60     # shops/warehouse resell surplus, so a glut clears within a day

var world: Node
var industries := {}      # key -> {key, def, owner, inp:{}, out:{}, level, pos, load, deliver, office, prod}
var consumers := {}       # key -> {key, def, stock:{}, deliver}
var jobs: Array = []      # available
var active: Array = []    # accepted
var routes: Array = []    # hired driver routes
var next_id := 1
var _minute_acc := 0.0
var _zones: Array = []    # [{pos, kind:"load"/"deliver", site, radius}]
var market_lot: Dictionary = {}
var junk_site: Dictionary = {}
var _last_market_day := -1
var _last_junk_day := -1
var _pump_target: Node = null
var _last_cost_day := -1
var _ff := false          # fast-forwarding (sleep): no per-trip notifications
var _ff_income := 0


func setup(w: Node) -> void:
	world = w
	Game.hour_passed.connect(_on_hour)
	_build_sites()


# ------------------------------------------------------------------ sites
func _ip_world(ip: Dictionary) -> Vector3:
	return (ip.node as Node3D).global_position


func _build_sites() -> void:
	var by_obj := {}
	for ip in world.props.ips:
		var o: Dictionary = ip.obj
		var k := str(world.props.objects.find(o))
		(by_obj.get_or_add(k, []) as Array).append(ip)
	for k in by_obj.keys():
		var lst: Array = by_obj[k]
		var o: Dictionary = lst[0].obj
		var ipmap := {}
		for ip in lst:
			ipmap[ip.name] = ip
		var site_key := ""
		if o.has("industry"):
			site_key = o.industry
			var d: Dictionary = DB.INDUSTRIES[site_key]
			industries[site_key] = {"key": site_key, "owner": "npc", "inp": {}, "out": {}, "level": 1, "prod": 0.0,
				"pos": Vector3(o.x, o.y, o.z), "name": d.name}
			for g in d.in.keys():
				industries[site_key].inp[g] = randi_range(4, 16)
			for g in d.out.keys():
				industries[site_key].out[g] = randi_range(6, 20)
		elif DB.CONSUMERS.has(o.kind):
			site_key = o.kind
			consumers[site_key] = {"key": site_key, "stock": {}, "pos": Vector3(o.x, o.y, o.z), "name": DB.CONSUMERS[o.kind].name}
			for g in DB.CONSUMERS[o.kind].buys:
				consumers[site_key].stock[g] = randi_range(5, 25)
		for ipn in ipmap.keys():
			var node: Node3D = ipmap[ipn].node
			var p := node.global_position
			if ipn == "load" and site_key != "":
				_add_zone(p, "load", site_key)
			elif ipn == "deliver" and site_key != "":
				_add_zone(p, "deliver", site_key)
			elif ipn == "office" and site_key != "":
				_add_interact(node, "Manage " + industries[site_key].name, _open_office.bind(site_key), Vector3(1.2, 2.0, 1.2))
			elif ipn == "bed":
				_add_interact(node, "Sleep until morning (saves game)", _sleep, Vector3(1.5, 2.0, 1.5))
			elif ipn == "charger":
				_add_interact(node, "Battery charger - charges batteries lying on the bench (₴5)", _charge_batteries.bind(node), Vector3(0.42, 0.35, 0.36))
			elif ipn == "light":
				var l := OmniLight3D.new()
				l.omni_range = 9.0
				l.light_energy = 1.4
				l.light_color = Color(1, 0.9, 0.75)
				l.shadow_enabled = true
				node.add_child(l)
			elif ipn == "shop_general" or ipn == "shop_gas":
				_add_interact(node, "Shop", func(_p): world.hud.open_shop("general", _pickup_point(ipmap, node, ipn)), Vector3(1.5, 2.2, 1.0))
			elif ipn == "shop_parts":
				_add_interact(node, "Auto parts store", func(_p): world.hud.open_shop("parts", _pickup_point(ipmap, node, ipn)), Vector3(1.6, 2.2, 1.0))
			elif ipn.begins_with("pump"):
				var a := _add_interact(node, "Fuel pump", _pump_use, Vector3(1.0, 2.0, 1.0))
				a.set_meta("pump", true)
			elif ipn == "car_market":
				_add_interact(node, "Car market office", func(_p): world.hud.open_car_market(), Vector3(1.4, 2.2, 1.0))
				market_lot = {"spots": [], "sell": Vector3.ZERO}
				for ip2 in lst:
					if ip2.name.begins_with("spot_"):
						market_lot.spots.append(ip2.node)
					elif ip2.name == "sell":
						market_lot.sell = ip2.node.global_position
				_add_marker(market_lot.sell, Color(0.3, 0.6, 1.0), "SELL CAR")
			elif ipn == "junk":
				_add_interact(node, "Junkyard: sell loose parts lying here", _sell_junk_parts.bind(node), Vector3(1.4, 2.2, 1.0))
				junk_site = {"node": node, "pos": node.global_position}


# Where bought items go for buildings without an IP_pickup pallet, as an offset from the shop's
# interaction point in building space. Both counters are just inside the door, so the old
# "1.5 m along +Z" fallback dropped the items inside the village shop / gas kiosk where nobody saw them.
const PICKUP_FROM_COUNTER := {
	"shop_general": Vector3(2.6, -0.6, -1.6),   # village shop: on the ground right of the front steps
	"shop_gas": Vector3(2.6, -0.6, -1.2),       # gas station: in front of the kiosk, beside its door
}


func _pickup_point(ipmap: Dictionary, counter: Node3D, ipn: String) -> Vector3:
	if ipmap.has("pickup"):
		return (ipmap.pickup.node as Node3D).global_position + Vector3.UP * 0.5
	var off: Vector3 = PICKUP_FROM_COUNTER.get(ipn, Vector3(0, -0.6, -2.0))
	return counter.global_transform * off + Vector3.UP * 0.4


func _add_interact(at: Node3D, text: String, cb: Callable, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 1 << 4
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.set_meta("interact_text", text)
	a.set_script(preload("res://scripts/gameplay/interactable.gd"))
	a.callback = cb
	at.add_child(a)
	return a


func _add_zone(p: Vector3, kind: String, site: String) -> void:
	p = _off_road(p, site)
	_zones.append({"pos": p, "kind": kind, "site": site, "radius": 7.0})
	var nm := site_name(site) if (industries.has(site) or consumers.has(site)) else site
	_add_marker(p, Color(1.0, 0.8, 0.1) if kind == "load" else Color(0.2, 1.0, 0.4), ("LOAD  " if kind == "load" else "UNLOAD  ") + nm)


## Push a zone off the road surface towards its site so markers sit on the yard, not on the asphalt.
func _off_road(p: Vector3, site: String) -> Vector3:
	var center := p
	if industries.has(site):
		center = industries[site].pos
	elif consumers.has(site):
		center = consumers[site].pos
	for i in range(12):
		var nr: Array = world.roads.nearest(p)
		var rw := 4.0
		if int(nr[3]) >= 0:
			rw = float(world.roads.data[nr[3]].w) * 0.5
		if float(nr[0]) > rw + 7.5:
			break
		var away: Vector3 = (p - (nr[1] as Vector3))
		away.y = 0
		if away.length() < 0.1:
			away = (center - p)
		p += away.normalized() * 2.0
	return world.ground(p)


func _add_marker(p: Vector3, col: Color, label: String) -> void:
	# subtle painted ring on the ground + a small sign post
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 6.75
	tm.outer_radius = 7.0
	tm.rings = 48
	tm.ring_segments = 4
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1, 0.02, 1)
	mi.visibility_range_end = 150.0
	world.add_child(mi)
	mi.global_position = world.ground(p) + Vector3.UP * 0.06
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 1.8, 0.08)
	post.mesh = pm
	post.material_override = MatLib.get_mat("metal")
	world.add_child(post)
	var edge: Vector3 = world.ground(p + Vector3(6.9, 0, 0))
	post.global_position = edge + Vector3.UP * 0.9
	var l := Label3D.new()
	l.text = label
	l.font_size = 40
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.modulate = col.lightened(0.3)
	l.outline_size = 10
	l.shaded = false
	l.visibility_range_end = 45.0
	world.add_child(l)
	l.global_position = edge + Vector3.UP * 2.05


func zone_at(p: Vector3) -> Dictionary:
	for z in _zones:
		if Vector2(p.x - z.pos.x, p.z - z.pos.z).length() < z.radius:
			return z
	return {}


func site_name(key: String) -> String:
	if industries.has(key):
		return industries[key].name
	if consumers.has(key):
		return consumers[key].name
	return key


func site_pos(key: String) -> Vector3:
	for z in _zones:
		if z.site == key:
			return z.pos
	if industries.has(key):
		return industries[key].pos
	if consumers.has(key):
		return consumers[key].pos
	return Vector3.ZERO


# ------------------------------------------------------------------ prices
func price(good: String, site: String = "") -> int:
	var base: float = DB.GOODS[good].price
	var stock := 20.0
	var cap := 1.45
	if consumers.has(site):
		stock = float(consumers[site].stock.get(good, 20))
	elif industries.has(site):
		stock = float(industries[site].inp.get(good, 20))
		cap = INDUSTRY_PRICE_CAP
	return int(base * clampf(1.45 - stock / 50.0, PRICE_FLOOR, cap))


func buyers_of(good: String) -> Array:
	var out := []
	for k in consumers.keys():
		if good in DB.CONSUMERS[k].buys:
			out.append(k)
	for k in industries.keys():
		if DB.INDUSTRIES[k].in.has(good):
			out.append(k)
	return out


# ------------------------------------------------------------------ simulation
func _process(dt: float) -> void:
	if world == null:
		return
	_minute_acc += dt * Game.MINUTES_PER_SECOND * Game.time_scale
	while _minute_acc >= 1.0:
		_minute_acc -= 1.0
		_tick_minute()
	_update_pump(dt)


func _tick_minute() -> void:
	for k in industries.keys():
		var ind: Dictionary = industries[k]
		var d: Dictionary = DB.INDUSTRIES[k]
		var rate: float = d.rate * (1.0 + 0.5 * (ind.level - 1)) / 60.0
		var full := false
		for g in d.out.keys():
			if int(ind.out.get(g, 0)) >= STORAGE * ind.level:
				full = true
		var have := true
		for g in d.in.keys():
			if int(ind.inp.get(g, 0)) < int(d.in[g]):
				have = false
		if not full and have:
			ind.prod += rate
			while ind.prod >= 1.0:
				ind.prod -= 1.0
				for g in d.in.keys():
					ind.inp[g] = int(ind.inp[g]) - int(d.in[g])
				for g in d.out.keys():
					ind.out[g] = int(ind.out.get(g, 0)) + int(d.out[g])
	for k in consumers.keys():
		var c: Dictionary = consumers[k]
		for g in c.stock.keys():
			if randf() < DB.CONSUMERS[k].use_rate / 60.0:
				c.stock[g] = maxi(0, int(c.stock[g]) - 1)
	# hired routes
	for r in routes:
		r.t = float(r.t) + 1.0
		if r.t >= float(r.trip):
			r.t = 0.0
			_route_trip(r)


func _on_hour(day: int, hour: int) -> void:
	# NPC haulers keep the world economy moving slowly
	for k in industries.keys():
		var ind: Dictionary = industries[k]
		var d: Dictionary = DB.INDUSTRIES[k]
		if ind.owner == "npc":
			for g in d.in.keys():
				if randf() < 0.35:
					ind.inp[g] = mini(STORAGE, int(ind.inp[g]) + randi_range(1, 3))
			for g in d.out.keys():
				if int(ind.out[g]) > 40 and randf() < 0.5:
					ind.out[g] = int(ind.out[g]) - randi_range(2, 6)
	_generate_jobs()
	# expire jobs
	var now := day * 1440 + hour * 60
	jobs = jobs.filter(func(j): return int(j.expires) > now)
	# charge once per new day - also when the player slept through midnight
	if _last_cost_day < 0:
		_last_cost_day = day
	elif day != _last_cost_day:
		_last_cost_day = day
		_daily_costs()
	if day != _last_market_day and hour == 6:
		if day - _last_market_day >= 2 or _last_market_day < 0:
			_refresh_car_market()
	if day != _last_junk_day and hour == 7:
		_refresh_junkyard()


func _daily_costs() -> void:
	var total := 0
	for k in industries.keys():
		if industries[k].owner == "player":
			total += int(DB.INDUSTRIES[k].upkeep) * int(industries[k].level)
	for r in routes:
		total += DRIVER_WAGE * int(r.trucks)
	if total > 0:
		Game.add_money(-total, "Daily upkeep & wages")


# ------------------------------------------------------------------ jobs
func _generate_jobs() -> void:
	var tries := 0
	while jobs.size() < 14 and tries < 40:
		tries += 1
		var r := randf()
		if r < 0.35:
			# parcels between any two sites
			var keys: Array = industries.keys() + consumers.keys()
			var a: String = keys.pick_random()
			var b: String = keys.pick_random()
			if a == b:
				continue
			var dist := site_pos(a).distance_to(site_pos(b))
			var units := randi_range(1, 2) if randf() < 0.7 else randi_range(3, 6)
			_add_job("parcel", units, a, b, int(units * (45 + dist * 0.16)))
		else:
			var srcs := industries.keys().filter(func(k): return not industries[k].out.is_empty())
			var a: String = srcs.pick_random()
			var goods: Array = industries[a].out.keys()
			var g: String = goods.pick_random()
			if int(industries[a].out[g]) < 4:
				continue
			var dsts := buyers_of(g)
			if dsts.is_empty():
				continue
			var b: String = dsts.pick_random()
			var dist := site_pos(a).distance_to(site_pos(b))
			var units := randi_range(2, 12)
			if DB.GOODS[g].kind == "crate":
				units = randi_range(2, 8)
			_add_job(g, units, a, b, int(units * (28 + dist * 0.17)))
	# the board can fill up with bulk/crate jobs; keep a few small parcel runs for small cars
	var small := jobs.filter(func(j): return j.good == "parcel" and int(j.units) <= 2).size()
	var sites: Array = industries.keys() + consumers.keys()
	tries = 0
	while small < SMALL_PARCEL_JOBS and tries < 20:
		tries += 1
		var pa: String = sites.pick_random()
		var pb: String = sites.pick_random()
		if pa == pb:
			continue
		var pu := randi_range(1, 2)
		_add_job("parcel", pu, pa, pb, int(pu * (45 + site_pos(pa).distance_to(site_pos(pb)) * 0.16)))
		small += 1


func _add_job(good: String, units: int, a: String, b: String, pay: int) -> void:
	var now := Game.day * 1440 + int(Game.minutes)
	jobs.append({"id": next_id, "good": good, "units": units, "from": a, "to": b, "pay": pay, "expires": now + randi_range(240, 720), "loaded": false})
	next_id += 1


func accept_job(id: int) -> bool:
	if active.size() >= MAX_ACTIVE_JOBS:
		Game.notify("You can only take %d jobs at once" % MAX_ACTIVE_JOBS, "warn")
		return false
	for j in jobs:
		if j.id == id:
			jobs.erase(j)
			active.append(j)
			Game.notify("Job accepted: %d x %s  %s → %s" % [j.units, DB.GOODS[j.good].name, site_name(j.from), site_name(j.to)])
			return true
	return false


func cancel_job(id: int) -> void:
	for j in active:
		if j.id == id:
			if j.loaded:
				for v in world.vehicles:
					v.take_cargo(id)
			active.erase(j)
			Game.add_money(-int(j.pay * 0.1), "Job cancelled (penalty)")
			return


# ------------------------------------------------------------------ cargo actions (called when player presses J in a zone)
func cargo_action(v: Vehicle) -> void:
	var z := zone_at(v.global_position)
	if z.is_empty():
		Game.notify("Drive into a LOAD / UNLOAD marker first")
		return
	if v.speed_kmh > 3.0:
		Game.notify("Stop the vehicle first")
		return
	var did := false
	if z.kind == "load":
		# job cargo first
		for j in active:
			if j.from == z.site and not j.loaded:
				var kind: String = DB.GOODS[j.good].kind
				if not v.can_carry(j.good):
					Game.notify("%s can't carry %s" % [v.def.name, kind], "warn")
					continue
				if v.cargo_units() + int(j.units) > v.cargo_capacity():
					Game.notify("Not enough space (%d/%d)" % [v.cargo_units(), v.cargo_capacity()], "warn")
					continue
				if industries.has(j.from) and j.good != "parcel":
					var ind: Dictionary = industries[j.from]
					ind.out[j.good] = maxi(0, int(ind.out.get(j.good, 0)) - int(j.units))
				v.add_cargo(j.good, int(j.units), int(j.id))
				j.loaded = true
				did = true
				Game.notify("Loaded %d x %s for %s" % [j.units, DB.GOODS[j.good].name, site_name(j.to)])
		if not did:
			world.hud.open_trade(z.site, v)
			return
	else:
		for j in active.duplicate():
			if j.to == z.site and j.loaded:
				var c := v.take_cargo(int(j.id))
				if c.is_empty():
					continue
				var pay := int(float(j.pay) * clampf(float(c.cond) / 100.0, 0.2, 1.0))
				var now := Game.day * 1440 + int(Game.minutes)
				if now > int(j.expires) + 240:
					pay = int(pay * 0.7)
				Game.add_money(pay, "Delivered %d x %s" % [j.units, DB.GOODS[j.good].name])
				Game.stats.deliveries += 1
				_receive_goods(z.site, j.good, int(j.units))
				active.erase(j)
				did = true
		if not did:
			world.hud.open_trade(z.site, v)
			return


func _receive_goods(site: String, good: String, units: int) -> void:
	if consumers.has(site):
		var st: Dictionary = consumers[site].stock
		st[good] = mini(CONSUMER_STOCK_MAX, int(st.get(good, 0)) + units)
	elif industries.has(site) and DB.INDUSTRIES[site].in.has(good):
		var ind: Dictionary = industries[site]
		ind.inp[good] = mini(STORAGE * int(ind.level) * 2, int(ind.inp.get(good, 0)) + units)


## Trade: buy goods from a site's output into the vehicle (free if player-owned).
func trade_buy(site: String, good: String, units: int, v: Vehicle) -> void:
	if not industries.has(site):
		return
	var ind: Dictionary = industries[site]
	units = mini(units, int(ind.out.get(good, 0)))
	units = mini(units, v.cargo_capacity() - v.cargo_units())
	if units <= 0 or not v.can_carry(good):
		Game.notify("Can't load that", "warn")
		return
	var cost := 0 if ind.owner == "player" else int(DB.GOODS[good].price * 0.6) * units
	if cost > 0 and not Game.spend(cost, "Bought %d x %s" % [units, DB.GOODS[good].name]):
		return
	ind.out[good] = int(ind.out[good]) - units
	v.add_cargo(good, units, -1)


func trade_sell(site: String, good: String, v: Vehicle) -> void:
	var units := 0
	for c in v.cargo:
		if c.good == good and int(c.job) == -1:
			units += int(c.units)
	if units <= 0:
		return
	var p := price(good, site)
	var taken := v.take_good(good, units)
	Game.add_money(p * taken, "Sold %d x %s" % [taken, DB.GOODS[good].name])
	_receive_goods(site, good, taken)


# ------------------------------------------------------------------ business
func buy_industry(key: String) -> void:
	var ind: Dictionary = industries[key]
	if ind.owner == "player":
		return
	if Game.spend(int(DB.INDUSTRIES[key].price), "Bought " + ind.name):
		ind.owner = "player"
		Game.notify("%s is now yours. Its output can be loaded for free at its LOAD marker." % ind.name)


func upgrade_industry(key: String) -> void:
	var ind: Dictionary = industries[key]
	if ind.owner != "player" or int(ind.level) >= 3:
		return
	var cost := int(DB.INDUSTRIES[key].price * 0.6 * int(ind.level))
	if Game.spend(cost, "Upgraded " + ind.name):
		ind.level = int(ind.level) + 1


func hire_route(from: String, to: String, good: String) -> void:
	for r in routes:
		if r.from == from and r.to == to and r.good == good:
			if Game.spend(DRIVER_HIRE, "Hired another driver"):
				r.trucks = int(r.trucks) + 1
			return
	if not Game.spend(DRIVER_HIRE, "Hired a driver"):
		return
	routes.append({"from": from, "to": to, "good": good, "trucks": 1, "t": 0.0, "trip": route_trip_minutes(from, to)})


## Game minutes for one hired-driver round: loading + driving there and back.
func route_trip_minutes(from: String, to: String) -> float:
	return 30.0 + ROUTE_LEGS * site_pos(from).distance_to(site_pos(to)) / 6.0


func fire_route(i: int) -> void:
	if i >= 0 and i < routes.size():
		var r: Dictionary = routes[i]
		r.trucks = int(r.trucks) - 1
		if int(r.trucks) <= 0:
			routes.remove_at(i)


func _route_trip(r: Dictionary) -> void:
	var src: Dictionary = industries.get(r.from, {})
	if src.is_empty() or src.owner != "player":
		return
	var units := mini(ROUTE_UNITS * int(r.trucks), int(src.out.get(r.good, 0)))
	if units <= 0:
		return
	src.out[r.good] = int(src.out[r.good]) - units
	if industries.has(r.to) and industries[r.to].owner == "player":
		_receive_goods(r.to, r.good, units)
	else:
		var p := price(r.good, r.to)
		_receive_goods(r.to, r.good, units)
		if _ff:
			_ff_income += p * units
			Game.add_money(p * units)
		else:
			Game.add_money(p * units, "Route: %d x %s → %s" % [units, DB.GOODS[r.good].name, site_name(r.to)])


func _open_office(_p, key: String) -> void:
	world.hud.open_office(key)


# ------------------------------------------------------------------ services
func _sleep(_p) -> void:
	var h := Game.hour_f()
	if h > 6.0 and h < 19.0:
		Game.notify("You're not tired yet (sleep after 19:00)")
		return
	# the world keeps going overnight: production, hired drivers, job board, daily upkeep
	var skip := (1440.0 - Game.minutes + 420.0) if h >= 19.0 else (420.0 - Game.minutes)
	_fast_forward(int(skip))
	Game.minutes = 7.0 * 60.0
	Game.notify("You slept until 07:00")
	if _ff_income > 0:
		Game.notify("Overnight your drivers sold goods for ₴%d" % _ff_income, "money")
	Game.save_game()


## Run the economy for `total` game minutes in one go (sleeping), emitting every hour on the way.
func _fast_forward(total: int) -> void:
	_ff = true
	_ff_income = 0
	for i in range(total):
		Game.minutes += 1.0
		if Game.minutes >= 1440.0:
			Game.minutes -= 1440.0
			Game.day += 1
		_tick_minute()
		var hr := int(Game.minutes / 60.0)
		if hr != Game._last_hour:
			Game._last_hour = hr
			Game.hour_passed.emit(Game.day, hr)
	_ff = false


func _charge_batteries(_p, node: Node3D) -> void:
	var n := 0
	for c in world.dynamic_root.get_children():
		if c is Item and c.item_id == "battery" and c.global_position.distance_to(node.global_position) < 2.6:
			c.data.charge = 100.0 * float(c.data.get("cond", 100)) / 100.0
			n += 1
	if n == 0:
		Game.notify("Put a battery on the workbench first")
	elif Game.spend(5 * n, "Charged %d battery" % n):
		pass


func _pump_use(p) -> void:
	# toggle fuelling the nearest owned vehicle / held jerry can
	_pump_target = null
	var pl: Player = Game.player
	if pl.held and DB.part(pl.held.item_id).get("fluid", "") == "fuel":
		_pump_target = pl.held
	else:
		var best: Vehicle = null
		var bd := 7.0
		for v in world.vehicles:
			if v.owned:
				var d := (v.global_position as Vector3).distance_to(pl.global_position)
				if d < bd:
					bd = d
					best = v
		_pump_target = best
	if _pump_target == null:
		Game.notify("Park a vehicle next to the pump (or hold a jerry can)")
	else:
		Game.notify("Fuelling... (walk away to stop)  ₴%.1f / L" % FUEL_PRICE)


func _update_pump(dt: float) -> void:
	if _pump_target == null or not is_instance_valid(_pump_target):
		_pump_target = null
		return
	var pl: Player = Game.player
	var tp: Vector3 = _pump_target.global_position
	if pl.global_position.distance_to(tp) > 8.0 or pl.vehicle != null:
		_pump_target = null
		return
	var amt := 6.0 * dt
	var added := 0.0
	if _pump_target is Item:
		var it: Item = _pump_target
		var cap: float = DB.part(it.item_id).capacity
		added = minf(amt, cap - float(it.data.fill))
		it.data.fill = float(it.data.fill) + added
	else:
		added = (_pump_target as Vehicle).add_fluid("fuel", amt)
	if added <= 0.0001:
		Game.notify("Tank full")
		_pump_target = null
		return
	_fuel_cost_acc += added * FUEL_PRICE
	if _fuel_cost_acc >= 1.0:
		var c := int(_fuel_cost_acc)
		_fuel_cost_acc -= c
		Game.money -= c
		Game.money_changed.emit(Game.money)


var _fuel_cost_acc := 0.0


func _sell_junk_parts(_p, node: Node3D) -> void:
	var total := 0
	for c in world.dynamic_root.get_children():
		if c is Item and c.shop_price <= 0 and not c.held and c.global_position.distance_to(node.global_position) < 4.0:
			var d := DB.part(c.item_id)
			total += int(float(d.get("price", 10)) * 0.3 * float(c.data.get("cond", 50)) / 100.0) + 2
			c.queue_free()
	if total > 0:
		Game.add_money(total, "Sold parts to the junkyard")
	else:
		Game.notify("Drop parts next to the office door to sell them")


# ------------------------------------------------------------------ car market & junkyard
func _refresh_car_market() -> void:
	_last_market_day = Game.day
	if market_lot.is_empty():
		return
	for v in world.vehicles.duplicate():
		if not v.owned and v.has_meta("market"):
			world.remove_vehicle(v)
	var pool := ["klasyka", "hatch", "sedan", "cruiser", "bobyk", "bukhanka", "minivan", "pickup", "suv", "stepvan", "kombi"]
	for i in range(market_lot.spots.size()):
		if randf() < 0.15:
			continue
		var vid: String = pool.pick_random()
		if i == market_lot.spots.size() - 1 and randf() < 0.5:
			vid = "truck"
		var sp: Node3D = market_lot.spots[i]
		var xf := Transform3D(sp.global_basis.rotated(Vector3.UP, PI * 0.5), world.ground(sp.global_position) + Vector3.UP * 0.4)
		var v: Vehicle = world.spawn_vehicle(vid, xf, randi() % 5)
		var missing := []
		var slots_all: Array = v.slots.keys()
		for k in range(randi_range(0, 3)):
			var s: String = slots_all.pick_random()
			if s != "engine" and not missing.has(s):
				missing.append(s)
		var lo := randf_range(25.0, 75.0)
		v.install_default_parts(lo, minf(100.0, lo + 30.0), missing)
		v.owned = false
		v.set_meta("market", true)
		v.for_sale_price = int(v.value() * randf_range(0.85, 1.2) / 10.0) * 10


func sell_vehicle_value(v: Vehicle) -> int:
	# below the lowest asking price (0.85x), so a car is only worth flipping after you fix it up
	return int(v.value() * 0.8 / 10.0) * 10


func sell_vehicle_at_market() -> void:
	if market_lot.is_empty():
		return
	for v in world.vehicles.duplicate():
		if v.owned and (v.global_position as Vector3).distance_to(market_lot.sell) < 8.0 and v.driver == null:
			var val := sell_vehicle_value(v)
			world.remove_vehicle(v)
			Game.add_money(val, "Sold " + v.def.name)
			return
	Game.notify("Park the car inside the blue SELL marker and get out first")


func vehicle_in_sell_zone() -> Vehicle:
	if market_lot.is_empty():
		return null
	for v in world.vehicles:
		if v.owned and (v.global_position as Vector3).distance_to(market_lot.sell) < 8.0:
			return v
	return null


func on_vehicle_bought(v: Vehicle) -> void:
	v.remove_meta("market")


func _refresh_junkyard() -> void:
	_last_junk_day = Game.day
	if junk_site.is_empty():
		return
	for c in world.dynamic_root.get_children():
		if c is Item and c.shop_price > 0 and c.has_meta("junk"):
			c.queue_free()
	var ids := DB.PARTS.keys().filter(func(k): return k != "engine_diesel" and k != "wheel_truck" and k != "gearbox_heavy")
	var base: Vector3 = junk_site.pos
	for i in range(10):
		var id: String = ids.pick_random()
		var cond := randf_range(15.0, 70.0)
		var a := i * 0.6
		var p := base + Vector3(cos(a) * (6 + i * 0.6), 1.0, sin(a) * (6 + i * 0.6) + 4.0)
		p.y = world.terrain.height_at(p.x, p.z) + 0.6
		var d := {"cond": cond}
		if id == "battery":
			d.charge = randf_range(0, 40)
		var it := Item.spawn(world.dynamic_root, id, d, Transform3D(Basis(Vector3.UP, randf() * TAU), p))
		it.shop_price = maxi(5, int(float(DB.PARTS[id].price) * cond / 100.0 * 0.45))
		it.set_meta("junk", true)


func buy_shop_item(id: String, at: Vector3) -> void:
	var def := DB.part(id)
	if Game.spend(int(def.price), "Bought " + def.name):
		var d := {"cond": 100.0}
		if id.begins_with("battery"):
			d.charge = 100.0
		if def.get("empty", false):
			d.fill = 0.0
		var p := at + Vector3(randf_range(-0.6, 0.6), 0.3 + randf() * 0.3, randf_range(-0.6, 0.6))
		Item.spawn(world.dynamic_root, id, d, Transform3D(Basis.IDENTITY, p))


# ------------------------------------------------------------------ lifecycle
func new_game() -> void:
	_generate_jobs()
	_refresh_car_market()
	_refresh_junkyard()


func save_state() -> Dictionary:
	return {"industries": industries.values().map(func(i): return {"key": i.key, "owner": i.owner, "inp": i.inp, "out": i.out, "level": i.level}),
		"consumers": consumers.values().map(func(c): return {"key": c.key, "stock": c.stock}),
		"jobs": jobs, "active": active, "routes": routes, "next_id": next_id, "market_day": _last_market_day, "junk_day": _last_junk_day,
		"cost_day": _last_cost_day}


func load_state(d: Dictionary) -> void:
	if d.is_empty():
		new_game()
		return
	for i in d.get("industries", []):
		if industries.has(i.key):
			industries[i.key].merge(i, true)
	for c in d.get("consumers", []):
		if consumers.has(c.key):
			consumers[c.key].stock = c.stock
	jobs = d.get("jobs", [])
	active = d.get("active", [])
	routes = d.get("routes", [])
	for r in routes:
		r.trip = route_trip_minutes(r.from, r.to)  # older saves used one-way trips
	next_id = int(d.get("next_id", 1))
	_last_market_day = int(d.get("market_day", -1))
	_last_junk_day = int(d.get("junk_day", -1))
	_last_cost_day = int(d.get("cost_day", -1))
	# vehicles for sale were saved with the world; mark them
	for v in world.vehicles:
		if not v.owned:
			v.set_meta("market", true)
	if jobs.is_empty():
		_generate_jobs()
