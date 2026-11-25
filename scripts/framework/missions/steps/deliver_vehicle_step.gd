class_name DeliverVehicleStep
extends VehicleStep
## Deliver [member count] matching vehicles into [TriggerZone] [member zone_id], stopped (and empty
## when [member require_exit]). Each delivery is "clean" when the heat never went above
## [member clean_max_heat] while the player drove it during this step and its damage (since it was
## stolen, or since this step started) is at most [member clean_max_damage] of max health.
## Clean deliveries apply [member clean_rewards] on the spot and are listed as run bonuses.

const META_START_HEALTH := &"mission_start_health"

@export var zone_id: StringName
@export var count := 1
@export var require_exit := false
## Remove delivered vehicles from the world (handed over to the garage).
@export var remove_on_delivery := true
@export var track_clean := true
@export var clean_max_heat := 0.0
@export_range(0.0, 1.0) var clean_max_damage := 0.25
@export var clean_rewards: Array[Effect] = []
@export var clean_label := "Clean delivery"
@export var clean_message := "Clean delivery: no heat, barely a scratch."

## instance_id -> {vehicle, start_health, dirty}
var _tracked: Dictionary = {}
var _delivered := 0
var _clean := 0


func _begin() -> void:
	_tracked.clear()
	_delivered = 0
	_clean = 0


func _tick(_delta: float) -> void:
	var driven := driven_vehicle()
	if driven != null:
		_track(driven)
		if Missions.heat.level() > clean_max_heat:
			_tracked[driven.get_instance_id()]["dirty"] = true
	for vehicle in candidate_vehicles():
		_track(vehicle)
	var zone := Missions.find_zone(zone_id)
	if zone == null:
		return
	for key in _tracked.keys():
		var entry: Dictionary = _tracked[key]
		var vehicle: Vehicle = entry["vehicle"]
		if not is_instance_valid(vehicle) or entry.get("delivered", false):
			continue
		if not zone.contains_point(vehicle.global_position) or not is_stopped(vehicle, stop_speed):
			continue
		if require_exit and vehicle.driver != null:
			continue
		_deliver(entry)
		if state != State.ACTIVE:
			return


## Damage taken (0-1 of max health) by a tracked vehicle; -1 when unknown.
func damage_of(vehicle: Vehicle) -> float:
	var entry: Dictionary = _tracked.get(vehicle.get_instance_id(), {})
	if entry.is_empty():
		return -1.0
	return maxf(0.0, float(entry["start_health"]) - vehicle.health) / maxf(vehicle.max_health, 1.0)


func is_clean(vehicle: Vehicle) -> bool:
	var entry: Dictionary = _tracked.get(vehicle.get_instance_id(), {})
	return not entry.is_empty() and not entry["dirty"] and damage_of(vehicle) <= clean_max_damage


func clean_count() -> int:
	return _clean


func _track(vehicle: Vehicle) -> void:
	var key := vehicle.get_instance_id()
	if _tracked.has(key):
		return
	var start_health: float = vehicle.get_meta(META_START_HEALTH, vehicle.health)
	_tracked[key] = {"vehicle": vehicle, "start_health": start_health, "dirty": Missions.heat.level() > clean_max_heat}


func _deliver(entry: Dictionary) -> void:
	var vehicle: Vehicle = entry["vehicle"]
	entry["delivered"] = true
	_delivered += 1
	if track_clean:
		var clean := is_clean(vehicle)
		var label := clean_label if count <= 1 else "%s %d" % [clean_label, _delivered]
		run.add_bonus(StringName("%s_clean_%d" % [id, _delivered]), label, clean)
		if clean:
			_clean += 1
			run.ctx.vars["clean_deliveries"] = _clean
			Effect.apply_all(clean_rewards, run.ctx)
			EventBus.notify.emit(clean_message)
		else:
			EventBus.notify.emit("Delivered, but it wasn't clean.")
	Missions.post_event(&"vehicle_delivered", {"vehicle": vehicle, "zone_id": zone_id, "clean": track_clean and is_clean(vehicle)})
	if remove_on_delivery:
		if vehicle.driver != null:
			vehicle.exit()
		vehicle.queue_free()
	notify_changed()
	if _delivered >= count:
		complete()


func _progress() -> String:
	return "%d/%d" % [_delivered, count] if count > 1 else ""


func _waypoint() -> Variant:
	return Missions.locate(zone_id)
