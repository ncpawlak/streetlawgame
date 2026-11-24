class_name LocationStatusCondition
extends Condition
## Met when the location's status is one of [member statuses].

@export var statuses: Array[StringName] = [&"open"]


func _evaluate(ctx: ActionContext) -> bool:
	var location := ctx.location as Location
	return location != null and statuses.has(location.state.status)


func _reason(ctx: ActionContext) -> String:
	var location := ctx.location as Location
	if location == null:
		return "Not here"
	match location.state.status:
		&"robbed":
			return "Already hit recently"
		&"taken_out":
			return "Nothing left here"
		&"closed":
			return "Closed"
	return "Not now"
