class_name LeadCondition
extends Condition
## True when the journal has lead [member lead_id] (optionally only once it's done).

@export var lead_id: StringName
@export var require_done := false


func _evaluate(_ctx: ActionContext) -> bool:
	if not Missions.journal.has_lead(lead_id):
		return false
	return not require_done or Missions.journal.get_lead(lead_id)["state"] == MissionJournal.DONE


func _reason(_ctx: ActionContext) -> String:
	return "Need a lead"
