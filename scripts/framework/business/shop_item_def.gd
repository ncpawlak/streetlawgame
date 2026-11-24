class_name ShopItemDef
extends ContentDef
## Something a business shop sells. Lives in data/shop_items/<id>.tres. The price paid is
## base_price x the area tier multiplier, halved at a site the player owns (Businesses.shop_price).

const TYPE := &"shop_items"

@export var base_price := 10
## Applied to the buyer when bought (GiveWeaponEffect, HealEffect...).
@export var effects: Array[Effect] = []


func validate() -> PackedStringArray:
	var issues := super()
	if base_price < 0:
		issues.append("shop item has a negative base_price")
	if effects.is_empty() or effects.has(null):
		issues.append("shop item needs at least one effect and no empty slots")
	return issues
