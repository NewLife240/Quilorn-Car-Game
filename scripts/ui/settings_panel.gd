extends PanelContainer
## Graphics / gameplay settings. Used from the main menu and the pause menu.

signal closed

var _rows: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	custom_minimum_size = Vector2(760, 640)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var v := UIKit.vbox([], 10)
	add_child(v)
	v.add_child(UIKit.label("Settings", 30, UIKit.ACCENT, true))
	var q := HBoxContainer.new()
	q.add_child(UIKit.label("Quality preset", 18))
	q.add_child(UIKit.spacer())
	for p in ["low", "medium", "high", "ultra"]:
		q.add_child(UIKit.button(p.capitalize(), func(): Game.set_quality(p); _rebuild()))
	v.add_child(q)
	_rows = UIKit.vbox([], 6)
	v.add_child(UIKit.scroll(_rows))
	v.add_child(UIKit.hbox([UIKit.spacer(), UIKit.button("Close", func(): closed.emit(); queue_free(), 160)]))
	_rebuild()


func _rebuild() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var s: Dictionary = Game.settings
	_slider("Render scale (lower = faster)", "render_scale", 0.5, 1.0, 0.05)
	_check("AMD FSR 2 upscaling (when render scale < 1)", "fsr")
	_option("Shadows", "shadows", ["Off", "Low", "High", "Ultra"])
	_check("Ambient occlusion (SSAO)", "ssao")
	_check("Bloom / glow", "glow")
	_check("Volumetric fog (expensive)", "volumetric")
	_slider("View distance", "view_distance", 0.5, 1.5, 0.05)
	_slider("Grass & crops density", "grass", 0.0, 1.5, 0.05)
	_option("FPS limit", "fps_limit", ["Unlimited", "60", "120", "144", "165"], [0, 60, 120, 144, 165])
	_check("V-Sync", "vsync")
	_check("Fullscreen", "fullscreen")
	_slider("Field of view", "fov", 60, 100, 1)
	_slider("Mouse sensitivity", "sensitivity", 0.05, 0.6, 0.01)
	_check("Invert mouse Y", "invert_y")
	_check("Automatic gearbox (G toggles while driving)", "auto_gearbox")
	_slider("Master volume", "master_volume", 0.0, 1.0, 0.05)
	_check("Show FPS counter", "show_fps")


func _row(title: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := UIKit.label(title, 17)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(ctrl)
	_rows.add_child(h)


func _slider(title: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(Game.settings[key])
	sl.custom_minimum_size.x = 240
	var val := UIKit.label(str(snappedf(sl.value, step)), 16, UIKit.ACCENT)
	val.custom_minimum_size.x = 56
	sl.value_changed.connect(func(x): Game.settings[key] = x; val.text = str(snappedf(x, step)))
	sl.drag_ended.connect(func(_c): Game.commit_settings())
	h.add_child(sl)
	h.add_child(val)
	_row(title, h)


func _check(title: String, key: String) -> void:
	var c := CheckBox.new()
	c.button_pressed = bool(Game.settings[key])
	c.toggled.connect(func(on): Game.settings[key] = on; Game.commit_settings())
	_row(title, c)


func _option(title: String, key: String, items: Array, values: Array = []) -> void:
	var o := OptionButton.new()
	for i in items:
		o.add_item(i)
	var cur = Game.settings[key]
	o.selected = values.find(int(cur)) if not values.is_empty() else int(cur)
	o.item_selected.connect(func(i): Game.settings[key] = values[i] if not values.is_empty() else i; Game.commit_settings())
	_row(title, o)
