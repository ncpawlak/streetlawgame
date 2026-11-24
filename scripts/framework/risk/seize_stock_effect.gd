class_name SeizeStockEffect
extends Effect
## Risk effect: takes a fraction of every item in the site's stash (police raid, rival robbery).

@export_range(0.0, 1.0) var fraction := 0.5
## Heat left on the site afterwards, as a fraction of the current heat.
@export_range(0.0, 1.0) var heat_after := 0.5


func _apply(ctx: ActionContext) -> void:
	var model := OperationsModel.from_context(ctx)
	var site_id := StringName(str(ctx.vars.get("site_id", "")))
	var stash := model.site_stash(site_id) if model != null else null
	if stash == null:
		return
	for item_id in stash.item_ids():
		var taken := ceili(stash.count(item_id) * fraction)
		stash.remove(item_id, taken)
	model.site_state(site_id).heat *= heat_after
