extends Control
## Map tab: world map texture with locations, jobs, vehicles and the player.

var tex: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(600, 560)
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _process(_dt: float) -> void:
	queue_redraw()


func _w2m(p: Vector3, r: Rect2) -> Vector2:
	return r.position + Vector2((p.x + 1024.0) / 2048.0, (p.z + 1024.0) / 2048.0) * r.size


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var r := Rect2(Vector2((size.x - s) * 0.5, 0), Vector2(s, s))
	if tex:
		draw_texture_rect(tex, r, false)
	else:
		draw_rect(r, Color(0.2, 0.3, 0.2))
	var font := get_theme_default_font()
	var w = Game.world
	for k in w.locations.keys():
		var l: Dictionary = w.locations[k]
		var p := _w2m(Vector3(l.x, 0, l.z), r)
		draw_circle(p, 4, Color(1, 1, 1))
		draw_string(font, p + Vector2(7, 5), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
	var eco = w.economy
	for j in eco.active:
		var a := _w2m(eco.site_pos(j.from), r)
		var b := _w2m(eco.site_pos(j.to), r)
		draw_line(a, b, Color(1, 0.8, 0.2, 0.8), 2.0)
		draw_circle(b if j.loaded else a, 7, Color(1, 0.8, 0.2))
	for v in w.vehicles:
		var p := _w2m(v.global_position, r)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.7, 1.0) if v.owned else Color(0.7, 0.7, 0.7))
	var pl: Player = Game.player
	if pl:
		var pp := _w2m(pl.global_position, r)
		var f := -pl.cam.global_basis.z
		var ang := atan2(f.z, f.x)
		var pts := PackedVector2Array([pp + Vector2(cos(ang), sin(ang)) * 12, pp + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 8, pp + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 8])
		draw_colored_polygon(pts, Color(1, 0.25, 0.2))
