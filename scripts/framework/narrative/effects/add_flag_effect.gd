class_name AddFlagEffect
extends Effect
## Adds [member amount] to a numeric GameState flag (missing = 0). Counters such as leads found.

@export var flag: StringName
@export var amount := 1


func _apply(_ctx: ActionContext) -> void:
	GameState.set_flag(flag, int(GameState.get_flag(flag, 0)) + amount)
