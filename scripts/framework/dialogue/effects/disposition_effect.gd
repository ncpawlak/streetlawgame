class_name DispositionEffect
extends Effect
## Shifts how the occupant feels about the player (stored per location, per role; clamped to -1..1).

@export var fear := 0.0
@export var favor := 0.0


func _apply(ctx: ActionContext) -> void:
	var occupant := ctx.occupant as Occupant
	if occupant == null or occupant.location == null:
		return
	var mood := occupant.location.state.disposition(occupant.role())
	mood["fear"] = clampf(float(mood.get("fear", 0.0)) + fear, -1.0, 1.0)
	mood["favor"] = clampf(float(mood.get("favor", 0.0)) + favor, -1.0, 1.0)


func _describe(_ctx: ActionContext) -> String:
	return "Fear %+.1f, favour %+.1f" % [fear, favor]