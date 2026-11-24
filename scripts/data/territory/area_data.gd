class_name AreaData
extends Resource
## A region of the city made of several districts (data/areas/<id>.tres).
## Membership lives on [member DistrictData.area_id]; an area doesn't list its districts.

@export var id: StringName
@export var display_name := ""
@export var bonuses: Array[AreaBonusData] = []
## Passed along with [signal EventBus.area_captured] for story/mission hooks.
@export var story_beat: StringName
@export var sort_order := 0
