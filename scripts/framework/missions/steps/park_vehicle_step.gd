class_name ParkVehicleStep
extends VehicleStep
## Park a matching vehicle inside [TriggerZone] [member zone_id]: stopped for [member hold_time]
## seconds, optionally with zero heat ([member require_zero_heat]) and the player out of the car
## ([member require_exit]). "Park in Pedro's driveway with zero heat."

@export var zone_id: StringName
@export var require_zero_heat := true
@export var require_exit := false
@export var hold_time := 1.0

var _held := 0.0
var _blocked_by_heat := false


func _begin() -> void:
	_held = 0.0
	_blocked_by_heat = false


func _tick(delta: float) -> void:
	var zone := Missions.find_zone(zone_id)
	var parked := false
	var in_zone := false
	if zone != null:
		for vehicle in _vehicles():
			if not zone.contains_point(vehicle.global_position):
				continue
			in_zone = true
			if is_stopped(vehicle, stop_speed) and (not require_exit or vehicle.driver == null):
				parked = true
				break
	var heat_ok := not require_zero_heat or not Missions.heat.is_hot()
	var blocked := in_zone and not heat_ok
	if blocked != _blocked_by_heat:
		_blocked_by_heat = blocked
		notify_changed()
	if parked and heat_ok:
		_held += delta
		if _held >= hold_time:
			complete()
	else:
		_held = 0.0


func _vehicles() -> Array[Vehicle]:
	var out := candidate_vehicles()
	if require_exit and vehicle_tag == &"" and vehicle_var == &"":
		out.clear()
		for node in Missions.get_tree().get_nodes_in_group("vehicles"):
			if node is Vehicle and matches(node):
				out.append(node)
	return out


func _progress() -> String:
	return "lose the heat first" if _blocked_by_heat else ""


func _waypoint() -> Variant:
	return Missions.locate(zone_id)
