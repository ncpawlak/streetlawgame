class_name BusinessTypeDef
extends ContentDef
## A kind of business (corner store, gun store, chop shop...). Placed in the world as one or more
## [BusinessSiteDef]s. Lives in data/business_types/<id>.tres.

const TYPE := &"business_types"

## &"retail" (has a shop), &"service" or &"front".
@export var category: StringName = &"retail"
## Purchase price before the area tier multiplier (see Businesses.price_of).
@export var base_price := 1000
## Cash per income cycle before the area tier multiplier.
@export var base_income := 50
## Clout (0-100) granted to the site's district while the player owns the site.
@export_range(0, 100) var clout_value := 5
## Ambient crew that hang out in front of an owned site.
@export var hangout_crew_count := 2
## Shop stock (data/shop_items/<id>.tres). Empty = no shop.
@export var shop_item_ids: Array[StringName] = []
## Appearance service run at the counter: &"clothing" (clothing store), &"barber" or &"" (none).
## Opens the appearance panel priced at the site (see PlayerAppearance / OpenAppearanceEffect).
@export var appearance_service: StringName = &""
## Door, sign and map marker colour.
@export var color := Color(0.75, 0.6, 0.3)


func has_shop() -> bool:
	return not shop_item_ids.is_empty()


func validate() -> PackedStringArray:
	var issues := super()
	if base_price <= 0:
		issues.append("business type needs a positive base_price")
	if base_income < 0:
		issues.append("business type has negative base_income")
	if hangout_crew_count < 0:
		issues.append("business type has negative hangout_crew_count")
	for item_id in shop_item_ids:
		if not ContentDB.has_def(ShopItemDef.TYPE, item_id):
			issues.append("unknown shop item '%s'" % item_id)
	if not [&"", &"clothing", &"barber"].has(appearance_service):
		issues.append("unknown appearance_service '%s'" % appearance_service)
	return issues
