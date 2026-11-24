class_name ExitLocationEffect
extends Effect
## Leaves the location's interior (or whichever location the player is inside).


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location == null:
		location = Locations.current
	if location != null and ctx.actor is Node3D:
		location.exit(ctx.actor as Node3D)


func _describe(_ctx: ActionContext) -> String:
	return "Leave"
