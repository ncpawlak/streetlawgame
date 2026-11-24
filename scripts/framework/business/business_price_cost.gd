class_name BusinessPriceCost
extends Cost
## Cash cost of buying a business site, priced live by Businesses.price_of (base x area tier).
## site_id empty = the site the action is about.

@export var site_id: StringName


func _can_pay(ctx: ActionContext) -> bool:
	return GameState.cash >= _price(ctx)


func _pay(ctx: ActionContext) -> void:
	GameState.spend_cash(_price(ctx))


func _describe(ctx: ActionContext) -> String:
	return "$%d" % _price(ctx)


func _price(ctx: ActionContext) -> int:
	return Businesses.price_of(site_id if site_id != &"" else BusinessSiteDef.site_id_from(ctx))
