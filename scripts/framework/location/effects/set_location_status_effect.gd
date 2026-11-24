class_name SetLocationStatusEffect
extends Effect
## Sets the location's status, optionally reverting to open after [member reset_after] seconds.

@export var status := &"robbed"
@export var reset_after := 0.0


func _apply(ctx: ActionContext) -> void:
	var location := ctx.location as Location
	if location != null:
		Locations.set_status(location, status, reset_after)


func _describe(_ctx: ActionContext) -> String:
	return "Status -> %s" % status
