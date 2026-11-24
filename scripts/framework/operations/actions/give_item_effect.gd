class_name GiveItemEffect
extends Effect
## Puts items into a site stash (as much as fits). site_id empty = ctx.vars.site_id.

@export var item_id: StringName
@export var amount := 1
@export var site_id: StringName


func _describe(_ctx: ActionContext) -> String:
	return "+%d %s" % [amount, item_id]


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	var target := site_id if not site_id.is_empty() else StringName(str(ctx.vars.get("site_id", "")))
	if model != null and model.site_stash(target) != null:
		model.site_stash(target).add(item_id, amount)
