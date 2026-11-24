class_name AllCondition
extends Condition
## Met when every child condition is met.

@export var conditions: Array[Condition] = []


func _evaluate(ctx: ActionContext) -> bool:
	return Condition.all_met(conditions, ctx)


func _reason(ctx: ActionContext) -> String:
	return Condition.first_reason(conditions, ctx)
