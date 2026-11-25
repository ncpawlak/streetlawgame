class_name EnterZoneStep
extends MissionStep
## Get into a [TriggerZone] (by zone_id) while its own filters (on foot / in vehicle / specific
## vehicle / stopped / conditions) hold.

@export var zone_id: StringName


func _tick(_delta: float) -> void:
	var zone := Missions.find_zone(zone_id)
	if zone != null and zone.is_satisfied():
		complete()


func _waypoint() -> Variant:
	return Missions.locate(zone_id)
