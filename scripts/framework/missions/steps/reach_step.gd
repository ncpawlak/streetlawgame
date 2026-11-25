class_name ReachStep
extends MissionStep
## Go to a place: within [member radius] of [member target] (zone id, mission tag or run var) or of
## [member position] when no target is set.

enum Mode { ANY, ON_FOOT, IN_VEHICLE }

@export var target: StringName
@export var position := Vector3.ZERO
@export var radius := 8.0
@export var mode := Mode.ANY


func _tick(_delta: float) -> void:
	var player := GameState.player
	var at: Variant = _waypoint()
	if player == null or not at is Vector3:
		return
	if mode == Mode.ON_FOOT and not player.is_on_foot():
		return
	if mode == Mode.IN_VEHICLE and player.is_on_foot():
		return
	var from := player.get_focus_position()
	var goal: Vector3 = at
	if Vector2(from.x - goal.x, from.z - goal.z).length() <= radius and absf(from.y - goal.y) < radius + 6.0:
		complete()


func _waypoint() -> Variant:
	return Missions.locate(target) if target != &"" else position
