class_name DemandPricingModel
extends PricingModel
## Price = value × district demand × (1 - saturation, floored) × seller skill bonus.

@export var skill_bonus := 0.05


func unit_price(item: ItemData, market: MarketProfile, saturation: float, seller_skill: int) -> int:
	var supply_factor := maxf(market.min_price_factor, 1.0 - saturation)
	var skill_factor := 1.0 + (seller_skill - 1) * skill_bonus
	return maxi(1, roundi(item.base_value * multiplier * market.demand_for(item) * supply_factor * skill_factor))
