class_name BuyBusinessEffect
extends Effect
## Hands a business site to the player (Businesses.acquire). site_id empty = the site the action is
## about. Pair with a CashCost; Businesses.purchase_action builds the standard version.

@export var site_id: StringName


func _describe(_ctx: ActionContext) -> String:
	return "Buy business"


func _apply(ctx: ActionContext) -> void:
	var id := site_id if site_id != &"" else BusinessSiteDef.site_id_from(ctx)
	if Businesses.acquire(id, &"purchase"):
		EventBus.notify.emit("You bought %s" % Businesses.site(id).label())
