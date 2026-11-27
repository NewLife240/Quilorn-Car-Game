extends Node
## Economy rules test (headless): daily upkeep is charged when sleeping through midnight,
## hiring needs money, the starter car always has parcel work, gluts clear.
## Run: godot --headless res://tests/economy_test.tscn   (exit code 1 on failure)

var world: World
var failures := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _ready() -> void:
	Game.new_game = true
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	for i in 3: await get_tree().physics_frame
	var eco = world.economy

	# the starter car (2 parcel slots) always finds small parcel runs on the board
	var small: Array = eco.jobs.filter(func(j): return j.good == "parcel" and int(j.units) <= 2)
	check(small.size() >= eco.SMALL_PARCEL_JOBS, "board has >= %d small parcel jobs (%d)" % [eco.SMALL_PARCEL_JOBS, small.size()])

	# hiring with no money is refused (it used to push money negative for an extra driver)
	eco.industries.sunflower_farm.owner = "player"
	Game.money = 600
	eco.hire_route("sunflower_farm", "warehouse", "sunflower")
	check(eco.routes.size() == 1 and Game.money == 100, "first driver hired for ₴%d" % eco.DRIVER_HIRE)
	eco.hire_route("sunflower_farm", "warehouse", "sunflower")
	check(int(eco.routes[0].trucks) == 1 and Game.money == 100, "second driver refused without money")

	# sleeping from 21:00 to 07:00 crosses midnight: upkeep + wages must be charged once
	Game.money = 5000
	Game.minutes = 21.0 * 60.0
	var day0 := Game.day
	eco._sleep(null)
	var expected: int = int(DB.INDUSTRIES.sunflower_farm.upkeep) + eco.DRIVER_WAGE
	var route_income: int = eco._ff_income
	check(Game.day == day0 + 1 and is_equal_approx(Game.minutes, 420.0), "woke up next day at 07:00")
	check(Game.money == 5000 - expected + route_income, "slept: charged ₴%d upkeep+wage once, drivers earned ₴%d (money %d)" % [expected, route_income, Game.money])
	check(route_income > 0, "hired driver kept working overnight")

	# a glut at a buyer is capped, so the price recovers after you stop oversupplying
	eco._receive_goods("warehouse", "sunflower", 500)
	check(int(eco.consumers.warehouse.stock.sunflower) <= eco.CONSUMER_STOCK_MAX, "consumer stock capped at %d" % eco.CONSUMER_STOCK_MAX)
	check(eco.price("sunflower", "warehouse") >= int(DB.GOODS.sunflower.price * eco.PRICE_FLOOR), "glut price stays at the floor")
	# factories never pay a scarcity premium
	eco.industries.oil_press.inp.sunflower = 0
	check(eco.price("sunflower", "oil_press") <= int(DB.GOODS.sunflower.price), "factory input price capped at base")

	print("ECONOMY TEST ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
