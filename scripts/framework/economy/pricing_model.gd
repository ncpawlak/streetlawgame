class_name PricingModel
extends Resource
## Strategy for what one unit sells for. The base is a flat multiple of the item's value
## (fences, fixed-price buyers); subclass for demand curves, events, etc.

@export var multiplier := 1.0


func unit_price(item: ItemData, _market: MarketProfile, _saturation: float, _seller_skill: int) -> int:
	return maxi(0, roundi(item.base_value * multiplier))
