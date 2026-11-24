class_name AnyCondition
extends Condition
## Met when at least one child condition is met (or the list is empty).

@export var conditions: Array[Condition] = []


func _evaluate(ctx: ActionContext) -> bool:
	if conditions.is_empty():
		return true
	for condition in conditions:
		if condition != null and condition.is_met(ctx):
			return true
	return false


func _reason(ctx: ActionContext) -> String:
	return Condition.first_reason(conditions, ctx)
