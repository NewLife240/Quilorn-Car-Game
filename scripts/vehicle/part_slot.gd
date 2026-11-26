extends Area3D
class_name PartSlot
## A mounting point on a vehicle. Holds one installed part (data Dictionary) with bolt state.

signal changed(slot: PartSlot)

var slot_name := ""
var vehicle: Node = null
var parent_slot: PartSlot = null
var child_slots: Array[PartSlot] = []
var needs_hood := false
var data: Dictionary = {}          # {"id":..., "cond":..., ...}
var bolts := 0                     # tightened bolts
var model: Node3D = null
var mount: Node3D = null           # node the model hangs from (moves with engine etc.)
var size := Vector3(0.4, 0.4, 0.4)
var model_scale := Vector3.ONE
var model_rot := Vector3.ZERO
var _shape: CollisionShape3D
var _ghost: MeshInstance3D


func setup(p_name: String, p_vehicle: Node, p_size: Vector3) -> void:
	slot_name = p_name
	vehicle = p_vehicle
	size = p_size
	name = "Slot_" + p_name
	collision_layer = 1 << 4
	collision_mask = 0
	monitoring = false
	monitorable = true
	_shape = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	_shape.shape = b
	add_child(_shape)
	mount = Node3D.new()
	mount.name = "Mount"
	add_child(mount)
	set_meta("interactable", true)


func is_installed() -> bool:
	return not data.is_empty()


func part_id() -> String:
	return data.get("id", "")


func cond() -> float:
	return float(data.get("cond", 0.0)) if is_installed() else 0.0


func max_bolts() -> int:
	if not is_installed():
		return 0
	return int(DB.part(part_id()).get("bolts", 2))


func is_tight() -> bool:
	return is_installed() and bolts >= max_bolts()


## Quality factor 0..1 used by the simulation. Loose parts work worse.
func quality() -> float:
	if not is_installed():
		return 0.0
	var q := cond() / 100.0
	if bolts == 0:
		q *= 0.6
	elif bolts < max_bolts():
		q *= 0.85
	return q


func accessible() -> bool:
	if parent_slot and not parent_slot.is_installed():
		return false
	if needs_hood and vehicle and not vehicle.hood_open:
		return false
	return true


func update_enabled() -> void:
	var en := accessible()
	_shape.disabled = not en
	for c in child_slots:
		c.update_enabled()


func can_accept(item_id: String) -> bool:
	if is_installed() or not accessible():
		return false
	return DB.fits(item_id, slot_name, vehicle.cls)


func install(d: Dictionary, p_bolts: int = 0) -> void:
	data = d.duplicate(true)
	bolts = p_bolts
	_make_model()
	for c in child_slots:
		c.update_enabled()
	changed.emit(self)


func remove() -> Dictionary:
	var d := data
	data = {}
	bolts = 0
	if model:
		model.queue_free()
		model = null
	for c in child_slots:
		c.update_enabled()
	changed.emit(self)
	return d


func has_children_installed() -> bool:
	for c in child_slots:
		if c.is_installed():
			return true
	return false


func tighten() -> bool:
	if is_installed() and bolts < max_bolts():
		bolts += 1
		changed.emit(self)
		return true
	return false


func loosen() -> bool:
	if is_installed() and bolts > 0:
		bolts -= 1
		changed.emit(self)
		return true
	return false


func _make_model() -> void:
	if model:
		model.queue_free()
	var def := DB.part(part_id())
	var ps: PackedScene = load(def.mesh)
	model = ps.instantiate()
	model.scale = model_scale * float(def.get("scale", 1.0))
	model.rotation = model_rot
	mount.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func show_ghost(on: bool, item_id: String = "") -> void:
	if on:
		if _ghost == null:
			_ghost = MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			_ghost.mesh = bm
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.3, 1.0, 0.4, 0.25)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = true
			_ghost.material_override = m
			_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_ghost)
		_ghost.visible = true
	elif _ghost:
		_ghost.visible = false


func describe() -> String:
	if not is_installed():
		return "%s slot (empty)" % DB.slot_display(slot_name)
	var def := DB.part(part_id())
	var s := "%s  %d%%  bolts %d/%d" % [def.name, int(cond()), bolts, max_bolts()]
	if slot_name == "battery":
		s += "  charge %d%%" % int(data.get("charge", 0))
	return s


func save_state() -> Dictionary:
	return {"data": data, "bolts": bolts}
