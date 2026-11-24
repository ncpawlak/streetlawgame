class_name ArrestCrewEffect
extends Effect
## Risk effect: the crew member in ctx.vars.crew_id is arrested and pulled off their job.

## Seconds until they're released (0 = until something else frees them).
@export var jail_seconds := 180.0


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	var crew_id := StringName(str(ctx.vars.get("crew_id", "")))
	if model != null and not crew_id.is_empty():
		model.jail(crew_id, jail_seconds)
