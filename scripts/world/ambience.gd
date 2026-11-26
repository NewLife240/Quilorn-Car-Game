extends Node
## Ambient soundscape: birds by day, crickets at night, wind, rain, river, random thunder.

var world: Node
var players := {}
var _thunder_t := 20.0
var _river: PackedVector2Array


func setup(w: Node) -> void:
	world = w
	for r in w.data.river:
		_river.append(Vector2(r[0], r[1]))
	for k in ["birds", "crickets", "wind", "rain", "river"]:
		var p := AudioStreamPlayer.new()
		var path := "res://assets/sounds/amb/%s.ogg" % k
		if k == "river":
			path = "res://assets/sounds/amb/river.ogg"
		var st: AudioStream = load(path).duplicate()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		p.stream = st
		p.volume_db = -80.0
		p.autoplay = false
		add_child(p)
		p.play(randf() * 10.0)
		players[k] = p
	var th := AudioStreamPlayer.new()
	th.stream = load("res://assets/sounds/amb/thunder.ogg")
	add_child(th)
	players["thunder"] = th


func _river_dist(p: Vector3) -> float:
	var best := 1e9
	for i in range(0, _river.size() - 1, 2):
		best = minf(best, Vector2(p.x, p.z).distance_to(_river[i]))
	return best


func _fade(k: String, lin: float, dt: float) -> void:
	var p: AudioStreamPlayer = players[k]
	var cur := db_to_linear(p.volume_db)
	cur = move_toward(cur, clampf(lin, 0.0, 1.0), dt * 0.4)
	p.volume_db = linear_to_db(maxf(cur, 0.0001))


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or world == null:
		return
	var h := Game.hour_f()
	var day := clampf(1.0 - absf(h - 13.0) / 8.0, 0.0, 1.0)
	var night := clampf((absf(h - 13.0) - 7.5) / 1.5, 0.0, 1.0)
	var rain: float = world.weather
	var inside_car: bool = Game.player != null and Game.player.vehicle != null
	var muffle := 0.45 if inside_car else 1.0
	var p := cam.global_position
	var alt := clampf((p.y - 20.0) / 40.0, 0.0, 1.0)
	_fade("birds", day * (1.0 - rain) * 0.55 * muffle, dt)
	_fade("crickets", night * (1.0 - rain) * 0.5 * muffle, dt)
	_fade("wind", (0.12 + alt * 0.35 + rain * 0.2) * muffle, dt)
	_fade("rain", smoothstep(0.45, 0.8, rain) * 0.8 * (0.6 if inside_car else 1.0), dt)
	var rd := _river_dist(p)
	_fade("river", clampf(1.0 - rd / 70.0, 0.0, 1.0) * 0.6 * muffle, dt)
	if rain > 0.7:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(25.0, 70.0)
			var th: AudioStreamPlayer = players.thunder
			th.volume_db = randf_range(-12.0, -2.0)
			th.pitch_scale = randf_range(0.8, 1.1)
			th.play()
