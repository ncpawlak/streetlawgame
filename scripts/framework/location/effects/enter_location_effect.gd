class_name EnterLocationEffect
extends Effect
## Moves the actor into the location's interior (see InteriorStrategy).


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location != null and ctx.actor is Node3D:
		location.enter(ctx.actor as Node3D)


func _describe(_ctx: ActionContext) -> String:
	return "Enter"
