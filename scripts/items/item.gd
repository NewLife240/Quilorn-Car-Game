extends RigidBody3D
class_name Item
## A physical, pickable item: car part, fluid container or tool.

var item_id := ""
var data: Dictionary = {}
var held := false
var shop_price := 0          # >0 while the item still sits on a shop pallet unpaid
var model: Node3D


static func spawn(parent: Node, id: String, d: Dictionary, xf: Transform3D) -> Item:
	var it := Item.new()
	it.item_id = id
	it.data = d.duplicate(true)
	it.data.id = id
	parent.add_child(it)
	it.global_transform = xf
	return it


func _ready() -> void:
	var def := DB.part(item_id)
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2)
	mass = float(def.get("mass", 2.0))
	linear_damp = 0.1
	angular_damp = 0.4
	can_sleep = true
	continuous_cd = mass < 3.0
	set_meta("item", true)
	var ps: PackedScene = load(def.mesh)
	model = ps.instantiate()
	add_child(model)
	var sc: float = def.get("scale", 1.0)
	if item_id.begins_with("wheel"):
		sc = 1.0
	model.scale = Vector3.ONE * sc
	# collision box from mesh bounds
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		a = (mi as MeshInstance3D).transform * a
		aabb = a if first else aabb.merge(a)
		first = false
	aabb.position *= sc
	aabb.size *= sc
	var cs := CollisionShape3D.new()
	if item_id.begins_with("wheel"):
		var cyl := CylinderShape3D.new()
		cyl.radius = aabb.size.y * 0.5
		cyl.height = aabb.size.x
		cs.shape = cyl
		cs.rotation.z = PI / 2
	else:
		var bs := BoxShape3D.new()
		bs.size = aabb.size.max(Vector3(0.05, 0.05, 0.05))
		cs.shape = bs
	cs.position = aabb.get_center()
	add_child(cs)
	if not data.has("cond"):
		data.cond = 100.0
	if def.has("fluid") and not data.has("fill"):
		data.fill = float(def.capacity)
	if item_id == "battery" and not data.has("charge"):
		data.charge = 80.0


func display_name() -> String:
	var def := DB.part(item_id)
	var s: String = def.get("name", item_id)
	if DB.is_part(item_id):
		s += "  (%d%%)" % int(data.get("cond", 100))
	if data.has("fill"):
		s += "  %.1f / %.0f L" % [float(data.fill), float(def.capacity)]
	if item_id == "battery":
		s += "  charge %d%%" % int(data.get("charge", 0))
	if shop_price > 0:
		s += "  -  ₴%d" % shop_price
	return s


func save_state() -> Dictionary:
	return {"id": item_id, "data": data, "xf": var_to_str(global_transform), "price": shop_price}
