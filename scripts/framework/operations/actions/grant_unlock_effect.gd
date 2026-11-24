class_name GrantUnlockEffect
extends Effect
## Grants an operations unlock id (missions, story beats, alternative plug flows).

@export var unlock_id: StringName


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	if model != null:
		model.grant_unlock(unlock_id)
