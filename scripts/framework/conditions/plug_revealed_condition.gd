class_name PlugRevealedCondition
extends Condition
## True once a plug has been revealed (its reveal_conditions passed). Gates the plug's meeting spot so
## players can't skip the supplier progression by finding the door early.

@export var plug_id: StringName


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	return model != null and model.is_plug_revealed(plug_id)


func _reason(_ctx: ActionContext) -> String:
	return "Nobody here knows you"
