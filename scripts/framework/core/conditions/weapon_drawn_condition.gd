class_name WeaponDrawnCondition
extends Condition
## The actor is holding a real weapon (not one of [member unarmed_ids]).

@export var unarmed_ids: Array[StringName] = [&"fists"]


func _evaluate(ctx: ActionContext) -> bool:
	if ctx.actor == null or not "weapons" in ctx.actor:
		return false
	var inventory := ctx.actor.get("weapons") as WeaponInventory
	if inventory == null or inventory.current() == null:
		return false
	return not unarmed_ids.has(inventory.current().data.id)


func _reason(_ctx: ActionContext) -> String:
	return "Draw a weapon"
