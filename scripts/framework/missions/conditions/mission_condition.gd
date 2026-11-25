class_name MissionCondition
extends Condition
## True when mission [member mission_id] is in [member state]: completed, active, unlocked or available.

enum Check { COMPLETED, ACTIVE, UNLOCKED, AVAILABLE }

@export var mission_id: StringName
@export var state := Check.COMPLETED


func _evaluate(_ctx: ActionContext) -> bool:
	match state:
		Check.ACTIVE:
			return Missions.is_active(mission_id)
		Check.UNLOCKED:
			return Missions.is_unlocked(mission_id)
		Check.AVAILABLE:
			return Missions.can_start(mission_id)
	return Missions.is_completed(mission_id)


func _reason(_ctx: ActionContext) -> String:
	var mission := Missions.get_mission(mission_id)
	var title := mission.label() if mission != null else String(mission_id)
	match state:
		Check.ACTIVE:
			return "Requires mission %s in progress" % title
		Check.UNLOCKED:
			return "Locked"
		Check.AVAILABLE:
			return Missions.start_block_reason(mission_id)
	return "Complete %s first" % title
