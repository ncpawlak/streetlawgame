class_name StealVehicleStep
extends VehicleStep
## Steal (get into) [member count] matching vehicles. The latest one is stored in run var
## [member store_as] and tagged [member tag_as] so later steps (deliver, park) can refer to it.

@export var count := 1
@export var store_as: StringName = &"vehicle"
@export var tag_as: StringName

var _stolen: Array[Vehicle] = []


func _begin() -> void:
	_stolen.clear()
	var driven := driven_vehicle()
	if driven != null:
		_take(driven)


func _handle(event: Dictionary) -> void:
	if event["type"] == &"vehicle_entered" and event.get("vehicle") is Vehicle:
		var vehicle: Vehicle = event["vehicle"]
		if matches(vehicle):
			_take(vehicle)


func _take(vehicle: Vehicle) -> void:
	if _stolen.has(vehicle) or state != State.ACTIVE:
		return
	_stolen.append(vehicle)
	vehicle.set_meta(DeliverVehicleStep.META_START_HEALTH, vehicle.health)
	if store_as != &"":
		run.ctx.vars[store_as] = vehicle
	if tag_as != &"":
		Missions.tag(vehicle, tag_as)
	notify_changed()
	if _stolen.size() >= count:
		complete()


func _progress() -> String:
	return "%d/%d" % [_stolen.size(), count] if count > 1 else ""


func _waypoint() -> Variant:
	var player := GameState.player
	var from := player.get_focus_position() if player != null else Vector3.ZERO
	var best: Variant = null
	var best_distance := INF
	if vehicle_tag != &"":
		for node in Missions.tagged(vehicle_tag):
			if node is Vehicle and matches(node) and not _stolen.has(node):
				var distance := (node as Vehicle).global_position.distance_to(from)
				if distance < best_distance:
					best_distance = distance
					best = (node as Vehicle).global_position
	return best
