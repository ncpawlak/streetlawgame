class_name PlugRelationshipEffect
extends Effect
## Changes the relationship with a plug (late payment, snitch scare, favour done).

@export var plug_id: StringName
@export var delta := -10.0


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	if model != null:
		model.change_relationship(plug_id, delta)
