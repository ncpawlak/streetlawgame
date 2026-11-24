class_name FlagCondition
extends Condition
## A GameState flag equals [member value] (missing flags read as false).

@export var flag: StringName
@export var value: Variant = true


func _evaluate(_ctx: ActionContext) -> bool:
	return GameState.get_flag(flag, false) == value


func _reason(_ctx: ActionContext) -> String:
	return "Locked"
