class_name UnlockMissionEffect
extends Effect
## Unlocks mission [member mission_id] so its start marker appears.

@export var mission_id: StringName


func _apply(_ctx: ActionContext) -> void:
	Missions.unlock_mission(mission_id)
