class_name HaveItemStep
extends MissionStep
## Have (pick up / loot) [member count] of mission item [member item_id] (Missions.items). Pair with a
## [MissionPickup] or KillStep.drop_item_id. [member waypoint_tag] points the HUD at the pickup.

@export var item_id: StringName
@export var count := 1
## Remove the items when the step completes (hand over the package).
@export var consume := false
@export var waypoint_tag: StringName


func _begin() -> void:
	_check()


func _tick(_delta: float) -> void:
	_check()


func _check() -> void:
	if state == State.ACTIVE and Missions.items.has(item_id, count):
		if consume:
			Missions.items.remove(item_id, count)
		complete()


func _progress() -> String:
	return "%d/%d" % [mini(Missions.items.count_of(item_id), count), count] if count > 1 else ""


func _waypoint() -> Variant:
	if waypoint_tag != &"":
		return Missions.locate(waypoint_tag)
	for pickup in Missions.tagged(MissionPickup.tag_for(item_id)):
		if pickup is Node3D:
			return (pickup as Node3D).global_position
	return null
