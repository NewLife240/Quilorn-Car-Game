extends Node
## Static game data: parts, vehicles, goods, industries.

const P := "res://assets/parts/"

# slot: which vehicle slot the part fits.  cls: "small" or "big" (vehicle class).
# bolts: number of bolts to tighten.  wear: condition loss per hour of engine running.
var PARTS := {
	"engine_i4": {"name": "1.5L Petrol Engine", "slot": "engine", "cls": "small", "price": 950, "mass": 110.0, "mesh": P + "engine_i4.glb", "bolts": 6,
		"torque": 118.0, "rpm_peak": 3400.0, "redline": 6000.0, "idle": 850.0, "inertia": 0.16, "fuel_use": 1.0, "wear": 0.35},
	"engine_i4_sport": {"name": "1.8L Twin-Carb Engine", "slot": "engine", "cls": "small", "price": 2400, "mass": 118.0, "mesh": P + "engine_i4_sport.glb", "bolts": 6,
		"torque": 152.0, "rpm_peak": 4400.0, "redline": 7000.0, "idle": 900.0, "inertia": 0.14, "fuel_use": 1.35, "wear": 0.5},
	"engine_diesel": {"name": "6.0L Diesel Engine", "slot": "engine", "cls": "big", "price": 4200, "mass": 380.0, "mesh": P + "engine_diesel.glb", "bolts": 8,
		"torque": 520.0, "rpm_peak": 1600.0, "redline": 3000.0, "idle": 650.0, "inertia": 0.9, "fuel_use": 2.6, "wear": 0.25},
	"gearbox": {"name": "4-Speed Gearbox", "slot": "gearbox", "cls": "small", "price": 520, "mass": 32.0, "mesh": P + "gearbox.glb", "bolts": 4, "wear": 0.15},
	"gearbox_heavy": {"name": "Heavy 5-Speed Gearbox", "slot": "gearbox", "cls": "big", "price": 1400, "mass": 95.0, "mesh": P + "gearbox.glb", "bolts": 6, "wear": 0.1, "scale": 1.35},
	"carburetor": {"name": "Carburettor", "slot": "carburetor", "price": 140, "mass": 2.5, "mesh": P + "carburetor.glb", "bolts": 2, "wear": 0.6},
	"air_filter": {"name": "Air Filter", "slot": "air_filter", "price": 28, "mass": 0.8, "mesh": P + "air_filter.glb", "bolts": 1, "wear": 1.2},
	"spark_plugs": {"name": "Spark Plugs (set)", "slot": "spark_plugs", "price": 34, "mass": 0.4, "mesh": P + "spark_plugs.glb", "bolts": 4, "wear": 1.0},
	"ignition_coil": {"name": "Ignition Coil", "slot": "ignition_coil", "price": 65, "mass": 1.2, "mesh": P + "ignition_coil.glb", "bolts": 2, "wear": 0.4},
	"alternator": {"name": "Alternator", "slot": "alternator", "price": 150, "mass": 5.5, "mesh": P + "alternator.glb", "bolts": 2, "wear": 0.4},
	"starter": {"name": "Starter Motor", "slot": "starter", "price": 125, "mass": 4.5, "mesh": P + "starter.glb", "bolts": 2, "wear": 0.0},
	"radiator": {"name": "Radiator", "slot": "radiator", "price": 170, "mass": 7.0, "mesh": P + "radiator.glb", "bolts": 4, "wear": 0.2},
	"battery": {"name": "Battery 55Ah", "slot": "battery", "price": 115, "mass": 14.0, "mesh": P + "battery.glb", "bolts": 2, "wear": 0.1},
	"fuel_tank": {"name": "Fuel Tank", "slot": "fuel_tank", "price": 190, "mass": 9.0, "mesh": P + "fuel_tank.glb", "bolts": 4, "wear": 0.05},
	"exhaust": {"name": "Exhaust & Muffler", "slot": "exhaust", "price": 135, "mass": 11.0, "mesh": P + "exhaust.glb", "bolts": 3, "wear": 0.25},
	"wheel_road": {"name": "Road Tyre on Steel Rim", "slot": "wheel", "cls": "small", "price": 75, "mass": 14.0, "mesh": P + "wheel_road.glb", "bolts": 4, "wear": 0.4,
		"grip_road": 1.0, "grip_mud": 0.72, "grip_dirt": 0.85},
	"wheel_sport": {"name": "Sport Tyre on Alloy", "slot": "wheel", "cls": "small", "price": 180, "mass": 12.0, "mesh": P + "wheel_sport.glb", "bolts": 4, "wear": 0.7,
		"grip_road": 1.12, "grip_mud": 0.6, "grip_dirt": 0.8},
	"wheel_offroad": {"name": "Mud Tyre on Steel Rim", "slot": "wheel", "cls": "small", "price": 155, "mass": 18.0, "mesh": P + "wheel_offroad.glb", "bolts": 4, "wear": 0.5,
		"grip_road": 0.9, "grip_mud": 1.15, "grip_dirt": 1.05},
	"wheel_truck": {"name": "Truck Mud Tyre", "slot": "wheel", "cls": "big", "price": 320, "mass": 60.0, "mesh": P + "wheel_truck.glb", "bolts": 6, "wear": 0.3,
		"grip_road": 0.92, "grip_mud": 1.2, "grip_dirt": 1.05},
}

# Consumables & tools: pickable items that are not installed.
var ITEMS := {
	"jerrycan": {"name": "Jerry Can", "price": 40, "mass": 2.0, "mesh": P + "jerrycan.glb", "fluid": "fuel", "capacity": 20.0},
	"oil_bottle": {"name": "Motor Oil 4L", "price": 30, "mass": 0.5, "mesh": P + "oil_bottle.glb", "fluid": "oil", "capacity": 4.0},
	"coolant_bottle": {"name": "Coolant 5L", "price": 22, "mass": 0.5, "mesh": P + "coolant_bottle.glb", "fluid": "coolant", "capacity": 5.0},
	"repair_kit": {"name": "Repair Kit", "price": 60, "mass": 3.0, "mesh": "res://assets/props/crate.glb", "scale": 0.35, "repair": 35.0},
}

# Gear sets: index 0 = reverse, 1 = neutral, 2.. forward
const GEARS := {
	"car": {"ratios": [-3.53, 0.0, 3.67, 2.10, 1.36, 1.0], "final": 4.1, "low": 1.0},
	"car5": {"ratios": [-3.53, 0.0, 3.67, 2.10, 1.36, 1.0, 0.82], "final": 3.9, "low": 1.0},
	"offroad": {"ratios": [-4.12, 0.0, 4.12, 2.64, 1.58, 1.0], "final": 4.6, "low": 2.08},
	"heavy": {"ratios": [-6.4, 0.0, 6.4, 3.9, 2.45, 1.5, 1.0], "final": 5.6, "low": 2.2},
}

# drive: "rwd" / "fwd" / "awd".  can_awd: driver may toggle 4x4.  low: has low range.
# cargo: units of cargo, kinds: allowed cargo kinds.
var VEHICLES := {
	"kombi": {"name": "Kombi 2104", "price": 2900, "mass": 960.0, "cls": "small", "drive": "rwd", "gears": "car", "wheel": "wheel_road", "fuel_cap": 39.0,
		"cargo": 2, "kinds": ["parcel"], "steer": 34.0, "susp": 0.20, "spring": 1.0, "engine": "engine_i4"},
	"klasyka": {"name": "Klasyka 2106", "price": 3200, "mass": 1000.0, "cls": "small", "drive": "rwd", "gears": "car", "wheel": "wheel_road", "fuel_cap": 39.0,
		"cargo": 1, "kinds": ["parcel"], "steer": 34.0, "susp": 0.20, "spring": 1.0, "engine": "engine_i4"},
	"hatch": {"name": "Hatch GT", "price": 3600, "mass": 860.0, "cls": "small", "drive": "fwd", "gears": "car5", "wheel": "wheel_road", "fuel_cap": 45.0,
		"cargo": 1, "kinds": ["parcel"], "steer": 36.0, "susp": 0.17, "spring": 1.05, "engine": "engine_i4_sport"},
	"sedan": {"name": "Nordic 740 Sedan", "price": 4300, "mass": 1250.0, "cls": "small", "drive": "rwd", "gears": "car5", "wheel": "wheel_road", "fuel_cap": 60.0,
		"cargo": 2, "kinds": ["parcel"], "steer": 33.0, "susp": 0.19, "spring": 1.0, "engine": "engine_i4_sport"},
	"cruiser": {"name": "Cruiser Brougham", "price": 3900, "mass": 1550.0, "cls": "small", "drive": "rwd", "gears": "car", "wheel": "wheel_road", "fuel_cap": 70.0,
		"cargo": 2, "kinds": ["parcel"], "steer": 32.0, "susp": 0.22, "spring": 0.85, "engine": "engine_i4_sport"},
	"bobyk": {"name": "Bobyk 469 4x4", "price": 5200, "mass": 1550.0, "cls": "small", "drive": "rwd", "can_awd": true, "low": true, "gears": "offroad", "wheel": "wheel_offroad", "fuel_cap": 78.0,
		"cargo": 2, "kinds": ["parcel", "crate"], "steer": 33.0, "susp": 0.28, "spring": 1.1, "engine": "engine_i4"},
	"bukhanka": {"name": "Bukhanka 452 4x4 Van", "price": 6100, "mass": 1750.0, "cls": "small", "drive": "rwd", "can_awd": true, "low": true, "gears": "offroad", "wheel": "wheel_offroad", "fuel_cap": 86.0,
		"cargo": 5, "kinds": ["parcel", "crate"], "steer": 33.0, "susp": 0.28, "spring": 1.15, "engine": "engine_i4"},
	"minivan": {"name": "Astra Van", "price": 4800, "mass": 1700.0, "cls": "small", "drive": "rwd", "gears": "car", "wheel": "wheel_road", "fuel_cap": 70.0,
		"cargo": 4, "kinds": ["parcel", "crate"], "steer": 33.0, "susp": 0.2, "spring": 1.15, "engine": "engine_i4_sport"},
	"stepvan": {"name": "Step Van P30", "price": 9800, "mass": 3200.0, "cls": "big", "drive": "rwd", "gears": "heavy", "wheel": "wheel_truck", "fuel_cap": 120.0,
		"cargo": 8, "kinds": ["parcel", "crate"], "steer": 34.0, "susp": 0.22, "spring": 1.35, "engine": "engine_diesel"},
	"pickup": {"name": "Ranger Pickup 4x4", "price": 7400, "mass": 1800.0, "cls": "small", "drive": "rwd", "can_awd": true, "low": true, "gears": "offroad", "wheel": "wheel_offroad", "fuel_cap": 80.0,
		"cargo": 4, "kinds": ["parcel", "crate", "bulk"], "steer": 34.0, "susp": 0.25, "spring": 1.2, "engine": "engine_i4_sport"},
	"suv": {"name": "Trekker SUV 4x4", "price": 8200, "mass": 1900.0, "cls": "small", "drive": "awd", "low": true, "gears": "offroad", "wheel": "wheel_offroad", "fuel_cap": 85.0,
		"cargo": 2, "kinds": ["parcel", "crate"], "steer": 34.0, "susp": 0.26, "spring": 1.2, "engine": "engine_i4_sport"},
	"truck": {"name": "KrAZ-ish 6x6 Timber Truck", "price": 24000, "mass": 7800.0, "cls": "big", "drive": "awd", "can_awd": true, "low": true, "gears": "heavy", "wheel": "wheel_truck", "fuel_cap": 250.0,
		"cargo": 12, "kinds": ["parcel", "crate", "bulk", "logs"], "steer": 30.0, "susp": 0.32, "spring": 1.6, "engine": "engine_diesel"},
}

# Slot layout shared by every vehicle. Positions are resolved at runtime from the vehicle meta.
const SLOTS := ["engine", "gearbox", "radiator", "battery", "ignition_coil", "fuel_tank", "exhaust",
	"carburetor", "air_filter", "spark_plugs", "alternator", "starter"]
# Which slots sit on the engine block (removed together with it).
const ENGINE_CHILD_SLOTS := ["carburetor", "spark_plugs", "alternator", "starter"]
const SLOT_PARENT := {"carburetor": "engine", "spark_plugs": "engine", "alternator": "engine", "starter": "engine", "air_filter": "carburetor"}
const REQUIRED_FOR_START := ["engine", "gearbox", "battery", "ignition_coil", "fuel_tank", "carburetor", "spark_plugs", "starter"]

var GOODS := {
	"parcel": {"name": "Parcels", "kind": "parcel", "price": 0, "mass": 30.0, "mesh": "res://assets/props/crate.glb"},
	"logs": {"name": "Logs", "kind": "logs", "price": 48, "mass": 450.0, "mesh": "res://assets/props/log.glb"},
	"planks": {"name": "Planks", "kind": "bulk", "price": 95, "mass": 250.0, "mesh": "res://assets/props/planks.glb"},
	"furniture": {"name": "Furniture", "kind": "crate", "price": 240, "mass": 120.0, "mesh": "res://assets/props/crate.glb"},
	"wheat": {"name": "Wheat", "kind": "bulk", "price": 38, "mass": 300.0, "mesh": "res://assets/props/sacks.glb"},
	"flour": {"name": "Flour", "kind": "crate", "price": 72, "mass": 200.0, "mesh": "res://assets/props/sacks.glb"},
	"bread": {"name": "Bread", "kind": "crate", "price": 115, "mass": 80.0, "mesh": "res://assets/props/crate.glb"},
	"sunflower": {"name": "Sunflower Seeds", "kind": "bulk", "price": 44, "mass": 260.0, "mesh": "res://assets/props/sacks.glb"},
	"sunflower_oil": {"name": "Sunflower Oil", "kind": "crate", "price": 150, "mass": 180.0, "mesh": "res://assets/props/barrel.glb"},
	"gravel": {"name": "Gravel", "kind": "bulk", "price": 22, "mass": 500.0, "mesh": "res://assets/props/sacks.glb"},
}

# rate: production cycles per game hour.  inputs/outputs per cycle.
var INDUSTRIES := {
	"lumber_camp": {"name": "Lumber Camp", "price": 16000, "upkeep": 160, "rate": 2.0, "in": {}, "out": {"logs": 3}},
	"sawmill": {"name": "Sawmill", "price": 22000, "upkeep": 220, "rate": 2.0, "in": {"logs": 2}, "out": {"planks": 2}},
	"furniture_factory": {"name": "Furniture Factory", "price": 30000, "upkeep": 300, "rate": 1.5, "in": {"planks": 2}, "out": {"furniture": 1}},
	"grain_farm": {"name": "Zoria Grain Farm", "price": 14000, "upkeep": 140, "rate": 2.0, "in": {}, "out": {"wheat": 3}},
	"flour_mill": {"name": "Flour Mill", "price": 20000, "upkeep": 200, "rate": 2.0, "in": {"wheat": 2}, "out": {"flour": 1}},
	"bakery": {"name": "Bakery", "price": 18000, "upkeep": 180, "rate": 2.0, "in": {"flour": 1}, "out": {"bread": 2}},
	"sunflower_farm": {"name": "Khutir Sunflower Farm", "price": 12000, "upkeep": 120, "rate": 2.0, "in": {}, "out": {"sunflower": 3}},
	"oil_press": {"name": "Oil Press", "price": 19000, "upkeep": 190, "rate": 2.0, "in": {"sunflower": 3}, "out": {"sunflower_oil": 1}},
	"quarry": {"name": "Gravel Quarry", "price": 11000, "upkeep": 130, "rate": 2.0, "in": {}, "out": {"gravel": 4}},
}

# Places that buy goods (prices react to stock).
var CONSUMERS := {
	"town_market": {"name": "Stepove Market", "buys": ["bread", "sunflower_oil", "furniture", "flour"], "use_rate": 2.0},
	"warehouse": {"name": "Stepove Warehouse", "buys": ["planks", "gravel", "wheat", "sunflower", "logs"], "use_rate": 3.0},
	"shop_village": {"name": "Sonyachne Shop", "buys": ["bread", "sunflower_oil", "flour"], "use_rate": 1.0},
}


func part(id: String) -> Dictionary:
	if PARTS.has(id):
		return PARTS[id]
	if ITEMS.has(id):
		return ITEMS[id]
	return {}


func is_part(id: String) -> bool:
	return PARTS.has(id)


func vehicle_meta(vid: String) -> Dictionary:
	var f := FileAccess.open("res://assets/vehicles/%s/meta.json" % vid, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())


func fits(part_id: String, slot: String, vehicle_cls: String) -> bool:
	if not PARTS.has(part_id):
		return false
	var p: Dictionary = PARTS[part_id]
	if p.slot != slot and not (slot.begins_with("wheel") and p.slot == "wheel"):
		return false
	if p.has("cls") and p.cls != vehicle_cls:
		return false
	return true


func slot_display(slot: String) -> String:
	if slot.begins_with("wheel"):
		return "Wheel"
	return slot.capitalize()
