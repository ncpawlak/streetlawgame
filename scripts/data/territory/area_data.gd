class_name AreaData
extends ContentDef
## A region of the city made of several districts (data/areas/<id>.tres).
## Membership lives on [member DistrictData.area_id]; an area doesn't list its districts.

@export var bonuses: Array[AreaBonusData] = []
## Passed along with [signal EventBus.area_captured] for story/mission hooks.
@export var story_beat: StringName
@export var sort_order := 0
## Economy tier 1-5 (business prices and income scale with it, see Businesses.TIER_MULTIPLIERS).
@export_range(1, 5) var tier := 1
