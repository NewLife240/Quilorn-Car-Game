extends Node
## Global game state: money, clock, settings, notifications, save/load.

signal money_changed(value: int)
signal notified(text: String, kind: String)
signal settings_changed
signal hour_passed(day: int, hour: int)

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const MINUTES_PER_SECOND := 1.0  # 1 real second = 1 game minute -> 24 min day

var money: int = 1800
var day: int = 1
var minutes: float = 7.5 * 60.0  # time of day in minutes
var time_scale: float = 1.0
var world: Node = null
var player: Node = null
var hud: Node = null
var ui_open: bool = false
var loading_save: bool = false
var new_game: bool = true
var stats := {"earned": 0, "deliveries": 0, "km": 0.0}
var flags := {}

var settings := {
	"quality": "high", "render_scale": 1.0, "fsr": false, "fov": 75.0, "sensitivity": 0.22,
	"vsync": false, "fps_limit": 0, "view_distance": 1.0, "grass": 1.0, "shadows": 2,
	"ssao": true, "glow": true, "volumetric": false, "auto_gearbox": true, "fullscreen": true,
	"invert_y": false, "master_volume": 0.8, "show_fps": true,
}

var _last_hour := -1


var _ui_player: AudioStreamPlayer


func ui_sound(name: String) -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_ui_player)
	_ui_player.stream = load("res://assets/sounds/ui/%s.ogg" % name)
	_ui_player.volume_db = -8.0
	_ui_player.play()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	apply_window_settings()


func _process(delta: float) -> void:
	if get_tree().paused or world == null:
		return
	minutes += delta * MINUTES_PER_SECOND * time_scale
	if minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
	var hr := int(minutes / 60.0)
	if hr != _last_hour:
		_last_hour = hr
		hour_passed.emit(day, hr)


func hour_f() -> float:
	return minutes / 60.0


func clock_text() -> String:
	var h := int(minutes / 60.0)
	var m := int(minutes) % 60
	return "Day %d  %02d:%02d" % [day, h, m]


func add_money(amount: int, reason: String = "") -> void:
	money += amount
	if amount > 0:
		stats.earned += amount
	money_changed.emit(money)
	if reason != "":
		notify(("+" if amount >= 0 else "") + "₴%d  %s" % [amount, reason], "money" if amount >= 0 else "cost")


func can_afford(amount: int) -> bool:
	return money >= amount


func spend(amount: int, reason: String = "") -> bool:
	if money < amount:
		notify("Not enough money (₴%d needed)" % amount, "warn")
		return false
	add_money(-amount, reason)
	return true


func notify(text: String, kind: String = "info") -> void:
	notified.emit(text, kind)


func set_ui_open(open: bool) -> void:
	ui_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ input
func _key(action: String, keys: Array, mouse: Array = []) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in mouse:
		var m := InputEventMouseButton.new()
		m.button_index = b
		InputMap.action_add_event(action, m)


func _setup_input() -> void:
	_key("forward", [KEY_W, KEY_UP])
	_key("back", [KEY_S, KEY_DOWN])
	_key("left", [KEY_A, KEY_LEFT])
	_key("right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("crouch", [KEY_C])
	_key("interact", [KEY_E])
	_key("grab", [], [MOUSE_BUTTON_LEFT])
	_key("throw", [], [MOUSE_BUTTON_RIGHT])
	_key("tighten", [KEY_R])
	_key("loosen", [KEY_T])
	_key("tablet", [KEY_TAB])
	_key("pause", [KEY_ESCAPE])
	_key("map", [KEY_M])
	# vehicle
	_key("handbrake", [KEY_SPACE])
	_key("shift_up", [KEY_SHIFT])
	_key("shift_down", [KEY_CTRL])
	_key("ignition", [KEY_F])
	_key("lights", [KEY_L])
	_key("horn", [KEY_H])
	_key("camera", [KEY_V])
	_key("diff_lock", [KEY_X])
	_key("drive_mode", [KEY_Z])
	_key("gearbox_mode", [KEY_G])
	_key("look_back", [KEY_B])
	_key("reset_vehicle", [KEY_BACKSPACE])
	_key("cargo", [KEY_J])


# ------------------------------------------------------------------ settings
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			settings[k] = cf.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_window_settings() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.fps_limit)
	if not DisplayServer.get_name() == "headless":
		var want := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if settings.fsr and settings.render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(settings.render_scale)
	AudioServer.set_bus_volume_db(0, linear_to_db(float(settings.master_volume)))


func set_quality(q: String) -> void:
	settings.quality = q
	match q:
		"low":
			settings.merge({"shadows": 0, "ssao": false, "glow": false, "volumetric": false, "grass": 0.35, "view_distance": 0.6, "render_scale": 0.77, "fsr": true}, true)
		"medium":
			settings.merge({"shadows": 1, "ssao": false, "glow": true, "volumetric": false, "grass": 0.65, "view_distance": 0.8, "render_scale": 1.0, "fsr": false}, true)
		"high":
			settings.merge({"shadows": 2, "ssao": true, "glow": true, "volumetric": false, "grass": 1.0, "view_distance": 1.0, "render_scale": 1.0, "fsr": false}, true)
		"ultra":
			settings.merge({"shadows": 3, "ssao": true, "glow": true, "volumetric": true, "grass": 1.4, "view_distance": 1.3, "render_scale": 1.0, "fsr": false}, true)
	commit_settings()


func commit_settings() -> void:
	save_settings()
	apply_window_settings()
	settings_changed.emit()


# ------------------------------------------------------------------ save / load
func save_game() -> void:
	if world == null:
		return
	var data := {
		"version": 1, "money": money, "day": day, "minutes": minutes, "stats": stats, "flags": flags,
		"world": world.save_state(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	notify("Game saved", "info")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func read_save() -> Dictionary:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func start_new_game() -> void:
	money = 1800
	day = 1
	minutes = 7.5 * 60.0
	stats = {"earned": 0, "deliveries": 0, "km": 0.0}
	flags = {}
	new_game = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func continue_game() -> void:
	var d := read_save()
	if d.is_empty():
		start_new_game()
		return
	money = int(d.get("money", 1800))
	day = int(d.get("day", 1))
	minutes = float(d.get("minutes", 450.0))
	stats = d.get("stats", stats)
	flags = d.get("flags", {})
	new_game = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func pending_world_state() -> Dictionary:
	if new_game:
		return {}
	return read_save().get("world", {})
