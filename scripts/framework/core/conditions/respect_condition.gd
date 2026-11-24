class_name RespectCondition
extends Condition
## Player has at least [member amount] respect.

@export var amount := 0


func _evaluate(_ctx: ActionContext) -> bool:
	return GameState.respect >= amount


func _reason(_ctx: ActionContext) -> String:
	return "Need %d respect" % amount
