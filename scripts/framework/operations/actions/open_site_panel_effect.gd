class_name OpenSitePanelEffect
extends Effect
## Door action on a trap house / lab / business: opens its management panel.

@export var site_id: StringName


func _describe(_ctx: ActionContext) -> String:
	return "Manage"


func _apply(_ctx: ActionContext) -> void:
	var service := OperationsModel.service_node()
	if service != null:
		service.call("open_site_panel", site_id)
