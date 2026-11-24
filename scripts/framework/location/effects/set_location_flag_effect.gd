class_name SetLocationFlagEffect
extends Effect
## Sets a persistent flag on the location (saved with its LocationState).

@export var flag: StringName
@export var value: Variant = true


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location != null:
		location.state.flags[flag] = value