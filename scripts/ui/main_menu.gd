extends Control
## Main menu.

var _panel: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var bg := TextureRect.new()
	if ResourceLoader.exists("res://assets/ui/menu_bg.jpg"):
		bg.texture = load("res://assets/ui/menu_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = UIKit.vbox([], 14)
	_panel.position = Vector2(110, 230)
	add_child(_panel)
	_panel.add_child(UIKit.label("RUSTY ROADS", 84, UIKit.ACCENT, true))
	_panel.add_child(UIKit.label("Fix cars. Haul cargo. Build a business in the Ukrainian countryside.", 22, Color(0.9, 0.9, 0.85)))
	_panel.add_child(Control.new())
	if Game.has_save():
		_panel.add_child(UIKit.button("Continue", func(): Game.continue_game(), 320))
	_panel.add_child(UIKit.button("New game", func(): Game.start_new_game(), 320))
	_panel.add_child(UIKit.button("Settings", _settings, 320))
	_panel.add_child(UIKit.button("Quit", func(): get_tree().quit(), 320))
	var v := UIKit.label("v1.0  ·  Godot 4.7  ·  models: GGBot, rgsdev, OpenGameArt (CC0) · textures: ambientCG (CC0)", 14, Color(0.7, 0.7, 0.7))
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	v.position = Vector2(24, get_viewport_rect().size.y - 40)
	add_child(v)


func _settings() -> void:
	var s := preload("res://scripts/ui/settings_panel.gd").new()
	add_child(s)
	s.position = (get_viewport_rect().size - Vector2(760, 640)) * 0.5
