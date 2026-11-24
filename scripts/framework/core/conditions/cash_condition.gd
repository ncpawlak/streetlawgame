class_name CashCondition
extends Condition
## Player has at least [member amount] cash (without spending it; use CashCost to spend).

@export var amount := 0


func _evaluate(_ctx: ActionContext) -> bool:
	return GameState.cash >= amount


func _reason(_ctx: ActionContext) -> String:
	return "Need $%d" % amount
