class_name VehicleClass
extends Resource
## A kind of car (junker, sedan, muscle, SUV, sports, luxury). Each class sets how hard the car is to
## break into, how likely it is to carry a tracker, what a chop shop pays for it, its health and its
## handling. The game's cars all come from this one data table:
##     var car := Vehicle.new()
##     car.vehicle_class_id = &"muscle"
## Changing a row changes every car of that class. Leave the id empty for the stock Sedan build.
## Planned: truck (higher centre of mass, bouncier suspension) and off-road truck (heavier, more grip).

## Lock difficulty and tracker chance are relative to a sedan (1.0) and run 0..1. Handling keys are
## [constant VehicleTuning.PARAMS]; any key left out keeps the stock value. The stock (sedan) handling
## was play-tuned; the other rows are that baseline scaled by their original offsets, still unbalanced.
const TABLE := {
	&"junker": {
		"display_name": "Junker", "color": Color(0.45, 0.38, 0.3), "lock_difficulty": 0.7,
		"tracker_chance": 0.0, "chop_value": 600, "max_health": 220.0,
		"handling": {&"mass": 1170.0, &"center_of_mass_y": 0.3, &"suspension_stiffness": 55.0,
			&"damping_compression": 1.1, &"damping_relaxation": 1.7, &"suspension_travel": 0.35,
			&"roll_influence": 0.15, &"friction_slip": 4.1, &"engine_force": 2200.0, &"max_steer": 0.5,
			&"steer_speed": 2.0},
	},
	&"sedan": {
		"display_name": "Sedan", "color": Color(0.55, 0.6, 0.65), "lock_difficulty": 1.0,
		"tracker_chance": 0.1, "chop_value": 1200, "max_health": 300.0,
		"handling": {},
	},
	&"muscle": {
		"display_name": "Muscle car", "color": Color(0.9, 0.55, 0.1), "lock_difficulty": 1.1,
		"tracker_chance": 0.35, "chop_value": 2800, "max_health": 340.0,
		"handling": {&"mass": 1820.0, &"suspension_stiffness": 82.0, &"damping_compression": 1.7,
			&"damping_relaxation": 2.45, &"roll_influence": 0.12, &"friction_slip": 4.2,
			&"engine_force": 5200.0, &"max_steer": 0.5, &"steer_speed": 2.3},
	},
	&"suv": {
		"display_name": "SUV", "color": Color(0.15, 0.3, 0.2), "lock_difficulty": 1.15,
		"tracker_chance": 0.25, "chop_value": 2200, "max_health": 420.0,
		"handling": {&"mass": 2600.0, &"center_of_mass_y": 0.45, &"suspension_stiffness": 91.0,
			&"damping_compression": 1.85, &"damping_relaxation": 2.7, &"suspension_travel": 0.4,
			&"roll_influence": 0.2, &"engine_force": 4800.0, &"max_steer": 0.5, &"steer_speed": 2.0},
	},
	&"sports": {
		"display_name": "Sports coupe", "color": Color(0.8, 0.1, 0.1), "lock_difficulty": 1.3,
		"tracker_chance": 1.0, "chop_value": 3500, "max_health": 260.0,
		"handling": {&"mass": 1500.0, &"center_of_mass_y": 0.05, &"suspension_stiffness": 146.0,
			&"damping_compression": 2.6, &"damping_relaxation": 3.9, &"suspension_travel": 0.2,
			&"roll_influence": 0.05, &"friction_slip": 6.5, &"engine_force": 5500.0, &"max_steer": 0.6,
			&"steer_speed": 3.2},
	},
	&"luxury": {
		"display_name": "Luxury sedan", "color": Color(0.08, 0.08, 0.1), "lock_difficulty": 1.45,
		"tracker_chance": 1.0, "chop_value": 4500, "max_health": 360.0,
		"handling": {&"mass": 2340.0, &"suspension_stiffness": 100.0, &"damping_compression": 2.25,
			&"damping_relaxation": 3.4, &"roll_influence": 0.08, &"friction_slip": 5.55,
			&"engine_force": 4800.0, &"steer_speed": 2.4},
	},
}

static var _cache := {}

@export var id: StringName
@export var display_name := ""
@export var color := Color.GRAY
## Multiplies a lock / hotwire / struggle minigame's difficulty.
@export var lock_difficulty := 1.0
## Chance (0..1) the car is fitted with a tracker.
@export_range(0.0, 1.0) var tracker_chance := 0.0
## What a chop shop pays for one in perfect condition.
@export var chop_value := 1000
@export var max_health := 300.0
var handling: VehicleTuning


## The class for [param class_id], or null if there's no such row. Classes are shared; don't edit the
## returned resource unless you mean to change every car of that class.
static func find(class_id: StringName) -> VehicleClass:
	if _cache.has(class_id):
		return _cache[class_id]
	if not TABLE.has(class_id):
		return null
	var row: Dictionary = TABLE[class_id]
	var vehicle_class := VehicleClass.new()
	vehicle_class.id = class_id
	vehicle_class.display_name = row["display_name"]
	vehicle_class.color = row["color"]
	vehicle_class.lock_difficulty = row["lock_difficulty"]
	vehicle_class.tracker_chance = row["tracker_chance"]
	vehicle_class.chop_value = row["chop_value"]
	vehicle_class.max_health = row["max_health"]
	vehicle_class.handling = VehicleTuning.from_dict(row["handling"])
	_cache[class_id] = vehicle_class
	return vehicle_class


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: StringName in TABLE:
		result.append(key)
	return result


## Rolls whether a newly spawned car of this class has a tracker fitted.
func roll_tracker(rng: RandomNumberGenerator = null) -> bool:
	if tracker_chance >= 1.0:
		return true
	if tracker_chance <= 0.0:
		return false
	return (rng.randf() if rng != null else randf()) < tracker_chance


## Gives [param vehicle] this class's health and handling (call after its wheels exist).
func apply_to(vehicle: Vehicle) -> void:
	vehicle.max_health = max_health
	vehicle.health = max_health
	handling.apply(vehicle)
