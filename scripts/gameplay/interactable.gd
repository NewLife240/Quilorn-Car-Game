extends Area3D
## Generic interactable trigger used by world services (shops, pumps, offices, beds).
var callback: Callable


func interact(p: Node) -> void:
	if callback.is_valid():
		callback.call(p)
