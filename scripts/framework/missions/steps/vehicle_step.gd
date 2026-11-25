class_name VehicleStep
extends MissionStep
## Base for steps about a vehicle. Which vehicles count: those tagged [member vehicle_tag], the one
## held in run var [member vehicle_var] (set by StealVehicleStep), or any vehicle when both are empty.

@export var vehicle_tag: StringName
@export var vehicle_var: StringName
## Below this speed (m/s) a vehicle counts as stopped.
@export var stop_speed := 1.5


func matches(vehicle: Vehicle) -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_wrecked():
		return false
	if vehicle_tag == &"" and vehicle_var == &"":
		return true
	if vehicle_tag != &"" and Missions.has_tag(vehicle, vehicle_tag):
		return true
	return vehicle_var != &"" and run != null and run.ctx.vars.get(vehicle_var) == vehicle


## The player's car if it counts, else null.
func driven_vehicle() -> Vehicle:
	var player := GameState.player
	if player == null or player.current_vehicle == null:
		return null
	return player.current_vehicle if matches(player.current_vehicle) else null


## Every vehicle in the scene that counts.
func candidate_vehicles() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	if run == null or not Missions.is_inside_tree():
		return out
	if vehicle_tag != &"":
		for node in Missions.tagged(vehicle_tag):
			if node is Vehicle and matches(node):
				out.append(node)
	if vehicle_var != &"":
		var held: Variant = run.ctx.vars.get(vehicle_var)
		if held is Vehicle and is_instance_valid(held) and not out.has(held) and matches(held):
			out.append(held)
	if vehicle_tag == &"" and vehicle_var == &"":
		var driven := driven_vehicle()
		if driven != null:
			out.append(driven)
	return out


static func is_stopped(vehicle: Vehicle, threshold: float) -> bool:
	return vehicle.linear_velocity.length() <= threshold
