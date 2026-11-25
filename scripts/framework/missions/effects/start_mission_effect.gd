class_name StartMissionEffect
extends Effect
## Starts mission [member mission_id] (ignoring unlock/conditions with [member force]).

@export var mission_id: StringName
@export var force := false


func _apply(_ctx: ActionContext) -> void:
	Missions.start_mission(mission_id, force)
