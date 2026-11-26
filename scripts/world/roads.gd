extends Node3D
class_name Roads
## Builds asphalt road ribbons on top of the (already flattened) terrain.

var data: Array = []


func build(terrain: Terrain, roads: Array) -> void:
	data = roads
	var lane_mat := _mat("road", 1.0)
	var plain_mat := _mat("asphalt", 0.25)
	var idx := 0
	for rd in roads:
		if rd.kind != "asphalt":
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(terrain, rd.pts, float(rd.w), 0.012 + idx * 0.003, rd.w >= 7.0)
		mi.material_override = lane_mat if rd.w >= 7.0 else plain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		idx += 1


func _mat(name: String, uscale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_c.jpg" % name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_n.jpg" % name)
	m.roughness_texture = load("res://assets/textures/%s_r.jpg" % name)
	m.albedo_color = Color(0.78, 0.78, 0.8)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if uscale < 1.0:
		m.uv1_scale = Vector3(1, 1, 1)
	return m


func _ribbon(t: Terrain, pts: Array, w: float, lift: float, lanes: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := maxi(6, int(ceil(w)))
	var dist := 0.0
	var prev := Vector3.ZERO
	var rows := []
	var clean := []
	for q in pts:
		if clean.is_empty() or Vector2(q[0] - clean[-1][0], q[2] - clean[-1][2]).length() > 1.2:
			clean.append(q)
	pts = clean
	for i in range(pts.size()):
		var p := Vector3(pts[i][0], 0, pts[i][2])
		var a := Vector3(pts[maxi(i - 2, 0)][0], 0, pts[maxi(i - 2, 0)][2])
		var b := Vector3(pts[mini(i + 2, pts.size() - 1)][0], 0, pts[mini(i + 2, pts.size() - 1)][2])
		var tan := (b - a).normalized()
		var nrm := Vector3(-tan.z, 0, tan.x)
		if i > 0:
			dist += p.distance_to(prev)
		prev = p
		var row := []
		for k in range(-1, across + 2):
			var f := float(k) / across
			var edge := k < 0 or k > across
			var fc := clampf(f, 0.0, 1.0)
			var q := p + nrm * (fc - 0.5) * w
			q.y = t.height_at(q.x, q.z) + lift
			if edge:
				q += nrm * (0.45 if k > across else -0.45)
				q.y -= 0.32
			var u := fc if lanes else fc * w / 4.0
			if edge:
				u += (0.04 if k > across else -0.04)
			var v := dist / (w if lanes else 4.0)
			row.append([q, Vector2(u, v)])
		rows.append(row)
	for i in range(rows.size() - 1):
		for k in range(across + 2):
			var a: Array = rows[i][k]
			var b: Array = rows[i][k + 1]
			var c: Array = rows[i + 1][k]
			var d: Array = rows[i + 1][k + 1]
			for v in [a, c, b, b, c, d]:
				st.set_uv(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	st.generate_tangents()
	return st.commit()


## Closest point on any road to p (xz).  Returns [distance, point, tangent, road_index]
func nearest(p: Vector3) -> Array:
	var best := [1e9, Vector3.ZERO, Vector3.FORWARD, -1]
	for ri in range(data.size()):
		var pts: Array = data[ri].pts
		for i in range(0, pts.size() - 1):
			var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
			var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
			var ab := b - a
			var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var q := a + ab * tt
			var d := Vector2(p.x - q.x, p.z - q.z).length()
			if d < best[0]:
				best = [d, q, ab.normalized(), ri]
	return best
