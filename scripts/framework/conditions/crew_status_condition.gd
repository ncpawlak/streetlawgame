class_name CrewStatusCondition
extends Condition
## True when the crew member in ctx.vars.crew_id has the given status (default: active).

@export var status := CrewMemberData.Status.ACTIVE


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	if model == null:
		return false
	var member := model.crew(StringName(str(ctx.vars.get("crew_id", ""))))
	return member != null and member.status == status


func _reason(_ctx: ActionContext) -> String:
	return "Crew member is %s" % String(CrewMemberData.Status.keys()[status]).to_lower()
