class_name VehicleTuning
extends RefCounted
## A car's handling numbers. The field defaults are the stock [Vehicle] build. [VehicleClass] keeps
## one per class, apply() pushes the values onto any Vehicle's body and wheels, and the carjack
## driver's F7 panel edits them live. to_text() prints the same keys the class table uses, so a line
## copied from the panel can be pasted straight into [constant VehicleClass.TABLE].

## [property, label, min, max, step]
const PARAMS := [
	[&"mass", "Mass (kg)", 300.0, 4000.0, 50.0],
	[&"center_of_mass_y", "Centre of mass height (m)", -0.6, 1.2, 0.05],
	[&"suspension_stiffness", "Suspension stiffness", 10.0, 200.0, 1.0],
	[&"damping_compression", "Damping (compression)", 0.1, 5.0, 0.05],
	[&"damping_relaxation", "Damping (rebound)", 0.1, 5.0, 0.05],
	[&"suspension_travel", "Suspension travel (m)", 0.05, 0.6, 0.01],
	[&"roll_influence", "Roll influence (body lean)", 0.0, 1.0, 0.01],
	[&"friction_slip", "Tyre grip (friction slip)", 0.5, 10.0, 0.1],
	[&"engine_force", "Engine force", 500.0, 12000.0, 100.0],
	[&"max_steer", "Max steer (rad)", 0.2, 1.0, 0.01],
	[&"steer_speed", "Steer speed", 0.5, 8.0, 0.1],
]

var mass := 1300.0
var center_of_mass_y := 0.2
var suspension_stiffness := 73.0
var damping_compression := 1.55
var damping_relaxation := 2.15
var suspension_travel := 0.3
var roll_influence := 0.1
var friction_slip := 4.9
var engine_force := 3000.0
var max_steer := 0.55
var steer_speed := 2.5


static func from_vehicle(vehicle: Vehicle) -> VehicleTuning:
	var tuning := VehicleTuning.new()
	tuning.mass = vehicle.mass
	tuning.center_of_mass_y = vehicle.center_of_mass.y
	tuning.engine_force = vehicle.max_engine_force
	tuning.max_steer = vehicle.max_steer
	tuning.steer_speed = vehicle.steer_speed
	var wheels := wheels_of(vehicle)
	if not wheels.is_empty():
		var wheel := wheels[0]
		tuning.suspension_stiffness = wheel.suspension_stiffness
		tuning.damping_compression = wheel.damping_compression
		tuning.damping_relaxation = wheel.damping_relaxation
		tuning.suspension_travel = wheel.suspension_travel
		tuning.roll_influence = wheel.wheel_roll_influence
		tuning.friction_slip = wheel.wheel_friction_slip
	return tuning


## Stock handling with [param overrides] (PARAMS keys) on top.
static func from_dict(overrides: Dictionary) -> VehicleTuning:
	var tuning := VehicleTuning.new()
	for key: StringName in overrides:
		assert(tuning.get(key) != null, "Unknown handling key %s" % key)
		tuning.set(key, float(overrides[key]))
	return tuning


static func wheels_of(vehicle: Vehicle) -> Array[VehicleWheel3D]:
	var wheels: Array[VehicleWheel3D] = []
	for child in vehicle.get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
	return wheels


func apply(vehicle: Vehicle) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	vehicle.mass = mass
	vehicle.center_of_mass = Vector3(0.0, center_of_mass_y, 0.0)
	vehicle.max_engine_force = engine_force
	vehicle.max_steer = max_steer
	vehicle.steer_speed = steer_speed
	for wheel in wheels_of(vehicle):
		wheel.suspension_stiffness = suspension_stiffness
		wheel.damping_compression = damping_compression
		wheel.damping_relaxation = damping_relaxation
		wheel.suspension_travel = suspension_travel
		wheel.wheel_roll_influence = roll_influence
		wheel.wheel_friction_slip = friction_slip
	vehicle.sleeping = false


func duplicate_tuning() -> VehicleTuning:
	var copy := VehicleTuning.new()
	for spec: Array in PARAMS:
		copy.set(spec[0], get(spec[0]))
	return copy


static func format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(value))
	return "%.2f" % value


func to_text() -> String:
	var parts: PackedStringArray = []
	for spec: Array in PARAMS:
		parts.append("%s=%s" % [spec[0], format_value(get(spec[0]), spec[4])])
	return ", ".join(parts)
