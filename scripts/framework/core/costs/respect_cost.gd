class_name RespectCost
extends Cost
## Spends player respect.

@export var amount := 0


func _can_pay(_ctx: ActionContext) -> bool:
	return GameState.respect >= amount


func _pay(_ctx: ActionContext) -> void:
	GameState.add_respect(-amount)


func _describe(_ctx: ActionContext) -> String:
	return "%d respect" % amount
