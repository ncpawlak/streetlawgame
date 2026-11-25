class_name FlagAtLeastCondition
extends Condition
## A numeric GameState flag is at least [member amount] (missing = 0), e.g. leads >= 3.

@export var flag: StringName
@export var amount := 1


func _evaluate(_ctx: ActionContext) -> bool:
	return int(GameState.get_flag(flag, 0)) >= amount


func _reason(_ctx: ActionContext) -> String:
	return "Not yet"
