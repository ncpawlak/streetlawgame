class_name TakeOutEffect
extends Effect
## Immediately marks the location taken out (applies its cleared_effects). Use for "torch the place"
## style actions; clearing hostiles inside triggers the same thing automatically.


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location != null:
		location.take_out(ctx.actor)


func _describe(_ctx: ActionContext) -> String:
	return "Take out"
