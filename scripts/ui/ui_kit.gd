extends RefCounted
class_name UIKit
## Theme and small widget builders shared by every UI screen.

const ACCENT := Color(0.98, 0.78, 0.22)
const PANEL := Color(0.07, 0.08, 0.1, 0.92)
const PANEL2 := Color(0.13, 0.14, 0.17, 0.95)
static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var f: Font = load("res://assets/fonts/DejaVuSans.ttf")
	var fb: Font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	t.default_font = f
	t.default_font_size = 18
	t.set_font("bold", "Label", fb)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", sb)
	t.set_stylebox("panel", "Panel", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.2, 0.22, 0.26)
	bn.set_corner_radius_all(6)
	bn.set_content_margin_all(8)
	bn.content_margin_left = 14
	bn.content_margin_right = 14
	var bh := bn.duplicate()
	bh.bg_color = Color(0.3, 0.32, 0.38)
	var bp := bn.duplicate()
	bp.bg_color = ACCENT.darkened(0.2)
	var bd := bn.duplicate()
	bd.bg_color = Color(0.15, 0.15, 0.17)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.95))
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0.12, 0.13, 0.16)
	tab.set_content_margin_all(10)
	tab.content_margin_left = 18
	tab.content_margin_right = 18
	var tabs := tab.duplicate()
	tabs.bg_color = Color(0.22, 0.24, 0.3)
	tabs.border_color = ACCENT
	tabs.border_width_bottom = 3
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tabs)
	t.set_stylebox("tab_selected", "TabContainer", tabs)
	var pan := StyleBoxFlat.new()
	pan.bg_color = Color(0, 0, 0, 0)
	t.set_stylebox("panel", "TabContainer", pan)
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	var row := StyleBoxFlat.new()
	row.bg_color = PANEL2
	row.set_corner_radius_all(6)
	row.set_content_margin_all(10)
	t.set_stylebox("panel", "row", row)
	return t


static func label(text: String, size := 18, col := Color(0.92, 0.92, 0.92), bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", theme().get_font("bold", "Label"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	return b


static func row_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "row"
	var sb: StyleBox = theme().get_stylebox("panel", "row")
	p.add_theme_stylebox_override("panel", sb)
	return p


static func hbox(children: Array, sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func vbox(children: Array = [], sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func bar(value: float, col: Color, w := 160.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = 1
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(w, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(3)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


static func cond_color(c: float) -> Color:
	if c > 70:
		return Color(0.4, 0.9, 0.4)
	if c > 35:
		return Color(1.0, 0.8, 0.3)
	return Color(1.0, 0.35, 0.3)
