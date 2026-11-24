class_name MarketProfile
extends ContentDef
## How a district's street market reacts to product. id &"default" applies to districts without
## their own profile; otherwise set district_id.

@export var district_id: StringName
## Item id or item category -> demand multiplier (1.0 = normal). Item ids win over categories.
@export var demand: Dictionary = {}
## Saturation added per unit sold; price drops as saturation rises.
@export var saturation_per_unit := 0.01
@export var saturation_recovery_per_minute := 0.2
## Prices never drop below this fraction from saturation.
@export var min_price_factor := 0.3


func demand_for(item: ItemData) -> float:
	if demand.has(item.id):
		return float(demand[item.id])
	return float(demand.get(item.category, 1.0))
