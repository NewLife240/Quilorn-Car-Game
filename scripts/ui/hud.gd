extends CanvasLayer
## In-game HUD, tablet (jobs / business / market / map / vehicle / help), modal dialogs and pause menu.

const EconomyRules := preload("res://scripts/gameplay/economy.gd")

var root: Control
var money_lbl: Label
var clock_lbl: Label
var fps_lbl: Label
var hint_lbl: Label
var info_lbl: Label
var zone_lbl: Label
var cross: ColorRect
var notif_box: VBoxContainer
var check_box: VBoxContainer
var jobs_box: VBoxContainer
var dash: PanelContainer
var dash_speed: Label
var dash_gear: Label
var dash_rpm: ProgressBar
var dash_lines: Label
var dash_warn: Label
var tablet: Control
var modal: Control
var pause_menu: Control
var _tabs: TabContainer
var _map_tex: Texture2D
var _check_t := 0.0
var underwater: ColorRect


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	underwater = ColorRect.new()
	underwater.color = Color(0.05, 0.22, 0.28, 0.72)
	underwater.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater.visible = false
	root.add_child(underwater)
	_build_hud()
	Game.notified.connect(_on_notify)
	Game.money_changed.connect(func(_m): _update_money())
	_update_money()
	if ResourceLoader.exists("res://assets/world/map.png"):
		_map_tex = load("res://assets/world/map.png")


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	var tl := UIKit.vbox([], 2)
	tl.position = Vector2(24, 18)
	money_lbl = UIKit.label("", 28, UIKit.ACCENT, true)
	clock_lbl = UIKit.label("", 18)
	fps_lbl = UIKit.label("", 14, Color(0.7, 0.9, 0.7))
	tl.add_child(money_lbl)
	tl.add_child(clock_lbl)
	tl.add_child(fps_lbl)
	root.add_child(tl)
	cross = ColorRect.new()
	cross.color = Color(1, 1, 1, 0.8)
	cross.size = Vector2(4, 4)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-2, -2)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	var bc := UIKit.vbox([], 4)
	bc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bc.offset_top = -190
	bc.offset_left = -500
	bc.offset_right = 500
	bc.alignment = BoxContainer.ALIGNMENT_END
	info_lbl = UIKit.label("", 20, Color(1, 1, 1), true)
	hint_lbl = UIKit.label("", 18, UIKit.ACCENT)
	zone_lbl = UIKit.label("", 22, Color(0.5, 1.0, 0.6), true)
	for l in [zone_lbl, info_lbl, hint_lbl]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bc.add_child(l)
	root.add_child(bc)
	notif_box = UIKit.vbox([], 4)
	notif_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notif_box.offset_top = 20
	notif_box.offset_left = -360
	notif_box.offset_right = 360
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notif_box)
	var tr := UIKit.vbox([], 4)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -420
	tr.offset_right = -24
	tr.offset_top = 18
	check_box = UIKit.vbox([], 2)
	jobs_box = UIKit.vbox([], 2)
	tr.add_child(check_box)
	tr.add_child(jobs_box)
	root.add_child(tr)
	# dashboard
	dash = PanelContainer.new()
	dash.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dash.offset_left = -330
	dash.offset_top = -200
	dash.offset_right = -24
	dash.offset_bottom = -24
	var dv := UIKit.vbox([], 4)
	dash.add_child(dv)
	var top := HBoxContainer.new()
	dash_speed = UIKit.label("0", 52, Color.WHITE, true)
	top.add_child(dash_speed)
	top.add_child(UIKit.label("km/h", 16, Color(0.7, 0.7, 0.7)))
	top.add_child(UIKit.spacer())
	dash_gear = UIKit.label("N", 52, UIKit.ACCENT, true)
	top.add_child(dash_gear)
	dv.add_child(top)
	dash_rpm = UIKit.bar(0, UIKit.ACCENT, 280)
	dv.add_child(dash_rpm)
	dash_lines = UIKit.label("", 15)
	dv.add_child(dash_lines)
	dash_warn = UIKit.label("", 15, Color(1, 0.4, 0.3), true)
	dv.add_child(dash_warn)
	root.add_child(dash)


func _update_money() -> void:
	money_lbl.text = "₴ %s" % _fmt(Game.money)


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _process(dt: float) -> void:
	clock_lbl.text = Game.clock_text() + ("   ☂ rain" if Game.world and Game.world.weather > 0.55 else "")
	fps_lbl.visible = Game.settings.show_fps
	fps_lbl.text = "%d FPS" % Engine.get_frames_per_second()
	var p: Player = Game.player
	if p == null:
		return
	var cam3 := get_viewport().get_camera_3d()
	underwater.visible = cam3 != null and Game.world != null and cam3.global_position.y < Game.world.terrain.water_level - 0.05
	var v: Vehicle = p.vehicle
	var ui := modal != null or tablet != null or pause_menu != null
	cross.visible = v == null and not ui
	hint_lbl.text = "" if ui else p.hint
	info_lbl.text = "" if ui else p.info
	dash.visible = v != null and not ui
	zone_lbl.text = ""
	if v:
		_update_dash(v)
		var z: Dictionary = Game.world.economy.zone_at(v.global_position)
		if not z.is_empty():
			zone_lbl.text = "%s  %s   [J] %s" % ["▼" if z.kind == "load" else "▲", Game.world.economy.site_name(z.site), "Load / Buy cargo" if z.kind == "load" else "Unload / Sell cargo"]
		elif Game.world.economy.vehicle_in_sell_zone() == v:
			zone_lbl.text = "Car market: get out and use the office to sell this car"
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.5
		_update_checklist()
		_update_jobs_hud()


func _update_dash(v: Vehicle) -> void:
	dash_speed.text = str(int(v.speed_kmh))
	dash_gear.text = v.gear_text()
	var red: float = v.engine_def().get("redline", 6000.0)
	dash_rpm.value = clampf(v.engine_rpm / red, 0, 1)
	var bat := v.battery_charge()
	dash_lines.text = "RPM %d   %s%s   %s\nFuel %.0f/%.0f L   Temp %d°C   Batt %d%%" % [
		int(v.engine_rpm), v.drive_mode_text(), "  DIFF" if v.diff_lock else "", "AUTO" if v.auto_gearbox else "MANUAL",
		v.fuel, v.def.fuel_cap, int(v.temp), int(bat)]
	var w := []
	if not v.running:
		w.append("ENGINE OFF - hold [F] to start" if v.ignition == 0 or not v.cranking else "Cranking...")
	if v.temp > 105:
		w.append("OVERHEATING")
	if v.oil < 1.0 and v.has("engine"):
		w.append("LOW OIL")
	if v.fuel < 3.0:
		w.append("LOW FUEL")
	if bat < 15 and v.has("battery"):
		w.append("BATTERY LOW")
	if v.in_handbrake > 0.5:
		w.append("HANDBRAKE")
	if v.cargo_units() > 0:
		w.append("Cargo %d/%d" % [v.cargo_units(), v.cargo_capacity()])
	dash_warn.text = "  ".join(w)


func _update_checklist() -> void:
	for c in check_box.get_children():
		c.queue_free()
	if Game.flags.get("tutorial_done", false):
		return
	var car: Vehicle = null
	for v in Game.world.vehicles:
		if v.vid == "kombi" and v.owned:
			car = v
			break
	if car == null:
		return
	var rear_ok: bool = car.slots.wheel2.is_tight() and car.slots.wheel3.is_tight()
	var items := [
		["Install & tighten the battery", car.slots.battery.is_tight()],
		["Install & tighten the carburettor", car.slots.carburetor.is_tight()],
		["Install & tighten the spark plugs", car.slots.spark_plugs.is_tight()],
		["Mount both rear wheels", rear_ok],
		["Pour fuel from the jerry can (fuel cap, rear left)", car.fuel > 8.0],
		["Start the engine (hold F)", car.running],
		["Buy an air filter (village shop / Stepove parts)", car.has("air_filter")],
		["Take a delivery job (TAB → Jobs)", Game.stats.deliveries > 0 or not Game.world.economy.active.is_empty()],
	]
	var done := 0
	check_box.add_child(UIKit.label("Get the Kombi running", 18, UIKit.ACCENT, true))
	for it in items:
		if it[1]:
			done += 1
		check_box.add_child(UIKit.label(("✔ " if it[1] else "○ ") + it[0], 15, Color(0.6, 0.95, 0.6) if it[1] else Color(0.9, 0.9, 0.9)))
	if done == items.size():
		Game.flags.tutorial_done = true
		Game.notify("Checklist complete! Earn money, flip cars and build your business.", "money")


func _update_jobs_hud() -> void:
	for c in jobs_box.get_children():
		c.queue_free()
	var eco = Game.world.economy
	for j in eco.active:
		var target: String = j.to if j.loaded else j.from
		var d := (Game.player.global_position as Vector3).distance_to(eco.site_pos(target))
		jobs_box.add_child(UIKit.label("%s %d× %s → %s  (%dm)  ₴%d" % ["🚚" if j.loaded else "📦", j.units, DB.GOODS[j.good].name, eco.site_name(target), int(d), j.pay], 15, Color(0.85, 0.9, 1.0)))


func _on_notify(text: String, kind: String) -> void:
	var col := Color(1, 1, 1)
	match kind:
		"money": col = Color(0.5, 1, 0.5)
		"cost": col = Color(1, 0.7, 0.5)
		"warn": col = Color(1, 0.5, 0.4)
	var p := UIKit.row_panel()
	var l := UIKit.label(text, 17, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	notif_box.add_child(p)
	if notif_box.get_child_count() > 5:
		notif_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if modal:
			close_modal()
		elif tablet:
			close_tablet()
		elif pause_menu:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tablet") and pause_menu == null:
		if tablet:
			close_tablet()
		elif modal == null:
			open_tablet()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and pause_menu == null and modal == null:
		if tablet:
			close_tablet()
		else:
			open_tablet(3)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cargo") and Game.player and Game.player.vehicle and modal == null and tablet == null:
		Game.world.economy.cargo_action(Game.player.vehicle)


func _overlay() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	return bg


func _center_panel(parent: Control, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	parent.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.position = (root.get_viewport_rect().size - size) * 0.5
	return p


# ------------------------------------------------------------------ pause
func open_pause_menu() -> void:
	if pause_menu == null:
		close_modal()
		close_tablet()
		_open_pause()


func _open_pause() -> void:
	pause_menu = _overlay()
	Game.set_ui_open(true)
	get_tree().paused = true
	var p := _center_panel(pause_menu, Vector2(420, 420))
	var v := UIKit.vbox([], 12)
	p.add_child(v)
	v.add_child(UIKit.label("Paused", 32, UIKit.ACCENT, true))
	v.add_child(UIKit.button("Resume", _close_pause))
	v.add_child(UIKit.button("Settings", func():
		var s := preload("res://scripts/ui/settings_panel.gd").new()
		pause_menu.add_child(s)
		s.position = (root.get_viewport_rect().size - Vector2(760, 640)) * 0.5))
	v.add_child(UIKit.button("Save game", func(): Game.save_game()))
	v.add_child(UIKit.button("Save & quit to menu", func():
		Game.save_game()
		get_tree().paused = false
		Game.world = null
		Game.player = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	v.add_child(UIKit.button("Quit to desktop", func(): get_tree().quit()))


func _close_pause() -> void:
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false
	Game.set_ui_open(false)


# ------------------------------------------------------------------ modal helpers
func _open_modal(title: String, size := Vector2(900, 620)) -> VBoxContainer:
	close_modal()
	modal = _overlay()
	Game.set_ui_open(true)
	var p := _center_panel(modal, size)
	var v := UIKit.vbox([], 10)
	p.add_child(v)
	v.add_child(UIKit.hbox([UIKit.label(title, 28, UIKit.ACCENT, true), UIKit.spacer(), UIKit.button("Close [Esc]", close_modal)]))
	return v


func close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	if tablet == null and pause_menu == null:
		Game.set_ui_open(false)


# ------------------------------------------------------------------ shops
const SHOP_GENERAL := ["jerrycan", "diesel_can", "oil_bottle", "coolant_bottle", "repair_kit", "spray_paint", "air_filter", "air_filter_sport", "spark_plugs", "spark_plugs_iridium", "battery", "wheel_road", "ignition_coil"]


func open_shop(kind: String, pickup: Vector3) -> void:
	var v := _open_modal("Auto parts store" if kind == "parts" else "Shop")
	v.add_child(UIKit.label("Bought items are placed on the pallet / counter outside.", 15, Color(0.7, 0.7, 0.7)))
	var list := UIKit.vbox([], 6)
	v.add_child(UIKit.scroll(list))
	var ids: Array = DB.PARTS.keys() + ["jerrycan", "oil_bottle", "coolant_bottle", "repair_kit", "spray_paint"] if kind == "parts" else SHOP_GENERAL
	for id in ids:
		var d := DB.part(id)
		var r := UIKit.row_panel()
		var cls := ("  [%s vehicles]" % d.cls) if d.has("cls") else ""
		var nm := UIKit.label("%s%s" % [d.name, cls], 18)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(UIKit.hbox([nm, UIKit.label("₴%d" % d.price, 18, UIKit.ACCENT, true), UIKit.button("Buy", func(): Game.world.economy.buy_shop_item(id, pickup), 90)]))
		list.add_child(r)


# ------------------------------------------------------------------ trade at a zone
func open_trade(site: String, veh: Vehicle) -> void:
	var eco = Game.world.economy
	var v := _open_modal(eco.site_name(site))
	var list := UIKit.vbox([], 6)
	v.add_child(UIKit.scroll(list))
	v.add_child(UIKit.label("Vehicle cargo: %d / %d   (%s)" % [veh.cargo_units(), veh.cargo_capacity(), ", ".join(veh.def.kinds)], 16))
	if eco.industries.has(site):
		var ind: Dictionary = eco.industries[site]
		list.add_child(UIKit.label("Output for sale" + (" (yours - free)" if ind.owner == "player" else ""), 20, UIKit.ACCENT, true))
		for g in ind.out.keys():
			var r := UIKit.row_panel()
			var avail := int(ind.out[g])
			var cost := 0 if ind.owner == "player" else int(DB.GOODS[g].price * 0.6)
			var nm := UIKit.label("%s  - %d in stock  ₴%d each" % [DB.GOODS[g].name, avail, cost], 17)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var h := UIKit.hbox([nm])
			for n in [1, 4, 12]:
				h.add_child(UIKit.button("Load %d" % n, func(): eco.trade_buy(site, g, n, veh); open_trade(site, veh)))
			r.add_child(h)
			list.add_child(r)
	var buys: Array = DB.CONSUMERS[site].buys if eco.consumers.has(site) else (DB.INDUSTRIES[site].in.keys() if eco.industries.has(site) else [])
	if not buys.is_empty():
		list.add_child(UIKit.label("Buying", 20, UIKit.ACCENT, true))
		for g in buys:
			var have := 0
			for c in veh.cargo:
				if c.good == g and int(c.job) == -1:
					have += int(c.units)
			var r := UIKit.row_panel()
			var nm := UIKit.label("%s  - pays ₴%d each  (you carry %d)" % [DB.GOODS[g].name, eco.price(g, site), have], 17)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := UIKit.button("Sell all", func(): eco.trade_sell(site, g, veh); open_trade(site, veh))
			b.disabled = have == 0
			r.add_child(UIKit.hbox([nm, b]))
			list.add_child(r)


# ------------------------------------------------------------------ industry office
func open_office(key: String) -> void:
	var eco = Game.world.economy
	var ind: Dictionary = eco.industries[key]
	var d: Dictionary = DB.INDUSTRIES[key]
	var v := _open_modal(ind.name)
	var ins := []
	for g in d.in.keys():
		ins.append("%d %s" % [d.in[g], DB.GOODS[g].name])
	var outs := []
	for g in d.out.keys():
		outs.append("%d %s" % [d.out[g], DB.GOODS[g].name])
	v.add_child(UIKit.label("Recipe: %s → %s   (%.1f cycles/hour at level %d)" % [" + ".join(ins) if not ins.is_empty() else "nothing", " + ".join(outs), d.rate * (1.0 + 0.5 * (ind.level - 1)), ind.level], 17))
	v.add_child(UIKit.label("Input stock: %s     Output stock: %s" % [str(ind.inp), str(ind.out)], 16, Color(0.8, 0.85, 1.0)))
	if ind.owner == "npc":
		v.add_child(UIKit.label("Owned by the regional cooperative. Price ₴%s, upkeep ₴%d/day." % [_fmt(d.price), d.upkeep], 17))
		v.add_child(UIKit.button("Buy this business (₴%s)" % _fmt(d.price), func(): eco.buy_industry(key); open_office(key)))
	else:
		v.add_child(UIKit.label("You own this. Level %d/3. Upkeep ₴%d/day." % [ind.level, int(d.upkeep) * int(ind.level)], 17, Color(0.6, 1, 0.6)))
		if int(ind.level) < 3:
			v.add_child(UIKit.button("Upgrade to level %d (₴%s)" % [ind.level + 1, _fmt(int(d.price * 0.6 * int(ind.level)))], func(): eco.upgrade_industry(key); open_office(key)))
		v.add_child(UIKit.label("Hire drivers (₴%d hiring + ₴%d/day each, %d units per round trip) to haul your output automatically. Too many drivers flood the buyer and the price drops:" % [EconomyRules.DRIVER_HIRE, EconomyRules.DRIVER_WAGE, EconomyRules.ROUTE_UNITS], 17, UIKit.ACCENT))
		var list := UIKit.vbox([], 6)
		v.add_child(UIKit.scroll(list))
		for g in d.out.keys():
			for dst in eco.buyers_of(g):
				var r := UIKit.row_panel()
				var nm := UIKit.label("%s → %s  (₴%d each)" % [DB.GOODS[g].name, eco.site_name(dst), eco.price(g, dst)], 16)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				r.add_child(UIKit.hbox([nm, UIKit.button("Hire driver", func(): eco.hire_route(key, dst, g); open_office(key))]))
				list.add_child(r)


# ------------------------------------------------------------------ car market
func open_car_market() -> void:
	var eco = Game.world.economy
	var v := _open_modal("Car Market - buy, fix, flip")
	v.add_child(UIKit.label("Cars for sale are parked on the lot - walk up to the driver door and press E to buy.", 16, Color(0.75, 0.75, 0.75)))
	var list := UIKit.vbox([], 6)
	v.add_child(UIKit.scroll(list))
	for car in Game.world.vehicles:
		if car.owned:
			continue
		var miss: Array = car.missing_parts()
		var avg := 0.0
		var n := 0
		for s in car.slots.values():
			if s.is_installed():
				avg += s.cond()
				n += 1
		var r := UIKit.row_panel()
		var nm := UIKit.label("%s   condition ~%d%%   missing: %s" % [car.def.name, int(avg / maxf(1, n)), ", ".join(miss.map(func(x): return DB.slot_display(x))) if not miss.is_empty() else "nothing"], 16)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(UIKit.hbox([nm, UIKit.label("₴%s" % _fmt(car.for_sale_price), 18, UIKit.ACCENT, true)]))
		list.add_child(r)
	var sv: Vehicle = eco.vehicle_in_sell_zone()
	if sv:
		v.add_child(UIKit.hbox([UIKit.label("In the SELL zone: %s - offer ₴%s" % [sv.def.name, _fmt(eco.sell_vehicle_value(sv))], 18), UIKit.spacer(),
			UIKit.button("Sell", func(): eco.sell_vehicle_at_market(); close_modal())]))
	else:
		v.add_child(UIKit.label("To sell a car: park it in the blue SELL marker, get out, then talk to the office.", 16))


# ------------------------------------------------------------------ tablet
func open_tablet(tab := 0) -> void:
	close_modal()
	tablet = _overlay()
	Game.set_ui_open(true)
	var p := _center_panel(tablet, Vector2(1180, 760))
	var v := UIKit.vbox([], 8)
	p.add_child(v)
	v.add_child(UIKit.hbox([UIKit.label("Rusty Roads tablet", 26, UIKit.ACCENT, true), UIKit.spacer(), UIKit.label("₴ " + _fmt(Game.money) + "    " + Game.clock_text(), 20),
		UIKit.button("Save", func(): Game.save_game()), UIKit.button("Close [Tab]", close_tablet)]))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_tab_jobs())
	_tabs.add_child(_tab_business())
	_tabs.add_child(_tab_market())
	_tabs.add_child(_tab_map())
	_tabs.add_child(_tab_vehicle())
	_tabs.add_child(_tab_help())
	_tabs.current_tab = tab


func close_tablet() -> void:
	if tablet:
		tablet.queue_free()
		tablet = null
	if modal == null and pause_menu == null:
		Game.set_ui_open(false)


func _refresh_tablet() -> void:
	var t := _tabs.current_tab if _tabs else 0
	open_tablet(t)


func _tab_jobs() -> Control:
	var eco = Game.world.economy
	var v := UIKit.vbox([], 6)
	v.name = "Jobs"
	v.add_child(UIKit.label("Active jobs (%d/%d)" % [eco.active.size(), eco.MAX_ACTIVE_JOBS], 20, UIKit.ACCENT, true))
	for j in eco.active:
		var r := UIKit.row_panel()
		var nm := UIKit.label("%d× %s   %s → %s   ₴%d   %s" % [j.units, DB.GOODS[j.good].name, eco.site_name(j.from), eco.site_name(j.to), j.pay, "LOADED" if j.loaded else "go to pickup"], 16)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(UIKit.hbox([nm, UIKit.button("Cancel (-10%)", func(): eco.cancel_job(j.id); _refresh_tablet())]))
		v.add_child(r)
	v.add_child(UIKit.label("Available jobs - drive into the LOAD marker and press [J]", 20, UIKit.ACCENT, true))
	var list := UIKit.vbox([], 6)
	var veh: Vehicle = Game.player.vehicle
	for j in eco.jobs:
		var r := UIKit.row_panel()
		var d: float = eco.site_pos(j.from).distance_to(eco.site_pos(j.to))
		var kind: String = DB.GOODS[j.good].kind
		var nm := UIKit.label("%d× %s  [%s]   %s → %s  (%.1f km)" % [j.units, DB.GOODS[j.good].name, kind, eco.site_name(j.from), eco.site_name(j.to), d / 1000.0], 16)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pay := UIKit.label("₴%d" % j.pay, 18, UIKit.ACCENT, true)
		r.add_child(UIKit.hbox([nm, pay, UIKit.button("Accept", func(): eco.accept_job(j.id); _refresh_tablet())]))
		list.add_child(r)
	v.add_child(UIKit.scroll(list))
	return v


func _tab_business() -> Control:
	var eco = Game.world.economy
	var v := UIKit.vbox([], 6)
	v.name = "Business"
	var list := UIKit.vbox([], 6)
	for k in eco.industries.keys():
		var ind: Dictionary = eco.industries[k]
		var d: Dictionary = DB.INDUSTRIES[k]
		var r := UIKit.row_panel()
		var mine: bool = ind.owner == "player"
		var nm := UIKit.label("%s%s   in %s   out %s" % [ind.name, "  ★ yours (lvl %d)" % ind.level if mine else "", str(ind.inp), str(ind.out)], 16, Color(0.6, 1, 0.6) if mine else Color(0.9, 0.9, 0.9))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var h := UIKit.hbox([nm])
		if not mine:
			h.add_child(UIKit.button("Buy ₴%s" % _fmt(d.price), func(): eco.buy_industry(k); _refresh_tablet()))
		else:
			h.add_child(UIKit.button("Manage", func(): close_tablet(); open_office(k)))
		r.add_child(h)
		list.add_child(r)
	v.add_child(UIKit.scroll(list))
	if not eco.routes.is_empty():
		v.add_child(UIKit.label("Hired drivers", 20, UIKit.ACCENT, true))
		for i in range(eco.routes.size()):
			var rt: Dictionary = eco.routes[i]
			v.add_child(UIKit.hbox([UIKit.label("%d× truck  %s: %s → %s" % [rt.trucks, DB.GOODS[rt.good].name, eco.site_name(rt.from), eco.site_name(rt.to)], 16), UIKit.spacer(),
				UIKit.button("Fire one", func(): eco.fire_route(i); _refresh_tablet())]))
	return v


func _tab_market() -> Control:
	var eco = Game.world.economy
	var v := UIKit.vbox([], 4)
	v.name = "Prices"
	var list := UIKit.vbox([], 4)
	for g in DB.GOODS.keys():
		if g == "parcel":
			continue
		var s := "%-16s" % DB.GOODS[g].name
		var parts := []
		for b in eco.buyers_of(g):
			parts.append("%s ₴%d" % [eco.site_name(b), eco.price(g, b)])
		var r := UIKit.row_panel()
		var l := UIKit.label("%s  →  %s" % [DB.GOODS[g].name, "   |   ".join(parts)], 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(l)
		list.add_child(r)
	v.add_child(UIKit.scroll(list))
	return v


func _tab_map() -> Control:
	var m := preload("res://scripts/ui/map_view.gd").new()
	m.name = "Map"
	m.tex = _map_tex
	return m


func _tab_vehicle() -> Control:
	var v := UIKit.vbox([], 4)
	v.name = "Vehicle"
	var p: Player = Game.player
	var car: Vehicle = p.vehicle
	if car == null:
		var bd := 1e9
		for c in Game.world.vehicles:
			if c.owned:
				var d := (c.global_position as Vector3).distance_to(p.global_position)
				if d < bd:
					bd = d
					car = c
	if car == null:
		v.add_child(UIKit.label("You don't own a vehicle.", 18))
		return v
	v.add_child(UIKit.label("%s   odometer %.1f km   value ~₴%s" % [car.def.name, car.odometer / 1000.0, _fmt(car.value())], 20, UIKit.ACCENT, true))
	v.add_child(UIKit.label("Fuel %.1f/%.0f L   Oil %.1f/%.1f L   Coolant %.1f/%.1f L   Engine temp %d°C" % [car.fuel, car.def.fuel_cap, car.oil, car.OIL_CAP, car.coolant, car.COOLANT_CAP, int(car.temp)], 17))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	for s in car.slots.values():
		grid.add_child(UIKit.label(DB.slot_display(s.slot_name), 16))
		if s.is_installed():
			grid.add_child(UIKit.label(DB.part(s.part_id()).name, 16))
			grid.add_child(UIKit.bar(s.cond() / 100.0, UIKit.cond_color(s.cond()), 140))
			grid.add_child(UIKit.label("%d%%  bolts %d/%d" % [int(s.cond()), s.bolts, s.max_bolts()], 15, UIKit.cond_color(s.cond()) if s.is_tight() else Color(1, 0.5, 0.3)))
		else:
			grid.add_child(UIKit.label("— missing —", 16, Color(1, 0.4, 0.3)))
			grid.add_child(Control.new())
			grid.add_child(Control.new())
	v.add_child(UIKit.scroll(grid))
	return v


func _tab_help() -> Control:
	var l := RichTextLabel.new()
	l.name = "Help"
	l.bbcode_enabled = true
	l.fit_content = false
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.text = """[b][color=#f9c838]On foot[/color][/b]
WASD move · Shift sprint · Space jump · C crouch · Mouse look
LMB grab / drop / install part on the highlighted slot · RMB throw
E interact (doors, hood, trunk, shops, pumps, beds) · hold E pour fluids / use repair kit
Carry parts home in the trunk: hold a part and press E at the back of the car
R tighten bolts · T loosen bolts (a part comes off only with all bolts loose)
Tab tablet · M map · Esc pause

[b][color=#f9c838]Driving[/color][/b]
W/S throttle & brake (auto gearbox reverses when stopped) · A/D steer · Space handbrake
F tap = ignition on/off, hold = crank the starter · L lights · H horn
V first / third person camera · B look back · G auto / manual gearbox
Shift / Ctrl gear up / down (manual) · Z 2WD / AWD / LOW range · X differential lock
J load / unload cargo inside a marker · E get out · Backspace flip the car upright (when slow)

[b][color=#f9c838]Cars[/color][/b]
An engine needs: block, gearbox, carburettor, spark plugs, ignition coil, starter, battery, fuel tank with fuel.
Loose bolts make parts work worse and wear faster. Watch oil, coolant and temperature.
Mud: switch to AWD, engage LOW range and lock the differential. Spinning wheels dig ruts.
Buy cheap wrecks at the car market or used parts at the junkyard, fix them and sell for profit.

[b][color=#f9c838]Business[/color][/b]
Deliver jobs for money, buy industries, haul your own goods to buyers (prices drop when they are oversupplied),
upgrade production and hire drivers to automate supply chains."""
	return l
