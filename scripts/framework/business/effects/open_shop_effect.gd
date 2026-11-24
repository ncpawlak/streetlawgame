class_name OpenShopEffect
extends Effect
## Opens the shop of a business site. site_id empty = the site the action is about.

@export var site_id: StringName


func _describe(_ctx: ActionContext) -> String:
	return "Shop"


func _apply(ctx: ActionContext) -> void:
	Businesses.open_shop(site_id if site_id != &"" else BusinessSiteDef.site_id_from(ctx), ctx.actor)
