extends RefCounted
## Tiny assertion helper for the headless test scenes.
##   var c := Check.new("drive", get_tree(), 180.0)
##   c.ok(v.running, "engine started")
##   c.finish()   # quits with exit code 0 if every check passed, 1 otherwise
## A watchdog fails the test (exit code 2) if it has not finished after `timeout_s`,
## so a test that hangs or dies on a script error never passes silently.

var test_name := ""
var passed := 0
var failed := 0
var done := false
var _tree: SceneTree


func _init(p_name: String, tree: SceneTree, timeout_s: float = 240.0) -> void:
	test_name = p_name
	_tree = tree
	var timer := tree.create_timer(timeout_s, true, false, true)
	timer.timeout.connect(_on_timeout.bind(timeout_s))


func ok(cond: bool, msg: String) -> bool:
	if cond:
		passed += 1
		print("  PASS  ", msg)
	else:
		failed += 1
		print("  FAIL  ", msg)
	return cond


## Numeric helpers print the measured value, so a failure shows how far off it was.
func at_least(value: float, minimum: float, what: String) -> bool:
	return ok(value >= minimum, "%s = %.2f (want >= %.2f)" % [what, value, minimum])


func at_most(value: float, maximum: float, what: String) -> bool:
	return ok(value <= maximum, "%s = %.2f (want <= %.2f)" % [what, value, maximum])


func finish() -> void:
	if done:
		return
	done = true
	var status := "PASSED" if failed == 0 else "FAILED"
	print("RESULT %s %s (%d passed, %d failed)" % [test_name, status, passed, failed])
	_tree.quit(0 if failed == 0 else 1)


func _on_timeout(timeout_s: float) -> void:
	if done:
		return
	done = true
	print("  FAIL  timed out after %.0f s (test hung or stopped on a script error)" % timeout_s)
	print("RESULT %s FAILED (%d passed, %d failed, timeout)" % [test_name, passed, failed + 1])
	_tree.quit(2)
