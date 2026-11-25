class_name UnlockSafehouseEffect
extends Effect
## Unlocks player safehouse [member safehouse_id].

@export var safehouse_id: StringName


func _apply(_ctx: ActionContext) -> void:
	Missions.unlock_safehouse(safehouse_id)


func _describe(_ctx: ActionContext) -> String:
	var def := ContentDB.find_def(PlayerSafehouseDef.TYPE, safehouse_id)
	return "Safehouse: %s" % (def.label() if def != null else String(safehouse_id))
