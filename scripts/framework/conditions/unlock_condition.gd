class_name UnlockCondition
extends Condition
## True when the player has an unlock id (granted by plugs, missions...), e.g. &"drug:coke".

@export var unlock_id: StringName


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	return model != null and model.has_unlock(unlock_id)


func _reason(_ctx: ActionContext) -> String:
	return "Locked (%s)" % unlock_id
