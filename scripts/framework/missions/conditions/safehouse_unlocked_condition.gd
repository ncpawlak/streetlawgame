class_name SafehouseUnlockedCondition
extends Condition
## True when player safehouse [member safehouse_id] is unlocked.

@export var safehouse_id: StringName


func _evaluate(_ctx: ActionContext) -> bool:
	return Missions.is_safehouse_unlocked(safehouse_id)


func _reason(_ctx: ActionContext) -> String:
	return "Locked"
