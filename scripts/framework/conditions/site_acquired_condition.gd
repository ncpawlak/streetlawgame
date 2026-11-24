class_name SiteAcquiredCondition
extends Condition
## True when the player owns an operations site. site_id empty = ctx.vars.site_id.

@export var site_id: StringName


func _evaluate(ctx: ActionContext) -> bool:
	var model := OperationsModel.from_context(ctx)
	return model != null and model.is_site_acquired(_site(ctx))


func _reason(_ctx: ActionContext) -> String:
	return "You don't own this place"


func _site(ctx: ActionContext) -> StringName:
	return site_id if not site_id.is_empty() else StringName(str(ctx.vars.get("site_id", "")))
