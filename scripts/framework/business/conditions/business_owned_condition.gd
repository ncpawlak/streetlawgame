class_name BusinessOwnedCondition
extends Condition
## True when the player owns a business site. site_id empty = the site the action is about.

@export var site_id: StringName


func _evaluate(ctx: ActionContext) -> bool:
	return Businesses.is_owned(_site(ctx))


func _reason(ctx: ActionContext) -> String:
	var site := ContentDB.find_def(BusinessSiteDef.TYPE, _site(ctx)) as BusinessSiteDef
	return "You don't own %s" % (site.label() if site != null else String(_site(ctx)))


func _site(ctx: ActionContext) -> StringName:
	return site_id if site_id != &"" else BusinessSiteDef.site_id_from(ctx)
