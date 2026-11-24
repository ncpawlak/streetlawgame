class_name MeetPlugEffect
extends Effect
## Door action on a plug's meeting spot: marks the plug as met and opens the deal panel.

@export var plug_id: StringName


func describe(_ctx: ActionContext) -> String:
	return "Talk business"


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	if model != null:
		model.meet_plug(plug_id)
	var service := OperationsModel.service_node()
	if service != null:
		service.call("open_plug_panel", plug_id)
