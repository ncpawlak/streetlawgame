class_name UnlockCondition
extends Condition
## True when the player has an unlock id (granted by plugs, missions...), e.g. &"drug:coke".

@export var unlock_id: StringName
@export var failure_text := "Locked"


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	return model != null and model.has_unlock(unlock_id)


func _reason(_ctx: ActionContext) -> String:
	return failure_text
