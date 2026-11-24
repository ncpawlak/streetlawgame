class_name SetFlagEffect
extends Effect
## Sets a GameState flag (persisted with the save).

@export var flag: StringName
@export var value: Variant = true


func _apply(_ctx: ActionContext) -> void:
	GameState.set_flag(flag, value)
