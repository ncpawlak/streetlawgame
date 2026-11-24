class_name CashCost
extends Cost
## Spends player cash.

@export var amount := 0


func _can_pay(_ctx: ActionContext) -> bool:
	return GameState.cash >= amount


func _pay(_ctx: ActionContext) -> void:
	GameState.spend_cash(amount)


func _describe(_ctx: ActionContext) -> String:
	return "$%d" % amount
