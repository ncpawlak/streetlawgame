class_name ItemCost
extends Cost
## Pays items out of a site stash. site_id empty = ctx.vars.site_id.

@export var item_id: StringName
@export var amount := 1
@export var site_id: StringName


func _describe(ctx: ActionContext) -> String:
	var model := OperationsModel.from_context(ctx)
	var item := model.item(item_id) if model != null else null
	return "%d× %s" % [amount, item.display_name if item != null else String(item_id)]


func _can_pay(ctx: ActionContext) -> bool:
	var stash := _stash(ctx)
	return stash != null and stash.count(item_id) >= amount


func _pay(ctx: ActionContext) -> void:
	var stash := _stash(ctx)
	if stash != null:
		stash.remove(item_id, amount)


func _stash(ctx: ActionContext) -> Inventory:
	var model := OperationsModel.from_context(ctx)
	var target := site_id if not site_id.is_empty() else StringName(str(ctx.vars.get("site_id", "")))
	return model.site_stash(target) if model != null else null
