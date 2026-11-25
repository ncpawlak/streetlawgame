class_name MissionItemCondition
extends Condition
## True when Missions.items holds at least [member count] of [member item_id].

@export var item_id: StringName
@export var count := 1


func _evaluate(_ctx: ActionContext) -> bool:
	return Missions.items.has(item_id, count)


func _reason(_ctx: ActionContext) -> String:
	return "Need %s" % String(item_id).capitalize()
