extends Node3D
class_name World
## Root of the game scene: builds environment, terrain, props, spawns player & vehicles, owns gameplay systems.

var terrain: Terrain
var roads: Roads
var props: Node3D
var dynamic_root: Node3D
var vehicles: Array = []
var player: Player
var hud: Node
var data: Dictionary
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var economy: Node
var weather := 0.0          # 0 clear .. 1 rain
var _weather_target := 0.0
var _weather_timer := 0.0
var rain: GPUParticles3D
var locations := {}
var traffic: Node
var ambience: Node
var rain_hf: GPUParticlesCollisionHeightField3D
var _light_t := 0.0
var _night := -1
var _sky_key := Vector2(-1, -1)
var perf_watch: Node


func _ready() -> void:
	Game.world = self
	data = JSON.parse_string(FileAccess.open("res://assets/world/world.json", FileAccess.READ).get_as_text())
	locations = data.locations
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.water_level = float(data.water)
	add_child(terrain)
	terrain.build(Game.settings.view_distance)
	_build_water()
	roads = Roads.new()
	roads.name = "Roads"
	add_child(roads)
	roads.build(terrain, data.roads)
	props = preload("res://scripts/world/props.gd").new()
	props.name = "Props"
	add_child(props)
	props.build(self)
	dynamic_root = Node3D.new()
	dynamic_root.name = "Dynamic"
	add_child(dynamic_root)
	economy = preload("res://scripts/gameplay/economy.gd").new()
	economy.name = "Economy"
	add_child(economy)
	economy.setup(self)
	traffic = preload("res://scripts/gameplay/traffic.gd").new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(self)
	ambience = preload("res://scripts/world/ambience.gd").new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(self)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	Game.hud = hud
	perf_watch = preload("res://scripts/debug/perf_watch.gd").new()
	perf_watch.name = "PerfWatch"
	add_child(perf_watch)
	perf_watch.setup(self)
	var st := Game.pending_world_state()
	if st.is_empty():
		_new_game()
	else:
		load_state(st)
	Game.settings_changed.connect(apply_settings)
	apply_settings()
	Game.set_ui_open(false)


# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.26, 0.46, 0.78)
	sky_mat.sky_horizon_color = Color(0.66, 0.74, 0.82)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.2)
	sky_mat.ground_horizon_color = Color(0.62, 0.68, 0.72)
	sky_mat.sun_angle_max = 2.5
	sky_mat.sun_curve = 0.06
	sky_mat.sky_curve = 0.12
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 250.0
	env.fog_depth_end = 1700.0
	env.fog_depth_curve = 1.4
	env.fog_light_color = Color(0.68, 0.75, 0.84)
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	# rain
	rain = GPUParticles3D.new()
	rain.amount = 6000
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25, 1, 25)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rain.process_material = pm
	rain.collision_base_size = 0.02
	# rain stops at roofs / car roofs: heightfield of the scene around the camera
	rain_hf = GPUParticlesCollisionHeightField3D.new()
	rain_hf.size = Vector3(60, 60, 60)
	rain_hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	# re-render the occlusion map only when the camera moves, not every frame while parked
	rain_hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	rain_hf.follow_camera_enabled = true
	rain_hf.visible = false
	add_child(rain_hf)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.015, 0.45)
	var rm := StandardMaterial3D.new()
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.8, 0.85, 0.9, 0.35)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = rm
	rain.draw_pass_1 = qm
	rain.emitting = false
	add_child(rain)


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2048, 2048)
	pm.subdivide_depth = 16
	pm.subdivide_width = 16
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("normal_a", load("res://assets/textures/concrete_n.jpg"))
	mi.material_override = m
	mi.position = Vector3(0, terrain.water_level, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func apply_settings() -> void:
	var s: Dictionary = Game.settings
	env.ssao_enabled = s.ssao
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = s.glow
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.volumetric_fog_enabled = s.volumetric
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_length = 120.0
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	match int(s.shadows):
		0:
			sun.shadow_enabled = false
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 120.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		2:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 200.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		3:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 320.0
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	terrain.set_view_distance(float(s.view_distance))
	env.fog_depth_end = 1700.0 * float(s.view_distance)
	props.apply_settings(s)
	get_viewport().scaling_3d_scale = float(s.render_scale)


func _process(dt: float) -> void:
	_light_t -= dt
	if _light_t <= 0.0:
		_light_t = 0.25
		_update_daylight()
	_update_weather(dt)
	var cam := get_viewport().get_camera_3d()
	if cam and rain.emitting:
		rain.global_position = cam.global_position + Vector3.UP * 12.0


func _update_daylight() -> void:
	var h := Game.hour_f()
	# sun goes up at 5:30, down at 21:00
	var t := (h - 5.5) / 15.5
	var elev := sin(clampf(t, -0.15, 1.15) * PI) * 62.0
	var az := lerpf(-100.0, 100.0, t)
	sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(az + 180.0), 0)
	var day := clampf((elev + 4.0) / 18.0, 0.0, 1.0)
	var golden := clampf(1.0 - absf(elev - 8.0) / 14.0, 0.0, 1.0)
	sun.light_energy = day * lerpf(1.35, 0.7, weather)
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.36), golden * 0.8)
	sun.visible = day > 0.01
	moon.light_energy = (1.0 - day) * 0.2
	moon.visible = day < 0.95
	var night := 1 if (day < 0.3 or weather > 0.85) else 0
	if night != _night:
		_night = night
		for l in props.street_lights:
			l.visible = night == 1
		traffic.set_night(night == 1)
	# every sky material change re-bakes the sky radiance on the GPU: only touch it on visible changes
	var key := Vector2(snappedf(h, 0.05), snappedf(weather, 0.02))
	if key == _sky_key:
		return
	_sky_key = key
	var overcast := weather
	sky_mat.sky_top_color = Color(0.03, 0.05, 0.1).lerp(Color(0.26, 0.46, 0.78).lerp(Color(0.42, 0.46, 0.5), overcast), day)
	sky_mat.sky_horizon_color = Color(0.05, 0.07, 0.12).lerp(Color(0.68, 0.74, 0.82).lerp(Color(0.95, 0.65, 0.45), golden * 0.6).lerp(Color(0.55, 0.57, 0.6), overcast), day)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_depth_begin = lerpf(250.0, 60.0, overcast)
	env.ambient_light_energy = lerpf(0.42, 1.0, day)
	env.background_energy_multiplier = lerpf(0.35, 1.0, day)


func _update_weather(dt: float) -> void:
	_weather_timer -= dt
	if _weather_timer <= 0.0:
		_weather_timer = randf_range(240.0, 600.0)
		_weather_target = 1.0 if randf() < 0.22 else 0.0
	weather = move_toward(weather, _weather_target, dt / 40.0)
	rain.emitting = weather > 0.55
	rain_hf.visible = rain.emitting
	terrain.set_wetness(clampf(terrain.wetness + (0.004 if weather > 0.55 else -0.0015) * dt, 0.0, 1.0))


# ------------------------------------------------------------------ helpers
func loc_pos(key: String) -> Vector3:
	var l: Dictionary = locations[key]
	return Vector3(l.x, terrain.height_at(l.x, l.z), l.z)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


func spawn_vehicle(vid: String, xf: Transform3D, paint: int = 0) -> Vehicle:
	var v := Vehicle.new()
	v.setup(vid, paint)
	dynamic_root.add_child(v)
	v.global_transform = xf
	vehicles.append(v)
	return v


func remove_vehicle(v: Vehicle) -> void:
	vehicles.erase(v)
	v.queue_free()


func buy_vehicle(v: Vehicle) -> bool:
	if v.owned:
		return false
	if Game.spend(v.for_sale_price, "Bought " + v.def.name):
		v.owned = true
		v.for_sale_price = 0
		economy.on_vehicle_bought(v)
		return true
	return false


func _new_game() -> void:
	var g: Dictionary = props.find_object("garage")
	var gpos := Vector3(g.x, g.y, g.z)
	var gyaw: float = g.rot
	var gb := Basis(Vector3.UP, gyaw)
	# starter car inside the garage, half assembled
	var car := spawn_vehicle("kombi", Transform3D(gb, gpos + gb * Vector3(0, 0.35, 0.3)), 0)
	car.install_default_parts(48.0, 70.0, ["battery", "carburetor", "air_filter", "spark_plugs", "wheel2", "wheel3"])
	car.fuel = 3.0
	car.oil = 2.2
	car.coolant = 3.0
	car.hood_open = true
	for s in car.slots.values():
		s.update_enabled()
	# parts lying around the garage
	var bench := gpos + gb * Vector3(-3.6, 0, -1.6)
	var drop := func(id: String, d: Dictionary, off: Vector3) -> void:
		Item.spawn(dynamic_root, id, d, Transform3D(gb, bench + gb * off))
	drop.call("battery", {"cond": 70.0, "charge": 35.0}, Vector3(0, 1.05, -0.7))
	drop.call("carburetor", {"cond": 62.0}, Vector3(0.05, 1.02, -0.15))
	drop.call("spark_plugs", {"cond": 45.0}, Vector3(0.05, 1.0, 0.3))
	drop.call("oil_bottle", {"fill": 2.0}, Vector3(-0.1, 1.05, 0.7))
	drop.call("coolant_bottle", {"fill": 3.0}, Vector3(0.12, 1.05, 0.75))
	drop.call("wheel_road", {"cond": 58.0}, Vector3(1.0, 0.4, 2.2))
	drop.call("wheel_road", {"cond": 52.0}, Vector3(1.0, 0.4, 2.8))
	drop.call("jerrycan", {"fill": 12.0}, Vector3(0.5, 0.3, 1.6))
	var sp: Dictionary = props.find_object("spawn_player")
	player.global_position = gpos + gb * Vector3(-1.5, 0.2, 3.5)
	player.set_look(gyaw, -0.15)
	economy.new_game()
	Game.flags.tutorial = 0
	Game.notify("Welcome to Sonyachne. Your old Kombi needs work - check the checklist (top right).", "info")


# ------------------------------------------------------------------ save / load
func save_state() -> Dictionary:
	var vs := []
	for v in vehicles:
		vs.append(v.save_state())
	var items := []
	for c in dynamic_root.get_children():
		if c is Item and not c.is_queued_for_deletion():
			items.append(c.save_state())
	return {
		"vehicles": vs, "items": items, "player": player.save_state(), "economy": economy.save_state(),
		"terrain": terrain.save_state(), "weather": weather,
	}


func load_state(d: Dictionary) -> void:
	for vd in d.get("vehicles", []):
		var v := spawn_vehicle(vd.vid, str_to_var(vd.xf), int(vd.get("paint", 0)))
		v.load_state(vd)
	for it in d.get("items", []):
		var i := Item.spawn(dynamic_root, it.id, it.data, str_to_var(it.xf))
		i.shop_price = int(it.get("price", 0))
	economy.load_state(d.get("economy", {}))
	terrain.load_state(d.get("terrain", {}))
	weather = float(d.get("weather", 0.0))
	var p: Dictionary = d.get("player", {})
	player.global_position = str_to_var(p.get("pos", "Vector3(0, 50, 0)"))
	player.set_look(float(p.get("yaw", 0.0)), 0.0)
	var vi := int(p.get("vehicle", -1))
	if vi >= 0 and vi < vehicles.size():
		player.call_deferred("enter_vehicle", vehicles[vi])
