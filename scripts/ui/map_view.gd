extends Control
## Map tab: zoomable / draggable world map with points of interest, jobs, vehicles and the player.

var tex: Texture2D
var zoom := 1.0
var center := Vector2.ZERO        # world xz at the view centre
var _drag := false
var _centered := false

const POI := {
	"garage": ["H", Color(0.3, 0.9, 1.0), "Home & garage"],
	"parts_store": ["P", Color(1.0, 0.8, 0.2), "Auto parts store"],
	"shop_village": ["S", Color(0.6, 1.0, 0.5), "Village shop"],
	"gas_station": ["F", Color(1.0, 0.35, 0.3), "Gas station"],
	"car_market": ["C", Color(0.45, 0.6, 1.0), "Car market"],
	"junkyard_office": ["J", Color(0.85, 0.55, 0.3), "Junkyard (used parts)"],
	"town_market": ["M", Color(0.9, 0.6, 1.0), "Town market (buys goods)"],
	"warehouse": ["W", Color(0.75, 0.75, 0.75), "Warehouse (buys goods)"],
}


func _ready() -> void:
	custom_minimum_size = Vector2(600, 560)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(_dt: float) -> void:
	if not _centered and Game.player:
		_centered = true
		center = Vector2(Game.player.global_position.x, Game.player.global_position.z)
		zoom = 2.0
	queue_redraw()


func _px_per_m() -> float:
	return minf(size.x, size.y) / 2048.0 * zoom


func _w2m(p: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(p.x, p.z) - center) * _px_per_m()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before: Vector2 = center + (e.position - size * 0.5) / _px_per_m()
			zoom = clampf(zoom * (1.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, 12.0)
			var after: Vector2 = center + (e.position - size * 0.5) / _px_per_m()
			center += before - after
			accept_event()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		center -= e.relative / _px_per_m()
	center = center.clamp(Vector2(-1024, -1024), Vector2(1024, 1024))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.1))
	var tl := _w2m(Vector3(-1024, 0, -1024))
	var br := _w2m(Vector3(1024, 0, 1024))
	if tex:
		draw_texture_rect(tex, Rect2(tl, br - tl), false)
	var font := get_theme_default_font()
	var w = Game.world
	var fs := int(clampf(11 + zoom, 12, 18))
	for k in w.locations.keys():
		var l: Dictionary = w.locations[k]
		var p := _w2m(Vector3(l.x, 0, l.z))
		draw_string_outline(font, p + Vector2(-40, -14), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		draw_string(font, p + Vector2(-40, -14), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
	# points of interest
	for o in w.props.objects:
		if POI.has(o.kind):
			var d: Array = POI[o.kind]
			var p := _w2m(Vector3(o.x, 0, o.z))
			draw_circle(p, 9, Color(0, 0, 0, 0.7))
			draw_circle(p, 7.5, d[1])
			draw_string(font, p + Vector2(-4.5, 5), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0))
	var eco = w.economy
	for k in eco.industries.keys():
		var p := _w2m(eco.site_pos(k))
		var mine: bool = eco.industries[k].owner == "player"
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(0.4, 1.0, 0.4) if mine else Color(1.0, 0.85, 0.3))
		if zoom > 2.2:
			draw_string_outline(font, p + Vector2(9, 5), eco.industries[k].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
			draw_string(font, p + Vector2(9, 5), eco.industries[k].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.8))
	for j in eco.active:
		var a := _w2m(eco.site_pos(j.from))
		var b := _w2m(eco.site_pos(j.to))
		draw_dashed_line(a, b, Color(1, 0.8, 0.2, 0.9), 2.0, 8.0)
		draw_circle(b if j.loaded else a, 8, Color(1, 0.3, 0.2))
	for v in w.vehicles:
		var p := _w2m(v.global_position)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.7, 1.0) if v.owned else Color(0.7, 0.7, 0.7))
	var pl: Player = Game.player
	if pl:
		var pp := _w2m(pl.global_position)
		var f := -pl.cam.global_basis.z
		var ang := atan2(f.z, f.x)
		var pts := PackedVector2Array([pp + Vector2(cos(ang), sin(ang)) * 13, pp + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 9, pp + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 9])
		draw_colored_polygon(pts, Color(1, 0.2, 0.15))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0), 1.5)
	# legend
	var y := 14.0
	draw_rect(Rect2(Vector2(8, 6), Vector2(250, 22.0 * (POI.size() + 3) + 6)), Color(0, 0, 0, 0.6))
	for k in POI.keys():
		var d: Array = POI[k]
		draw_circle(Vector2(22, y + 6), 7, d[1])
		draw_string(font, Vector2(17.5, y + 11), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0))
		draw_string(font, Vector2(36, y + 11), d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
		y += 22
	draw_rect(Rect2(Vector2(16, y), Vector2(12, 12)), Color(1.0, 0.85, 0.3))
	draw_string(font, Vector2(36, y + 11), "Industry (green = yours)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
	y += 22
	draw_circle(Vector2(22, y + 6), 6, Color(1, 0.3, 0.2))
	draw_string(font, Vector2(36, y + 11), "Job pickup / drop-off", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
	y += 22
	draw_string(font, Vector2(16, y + 11), "Wheel: zoom   Drag: pan", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))
