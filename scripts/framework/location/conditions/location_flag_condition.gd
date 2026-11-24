class_name LocationFlagCondition
extends Condition
## Met when the location's persistent flag [member flag] equals [member value] (unset counts as null).
## Use for per-building one-offs ("already recruited here"); GameState flags are global.

@export var flag: StringName
@export var value: Variant = true


func _evaluate(ctx: ActionContext) -> bool:
	var location := ctx.location as Location
	return location != null and location.state.flags.get(flag) == value


func _reason(_ctx: ActionContext) -> String:
	return "Not now"